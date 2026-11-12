"""Render the 2D chart tooth pictures from the 3D model (stage 1 of 2).

  blender -b tmp/subject.blend --python blender/render_chart.py -- <raw_dir> [fdi fdi ...]
  python  blender/chart_post.py <raw_dir> <out_dir>           (stage 2: crop, margin, scale, WebP)

Stage 1 (this file) writes one transparent 1200 px PNG per view into <raw_dir>:
  <fdi>_turn000 .. turn315 (45 degree steps), <fdi>_occlusal, <fdi>_apical.
Convention (identical to the original BoneBox pictures the Flutter chart was built around):
  * turn000 = the cheek / lip (facial) side; the tooth turns about its long axis so that the facial
    side moves towards the screen RIGHT as the angle grows (turn090 = the distal side of a right
    tooth ... mirrored for the left, exactly like the old pictures);
  * upper teeth: crown at the BOTTOM, root up.  Lower teeth: crown at the TOP, root down;
  * occlusal: looking down on the biting surface, facial side at the TOP of the picture for both
    jaws; apical: looking up from the root tip, same up vector (so it is the mirror of occlusal).
Look: EEVEE, soft three-light studio rig that travels with the camera, glossy ivory enamel, warmer matt
root, no outline pass, transparent film (straight alpha - stage 2 removes colour bleed on the edge).
"""
import math
import os
import sys
import numpy as np
import bpy
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
D = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import blib

A = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
raw_dir = os.path.abspath(A[0]) if A else os.path.join(D, 'tmp', 'chart_raw')
QUICK = '--quick' in A
only = [int(a) for a in A[1:] if a.isdigit()]
os.makedirs(raw_dir, exist_ok=True)

SIZE = 1200
SCALE_MM = 34.0          # orthographic window; the longest tooth (canine, ~27 mm) fits with margin
sc = bpy.context.scene
sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x = sc.render.resolution_y = SIZE
sc.render.resolution_percentage = 100
sc.render.film_transparent = True
sc.render.filter_size = 1.0
sc.render.image_settings.file_format = 'PNG'
sc.render.image_settings.color_mode = 'RGBA'
sc.render.image_settings.compression = 15
sc.view_settings.view_transform = 'Standard'
sc.view_settings.look = 'None'
sc.view_settings.exposure = 0.35
ee = sc.eevee
for k, v in (('taa_render_samples', 96), ('use_raytracing', False), ('use_shadows', True),
             ('use_fast_gi', False), ('shadow_ray_count', 2), ('shadow_step_count', 8)):
    if hasattr(ee, k):
        try:
            setattr(ee, k, v)
        except Exception:
            pass
d = sc.display
d.shading.show_object_outline = False
d.shading.show_cavity = False

# world: soft, slightly cool-white ambient (invisible, the film is transparent)
w = sc.world or bpy.data.worlds.new('W')
sc.world = w
w.use_nodes = True
bg = w.node_tree.nodes.get('Background')
bg.inputs['Color'].default_value = (0.92, 0.94, 1.0, 1.0)
bg.inputs['Strength'].default_value = 0.35

# ------------------------------------------------------------------ materials
FDIS = [q * 10 + t for q in (1, 2, 3, 4) for t in range(1, 9)]
TURNS = list(range(0, 360, 45))
if '--quick' in A:
    TURNS = [0, 90]
CROWN_RGB = (0.98, 0.94, 0.84)     # ivory enamel
ROOT_RGB = (0.84, 0.67, 0.46)      # warmer, a little darker root surface


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
    sep = nt.nodes.new('ShaderNodeSeparateColor')
    nt.links.new(at.outputs['Color'], b.inputs['Base Color'])
    nt.links.new(at.outputs['Color'], sep.inputs['Color'])
    # region mask (1 = crown, 0 = root) is stored in the attribute alpha
    mr = nt.nodes.new('ShaderNodeMapRange')
    mr.inputs['From Min'].default_value = 0.0
    mr.inputs['From Max'].default_value = 1.0
    mr.inputs['To Min'].default_value = 0.62      # root: matt
    mr.inputs['To Max'].default_value = 0.16      # crown: glossy
    nt.links.new(at.outputs['Alpha'], mr.inputs['Value'])
    nt.links.new(mr.outputs['Result'], b.inputs['Roughness'])
    mc = nt.nodes.new('ShaderNodeMapRange')
    mc.inputs['To Min'].default_value = 0.0
    mc.inputs['To Max'].default_value = 0.35
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
    """Crown/root colour into the 'ChartCol' point attribute (alpha = crown mask), keeping the baked
    crevice darkening of the model's 'Col' attribute."""
    me = ob.data
    n = len(me.vertices)
    crev = np.ones(n, np.float32)
    ca = me.color_attributes.get('Col')
    if ca is not None and ca.domain == 'POINT':
        raw = np.empty(n * 4, np.float32)
        ca.data.foreach_get('color', raw)
        crev = np.clip(raw.reshape(-1, 4)[:, 0], 0.0, 1.0)
        crev = 0.55 + 0.45 * crev           # soften: the old pictures have light, not harsh, grooves
    V = np.empty(n * 3, np.float32)
    me.vertices.foreach_get('co', V)
    z = V.reshape(-1, 3)[:, 2]
    t = np.clip((z + 0.6) / 1.2, 0.0, 1.0)  # CEJ blend over 1.2 mm; z = 0 is the gum line
    t = t * t * (3 - 2 * t)
    rgb = np.array(ROOT_RGB)[None, :] * (1 - t[:, None]) + np.array(CROWN_RGB)[None, :] * t[:, None]
    rgb *= crev[:, None]
    col = np.concatenate([rgb, t[:, None]], axis=1).astype(np.float32)
    nm = 'ChartCol'
    if nm in me.color_attributes:
        me.color_attributes.remove(me.color_attributes[nm])
    att = me.color_attributes.new(nm, 'FLOAT_COLOR', 'POINT')
    att.data.foreach_set('color', col.ravel())
    me.materials.clear()
    me.materials.append(MAT)


