# Antigravity brief: make the new 3D model the only 3D view, and use its renders in the 2D chart

Start this only after Phase D of `handoff/antigravity_dental3d.md` has reached GATE D.
Do Part A, stop at GATE A. Then Part B, stop at GATE B. Do not commit. Do not run `flutter test`.

## Background (read once)

- Flutter app in `CruDoc/` (package `doctor_management_app`).
- New 3D viewer: web bundle in `assets/dental3d/` (source in `dental3d/`), shown by
  `lib/features/dental/explain3d/dental3d_screen.dart` (`Dental3dScreen({patientId, patientName})`),
  served by `dental3d_server.dart`, fed by `dental3d_snapshot.dart`
  (`buildDental3dSnapshot(entries, {plan, savedJson})`).
- The page talks through `window.App3DBridge`: `selectPart(id)`, `setPartStatus`, `setMode('pbr'|'xray'|'heatmap')`,
  `applyStateSnapshot(json)`, `resetCamera()`, `setCameraPreset`, `setJawOpen`, `setLayer`, `setGumStyle`, `getState()`.
  It sends packets `{type, ts, payload}` to the Flutter handler named `dental3d`:
  `READY`, `PART_SELECTED` (payload has the part id, e.g. `tooth_36`), `PART_HOVERED`, `STATE_UPDATED`.
- Old 3D (to be removed): `lib/features/dental/presentation/desktop/chart/tooth_chart_3d.dart`
  (`ToothChart3D`), with `jaw_model.dart`, `tooth_anatomy.dart`, `tooth_textures.dart`.
- Both meet in `lib/features/dental/presentation/desktop/tooth_chart_card.dart`:
  the `Chart | 3D` switch (about line 250), `ToothChart3D(` (about line 330),
  "The tooth picked in 3D, and the way into it" (about line 423), "3D colours" (about line 469),
  and the `Show patient` button that pushes `Dental3dScreen`.

## Part A: swap the 3D view

A1. Inventory first. Read `tooth_chart_3d.dart` and the 3D parts of `tooth_chart_card.dart`. Write a short table in your
    report: every feature of the old 3D (rotate, zoom, pan, reset view, tap a tooth, the picked-tooth panel and its
    "open tooth" action, colour by findings or by plan, hover, anything else) and how the new viewer covers it.

A2. Split `Dental3dScreen` into two widgets in the same folder:
    - `Dental3dView`: the web view only, no Scaffold and no app bar. Parameters: `patientId`, `patientName`,
      `showPlan` (bool), `onToothSelected(int? fdi)`, `compact` (bool).
    - `Dental3dScreen`: a Scaffold that wraps `Dental3dView` (behaviour unchanged).

A3. In `tooth_chart_card.dart`, replace `ToothChart3D(...)` with `Dental3dView(...)` in the same place and size.
    - Tap a tooth in 3D: on `PART_SELECTED`, parse the FDI number from `tooth_<fdi>` and call the same code the old
      `ToothChart3D` tap used, so the same picked-tooth panel and "open tooth" action appear. Part ids that are not
      teeth (gum, bone) clear the selection.
    - When a tooth is picked from Flutter (panel, list), call `App3DBridge.selectPart('tooth_<fdi>')`.
    - Colour layer: findings = snapshot without the plan; plan = snapshot with the plan. Rebuild the snapshot and
      call `applyStateSnapshot` when the layer changes. Do not reload the page.
    - `compact: true` must hide the page's own right-hand tooth list. If the page has no such option, add a URL
      query `?compact=1` that `dental3d/src/main.js` reads to hide the list panel, then run `npm run build` in `dental3d/`.
    - Zoom, rotate, pan and reset already work inside the page. Do not add Flutter gestures on top of the web view.

A4. Milk teeth: the new model has adult teeth only (11-48). When `Milk teeth` is selected, show the 2D chart and
    disable the `3D` segment.

A5. Remove the old 3D: delete `tooth_chart_3d.dart`, and `jaw_model.dart`, `tooth_anatomy.dart`, `tooth_textures.dart`
    only if `grep` shows nothing else imports them (the 2D chart may use some: keep what it uses). Remove imports and
    dead code left behind in `tooth_chart_card.dart`. Do not delete any image in `assets/images/teeth/` in Part A.

A6. Keep the `Show patient` button exactly as it is.

A7. Check: `flutter analyze` on the files you changed must show no errors. If you changed `dental3d/src`, run
    `node tests/verify.mjs` in `dental3d/` (all checks must pass) and `npm run build`.

**GATE A.** Report: the A1 table, files changed and deleted, analyze result, and anything the old 3D did that the
new one does not do yet.

## Part B: 2D chart images rendered from the 3D model

The 2D chart shows tooth pictures from `assets/images/teeth/`, 13 files per tooth, 32 teeth (FDI 11-48):
`<fdi>_turn000.webp` ... `<fdi>_turn315.webp` (eight views, 45 degree steps), `<fdi>_occlusal.webp`,
`<fdi>_apical.webp`, and `<fdi>_tex_crown.webp`, `<fdi>_tex_occlusal.webp`, `<fdi>_tex_root.webp`.

Goal: replace the `turn*`, `occlusal` and `apical` pictures with renders of our own model, with the same file
names, so no Dart code changes.

B1. Look at the existing pictures for 11, 14, 36 and 46 first. Note for each kind: pixel size, transparent
    background or not, which way the crown points, how much empty margin, which face `turn000` shows and which way
    the turn goes (compare `turn000`, `turn045`, `turn090`). Your renders must match all of that.

B2. Write `dental3d/blender/render_chart.py`. Run it with Blender 5.2 headless:
    `"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b dental3d/tmp/subject.blend --python dental3d/blender/render_chart.py -- <out_dir>`
    (if `tmp/subject.blend` is missing, run `dental3d/blender/build.py` first as its header describes).
    For each object `tooth_<fdi>`:
    - hide everything else (other teeth, pulp, templates);
    - work in the tooth's own frame (apply the inverse of its world matrix): local +Z is towards the biting edge,
      local -Y is the lip/cheek side, origin at the gum line;
    - orthographic camera, same scale for all 32 teeth so sizes compare correctly, transparent film;
    - soft studio light, no hard shadows; material: crown (local z >= 0) glossy ivory white, root (z < 0) slightly
      warmer and matt, with a soft 1 mm blend between them;
    - render the eight turns about the local Z axis, the occlusal view (looking down the -Z direction onto the biting
      surface) and the apical view (from the root tip), save as WebP with the names above.

B3. Write the renders to `dental3d/tmp/chart_renders/` first and make one contact sheet PNG of all 32 `turn000` and
    all 32 `occlusal` pictures. Look at it: every tooth upright, facing the right way, upper and lower not swapped,
    left and right not swapped, nothing cropped.

B4. Only when the sheet looks right, copy the files over the same names in `assets/images/teeth/`. Do not touch the
    `tex_*` files unless Part A left them unused (then list them in the report; do not delete them yet).

B5. Check: `flutter analyze` shows no new errors. Do not regenerate goldens.

**GATE B.** Report: the B1 notes, the contact sheet path, the number of files replaced, and any tooth that looks wrong.

## Rules

- Do not edit: `dental3d/blender/build.py`, `libcrowns.py`, `toothlib.py`, `public/models/`, `scene_manifest.json`.
- Do not add packages. Do not change `pubspec.yaml` unless an asset folder is removed.
- Keep reports short: tables and file lists, no long prose.
