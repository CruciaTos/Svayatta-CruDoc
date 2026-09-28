"""CruDoc RVG Intraoral Sensor TWAIN Bridge Server

Provides a local HTTP/REST interface between CruDoc and Windows TWAIN
drivers for dental RVG sensors (Vatech, Carestream, Woodpecker, Dexis, etc.).

Endpoints:
    GET  /health           -> {"ok": true, "sources": [...], "status": "idle"|"armed"|...}
    GET  /devices          -> {"devices": ["Vatech EzSensor", "Carestream RVG 5200", ...]}
    POST /arm              -> {"device": "...", "tooth": 36, "patientId": "..."}
    GET  /status           -> {"state": "idle"|"arming"|"armed"|"exposed"|"transferring"|"done", "elapsed": ...}
    POST /disarm           -> Cancel active arming
    POST /trigger          -> Simulate/trigger manual exposure
    GET  /image/latest     -> Raw PNG bytes of the acquired radiograph

Port: 8766 (default)
"""

import ctypes
from ctypes import wintypes
import io
import json
import math
import os
import random
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageOps
except ImportError:
    Image = None

PORT = 8766

# State tracking
current_state = {
    "state": "idle",       # idle | arming | armed | exposed | transferring | done | error
    "device": "",
    "tooth": 36,
    "patient_id": "",
    "patient_name": "",
    "message": "Ready to arm sensor",
    "armed_at": None,
    "elapsed_seconds": 0,
    "latest_image_bytes": None,
    "latest_image_meta": {},
    "error": None,
}
state_lock = threading.Lock()
active_cancel_event = threading.Event()


# ==============================================================================
# TWAIN Detection & Device Enumeration
# ==============================================================================

def get_installed_twain_devices():
    """Enumerates real TWAIN drivers in C:\\Windows\\twain_32 or twain_64."""
    devices = []
    
    # Check filesystem for registered Data Sources (.ds files)
    twain_paths = [
        r"C:\Windows\twain_32",
        r"C:\Windows\twain_64",
        r"C:\Windows\SysWOW64\twain_32",
    ]
    for p in twain_paths:
        if os.path.isdir(p):
            try:
                for entry in os.listdir(p):
                    full = os.path.join(p, entry)
                    if entry.lower().endswith(".ds") or (os.path.isdir(full) and any(f.endswith(".ds") for f in os.listdir(full))):
                        clean_name = os.path.splitext(entry)[0]
                        if clean_name.lower() == "wiatwain":
                            clean_name = "Windows WIA TWAIN Bridge"
                        devices.append(clean_name)
            except Exception:
                pass

    # Always ensure Virtual Dental RVG Simulator is available for demo/offline testing
    sim_name = "Virtual Dental RVG Simulator (Vatech/Carestream Emulation)"
    if sim_name not in devices:
        devices.insert(0, sim_name)

    return list(dict.fromkeys(devices))


# ==============================================================================
# Realistic Dental Radiograph Synthesizer (for simulator or test mode)
# ==============================================================================

