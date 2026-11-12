"""Workbench verification renders.
  blender -b --python blender/render_verify.py -- N
Writes tmp/verify_pass_N.png, verify_types_upper_N.png, verify_types_lower_N.png, verify_templates_N.png
(+ verify_pass_N_bottom.png : upper arch seen from below)."""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
D = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import numpy as np
import bpy
from mathutils import Vector, Matrix
import blib

N = sys.argv[sys.argv.index('--') + 1] if '--' in sys.argv else '1'
TMP = os.path.join(D, 'tmp')
bpy.ops.wm.open_mainfile(filepath=os.path.join(TMP, 'subject.blend'))
scene = bpy.context.scene
objs = {o.name: o for o in scene.objects}
teeth = {n: o for n, o in objs.items() if n.startswith('tooth_')}
pulps = {n: o for n, o in objs.items() if n.startswith('pulp_')}
tpls = {n: o for n, o in objs.items() if n.startswith('tpl_')}
ename = bpy.data.materials['mat_enamel']
tmpf = os.path.join(TMP, '_v.png')


def hide_all():
    for o in scene.objects:
        o.hide_render = True


def world_bbox(obs):
    pts = []
    for o in obs:
        for c in o.bound_box:
            pts.append(o.matrix_world @ Vector(c))
    a = np.array([[p.x, p.y, p.z] for p in pts])
    return a.min(0), a.max(0)


def shot(direction, up, centre, scale, size):
    blib.setup_render(scene, size, size)
    cam = blib.get_camera(scene)
    blib.aim_camera(cam, centre, direction, up, scale)
    blib.render_to(scene, tmpf)
    return blib.load_pixels(tmpf)


# ---------------------------------------------------------------- 1. dentition
hide_all()
for o in teeth.values():
    o.hide_render = False
lo, hi = world_bbox(teeth.values())
ctr = (lo + hi) / 2
S = 760
views = [('front', (0, 1, 0), (0, 0, 1), 86), ('back', (0, -1, 0), (0, 0, 1), 86),
         ('left', (1, 0, 0), (0, 0, 1), 86), ('right', (-1, 0, 0), (0, 0, 1), 86),
         ('top', (0, 0, -1), (0, 1, 0), 76), ('iso', (-0.55, 0.7, -0.45), (0, 0, 1), 80)]
tiles = []
for name, d, up, sc in views:
    if name == 'top':  # lower arch occlusal view: hide the upper arch
        for n, o in teeth.items():
            o.hide_render = (int(n.split('_')[1]) < 30)
    else:
        for o in teeth.values():
            o.hide_render = False
    tiles.append(shot(d, up, tuple(ctr), sc, S))
for o in teeth.values():
    o.hide_render = False
blib.save_pixels(blib.tile_images(tiles, 3), os.path.join(TMP, 'verify_pass_%s.png' % N))
for n, o in teeth.items():
    o.hide_render = int(n.split('_')[1]) > 30
bot = shot((0, 0, 1), (0, 1, 0), tuple(ctr), 76, S)
blib.save_pixels(bot, os.path.join(TMP, 'verify_pass_%s_bottom.png' % N))
print('sheet 1 done')

# ---------------------------------------------------------------- 2. per-type
def type_sheet(fdis, out):
    tl_ = []
    saved = {}
    for fdi in fdis:
        o = teeth['tooth_%d' % fdi]
        saved[o.name] = o.matrix_world.copy()
    rows = [((0, 1, 0), (0, 0, 1), 34), ((-1, 0, 0), (0, 0, 1), 34), ((0, 0, -1), (0, 1, 0), 18)]
    tiles_ = {}
    for fdi in fdis:
        o = teeth['tooth_%d' % fdi]
        po = pulps['pulp_%d' % fdi]
        hide_all()
        o.hide_render = False
        po.hide_render = True
        o.parent = None
        o.matrix_world = Matrix.Identity(4)
        bpy.context.view_layer.update()
        lo, hi = world_bbox([o])
        c = (lo + hi) / 2
        for ri, (d, up, sc) in enumerate(rows):
            cc = (0, 0, c[2]) if ri < 2 else (0, 0, 0)
            tiles_[(ri, fdi)] = shot(d, up, cc, sc, 340)
    arr = []
    for ri in range(3):
        for fdi in fdis:
            arr.append(tiles_[(ri, fdi)])
    blib.save_pixels(blib.tile_images(arr, len(fdis)), out)


# parent bookkeeping: keep original matrices so we can restore if needed (not saved back)
type_sheet(list(range(21, 29)), os.path.join(TMP, 'verify_types_upper_%s.png' % N))
type_sheet(list(range(41, 49)), os.path.join(TMP, 'verify_types_lower_%s.png' % N))
print('sheet 2 done')

# ---------------------------------------------------------------- 3. templates
bpy.ops.wm.open_mainfile(filepath=os.path.join(TMP, 'subject.blend'))
scene = bpy.context.scene
objs = {o.name: o for o in scene.objects}
tpls = [objs[n] for n in ['tpl_implant_fixture', 'tpl_implant_abutment', 'tpl_healing_cap', 'tpl_bracket', 'tpl_post']]
scales = [17, 9, 8, 6, 13]
d3 = (0.35, 0.85, -0.4)
tl_ = []
for o, sc in zip(tpls, scales):
    hide_all()
    o.hide_render = False
    lo, hi = world_bbox([o])
    tl_.append(shot(d3, (0, 0, 1), tuple((lo + hi) / 2), sc, 480))
# cut-away: first molar (tooth_26) at identity, half transparent enamel
hide_all()
t = objs['tooth_26']
p = objs['pulp_26']
t.parent = None
t.matrix_world = Matrix.Identity(4)
bpy.context.view_layer.update()
mt = bpy.data.materials['mat_enamel'].copy()
mt.diffuse_color = (0.93, 0.9, 0.82, 0.22)
t.data.materials[0] = mt
t.show_transparent = True
t.hide_render = False
p.hide_render = False
lo, hi = world_bbox([t])
tl_.append(shot((0.25, 0.85, -0.25), (0, 0, 1), tuple((lo + hi) / 2), 30, 480))
blib.save_pixels(blib.tile_images(tl_, 3), os.path.join(TMP, 'verify_templates_%s.png' % N))
print('sheet 3 done')
