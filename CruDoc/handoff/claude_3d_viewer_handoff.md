# Handoff: 3D viewer v2 (for the next Claude session, any account)

Written 2026-11-10 by the session that did the work below. Read this file first, then
`handoff/antigravity_3d_viewer_v2.md` (the labour brief) and `cbct_viewer/src/view3d.js`.

## To start the next session, paste this

> Read `CruDoc/handoff/claude_3d_viewer_handoff.md` and continue from "Next after
> surfaces". Check usage first and stop at 60 % of the 5-hour limit.

Surface-only 3D was built by the second session on 2026-11-10: see "Surface-only 3D
(DONE)" near the end. Everything is still uncommitted.

## What the user wants

- The 3D viewer smooth and light on an ordinary doctor's laptop or a tablet. "3D is just
  for viewing": lower detail is fine, stutter is not.
- State of the art look (shading, smoothing), for any medical scan, not only dental.
- Smart dental help later (teeth highlighting, gums, detection, AI assistance).
- Smooth animations and transitions everywhere ("the illusion of peak operations").
- Claude is the architect and does the hard parts; Antigravity (Gemini 3.8) does the
  labour from a brief file the user pastes whole.

## How the user works (follow these)

- Check plan usage (`get_usage`) after every build-and-test cycle. Stop cleanly at about
  60 % of the 5-hour limit or 77 % weekly. This session ran 6 % -> 84 % in one turn: do
  not repeat that. Read files in parts, keep test output short (`grep`/`tail`).
- Cost-sensitive: do the work directly, no extra tests, research or documents unless asked.
- Batch edits per phase, one build and check per batch.
- Commit only when asked. Nothing from this session is committed.
- Plain, simple English in replies. Say plainly what was not verified.
- Antigravity briefs: one standalone file, "▶ DO NOW" on top, exact paths and snippets,
  GATE lines are the only stops.

## State of the code (uncommitted, on top of commit d5b2236, branch main)

Changed: `cbct_viewer/src/` `view3d.js` `lod.js` `engine.js` `session.js` `chrome.js`
`state.js` `main.js` `styles/viewer.css`, `cbct_viewer/tests/perf.mjs`, and the built
`assets/cbct_viewer/a/main.js` + `main.css`.
New: `cbct_viewer/src/presets3d.js`, `cbct_viewer/src/motion.js`,
`cbct_viewer/tests/look.mjs`, `handoff/antigravity_3d_viewer_v2.md`, this file.
`pubspec.lock` also shows as changed: not from this work, leave it.

Verified on the final build: `npm test` 19 pass, `npm run smoke` ALL PASS (30 checks),
`node tests/look.mjs` first drag 0 frames over 50 ms at 1x.
NOT verified: the look of the new presets and the Smooth slider (pictures are in
`cbct_viewer/tests/out/look-*.png`, nobody looked at them), `npm run perf` and
`node tests/transitions.mjs` on the final build, the real Windows app, any tablet, any
real dental CBCT. Antigravity has not been given the brief yet.

## What was built and how it works

1. **Two copies in the 3D view.** `engine.js`: `held = { mpr, fast, fine }`.
   `showVolume(..., views)` puts the small `preview` volume on the 3D view as the light
   copy (first actor). `setFine3d(level)` adds a hidden second actor (uid `cbctFine`):
   `{ data, geo }` for an in-between level, or `'slices'` to borrow the slice views'
   volume (shared GPU texture, no second upload).
2. **Moving and still** (`view3d.js`). `lowerQuality()` is called by anything that moves
   the picture (pointer down, wheel, camera flight, sliders) and shows the current plan;
   `sharpenSoon(ms)` -> `settle()` shows the sharp copy and fades a snapshot of the last
   moving frame over it (260 ms). The Cornerstone rotate tool's own sample trick is
   switched off (`rotateSampleDistanceFactor: 1`).
3. **Calibration** (`view3d.js` `calibrate`, `PLANS`). Five plans, cheapest first: light
   copy at 1/4, 1/2, all samples; sharp copy at 1/2, all samples. Hidden behind the poster
   (or a snapshot) it renders a few frames of each and keeps the best plan whose frame
   time fits `budget()` (60 fps, or every refresh on a 60 Hz screen). Results are cached
   per look and view size. During real drags `meter` only steps DOWN.
