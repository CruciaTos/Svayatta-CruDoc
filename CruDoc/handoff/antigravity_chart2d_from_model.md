# Antigravity brief: 2D tooth chart drawn from our own 3D tooth model

Start after `handoff/antigravity_dental3d_finish.md` Part 3 is done (the tooth model must be final first).
Do the parts in order. Stop at every GATE and report. Do not commit.

## What the chart does today (read this first)

- The 2D chart does NOT show pictures of teeth. It draws every tooth itself and fills the drawn shape with a
  stretched texture:
  - `lib/features/dental/presentation/desktop/chart/tooth_art.dart`: `BuccalShape` (about line 1179, the cheek-side
    view with roots), `OcclusalShape` (about line 1536, the biting surface), the paint code (about line 1699 onward)
    and all overlays: decay, fillings, crown/cap, root canal and canals, implant, missing, fracture, impacted,
    unerupted, lesion, inflamed gum, planned work.
  - `tooth_textures.dart`: loads `assets/images/teeth/<fdi>_tex_crown.webp`, `_tex_root.webp`, `_tex_occlusal.webp`.
  - `tooth_anatomy.dart`: `ToothSpec` (sizes in mm). `tooth_chart_2d.dart`: lays the teeth out. `tooth_render.dart`,
    `cached_paint.dart`: older/simple painter and caching.
- The `<fdi>_turn000..315`, `_occlusal`, `_apical` pictures are used by NO Dart code. They were only the source for
  the textures (`tool/teeth/make_tooth_textures.py`).
- Result today: drawn outlines + stretched third-party textures. The teeth do not match our 3D model.

## Goal

Each tooth in the 2D chart is a clean straight-on picture of the SAME tooth as in the 3D model (same shape, same
finish), and every overlay still works and lines up with it.

## Rules

- Follow `.claude/rules/crudoc-ui.md`: no hard-coded colours, sizes or spacing; use the design tokens.
- Do not edit `dental3d/src`, `dental3d/blender/build.py`, `libcrowns.py`, or any `.glb`.
- `flutter test` is allowed ONLY for the one painter test file named below, run alone, never two at once.
  Never run the whole test suite.
- Keep the old drawn shapes as the fallback (milk teeth and any tooth without model data).

## Part 0: a picture of the chart as it is now

0.1 Write `test/tool/tooth_chart_sheet_test.dart`: a pure painter test (no providers, no database, no WebView).
    It paints, with the SAME paint calls the chart uses, onto a `ui.PictureRecorder` and saves PNG files:
    - sheet A: all 32 adult teeth, cheek-side view, upper row and lower row, at 6 px per mm;
    - sheet B: all 32 biting surfaces;
    - sheet C: tooth 16, 11, 36, 46 each with: decay on two surfaces, a filling, a crown, root canal treated,
      implant, missing, fractured, lesion, planned work;
    - the same three sheets on the dark theme colours.
    Output folder: `dental3d/tmp/chart2d/before/`. Load the texture images in the test with `rootBundle`.
0.2 Run only that file: `flutter test test/tool/tooth_chart_sheet_test.dart`.

**GATE 0.** Report the PNG paths. If the test cannot paint without providers, say what blocks it.

## Part 1: export pictures and outlines from the model (Blender)

1.1 Write `dental3d/blender/export_chart2d.py`. Run:
    `"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b dental3d/tmp/subject.blend --python dental3d/blender/export_chart2d.py`
    (if `tmp/subject.blend` is missing, run `blender/build.py` first as its header says).
1.2 For the 16 teeth of the patient's right side (11-18 and 41-48; the left side is their mirror image), with the
    tooth in its own frame (local +Z = towards the biting edge, local -Y = cheek/lip side, origin at the gum line):
    - `buccal` picture: orthographic camera on the cheek side looking straight at the tooth, whole tooth with roots;
    - `occlusal` picture: orthographic camera looking straight down onto the biting surface;
    - same scale for every tooth: 24 pixels per mm; transparent background; soft even studio light, no cast shadow;
      crown glossy ivory, root slightly warmer and matt, soft 1 mm blend at the gum line (the look of the 3D viewer);
    - no dark or white fringe on the edge (render with a transparent film and save straight alpha).
    Save as `assets/images/teeth/<fdi>_m_buccal.webp` and `<fdi>_m_occlusal.webp` (quality 90, with alpha).
