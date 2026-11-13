# Handoff: dental 3D viewer and 2D tooth chart (13 Nov 2026)

For the next session (Opus). Written by the previous session after reviewing the work. Everything below was
checked by that session unless it says "not checked".

## Where things are

- Repo root: `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc`. App: `CruDoc/` (Flutter, package `doctor_management_app`).
- Branch: `main` at `e851370` (the dental branch is merged). **Nothing since then is committed.**
  About 18 changed files plus new files; list with `git status --short | grep -v images/teeth`.
- Do not run `flutter test` in general: dental tests hang on this machine. The one safe test is
  `flutter test test/tool/tooth_chart_sheet_test.dart`, run alone.
- UI rules: `CruDoc/.claude/rules/crudoc-ui.md` (design tokens only).
- Soham's standing wishes: keep it simple and clean, use smaller models for the hands-on work, plain language.

## Fix first (will break the build elsewhere)

1. `lib/features/dental/presentation/desktop/chart/tooth_model_shapes.g.dart` is **ignored by git**
   (`CruDoc/.gitignore` line 10: `*.g.dart`). The chart code imports it, so a commit made today builds on this PC
   and fails on any other machine or in CI. Rename it (for example `tooth_model_shapes.dart`), update the imports
   and the generator's output path, or force-add it.
2. The generator is split across an ignored folder. `dental3d/blender/export_chart2d.py` calls
   `dental3d/tmp/chart2d/process_shapes.py` and reads `dental3d/tmp/chart2d/outlines.json`; `dental3d/tmp/` is
   git-ignored. Move `process_shapes.py` next to `export_chart2d.py` and make the outlines regenerate from the
   model, so the export works from a clean checkout. The post step calls system `python`
   (override: `CHART_PYTHON`).

## 2D tooth chart: state after today's clean-up

What it is now:
- Row chart (`chart/tooth_chart_2d.dart`, painting in `chart/tooth_art.dart`): each tooth is a Blender picture of
  our own tooth model (`assets/images/teeth/<fdi>_m_buccal.webp`, `<fdi>_m_occlusal.webp`, 16 right-side teeth,
  left side mirrored, loaded by `chart/tooth_textures.dart`) clipped to outlines from the generated shapes file.
  All finding marks (decay, filling, crown, root canal, implant, missing, fracture, lesion, planned) are the
  original ones and line up. Tooth slots are sized from the model so nothing overlaps.
- Odontogram (`chart/tooth_chart_arches.dart`, widget `ToothChartArches`): flat 2D. Each tooth is its outline with
  a flat fill; findings are a soft tint plus coloured outline; missing tooth is a dashed outline; numbers sit
  outside the arch; a bar below shows the tooth name, findings and Open. No pictures.
- Setting: `ToothChartView { rows, arches }` and `toothChartViewProvider` in
  `lib/features/dental/domain/tooth_numbering.dart`; control "Tooth chart view" in
  `lib/features/settings/presentation/desktop_settings_screen.dart`. In `tooth_chart_card.dart`: a phone held
  upright (width under 600 and taller than wide) always shows arches; everything else follows the setting.
- Review sheets (painter test output): `dental3d/tmp/chart2d/after/` (sheet a, b, c, d per layer, light and dark)
  and `dental3d/tmp/chart2d/arches/`. Before pictures: `dental3d/tmp/chart2d/before/`.

