# CBCT 3D Viewer Protocol & Contract

This document specifies the contract and interface between the CruDoc Flutter application (`lib/features/radiology/cbct/`) and the embedded offline web-based 3D viewer (`cbct_viewer/`).

---

## 1. Page URL & Query Parameters

The Flutter application starts a local loopback HTTP server and opens the WebView navigating to `http://127.0.0.1:<port>/index.html` with query parameters.

### Query Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `base` | string | `'/dev/phantom/'` | URL base path to the scan pack on the loopback server, formatted as `/v/<token>/`. |
| `title` | string | `'CBCT'` | Patient name or study description displayed in the viewer header bar. |
| `chip` | string | `''` | Subtitle chip string containing modality, equipment details, scan date, and FOV dimensions (e.g. `CBCT · Maker Model · 09 Nov 2026 · 38 × 38 × 38 mm`). |
| `badge` | string | `''` | Badge tag passed by `cbct_viewer_screen.dart`: `"Anonymized"` when DICOM IdentityRemoved is YES, else `"On this device"`. |
| `device` | string | `'pc'` | Device classification (`'pc'` or `'tablet'`). Chooses which volume the page loads (`mid.i16` on a tablet when the pack has one, otherwise `full.i16`; `session.js`). The side panel starts closed when the window is narrower than 1100 px unless a saved state says otherwise (`session.js`, `applySavedUi`). |
| `first` | `'0'` \| `'1'` | `'0'` | First-open flag. The initial camera aim and "solidify" animation runs only when `first=1`, there are no saved cameras, and reduced motion is off (`session.js`, `open`). Otherwise, saved state/cameras are restored or cameras are fitted directly. |
| `reduced` | `'0'` \| `'1'` | `'0'` | Reduced motion flag. If `'1'` or if system `prefers-reduced-motion` matches, shortens animation and transition durations. |
| `debug` | flag | *none* | If present in query string, exposes global debug hooks on `window.__cbct` (`core`, `state`, `annotation`). |

*Note:* `cbct_viewer_screen.dart` passes `badge` ("Anonymized" when DICOM IdentityRemoved is YES, otherwise "On this device"). `debug` is supported by `src/main.js` for testing and diagnostic inspection.

---

## 2. Loopback Server Routes (`cbct_server.dart`)

The Flutter host runs an embedded `HttpServer` listening exclusively on loopback IPv4 (`127.0.0.1`). All requests receive security headers:
- `Cache-Control: no-store`
- `X-Content-Type-Options: nosniff`