4. **`lod.js`** now picks the level of the STILL picture: the coarsest level whose voxel
   is <= 1.3 screen pixels; coarser again only when the level on screen is < 0.6 px.
   `session.js` calls `evaluateLod(true)` inside `swapToFull` while snapshots still cover
   the slice views, so the shader compile freeze is invisible.
5. **Camera motion** (`motion.js`): `smoothZoom` (wheel glides to a target, keeps the
   point under the cursor), `flyTo` (quaternion slerp, easeOutCubic). `view3d.js`
   `flyHome()` for Reset, gizmo letters call `flyToSide`.
6. **Looks as data** (`presets3d.js`): `buildLook(meta, view3d, solid)` returns colour and
   opacity points in real units; families by `meta.kind` (`dental` default, `ct`, `mr`).
   New dental look `roots` = "Teeth in bone". The packer does not write `kind` yet
   (Antigravity task A3), so every scan is dental today.
7. **"Smooth" slider**: `state.view3d.soft` 0..100 -> `setScalarOpacityUnitDistance`
   = smallest full-scan spacing x (0.6 + soft/100 x 5.4), same for both copies.
8. Debug with `?debug`: `window.__cbct.tuning.plan`, `.debug3d()`, `.lod`, `.stillMs()`.

## Measurements and traps (cost real time to find)

- On this PC (Intel UHD, 144 Hz screen) frame cost follows the number of SAMPLES along
  the rays, not the volume size: light copy (100^3) at all samples = 97 ms per frame, at
  1/4 samples = 7 ms. Zoomed in, the same plan costs more (more pixels hit the volume).
- vtk.js compiles a new shader for every distinct sample count (`maximumNumberOfSamples`
  is a `#define`) and blend mode: 0.4 to 0.9 s freeze the first time. Programs are cached,
  so going back to an earlier value is free. Adding or removing a clip plane, lights or
  LAO also recompiles.
- JS timing around `viewport.render()` does not see GPU time. Use `requestAnimationFrame`
  deltas (the `meter` and `costOf` in `view3d.js` do).
- Cornerstone renders on the NEXT animation frame; wait two frames before copying a canvas.
- `addVolumes` hides an actor unless `visibility: true` is passed, and resets the camera:
  save and restore it (`setFine3d` does).
- vtk objects are sealed: keep extra data in a `WeakMap`.
- The Bash tool breaks on heredocs that contain apostrophes: write a script file with the
  Write tool (scratchpad) and run it, or use Edit.
- Never run `npm ci` / `tool\build_cbct_viewer.ps1` with a shell inside `node_modules`.
  Build with `npx vite build` in `cbct_viewer/`. The build output is committed.
- Older gotchas: see the comments in `view3d.js`, `engine.js` and
  `handoff/cbct_pending_tasks.md`.

## Known problems left

1. Opening is slower: the hidden calibration adds about 2 s before the live picture on
   the small test scan (preview 2.5 s -> 4.7 s, full 3.7 s -> 6.4 s).
2. At 1.5x screen scaling there is one 2.7 s frame when the sharp copy first appears.
3. Even the cheapest ray-cast plan is the limit on weak chips and tablets. This is why
   the next step below replaces ray casting for the normal looks.

## Surface-only 3D (DONE, 2026-11-10, second session, uncommitted)

