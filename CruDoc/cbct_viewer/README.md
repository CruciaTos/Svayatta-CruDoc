# CruDoc CBCT Viewer

The four-panel CBCT viewer (Axial, 3D, Coronal, Sagittal) that CruDoc shows in a WebView on Windows PCs and tablets. Built with Vite and Cornerstone3D, it operates fully offline with instant poster pictures and progressive volume streaming.

The whole brief and the step-by-step plan live in `handoff/cbct_3d_viewer_build_guide.md`; the look to match is `handoff/cbct_reference.png`.

## Commands

```powershell
cd cbct_viewer
npm ci            # install the exact pinned versions from package-lock.json
npm run phantom   # generate the synthetic jaw phantom in dev/phantom/
npm run dev       # dev server; open http://localhost:5173/?base=/dev/phantom/&debug=1
npm test          # runs node --test "src/*.test.js"
npm run smoke     # run the Playwright smoke test against the built assets
npm run shot -- 0 # capture a screenshot of the viewer
npm run responsive # run layout checks across desktop, laptop, and tablet viewports
```

`?debug` in the page URL exposes `window.__cbct` (the engine state and the annotation store) for the test scripts.

Or, from the project root: `powershell -File tool\build_cbct_viewer.ps1` (runs `npm ci` + `npm run build` and lists the output).

**The build output in `assets/cbct_viewer/` is committed**, so the Flutter app builds on a machine without Node. Rebuild it after every change to this folder.

## Module Map (`cbct_viewer/src/`)