Any path containing directory traversal sequences (`..` or `\`) immediately returns HTTP `404 Not Found`. Supported HTTP methods are strictly `GET` and `PUT` (other methods return `405 Method Not Allowed`). A PUT or GET with an unknown or revoked token, or for a pack folder that no longer exists, returns 404.

### Asset Route (`/` or `/<asset-path>`)

- Serves static pre-built viewer web assets bundled in Flutter `assets/cbct_viewer/`.
- Method: `GET` only (PUT returns `404 Not Found`).
- Maps MIME types: `.html` (`text/html`), `.js` (`text/javascript; charset=utf-8`), `.css` (`text/css; charset=utf-8`), `.json` (`application/json`), `.png` (`image/png`), `.ttf` (`font/ttf`), `.woff2` (`font/woff2`).

### Pack Routes (`/v/<token>/<file>`)

Each study session is registered under a cryptographically secure 32-byte base64url token.

#### GET /v/<token>/<file>
Permitted files for read operations:
- `meta.json` (metadata and geometry)
- `full.i16` (full resolution volume)
- `mid.i16` (intermediate resolution volume)
- `preview.i16` (downsampled factor-2 preview volume)
- `poster_axial.png` (middle axial slice poster)
- `poster_coronal.png` (middle coronal slice poster)
- `poster_sagittal.png` (middle sagittal slice poster)
- `poster_3d.png` (3D view poster)
- `state.json` (saved view and tool state)

Status codes:
- `200 OK`: File found and streamed with `Content-Type` and `Content-Length`.
- `404 Not Found`: Unknown token, file not in whitelist, or file does not exist on disk.

#### PUT /v/<token>/<file>
Permitted files for write operations:
- `state.json` (max size: 256 KB = 262,144 bytes)
- `poster_axial.png` (max size: 12 MB = 12,582,912 bytes)
- `poster_coronal.png` (max size: 12 MB)
- `poster_sagittal.png` (max size: 12 MB)
- `poster_3d.png` (max size: 12 MB)
- `snap_<1-9 digits>.png` matching regex `^snap_\d{1,9}\.png$` (max size: 12 MB)

Validation and write semantics:
- Written atomically to `<file>.tmp` before renaming to target filename.
- `state.json` payload is parsed as JSON; invalid JSON returns `400 Bad Request`.
- PNG files must begin with valid 8-byte PNG signature `[0x89, 0x50, 0x4E, 0x47, ...]`; otherwise returns `400 Bad Request`.
- Requests exceeding file size limits return `413 Request Entity Too Large`.
- Successful write returns `204 No Content`.

---

## 3. Web-to-Flutter Bridge Messages

The web page communicates with the native Flutter host using `window.flutter_inappwebview.callHandler('cbct', msg)`:

```javascript
post({ type: '<message_type>', ...fields });
```

### Message Types & Payloads

1. **`boot`**: Emitted once on initial script execution.
   - Fields: `{ type: 'boot', version: string }`
2. **`shown`**: Emitted when static poster layers are decoded and mounted, before 3D engine startup.
   - Fields: `{ type: 'shown' }`
3. **`preview`**: Emitted when the low-resolution preview volume is loaded and rendered.
   - Fields: `{ type: 'preview', ms: number }`
4. **`full`**: Emitted when the full resolution volume has completed streaming and swaps in.
   - Fields: `{ type: 'full', ms: number }`
5. **`timing`**: Performance timing milestones.
   - Fields: `{ type: 'timing', marks: { open, shown, preview, full } }`
6. **`snapshot`**: Emitted when user triggers key-image snapshot capture (via button or `S` key).
   - Fields: `{ type: 'snapshot', file: string, view: string }`
7. **`close`**: Emitted when user clicks the back button after state and posters are saved.
   - Fields: `{ type: 'close' }`
8. **`error`**: Emitted when engine or network initialization fails.
   - Fields: `{ type: 'error', message: string }`

---

## 4. Flutter Handling of Messages (`cbct_viewer_screen.dart`)

Flutter registers the JavaScript handler `cbct` via `controller.addJavaScriptHandler(handlerName: 'cbct', callback: _onMessage)`.

Handling per message type:
- **`close`**: Sets `_saved = true` and invokes `_leave()`. `_leave()` asks the web viewer to execute `window.CbctViewer.prepareClose()` (which is skipped if `_saved` is already true), and then pops the route via `Navigator.of(context).pop()`. For system back or Esc key navigation, a native Flutter `PopScope(canPop: false, onPopInvokedWithResult: ...)` also invokes `_leave()`, ensuring view state and posters are saved before popping.
- **`shown`**: Logs elapsed milliseconds since tap and calls `_hidePosters()`, transitioning out the native Flutter poster overlay to reveal the WebView canvas.
- **`preview`**: Logs elapsed milliseconds (`[cbct] tap->preview`).
- **`full`**: Logs elapsed milliseconds (`[cbct] tap->full`) and ensures native posters are hidden (`_hidePosters()`).
- **`snapshot`**: Asynchronously calls `saveCbctSnapshot(context: context, ref: ref, studyId: widget.studyId, packDir: dir, file: msg['file'], view: msg['view'])` to record the snapshot file into radiology study records.
- **`error`**: Calls `_hidePosters()` and sets `_error = msg['message']` to display an in-app error card (`RadNotConnected`).
- **`boot` / `timing`**: Ignored by Flutter (no case in `_onMessage`'s switch statement).

---

## 5. `state.json` Schema

Saved automatically via debounced autosave (2 s after state change) and upon viewer exit (`prepareClose()`):

```json
{
  "version": 1,
  "layout": "2x2",
  "focus": "axial",
  "panelOpen": true,
  "tool": "crosshair",
  "overlays": true,
  "contrast": {
    "preset": "bone",
    "low": -600,
    "high": 3000,
    "invert": false
  },
  "slab": {
    "mode": "thin",
    "thickness": 0
  },
  "view3d": {
    "preset": "bone",
    "threshold": 0,
    "opacity": 100,
    "cut": "off",
    "cutFlip": false
  },
  "cameras": {
    "axial": { "focalPoint": [0, 0, 0], "position": [0, 0, 100], "viewUp": [0, -1, 0], "parallelScale": 20 },
    "coronal": { "focalPoint": [0, 0, 0], "position": [0, -100, 0], "viewUp": [0, 0, 1], "parallelScale": 20 },
    "sagittal": { "focalPoint": [0, 0, 0], "position": [100, 0, 0], "viewUp": [0, 0, 1], "parallelScale": 20 },
    "threeD": { "focalPoint": [0, 0, 0], "position": [0, -200, 100], "viewUp": [0, 0, 1] }
  },
  "centre": [0, 0, 0],
  "posters": {
    "axial": { "kind": "canvas", "w": 400, "h": 300 },
    "coronal": { "kind": "canvas", "w": 400, "h": 300 },
    "sagittal": { "kind": "canvas", "w": 400, "h": 300 },
    "3d": { "kind": "canvas", "w": 400, "h": 300 }
  },
  "savedAt": "2026-11-09T12:00:00.000Z"
}
```

*Note on fields:* `cameras` and `centre` can be `null` (when saved before a volume was loaded). `posters` only lists views that were big enough to capture (any view hidden by the single-view layout is skipped because its canvas has no width). The 3D view is stored under the key `3d`, while MPR views are stored under `axial`, `coronal`, `sagittal`.

---

## 6. The Fit Rule Formula & Reference Cases

The fit rule guarantees that a cross-sectional plane of physical dimensions $u \times v$ (in millimeters) fits completely, centered without distortion, into a viewport of $W \times H$ pixels. The algorithm is implemented identically in JavaScript (`cbct_viewer/src/fit.js`) and Dart (`lib/features/radiology/cbct/cbct_fit.dart`).

### Mathematical Formula

Given:
- Viewport width $W$ (px) and height $H$ (px)
- Plane physical width $u$ (mm) and height $v$ (mm)

$$\text{aspect} = \frac{W}{H}$$

$$\text{parallelScale} = \max\left(\frac{v}{2}, \frac{u}{2 \times \text{aspect}}\right)$$

$$\text{pxPerMm} = \frac{H}{2 \times \text{parallelScale}}$$

$$\text{rectW} = u \times \text{pxPerMm}, \quad \text{rectH} = v \times \text{pxPerMm}$$

$$\text{rectX} = \frac{W - \text{rectW}}{2}, \quad \text{rectY} = \frac{H - \text{rectH}}{2}$$

Cornerstone3D cameras use `parallelScale` (half visible height in mm). The rendered poster / plane rectangle is centered at `(rectX, rectY)` with size `(rectW, rectH)`.

### Test Cases

1. **Wide Viewport ($W > H$) - Height Decides:**
   - Input: $W = 400$, $H = 300$, $u = 40$, $v = 40$
   - $\text{aspect} = 400 / 300 = 1.3333$
   - $\frac{v}{2} = 20$; $\frac{u}{2 \times \text{aspect}} = \frac{40}{2.6667} = 15 \implies \text{parallelScale} = 20$
   - $\text{pxPerMm} = 300 / 40 = 7.5$
   - Result: $\text{parallelScale} = 20$, $\text{pxPerMm} = 7.5$.

2. **Tall Viewport ($H > W$) - Width Decides:**
   - Input: $W = 300$, $H = 400$, $u = 40$, $v = 40$
   - $\text{aspect} = 300 / 400 = 0.75$
   - $\frac{v}{2} = 20$; $\frac{u}{2 \times \text{aspect}} = \frac{40}{1.5} = 26.6667 \implies \text{parallelScale} \approx 26.6667$
   - $\text{pxPerMm} = 400 / (2 \times 26.6667) = 7.5$
   - Result: $\text{parallelScale} = 26.6667$, $\text{pxPerMm} = 7.5$.

3. **Wide Plane in Square Viewport:**
   - Input: $W = 500$, $H = 500$, $u = 40$, $v = 20$
   - $\text{aspect} = 1.0$
   - $\frac{v}{2} = 10$; $\frac{u}{2 \times \text{aspect}} = 20 \implies \text{parallelScale} = 20$
   - $\text{pxPerMm} = 500 / 40 = 12.5$
   - $\text{rectW} = 40 \times 12.5 = 500$, $\text{rectH} = 20 \times 12.5 = 250$
   - Result: $\text{parallelScale} = 20$, $\text{pxPerMm} = 12.5$, $\text{rectW} = 500$, $\text{rectH} = 250$.
