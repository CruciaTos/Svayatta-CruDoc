# CBCT 3D viewer: what's left, sorted by difficulty (do top to bottom)

**Already working** (2026-11-09): tap 3D opens the viewer inside CruDoc. DICOM slices are
packed once into a volume file, a local server hands it to the WebView, and the page shows
Axial / 3D / Coronal / Sagittal with linked crosshairs, contrast and 3D presets, cut at
crosshair and Reset. Tested on a synthetic scan in Edge, plus the packer test.
Not yet tried on a real scan inside the app.

Source of truth for the look and rules: `handoff/cbct_3d_viewer_build_guide.md` (Parts A-C)
and `handoff/cbct_reference.png`. Cornerstone gotchas are in the memory note `cbct-viewer-build`.

## Tier 1: easy (small UI or wiring, low risk)

| # | Task | Where |
|---|---|---|
| 1 | Bundle Geist fonts (done: Geist; Geist Mono still uses the system mono) | `cbct_viewer/public/fonts`, `viewer.css` |
| 2 | Hide the 3D buttons on phones (`canOpen3d`: not web, shortest side >= 600) | new `cbct_device.dart`, `worklist_screen.dart`, `viewer_screen.dart` |
| 3 | **Done (2026-11-09):** Invert toggle and editable Width / Level boxes in the status bar, two-way with window drags. Still to do: the sliders, once the right panel exists | `main.js` |
| 4 | **Partly done:** R, H, F, ?, Esc and 1-5 work, with the help sheet. Still to do: C P Z W L A E (needs the toolbar tools, task 10) and ] (needs the panel) | `main.js` |
| 5 | **Done:** 2 x 2, 1 + 3 and single layouts, maximise and reset buttons on each view, double-click | `main.js`, `viewer.css` |
| 6 | Right panel (CONTRAST / SLAB / 3D VIEW) and its show/hide slide: not built yet | `main.js`, `viewer.css` |
| 7 | Server and fit-maths tests (Dart + `node --test`) | `test/features/radiology/cbct/`, `src/fit.js` |

## Tier 2: medium (Cornerstone events or new maths)

| # | Task |
|---|---|
| 8 | Orientation letters (A3.8), info overlay (slice mm, W/L, zoom), scale bar, slice scrollbar |
| 9 | Status bar readout: mouse position in mm and voxel value |
| 10 | Toolbar tools: Pan, Zoom, Window/Level, Length, Angle, Ellipse ROI, with styling |
| 11 | Slab: Thin, MIP, Mean, MinIP + thickness (Cornerstone uses half-thickness; see notes) |
| 12 | 3D panel: Skin + bone preset, Threshold and Opacity sliders |
| 13 | 3D gizmo and plane outlines; click on the 3D to place the crosshair (ray march) |
| 14 | Histogram with ramp and draggable window handles, landmark labels |
| 15 | Snapshot (S) saved as a key image on the study |
| 16 | Pack on import and after cloud download, with queue and `failed.json` (`CbctStore`) |
| 17 | JPEG 2000 CBCT studies (the 3D gate still needs uncompressed files) |

## Tier 3: hard (cross-layer, or needs real devices)

| # | Task |
|---|---|
| 18 | Preview-then-full loading (`preview.i16`, swap keeping cameras, window and slab) |
| 19 | Posters and instant first frame (packer plane sampling + PNG, web image layer, Flutter poster layer) |
| 20 | Saved view state (`state.json`, canvas capture on close, restore before the first render) |
| 21 | Crosshair look from the reference: filled dots, hollow rings, oblique labels |
| 22 | Warm-up of the WebView (keep-alive) and timing on PC, iPad, Android tablet |
| 23 | Tablet memory (16-bit GPU textures are not guaranteed), solidify animation, reduced motion |

## Tier 4: needs you, or later

- Try a real CBCT import on the PC, then an iPad / Android tablet (nothing here can do that).
- Save 3D measurements to the study (decision G6 = later).
- Roadmap items: panoramic from CBCT, nerve canal, airway, implant planning, STL / GIF export.