- `chrome.js`: All the HTML: top bar, viewport frames, right panel, status bar, help sheet. Reads and writes the store only; engine and overlays fill the frames.
- `core.js`: Shared engine-side singleton plus the geometry helpers every module needs. Written by engine.js; read by overlays, 3D, session.
- `core.test.js`: Unit tests for geometry helpers, coordinate conversions, bounding box corners, and voxel lookups.
- `engine.js`: Cornerstone3D: rendering engine, the four viewports, the volume on screen, tools, and applying the store's contrast / slab / tool to the images. Also exposes `setFine3d` for the two-copy (moving / still) render pipeline.
- `fit.js`: The one fit rule, shared with Dart (`lib/features/radiology/cbct/cbct_fit.dart`). A viewport of W x H px showing a plane of u x v mm: the whole plane fits, centred; parallelScale is half the visible height in mm (Cornerstone's unit).
- `fit.test.js`: Unit tests for camera fitting.
- `icons.js`: Stroke icons from Lucide (ISC licence).
- `lod.js`: Level-of-detail manager. `window.__cbct.lod` is the level of the STILL picture: 0 = only the light preview copy, last = the slice views' own full volume (shared, no second copy).
- `main.js`: Viewer entry point: mounts chrome, boots Cornerstone3D engine, bridges messages to Flutter, and handles URL query parameters.
- `motion.js`: Camera animation helpers — `flyTo()` turns/zooms the camera along the shortest arc (used by gizmo letters and Reset), `smoothZoom()` replaces wheel notch-zoom with a glide that keeps the cursor point in place. Exports `slerp`, `basisOf`, `cameraQuat` for unit tests.
- `orientation.js`: Orientation letters for a view's four edges (guide A3.8). World axes are DICOM LPS: +x Left, +y Posterior, +z Superior.
- `orientation.test.js`: Unit tests for orientation letters.
- `overlays.js`: The numbers and letters around the slice views: orientation letters, slice / window / zoom lines, scale bar, slice scrollbar, and the status-bar readout.
- `presets3d.js`: Transfer-function "looks" for the 3D viewport, one family per scan kind (`dental`, `ct`, `mr`). Pure data functions — `buildLook`, `presetsFor`, `validPreset`, `presetLabel`, `scanKind` — no GPU needed; tested without a browser.
- `session.js`: How a scan gets on screen without the doctor ever seeing a blank panel: poster pictures first, a small preview volume next, the full volume last, each swap hidden behind a snapshot that fades; also saved view state, loopback server calls, and snapshots.
- `shims/events.js`: Tiny stand-in for the Node module `events`, which vtk.js needs at load.
- `shims/url.js`: Tiny stand-in for the Node module `url`, which vtk.js needs at load.
- `state.js`: One small store. The UI writes what the user sets; the engine applies it and writes back what it learns (window/level drags, hovered position...); `set()` merges one level deep for object values and notifies once, synchronously.
- `state.test.js`: Unit tests for store mutations, subscriptions, window presets, and preset matching.
- `styles/tokens.css`: Design tokens (colors, typography, spacing).
- `styles/viewer.css`: All page styling for the viewer layout, chrome, viewports, panels, and overlays.
- `view3d.js`: The 3D viewport: transfer-function presets (from `presets3d.js`), the two-copy moving/still pipeline (light copy while moving, sharp copy on still with fade-in), cut at crosshair, the orientation gizmo, the three plane outlines and click-to-place.

## Pack Format

A pack folder contains the pre-processed volume data and preview images for one CBCT study:
- `meta.json`: Scan geometry, volume manifests, display presets, CT landmarks, poster filenames, and device info.
- `full.i16`: Full-resolution raw voxel volume stored as 16-bit signed integers (little-endian).
- `preview.i16`: Factor-2 box-averaged preview volume for rapid first display while full data loads.
- `mid.i16`: Optional intermediate-resolution volume used on tablet devices.
- `poster_axial.png`: Grayscale 8-bit PNG poster of the middle axial slice (Bone window, anterior on top).
- `poster_coronal.png`: Grayscale 8-bit PNG poster of the middle coronal slice (Bone window, superior on top).
- `poster_sagittal.png`: Grayscale 8-bit PNG poster of the middle sagittal slice (Bone window, superior on top).
- `poster_3d.png`: Grayscale poster image for the 3D viewport.
- `state.json`: Saved layout, window/level, slab, 3D parameters, camera matrices, and center.
- `snap_<n>.png`: Saved key-image snapshots.

### `meta.json` Fields Read by the Viewer

- `packVersion`: Format version integer (`2`).
- `seriesKey`: Unique identifier for the series.
- `source`: `{ fingerprint }` ensuring volume cache validity against source DICOM slices.
- `geometry`:
  - `dims`: `[nx, ny, nz]` volume dimensions in voxels.
  - `spacing`: `[sx, sy, sz]` voxel spacing in millimeters.
  - `origin`: `[ox, oy, oz]` 3D origin in world coordinates (DICOM LPS).
  - `direction`: 9-element array representing the 3x3 orientation direction cosine matrix.
- `volumes`:
  - `full`: `{ file, dims, spacing, origin }` path and geometry for full resolution volume.
  - `preview`: `{ file, factor, dims, spacing, origin }` path and geometry for preview volume.
  - `mid`: `{ file, dims, spacing, origin }` (or `null`) intermediate volume for tablets.
- `posters`: `{ axial, coronal, sagittal, threeD }` filenames of the static 2D poster images.
- `values`:
  - `min`, `max`: Minimum and maximum voxel values.
  - `padValue`: Value used for voxels outside the reconstructed cylinder (e.g. `-1000`).
  - `valueOffset`: Value offset applied such that `stored = real - valueOffset`.
- `landmarks`: Anatomical CT reference values (`air`, `soft`, `bone`, `teeth`, `metal`).
- `presets`: Map of named window presets (`bone`, `teeth`, `soft`, `fineBone`, `full`), each defining `{ low, high }` thresholds in real units.
- `device`: `{ manufacturer, model }` device identification.

## Rules

- **Offline.** No CDN, no web fonts, no analytics, no network calls except to the
  app's own loopback server. `index.html` carries a Content-Security-Policy
  (`connect-src 'self'`) that enforces it. Fonts live in `public/fonts/`.
- **No real patient scans** in code, tests, logs, screenshots or git. Tests use
  the synthetic jaw phantom (patient `TEST^PHANTOM`).
- **Exact versions.** Dependencies are pinned without `^`. Cornerstone `core`
  and `tools` share one version, and `@kitware/vtk.js` is the version Cornerstone
  depends on (`npm ls @kitware/vtk.js` must show a single copy).
- **No DICOM parsing here.** The app sends raw voxels, so there is no
  `dicom-image-loader`, `dicom-parser` or codec.
- **Stable output names**, no hashes (`a/main.js`), because Flutter lists asset
  folders and hashes would leave stale files.
