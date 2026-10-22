"""Read a supplier's purchase bill: every medicine line with its pack,
batch, expiry, quantity, free quantity, MRP, rate, discount, GST and
amount, and the bill's subtotal, tax and grand total.

Sarvam Vision (api.sarvam.ai, document extract) reads it first. Without a
key, without internet, or when Sarvam fails, PaddleOCR reads it on this
computer and the table is rebuilt from where the text sits.

    python bill_scan.py bill.jpg            a table, for testing by hand
    python bill_scan.py bill.jpg --offline  PaddleOCR only
    python bill_scan.py bill.jpg --json     for the app (Inventory > Scan)

--json prints one line:
    {"source": "sarvam" | "paddle", "note": why Paddle was used or null,
     "supplier", "invoiceNumber", "invoiceDate",
     "subtotal", "taxAmount", "taxPercent", "grandTotal", "amountsIncludeTax",
     "items": [{"name", "pack", "batch", "expiry", "quantity",
                "quantityUnit", "freeQuantity", "mrp", "rate",
                "discountPercent", "taxPercent", "amount"}],
     "lines": [the text, row by row; PaddleOCR only]}
or {"error": "..."}. Numbers the bill doesn't show are null.

The Sarvam key is SARVAM_API_KEY from the environment, CruDoc/.env.local
or CruDoc/tool/voice_server/.env.
"""

import argparse
import contextlib
import json
import math
import os
import re
import sys
import time
from pathlib import Path

# Sets the model folder defaults; Paddle itself loads only when needed.
from prescription_ocr import FILE_TYPES, check_image, load_image, load_ocr

HERE = Path(__file__).resolve().parent
CRUDOC = HERE.parents[1]
SARVAM_JOB = "https://api.sarvam.ai/doc-ai/v1/job"
# Sarvam reads a bill in about 10 s; past this, read it here instead.
SARVAM_DEADLINE = 60
UPLOAD_SIDE = 2400

ITEM_FIELDS = {
    "name": ("string", "Product name with strength and form exactly as printed, e.g. DOLO 650 TAB"),
    "pack": ("string", "Pack size as printed, e.g. 15'S, 1x10, 100ML"),
    "batch": ("string", "Batch number"),
    "expiry": ("string", "Expiry date as printed, e.g. 03/28"),
    "quantity": ("number", "Billed quantity, in packs"),
    "quantityUnit": ("string", "Unit printed with the quantity, e.g. TBS, STRIP, BTL, PKG, BOX; empty if none"),
    "freeQuantity": ("number", "Free or bonus quantity, 0 if none"),
    "mrp": ("number", "MRP of one pack"),
    "rate": ("number", "Purchase rate of one pack, before discount and tax"),
    "discountPercent": ("number", "Discount on the line in percent (Disc %), 0 if none"),
    "taxPercent": (
        "number",
        "GST on the line in percent (CGST + SGST, or IGST), only when the item table has a GST column",
    ),
    "amount": ("number", "The line's amount column exactly as printed (often the taxable value after discount)"),
}
NUMBER_FIELDS = {k for k, (t, _) in ITEM_FIELDS.items() if t == "number"}

BILL_FIELDS = {
    "supplier": ("string", "Name of the distributor or wholesaler who issued the bill (the seller, not the buyer)"),
    "invoiceNumber": ("string", "Invoice or bill number"),
    "invoiceDate": ("string", "Invoice date exactly as printed"),
    "subtotal": ("number", "Total taxable value of all items, after discounts and before GST"),
    "taxAmount": ("number", "Total GST charged on the bill (CGST + SGST, or IGST)"),
    "taxPercent": ("number", "GST rate in percent when one rate covers the whole bill (CGST + SGST, or IGST)"),
    "grandTotal": ("number", "Final amount payable for the bill, including GST and round-off"),
    "amountsIncludeTax": (
        "boolean",
        "True when the item rates and amounts already include GST (e.g. a chemist's retail cash memo"
        " whose item values add up to the amount payable); false when GST is added on top of them",
    ),
}


def clean_bill_field(kind: str, value):
    if kind == "number":
        return to_number(value)
    if kind == "boolean":
        if isinstance(value, bool):
            return value
        text = str(value).strip().lower()
        return True if text == "true" else False if text == "false" else None
    return clean_text(value)

