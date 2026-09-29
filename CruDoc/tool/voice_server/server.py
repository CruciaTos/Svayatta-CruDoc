"""Local speech-to-text server for the CruDoc voice demo.

Runs three Whisper sizes on the laptop's NVIDIA GPU (falls back to CPU) and
transcribes whatever audio the app posts:
  fast      base.en, ~60 ms: the live words while the doctor talks
  short     small.en, ~140 ms: the final pass of short commands ("confirm")
  accurate  large-v3-turbo, ~260 ms: the final pass of longer sentences

The app starts this itself
(lib/features/voice/services/speech_engine.dart); to run it by hand:

    .venv\\Scripts\\python server.py

POST /transcribe   body: 16 kHz mono PCM16 little-endian
                   header X-Hints: URL-encoded patient names, comma separated
                   header X-Model: fast | short | accurate (default)
                   -> {"text": "...", "ms": 123}
POST /intent       body: {"text": "...", "options": [{"id": "...", "phrases": [...]}]}
                   -> {"id": "...", "score": 0.72}: the option closest in
                   meaning (all-MiniLM-L6-v2 on the CPU, a few ms)
GET  /health       -> {"ok": true, "device": "cuda"}
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
MODELS = {
    "fast": ("base.en", "float16"),
    "short": ("small.en", "float16"),
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


def _load():
    try:
        loaded = {}
        for key, (name, compute) in MODELS.items():
            m = WhisperModel(name, device="cuda", compute_type=compute)
            list(m.transcribe(np.zeros(16000, dtype=np.float32), language="en")[0])
            loaded[key] = m
        return loaded, "cuda"
    except Exception as e:  # no GPU / CUDA libs: slower, still works
        print(f"GPU unavailable ({e}); using CPU", flush=True)
        m = WhisperModel("small.en", device="cpu", compute_type="int8")
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


def transcribe(pcm: bytes, hints: str, which: str) -> str:
    audio = np.frombuffer(pcm, dtype=np.int16).astype(np.float32) / 32768.0
    which = which if which in models else "accurate"
    # The command words steer spelling ("Add appointment", not "At
    # appointment"); naming the patients gets Indian names right. Names go
    # last: Whisper keeps the end of a long prompt.
    prompt = (
        "Doctor's voice commands in a clinic app: add patient, book an "
        "appointment, reschedule, move, open, go to schedule, confirm, "
        "cancel. Date of birth, mobile, email, allergic to."
        + (f" Patients: {hints}." if hints else "")
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
        return " ".join(s.text.strip() for s in segments).strip()


class Handler(BaseHTTPRequestHandler):
    def _json(self, obj):
        body = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self._json({"ok": True, "device": device})

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
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
        pcm = body
        hints = unquote(self.headers.get("X-Hints", ""))
        which = self.headers.get("X-Model", "accurate")
        t0 = time.perf_counter()
        text = transcribe(pcm, hints, which) if pcm else ""
        self._json({"text": text, "ms": int((time.perf_counter() - t0) * 1000)})

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