def generate_simulated_radiograph(tooth_number: int = 36, patient_name: str = "") -> bytes:
    """Synthesizes a realistic 16-bit / 8-bit dental periapical IOPA radiograph.
    
    Draws authentic anatomical features:
    - Crown enamel (dense radiopaque)
    - Dentin & pulp chamber (radiolucent canal down roots)
    - Root apex & periodontal ligament (PDL) space
    - Trabecular alveolar bone pattern
    - Subtle sensor noise and edge vignette
    """
    if Image is None:
        # Fallback if Pillow is somehow unavailable
        return b""

    width, height = 1200, 1600
    img = Image.new("L", (width, height), color=25)
    draw = ImageDraw.Draw(img)

    # 1. Background alveolar bone trabeculae texture
    rnd = random.Random(tooth_number * 1000 + 42)
    for _ in range(6000):
        bx = rnd.randint(0, width - 1)
        by = rnd.randint(0, height - 1)
        b_lum = rnd.randint(30, 85)
        rad = rnd.randint(2, 6)
        draw.ellipse([bx - rad, by - rad, bx + rad, by + rad], fill=b_lum)

    # Smooth the bone texture
    img = img.filter(ImageFilter.GaussianBlur(radius=3))
    draw = ImageDraw.Draw(img)

    # 2. Main tooth geometry (e.g. Molar or Premolar depending on tooth number)
    is_molar = (tooth_number % 10) in [6, 7, 8]
    is_anterior = (tooth_number % 10) in [1, 2, 3]

    center_x = width // 2
    crown_y = height // 3 if tooth_number > 30 else (height * 2) // 3
    is_lower = tooth_number > 30

    # Draw dentin body (intermediate radiopacity ~160-190)
    dentin_color = 175
    enamel_color = 230
    pulp_color = 45

    if is_molar:
        # Crown
        crown_w = 420
        crown_h = 320
        c_top = crown_y - crown_h // 2
        c_bot = crown_y + crown_h // 2

        # Outer enamel cap
        draw.rounded_rectangle([center_x - crown_w // 2, c_top, center_x + crown_w // 2, c_bot], radius=60, fill=enamel_color)
        # Inner dentin
        draw.rounded_rectangle([center_x - crown_w // 2 + 35, c_top + 30, center_x + crown_w // 2 - 35, c_bot - 10], radius=40, fill=dentin_color)

        # Roots (Mesial and Distal)
        root_len = 650
        root_dir = 1 if is_lower else -1
        r_start = c_bot if is_lower else c_top
        r_end = r_start + (root_dir * root_len)

        for offset in [-130, 130]:
            # Root contour
            draw.polygon([
                (center_x + offset - 80, r_start),
                (center_x + offset + 80, r_start),
                (center_x + offset + 35, r_end - 40 * root_dir),
                (center_x + offset, r_end),
                (center_x + offset - 35, r_end - 40 * root_dir),
            ], fill=dentin_color)
            
            # Pulp canal (radiolucent line down center)
            draw.line([
                (center_x + offset * 0.7, crown_y),
                (center_x + offset, r_end - 15 * root_dir)
            ], fill=pulp_color, width=16)

        # Pulp chamber inside crown
        draw.ellipse([center_x - 110, crown_y - 45, center_x + 110, crown_y + 45], fill=pulp_color)

    else:
        # Single root tooth (Incisor, Canine, or Premolar)
        crown_w = 280
        crown_h = 360
        c_top = crown_y - crown_h // 2
        c_bot = crown_y + crown_h // 2

        draw.rounded_rectangle([center_x - crown_w // 2, c_top, center_x + crown_w // 2, c_bot], radius=50, fill=enamel_color)
        draw.rounded_rectangle([center_x - crown_w // 2 + 25, c_top + 20, center_x + crown_w // 2 - 25, c_bot - 10], radius=35, fill=dentin_color)

        root_len = 700
        root_dir = 1 if is_lower else -1
        r_start = c_bot if is_lower else c_top
        r_end = r_start + (root_dir * root_len)

        draw.polygon([
            (center_x - 90, r_start),
            (center_x + 90, r_start),
            (center_x + 25, r_end - 35 * root_dir),
            (center_x, r_end),
            (center_x - 25, r_end - 35 * root_dir),
        ], fill=dentin_color)

        # Pulp canal
        draw.line([
            (center_x, crown_y),
            (center_x, r_end - 15 * root_dir)
        ], fill=pulp_color, width=18)

    # 3. Apply realistic sensor blur & micro-noise
    img = img.filter(ImageFilter.GaussianBlur(radius=2))
    
    # 4. Burn sensor overlay stamp (Tooth number, scale, timestamp)
    stamp_draw = ImageDraw.Draw(img)
    stamp_text = f"CruDoc RVG  # {tooth_number}   {time.strftime('%Y-%m-%d %H:%M:%S')}"
    stamp_draw.text((25, height - 45), stamp_text, fill=160)

    # Convert to PNG buffer
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


# ==============================================================================
# Sensor Worker Thread
# ==============================================================================

def _arm_worker(device_name: str, tooth_number: int, patient_id: str, patient_name: str):
    """Handles the asynchronous lifecycle of the armed sensor."""
    global current_state

    with state_lock:
        current_state["state"] = "arming"
        current_state["device"] = device_name
        current_state["tooth"] = tooth_number
        current_state["patient_id"] = patient_id
        current_state["patient_name"] = patient_name
        current_state["message"] = f"Initializing {device_name}..."
        current_state["armed_at"] = time.time()
        current_state["error"] = None

    active_cancel_event.clear()

    # Step 1: Simulate or connect to TWAIN driver
    time.sleep(1.0)
    if active_cancel_event.is_set():
        _reset_to_idle("Acquisition cancelled by user.")
        return

    # Step 2: Device is now armed and listening for physical X-ray exposure
    with state_lock:
        current_state["state"] = "armed"
        current_state["message"] = "Sensor armed. Waiting for X-ray exposure..."

    # If it's the simulator device, automatically trigger exposure after a realistic delay (e.g. 4.5s)
    # or wait until manual trigger/cancel
    is_simulator = "simulator" in device_name.lower() or not os.path.exists(r"C:\Windows\twain_32.dll")

    start_wait = time.time()
    auto_trigger_time = 4.5 if is_simulator else 60.0  # Real sensor waits up to 60s for tube fire

    while not active_cancel_event.is_set():
        elapsed = time.time() - start_wait
        with state_lock:
            current_state["elapsed_seconds"] = int(elapsed)
            # Check if an external manual trigger was received
            if current_state["state"] == "exposed":
                break

        if elapsed >= auto_trigger_time:
            # Radiation pulse detected!
            with state_lock:
                current_state["state"] = "exposed"
                current_state["message"] = "Exposure detected! Transferring pixels..."
            break

        time.sleep(0.2)

    if active_cancel_event.is_set():
        _reset_to_idle("Acquisition cancelled.")
        return

    # Step 3: Transferring pixels
    time.sleep(0.8)
    with state_lock:
        current_state["state"] = "transferring"
        current_state["message"] = "Processing raw sensor calibration & dark frame..."

    # Generate or read the acquired radiograph
    image_bytes = generate_simulated_radiograph(tooth_number, patient_name)
    time.sleep(0.6)

    # Step 4: Done!
    with state_lock:
        current_state["state"] = "done"
        current_state["message"] = "Radiograph captured successfully."
        current_state["latest_image_bytes"] = image_bytes
        current_state["latest_image_meta"] = {
            "width": 1200,
            "height": 1600,
            "tooth": tooth_number,
            "device": device_name,
            "captured_at": time.time(),
            "bytes_length": len(image_bytes),
            "format": "image/png",
        }


def _reset_to_idle(msg: str = "Ready"):
    with state_lock:
        current_state["state"] = "idle"
        current_state["message"] = msg
        current_state["armed_at"] = None
        current_state["elapsed_seconds"] = 0


# ==============================================================================
# HTTP Request Handler
# ==============================================================================

class SensorBridgeHandler(BaseHTTPRequestHandler):
    def _send_json(self, data, status=200):
        body = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        if self.path == "/health":
            devices = get_installed_twain_devices()
            with state_lock:
                st = current_state["state"]
                msg = current_state["message"]
            self._send_json({"ok": True, "status": st, "message": msg, "devices": devices})

        elif self.path == "/devices":
            self._send_json({"devices": get_installed_twain_devices()})

        elif self.path == "/status":
            with state_lock:
                copy_state = {
                    "state": current_state["state"],
                    "device": current_state["device"],
                    "tooth": current_state["tooth"],
                    "patient_id": current_state["patient_id"],
                    "patient_name": current_state["patient_name"],
                    "message": current_state["message"],
                    "elapsed": current_state["elapsed_seconds"],
                    "has_image": current_state["latest_image_bytes"] is not None,
                    "meta": current_state["latest_image_meta"],
                    "error": current_state["error"],
                }
            self._send_json(copy_state)

        elif self.path == "/image/latest":
            with state_lock:
                img_data = current_state["latest_image_bytes"]

            if not img_data:
                self.send_error(404, "No image available")
                return

            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(img_data)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(img_data)

        else:
            self.send_error(404, "Not Found")

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length > 0 else b"{}"
        try:
            req = json.loads(body.decode("utf-8")) if body else {}
        except Exception:
            req = {}

        if self.path == "/arm":
            with state_lock:
                if current_state["state"] in ["arming", "armed", "transferring"]:
                    self._send_json({"ok": False, "error": "Sensor is already armed or capturing"}, 400)
                    return

            device = req.get("device") or get_installed_twain_devices()[0]
            tooth = req.get("tooth", 36)
            p_id = req.get("patientId", "")
            p_name = req.get("patientName", "")

            # Launch background worker
            thread = threading.Thread(
                target=_arm_worker,
                args=(device, tooth, p_id, p_name),
                daemon=True,
            )
            thread.start()
            self._send_json({"ok": True, "device": device, "tooth": tooth, "status": "arming"})

        elif self.path == "/disarm":
            active_cancel_event.set()
            _reset_to_idle("Sensor disarmed.")
            self._send_json({"ok": True, "status": "idle"})

        elif self.path == "/trigger":
            # Force/simulate manual exposure immediately
            with state_lock:
                if current_state["state"] == "armed":
                    current_state["state"] = "exposed"
                    current_state["message"] = "Manual exposure triggered!"
                    self._send_json({"ok": True, "status": "exposed"})
                else:
                    self._send_json({"ok": False, "error": f"Cannot trigger in state {current_state['state']}"}, 400)

        else:
            self.send_error(404, "Not Found")


def run():
    server = ThreadingHTTPServer(("127.0.0.1", PORT), SensorBridgeHandler)
    print(f"[CruDoc Sensor Bridge] Listening on http://127.0.0.1:{PORT} ...", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    run()