# ------------------------------------------------------------------ camera + light rig
cam = blib.get_camera(sc)
cam.data.ortho_scale = SCALE_MM
rig = bpy.data.objects.new('rig', None)
sc.collection.objects.link(rig)


def add_area(name, loc, energy, size, colour):
    ld = bpy.data.lights.new(name, 'AREA')
    ld.energy = energy
    ld.size = size
    ld.color = colour
    if hasattr(ld, 'use_shadow'):
        ld.use_shadow = True
    lo = bpy.data.objects.new(name, ld)
    sc.collection.objects.link(lo)
    lo.parent = rig
    lo.location = loc
    c = lo.constraints.new('TRACK_TO')
    c.target = tgt
    c.track_axis = 'TRACK_NEGATIVE_Z'
    c.up_axis = 'UP_Y'
    return lo


tgt = bpy.data.objects.new('tgt', None)
sc.collection.objects.link(tgt)
# rig frame: +X = screen right, +Y = screen up, -Z = towards the subject (camera looks down -Z)
key = add_area('key', (-60, 70, 90), 45000.0, 70.0, (1.0, 0.97, 0.92))      # soft, warm, upper left
fill = add_area('fill', (80, 10, 70), 14000.0, 90.0, (0.92, 0.95, 1.0))      # cool fill, right
rim = add_area('rim', (30, 80, -60), 22000.0, 40.0, (1.0, 1.0, 1.0))         # edge light from behind-top
low = add_area('bounce', (0, -90, 60), 6000.0, 90.0, (1.0, 0.96, 0.9))      # bounce from below


def aim(direction, up, centre):
    """Place camera + rig: look along `direction` at `centre` with screen-up = `up`."""
    dv = Vector(direction).normalized()
    cam.location = Vector(centre) - dv * 300.0
    cam.rotation_euler = blib._look(dv, Vector(up))
    cam.data.ortho_scale = SCALE_MM
    cam.data.clip_start = 10.0
    cam.data.clip_end = 1000.0
    # rig shares the camera frame so the light is the same relative to the picture in every view
    rig.matrix_world = Matrix.LocRotScale(Vector(centre), cam.rotation_euler.to_quaternion(), None)
    tgt.location = Vector(centre)
    bpy.context.view_layer.update()


# ------------------------------------------------------------------ render loop
for o in sc.objects:
    if o.name.startswith(('tooth_', 'pulp_', 'tpl_')):
        o.hide_render = True
        o.hide_viewport = True
count = 0
for fdi in (only or FDIS):
    ob = sc.objects.get(f'tooth_{fdi}')
    if ob is None:
        print('missing', fdi)
        continue
    ob.hide_render = False
    ob.hide_viewport = False
    keep = (ob.parent, ob.matrix_parent_inverse.copy(), ob.matrix_basis.copy())
    ob.parent = None                      # tooth local frame at the origin, no arch rotation
    ob.matrix_world = Matrix.Identity(4)
    paint(ob)
    V = np.empty(len(ob.data.vertices) * 3, np.float32)
    ob.data.vertices.foreach_get('co', V)
    V = V.reshape(-1, 3)
    zc = 0.5 * (V[:, 2].min() + V[:, 2].max())
    ctr = Vector((0, 0, zc))
    upper = fdi < 30
    up_turn = (0, 0, -1) if upper else (0, 0, 1)
    for deg in TURNS:
        rad = math.radians(deg)
        ob.rotation_mode = 'XYZ'
        ob.rotation_euler = (0, 0, -rad if upper else rad)
        aim((0, 1, 0), up_turn, ctr)
        sc.render.filepath = os.path.join(raw_dir, f'{fdi}_turn{deg:03d}.png')
        bpy.ops.render.render(write_still=True)
        count += 1
    ob.rotation_euler = (0, 0, 0)
    up_occ = (0, -1, 0)                   # facial (-Y) at the top of the picture
    for name, direction in (('occlusal', (0, 0, -1)), ('apical', (0, 0, 1))):
        aim(direction, up_occ, ctr)
        sc.render.filepath = os.path.join(raw_dir, f'{fdi}_{name}.png')
        bpy.ops.render.render(write_still=True)
        count += 1
    ob.hide_render = True
    ob.hide_viewport = True
    ob.parent, ob.matrix_parent_inverse, ob.matrix_basis = keep
    print('tooth', fdi, 'done', flush=True)
print('rendered', count, 'raw views into', raw_dir)
