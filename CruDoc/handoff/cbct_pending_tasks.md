# CBCT 3D viewer: status and what's left (updated 2026-11-10, evening)

Tap 3D on a CBCT study (PC or tablet) and the viewer opens inside CruDoc: Axial / 3D /
Coronal / Sagittal with linked crosshairs. Spec: `handoff/cbct_3d_viewer_build_guide.md`;
look: `handoff/cbct_reference.png`; web/Flutter contract: `handoff/cbct_protocol.md`.

## Done and tested (headless Edge on a synthetic scan, plus Dart tests)

- **Packer** (Dart, background isolate): one volume + a small preview + optional mid
  (tablets) + four poster PNGs + `meta.json`, pack format v2. Tests: order after
  shuffle, geometry, landmarks, preview dims/origin, poster orientation.
- **Loopback server**: token per open, GET/PUT whitelists, size and PNG checks (tests).
- **Screen**: pack-on-demand with progress, WebView, back/Esc/system-back save the view
  first (posters + state), "Anonymized / On this device" badge, key-image snapshot save,
  poster layer while the page boots, phone message, JPEG 2000 gate.
- **Store**: one pack at a time, priority bump, failures remembered per app version,
  enqueue after import (tests with a fake packer).
- **Viewer page** (all in `cbct_viewer/src/`): top bar + tools (C P Z W L A E), layouts,
  right panel (contrast presets, histogram with draggable window, level/width, invert,
  slab Thin/MIP/Mean/MinIP + thickness, 3D presets incl. Skin + bone, threshold,
  opacity, cut at crosshair + flip), orientation letters, slice/window/zoom lines, scale
  bar, slice scrollbar, status readout, 3D gizmo + plane outlines + crosshair dot,
  click-to-place, Length/Angle/Ellipse measurements, key-image snapshot, help sheet,
  all shortcuts, preview then full loading with the focus-pull swap, posters then live,
  saved view state and restore, first-open "solidify", reduced motion, offline CSP.
  Browser smoke test: 30 checks pass; re-open/restore test passes.

## Done and tested (2026-11-10) — Surfaces, implant plan & panoramic foundations

- **Surface 3D** (`surface.js`, `mesher.js`, `mesher.worker.js`): Bone, Teeth, Teeth in bone,
  Skin + bone (and CT Bone / Skin / Muscle, MR Tissue) are drawn as triangle meshes
  built in a web worker using marching cubes; rotation costs ~7 ms per frame. X-ray,
  MIP and CT Lungs remain ray-cast. Threshold and Smooth rebuild the mesh after the
  slider rests (Smooth = 0..3 smoothing passes). With `?debug`, `window.__cbct.debug3d()`
  returns `{ mesh: true, tris, meshMs, grid }`.
- **Implant plan** (`plan.js` geometry, `planning.js` UI, dental scans only): Right panel
  section "Implant plan": Nerve canal Right / Left, Trace (key N: clicks in slice view
  add points; Backspace removes the last), Undo point, Clear; Implants: Add at crosshair,
  chips "Implant 1..", Lower / Upper jaw, Diameter, Length, Tilt A–P, Tilt L–R, Move to
  crosshair, Delete, and distance to canal (green ≥ 2 mm, amber 1–2 mm, red < 1 mm).
  Drawn in slice views and 3D. Saved in `state.json` under `plan: { nerves: { right, left }, implants }`
  (world mm, LPS). Tested via `npm run plan`.
- **Automatic help** (`assist.js`, no AI): Trace Auto-follow follows the canal between
  clicks; each implant shows bone width, height to canal/sinus and position against crest;
  buttons "Suggest size" and "Seat at crest". Panel section "Found automatically" boxes
  metal / very dense objects (M1, M2..) in slice views and 3D; with `?debug`,
  `window.__cbct.foundBoxes()` returns them.
- **Scan kind and 3D looks** (`presets3d.js`): `meta.kind` = `dental` (default), `ct`, `mr`.
- **Camera motion** (`motion.js`): gizmo letters turn view smoothly, wheel zoom glides.
- **Smooth slider**: `state.view3d.soft` (default 40).
- **Packer** (Dart): writes `meta.kind` and `meta.modality`, pack version 4.
- **Viewer gate**: accepts CT/MR DICOM series with ≥ 30 slices of equal size.
- **Dental arch, panoramic and cross-sections** (`arch.js`, `panoramic.js`, pure functions):
  tooth-band arch detection, curve fitting, linear voxel interpolation, arch polyline
  resampling with outward normals, panoramic generation, curved cross-sections.
- **Plan summary** (`summary.js`): plain text report with nerve canal status, implant
  specifications, clearances, bone widths, and dense object detection.

## Open (Claude does next)

1. **Panoramic view on screen** (from B1–B3) and a "Copy summary" button (B4): a fifth view
   or a layout mode, click on the panoramic to move the crosshair, cross-sections along the
   arch, implants drawn on it.
2. **Real CBCT check** of surface 3D (triangle count, noisy bone) and the implant plan.
3. **Cut face in surface mode** is a hollow shell: cap it.
4. **Automatic tooth boxing and numbering** along the arch (no AI), then AI help: decisions
   in `handoff/cbct_ai_design.md` (where the model runs, which model, licence), then the
   speed spike (M1).

## Not verified (needs the real app)

- Opening 3D from a real imported CBCT in the Windows app (WebView2), and the poster
  layer fade there. Nothing here could drive the Flutter window.
- A real scan's size and speed (400 × 400 × 400, 512 × 512 × 512): packing time, memory,
  the 3D poster ray march, 16-bit GPU textures (Cornerstone may fall back to float).
- iPad / Android tablet (touch gestures, memory, WebKit).
- Angle and Ellipse tools by hand (Length was driven; the other two use the same wiring).
