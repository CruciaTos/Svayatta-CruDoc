# Tooth chart: pure 2D redraw (plan, 13 Nov 2026)

Soham's request: scrap the Blender-picture row chart, draw our own pure 2D teeth that are smooth, clean and
premium. Add a phone setting for the odontogram: 2D or 3D. In 3D, the odontogram is a top view of the crowns
rendered from our 3D model, with no roots showing.
References are layout and style ideas only, not artwork to copy:
- vector teeth row: smooth outlines, soft shading, ivory crowns, warm roots
- textbook occlusal outlines with groove patterns
- row charts with side and top views, gum line, findings overlays
- 3D top view of the arch

## Decisions
1. **Parametric vector teeth** in plain Dart (not generated, not git-ignored), new folder
   `lib/features/dental/presentation/desktop/chart/vector_teeth/`. Each tooth type (8 types × upper/lower) is
   defined by a few dimensions from a standard anatomy table:
   - crown width and height
   - cervical width
   - root length, number of roots, trunk depth and spread
   - cusp profile

   Smooth cubic Bézier paths are built from those dimensions, with no traced points, so there are no bumps.
   The output keeps the same fields as `ToothModelShape`:
   - buccal crown, roots, pulp, neck left and right, canals
   - occlusal outline, plus a new groove list

   Because the fields match, the existing finding marks in `tooth_art.dart` keep working.
   Milk teeth use the same builder with milk dimensions.
2. **Look:**
   - Crown: ivory gradient with a soft highlight band and a subtle inner rim shade.
   - Root: warm cream gradient.
   - Neck line (CEJ, where enamel meets root): never straight, and its shape differs for each tooth. Do not
     assume one shape. Take each tooth's curve from our own 3D library crowns (the open cervical edge of the
     crown mesh is the real CEJ) and check it against anatomy references on the web.
   - Same fix in the 3D model: the enamel/root colour split is currently a flat height in `libcrowns.py`
     (and the chart pictures showed it). Make it follow the same scalloped CEJ curve, then rebuild
     subject.glb.
   - Outline: thin and soft.
   - Light teeth in both themes.
3. **Row chart:** paint the vector teeth instead of the webp pictures. The marks stay on top.
4. **2D odontogram:** the vector top views placed on a smooth arch curve. Keep:
   - the 2.5D shading
   - numbers inside the teeth
   - solid finding fills
   - the selected-tooth bar
5. **3D odontogram:** the per-tooth `_m_occlusal.webp` Blender pictures placed on `toothArchShapes` centres,
   with no roots. Setting: `odontogramStyle {flat2d, model3d}` next to `toothChartViewProvider`, with a control
   in desktop settings. The phone upright layout uses it.
6. Rename `tooth_model_shapes.g.dart` to `tooth_model_shapes.dart` so git does not ignore it. It is still
   needed for the 3D odontogram.

## Order
- A (Sonnet high): build the vector tooth library and a review-sheet test that draws all teeth in both views.
  Opus reviews the pictures and iterates until it looks premium.
- C (Sonnet medium, parallel with A): add the 3D odontogram widget, the setting, and the rename.
- B (Sonnet medium, after A): wire the vector teeth into the row chart and the 2D odontogram. Check that the
  marks line up. Run the painter test.
- Then: drop the unused tooth webps, and check the chart in the app on Windows and on the phone.
