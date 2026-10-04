from dataclasses import dataclass
import hashlib
from io import BytesIO
import os
import subprocess
import tempfile
import numpy as np
import pydicom

@dataclass
class FrameOut:
    data: bytes          # the codestream
    total: int           # len(data)
    preview_end: int     # tilepart_ends(data)[-2]
    sha256: str          # hex of data

@dataclass
class ViewResult:
    status: str          # 'ready' | 'skipped'
    reason: str
    meta: dict           # width, height, frames, bitsStored, signed, slope, intercept,
                         # windowCenter, windowWidth, photometric, codec
    frames: list[FrameOut]

def tilepart_ends(cs: bytes) -> list[int]:
    """Byte offset just after each tile-part. The last tile-part is the
    full-resolution one; ends[-2] is previewEnd."""
    if cs[:2] != b'\xff\x4f':
        raise ValueError('not a JPEG 2000 codestream')
    i = 2
    while cs[i:i + 2] != b'\xff\x90':          # walk main-header segments to first SOT
        seg_len = int.from_bytes(cs[i + 2:i + 4], 'big')
        i += 2 + seg_len
    ends = []
    while cs[i:i + 2] == b'\xff\x90':          # SOT: FF90 Lsot(2) Isot(2) Psot(4) TPsot TNsot
        psot = int.from_bytes(cs[i + 6:i + 10], 'big')
        if psot == 0:                         # last tile-part runs to the end marker
            ends.append(len(cs) - 2)
            break
        i += psot
        ends.append(i)
    return ends

def encode_frame(pixels: np.ndarray, bits_stored: int, signed: bool, codec: str) -> bytes:
    h, w = pixels.shape
    dtype_str = f"<i{2 if bits_stored > 8 else 1}" if signed else f"<u{2 if bits_stored > 8 else 1}"
    raw_data = pixels.astype(dtype_str).tobytes()

    with tempfile.TemporaryDirectory() as tmpdir:
        if codec == 'htj2k':
            raw_path = os.path.join(tmpdir, "input.raw")
            out_path = os.path.join(tmpdir, "out.j2c")
            with open(raw_path, "wb") as f:
                f.write(raw_data)
            cmd = [
                "ojph_compress",
                "-i", raw_path,
                "-o", out_path,
                "-reversible", "true",
                "-num_decomps", "5",
                "-prog_order", "RPCL",
                "-tileparts", "R",
                "-tlm_marker", "true",
                "-dims", f"{{{w},{h}}}",
                "-num_comps", "1",
                "-bit_depth", str(bits_stored),
                "-signed", "true" if signed else "false",
                "-downsamp", "{1,1}"
            ]
            subprocess.run(cmd, check=True, capture_output=True)
            with open(out_path, "rb") as f:
                return f.read()
        elif codec == 'j2k':
            raw_path = os.path.join(tmpdir, "input.rawl")
            out_path = os.path.join(tmpdir, "out.j2k")
            with open(raw_path, "wb") as f:
                f.write(raw_data)
            cmd = [
                "opj_compress",
                "-i", raw_path,
                "-o", out_path,
                "-F", f"{w},{h},1,{bits_stored},{'s' if signed else 'u'}",
                "-p", "RPCL",
                "-TP", "R",
                "-n", "6"
            ]
            subprocess.run(cmd, check=True, capture_output=True)
            with open(out_path, "rb") as f:
                return f.read()
        else:
            raise ValueError(f"Unsupported codec: {codec}")

def decode_full(cs: bytes, width: int, height: int, bits_stored: int, signed: bool) -> np.ndarray:
    with tempfile.TemporaryDirectory() as tmpdir:
        in_path = os.path.join(tmpdir, "in.j2k")
        out_path = os.path.join(tmpdir, "out.rawl")
        with open(in_path, "wb") as f:
            f.write(cs)
        cmd = ["opj_decompress", "-i", in_path, "-o", out_path]
        subprocess.run(cmd, check=True, capture_output=True)
        dtype_str = f"<i{2 if bits_stored > 8 else 1}" if signed else f"<u{2 if bits_stored > 8 else 1}"
        with open(out_path, "rb") as f:
            data = f.read()
        return np.frombuffer(data, dtype=dtype_str).reshape((height, width))

