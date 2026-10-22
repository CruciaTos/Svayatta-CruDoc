"""Read the text on a prescription, medicine strip or bill with PaddleOCR 3.x.

By hand: prints each line found and saves the text to paddle_output.txt
next to this script.

    python prescription_ocr.py prescription_images\\Prescription2.jpg

For the app (Inventory > Scan on desktop): --json prints one line of
JSON, {"lines": [{"text": ..., "score": ...}]} or {"error": ...}, and
saves nothing.
"""

import argparse
import contextlib
import json
import os
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
SAMPLES = HERE / "prescription_images"
OUTPUT = HERE / "paddle_output.txt"
FILE_TYPES = {".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff", ".webp", ".pdf"}
# Longest side, in pixels, that images are shrunk to before reading.
MAX_SIDE = 1600

# Models go next to the venv's real folder (.venv here may be a link to
# another drive), not the user folder: D:\crudoc_paddle\models for
# .venv -> D:\crudoc_paddle\venv. Set PADDLE_PDX_CACHE_HOME to override.
if sys.prefix != sys.base_prefix:
    os.environ.setdefault(
        "PADDLE_PDX_CACHE_HOME",
        str(Path(os.path.realpath(sys.prefix)).parent / "models"),
    )
# The models are already downloaded; skip the slow check of the hosts.
os.environ.setdefault("PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK", "True")


def how_to_run() -> str:
    return (
        "No image given.\n\n"
        f"Put a prescription photo or scan in:\n  {SAMPLES}\n\n"
        "Then run (from the repo root, PowerShell):\n"
        "  CruDoc\\tool\\paddle_ocr_test\\.venv\\Scripts\\python.exe "
        "CruDoc\\tool\\paddle_ocr_test\\prescription_ocr.py "
        "CruDoc\\tool\\paddle_ocr_test\\prescription_images\\Prescription2.jpg"
    )


def check_image(path: Path) -> str | None:
    """The problem with [path], or None when it can be read."""
    if not path.exists():
        return f"File not found: {path}"
    if not path.is_file():
        return f"Not a file: {path}"
    if path.suffix.lower() not in FILE_TYPES:
        allowed = ", ".join(sorted(FILE_TYPES))
        return f"Unsupported file type '{path.suffix}'. Use one of: {allowed}"
    return None


def load_ocr(textline_orientation: bool = True, size: str = "medium"):
    """The OCR pipeline. The first run downloads the models.

    [textline_orientation] checks every line for upside-down text: useful
    on handwriting, slow on a bill with hundreds of cells. [size] is the
    PP-OCRv6 model: "medium" reads handwriting best; "small" reads a
    printed bill as well, 4x faster (12 s against 47 s here)."""
    from paddleocr import PaddleOCR

    return PaddleOCR(
        text_detection_model_name=f"PP-OCRv6_{size}_det",
        text_recognition_model_name=f"PP-OCRv6_{size}_rec",
        # Phone photos are often sideways: turn the page upright first.
        use_doc_orientation_classify=True,
        # Straightening curled pages is slow and rarely needed for a slip.
        use_doc_unwarping=False,
        use_textline_orientation=textline_orientation,
        # Paddle's oneDNN path crashes on this Windows setup
        # ("ConvertPirAttribute2RuntimeAttribute not support"); the plain
        # CPU path is slower but works.
        enable_mkldnn=False,
    )


def load_image(path: Path):
    """[path] as a BGR array no bigger than MAX_SIDE, or the path itself
    for a PDF. A 4000 px phone photo takes minutes on a CPU and reads no
    better than a 1600 px one."""
    if path.suffix.lower() == ".pdf":
        return str(path)
    import cv2
    import numpy as np

    # imdecode, not imread: imread can't open paths with non-ASCII letters.
    image = cv2.imdecode(np.fromfile(str(path), dtype=np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise RuntimeError(f"Couldn't open the image: {path.name}")
    height, width = image.shape[:2]
    scale = MAX_SIDE / max(height, width)
    if scale < 1:
        size = (round(width * scale), round(height * scale))
        image = cv2.resize(image, size, interpolation=cv2.INTER_AREA)
    return image


def read_lines(ocr, path: Path) -> list[tuple[str, float]]:
    """(text, confidence) for each line, top to bottom, across pages."""
    lines = []
    for page in ocr.predict(load_image(path)):
        for text, score in zip(page["rec_texts"], page["rec_scores"]):
            if text.strip():
                lines.append((text.strip(), float(score)))
    return lines


def run(path: Path) -> list[tuple[str, float]]:
    """Reads [path]; raises RuntimeError with a readable reason."""
    try:
        ocr = load_ocr()
    except ImportError as e:
        raise RuntimeError(
            f"PaddleOCR isn't installed in this Python ({sys.executable}). "
            "Use CruDoc\\tool\\paddle_ocr_test\\.venv\\Scripts\\python.exe. "
            f"Details: {e}"
        ) from e
    try:
        return read_lines(ocr, path)
    except RuntimeError:
        raise
    except Exception as e:  # model download, bad image, Paddle runtime
        raise RuntimeError(f"OCR failed: {type(e).__name__}: {e}") from e


def main_json(image: str | None) -> int:
    """One line of JSON on stdout; Paddle's own messages go to stderr."""

    def reply(payload: dict) -> None:
        sys.__stdout__.write(json.dumps(payload) + "\n")
        sys.__stdout__.flush()

    if not image:
        reply({"error": "No image given."})
        return 2
    path = Path(image).expanduser().resolve()
    problem = check_image(path)
    if problem:
        reply({"error": problem})
        return 1
    try:
        with contextlib.redirect_stdout(sys.stderr):
            lines = run(path)
    except RuntimeError as e:
        reply({"error": str(e)})
        return 1
    reply({"lines": [{"text": t, "score": round(s, 3)} for t, s in lines]})
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run PaddleOCR on a prescription, medicine strip or bill."
    )
    parser.add_argument("image", nargs="?", help="path to the image or PDF")
    parser.add_argument(
        "--json",
        action="store_true",
        help="print the lines as JSON (for the app) and save nothing",
    )
    args = parser.parse_args()

    if args.json:
        return main_json(args.image)

    if not args.image:
        print(how_to_run())
        return 2

    path = Path(args.image).expanduser().resolve()
    problem = check_image(path)
    if problem:
        print(f"Error: {problem}", file=sys.stderr)
        return 1

    started = time.perf_counter()
    try:
        lines = run(path)
    except RuntimeError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    took = time.perf_counter() - started

    text = "\n".join(t for t, _ in lines)
    try:
        OUTPUT.write_text(text + "\n" if text else "", encoding="utf-8")
    except OSError as e:
        print(f"Error: couldn't save {OUTPUT}: {e}", file=sys.stderr)
        return 1

    print(f"--- {path.name}: {len(lines)} lines ---")
    for t, score in lines:
        flag = "  (low confidence)" if score < 0.6 else ""
        print(f"{t}{flag}")
    print("---")
    if lines:
        average = sum(s for _, s in lines) / len(lines)
        print(f"Average confidence: {average:.2f}")
    else:
        print("No text found. Try a sharper, well-lit, straight-on photo.")
    print(f"Took {took:.1f}s (loading the models and reading)")
    print(f"Saved to {OUTPUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
