"""Local voice-intelligence server for the CruDoc voice demo.

Speech-to-text runs on Sarvam's saaras:v4 by default (STT_ENGINE=sarvam):
the audio goes to api.sarvam.ai, and the API key stays on this machine,
out of the app. STT_ENGINE=whisper runs large-v3-turbo on the local GPU
instead, and nothing leaves the machine.

  ws://127.0.0.1:8766 → Sarvam's realtime WebSocket (sarvam only): the app
                        streams each utterance as it's spoken and gets live
                        partials, and the final ~100–300 ms after it ends
  POST /transcribe  → Sarvam saaras:v4 REST (or local Whisper); the app's
                      fallback when the stream fails
  POST /intent      → all-MiniLM-L6-v2 embedding match, ~5 ms, local

Settings come from the environment or tool/voice_server/.env:
    STT_ENGINE        sarvam (default) | whisper
    SARVAM_API_KEY    required for sarvam
    SARVAM_STT_MODEL  default saaras:v4
    SARVAM_LANGUAGE   default en-IN; "unknown" to auto-detect

To run by hand:
    .venv\\Scripts\\python server.py

POST /transcribe   body: 16 kHz mono PCM16 little-endian
                   header X-Hints: URL-encoded patient names, comma separated
                   header X-Model: fast | short | accurate (default; Whisper only)
                   header X-Mode: dictation for a consultation
                   header X-Context: the end of the dictation so far (Whisper only)
                   -> {"text": "...", "ms": 123}
POST /intent       body: {"text": "...", "options": [{"id": "...", "phrases": [...]}]}
                   -> {"id": "...", "score": 0.72}
GET  /health       -> {"ok": true, "engine": "sarvam"|"whisper", "device": ...,
                       "stream_port": 8766 (sarvam only)}

Stream, one connection per utterance:
    app → {"hints": "...", "mode": "dictation"|"", "context": "..."}  (first)
    app → binary 16 kHz mono PCM16 chunks
    app → {"event": "end"} when the utterance ends (closing instead cancels)
    ← {"type": "partial", "text": "..."}
    ← {"type": "final", "text": "...", "ms": 123}  (ms: after "end"), then close
    ← {"type": "error", "message": "..."}, then close
"""

import asyncio
import base64
import io
import json
import os
import sys
import threading
import time
import urllib.error
import urllib.request
import uuid
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlencode

PORT = 8765
STREAM_PORT = 8766
HERE = Path(__file__).resolve().parent


def _load_env_file():
    """KEY=value lines from tool/voice_server/.env; the real environment wins."""
    env = HERE / ".env"
    if not env.is_file():
        return
    for line in env.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


_load_env_file()
ENGINE = os.environ.get("STT_ENGINE", "sarvam").strip().lower()
SARVAM_URL = "https://api.sarvam.ai/speech-to-text"
SARVAM_WS = "wss://api.sarvam.ai/speech-to-text-realtime/ws"
SARVAM_KEY = os.environ.get("SARVAM_API_KEY", "").strip()
SARVAM_MODEL = os.environ.get("SARVAM_STT_MODEL", "saaras:v4").strip()
SARVAM_LANGUAGE = os.environ.get("SARVAM_LANGUAGE", "en-IN").strip()
if ENGINE == "sarvam" and not SARVAM_KEY:
    sys.exit("SARVAM_API_KEY is not set: add it to tool/voice_server/.env")

# Every mode uses large-v3-turbo: one model on disk and in GPU memory, and
# the accurate model's words even for live partials. "fast" still decodes
# with beam size 1, so live words stay quick.
MODELS = {
    "fast": ("large-v3-turbo", "int8_float16"),
    "short": ("large-v3-turbo", "int8_float16"),
    "accurate": ("large-v3-turbo", "int8_float16"),
}


def _add_cuda_dlls():
    """pip's nvidia-* wheels put cuBLAS/cuDNN DLLs where Windows won't look."""
    root = Path(sys.prefix) / "Lib" / "site-packages" / "nvidia"
    for sub in ("cublas", "cudnn", "cuda_runtime"):
        bin_dir = root / sub / "bin"
        if bin_dir.is_dir():
            os.add_dll_directory(str(bin_dir))
            os.environ["PATH"] = str(bin_dir) + os.pathsep + os.environ["PATH"]


import numpy as np  # noqa: E402

if ENGINE == "whisper":
    _add_cuda_dlls()
    from faster_whisper import WhisperModel  # noqa: E402


MODELS_DIR = HERE / "models"


def _path(name):
    """Use the copy from download_models.py if present (offline), else the
    Hugging Face name (downloaded and cached on first run)."""
    local = MODELS_DIR / f"faster-whisper-{name}"
    return str(local) if (local / "model.bin").is_file() else name


