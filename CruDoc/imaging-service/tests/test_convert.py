import json
import os
from io import BytesIO
from pathlib import Path
import numpy as np
import pytest
import pydicom
from pydicom.dataset import Dataset, FileMetaDataset
from pydicom.uid import ExplicitVRLittleEndian

from convert import build_view, decode_full, tilepart_ends

CODEC = os.environ.get("VIEW_CODEC", "htj2k")

def make_synthetic_dicom(
    rows: int,
    cols: int,
    bits_stored: int = 16,
    signed: bool = False,
    frames: int = 1,
    samples_per_pixel: int = 1,
    photometric: str = "MONOCHROME2",
    has_pixels: bool = True,
    min_val: int = 0
) -> tuple[bytes, np.ndarray | None]:
    ds = Dataset()
    ds.file_meta = FileMetaDataset()
    ds.file_meta.TransferSyntaxUID = ExplicitVRLittleEndian
    ds.file_meta.MediaStorageSOPClassUID = "1.2.840.10008.5.1.4.1.1.7"
    ds.file_meta.MediaStorageSOPInstanceUID = "1.2.3.4.5"

    ds.SOPClassUID = ds.file_meta.MediaStorageSOPClassUID
    ds.SOPInstanceUID = ds.file_meta.MediaStorageSOPInstanceUID
    ds.Modality = "OT"
    ds.Rows = rows
    ds.Columns = cols
    ds.SamplesPerPixel = samples_per_pixel
    ds.PhotometricInterpretation = photometric
    ds.BitsAllocated = 32 if bits_stored > 16 else (16 if bits_stored > 8 else 8)
    ds.BitsStored = bits_stored
    ds.HighBit = bits_stored - 1
    ds.PixelRepresentation = 1 if signed else 0
    if frames > 1:
        ds.NumberOfFrames = frames

    arr = None
    if has_pixels:
        if bits_stored > 16:
            dtype = "<i4" if signed else "<u4"
        elif bits_stored > 8:
            dtype = "<i2" if signed else "<u2"
        else:
            dtype = "<i1" if signed else "<u1"

        shape = (frames, rows, cols) if frames > 1 else (rows, cols)
        if samples_per_pixel > 1:
            shape = shape + (samples_per_pixel,)

        num_elements = int(np.prod(shape))
        if signed:
            max_val = (1 << (bits_stored - 1)) - 1
            span = max_val - min_val + 1
            raw_seq = (np.arange(num_elements, dtype=np.int64) % span) + min_val
        else:
            max_val = (1 << bits_stored) - 1
            span = max_val - min_val + 1
            raw_seq = (np.arange(num_elements, dtype=np.int64) % span) + min_val

        arr = raw_seq.astype(dtype).reshape(shape)
        ds.PixelData = arr.tobytes()

    bio = BytesIO()
    pydicom.dcmwrite(bio, ds, enforce_file_format=True)
    return bio.getvalue(), arr

def test_16bit_unsigned_513x387():
    dicom_bytes, arr = make_synthetic_dicom(387, 513, bits_stored=16, signed=False)
    res = build_view(dicom_bytes, codec=CODEC)
    assert res.status == "ready"
    assert res.reason == ""
    assert len(res.frames) == 1
    assert res.meta["width"] == 513
    assert res.meta["height"] == 387
    assert res.meta["bitsStored"] == 16
    assert res.meta["signed"] is False
    assert res.meta["codec"] == CODEC

    f0 = res.frames[0]
    assert f0.preview_end < f0.total
    decoded = decode_full(f0.data, 513, 387, 16, False)
    assert np.array_equal(arr, decoded)

def test_12bit_unsigned():
    dicom_bytes, arr = make_synthetic_dicom(200, 200, bits_stored=12, signed=False)
    res = build_view(dicom_bytes, codec=CODEC)
    assert res.status == "ready"
    assert len(res.frames) == 1
    f0 = res.frames[0]
    decoded = decode_full(f0.data, 200, 200, 12, False)
    assert np.array_equal(arr, decoded)

def test_16bit_signed_negative():
    dicom_bytes, arr = make_synthetic_dicom(200, 200, bits_stored=16, signed=True, min_val=-2000)
    assert np.any(arr < 0)
    res = build_view(dicom_bytes, codec=CODEC)
    assert res.status == "ready"
    assert len(res.frames) == 1
    f0 = res.frames[0]
    decoded = decode_full(f0.data, 200, 200, 16, True)
    assert np.array_equal(arr, decoded)

def test_8bit():
    dicom_bytes, arr = make_synthetic_dicom(200, 200, bits_stored=8, signed=False)
    res = build_view(dicom_bytes, codec=CODEC)
    assert res.status == "ready"
    assert len(res.frames) == 1
    f0 = res.frames[0]
    decoded = decode_full(f0.data, 200, 200, 8, False)
    assert np.array_equal(arr, decoded)

def test_3_frame():
    dicom_bytes, arr = make_synthetic_dicom(150, 150, bits_stored=16, signed=False, frames=3)
    res = build_view(dicom_bytes, codec=CODEC)
    assert res.status == "ready"
    assert res.meta["frames"] == 3
    assert len(res.frames) == 3
    for f in range(3):
        decoded = decode_full(res.frames[f].data, 150, 150, 16, False)
        assert np.array_equal(arr[f], decoded)

def test_rgb_skipped():
    dicom_bytes, _ = make_synthetic_dicom(100, 100, bits_stored=8, samples_per_pixel=3, photometric="RGB")
    res = build_view(dicom_bytes, codec=CODEC)
    assert res.status == "skipped"
    assert res.reason == "colour"
    assert len(res.frames) == 0

def test_no_pixel_data_skipped():
    dicom_bytes, _ = make_synthetic_dicom(100, 100, has_pixels=False)
    res = build_view(dicom_bytes, codec=CODEC)
    assert res.status == "skipped"
    assert res.reason == "no-pixels"
    assert len(res.frames) == 0

def test_bits_greater_than_16_skipped():
    dicom_bytes, _ = make_synthetic_dicom(100, 100, bits_stored=24)
    res = build_view(dicom_bytes, codec=CODEC)
    assert res.status == "skipped"
    assert res.reason == "bits>16"
    assert len(res.frames) == 0

def test_synthetic_fixtures_tileparts():
    fixtures_dir = Path(__file__).resolve().parent.parent.parent / "packages" / "crudoc_j2k" / "test" / "fixtures"
    with open(fixtures_dir / "synthetic.json", "r") as f:
        meta = json.load(f)

    # Check synthetic_a.j2c
    with open(fixtures_dir / "synthetic_a.j2c", "rb") as f:
        cs_a = f.read()
    ends_a = tilepart_ends(cs_a)
    assert len(ends_a) == 6
    assert ends_a[-2] == meta["previewEnd_a"]

    # Check synthetic_b.j2k
    with open(fixtures_dir / "synthetic_b.j2k", "rb") as f:
        cs_b = f.read()
    ends_b = tilepart_ends(cs_b)
    assert len(ends_b) == 6
    assert ends_b[-2] == meta["previewEnd_b"]