def build_view(dicom_bytes: bytes, codec: str) -> ViewResult:
    ds = pydicom.dcmread(BytesIO(dicom_bytes))

    # 1. No PixelData
    if not hasattr(ds, "PixelData") or ds.PixelData is None or len(ds.PixelData) == 0:
        return ViewResult(status="skipped", reason="no-pixels", meta={}, frames=[])

    # 2. SamplesPerPixel != 1 or colour PhotometricInterpretation
    samples_per_pixel = getattr(ds, "SamplesPerPixel", 1)
    photometric = str(getattr(ds, "PhotometricInterpretation", "MONOCHROME2"))
    if samples_per_pixel != 1 or photometric in ("RGB", "YBR_FULL", "YBR_FULL_422", "PALETTE COLOR"):
        return ViewResult(status="skipped", reason="colour", meta={}, frames=[])

    # 3. NumberOfFrames > 1000
    raw_frames = getattr(ds, "NumberOfFrames", 1)
    num_frames = 1 if raw_frames is None else int(raw_frames)
    if num_frames > 1000:
        return ViewResult(status="skipped", reason="too-many-frames", meta={}, frames=[])

    # 4. width * height > 100_000_000
    w = int(ds.Columns)
    h = int(ds.Rows)
    if w * h > 100_000_000:
        return ViewResult(status="skipped", reason="too-large", meta={}, frames=[])

    bits_stored = int(getattr(ds, "BitsStored", 16))
    if bits_stored > 16:
        return ViewResult(status="skipped", reason="bits>16", meta={}, frames=[])

    signed = (getattr(ds, "PixelRepresentation", 0) == 1)
    slope = float(getattr(ds, "RescaleSlope", 1.0))
    intercept = float(getattr(ds, "RescaleIntercept", 0.0))

    wc = getattr(ds, "WindowCenter", None)
    ww = getattr(ds, "WindowWidth", None)
    if wc is not None:
        if isinstance(wc, (list, pydicom.multival.MultiValue)):
            wc = float(wc[0])
        else:
            wc = float(wc)
    if ww is not None:
        if isinstance(ww, (list, pydicom.multival.MultiValue)):
            ww = float(ww[0])
        else:
            ww = float(ww)

    meta = {
        "width": w,
        "height": h,
        "frames": num_frames,
        "bitsStored": bits_stored,
        "signed": signed,
        "slope": slope,
        "intercept": intercept,
        "windowCenter": wc,
        "windowWidth": ww,
        "photometric": photometric,
        "codec": codec,
    }

    arr = ds.pixel_array
    if num_frames > 1 and arr.shape[0] != num_frames:
        raise ValueError(f"NumberOfFrames is {num_frames} but pixel_array leading dim is {arr.shape[0]}")
    elif num_frames == 1 and arr.ndim == 3 and arr.shape[-1] in (3, 4):
        return ViewResult(status="skipped", reason="colour", meta={}, frames=[])

    frames_out = []
    for f in range(num_frames):
        frame_pixels = arr[f] if num_frames > 1 else arr
        cs = encode_frame(frame_pixels, bits_stored, signed, codec)
        ends = tilepart_ends(cs)
        if len(ends) != 6:
            raise ValueError(f"Expected 6 tile-parts, got {len(ends)}")
        decoded = decode_full(cs, w, h, bits_stored, signed)
        if not np.array_equal(frame_pixels, decoded):
            raise ValueError(f"Decoded pixels for frame {f} do not match input pixels")
        preview_end = ends[-2]
        sha = hashlib.sha256(cs).hexdigest()
        frames_out.append(FrameOut(data=cs, total=len(cs), preview_end=preview_end, sha256=sha))

    return ViewResult(status="ready", reason="", meta=meta, frames=frames_out)