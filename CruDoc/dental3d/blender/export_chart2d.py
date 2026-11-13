"""export_chart2d.py - the 2D chart pictures and shapes, all from the Blender tooth model.

For the 16 right-side teeth (11-18, 41-48; the left side is mirrored in Dart):
  * renders assets/images/teeth/<fdi>_m_buccal.webp and <fdi>_m_occlusal.webp: orthographic, 24 px per mm,
    transparent film, soft even studio light, ivory crown, warmer matt root, 1.2 mm soft blend at the gum
    line; the biting-surface picture shows nothing deeper than 1 mm below the gum line. Picture boxes (mm)
    are read from tmp/chart2d/outlines.json so pictures and outlines line up;
  * renders a flat top-down crown silhouette per tooth in its arch pose (raw/arch_<fdi>.png) for the odontogram;
  * writes pulp_canals.json and arch_meta.json, then runs tmp/chart2d/process_shapes.py, which regenerates
    tooth_model_shapes.dart.
Raw PNGs go to tmp/chart2d/raw; the edge-colour clean-up and WebP save run in plain Python
(this same file, `python export_chart2d.py --post <raw_dir> <out_dir>`).

Run with:
  "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b dental3d/tmp/subject.blend --python dental3d/blender/export_chart2d.py
"""
import os
import sys
import json
import subprocess
import numpy as np

POST = len(sys.argv) > 1 and sys.argv[1] == '--post'
if not POST:
    import bpy
    import bmesh
    from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
DENTAL3D = os.path.dirname(HERE)
CRUDOC = os.path.dirname(DENTAL3D)
CHART2D_TMP = os.path.join(DENTAL3D, 'tmp', 'chart2d')
PULP_CANALS_JSON = os.path.join(CHART2D_TMP, 'pulp_canals.json')
PROCESS_SHAPES_PY = os.path.join(CHART2D_TMP, 'process_shapes.py')

os.makedirs(CHART2D_TMP, exist_ok=True)


def _post(raw_dir, out_dir):
    """Plain Python (numpy, scipy, Pillow): fill the colour of translucent edge pixels from the solid
    interior (no fringe, straight alpha) and save WebP."""
    from PIL import Image
    from scipy import ndimage
    os.makedirs(out_dir, exist_ok=True)
    n = 0
    for f in sorted(os.listdir(raw_dir)):
        if not f.endswith(('_m_buccal.png', '_m_occlusal.png')):
            continue
        a = np.asarray(Image.open(os.path.join(raw_dir, f)).convert('RGBA')).astype(np.float32) / 255.0
        solid = a[..., 3] > 0.97
        if solid.sum() > 50:
            idx = ndimage.distance_transform_edt(~solid, return_distances=False, return_indices=True)
            edge = ~solid
            a[..., :3][edge] = a[..., :3][idx[0], idx[1]][edge]
        a[..., :3] *= (a[..., 3:4] > 0.002)
        # Dart picture conventions: upper cheek-side pictures hang root-up (flip vertically); upper
        # biting surfaces are seen from below (flip horizontally), lower ones are flipped vertically.
        upper = int(f[0]) < 3
        if f.endswith('_m_buccal.png') and upper:
            a = a[::-1]
        elif f.endswith('_m_occlusal.png'):
            a = a[:, ::-1] if upper else a[::-1]
        a = np.ascontiguousarray(a)
        Image.fromarray((a * 255 + 0.5).astype(np.uint8), 'RGBA').save(
            os.path.join(out_dir, f[:-4] + '.webp'), 'WEBP', quality=92, alpha_quality=95, method=4)
        n += 1
    print('post-processed', n)


if POST:
    _post(sys.argv[2], sys.argv[3])
    sys.exit(0)
sc = bpy.context.scene