1.3 Orientation must match what `BuccalShape` and `OcclusalShape` expect. Read their comments and code first and
    write in your report: which way is mesial, where the biting edge is, which side is the cheek in the occlusal
    view. Export the pictures already in that frame so Dart needs no rotation.
1.4 Outlines. For each of the 16 teeth compute, from the mesh (project the vertices, or trace the alpha of the
    picture), in millimetres in the same frame as the picture:
    - `crown`: closed outline of the part above the gum line (cheek-side view);
    - `roots`: closed outline(s) of the part below the gum line (one path; molars show their separate roots);
    - `occlusal`: closed outline of the biting-surface view;
    - `neck`: the left and right points where crown meets root;
    - `canals`: one centre line per root canal, from the `pulp_<fdi>` mesh (top of the pulp chamber to each apex);
    - `imageBox`: the rectangle in mm that each picture covers.
    Simplify each outline to at most 64 points (smooth, no zig-zag). Round to 0.01 mm.
    Write `dental3d/tmp/chart2d/outlines.json` and generate
    `lib/features/dental/presentation/desktop/chart/tooth_model_shapes.g.dart` (const data, a map keyed by FDI
    number for the 16 right-side teeth, with a header comment "GENERATED by dental3d/blender/export_chart2d.py").
1.5 Make a check sheet `dental3d/tmp/chart2d/export_check.png`: every picture with its outlines drawn on top in red
    and the canal lines in blue. Look at it: outlines must hug the picture edge everywhere.

**GATE 1.** Report: the orientation notes from 1.3, the check sheet path, picture sizes, total size of the 32 files.

## Part 2: draw the chart from the model data (Dart)

2.1 `ToothTextures` (`tooth_textures.dart`): load `_m_buccal` and `_m_occlusal` for the 16 right-side teeth.
    Left-side teeth use the right-side tooth mirrored. Milk teeth keep today's rule (borrow the adult tooth).
2.2 `BuccalShape` and `OcclusalShape`: when model data exists for the tooth, build `crown`, `roots`, the neck, the
    crown rectangle and the canal lines from `tooth_model_shapes.g.dart`, scaled from mm to pixels with the shape's
    `k`. Keep every public member the paint code and overlays already use (same names, same meaning), so the
    overlays need no change. Keep the existing drawn construction as the fallback path.
2.3 Painting: draw the picture into `imageBox` (scaled, NOT stretched), clipped to the outline, in place of the
    stretched texture. Then the existing shading-free overlays on top, unchanged. Remove the code that stretches
    textures only when nothing uses it any more.
2.4 Surface areas for decay and fillings (`surfaceArea`): keep today's proportions inside the new crown rectangle.
2.5 Sizes: the tooth sizes on screen now come from the model outlines, so neighbouring teeth stay in proportion.
    Biting edges of a row sit on one straight line. Gaps between teeth are equal.
2.6 `flutter analyze lib/features/dental` must show no errors. Run the painter test again with output folder
    `dental3d/tmp/chart2d/after/`.

**GATE 2.** Report the after sheets. For each overlay in sheet C say: visible and aligned, or not.

## Part 3: make it perfect (check each line, fix what fails)

Target look for the row chart (ideas for layout only; do not copy artwork, colours or text):
`handoff/refs/chart2d/row_chart_closeup.png` and `handoff/refs/chart2d/row_chart_full_screen.png`.
- Three bands with air between them: upper teeth from the cheek side with roots pointing up; the biting surfaces in
  the middle; lower teeth from the cheek side with roots pointing down. No boxes or grid lines around teeth.
- One thin gum line running across each band, following every tooth's gum margin from the model (the `neck` points),
  scalloped between teeth. Where a recession value is recorded for a tooth, the line moves by that amount.
- Findings and work are flat, soft, translucent fills inside the tooth outline in the chart's existing colours:
  a crown tints the whole crown, a filling tints its surface in both the cheek-side and the biting-surface picture,
  a treated canal is a filled line along the model's canal, a post is a short solid bar in the canal.
- Perio marks (plaque, bleeding, pus) sit in small dot grids above the upper band and below the lower band, and only
  on the perio layer. Tooth numbers sit in one straight line under the lower band (and above the upper band if the
  card is tall enough).
- Keep the existing layers (`ChartLayer`: dental, plan, perio, endo) and their data. This is a restyle of how they
  are drawn, not new data.


