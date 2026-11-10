# Antigravity task: 3D viewer v2 (any medical scan, tests, docs, dental arch, panoramic)

This whole file is your brief. Claude (the lead) reviews the result.
Updated 2026-11-10 (second version: surfaces, implant plan, panoramic functions added).

## ▶ DO NOW

Do A3 to A7, then B1 to B4, in order. Then run the Checks once. Then STOP at **GATE** and
report. A1 and A2 are already done (`src/presets3d.test.js`, `src/motion.test.js` exist and
pass): do not redo them.

## Rules

> Project: `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\CruDoc`. Web viewer source:
> `cbct_viewer/src/`. Flutter side: `lib/features/radiology/cbct/`.

**How to work:** write every task first, then run all Checks once at the end. Run slow
commands in the background and carry on. "STOP" inside a task means: skip that part, note
it in your report, carry on. Only the GATE line stops the run.

- **Files you must NOT change** (Claude owns them, tuned by measurement):
  `cbct_viewer/src/view3d.js`, `lod.js`, `motion.js`, `engine.js`, `session.js`,
  `surface.js`, `mesher.js`, `mesher.worker.js`, `plan.js`, `planning.js`, `assist.js`,
  `findings.js`, `presets3d.js`,
  `state.js`, `styles/viewer.css`, and `tests/perf.mjs`, `tests/look.mjs`, `tests/plan.mjs`.
  In `chrome.js` change only what a task says. If a test fails because of these files, do
  not "fix" them: report the failure with its output.
- Never run `npm ci` or `tool\build_cbct_viewer.ps1` (it half-deletes `node_modules` when
  any terminal is inside it). Build with `npx vite build` from `cbct_viewer/`.
- Never commit. No real patient scans. Do not touch files a task does not name.
- `pubspec.lock` shows as changed in git: leave it alone.
- Flutter UI text follows `.claude/rules/crudoc-ui.md` (tokens only, no hard-coded colours).
- Shell: heredocs with apostrophes break; write files with your file tool.

## What Claude built on 2026-11-10 (read before you start)

- **Surface 3D.** Bone, Teeth, Teeth in bone, Skin + bone (and CT Bone / Skin / Muscle,
  MR Tissue) are drawn as triangle meshes built in a worker (`surface.js`, `mesher.js`):
  rotation costs about 7 ms per frame. X-ray, MIP and CT Lungs are still ray-cast.
  Threshold and Smooth rebuild the mesh after the slider rests; Smooth = 0..3 smoothing
  passes. With `?debug`: `window.__cbct.debug3d()` gives `mesh` (true in surface mode),
  `tris`, `meshMs`, `grid`.
- **Implant plan** (`plan.js` geometry, `planning.js` UI), dental scans only. Right panel
  section "Implant plan": Nerve canal Right / Left, **Trace** (key **N**: each click in a
  slice view adds a point; Backspace removes the last), Undo point, Clear; Implants:
  **Add at crosshair**, chips "Implant 1..", Lower / Upper jaw, Diameter, Length,
  Tilt A–P, Tilt L–R, Move to crosshair, Delete, and the distance to the canal
  (green >= 2 mm, amber 1–2 mm, red < 1 mm). Drawn in the slice views and in 3D.
  Saved in `state.json` as `plan: { nerves: { right, left }, implants }` (world mm, LPS).
  Check: `npm run plan`.
- **Automatic help** (`assist.js`, no AI): Trace has **Auto-follow** (click start and end,
  it follows the canal between clicks); each implant shows bone width, height to the
  canal or sinus and its position against the crest; buttons **Suggest size** and
  **Seat at crest**. A panel section "Found automatically" boxes metal / very dense
  objects (labels M1, M2..) in the slice views and 3D; with `?debug`
  `window.__cbct.foundBoxes()` returns them.
- **Looks by kind of scan** (`presets3d.js`): `meta.kind` = `dental` (default), `ct`, `mr`.
- **Camera motion** (`motion.js`), gizmo letters turn the view; **Smooth** slider
  (`state.view3d.soft`, default 40).