def make_smooth_pulp(fdi, z_max_tooth, z_min_tooth):
    p = sc.objects.get(f'pulp_{fdi}')
    t = sc.objects.get(f'tooth_{fdi}')
    if not p or not t:
        return [], []
    
    vp = np.empty(len(p.data.vertices) * 3, np.float32)
    p.data.vertices.foreach_get('co', vp)
    vp = vp.reshape(-1, 3)
    
    z_min_pulp = vp[:, 2].min()
    z_max_pulp = vp[:, 2].max()
    
    # Chamber vertical bounds
    z_chamber_top = z_max_pulp
    z_chamber_floor = max(z_max_pulp - 2.8, z_min_pulp + 3.0)
    
    # Vertices in chamber region
    v_cham = vp[vp[:, 2] >= z_chamber_floor]
    x_cmin = v_cham[:, 0].min()
    x_cmax = v_cham[:, 0].max()
    x_mid = 0.5 * (x_cmin + x_cmax)
    w_cham = max(x_cmax - x_cmin, 1.2)
    
    # Find canal root tips
    bottom = vp[vp[:, 2] < (z_min_pulp + 1.8)]
    tips = []
    for pt in bottom:
        if not any(np.hypot(pt[0] - tip[0], pt[1] - tip[1]) < 1.8 for tip in tips):
            tips.append(pt)
    tips.sort(key=lambda pt: pt[0]) # distal to mesial (-X to +X)
    
    # Trace canal centerlines
    canals = []
    for tip in tips:
        apex_z = max(tip[2], z_min_tooth + 1.0)
        n_pts = 8
        z_vals = np.linspace(apex_z, z_chamber_floor, n_pts)
        pts = []
        for zv in z_vals:
            slice_mask = np.abs(vp[:, 2] - zv) < 0.6
            if np.any(slice_mask):
                sv = vp[slice_mask]
                if len(pts) == 0:
                    pts.append([tip[0], tip[1], zv])
                else:
                    prev = pts[-1]
                    dists = np.hypot(sv[:, 0] - prev[0], sv[:, 1] - prev[1])
                    near = sv[dists < 1.5]
                    if len(near) > 0:
                        pts.append([float(near[:, 0].mean()), float(near[:, 1].mean()), zv])
                    else:
                        pts.append([prev[0], prev[1], zv])
            else:
                pts.append([tip[0], tip[1], zv])
        pts = np.array(pts, dtype=np.float32)
        for _ in range(2):
            pts[1:-1, 0] = 0.25 * pts[:-2, 0] + 0.5 * pts[1:-1, 0] + 0.25 * pts[2:, 0]
        canals.append(pts)
        
    poly = []
    if len(canals) == 1:
        c = canals[0]
        left_canal = []
        right_canal = []
        for i, pt in enumerate(c):
            t = i / (len(c) - 1)
            r = 0.12 * (1.0 - t) + 0.35 * t
            left_canal.append((pt[0] - r, pt[2]))
            right_canal.append((pt[0] + r, pt[2]))
            
        h_left = (x_mid - 0.32 * w_cham, z_chamber_top)
        h_mid = (x_mid, z_chamber_top - 0.25)
        h_right = (x_mid + 0.32 * w_cham, z_chamber_top)
        
        cham_left = (x_mid - 0.5 * w_cham, z_chamber_floor + 0.5 * (z_chamber_top - z_chamber_floor))
        cham_right = (x_mid + 0.5 * w_cham, z_chamber_floor + 0.5 * (z_chamber_top - z_chamber_floor))
        
        apex_pt = c[0]
        apex_cap = [
            (apex_pt[0] - 0.12, apex_pt[2]),
            (apex_pt[0], apex_pt[2] - 0.12),
            (apex_pt[0] + 0.12, apex_pt[2])
        ]
        poly = apex_cap + right_canal + [cham_right, h_right, h_mid, h_left, cham_left] + list(reversed(left_canal))
        
    else:
        c_left = canals[0]
        c_right = canals[-1]
        
        c_left_l = []
        c_left_r = []
        for i, pt in enumerate(c_left):
            t = i / (len(c_left) - 1)
            r = 0.12 * (1.0 - t) + 0.32 * t
            c_left_l.append((pt[0] - r, pt[2]))
            c_left_r.append((pt[0] + r, pt[2]))
            
        c_right_l = []
        c_right_r = []
        for i, pt in enumerate(c_right):
            t = i / (len(c_right) - 1)
            r = 0.12 * (1.0 - t) + 0.32 * t
            c_right_l.append((pt[0] - r, pt[2]))
            c_right_r.append((pt[0] + r, pt[2]))
            
        apex_left = [
            (c_left[0][0] - 0.12, c_left[0][2]),
            (c_left[0][0], c_left[0][2] - 0.12),
            (c_left[0][0] + 0.12, c_left[0][2])
        ]
        apex_right = [
            (c_right[0][0] - 0.12, c_right[0][2]),
            (c_right[0][0], c_right[0][2] - 0.12),
            (c_right[0][0] + 0.12, c_right[0][2])
        ]
        
        horn_left = (c_left[-1][0], z_chamber_top)
        horn_right = (c_right[-1][0], z_chamber_top)
        mid_dip = (0.5 * (horn_left[0] + horn_right[0]), z_chamber_top - 0.45)
        
        wall_left = (c_left[-1][0] - 0.45, 0.5 * (z_chamber_floor + z_chamber_top))
        wall_right = (c_right[-1][0] + 0.45, 0.5 * (z_chamber_floor + z_chamber_top))
        floor_mid = (0.5 * (c_left[-1][0] + c_right[-1][0]), z_chamber_floor + 0.4)
        
        poly = (
            apex_left +
            c_left_r +
            [floor_mid] +
            list(reversed(c_right_l)) +
            apex_right +
            c_right_r +
            [wall_right, horn_right, mid_dip, horn_left, wall_left] +
            list(reversed(c_left_l))
        )
        
    pulp_mm = [(round(float(x), 2), round(float(z_max_tooth - z), 2)) for x, z in poly]
    
    canals_mm = []
    for c in canals:
        c_reversed = list(reversed(c))
        c_line = [(round(float(pt[0]), 2), round(float(z_max_tooth - pt[2]), 2)) for pt in c_reversed]
        canals_mm.append(c_line)
        
    return pulp_mm, canals_mm


