# CBCT 3D viewer: status and what's left (updated 2026-11-09, evening)

Tap 3D on a CBCT study (PC or tablet) and the viewer opens inside CruDoc: Axial / 3D /
Coronal / Sagittal with linked crosshairs. Spec: `handoff/cbct_3d_viewer_build_guide.md`;
look: `handoff/cbct_reference.png`; web/Flutter contract: `handoff/cbct_protocol.md`
(being written by Antigravity, see below).

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

## Not verified (needs the real app)

- Opening 3D from a real imported CBCT in the Windows app (WebView2), and the poster
  layer fade there. Nothing here could drive the Flutter window.
- A real scan's size and speed (400 x 400 x 400, 512 x 512 x 512): packing time, memory,
  the 3D poster ray march, 16-bit GPU textures (Cornerstone may fall back to float).
- iPad / Android tablet (touch gestures, memory, WebKit).
- Angle and Ellipse tools by hand (Length was driven; the other two use the same wiring).
- Dragging the histogram handles and the slice scrollbar by hand.

## Still to build

1. **Crosshair look from the reference**: filled dots and hollow rings that are always
   visible (the Cornerstone tool shows its own handles on hover only).
2. **WebView warm-up / keep-alive** (guide Step 16): needs a spike on Windows WebView2
   with flutter_inappwebview 6.1.5, then timing on PC, iPad, Android tablet.
3. **Tablet memory**: confirm what the 16-bit option does on iPad; adjust the caps.
4. Save 3D measurements to the study (decision G6 = later).
5. Roadmap features: `handoff/cbct_roadmap.md`.

## Antigravity (`handoff/antigravity_cbct_support.md`)

Round 1 is done and reviewed by Claude: unit tests (19 of 19 pass with `npm test`), phantom
generator, smoke (all pass) and responsive (30 of 30) scripts, three Dart test files, the
analyzer fix. Its STOPs on the cloud-download hook and the Settings cache label were right
(no study-level "download finished" point; no screen lists the caches), so cloud-fetched
CBCTs are packed on first open. Round 2 is written (paste the whole file): fix the wrong
statements found in `docs/cbct_3d_viewer_guide.md`, `handoff/cbct_protocol.md` and the
README module map, plus a poster-layer widget test.

## Real-data check (2026-11-09)

A public torso CT (107 slices, 512 x 512, Zenodo 18225140, kept in
`C:\Users\Soham\Downloads\cbct_test_dicom\`) packs in 7.7 s and renders correctly in the
viewer in headless Edge (full volume on screen at 3.7 s). Not yet opened in the Windows app.
