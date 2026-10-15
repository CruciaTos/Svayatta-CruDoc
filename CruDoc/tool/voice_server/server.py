"""Local voice-intelligence server for the CruDoc voice demo.

Two-speed architecture — navigation is instantaneous, form-filling is smart:

  FAST PATH  (navigation: openPatient, markDone, cancel, …)
    POST /transcribe  X-Model: fast   → base.en Whisper, ~60 ms, no LLM
    POST /transcribe  X-Model: short  → small.en Whisper, ~140 ms, no LLM
    POST /intent      → all-MiniLM-L6-v2 embedding match, ~5 ms, no LLM

  HEAVY PATH  (form-filling: addAppointment, reschedule, addPatient)
    POST /transcribe  X-Model: accurate → large-v3-turbo, ~260 ms
    POST /extract     → llama-cpp-python LLM, ~300 ms
                        runs ONLY on the final transcript, never on partials
                        handles name disambiguation + richer field extraction

The LLM loads in a background thread at startup so Whisper is never blocked.
If the GGUF file is missing, /extract returns 503 and the app falls back to
the phonetic matcher + regex (safe degradation, no crash).

To run by hand:
    .venv\\Scripts\\python server.py

POST /transcribe   body: 16 kHz mono PCM16 little-endian
                   header X-Hints: URL-encoded patient names, comma separated
                   header X-Model: fast | short | accurate (default)
                   -> {"text": "...", "ms": 123}
POST /extract      body: JSON — see extraction.py for the full contract
                   -> {"patientId": ..., "patientConfidence": ..., ...}
POST /intent       body: {"text": "...", "options": [{"id": "...", "phrases": [...]}]}
                   -> {"id": "...", "score": 0.72}
GET  /health       -> {"ok": true, "device": "cuda", "llm": "ready"|"loading"|"unavailable"}
"""

import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote

PORT = 8765
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


_add_cuda_dlls()

import numpy as np  # noqa: E402
from faster_whisper import WhisperModel  # noqa: E402


MODELS_DIR = Path(__file__).resolve().parent / "models"


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


models, device = _load()
embedder, tokenizer = _load_embedder()
embed(["warm up"])
# One lock per model: a live pass and a final pass can run side by side.
locks = {key: threading.Lock() for key in models}
print(f"Voice server ready on :{PORT} ({device})", flush=True)


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


def transcribe(
    pcm: bytes, hints: str, which: str, mode: str = "", context: str = ""
) -> str:
    audio = np.frombuffer(pcm, dtype=np.int16).astype(np.float32) / 32768.0
    if audio.size == 0 or float(np.sqrt(np.mean(audio * audio))) < SILENCE_RMS:
        return ""
    which = which if which in models else "accurate"
    names = f" Patients: {hints}." if hints else ""
    if mode == "dictation":
        # A consultation being written down: clinical words, and the end of
        # what was said before, so names and terms stay spelled the same.
        prompt = (
            "A doctor's consultation with a patient: complaints, pain score, "
            "duration, history, examination, range of motion, diagnosis, "
            "advice, exercises, remedy, potency, follow-up."
            + names
            + (f" {context[-300:]}" if context else "")
        )
    else:
        # The command words steer spelling ("Add appointment", not "At
        # appointment"); naming the patients gets Indian names right.
        # Names go last: Whisper keeps the end of a long prompt.
        prompt = (
            "Doctor's voice commands in a clinic app: add patient, book an "
            "appointment, reschedule, move, open, go to schedule, confirm, "
            "cancel, start session, start consultation, call next patient, "
            "mark done, paid. Date of birth, mobile, email, allergic to."
            + names
        )
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
        self._json({"ok": True, "device": device})

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

        # ── Fast path: Whisper transcription ─────────────────────────────────
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