FDIS = [11, 12, 13, 14, 15, 16, 17, 18, 41, 42, 43, 44, 45, 46, 47, 48]
out_pulp = {}
for fdi in FDIS:
    t = sc.objects.get(f'tooth_{fdi}')
    vt = np.empty(len(t.data.vertices) * 3, np.float32)
    t.data.vertices.foreach_get('co', vt)
    vt = vt.reshape(-1, 3)
    z_min_tooth = float(vt[:, 2].min())
    z_max_tooth = float(vt[:, 2].max())
    pulp_mm, canals_mm = make_smooth_pulp(fdi, z_max_tooth, z_min_tooth)
    out_pulp[str(fdi)] = {'pulp': pulp_mm, 'canals': canals_mm}

with open(PULP_CANALS_JSON, 'w') as f:
    json.dump(out_pulp, f, indent=2)
print('Wrote', PULP_CANALS_JSON)

# ------------------------------------------------------------------ pictures
PX_PER_MM = 24.0
RAW_DIR = os.path.join(CHART2D_TMP, 'raw')
ASSETS_DIR = os.path.join(CRUDOC, 'assets', 'images', 'teeth')
ARCH_META = os.path.join(CHART2D_TMP, 'arch_meta.json')
OUTLINES_JSON = os.path.join(CHART2D_TMP, 'outlines.json')
os.makedirs(RAW_DIR, exist_ok=True)
with open(OUTLINES_JSON) as f:
    boxes = json.load(f)

sc.render.engine = 'BLENDER_EEVEE'
sc.render.film_transparent = True
sc.render.resolution_percentage = 100
sc.render.image_settings.file_format = 'PNG'
sc.render.image_settings.color_mode = 'RGBA'
sc.view_settings.view_transform = 'Standard'
sc.view_settings.look = 'None'
sc.view_settings.exposure = 0.8
for k, v in (('taa_render_samples', 96), ('use_raytracing', False)):
    if hasattr(sc.eevee, k):
        try:
            setattr(sc.eevee, k, v)
        except Exception:
            pass
w = sc.world or bpy.data.worlds.new('W')
sc.world = w
w.use_nodes = True
bg = w.node_tree.nodes.get('Background')
if bg:
    bg.inputs['Color'].default_value = (0.92, 0.94, 1.0, 1.0)
    bg.inputs['Strength'].default_value = 0.35

CROWN_RGB = (0.98, 0.94, 0.84)   # ivory enamel
ROOT_RGB = (0.84, 0.67, 0.46)    # warmer, matt root


