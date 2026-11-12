"""Close-up check renders of single teeth (facial + occlusal), each image <= 900 px wide.
  blender -b --python blender/render_closeups.py -- OUTDIR TAG FDI [FDI ...]
Writes OUTDIR/TAG_<fdi>.png : left = facial view (neighbours shown), right = occlusal view."""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
D = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import numpy as np
import bpy
from mathutils import Vector
import blib

A = sys.argv[sys.argv.index('--') + 1:]
OUT, TAG, FDIS = A[0], A[1], [int(x) for x in A[2:]]
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=os.path.join(D, 'tmp', 'subject.blend'))
sc = bpy.context.scene
teeth = {int(o['fdi']): o for o in sc.objects if o.name.startswith('tooth_')}
tmpf = os.path.join(D, 'tmp', '_cu.png')
for o in sc.objects:
    o.hide_render = o.name.startswith('pulp_') or o.name.startswith('tpl_')
bpy.context.view_layer.update()


def show(ids):
    for f, o in teeth.items():
        o.hide_render = f not in ids


def neighbours(f):
    q, i = divmod(f, 10)
    out = {f}
    for j in (i - 1, i + 1):
        if 1 <= j <= 8:
            out.add(q * 10 + j)
    if i == 1:  # across the midline
        out.add({1: 21, 2: 11, 3: 41, 4: 31}[q])
    return out


tiles = []
for f in FDIS:
    ob = teeth[f]
    M = ob.matrix_world
    R = M.to_3x3()
    facial = (R @ Vector((0, -1, 0))).normalized()
    coronal = (R @ Vector((0, 0, 1))).normalized()
    ctr = M.translation + coronal * (ob['crownHeight'] * 0.45)
    imgs = []
    for view in ('facial', 'occlusal'):
        blib.setup_render(sc, 450, 450)
        cam = blib.get_camera(sc)
        if view == 'facial':
            show(neighbours(f))
            blib.aim_camera(cam, ctr, -facial, coronal, 24.0)
        else:
            show({k for k in teeth if (k < 30) == (f < 30)})
            blib.aim_camera(cam, ctr, -coronal, facial, 24.0)
        blib.render_to(sc, tmpf)
        imgs.append(blib.load_pixels(tmpf))
    blib.save_pixels(blib.tile_images(imgs, 2, pad=0), os.path.join(OUT, '%s_%d.png' % (TAG, f)))
print('closeups done', FDIS)