- AI design (for reading only, not a task): `handoff/cbct_ai_design.md`.

## A3. Packer writes the kind of scan (Dart)

File: `lib/features/radiology/cbct/cbct_pack.dart`. Where `manufacturer` and `model` are
read from the first slice (search `DicomTag.manufacturer`), also read the Modality and
Body Part Examined tags. Look up the real tag names in the project's `DicomTag` class:
do not invent names; if a tag constant is missing, add it next to the others using the
standard numbers (Modality 0008,0060; Body Part Examined 0018,0015).
Then compute `kind`:
```
fovMm   = largest of dims[i] * spacing[i]
ratio   = largest spacing / smallest spacing
if modality == 'MR'                                   -> 'mr'
else if modality == 'CT' and (fovMm > 260 or ratio > 1.6
        or bodyPart is one of CHEST, ABDOMEN, PELVIS, SPINE, LSPINE, TSPINE, CSPINE,
           EXTREMITY, KNEE, SHOULDER, HIP, HEART)       -> 'ct'
else                                                  -> 'dental'
```
Write `'kind': kind` and `'modality': modality ?? ''` at the top level of `meta`. Bump
`cbctPackVersion` from 3 to 4. Extend `test/features/radiology/cbct/cbct_pack_test.dart`:
the existing synthetic scan gets `kind == 'dental'`. STOP if the packer has no access to
the modality without a large refactor: then write `kind` from fov and ratio only.

## A4. Let non-dental volume scans open in the 3D viewer (Flutter)

Find where the app decides a study can open in 3D (start at
`test/features/radiology/cbct/cbct_viewer_gate_test.dart` and
`lib/features/radiology/open_study.dart`). Today it accepts CBCT. Also accept any CT or MR
series with at least 30 slices of equal size. Add one test per new case to the gate test.
STOP (skip, report what you found) if the gate depends on vendor or cloud fields you do
not understand.

## A5. Wording: "3D viewer", not "CBCT", for non-dental scans

List with a search every user-facing string containing `CBCT` under `lib/features/radiology/`
(not code identifiers, not comments). For screens that can now show CT/MR (A4), change the
visible text to "3D viewer" / "3D". Keep "CBCT" where the screen is dental-only. Put the
before/after list in your report. Do not rename files, classes or folders.

## A6. Help sheet and smoke checks

1. `cbct_viewer/src/chrome.js`, the `SHORTCUTS` list: the row
   `['Click L R A P S I', '3D: turn to look from that side']` is already there. Change the
   first row to `['C P Z W N', 'Crosshair, pan, zoom, window / level, trace nerve']` and add
   after it `['Backspace', 'While tracing: remove the last nerve point']`.
2. `cbct_viewer/tests/smoke.mjs`: add checks (same style as the others):
   - the 3D chip row contains a chip with text `Teeth in bone`;
   - clicking it sets the 3D label (`.vp[data-id=threeD] small`) to `Teeth in bone`;
   - a slider row labelled `Smooth` exists in the panel;
   - panel sections whose `h3` text is `Implant plan` and `Found automatically` exist;
   - clicking `.gizmo circle` (use `{ force: true }`) changes
     `window.__cbct.core.engine.getViewport('threeD').getCamera().viewPlaneNormal`
     within 1.5 s.
3. Run `node tests/transitions.mjs`. Its Opening phase is known to FAIL (the open is now
   ~2 s and fits in ~3 screenshots). Do not change `src/` for it: report the numbers.

## A7. Docs

Update to match "What Claude built" above:
- `cbct_viewer/README.md` module map: add `presets3d.js`, `motion.js`, `surface.js`,
  `mesher.js` (+ worker), `plan.js`, `planning.js`, `assist.js`, `findings.js`, and
  (after Part B) `arch.js`, `panoramic.js`, `summary.js`, one line each; new one-line descriptions for `lod.js` (level of the
  ray-cast still picture; unused in surface mode) and `view3d.js`. Add the test commands
  `npm run plan` and `node tests/look.mjs`.
