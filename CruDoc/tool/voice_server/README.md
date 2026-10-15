# CruDoc Voice Server — Setup Guide

Speech-to-text for the CruDoc voice scribe and voice commands. Runs on `127.0.0.1:8765`.

**Default engine: Sarvam `saaras:v4`** (`STT_ENGINE=sarvam`). Each clip is sent to
`api.sarvam.ai`, so patient speech leaves the machine. The API key is kept in this folder's
`.env`, not in the app. Patient names and a few clinical words go along as `keyterms` so
they're spelled right.

**Streaming:** the server also listens on `ws://127.0.0.1:8766` and relays each utterance to
Sarvam's realtime WebSocket (`/speech-to-text-realtime/ws`, manual endpointing: the app says
when an utterance starts and ends). Live words arrive while the doctor speaks, and the final
~100–350 ms after they stop; only the audio of each utterance is sent and billed. If the stream
fails, the app falls back to one `POST /transcribe` (Sarvam REST, up to 30 s of audio).

## 0. Sarvam setup

```powershell
copy .env.example .env   # then set SARVAM_API_KEY
```

| Setting | Default | |
|---|---|---|
| `STT_ENGINE` | `sarvam` | `whisper` switches back to local Whisper (below) |
| `SARVAM_API_KEY` | — | Required for `sarvam` |
| `SARVAM_STT_MODEL` | `saaras:v4` | |
| `SARVAM_LANGUAGE` | `en-IN` | `hi-IN`, `mr-IN`, … or `unknown` to auto-detect |

With Sarvam, the GPU and the Whisper model download (steps 1 and 3) aren't needed, but the venv is
(it still runs `/intent`). Failed Sarvam calls are printed in the server log (status and error
message, never the transcript).

## Local Whisper (`STT_ENGINE=whisper`)

Nothing leaves the machine. Every mode runs on one model, `large-v3-turbo` (INT8_FP16 on GPU,
INT8 on CPU), loaded once:

| Mode | Decoding | Used for |
|---|---|---|
| `fast` | beam 1 | Live words while the talk key is held |
| `short` | beam 3 | Short utterances (< 2.5 s) |
| `accurate` | beam 3 | Final clinical transcription pass |

## 1. Requirements

- Windows 10/11, Python 3.10–3.12
- **GPU (recommended):** NVIDIA GPU with a recent driver (CUDA 12 capable). The CUDA/cuDNN libraries come from pip — no CUDA Toolkit install needed.
- **No GPU:** still works — the server runs `large-v3-turbo` on CPU (much slower).
- ~1.7 GB free disk for models.

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

This saves `large-v3-turbo` into `tool/voice_server/models/` (git-ignored) and caches the
`all-MiniLM-L6-v2` embedding model used by `/intent`. After this, the server runs fully offline.

Source (Hugging Face): `mobiuslabsgmbh/faster-whisper-large-v3-turbo` (the repo faster-whisper
itself uses for `large-v3-turbo`). `base.en` and `small.en` can still be fetched by name
(`download_models.py small.en`) if `MODELS` in `server.py` is pointed back at them.

> Skipping this step is fine too — `server.py` downloads anything missing on first start.

## 4. Run

```powershell
.venv\Scripts\python server.py
```

Wait for `Voice server ready on :8765 (sarvam, cloud)` — or `(whisper, cuda)` / `(whisper, cpu)` with local Whisper. Check it:

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

- **`SARVAM_API_KEY is not set`** — add it to `tool/voice_server/.env` (step 0).
- **`Sarvam STT 403` / `429`** — invalid key / rate limit or out of credits on the Sarvam account.
- **`GPU unavailable (...); using CPU`** — update the NVIDIA driver; re-run `pip install -r requirements.txt` so `nvidia-cublas-cu12` / `nvidia-cudnn-cu12` are in the venv.
- **Port 8765 / 8766 in use** — another server instance is running; close it.
- **App says model folder missing** — on-device mode only: the files in step 5 aren't in `assets/voice/whisper/`, or the pubspec line is still commented.