- Light and dark theme: no white or dark halo around a tooth; the ivory reads well on both backgrounds.
- Sharp at 100%, 150% and 200% display scale (draw with `FilterQuality.medium` or better; no blur, no jagged edge).
- Selected tooth, hovered tooth and dimmed tooth look the same as before the change.
- Missing tooth: faint ghost of the model outline. Implant: the implant drawing sits inside the root outline.
- Root canal view: canals follow the model's canal lines.
- Tooth numbers centred under/over each tooth; nothing overlaps at the narrowest card width.
- Speed: pictures decoded once, teeth cached as before (`cached_paint.dart`); scrolling the patient page stays smooth.
- Clean-up, only after everything above passes: list (do not delete yet) the files in `assets/images/teeth/` that no
  Dart code and no script needs any more (`*_turn*`, `*_apical`, `*_occlusal`, `*_tex_*`), and the pubspec comment
  that should change.

**GATE 3.** Report the checklist with yes/no and the final sheets.

## Part 4: the odontogram view (arches) and the view setting

Reference pictures (ideas for layout only; do not copy their artwork, colours or text):
`handoff/refs/chart2d/odontogram_phone.png`, `handoff/refs/chart2d/odontogram_with_gums.png`.

An odontogram shows the two dental arches as if the mouth were opened flat: the upper arch on top with the front
teeth at the top of the screen, the lower arch below it with the front teeth at the bottom. The patient's right
side is on the left of the screen. It fits a phone held upright much better than the rows do.

4.1 Blender, in `export_chart2d.py`: one more picture per right-side tooth, `<fdi>_m_arch.webp`: the tooth in its
    real position and tilt in the arch (use the tooth's own world matrix from the model), orthographic camera
    looking straight along the vertical axis at the biting surface (from below for upper teeth, from above for lower
    teeth), 24 px per mm, transparent background, same light and finish as the other pictures. Because the camera is
    vertical and the teeth are tilted, front teeth show part of their face, like the reference.
    Also export for all 32 teeth, into `tooth_model_shapes.g.dart`: the tooth centre in the arch (x across, z front
    to back, in mm, from `dental3d/scene_manifest.json`), the picture's rectangle in mm, and the closed outline of the
    tooth in this view (at most 48 points). Left-side teeth mirror the right-side pictures.
4.2 Dart: a new widget `ToothChartArches` in `chart/tooth_chart_arches.dart` with the same inputs as `ToothChart2D`
    (data, child, layer, selected, onSelect, numbering). It places every tooth picture at its arch position at one
    common scale so both arches fit the width, with a clear gap between the arches and the labels `Upper` and
    `Lower` inside them.
    - State colours: use the chart's EXISTING colours and legend for found, done and planned work (the same ones the
      row chart and its legend use). Tint the whole tooth with a soft translucent fill inside its outline, plus a
      thin outline in the same colour. Do not add a new blue: see `.claude/rules/crudoc-ui.md`.
    - Missing tooth: faint dashed outline only. Selected tooth: ring in the selection colour.
    - Tap a tooth: select it and show, in a bar under the arches, the tooth name, its findings in one line, and
      `Open` (the same action as the row chart). Touch area per tooth at least 40 px. No hover-only behaviour.
    - Tooth numbers: small, outside the arch next to each tooth, in the doctor's numbering system.
    - Milk teeth: the same arches with 20 teeth, using the adult pictures the row chart borrows, at milk-tooth size.
    - No gums drawn (clean white look). Layers `dental` and `plan` are supported; for `perio` and `endo` show the row
      chart.
4.3 The setting. Add `Tooth chart view` with two choices, `Rows` and `Arches`, next to the tooth numbering setting
    (`lib/features/dental/domain/tooth_numbering.dart` shows how that one is stored and read; its control is in
    `lib/features/settings/presentation/desktop_settings_screen.dart`). Store and read it the same way
    (`toothChartViewProvider`). Default: `Rows`.
4.4 Which view shows:
    - phone held upright (width under 600 px and taller than wide): ALWAYS `Arches`, whatever the setting says;
    - everything else (phone on its side, tablet, desktop): the doctor's setting.
    No 3D WebView is embedded in the card on a phone; `Show patient` still opens the 3D full screen.
4.5 Add to the painter test: arches at 360 px wide (phone) and at 900 px wide, light and dark, with the same sample
    findings as sheet C. Output `dental3d/tmp/chart2d/arches/`.

**GATE 4.** Report the arches sheets, where the setting appears, and the `flutter analyze` result.