- `handoff/cbct_protocol.md`: `meta.kind`, `meta.modality`, pack version 4, `state.json`
  `view3d.soft` and `plan` (shape above), the `?debug` hooks
  (`__cbct.debug3d()`, `__cbct.meshStats`, `__cbct.tuning`, `__cbct.lod`).
- `handoff/cbct_pending_tasks.md`: a "2026-11-10" section listing "What Claude built" as
  done-and-tested-headless, and "Claude does next" below as open.

---

# Part B: dental arch, panoramic and cross-section (pure functions + tests)

No UI in this part (Claude adds the panoramic view to the screen afterwards). New files
only: `cbct_viewer/src/arch.js`, `arch.test.js`, `panoramic.js`, `panoramic.test.js`.
Use `node:test` / `node:assert`. Import geometry helpers from `./core.js`
(`worldToIndex(p, geo)`, `indexToWorld(ijk, geo)`, `axes(geo)`, `dot`, `sub`, `add`, `mul`,
`norm`, `cross`). `geo = { dims: [nx, ny, nz], spacing, origin, direction }`. Voxel
`(i, j, k)` is at index `i + j*nx + k*nx*ny`.

## B1. Find the arch: `arch.js`

`export function findArch(voxels, geo, teethValue)`; `voxels` Int16Array, `teethValue`
in stored units. Steps:
1. For every z slice count the voxels with value >= `teethValue`. Take the 20 % of slices
   around the slice with the highest count (the tooth band).
2. In that band, for every (x, y) column set a mask bit if any voxel is >= `teethValue`.
3. If fewer than 30 mask points: return `null` (no teeth found).
4. Fit `y = a*x*x + b*x + c` to the mask points by least squares (x, y in voxel indices;
   solve the 3x3 normal equations by hand, no library).
5. Return `{ points, zIndex, coefficients: [a, b, c] }`: 64 points along the curve from
   the smallest to the largest masked x, in world coordinates via
   `indexToWorld([x, y, zIndex], geo)`, where `zIndex` is the middle slice of the band.

Test with a synthetic 64x64x32 volume (identity direction, spacing 1, origin 0): value 0
everywhere, 2000 on voxels within 1.5 voxels of `y = 0.02*(x-32)^2 + 12` for z 12..18.
Assert the fitted `a` is within 0.004 of 0.02, the curve's lowest point is within 1.5
voxels of (32, 12), and an all-zero volume returns `null`.

## B2. Sampling and the arch path: in `panoramic.js`

1. `export function sampleLinear(voxels, geo, p)`: value at world point `p` by trilinear
   interpolation of the 8 neighbouring voxels (use `worldToIndex`); `null` outside the volume.
2. `export function archPath(points, stepMm, geo)`: the arch polyline re-sampled at equal
   arc length `stepMm` (linear between input points). Returns
   `{ points, normals, length }`: `normals[i]` = unit vector at right angles to the local
   tangent AND to `axes(geo).z` (so it lies in the axial plane), pointing to the side
   where the curve's centre of curvature is NOT (outward, toward the cheeks/lips). For a
   straight piece, use `cross(tangent, axes(geo).z)` normalised.

## B3. Panoramic and cross-section images: in `panoramic.js`

1. `export function panoramic(voxels, geo, arch, { stepMm = 0.25, thicknessMm = 10 } = {})`
   where `arch = archPath(...)`. Column `c` = arch point `c`. Row `r` runs from the top of
   the volume (superior) down: height = round(extent along `axes(geo).z` / stepMm).
   Pixel = mean of `sampleLinear` at `P + N*t + Z*zMm` for t from `-thicknessMm/2` to
   `+thicknessMm/2` in `stepMm` steps (skip `null` samples; a pixel with no samples gets
   the volume minimum). Return `{ width, height, data: Float32Array(width*height),
   mmPerPixel: stepMm, zTopMm }` with row-major data (row 0 = top).
