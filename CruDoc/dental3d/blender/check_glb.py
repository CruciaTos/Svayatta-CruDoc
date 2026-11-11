"""Parse public/models/subject.glb and assert the contract.   python blender/check_glb.py"""
import json, os, struct, sys

D = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
path = os.path.join(D, 'public', 'models', 'subject.glb')
man = json.load(open(os.path.join(D, 'scene_manifest.json'), encoding='utf-8'))

raw = open(path, 'rb').read()
magic, ver, length = struct.unpack('<4sII', raw[:12])
assert magic == b'glTF' and length == len(raw), 'bad GLB header'
clen, ctype = struct.unpack('<II', raw[12:20])
assert ctype == 0x4E4F534A
g = json.loads(raw[20:20 + clen])

nodes = g['nodes']
byname = {n['name']: n for n in nodes}
errors = []


def need(name):
    if name not in byname:
        errors.append('missing node ' + name)


for n in ['subject', 'arch_upper', 'arch_lower', 'jaw_hinge', 'templates']:
    need(n)
teeth = [p for p in man['parts'] if p['kind'] == 'tooth']
assert len(teeth) == 32
for p in teeth:
    need('tooth_%d' % p['fdi'])
    need('pulp_%d' % p['fdi'])
for t in man['templates']:
    need(t['nodeId'])
if errors:
    print('\n'.join(errors))
    sys.exit(1)

# parent map
parent = {}
for i, n in enumerate(nodes):
    for c in n.get('children', []):
        parent[c] = i
idx = {n['name']: i for i, n in enumerate(nodes)}


def pname(name):
    pi = parent.get(idx[name])
    return nodes[pi]['name'] if pi is not None else None


assert pname('arch_upper') == 'subject' and pname('jaw_hinge') == 'subject' and pname('templates') == 'subject'
assert pname('arch_lower') == 'jaw_hinge'
for p in teeth:
    exp = 'arch_upper' if p['arch'] == 'upper' else 'arch_lower'
    assert pname('tooth_%d' % p['fdi']) == exp, ('parent', p['fdi'])
    assert pname('pulp_%d' % p['fdi']) == 'tooth_%d' % p['fdi']
for t in man['templates']:
    assert pname(t['nodeId']) == 'templates'

hp = man['jawHinge']['point']
ht = byname['jaw_hinge'].get('translation', [0, 0, 0])
assert max(abs(a - b) for a, b in zip(ht, hp)) < 0.01, ('hinge', ht, hp)

worst_t = worst_q = 0.0
for p in teeth:
    n = byname['tooth_%d' % p['fdi']]
    t = n.get('translation', [0, 0, 0])
    q = n.get('rotation', [0, 0, 0, 1])
    dt = max(abs(a - b) for a, b in zip(t, p['position']))
    mq = p['quaternion']
    d1 = max(abs(a - b) for a, b in zip(q, mq))
    d2 = max(abs(a + b) for a, b in zip(q, mq))
    dq = min(d1, d2)
    worst_t, worst_q = max(worst_t, dt), max(worst_q, dq)
    assert dt < 0.01, ('translation', p['fdi'], t, p['position'])
    assert dq < 1e-3, ('rotation', p['fdi'], q, mq)
    ex = n.get('extras', {})
    for k in ('fdi', 'typeId', 'mesialSign', 'crownHeight', 'rootLength', 'md', 'bl'):
        assert k in ex, ('extras', p['fdi'], k)
    assert ex['fdi'] == p['fdi'] and ex['mesialSign'] == p['mesialSign']


def prim_info(node):
    m = g['meshes'][node['mesh']]
    tris = 0
    has_col = False
    draco = False
    for pr in m['primitives']:
        tris += g['accessors'][pr['indices']]['count'] // 3
        has_col = has_col or ('COLOR_0' in pr['attributes'])
        draco = draco or ('KHR_draco_mesh_compression' in pr.get('extensions', {}))
    return tris, has_col, draco


tot = 0
ptot = 0
maxby = {}
for p in teeth:
    n = byname['tooth_%d' % p['fdi']]
    tris, col, dr = prim_info(n)
    assert col, ('COLOR_0 missing', p['fdi'])
    assert dr, 'draco missing'
    tot += tris
    maxby[p['typeId']] = max(maxby.get(p['typeId'], 0), tris)
    ptris, _, _ = prim_info(byname['pulp_%d' % p['fdi']])
    ptot += ptris
    assert ptris <= 600
cls_budget = {'incisor': 3500, 'canine': 3500, 'premolar': 5000, 'molar': 7500}
for p in teeth:
    tris, _, _ = prim_info(byname['tooth_%d' % p['fdi']])
    assert tris <= cls_budget[p['toothClass']], ('budget', p['fdi'], tris)
assert tot <= 170000, tot
for t in man['templates']:
    tris, _, _ = prim_info(byname[t['nodeId']])
    lim = 8000 if t['nodeId'] == 'tpl_implant_fixture' else 4000
    assert tris <= lim, (t['nodeId'], tris)
    print('  %-22s %5d tris' % (t['nodeId'], tris))

assert 'cameras' not in g and 'animations' not in g, 'cameras/animations present'
assert 'KHR_draco_mesh_compression' in g.get('extensionsUsed', [])
print('tooth triangle total   :', tot, '(budget 170000)')
print('per-type max triangles :', dict(sorted(maxby.items())))
print('pulp triangle total    :', ptot)
print('worst translation err  : %.5f mm   worst quaternion err: %.2e' % (worst_t, worst_q))
print('file size              : %d bytes (%.2f MB)' % (len(raw), len(raw) / 1048576))
print('CHECK OK: all nodes present, transforms match manifest, COLOR_0 on all teeth')