def _load():
    try:
        loaded = {}
        # Modes that share a model share one loaded copy.
        by_model = {}
        for key, spec in MODELS.items():
            if spec not in by_model:
                name, compute = spec
                m = WhisperModel(_path(name), device="cuda", compute_type=compute)
                list(m.transcribe(np.zeros(16000, dtype=np.float32), language="en")[0])
                by_model[spec] = m
            loaded[key] = by_model[spec]
        return loaded, "cuda"
    except Exception as e:  # no GPU / CUDA libs: slower, still works
        print(f"GPU unavailable ({e}); using CPU", flush=True)
        m = WhisperModel(_path("large-v3-turbo"), device="cpu", compute_type="int8")
        return {key: m for key in MODELS}, "cpu"


def _load_embedder():
    """Sentence embeddings for matching phrasings the rules don't know."""
    import onnxruntime as ort
    from huggingface_hub import hf_hub_download
    from tokenizers import Tokenizer

    repo = "sentence-transformers/all-MiniLM-L6-v2"
    tok = Tokenizer.from_file(hf_hub_download(repo, "tokenizer.json"))
    tok.enable_truncation(128)
    tok.enable_padding()
    sess = ort.InferenceSession(
        hf_hub_download(repo, "onnx/model.onnx"),
        providers=["CPUExecutionProvider"],
    )
    return sess, tok


def embed(texts):
    enc = tokenizer.encode_batch(texts)
    ids = np.array([e.ids for e in enc], dtype=np.int64)
    mask = np.array([e.attention_mask for e in enc], dtype=np.int64)
    feeds = {"input_ids": ids, "attention_mask": mask}
    if any(i.name == "token_type_ids" for i in embedder.get_inputs()):
        feeds["token_type_ids"] = np.zeros_like(ids)
    out = embedder.run(None, feeds)[0]
    m = mask[..., None].astype(np.float32)
    v = (out * m).sum(1) / np.clip(m.sum(1), 1e-9, None)
    return v / np.linalg.norm(v, axis=1, keepdims=True)


_phrase_cache = {}


def best_option(text, options):
    pairs = [(o["id"], p.lower()) for o in options for p in o["phrases"]]
    if not pairs:
        return None, 0.0
    missing = sorted({p for _, p in pairs if p not in _phrase_cache})
    if missing:
        for p, v in zip(missing, embed(missing)):
            _phrase_cache[p] = v
    q = embed([text.lower()])[0]
    best = max(pairs, key=lambda ip: float(_phrase_cache[ip[1]] @ q))
    return best[0], float(_phrase_cache[best[1]] @ q)


models, device = _load() if ENGINE == "whisper" else ({}, "cloud")
embedder, tokenizer = _load_embedder()
embed(["warm up"])
# One lock per model: a live pass and a final pass can run side by side.
locks = {key: threading.Lock() for key in models}
print(f"Voice server ready on :{PORT} ({ENGINE}, {device})", flush=True)


# VOICE_DEBUG=1: print every transcription (length, loudness, result).
# Off by default: it would put what patients say in the console.
DEBUG = os.environ.get("VOICE_DEBUG") == "1"

# Quieter than this (RMS of the whole clip) is room noise, not speech:
# Whisper turns it into "Thank you." or repeats the prompt back.
SILENCE_RMS = 0.004


def _echoes_prompt(text: str, prompt: str) -> bool:
    """Whisper sometimes "hears" its own prompt in near-silence."""
    t = "".join(c for c in text.lower() if c.isalnum() or c == " ").strip()
    p = "".join(c for c in prompt.lower() if c.isalnum() or c == " ")
    return len(t) > 8 and t in p


# Words saaras:v4 should spell our way. It takes up to 50 keyterms of 64
# characters, in place of Whisper's prompt. Patient names go first.
COMMAND_TERMS = [
    "add patient", "appointment", "reschedule", "start consultation",
    "call next patient", "mark done", "date of birth", "allergic to",
    "inventory", "record payment", "expense", "invoice", "tablets",
    "capsules", "expiry", "batch number",
]
DICTATION_TERMS = [
    "pain score", "range of motion", "physiotherapy", "diagnosis",
    "follow-up", "remedy", "potency", "exercises",
]


def _keyterms(hints: str, mode: str) -> list:
    names = [n.strip()[:64] for n in hints.split(",") if n.strip()]
    terms = DICTATION_TERMS if mode == "dictation" else COMMAND_TERMS
    # Names first, but never so many that the command words drop off.
    names = list(dict.fromkeys(names))[: 50 - len(terms)]
    return list(dict.fromkeys(names + terms))[:50]


