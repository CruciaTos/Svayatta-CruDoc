"""Numeric checks on a built subject.blend (neighbour contacts, cusp heights, pulp clearance, manifold).
  blender -b --python blender/checks.py -- [blend] [out.json]
Prints a compact report and writes JSON (default tmp/checks.json)."""
import sys, os, json
import numpy as np
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
D = os.path.dirname(HERE)
A = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
blend = A[0] if A else os.path.join(D, 'tmp', 'subject.blend')
outp = A[1] if len(A) > 1 else os.path.join(D, 'tmp', 'checks.json')
bpy.ops.wm.open_mainfile(filepath=blend)
sc = bpy.context.scene
teeth = {int(o['fdi']): o for o in sc.objects if o.name.startswith('tooth_')}
pulps = {int(o.name.split('_')[1]): o for o in sc.objects if o.name.startswith('pulp_')}


def world(ob):
    me = ob.data
    V = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get('co', V)
    V = V.reshape(-1, 3).astype(np.float64)
    M = np.array(ob.matrix_world)
    Wv = V @ M[:3, :3].T + M[:3, 3]
    me.calc_loop_triangles()
    T = np.empty(len(me.loop_triangles) * 3, np.int32)
    me.loop_triangles.foreach_get('vertices', T)
    return V, Wv, T.reshape(-1, 3)


def bvh(Vw, T):
    return BVHTree.FromPolygons([tuple(v) for v in Vw], [tuple(t) for t in T], all_triangles=True)


def oriented(Vw, T):
    # make winding outward using signed volume
    a, b, c = Vw[T[:, 0]], Vw[T[:, 1]], Vw[T[:, 2]]
    vol = np.einsum('ij,ij->i', a, np.cross(b, c)).sum() / 6.0
    return T if vol > 0 else T[:, [0, 2, 1]]


def signed_to(B, P, maxd=2.0):
    """smallest distance from points P to BVH B and penetration (inside) depth."""
    gap, pen = 9e9, 0.0
    for p in P:
        r = B.find_nearest(Vector(p), maxd)
        if r[0] is None:
            continue
        d = r[3]
        inside = (Vector(p) - r[0]).dot(r[1]) < 0
        if inside:
            pen = max(pen, d)
        else:
            gap = min(gap, d)
    return gap, pen


def manifold(T):
    e = np.sort(np.concatenate([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]]), axis=1)
    _, c = np.unique(e, axis=0, return_counts=True)
    return bool((c == 2).all()), int((c != 2).sum())


W = {}
res = {'cusp': {}, 'pairs': {}, 'manifold': {}, 'tris': {}, 'pulp': {}}
for fdi, ob in teeth.items():
    V, Wv, T = world(ob)
    T = oriented(Wv, T)
    W[fdi] = (V, Wv, T, bvh(Wv, T))
    upper = fdi < 30
    # viewer y == blender z (occlusal plane z=0). crown tip = extreme toward plane
    tip = Wv[:, 2].min() if upper else Wv[:, 2].max()
    res['cusp'][fdi] = float(abs(tip))
    res['manifold'][fdi] = manifold(T)
    res['tris'][fdi] = int(len(T))
pairs = []
for q in (1, 2, 3, 4):
    for i in range(1, 8):
        pairs.append((q * 10 + i, q * 10 + i + 1))
pairs += [(11, 21), (31, 41)]
for a, b in pairs:
    g1, p1 = signed_to(W[b][3], W[a][1][W[a][0][:, 2] > -2.0] if False else W[a][1])
    g2, p2 = signed_to(W[a][3], W[b][1])
    gap = min(g1, g2)
    pen = max(p1, p2)
    res['pairs']['%d-%d' % (a, b)] = float(-pen) if pen > 0.02 else float(gap if gap < 9e8 else 99.0)
# pulp clearance in the tooth local frame
for fdi, po in pulps.items():
    _, Wp, _ = world(po)
    _, Wt, Tt, Bt = W[fdi][0], W[fdi][1], W[fdi][2], W[fdi][3]
    mind = 9e9
    for p in Wp:
        r = Bt.find_nearest(Vector(p), 5.0)
        if r[0] is not None:
            d = r[3] if (Vector(p) - r[0]).dot(r[1]) < 0 else -r[3]
            mind = min(mind, d)
    res['pulp'][fdi] = float(mind)
json.dump(res, open(outp, 'w'))
print('CHECKS written', outp)
print('pairs', {k: round(v, 2) for k, v in res['pairs'].items()})
print('cusp', {k: round(v, 1) for k, v in sorted(res['cusp'].items())})
print('pulp_min', round(min(res['pulp'].values()), 2), 'manifold_all', all(m[0] for m in res['manifold'].values()),
      'tris', sum(res['tris'].values()))
