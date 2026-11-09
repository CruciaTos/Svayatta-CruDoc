# Antigravity task: CBCT 3D viewer, smooth transitions (no visible snaps)

This whole file is your brief. Claude (the lead) reviews the result.

## ▶ DO NOW

Do M1 to M4, then P1 to P8 (Part 2, performance), then the M5 checks once at the very end. One run, no pauses. "STOP" in a task = skip that part, note
it in your report, carry on. At the end run the Checks once and report: files changed,
Check output, what you skipped.

## Why

The viewer works and is fast, but the doctor sees things *snap*:
1. While rotating/zooming the 3D view we draw it at lower quality; when they stop, the
   sharp image **snaps** in.
2. Opening the viewer: poster pictures → quarter-quality preview → full volume → sharp
   3D. That is about **four visible jumps**. It must feel like ONE continuous process,
   as if the image simply comes into focus. Nobody should notice that anything changed.
3. The page itself just pops in when it opens.

Goal: every change of picture is a gradual crossfade/"focus pull" with an ease-out curve.
The opening may be slower (up to ~600 ms per step) on purpose, to hide loading.
Everything else in the UI keeps 200–250 ms easeOutCubic (`--ease` in tokens.css).

## Rules

> Project: `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\CruDoc`. Web viewer source:
> `cbct_viewer/src/`. Flutter side: `lib/features/radiology/cbct/`.
- Files you may change: `cbct_viewer/src/view3d.js`, `cbct_viewer/src/session.js`,
  `cbct_viewer/src/chrome.js`, `cbct_viewer/src/styles/viewer.css`,
  `cbct_viewer/src/styles/tokens.css`, `lib/features/radiology/cbct/cbct_poster_layer.dart`,
  `lib/features/radiology/cbct/cbct_viewer_screen.dart` (only the fade/route timing),
  `lib/features/radiology/open_study.dart` (route transition only). New file allowed:
  `cbct_viewer/tests/transitions.mjs`.
- Do NOT change rendering quality logic: keep `tuning`, the sample-distance values (x2, x4),
  `prewarm()`, the single permanent clip plane, the 3D `mid` volume. Those were tuned by
  measurement (see comments in `view3d.js`). Changing a sample distance to a new value
  freezes the view for ~1 s (vtk recompiles a shader).
- vtk objects are sealed: never add properties to them (use a `WeakMap`).
- Cornerstone draws on the NEXT animation frame after `viewport.render()`: wait two
  `requestAnimationFrame`s before you assume the new picture is on the canvas.
- Each viewport has a 2D canvas you can copy: `vp(id).getCanvas()` (core.js `vp`). Copy it
  with `drawImage` into your own overlay canvas (fast). `toDataURL` is slower; avoid it in
  per-interaction paths.
- Respect reduced motion: `state.reduced` (web) / `MediaQuery.disableAnimationsOf` (Flutter):
  all crossfades become 80 ms, no scaling or blur.
- Never commit. No real patient scans. Do not touch other files.

## M1. Sharpen without a snap (3D view, after rotate/zoom/cut-drag)

In `view3d.js`, `setQuality(0)` switches back to full quality and renders. Make it a
crossfade:
1. Before switching, copy the current (low-quality) 3D canvas into an overlay `<canvas>`
   placed exactly over the 3D viewport (append it to `frames.threeD.root`, absolutely
   positioned, same size, `pointer-events: none`, z-index between the image and the SVG
   overlays: use z-index 1 like `.poster`).
2. Switch to full quality and render; after two animation frames (the sharp image is now
   underneath), fade the overlay from opacity 1 to 0 over **260 ms easeOutCubic**, then
   remove it.
3. If the doctor starts interacting again during the fade, remove the overlay at once.
4. Optional, only if it looks better: also animate the overlay `filter: blur(0px)` →
   `blur(1px)` during the fade (the low-quality image softens while the sharp one shows).

