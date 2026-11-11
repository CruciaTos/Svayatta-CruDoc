"""Build the whole dentition + hardware templates from scene_manifest.json,
save tmp/subject.blend and export public/models/subject.glb.

  blender -b --python blender/build.py -- [--no-export] [--no-cache]
"""
import sys, os, json, hashlib, pickle, time
import numpy as np
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
D = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import toothlib as tl
import shapes
import hardware
import blib

ARGS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
os.makedirs(os.path.join(D, 'tmp', 'cache'), exist_ok=True)
os.makedirs(os.path.join(D, 'public', 'models'), exist_ok=True)

man = json.load(open(os.path.join(D, 'scene_manifest.json'), encoding='utf-8'))
LIBSRC = open(os.path.join(HERE, 'toothlib.py'), encoding='utf-8').read()


def build_type(tid):
    spec = shapes.SPECS[tid]
    key = hashlib.md5((LIBSRC + repr(sorted(spec.items(), key=lambda kv: kv[0]))).encode()).hexdigest()[:12]
    cp = os.path.join(D, 'tmp', 'cache', '%s_%s.pkl' % (tid, key))
    if os.path.exists(cp) and '--no-cache' not in ARGS:
        return pickle.load(open(cp, 'rb'))
    t0 = time.time()
    r = tl.build_tooth_mesh(spec)
    fit = r['fit']
    V = tl.apply_fit(r['V'], fit)
    N = tl.apply_fit_normals(r['N'], fit)
    T = tl.fix_winding(V, r['T'], N)
    p = tl.build_pulp_mesh(r['tooth'], spec, fit)
    PV = tl.apply_fit(p['V'], fit)
    PN = tl.apply_fit_normals(p['N'], fit)
    PT = tl.fix_winding(PV, p['T'], PN)
    out = dict(V=V, T=T, N=N, C=r['C'], PV=PV, PT=PT, PN=PN, fit=fit)
    pickle.dump(out, open(cp, 'wb'))
    print('built type %s: %d tris, pulp %d tris, %.1fs' % (tid, len(T), len(PT), time.time() - t0))
    return out


# ------------------------------------------------------------------ scene
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
mats = blib.make_materials()


def empty(name, parent=None, loc=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = 'PLAIN_AXES'
    e.empty_display_size = 2.0
    scene.collection.objects.link(e)
    e.location = loc
    if parent is not None:
        e.parent = parent
    return e


subject = empty('subject')
arch_upper = empty('arch_upper', subject)
hp = man['jawHinge']['point']  # viewer frame
hinge_loc = (hp[0], -hp[2], hp[1])
jaw_hinge = empty('jaw_hinge', subject, hinge_loc)
arch_lower = empty('arch_lower', jaw_hinge)
bpy.context.view_layer.update()
# arch_lower sits at world identity: parent inverse cancels the hinge translation
arch_lower.matrix_parent_inverse = jaw_hinge.matrix_world.inverted()
arch_lower.location = (0, 0, 0)
templates = empty('templates', subject)
bpy.context.view_layer.update()

cache = {}
stats = []
for part in man['parts']:
    if part['kind'] != 'tooth':
        continue
    tid = part['typeId']
    if tid not in cache:
        cache[tid] = build_type(tid)
    c = cache[tid]
    dims = part['dims']
    spec = shapes.SPECS[tid]
    for k_m, k_s in (('crownHeight', 'H'), ('rootLength', 'L'), ('md', 'md'), ('bl', 'bl')):
        if abs(dims[k_m] - spec[k_s]) > 1e-6:
            print('WARNING: %s %s manifest %s vs spec %s' % (tid, k_m, dims[k_m], spec[k_s]))
    V, T, N, PV, PT, PN = c['V'].copy(), c['T'].copy(), c['N'].copy(), c['PV'].copy(), c['PT'].copy(), c['PN'].copy()
    if part['mesialSign'] == -1:
        V[:, 0] *= -1
        N[:, 0] *= -1
        T = T[:, [0, 2, 1]]
        PV[:, 0] *= -1
        PN[:, 0] *= -1
        PT = PT[:, [0, 2, 1]]
    fdi = part['fdi']
    ob = blib.make_mesh_object('tooth_%d' % fdi, V, T, N, c['C'], mats['enamel'])
    parent = arch_upper if part['arch'] == 'upper' else arch_lower
    ob.parent = parent
    ob.matrix_world = Matrix(part['blenderMatrix'])
    ob['fdi'] = int(fdi)
    ob['typeId'] = tid
    ob['mesialSign'] = int(part['mesialSign'])
    ob['crownHeight'] = float(dims['crownHeight'])
    ob['rootLength'] = float(dims['rootLength'])
    ob['md'] = float(dims['md'])
    ob['bl'] = float(dims['bl'])
    po = blib.make_mesh_object('pulp_%d' % fdi, PV, PT, PN, None, mats['pulp'])
    po.parent = ob
    stats.append((ob.name, len(T), len(PT)))

# ------------------------------------------------------------- templates
tpl_defs = [('tpl_implant_fixture', hardware.fixture, 'titanium'),
            ('tpl_implant_abutment', hardware.abutment, 'titanium'),
            ('tpl_healing_cap', hardware.healing_cap, 'titanium'),
            ('tpl_bracket', hardware.bracket, 'steel'),
            ('tpl_post', hardware.post, 'post')]
mn_ids = [t['nodeId'] for t in man['templates']]
assert mn_ids == [d[0] for d in tpl_defs], mn_ids
for i, (name, fn, mk) in enumerate(tpl_defs):
    r = fn()
    ob = blib.make_mesh_object(name, r['V'], r['T'], r['N'], None, mats[mk])
    ob.parent = templates
    ob.location = (-24 + 12 * i, 0, -80)
    stats.append((name, len(r['T']), 0))

bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(D, 'tmp', 'subject.blend'))

tt = sum(s[1] for s in stats if s[0].startswith('tooth_'))
print('TOTAL tooth tris', tt, 'pulp tris', sum(s[2] for s in stats))
for s in stats:
    if s[0].startswith('tpl_'):
        print(' ', s)

if '--no-export' not in ARGS:
    out = os.path.join(D, 'public', 'models', 'subject.glb')
    for o in bpy.context.scene.objects:
        o.select_set(True)
    kw = dict(filepath=out, export_format='GLB', export_yup=True, export_apply=True, export_extras=True,
              export_cameras=False, export_lights=False, export_animations=False, export_normals=True,
              export_vertex_color='ACTIVE', export_active_vertex_color_when_no_material=True,
              export_draco_mesh_compression_enable=True, export_draco_mesh_compression_level=6,
              export_draco_position_quantization=14, export_draco_normal_quantization=10,
              export_draco_color_quantization=8, export_draco_generic_quantization=12,
              use_selection=False)
    bpy.ops.export_scene.gltf(**kw)
    print('exported', out, os.path.getsize(out), 'bytes')