Checked by looking at the pictures: `sheet_d_dental_light`, `arches_360_light`. Clean: ivory crowns, real grooves,
no stray lines, no overlap, marks aligned, arches apart, numbers off the teeth.
`flutter analyze lib/features/dental` and the settings screen: no issues (worker's run).

Not checked:
- The chart in the running app (Windows or phone). Only the painter test was run.
- `sheet_a`, `sheet_d_plan`, `sheet_d_endo`, `arches_900_dark` after the last change.
- Milk teeth in both views.

Known rough edges:
- Soham said some teeth look unnatural in the 2D side view and asked to fix that later. My read of which:
  upper side incisors 12/22 (slanted hooked edge), upper molars 16-18 (squat crowns, fused-looking roots),
  lower front teeth (boxy), canines (over-long), premolar roots (thin, hooked). The cause is in the tooth MODEL
  (formula roots; library crowns squashed by per-axis scaling), so fixing it there helps 3D too. Ask him to point
  at the worst ones first.
- Odontogram decay tint is a strong brown (alpha 0.35 in `tooth_chart_arches.dart`); soften if he wants.
- Dark theme: tooth pictures are bright on the dark canvas (no halo, but strong contrast).
- About 416 old pictures in `assets/images/teeth/` (`*_turn*`, `*_apical`, `*_occlusal`, `*_tex_*`) are no longer
  loaded by any Dart code. `tool/teeth/make_tooth_textures.py` used them. Remove them and fix the pubspec comment
  once the chart is confirmed in the app. (They came from BoneBox; dropping them also removes that credit duty.)
- Lesson: do NOT capture chart pictures from the three.js viewer. It was tried and gave blown-out, muddy pictures.
  Blender (`export_chart2d.py`) is the picture source.

## 3D viewer: state

- Source `CruDoc/dental3d/` (three.js), bundle `CruDoc/assets/dental3d/`, Flutter side
  `lib/features/dental/explain3d/`. The old in-card 3D (`tooth_chart_3d.dart`, `jaw_model.dart`) is deleted; the
  card's `3D` option embeds `Dental3dView`, `Show patient` opens `Dental3dScreen`.
- Teeth: sculpted library crowns on generated roots (`blender/libcrowns.py`, `build.py`). Lower crown mapping was
  flipped today (`SX lower = +1`): accepted from canine and molar pictures in `dental3d/tmp/handed/`; a comparison
  with a real lower molar was a near tie, so a dentist's glance would settle it. Contact gaps reported
  0.04-0.05 mm (not re-measured by me; viewer shows no midline slit).
- Tests in `dental3d/`: `node tests/verify.mjs` (55 pass, by Antigravity's run), `node tests/responsive.mjs`
  (48 pass, Antigravity's run), `node tests/player.mjs` (passed 3 of 3 on my runs; takes about 210 s, use a
  timeout of 480 s or more).
- Fixed today: animation tickers never stopped, so the page drew forever (battery); bridge left tooth 35 changed.
- In the app the page is opened with `?app=1`, which hides the example-patient menu (loading an example would
  overwrite the real patient's saved 3D state).

Not checked: the 3D inside the running app; any phone or tablet (no phone build contains it yet); phone frame
rate with 216k triangles. A Windows debug build was made on 12 Nov, before today's fixes.

## Other things produced

- App audit for the team: `CruDoc/docs/audit_2026-11-12/app_audit_report.md` (226 tasks in 8 packages; 43% of
  rows confirmed in code; 7 wrong file locations listed in its last section, not yet corrected in the tables).
- Briefs written for Antigravity (Gemini): `handoff/antigravity_dental3d_finish.md` (done except the phone check),
  `handoff/antigravity_chart2d_from_model.md` (superseded by today's clean-up; keep for the reasoning).
  Antigravity's "seen in the app" and "looks right" claims were wrong several times: always look at the pictures.
- Reference pictures from Soham (layout ideas only, do not copy artwork): `handoff/refs/chart2d/`.

## Suggested order

1. Fix the two "fix first" items, then run the painter test and `flutter analyze lib/features/dental`.
2. Build and open the app on Windows; check the row chart, the odontogram (setting and a narrow window), the 3D
   option, tap a tooth, Findings/Plan, Show patient and Back.
3. Commit (ask Soham first). Then a phone build and the same checks on a phone held upright and on its side.
4. Delete the unused old tooth pictures.
5. Later passes Soham has parked: natural tooth shapes in the model; bite and tooth positions (underbite,
   overbite, crossbite, crowding) from dentist sliders, then from five mouth photos, then CBCT.

## Usage note

Soham is on a Pro plan and is cost-sensitive. Two Sonnet workers in parallel used about 60% of a 5-hour window
in under an hour; run one at a time. On 13 Nov the weekly all-models meter read 100% (resets 17 Nov), though one
Sonnet worker still ran.