SCHEMA = {
    "type": "object",
    "properties": {
        **{k: {"type": t, "description": d} for k, (t, d) in BILL_FIELDS.items()},
        "items": {
            "type": "array",
            "description": "Every product line in the bill's item table, in order. Skip totals, taxes and discounts.",
            "items": {
                "type": "object",
                "properties": {
                    k: {"type": t, "description": d} for k, (t, d) in ITEM_FIELDS.items()
                },
            },
        },
    },
}


class SarvamUnavailable(Exception):
    """Sarvam can't read this bill now; the reason is fit to show."""


# ─── Sarvam Vision ────────────────────────────────────────────────────────


def sarvam_key() -> str | None:
    key = os.environ.get("SARVAM_API_KEY", "").strip()
    if key:
        return key
    for env in (CRUDOC / ".env.local", CRUDOC / "tool" / "voice_server" / ".env"):
        try:
            for line in env.read_text(encoding="utf-8").splitlines():
                name, _, value = line.partition("=")
                if name.strip() == "SARVAM_API_KEY" and value.strip():
                    return value.strip().strip("'\"")
        except OSError:
            continue
    return None


def upload_bytes(path: Path) -> tuple[str, bytes, str]:
    """(filename, bytes, type) to send. Images go as JPEG no bigger than
    UPLOAD_SIDE: Sarvam takes PNG/JPG/PDF, and phone photos are huge."""
    if path.suffix.lower() == ".pdf":
        return path.name, path.read_bytes(), "application/pdf"
    import cv2
    import numpy as np

    image = cv2.imdecode(np.fromfile(str(path), dtype=np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise SarvamUnavailable(f"couldn't open {path.name}")
    h, w = image.shape[:2]
    scale = UPLOAD_SIDE / max(h, w)
    if scale < 1:
        image = cv2.resize(image, (round(w * scale), round(h * scale)), interpolation=cv2.INTER_AREA)
    ok, data = cv2.imencode(".jpg", image, [cv2.IMWRITE_JPEG_QUALITY, 90])
    if not ok:
        raise SarvamUnavailable(f"couldn't prepare {path.name}")
    return path.stem + ".jpg", data.tobytes(), "image/jpeg"


def read_with_sarvam(path: Path) -> dict:
    """The bill's fields from Sarvam Vision; SarvamUnavailable otherwise."""
    import requests

    key = sarvam_key()
    if not key:
        raise SarvamUnavailable("no Sarvam API key")
    headers = {"api-subscription-key": key}
    deadline = time.monotonic() + SARVAM_DEADLINE

    def call(method: str, url: str, **kw):
        try:
            r = requests.request(method, url, headers=headers, timeout=30, **kw)
        except requests.ConnectionError:
            raise SarvamUnavailable("no internet connection to Sarvam") from None
        except requests.Timeout:
            raise SarvamUnavailable("Sarvam didn't answer in time") from None
        if r.status_code in (401, 403):
            raise SarvamUnavailable("the Sarvam API key was refused")
        if r.status_code == 402:
            raise SarvamUnavailable("the Sarvam account is out of credits")
        if r.status_code == 429:
            raise SarvamUnavailable("Sarvam is rate-limiting requests")
        if r.status_code >= 400:
            raise SarvamUnavailable(f"Sarvam returned {r.status_code}: {r.text[:200]}")
        return r.json()

    name, data, mime = upload_bytes(path)
    job = call(
        "POST",
        f"{SARVAM_JOB}/extract",
        files={"file": (name, data, mime)},
        data={"schema": json.dumps(SCHEMA), "language": "en-IN", "output_format": "json"},
    )["job_id"]
    while True:
        status = str(call("GET", f"{SARVAM_JOB}/{job}/status").get("status", "")).lower()
        if status in ("completed", "partially_completed"):
            break
        if status in ("failed", "rejected"):
            raise SarvamUnavailable(f"Sarvam couldn't read the bill ({status})")
        if time.monotonic() > deadline:
            raise SarvamUnavailable("Sarvam took too long")
        time.sleep(1)
    result = call("GET", f"{SARVAM_JOB}/{job}/results").get("result") or {}
    return {
        **{k: clean_bill_field(t, result.get(k)) for k, (t, _) in BILL_FIELDS.items()},
        "items": [
            item
            for raw in result.get("items") or []
            if isinstance(raw, dict) and (item := clean_item(raw))["name"]
        ],
    }


# ─── PaddleOCR (offline) ──────────────────────────────────────────────────

# Header words for each column, tried in order: a heading takes the first
# that fits ("Taxable Value" is the amount, not tax; "MFG Date" isn't the
# expiry). Columns starting "_" are read but not kept, so their text
# lands nowhere else.
HEADERS = {
    "_serial": r"^(sr|sl|s\.?\s*no)\b|^#$",
    "_hsn": r"hsn",
    "_maker": r"^(mfr|mfg|company|mkt)",
    "amount": r"amount|amt|taxable|value|total",
    "taxPercent": r"^(c|s|i)?gst|^tax\b|^vat",
    "discountPercent": r"^disc|discount",
    "name": r"product|item|description|particulars|medicine|name",
    "pack": r"pack|pkg|packing",
    "batch": r"batch|b\.?\s*no|lot",
    "expiry": r"exp",
    "quantity": r"qty|quan",
    "freeQuantity": r"free|bonus|sch",
    "mrp": r"m\.?\s*r\.?\s*p",
    "rate": r"rate|ptr|pts|price",
}
TABLE_END = re.compile(r"sub\s*total|grand\s*total|net\s*(amount|payable)|taxable|cgst|sgst|igst|total\b", re.I)
EXPIRY = re.compile(r"^(0?[1-9]|1[0-2])\s*[/\-.]\s*(\d{2}|\d{4})$|^[a-z]{3}[\s\-/]?\d{2,4}$", re.I)


def read_cells(path: Path) -> list[dict]:
    """Every piece of text with its box, {"text", "x1", "y1", "x2", "y2"},
    turned level: in a photo taken a little crooked, a row's right end
    sits higher or lower than its left and would join the next row."""
    ocr = load_ocr(textline_orientation=False, size="small")
    cells = []
    for page in ocr.predict(load_image(path)):
        polys = [[(float(x), float(y)) for x, y in poly] for poly in page["rec_polys"]]
        angle = tilt(polys)
        cos, sin = math.cos(-angle), math.sin(-angle)
        for text, poly in zip(page["rec_texts"], polys):
            if not text.strip():
                continue
            xs = [x * cos - y * sin for x, y in poly]
            ys = [x * sin + y * cos for x, y in poly]
            cells.append(
                {"text": text.strip(), "x1": min(xs), "y1": min(ys), "x2": max(xs), "y2": max(ys)}
            )
    return cells


def tilt(polys: list[list[tuple[float, float]]]) -> float:
    """The page's tilt in radians: the middle slope of its long text boxes'
    top edges."""
    slopes = sorted(
        math.atan2(p[1][1] - p[0][1], p[1][0] - p[0][0])
        for p in polys
        if len(p) == 4 and abs(p[1][0] - p[0][0]) > 2 * abs(p[3][1] - p[0][1])
    )
    return slopes[len(slopes) // 2] if slopes else 0.0


def group_rows(cells: list[dict]) -> list[list[dict]]:
    """Cells that share a line, top to bottom, each row left to right."""
    if not cells:
        return []
    heights = sorted(c["y2"] - c["y1"] for c in cells)
    tolerance = heights[len(heights) // 2] * 0.6
    rows: list[list[dict]] = []
    for cell in sorted(cells, key=lambda c: (c["y1"] + c["y2"]) / 2):
        middle = (cell["y1"] + cell["y2"]) / 2
        if rows:
            last = rows[-1]
            row_middle = sum((c["y1"] + c["y2"]) / 2 for c in last) / len(last)
            if abs(middle - row_middle) <= tolerance:
                last.append(cell)
                continue
        rows.append([cell])
    return [sorted(r, key=lambda c: c["x1"]) for r in rows]


def header_columns(row: list[dict], found: dict | None = None) -> dict[str, tuple[float, float]] | None:
    """Field → (x1, x2) when [row] is the item table's header. [found]:
    columns already known, when [row] holds the second line of headings."""
    found = dict(found or {})
    for cell in row:
        for field, pattern in HEADERS.items():
            if field not in found and re.search(pattern, cell["text"], re.I):
                found[field] = (cell["x1"], cell["x2"])
                break
    kept = [f for f in found if not f.startswith("_")]
    return found if len(kept) >= 3 and "name" in found else None


def tallest_text(rows: list[list[dict]]) -> str | None:
    """The seller's name: the biggest wordy text at the top, with the lines
    just above or below it in the same size ("MediCare / Wholesale
    Pharmacy")."""
    skip = re.compile(r"invoice|tax|bill|gst|cash|credit|memo|phone|ph:|original|duplicate|copy|recipient", re.I)
    top = [c for row in rows[:8] for c in row if len(re.findall(r"[A-Za-z]", c["text"])) >= 4 and not skip.search(c["text"])]
    if not top:
        return None
    best = max(top, key=lambda c: c["y2"] - c["y1"])
    height = best["y2"] - best["y1"]

    def same_block(c: dict) -> bool:
        gap = max(c["y1"] - best["y2"], best["y1"] - c["y2"])
        return (
            c is not best
            and -0.2 * height <= gap < height
            and abs(c["x1"] - best["x1"]) < height
            and abs((c["y2"] - c["y1"]) - height) < 0.3 * height
        )

    block = sorted([best, *filter(same_block, top)], key=lambda c: c["y1"])
    return " ".join(c["text"] for c in block)


def bill_totals(texts: list[str]) -> dict:
    """Grand total and GST rate from the text under the table."""
    money = re.compile(r"\d[\d,]*\.\d{2}\b")
    totals = [
        float(m.replace(",", ""))
        for t in texts
        if re.search(r"\btotal\b|payable|net\s*amount", t, re.I) and not re.search(r"words|only", t, re.I)
        for m in money.findall(t)
    ]
    whole = "\n".join(texts)

    def rate(kind: str) -> float | None:
        m = re.search(rf"\b{kind}\s*[@(:]?\s*(\d{{1,2}}(?:\.\d+)?)\s*%", whole, re.I)
        return float(m.group(1)) if m else None

    igst, cgst, sgst, gst = rate("igst"), rate("cgst"), rate("sgst"), rate("gst")
    tax = igst if igst is not None else (cgst + sgst if cgst is not None and sgst is not None else gst)
    return {"grandTotal": max(totals) if totals else None, "taxPercent": tax}


def column_of(cell: dict, columns: dict[str, tuple[float, float]]) -> str:
    """The header column [cell] sits under: the most overlap, else the
    nearest middle."""
    best, best_overlap = None, 0.0
    for field, (x1, x2) in columns.items():
        overlap = min(cell["x2"], x2) - max(cell["x1"], x1)
        if overlap > best_overlap:
            best, best_overlap = field, overlap
    if best:
        return best
    middle = (cell["x1"] + cell["x2"]) / 2
    return min(columns, key=lambda f: abs((columns[f][0] + columns[f][1]) / 2 - middle))


def parse_bill(rows: list[list[dict]]) -> dict:
    """Supplier, invoice and items from the rows of text."""
    texts = [" ".join(c["text"] for c in row) for row in rows]
    whole = "\n".join(texts)

    number = re.search(r"(?:invoice|bill|inv)\s*(?:no|number|#)\.?\s*[:\-]?\s*([A-Z0-9][A-Z0-9/\-]+)", whole, re.I)
    date = re.search(
        r"\bdate\s*[:\-]?\s*(\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}|\d{1,2}[\s\-/.]?[A-Za-z]{3,9}[\s\-/.,]*\d{2,4})",
        whole,
        re.I,
    )
    heights = sorted(c["y2"] - c["y1"] for row in rows for c in row) or [0]
    line_height = heights[len(heights) // 2]

    items = []
    columns = None
    header_at = -1
    for i, (row, text) in enumerate(zip(rows, texts)):
        if columns is None:
            columns = header_columns(row)
            if columns:
                header_at = i
                # Headings over two lines ("Disc." / "(%)", "Sr." / "No."):
                # take the other line's headings too.
                for j in (i - 1, i + 1):
                    if 0 <= j < len(rows) and len(rows[j]) <= 4:
                        columns = header_columns(rows[j], columns) or columns
            continue
        if i == header_at + 1 and not re.search(r"[A-Za-z]{3}", text):
            continue  # the header's second line
        if TABLE_END.search(text):
            break
        item: dict[str, str] = {}
        for cell in row:
            # A box as tall as several rows is the serial column read as one.
            if cell["y2"] - cell["y1"] > 1.8 * line_height:
                continue
            field = column_of(cell, columns)
            item[field] = f"{item[field]} {cell['text']}" if field in item else cell["text"]
        if "name" in item:
            item["name"] = re.sub(r"^\d{1,3}[.)]?\s+(?=[A-Za-z])", "", item["name"])
        if unit := re.sub(r"[\d.,\s]", "", item.get("quantity", "")):
            item["quantityUnit"] = unit  # "10 TBS"
        if len(re.findall(r"[A-Za-z]", item.get("name", ""))) >= 3:
            items.append(clean_item(item))

    if columns is None:
        # No header found: keep rows that carry an expiry date.
        for row in rows:
            texts_in_row = [c["text"] for c in row]
            expiry = next((t for t in texts_in_row if EXPIRY.match(t)), None)
            name = next((t for t in texts_in_row if len(re.findall(r"[A-Za-z]", t)) >= 3), None)
            if expiry and name:
                batch = next(
                    (
                        t
                        for t in texts_in_row
                        if t not in (name, expiry)
                        and re.fullmatch(r"[A-Z0-9\-]{4,}", t, re.I)
                        and re.search(r"\d", t)
                        and re.search(r"[A-Z]", t, re.I)
                    ),
                    None,
                )
                items.append(clean_item({"name": name, "expiry": expiry, "batch": batch}))

    return {
        "supplier": clean_text(tallest_text(rows)),
        "invoiceNumber": number.group(1) if number else None,
        "invoiceDate": clean_text(date.group(1)) if date else None,
        "subtotal": None,
        "taxAmount": None,
        "amountsIncludeTax": None,
        **bill_totals(texts),
        "items": items,
        "lines": texts,
    }


def read_with_paddle(path: Path) -> dict:
    try:
        cells = read_cells(path)
    except ImportError as e:
        raise RuntimeError(f"PaddleOCR isn't installed in this Python ({sys.executable}): {e}") from e
    return parse_bill(group_rows(cells))


# ─── Shared ───────────────────────────────────────────────────────────────


def clean_text(value) -> str | None:
    if value is None:
        return None
    text = re.sub(r"\s+", " ", str(value)).strip()
    return text or None


def to_number(value) -> float | None:
    if isinstance(value, (int, float)):
        return float(value)
    text = re.sub(r"[₹,\s]|rs\.?", "", str(value or ""), flags=re.I)
    match = re.search(r"\d+(?:\.\d+)?", text)
    return float(match.group()) if match else None


def clean_item(raw: dict) -> dict:
    return {
        field: to_number(raw.get(field)) if field in NUMBER_FIELDS else clean_text(raw.get(field))
        for field in ITEM_FIELDS
    }


def scan(path: Path, offline: bool = False) -> dict:
    note = "Offline mode" if offline else None
    if not offline:
        try:
            return {"source": "sarvam", "note": None, **read_with_sarvam(path)}
        except SarvamUnavailable as e:
            note = str(e)
        except Exception as e:  # anything unexpected: still read it here
            note = f"Sarvam failed: {type(e).__name__}: {e}"
        print(f"[bill_scan] Sarvam Vision unavailable ({note}); using PaddleOCR", file=sys.stderr)
    return {"source": "paddle", "note": note, **read_with_paddle(path)}


def main() -> int:
    parser = argparse.ArgumentParser(description="Read a supplier's purchase bill.")
    parser.add_argument("image", help="photo, scan or PDF of the bill")
    parser.add_argument("--json", action="store_true", help="one line of JSON, for the app")
    parser.add_argument("--offline", action="store_true", help="skip Sarvam; PaddleOCR only")
    args = parser.parse_args()

    path = Path(args.image).expanduser().resolve()
    problem = check_image(path)
    if args.json:
        out = sys.stdout
        if problem:
            out.write(json.dumps({"error": problem}) + "\n")
            return 1
        try:
            # Paddle's own messages go to stderr; stdout carries only the JSON.
            with contextlib.redirect_stdout(sys.stderr):
                result = scan(path, args.offline)
        except Exception as e:
            out.write(json.dumps({"error": f"{type(e).__name__}: {e}"}) + "\n")
            return 1
        out.write(json.dumps(result) + "\n")
        return 0

    if problem:
        print(f"Error: {problem}", file=sys.stderr)
        return 1
    started = time.perf_counter()
    result = scan(path, args.offline)
    print(f"Read by {result['source']}" + (f" ({result['note']})" if result["note"] else ""))
    print(f"Supplier: {result['supplier']}  Invoice: {result['invoiceNumber']}  Date: {result['invoiceDate']}")
    print(
        f"Subtotal: {result['subtotal']}  GST: {result['taxAmount']} ({result['taxPercent']}%)"
        f"  Grand total: {result['grandTotal']}"
    )
    for item in result["items"]:
        print("  " + " | ".join(f"{k}={v}" for k, v in item.items() if v is not None))
    print(f"{len(result['items'])} items in {time.perf_counter() - started:.1f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