def make_chart_material():
    m = bpy.data.materials.new('chart_tooth')
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    b = nt.nodes.new('ShaderNodeBsdfPrincipled')
    at = nt.nodes.new('ShaderNodeAttribute')
    at.attribute_name = 'ChartCol'
    nt.links.new(at.outputs['Color'], b.inputs['Base Color'])
    mr = nt.nodes.new('ShaderNodeMapRange')     # alpha = crown mask (1 crown, 0 root)
    mr.inputs['To Min'].default_value = 0.62    # root: matt
    mr.inputs['To Max'].default_value = 0.30    # crown: soft sheen
    nt.links.new(at.outputs['Alpha'], mr.inputs['Value'])
    nt.links.new(mr.outputs['Result'], b.inputs['Roughness'])
    mc = nt.nodes.new('ShaderNodeMapRange')
    mc.inputs['To Max'].default_value = 0.15
    nt.links.new(at.outputs['Alpha'], mc.inputs['Value'])
    for nm in ('Coat Weight', 'Clearcoat'):
        if nm in b.inputs:
            nt.links.new(mc.outputs['Result'], b.inputs[nm])
            break
    for nm in ('Coat Roughness', 'Clearcoat Roughness'):
        if nm in b.inputs:
            b.inputs[nm].default_value = 0.12
            break
    for nm in ('Subsurface Weight', 'Subsurface'):
        if nm in b.inputs:
            b.inputs[nm].default_value = 0.15
            break
    if 'Specular IOR Level' in b.inputs:
        b.inputs['Specular IOR Level'].default_value = 0.55
    nt.links.new(b.outputs['BSDF'], out.inputs['Surface'])
    return m


MAT = make_chart_material()


def paint(ob):
    """Crown/root colour into the 'ChartCol' point attribute (alpha = crown mask), keeping the model's
    baked crevice darkening (softened). z = 0 is the gum line; 1.2 mm smooth blend."""
    me = ob.data
    n = len(me.vertices)
    crev = np.ones(n, np.float32)
    ca = me.color_attributes.get('Col')
    if ca is not None and ca.domain == 'POINT':
        raw = np.empty(n * 4, np.float32)
        ca.data.foreach_get('color', raw)
        crev = 0.55 + 0.45 * np.clip(raw.reshape(-1, 4)[:, 0], 0.0, 1.0)
    V = np.empty(n * 3, np.float32)
    me.vertices.foreach_get('co', V)
    z = V.reshape(-1, 3)[:, 2]
    t = np.clip((z + 0.6) / 1.2, 0.0, 1.0)
    t = t * t * (3 - 2 * t)
    rgb = np.array(ROOT_RGB)[None, :] * (1 - t[:, None]) + np.array(CROWN_RGB)[None, :] * t[:, None]
    rgb *= crev[:, None]
    col = np.concatenate([rgb, t[:, None]], axis=1).astype(np.float32)
    if 'ChartCol' in me.color_attributes:
        me.color_attributes.remove(me.color_attributes['ChartCol'])
    att = me.color_attributes.new('ChartCol', 'FLOAT_COLOR', 'POINT')
    att.data.foreach_set('color', col.ravel())
    me.materials.clear()
    me.materials.append(MAT)


def _look(d, up):
    z = -d.normalized()
    x = up.cross(z).normalized()
    y = z.cross(x)
    return Matrix(((x.x, y.x, z.x), (x.y, y.y, z.y), (x.z, y.z, z.z))).to_euler()


cam_data = bpy.data.cameras.new('chart_cam')
cam_data.type = 'ORTHO'
cam_data.sensor_fit = 'HORIZONTAL'
cam = bpy.data.objects.new('chart_cam', cam_data)
sc.collection.objects.link(cam)
sc.camera = cam
rig = bpy.data.objects.new('rig', None)
sc.collection.objects.link(rig)
tgt = bpy.data.objects.new('tgt', None)
sc.collection.objects.link(tgt)


def add_area(name, loc, energy, size, colour):
    ld = bpy.data.lights.new(name, 'AREA')
    ld.energy, ld.size, ld.color = energy, size, colour
    if hasattr(ld, 'use_shadow'):
        ld.use_shadow = False                      # soft and even: no cast shadows
    lo = bpy.data.objects.new(name, ld)
    sc.collection.objects.link(lo)
    lo.parent = rig
    lo.location = loc
    c = lo.constraints.new('TRACK_TO')
    c.target = tgt
    c.track_axis = 'TRACK_NEGATIVE_Z'
    c.up_axis = 'UP_Y'


# the light travels with the camera, so every picture is lit the same way
add_area('key', (-60, 70, 90), 45000.0, 70.0, (1.0, 0.97, 0.92))
add_area('fill', (80, 10, 70), 14000.0, 90.0, (0.92, 0.95, 1.0))
add_area('rim', (30, 80, -60), 22000.0, 40.0, (1.0, 1.0, 1.0))
add_area('bounce', (0, -90, 60), 6000.0, 90.0, (1.0, 0.96, 0.9))