## M2. Opening the viewer: one continuous "coming into focus"

Read `session.js` `open()`, `revealLive()` and `swapToFull()`, and `swap3d()`.
1. **Page entrance** (`chrome.js` / `viewer.css`): on first paint, the whole viewer fades
   in from the background colour with a slight scale 0.985 → 1 over **450 ms
   easeOutCubic** (the top bar, panel and status bar fade in 60 ms after the image area;
   no sliding).
2. **Posters → preview** (`revealLive`): today each poster fades over 200 ms with a 40 ms
   stagger, so the four panels change one after another. Instead fade all four together
   over **500 ms easeOutCubic**, with the poster going slightly soft (`blur(0)` →
   `blur(1px)`) as it fades, so the live picture seems to sharpen out of it.
3. **Preview → full** (`swapToFull`, the "focus pull"): the snapshot overlays already fade
   (250 ms). Make it **600 ms easeOutCubic** with the same blur-as-it-fades, so the extra
   detail "develops" in. The snapshot must stay fully opaque until the full-volume frame
   is on screen underneath (wait two animation frames after the render).
4. **3D gets its own smaller volume** (`swap3d`): this currently swaps with no
   transition. Give it the same copy-overlay-and-fade treatment as M1 (450 ms).
5. **First-open "solidify"** (`solidify()` in `view3d.js`, 500 ms): keep it, but make sure
   it does not overlap a crossfade in a way that flickers. If it does, start it after the
   preview fade ends.
6. **2 px progress line** (`.progress` in `viewer.css`): fade in over 300 ms when loading
   starts, and out over 400 ms when the full volume is in. Its width changes must be
   smooth (`transition: width 300ms var(--ease)`).
7. The status/overlay text (slice numbers etc.) should not jump when the volume changes:
   if a number changes because of the swap (e.g. slice count 48 → 96), crossfade that
   text over 200 ms instead of replacing it instantly. STOP this item if it gets complicated.

## M3. Flutter: hand-over from the app's poster layer to the page

