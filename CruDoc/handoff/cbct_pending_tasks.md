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

## Done and tested (2026-11-10) — Antigravity round 3

- **Two-copy 3D render** (`view3d.js`, `engine.js`): a light preview copy drawn while
  moving; a sharp copy drawn when still and faded in over the last moving frame.
- **Calibration** (`view3d.js`): at load, hidden behind the poster, the viewer measures
  which of five quality plans this machine can hold at full frame rate and uses that plan
  while moving. Debug hooks via `?debug`: `window.__cbct.tuning.plan` (0 = cheapest),
  `window.__cbct.debug3d()`, `window.__cbct.lod`, `window.__cbct.stillMs()`.
- **`lod.js`** new meaning: `window.__cbct.lod` is the level of the STILL picture (0 =
  preview only, last = full shared volume, no second copy).
- **Camera motion** (`motion.js`): wheel zoom glides and keeps the point under the cursor;
  Reset and gizmo letters (L R A P S I) turn the camera smoothly. Exports `slerp`,
  `basisOf`, `cameraQuat` with unit tests in `motion.test.js`.
- **Looks by scan kind** (`presets3d.js`): `meta.kind` = `dental` / `ct` / `mr`.
  Dental: Bone, Teeth, Teeth in bone, Skin + bone, X-ray, MIP.
  CT: Bone, Skin, Muscle + bone, Lungs, X-ray, MIP. MR: Tissue, MIP.
  Unit tests in `presets3d.test.js` covering all looks for all kinds.
- **"Smooth" slider** in 3D panel: `state.view3d.soft` (0–100, default 40), saved in
  `state.json`.
- **Packer** writes `meta.kind` and `meta.modality` (pack version 4): uses DICOM
  Modality (0008,0060) and Body Part Examined (0018,0015) tags, FOV size and spacing
  ratio. Dart tests updated.
- **Gate** (`radIsVolume`): also accepts CT/MR DICOM series with ≥ 30 equal-size slices.
  New gate tests added.
- **Wording**: chip says "3D viewer" (not "CBCT") for non-dental scans.
- **Shortcuts help sheet**: added "Click L R A P S I — 3D: turn to look from that side".
- **Smoke test** (A6): checks for "Teeth in bone" chip, label, Smooth slider, and gizmo
  letter click changes camera.
- **Docs** updated: README module map, `cbct_protocol.md` (new sections 7–9), this file.

## Open (Claude does next)

1. **Surface mesh for the moving picture**: bone/teeth turned into triangles once at load
   and drawn while moving; ray-cast only as the sharp still.
2. **Faster opening**: calibration adds ~2 s before the live picture on the small test
   scan (preview 2.5 s → 4.7 s). Measure fewer frames or remember the result.
3. **Long frame** when a sharper LOD level first appears at 1.5× screen scaling.
4. **Tablet check** on a real device; looking at the new looks on a real CBCT and CT.
5. **Smart dental help** (tooth numbering, nerve canal, AI findings draft): design first;
   needs a decision on where the AI runs and on patient-data rules.

## Not verified (needs the real app)

- Opening 3D from a real imported CBCT in the Windows app (WebView2), and the poster
  layer fade there. Nothing here could drive the Flutter window.
- A real scan's size and speed (400 × 400 × 400, 512 × 512 × 512): packing time, memory,
  the 3D poster ray march, 16-bit GPU textures (Cornerstone may fall back to float).
- iPad / Android tablet (touch gestures, memory, WebKit).
- Angle and Ellipse tools by hand (Length was driven; the other two use the same wiring).
