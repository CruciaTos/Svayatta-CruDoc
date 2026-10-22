# Bill scanning (Inventory > Scan, desktop)

Inventory's **Scan** button photographs or picks a supplier's purchase bill.
The app runs `bill_scan.py --json`, which reads every medicine line
(name, pack, batch, expiry, quantity, free, MRP, rate, amount):

1. **Sarvam Vision** (`api.sarvam.ai/doc-ai/v1/job/extract`), about 10 s.
2. **PaddleOCR** on this computer when there's no internet, no key, or
   Sarvam fails: about 15–30 s, then the table is rebuilt from where the
   text sits.

The app then lists the lines for review. Ticked lines are added: items
already in the inventory are restocked, the rest are created.

## Setup (Windows, PowerShell, from the repo root)

```powershell
py -3.11 -m venv CruDoc\tool\paddle_ocr_test\.venv
CruDoc\tool\paddle_ocr_test\.venv\Scripts\python.exe -m pip install paddlepaddle==3.3.1 paddleocr==3.7.0 --timeout 60 --retries 10
```

If C: is short of space, make the venv elsewhere and link it:
`New-Item -ItemType Junction -Path CruDoc\tool\paddle_ocr_test\.venv -Target D:\crudoc_paddle\venv`.
PaddleOCR's models (~150 MB, downloaded on first use) go in a `models`
folder beside the venv's real location. Remove a linked `.venv` with
`rmdir` only, never a recursive delete.

**Sarvam key**: `SARVAM_API_KEY` from the environment, `CruDoc/.env.local`
or `CruDoc/tool/voice_server/.env` (the voice server's key works).

## By hand

```powershell
$py = 'CruDoc\tool\paddle_ocr_test\.venv\Scripts\python.exe'
& $py CruDoc\tool\paddle_ocr_test\bill_scan.py bill.jpg            # Sarvam, else PaddleOCR
& $py CruDoc\tool\paddle_ocr_test\bill_scan.py bill.jpg --offline  # PaddleOCR only
& $py CruDoc\tool\paddle_ocr_test\prescription_ocr.py rx.jpg       # plain text, PaddleOCR
```

Tests: `cd CruDoc\tool\paddle_ocr_test; .\.venv\Scripts\python.exe -m unittest test_bill_scan`

Don't turn on `enable_mkldnn`: Paddle 3.3 crashes with it on this setup.