New: `src/mesher.js` (own marching cubes on typed arrays with vtk's case table only;
applies the scan's direction; [1 2 1] smoothing passes), `src/mesher.worker.js`
(imported as `?worker&inline`: no new asset file), `src/surface.js` (samples the slice
volume `core.voxels` down to <= 256 per axis on PC / 192 on tablet, builds in the worker,
one vtkActor per tissue via `viewport.addActor`), `src/mesher.test.js` (ball: closed,
on the sphere, normals out, direction).
Changed: `presets3d.js` looks carry `surfaces: [{ iso, color, opacity }]` (all looks except
X-ray, MIP, CT Lungs). `view3d.js`: `meshLook` mode hides both volume actors, skips
calibration and the moving/still switch; `refresh3D` builds/swaps meshes under a
snapshot fade; Threshold and Smooth rebuild after the slider rests (260 ms); Smooth =
0..3 smoothing passes; cut plane added to mesh mappers; first-open solidify fades the
canvas (CSS opacity), because a mesh going fully opaque jumps between vtk passes.
`lod.js`: in mesh mode it only triggers a rebuild when the full scan arrives.
`session.js` `close()` calls `close3d()` (frees meshes). Debug: `__cbct.debug3d()` shows
`mesh, tris, meshMs, grid`; `__cbct.meshStats`.

Measured on this PC (phantom_big 200^3): bone mesh 112k triangles, built in 0.17-0.3 s
off the main thread; rotation p90 7.3 ms, max 8 ms per frame at 1x and 1.5x (was 7-97 ms
ray cast); full open 2.2-2.5 s (was 6.4 s with calibration). `npm test` 117 pass, smoke
ALL PASS, `npm run perf` all targets PASS (zoom target now accepts the mesh),
`tests/look.mjs` 0 slow frames, pictures looked at (looks, sliders, cut, zoom).
`tests/transitions.mjs` Opening FAILS: frames show smooth fades; the open is now so fast
that it spans ~3 screenshots, so one fade step reads as a jump (`DUMP=1` saves frames).
The test needs a faster capture (canvas copy in page) rather than Playwright screenshots.

NOT verified: real CBCT (noise -> many small fragments and 1-3 M triangles at 256 are
possible; measure, then consider dropping tiny pieces or a lower grid), real Windows app,
tablet, weak GPU memory with big meshes.

## Implant plan (DONE, 2026-11-10, second session, uncommitted)

`src/plan.js` (pure: Catmull-Rom path, segment distance, implant axis, clearance, safety,
tube and cylinder meshes; `plan.test.js` 5 tests) and `src/planning.js` (panel section
"Implant plan", dental only; Trace = tool `nerve` (key N), clicks in slice views add points,
Backspace undoes; implants added at the crosshair with jaw, diameter, length, two tilts;
clearance colours green >= 2 mm, amber 1-2, red < 1; SVG in `frames[id].svg` group
`plan`; 3D tube + cylinders as actors `cbctPlan*`, not clipped by the cut). `state.plan`
in `state.js`; `session.js` saves `plan` in `state.json` and restores it (tracing never
restored as the active tool). `chrome.js` now exports `chipRow segmented slider row section`.
Check: `npm run plan` (tests/plan.mjs) ALL PASS: trace, undo, add, lengthen -> closer,
saved body. Pictures `tests/out/plan-*.png` looked at.
Known: Lower/Upper default is "below the scan centre = lower" (a guess); implants cannot
be dragged in the views (sliders + Move to crosshair); with an opaque bone look the nerve
and implant are hidden inside bone in 3D (use Teeth in bone or the cut).

## Automatic help (DONE, 2026-11-10, second session, uncommitted)

The user's "AI assistance" = any automation (marking, boxing, measuring), not only AI.
`src/assist.js` (+ `assist.test.js`, 3 tests): `traceCanal` (Dijkstra on a <= 250k-node
grid around the two clicks, 26 neighbours; node cost = 1 + 8 x density + 6 x missing bone
wall (6 probes at 2.2 mm), air = 100; path smoothed, a point every 2.5 mm), `siteMeasure`
(crest at mid soft-bone level, widths = narrowest chord over 12 directions at 30 % level,
height to canal roof / to air), `suggestSize`, `findDense` (connected components >=
metal level on a <= 192 grid). UI: `planning.js` Auto-follow (state.plan.follow, default
on; per-side undo stack in memory), site lines, Seat at crest, Suggest size (notes shown
only while that implant is unchanged); `findings.js` section "Found automatically",
scans once when phase becomes full, boxes in slices (dashed, only where the slice cuts
the box) and 3D (line actor `cbctFound*`), chip click moves the crosshair.
`npm run plan` 16 checks ALL PASS (manual trace, follow, undo, sizes, boxes, saved).
NOT verified on a real canal: the follow cost is tuned on a synthetic jaw only.

AI / assistance design: `handoff/cbct_ai_design.md` (section 0 = automation, built and next;
section 1 = decisions for the user before any AI model).
Antigravity brief rewritten: `handoff/antigravity_3d_viewer_v2.md` (A3-A7, then Part B:
arch.js + panoramic.js pure functions, one GATE). Not given to Antigravity yet.

## Next after surfaces

1. Review Antigravity's GATE report, then put the panoramic view on screen (B1-B3 give
   the functions): click to move the crosshair, cross-sections, implants drawn on it.