def shoot(path, centre, direction, up, w_mm, h_mm, clip_end=1000.0, cam_dist=300.0):
    """Orthographic picture, w_mm x h_mm at 24 px per mm, camera looking along `direction` at `centre`
    (the light rig is centred there too, so every picture is lit the same way)."""
    rx, ry = int(round(w_mm * PX_PER_MM)), int(round(h_mm * PX_PER_MM))
    sc.render.resolution_x, sc.render.resolution_y = rx, ry
    dv = Vector(direction).normalized()
    cam.location = Vector(centre) - dv * cam_dist
    cam.rotation_euler = _look(dv, Vector(up))
    cam.data.ortho_scale = rx / PX_PER_MM
    cam.data.clip_start = 10.0
    cam.data.clip_end = clip_end
    rig.matrix_world = Matrix.LocRotScale(Vector(centre), cam.rotation_euler.to_quaternion(), None)
    tgt.location = Vector(centre)
    bpy.context.view_layer.update()
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


for o in sc.objects:
    if o.name.startswith(('tooth_', 'pulp_', 'tpl_')):
        o.hide_render = True
        o.hide_viewport = True

arch_meta = {}
for fdi in FDIS:
    ob = sc.objects[f'tooth_{fdi}']
    pose = ob.matrix_world.copy()            # the tooth's place in the arch
    ob.hide_render = False
    ob.hide_viewport = False
    paint(ob)
    # ---- tooth frame: parent removed, origin at the gum line, +Z towards the biting edge, -Y cheek side
    ob.parent = None
    ob.matrix_world = Matrix.Identity(4)
    V = np.empty(len(ob.data.vertices) * 3, np.float32)
    ob.data.vertices.foreach_get('co', V)
    zmax = float(V.reshape(-1, 3)[:, 2].max())
    # cheek side: right of the picture = +X (mesial), crown up; box in mm from outlines.json (y down from the tip)
    bx0, by0, bx1, by1 = boxes[str(fdi)]['buccal']['imageBox']
    shoot(os.path.join(RAW_DIR, f'{fdi}_m_buccal.png'),
          ((bx0 + bx1) / 2, 0, zmax - (by0 + by1) / 2), (0, 1, 0), (0, 0, 1), bx1 - bx0, by1 - by0)
    # biting surface: looking down, cheek (-Y) at the top; nothing deeper than 1 mm below the gum line
    ox0, oy0, ox1, oy1 = boxes[str(fdi)]['occlusal']['imageBox']
    shoot(os.path.join(RAW_DIR, f'{fdi}_m_occlusal.png'),
          ((ox0 + ox1) / 2, (oy0 + oy1) / 2, 0.0), (0, 0, -1), (0, -1, 0), ox1 - ox0, oy1 - oy0,
          clip_end=101.0, cam_dist=100.0)
    # ---- odontogram: crown only (above the gum line), in its arch pose, seen from above
    me = ob.data.copy()
    bm = bmesh.new()
    bm.from_mesh(me)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, -0.3), plane_no=(0, 0, 1), clear_inner=True)
    bm.to_mesh(me)
    bm.free()
    keep_data = ob.data
    ob.data = me
    ob.matrix_world = pose
    cx, cy = pose.translation.x, pose.translation.y
    shoot(os.path.join(RAW_DIR, f'arch_{fdi}.png'), (cx, cy, 0.0), (0, 0, -1), (0, 1, 0), 28.0, 28.0,
          clip_end=300.0, cam_dist=100.0)
    arch_meta[str(fdi)] = {'archCenter': [round(cx, 3), round(-cy, 3)], 'size': [28.0, 28.0]}
    ob.data = keep_data
    bpy.data.meshes.remove(me)
    ob.hide_render = True
    ob.hide_viewport = True
    print('rendered', fdi, flush=True)

with open(ARCH_META, 'w') as f:
    json.dump(arch_meta, f, indent=2)

# edge clean-up + WebP, then outlines and the Dart file
py = os.environ.get('CHART_PYTHON', 'python')
subprocess.run([py, os.path.abspath(__file__), '--post', RAW_DIR, ASSETS_DIR], check=True)
print('Running process_shapes.py...')
subprocess.run([py, PROCESS_SHAPES_PY], check=True)
print('export_chart2d.py finished successfully!')
