"""Pre-download the Whisper models the voice server uses, for offline use.

Run once (needs internet, ~2.3 GB total):
    .venv\\Scripts\\python download_models.py            # all three
    .venv\\Scripts\\python download_models.py base.en    # just one

Models land in tool/voice_server/models/faster-whisper-<name>/ (git-ignored).
server.py loads from there when present, otherwise falls back to the
Hugging Face cache (auto-download on first run).
"""

import sys
from pathlib import Path

from huggingface_hub import snapshot_download

MODELS = {
    "base.en": "Systran/faster-whisper-base.en",
    "small.en": "Systran/faster-whisper-small.en",
    "large-v3-turbo": "mobiuslabsgmbh/faster-whisper-large-v3-turbo",
}
# Embedding model used by /intent.
EMBEDDER = "sentence-transformers/all-MiniLM-L6-v2"

ROOT = Path(__file__).resolve().parent / "models"


def main():
    wanted = sys.argv[1:] or list(MODELS)
    for name in wanted:
        if name not in MODELS:
            sys.exit(f"Unknown model '{name}'. Choose from: {', '.join(MODELS)}")
        dest = ROOT / f"faster-whisper-{name}"
        print(f"-> {MODELS[name]}  ->  {dest}", flush=True)
        snapshot_download(MODELS[name], local_dir=dest)
    if not sys.argv[1:]:
        # Cached in the normal HF cache, which server.py reads via hf_hub_download.
        print(f"-> {EMBEDDER} (HF cache)", flush=True)
        snapshot_download(EMBEDDER, allow_patterns=["tokenizer.json", "onnx/model.onnx"])
    print("Done.")


if __name__ == "__main__":
    main()