2. `export function crossSection(voxels, geo, arch, sMm, { stepMm = 0.25, widthMm = 30 } = {})`:
   the plane at arc length `sMm` spanned by the normal `N` (horizontal, outward to the
   right of the image) and `Z` (up). Width = round(widthMm / stepMm) centred on the arch
   point; height as in panoramic; nearest arch point to `sMm` is fine. Return
   `{ width, height, data, mmPerPixel, origin, u, v }` where world(px, py) =
   `origin + u*px*mmPerPixel + v*py*mmPerPixel` (`u` = N, `v` = -Z, origin = top-left).

Tests (`panoramic.test.js`), synthetic 64x64x32 volumes, identity direction, spacing 1:
- `sampleLinear`: on a volume where value = i (the x index), `p = [10.5, 5, 5]` gives
  10.5; a point outside gives `null`.
- `archPath`: for points on a straight line of length 40, `length` is 40 +- 0.01, every
  normal is unit length and at right angles to z.
- `panoramic` of a volume filled with 7: every pixel is 7 (+- 1e-6); width equals
  `arch.points.length`.
- `panoramic` of the B1 synthetic arch volume, using `findArch`: the mean of rows for
  z 12..18 is far higher (> 5x) than the mean of rows for z 0..8.
- `crossSection` with a bright line along z at the arch point (value 1000 on the voxel
  column under arch point s): the brightest column of the image is within 2 px of the
  centre column.

## B4. Plan summary text: `summary.js` (+ `summary.test.js`)

`export function planSummary(plan, measures, found)` returns plain text (lines joined
with `
`) for the patient record. Inputs: `plan` = `state.plan` shape (see above);
`measures[i]` = the object `siteMeasure` (in `assist.js`) returns for implant i, or null;
`found` = the array `findDense` returns. Import `clearance` and `safety` from `./plan.js`.
Output, in this order, skipping empty parts:
```
Implant plan
Nerve canal: right traced (12 points), left not traced
Implant 1: 4.0 x 10.0 mm, lower jaw, tilt A-P 5°, L-R 0°
  Distance to the nerve canal 3.4 mm (safe)
  Bone width 6.8 mm near the crest, 7.1 mm at mid; height to the canal roof 12.0 mm
Found automatically: 2 metal or very dense objects (4.1 x 4.0 x 9.8 mm, 2.4 x 2.4 x 2.4 mm)
```
Numbers with one decimal; a missing number prints `–`; safety words: safe, close, too
close; no nerve traced -> `Distance to the nerve canal: not checked (no canal traced)`.
Tests: an empty plan gives only `Implant plan` and the nerve line `not traced` for both;
one implant with a known nerve gives the distance line with the right safety word
(build the nerve and implant like `src/plan.test.js` does); two found boxes give the
"Found automatically" line with both sizes. No UI: Claude adds a "Copy summary" button.

## Checks (once, at the end)

```powershell
cd C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\CruDoc\cbct_viewer
npx vite build
npm test
npm run smoke
npm run plan
npm run perf
node tests/look.mjs
cd ..
flutter analyze lib/features/radiology
flutter test test/features/radiology/cbct/cbct_pack_test.dart
flutter test test/features/radiology/cbct/cbct_viewer_gate_test.dart
```
Run the Flutter tests one at a time (two at once crash on sqlite3.dll).
Report: files changed, each command's last lines, the `first drag:` line from look.mjs,
the perf table, the B-test output, and what you skipped.

### GATE: stop here. Claude reviews.

---

## Claude does next (NOT for you)

1. Panoramic view on screen (from B1–B3) and a "Copy summary" button (B4): a fifth view or a layout mode, click on the
   panoramic to move the crosshair, cross-sections along the arch, implants drawn on it.
2. Real CBCT check of surface 3D (triangle count, noisy bone) and the implant plan.
3. Cut face in surface mode is a hollow shell: cap it.
4. Automatic tooth boxing and numbering along the arch (no AI), then AI help:
   decisions in `handoff/cbct_ai_design.md` (where the model runs, which model,
   licence), then the speed spike (M1).
