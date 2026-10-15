
import os
import site
from pathlib import Path

dll_handles = []
dll_dirs = []

for site_dir in site.getsitepackages():
    nvidia_dir = Path(site_dir) / "nvidia"

    for package in ("cublas", "cudnn"):
        dll_dir = nvidia_dir / package / "bin"

        if dll_dir.is_dir():
            dll_dirs.append(str(dll_dir))
            dll_handles.append(os.add_dll_directory(str(dll_dir)))

# Make the NVIDIA DLL folders visible to Windows
os.environ["PATH"] = os.pathsep.join(dll_dirs) + os.pathsep + os.environ["PATH"]

# Import only after configuring the DLL paths
from faster_whisper import WhisperModel

print("Loading Whisper Large V3 Turbo...")

model = WhisperModel(
    "turbo",
    device="cuda",
    compute_type="float16"
)

print("Model loaded successfully!")

segments, info = model.transcribe(r"C:\Users\OMKAR PASHTE\Documents\GitHub\Svayatta-CruDoc\CruDoc\WhatsApp Audio 2026-10-12 at 02.39.38.mp4", beam_size=5)

print(f"Detected language: {info.language}")

for segment in segments:
    print(segment.text)
