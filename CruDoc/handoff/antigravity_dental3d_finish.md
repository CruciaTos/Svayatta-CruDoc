# Antigravity brief: finish and check the dental 3D work

Work in the main folder on branch `main`. Do the parts in order and stop at each GATE with a short report.
Do not commit. Never run `flutter test`. Do not edit `.gitignore`.

## Background

- 3D viewer source: `CruDoc/dental3d/` (JS, three.js). Built bundle: `CruDoc/assets/dental3d/` (made by `npm run build` in `dental3d/`).
- Flutter side: `lib/features/dental/explain3d/` (`Dental3dView`, `Dental3dScreen`, server, snapshot) and
  `lib/features/dental/presentation/desktop/tooth_chart_card.dart` (Chart | 3D switch, `Show patient` button).
- Model build: `dental3d/blender/build.py` (+ `libcrowns.py`, `solve_contacts.py`) -> `dental3d/public/models/subject.glb`.
  Blender: `"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b`.
- 2D chart pictures: `assets/images/teeth/<fdi>_turn000..315.webp`, `_occlusal.webp`, `_apical.webp`,
  rendered by `dental3d/blender/render_chart.py` (+ `chart_post.py`).
- Tests (run inside `dental3d/`): `node tests/verify.mjs`, `node tests/player.mjs`, `node tests/responsive.mjs`.
- Two earlier workers were stopped half way. Their work is in the code but nobody checked it.

## Part 1: prove what works now (no code changes)

1.1 In `dental3d/`: run the three test files. Write down passed / failed counts and each failing check's name.
1.2 Run `blender/check_glb.py` on `public/models/subject.glb` as its header says. Write down the result.
1.3 Confirm `assets/dental3d/models/subject.glb` is the same file as `dental3d/public/models/subject.glb` (same size and hash).
1.4 `flutter analyze lib/features/dental` : write down errors and warnings.
1.5 Run the app on Windows (`flutter run -d windows --dart-define-from-file=google_desktop_oauth.json`), open a patient,
    open the tooth chart. Check and write yes/no for each:
    - `3D` in the Chart | 3D switch shows the 3D model inside the card.
    - Drag rotates, mouse wheel zooms, right-drag or two-finger drag pans.
    - Clicking a tooth in 3D shows the picked-tooth panel under the model, and its button opens the tooth.
    - Switching Findings / Plan changes the colours without the page reloading.
    - `Show patient` opens the full-screen viewer, and Back returns to the card with 3D still showing.
    - With `Milk teeth` selected, `3D` is disabled.
    - The example-patient menu is NOT shown inside the app.
    - The 2D chart shows every tooth upright, the right way round, not cropped.

**GATE 1.** Report the table. Do not fix anything yet.

## Part 2: fix what Part 1 found

Fix only the failures from Part 1, smallest change each. After every fix re-run the check that failed.
If you change anything in `dental3d/src`, run `npm run build` in `dental3d/` afterwards.

**GATE 2.** Report: each failure, what you changed, re-run result.

## Part 3: teeth

3.1 Gaps. Measure the gap between every pair of neighbouring teeth in `public/models/subject.glb`.
    Target: 0.00 to 0.10 mm, no overlap, left and right sides mirror images. `blender/solve_contacts.py` and
    `blender/contact_scale.json` were started for this: finish that approach (a small width correction per tooth type).
    Rebuild with `blender/build.py`, run `check_glb.py`, copy the GLB to `assets/dental3d/models/subject.glb`.
3.2 Lower teeth direction. It is not proven that the lower crowns are the right way round (front edge = mesial).
    Check tooth 36 and 46 from above: a lower first molar has three cheek-side cusps and the smallest one is at the BACK.
    Check 33 and 43 from the front: the canine tip sits slightly towards the FRONT (midline side) of the crown.
    If they are mirrored, flip the lower mapping in `blender/libcrowns.py` (keep meshes closed, normals outward) and rebuild.
    Save four pictures in `dental3d/tmp/handed/` (36 top, 46 top, 33 front, 43 front) and say what you decided and why.
3.3 If the GLB changed, re-render the chart pictures with `render_chart.py`, look at the contact sheet, then copy them
    into `assets/images/teeth/`.

**GATE 3.** Report: gap table before / after, the handedness decision with the four pictures, check_glb result.

## Part 4: phones and tablets

4.1 `node tests/responsive.mjs` must pass at 375x812, 812x375, 768x1024, 1280x800: no overlap, no sideways scroll,
    buttons at least 40 px, side panels become bottom sheets on narrow screens.
4.2 Run the app on an Android phone or emulator. Check: the chart's `3D` opens the full-screen viewer, one finger rotates,
    pinch zooms, two fingers pan, a tap selects a tooth, Back works, rotating the phone does not break the layout.
    If the page stays blank on Android, compare with how the CBCT viewer loads its page
    (`lib/features/radiology`, search `CbctServer`) and copy its WebView and network settings.

**GATE 4.** Report yes/no for each check, with a screenshot of the phone.