`cbct_poster_layer.dart` draws posters while the WebView boots and fades out when the page
posts `shown`. Make that fade **400 ms easeOutCubic** (it is the first image the doctor
sees, so it must match the page's posters pixel for pixel: do not change the geometry).
In `open_study.dart`, the route into the viewer is a 240 ms fade + scale 0.985 → 1: make it
**320 ms easeOutCubic**, fade only for reduced motion. Follow
`CruDoc/.claude/rules/crudoc-ui.md` (no bounce; this slower timing is approved by the user
for the 3D viewer only).

## M4. A frame-capture test that proves "no snaps"

Create `cbct_viewer/tests/transitions.mjs` (reuse `tests/serve.mjs` and the Edge launch
from `tests/smoke.mjs`; use the phantom in `dev/phantom`, run `npm run phantom` first if
missing). It:
1. Opens the viewer and takes a screenshot of the 3D viewport every 40 ms for 6 s.
2. Drags to rotate the 3D view for 1 s, releases, and keeps capturing for 1 s.
3. For each pair of consecutive frames, computes the mean absolute pixel difference
   (decode PNGs with `page.evaluate` + an offscreen canvas, or compare raw buffers from
   `page.screenshot({ type: 'png' })` decoded in the page). Prints the biggest jump
   during opening and during the sharpen after release.
Pass rule: after the first image appears, no single frame-to-frame change is larger than
3x the median change during that phase (i.e. no sudden jump). Print PASS/FAIL per phase.

## M5. Build and check (once, at the end)

```powershell
cd C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\CruDoc
powershell -File tool\build_cbct_viewer.ps1
cd cbct_viewer
npm test
npm run smoke
node tests/transitions.mjs
cd ..
flutter analyze lib/features/radiology/cbct
flutter test test/features/radiology/cbct/cbct_poster_layer_test.dart
```

Before running the build, make sure no terminal or process has its current directory
inside `cbct_viewer/node_modules` (npm ci then fails with EBUSY and half-deletes it).
Report: every file changed, each command's result, the transitions PASS/FAIL lines with
their numbers, and anything you skipped.

---

# Part 2: performance, "like a game engine" (P1 to P8)

The doctor usually looks at the WHOLE scan in the 3D view. At that zoom a 512-voxel scan
puts several voxels into one screen pixel, so rendering full detail is wasted work.
Detail is only needed when they zoom in. Build level-of-detail (LOD) for the 3D view:
coarse when zoomed out, finer only when zoomed in, and back to coarse when they zoom out.
The slice views (axial/coronal/sagittal) are NOT part of this: they stay full resolution.

Extra files you may change for Part 2: `cbct_viewer/src/engine.js` (only `showVolume` /
volume bookkeeping), `cbct_viewer/src/core.js` (helpers),
`lib/features/radiology/cbct/cbct_pack.dart` and `test/features/radiology/cbct/cbct_pack_test.dart`.
New files allowed: `cbct_viewer/src/lod.js`, `cbct_viewer/tests/perf.mjs`.

## What exists today (read first)

- `meta.json` has `volumes.preview` (≤128 voxels per axis, box-averaged), `volumes.mid`
  (≤384 per axis, only when the full scan is bigger than 384) and `volumes.full`.
- `session.js`: all four views start on `preview`; `swap3d()` then gives the 3D view `mid`
  (if it exists); `swapToFull()` gives the slice views `full`.
- `engine.js` `showVolume(voxels, geo, valueOffset, views)` puts a volume on some
  viewports and frees volumes no viewport holds (`held.mpr`, `held.threeD`).
- `view3d.js`: `apply3D()` (transfer function), `applyCut()` (one permanent clip plane),
  interaction quality (`tuning`, `lowerQuality`, `sharpenSoon`, `prewarm`). After ANY 3D
  volume swap call `refresh3D()`.
- Measured on this PC (Intel UHD): 3D from a 256x256x54 copy rotates smoothly; from the
  full 512x512x107 it stutters (30% of frames over 50 ms).

## P1. Packer: always write a 3D level set (Dart)

In `cbct_pack.dart` add levels for the 3D view, independent of `mid`:
- `lod0`: ≤128 per axis (point it at the existing `preview` file; same data).
- `lod1`: ≤256 per axis (box average, same method and origin shift as `preview`). Only
  when the full scan is bigger than 256 on some axis.
- last level: the full volume (`full.i16`).
Store `meta.volumes.lods = [{file, factor, dims, spacing, origin}, ...]`, coarse to fine.
Bump `cbctPackVersion` by one (old packs get rebuilt). Keep `preview` and `mid` exactly
as today. Extend `cbct_pack_test.dart`: the 96x96x40 synthetic scan gets 2 lods with dims
`[48,48,20]` and `[96,96,40]`.

## P2. Choose the level from the zoom (web, new `src/lod.js`)

Pick the coarsest level whose voxels are still at least about one screen pixel:
```
pxPerMm    = canvasHeightPx / (2 * camera.parallelScale)   // the 3D view is parallel projection
voxelPx(L) = min(spacing of level L) * pxPerMm              // one voxel's size on screen
choose the coarsest L with voxelPx(L) >= 0.75; if none, the finest
```
- Hysteresis: go finer when the current level's `voxelPx >= 1.4`; go coarser only when
  the coarser level's `voxelPx >= 0.75` has held for 600 ms.
- Evaluate only after zooming has STOPPED for 300 ms (listen to
  `Enums.Events.CAMERA_MODIFIED` from `@cornerstonejs/core` on `core.hosts.threeD`).
  Never swap while the doctor is dragging (`lowerQuality` active).
- At the default whole-scan view the answer must be the coarsest level.
- `canvasHeightPx` = `vp('threeD').getCanvas().height`.
- Expose the current level with `?debug` as `window.__cbct.lod`.

## P3. Load levels lazily, keep them cached (web)

- Start the 3D view on the coarsest level (already loaded as the preview). Do not load
  `mid` for the 3D view any more (replace `swap3d(mid3d)` with the LOD logic); tablets
  keep using `mid` for the slice views as today.
- Fetch a finer level only when P2 asks for it, in the background (export a
  `loadLevel(entry)` helper from `session.js` that reuses `fetchVoxels`). Show the 2 px
  progress line while it streams.
- Keep at most TWO levels for the 3D view in memory (the one on screen + the coarsest).
  The slice views keep `full` regardless.
- When the 3D view needs the full level, reuse the Int16Array already loaded for the
  slice views (`core.voxels`); never download it twice.

## P4. Swap levels without a visible change

Every level swap uses the M1 technique: copy the 3D canvas into an overlay; save
`vp('threeD').getCamera()`; `showVolume(data, geo, core.valueOffset, ['threeD'])`;
`setCamera` back exactly (as `swap3d()` does); `refresh3D()`; wait two animation frames;
fade the overlay out over 350 ms easeOutCubic. Zooming in should feel like the image just
gets sharper.

## P5. Ray sampling (keep the tuned values)

- Allowed sample-distance factors are only 1, 2 and 4. Others (for example 3) made vtk
  recompile its shader: a 1 s freeze. Keep `tuning.lowSampleDistance = 2` and
  `tuning.wheelSampleDistance = 4`. Lowering the pixel density (image sample distance)
  was measured SLOWER here: do not use it.
- Every new mapper (each level swap creates one) goes through `prewarm()` via
  `refresh3D()`, so the first drag after a swap does not freeze.

## P6. Do less work when nothing changes

1. Never render the 3D view while it is hidden (single-view layout with another view in
   focus: `state.layout === 'single' && state.focus !== 'threeD'`; hidden views are 4x4 px).
   Skip `apply3D`/`applyCut` renders and `scheduleDraw` then; render once when it is
   visible again.
2. Keep plane outlines/gizmo at one redraw per animation frame; keep the 90 ms cut throttle.
3. No `toDataURL` in interaction paths (use `drawImage`).
4. High-DPI: measure with P8 at `deviceScaleFactor: 1.5` (Playwright context option) and
   report whether the coarse level is still smooth. Do not change DPR handling without
   numbers.

## P7. Memory

Log once after loading (console) the bytes of each volume in memory (dims product x 2)
and `cache.getCacheSize()` from `@cornerstonejs/core`. After a level is freed the next log
must show it gone. Report the numbers for the phantom.

## P8. Performance test (new `cbct_viewer/tests/perf.mjs`)

Add an optional size argument to `tools/make_phantom.mjs` (`--size 400` gives
400x400x400 at 0.1 mm; default stays 96) and generate `dev/phantom_big`. Reuse
`tests/serve.mjs`. Measure with the page's own `requestAnimationFrame` intervals while
Playwright moves the real mouse:
- drag-rotate the 3D view (80 mouse moves);
- wheel-zoom in 10 notches, wait 1 s, rotate again;
- wheel-zoom out 10 notches, wait 1 s.
Per phase print: frames over 50 ms / total, p90, max, and `window.__cbct.lod`. Run the
whole sequence TWICE in the same page (the GPU is shared with other apps; compare rounds).
Targets: zoomed-out rotation under 2% of frames over 50 ms; the finer level appears within
2 s of zooming in; zooming out returns to the coarse level; no frame over 300 ms except a
level swap hidden by its fade. Add `"perf": "node tests/perf.mjs"` to the scripts block of
`cbct_viewer/package.json` (only that line).

Add to the M5 check list: `npm run perf` and
`flutter test test/features/radiology/cbct/cbct_pack_test.dart`.
