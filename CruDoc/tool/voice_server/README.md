# CruDoc Voice Server — Setup Guide

Local Whisper speech-to-text for the CruDoc voice scribe. Runs on `127.0.0.1:8765`; nothing leaves the machine.

| Mode | Model | Used for |
|---|---|---|
| `fast` | `base.en` (FP16, ~60 ms) | Live words while the talk key is held |
| `short` | `small.en` (FP16 GPU / INT8 CPU, ~140 ms) | Short utterances (< 2.5 s); also the CPU fallback |
| `accurate` | `large-v3-turbo` (INT8_FP16) | Final clinical transcription pass |

## 1. Requirements

- Windows 10/11, Python 3.10–3.12
- **GPU (recommended):** NVIDIA GPU with a recent driver (CUDA 12 capable). The CUDA/cuDNN libraries come from pip — no CUDA Toolkit install needed.
- **No GPU:** still works — the server falls back to `small.en` on CPU (slower).
- ~2.5 GB free disk for models.

## 2. Install

From `CruDoc/tool/voice_server/`:

```powershell
py -3.12 -m venv .venv
.venv\Scripts\python -m pip install --upgrade pip
.venv\Scripts\pip install -r requirements.txt
```

## 3. Download the models (once, needs internet)

```powershell
.venv\Scripts\python download_models.py
```

This saves the three Whisper models into `tool/voice_server/models/` (git-ignored) and caches the
`all-MiniLM-L6-v2` embedding model used by `/intent`. After this, the server runs fully offline.

Sources (Hugging Face):

- `Systran/faster-whisper-base.en`
- `Systran/faster-whisper-small.en`
- `mobiuslabsgmbh/faster-whisper-large-v3-turbo` (the repo faster-whisper itself uses for `large-v3-turbo`)

Download just one: `.venv\Scripts\python download_models.py small.en`

> Skipping this step is fine too — `server.py` downloads anything missing on first start.

## 4. Run

```powershell
.venv\Scripts\python server.py
```

Wait for `Voice server ready on :8765 (cuda)` — or `(cpu)` if no GPU was found. Check it:

```powershell
curl http://127.0.0.1:8765/health
```

Then start the CruDoc Windows app. `SpeechEngine.model = 'server'` (default) talks to this server.

## 5. Optional: fully on-device mode (no Python server)

The app can also transcribe in-process with sherpa-onnx. The INT8 ONNX files go in
`CruDoc/assets/voice/whisper/` (git-ignored):

```
base.en-encoder.int8.onnx   base.en-decoder.int8.onnx   base.en-tokens.txt
small.en-encoder.int8.onnx  small.en-decoder.int8.onnx  small.en-tokens.txt
```

Get them from the sherpa-onnx releases (extract only the 3 files above from each archive):

- https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-base.en.tar.bz2
- https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small.en.tar.bz2

Then:

1. In `pubspec.yaml`, uncomment `- assets/voice/whisper/`.
2. In `lib/features/voice/services/speech_engine.dart`, set `static const model = 'base.en';` (or `'small.en'`).
3. `flutter clean; flutter build windows`

## Troubleshooting

- **`GPU unavailable (...); using CPU`** — update the NVIDIA driver; re-run `pip install -r requirements.txt` so `nvidia-cublas-cu12` / `nvidia-cudnn-cu12` are in the venv.
- **Port 8765 in use** — another server instance is running; close it.
- **App says model folder missing** — on-device mode only: the files in step 5 aren't in `assets/voice/whisper/`, or the pubspec line is still commented.