2. Real CBCT check (user): triangle count, build time, noisy bone at Smooth 40; implant
   plan on a real jaw.
3. Cut face is a hollow shell (no cap). Ask the user if it matters.
4. AI: user decisions in `cbct_ai_design.md`, then M1 speed spike.
5. Mesh detail when zoomed far in on a big scan; `tests/transitions.mjs` capture speed.
6. Then "After that" below.

## Original plan for surface-only 3D (kept for reference)

The user asked why phone games are fast and this is heavy. Games draw surfaces (each
pixel touched about once); ray casting walks hundreds of steps per pixel per frame. The
user then chose: **the 3D view draws surfaces only**, with the tissues shown chosen
selectively; a mesh is built for each. Plan (API names from memory: verify them in
`node_modules/@kitware/vtk.js` before coding):

1. New `cbct_viewer/src/surface.js`: build a mesh from a level's Int16Array with
   `vtkImageMarchingCubes` (`Filters/General/ImageMarchingCubes`; contour value, computed
   normals for smooth shading, merged points) on a `vtkImageData` with the level's
   spacing, origin and direction. Render with `vtkMapper` + `vtkActor`, added to the 3D
   viewport with `viewport.addActor({ uid, actor })` (exists in Cornerstone's
   `Viewport.js`).
2. Start with the light level (<= 128 per axis: built in a moment, shown first), then
   rebuild from `lod1` (<= 256) in a worker and swap behind the usual snapshot fade. Use
   `?worker&inline` (the CSP allows blob workers; no new asset file for Flutter to serve).
   Measure triangle counts and frame time on this PC before deciding on the full level.
3. Looks: Bone, Teeth, CT Bone, CT Skin = one mesh at the look's threshold (use
   `buildLook(...).rampStart` to the fully solid value, midpoint as iso value).
   "Teeth in bone" and "Skin + bone" = two meshes, the outer one translucent. Each tissue
   is its own actor so it can be switched on and off (the selective rendering the user
   asked for). X-ray and MIP stay ray-cast with the existing plan machinery.
4. Threshold slider: rebuild the mesh after the slider rests (debounced), keep the old
   mesh on screen meanwhile. Opacity slider: actor opacity. Smooth slider: mesh smoothing
   strength or normals from a smoothed copy (decide after seeing it).
5. Cut at crosshair: `mapper.addClippingPlane(cutPlane)` with the same plane object.
6. Keep a mesh and a volume from being visible together: vtk then feeds the volume a
   depth texture and compiles yet another shader. Hide one before showing the other.
7. With meshes there is no moving/still switch for those looks, so skip calibration for
   them: this also removes the slow opening (problem 1).
8. Click-to-place keeps using the voxels (`pick()` in `view3d.js`): no change.
9. Update `tests/look.mjs` and `tests/perf.mjs` targets; look at the pictures.

Open decision for the user after the first prototype: keep an optional ray-cast "sharp
still" on strong computers, or surfaces only everywhere (recommended: surfaces only).

## After that

- Review Antigravity's GATE 1 report (`handoff/antigravity_3d_viewer_v2.md`: tests for
  looks and motion, packer `meta.kind`, CT/MR allowed in the viewer, wording, docs), then
  Part B (dental arch curve, the first step to a panoramic view).
- Tablet check on a real device; a real CBCT and a real CT (a public torso CT is in
  `C:\Users\Soham\Downloads\cbct_test_dicom\`).
- Smart dental features: per-tooth numbering, nerve canal and an AI findings draft need a
  design first (where the AI runs, patient-data rules: India DPDP). Gums cannot be
  separated reliably from CBCT alone; say so rather than fake it.

## Commands

```powershell
cd C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\CruDoc\cbct_viewer
npx vite build
npm test
npm run smoke
npm run perf
node tests/look.mjs
node tests/look.mjs --dsf 1.5
```
