# Muscle chart model pipeline

Builds `assets/muscle_viewer/body.glb` and `catalog.json` from the Z-Anatomy Blender file.

1. Get the source: `git clone https://github.com/Z-Anatomy/The-blend` and unzip `Z-Anatomy.zip` (gives `Startup.blend`).
2. Export (Blender 4.2, headless; or `pip install bpy==4.2.0` on Python 3.11):
   `blender -b --python zexport.py`  (edit the `p=` path at the top first)
   -> raw.glb (all muscles + skeleton, modifiers applied, ~46 MB) and catalog_raw.json
3. `python build_catalog.py` -> catalog.json (region, side, layer, action tags per muscle)
4. Compress: `npx gltfpack -i raw.glb -o body.glb -kn -km -si 0.4 -cc`
   (-si 0.4 = 40% of the triangles, ~5.5 MB; -si 1 = full detail, ~11 MB)

Ids look like `m_supraspinatus_muscle_r` (muscle, right side) and `b_scapula_l` (bone).
Never rename existing ids: saved patient findings point at them.

License: Z-Anatomy / BodyParts3D models are CC BY-SA 4.0. Keep the credit line in the
viewer and the About screen; edited model files stay under CC BY-SA.