def _wav(pcm: bytes) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(pcm)
    return buf.getvalue()


def _multipart(fields: dict, wav: bytes) -> tuple:
    boundary = uuid.uuid4().hex
    out = b""
    for k, v in fields.items():
        out += (
            f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"'
            f"\r\n\r\n{v}\r\n"
        ).encode()
    out += (
        f'--{boundary}\r\nContent-Disposition: form-data; name="file"; '
        f'filename="audio.wav"\r\nContent-Type: audio/wav\r\n\r\n'
    ).encode()
    out += wav + f"\r\n--{boundary}--\r\n".encode()
    return out, f"multipart/form-data; boundary={boundary}"


def _sarvam(pcm: bytes, hints: str, mode: str) -> str:
    fields = {"model": SARVAM_MODEL, "language_code": SARVAM_LANGUAGE}
    terms = _keyterms(hints, mode)
    if terms and SARVAM_MODEL.startswith("saaras:v4"):
        fields["keyterms"] = json.dumps(terms)
    body, content_type = _multipart(fields, _wav(pcm))
    req = urllib.request.Request(
        SARVAM_URL,
        data=body,
        headers={"api-subscription-key": SARVAM_KEY, "Content-Type": content_type},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return (json.loads(r.read()).get("transcript") or "").strip()
    except urllib.error.HTTPError as e:
        # The error body says what's wrong (key, model, rate limit); it
        # never holds the transcript.
        print(f"Sarvam STT {e.code}: {e.read()[:300]!r}", flush=True)
    except Exception as e:  # offline, timeout
        print(f"Sarvam STT failed: {type(e).__name__}: {e}", flush=True)
    return ""


def _prompt(hints: str, mode: str, context: str) -> str:
    names = f" Patients: {hints}." if hints else ""
    if mode == "dictation":
        # A consultation being written down: clinical words, and the end of
        # what was said before, so names and terms stay spelled the same.
        return (
            "A doctor's consultation with a patient: complaints, pain score, "
            "duration, history, examination, range of motion, diagnosis, "
            "advice, exercises, remedy, potency, follow-up."
            + names
            + (f" {context[-300:]}" if context else "")
        )
    # The command words steer spelling ("Add appointment", not "At
    # appointment"); naming the patients gets Indian names right.
    # Names go last: Whisper keeps the end of a long prompt.
    return (
        "Doctor's voice commands in a clinic app: add patient, book an "
        "appointment, reschedule, move, open, go to schedule, confirm, "
        "cancel, start session, start consultation, call next patient, "
        "mark done, paid, record payment, record expense, new invoice, "
        "add item to inventory, tablets, capsules, expiry, batch. Date of "
        "birth, mobile, email, allergic to."
        + names
    )


def transcribe(
    pcm: bytes, hints: str, which: str, mode: str = "", context: str = ""
) -> str:
    audio = np.frombuffer(pcm, dtype=np.int16).astype(np.float32) / 32768.0
    if audio.size == 0 or float(np.sqrt(np.mean(audio * audio))) < SILENCE_RMS:
        return ""
    if ENGINE == "sarvam":
        return _sarvam(pcm, hints, mode)
    which = which if which in models else "accurate"
    prompt = _prompt(hints, mode, context)
    with locks[which]:
        segments, _ = models[which].transcribe(
            audio,
            language="en",
            beam_size=1 if which == "fast" else 3,
            initial_prompt=prompt,
            condition_on_previous_text=False,
            without_timestamps=True,
            vad_filter=False,
        )
        # Drop what Whisper itself thinks wasn't speech.
        kept = [
            s.text.strip()
            for s in segments
            if not (s.no_speech_prob > 0.6 and s.avg_logprob < -0.8)
        ]
    text = " ".join(t for t in kept if t).strip()
    return "" if _echoes_prompt(text, prompt) else text


# ── Streaming: relay one utterance to Sarvam's realtime WebSocket ──────────
async def _relay(client):
    import websockets

    try:
        cfg = json.loads(await client.recv())
    except Exception:
        return
    hints, mode = cfg.get("hints", ""), cfg.get("mode", "")
    query = {
        "model": SARVAM_MODEL,
        "language_code": "auto" if SARVAM_LANGUAGE == "unknown" else SARVAM_LANGUAGE,
        # The app decides when an utterance starts and ends (talk key,
        # pauses), so Sarvam's own VAD stays off.
        "endpointing": "manual",
        # Commands want quick live words; dictation, steadier ones.
        "stream_type": "balanced" if mode == "dictation" else "fast",
        "prompt": _prompt(hints, mode, cfg.get("context", "")),
        "keyterms": json.dumps(_keyterms(hints, mode)),
    }
    ended = None
    try:
        async with websockets.connect(
            f"{SARVAM_WS}?{urlencode(query)}",
            additional_headers={"api-subscription-key": SARVAM_KEY},
            open_timeout=8,
        ) as up:
            begin = json.loads(await up.recv())
            if begin.get("event") != "session.begin":
                raise RuntimeError(f"unexpected first event: {begin}")
            await up.send(json.dumps({"event": "speech_start"}))

            async def upstream():
                nonlocal ended
                # Audio that arrived while connecting is waiting in `client`.
                async for msg in client:
                    if isinstance(msg, bytes):
                        audio = base64.b64encode(msg).decode()
                        await up.send(json.dumps({"event": "audio_input", "audio": audio}))
                    elif json.loads(msg).get("event") == "end":
                        ended = time.perf_counter()
                        await up.send(json.dumps({"event": "speech_end"}))
                        return
                # The app hung up without "end": the utterance was dropped.
                raise ConnectionAbortedError

            async def downstream():
                async for msg in up:
                    e = json.loads(msg)
                    kind = e.get("event")
                    if kind == "transcript.partial":
                        await client.send(json.dumps({"type": "partial", "text": e.get("text", "")}))
                    elif kind == "transcript.final":
                        ms = int((time.perf_counter() - ended) * 1000) if ended else 0
                        await client.send(
                            json.dumps({"type": "final", "text": e.get("text", ""), "ms": ms})
                        )
                        return
                    elif kind == "error":
                        # Never holds the transcript; safe to log.
                        print(f"Sarvam stream error: {e}", flush=True)
                        if e.get("is_fatal"):
                            raise RuntimeError(e.get("message", "stream error"))
                raise RuntimeError("Sarvam closed the stream before the final")

            up_task = asyncio.create_task(upstream())
            down_task = asyncio.create_task(downstream())
            try:
                await asyncio.gather(up_task, down_task)
            finally:
                up_task.cancel()
                down_task.cancel()
            await up.send(json.dumps({"event": "end"}))
    except ConnectionAbortedError:
        pass
    except Exception as e:
        print(f"Sarvam stream failed: {type(e).__name__}: {e}", flush=True)
        try:
            await client.send(json.dumps({"type": "error", "message": str(e)[:200]}))
        except Exception:
            pass


def _serve_stream():
    import websockets

    async def main():
        async with websockets.serve(_relay, "127.0.0.1", STREAM_PORT, max_size=2**20):
            await asyncio.Future()

    asyncio.run(main())


if ENGINE == "sarvam":
    import websockets  # noqa: E402,F401  (fail at startup, not on first use)

    threading.Thread(target=_serve_stream, daemon=True).start()


class Handler(BaseHTTPRequestHandler):
    def _json(self, obj):
        body = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _error(self, code: int, msg: str):
        body = json.dumps({"error": msg}).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        health = {"ok": True, "engine": ENGINE, "device": device}
        if ENGINE == "sarvam":
            health["stream_port"] = STREAM_PORT
        self._json(health)

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))

        # ── Semantic intent matching ──────────────────────────────────────────
        if self.path.startswith("/intent"):
            req = json.loads(body or b"{}")
            t0 = time.perf_counter()
            best, score = best_option(req.get("text", ""), req.get("options", []))
            self._json({
                "id": best,
                "score": score,
                "ms": int((time.perf_counter() - t0) * 1000),
            })
            return

        if not self.path.startswith("/transcribe"):
            self._error(404, f"no such endpoint: {self.path}")
            return

        # ── Transcription: Sarvam or local Whisper ───────────────────────────
        pcm = body
        hints = unquote(self.headers.get("X-Hints", ""))
        which = self.headers.get("X-Model", "accurate")
        mode = self.headers.get("X-Mode", "")
        context = unquote(self.headers.get("X-Context", ""))
        t0 = time.perf_counter()
        text = transcribe(pcm, hints, which, mode, context) if pcm else ""
        ms = int((time.perf_counter() - t0) * 1000)
        if DEBUG:
            audio = np.frombuffer(pcm, dtype=np.int16).astype(np.float32) / 32768.0
            rms = float(np.sqrt(np.mean(audio * audio))) if audio.size else 0.0
            peak = float(np.abs(audio).max()) if audio.size else 0.0
            print(
                f"[{which:8} {mode or 'command':9}] {audio.size / 16000:5.1f}s "
                f"rms={rms:.4f} peak={peak:.3f} {ms:4}ms -> {text!r}",
                flush=True,
            )
        self._json({"text": text, "ms": ms})

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
