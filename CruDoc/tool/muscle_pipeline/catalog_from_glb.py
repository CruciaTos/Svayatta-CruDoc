"""Rebuilds assets/muscle_viewer/catalog.json from body.glb alone.

The full pipeline (zexport.py + build_catalog.py) needs Blender and the
Z-Anatomy source. This fallback only needs the shipped model: every mesh
node is named by its catalog id (m_supraspinatus_muscle_r, b_scapula_l), so
ids, names and sides come from the names, and the body region from the
name, falling back to where the part sits on the body.

What it can't recover: Z-Anatomy's "superficial" flags and action tags.
No muscle is marked superficial (the "superficial muscles" toggle then
hides nothing) and has no action tags. Run the full pipeline for those.

    python catalog_from_glb.py            (from tool/muscle_pipeline)
"""

import json
import re
import struct
from pathlib import Path

ASSETS = Path(__file__).resolve().parents[2] / 'assets' / 'muscle_viewer'

# Name keywords first: the trunk and limbs overlap in height, so position
# alone can't tell a chest muscle from a back muscle or an arm muscle.
NAME_REGIONS = [
    (r'masseter|temporalis|pterygoid|buccinator|orbicularis|zygomatic|'
     r'levator labii|depressor|mentalis|risorius|nasalis|procerus|'
     r'frontalis|occipit|auricular|epicranius|tarsus|oculi|rectus (superior|'
     r'inferior|medialis|lateralis) bulbi|(superior|inferior) oblique muscle|'
     r'tongue|glossus|palat|uvula|pharyn|constrictor|platysma|corrugator|'
     r'levator palpebrae|septi nasi|modiolus', 'Head'),
    (r'sternocleidomastoid|scalen|longus colli|longus capitis|'
     r'hyoid|digastric|crico|arytenoid|thyro|vocal|colli|capitis', 'Neck'),
    (r'diaphragm|intercostal|pectoral|serratus anterior|subclavius|'
     r'transversus thoracis|subcostal|levatores costarum', 'Chest'),
    (r'trapezius|latissimus|rhomboid|levator scapulae|erector|iliocostalis|'
     r'longissimus|spinalis|multifidus|rotatores|interspinales|'
     r'intertransversarii|splenius|semispinalis|serratus posterior|'
     r'quadratus lumborum|thoracolumbar', 'Back'),
    (r'rectus abdominis|abdominal oblique|transversus abdominis|pyramidalis|cremaster',
     'Abdomen'),
    (r'gluteus|piriformis|gemellus|obturator|quadratus femoris|levator ani|'
     r'coccyg|pubo|ilio?coccyg|sphincter|perine|ischiocavernosus|'
     r'bulbospongiosus|psoas|iliacus|iliopsoas', 'Pelvis'),
    # Hand and foot share muscle names (interossei, digiti minimi).
    (r'\bfoot\b|plantar|hallucis', 'Lower limb'),
    (r'deltoid|supraspinatus|infraspinatus|teres|subscapularis|biceps brachii|'
     r'brachialis|brachioradialis|triceps|coracobrachialis|anconeus|'
     r'supinator|pronator|carpi|digitorum superficialis|digitorum profundus|'
     r'pollicis|palmar|digiti minimi(?! of foot)|lumbrical(?!.*foot)|'
     r'interossei(?!.*foot)|of hand|indicis|bicipital', 'Upper limb'),
    (r'femoris|vastus|sartorius|gracilis|adductor|pectineus|tensor fasciae|'
     r'iliotibial|popliteus|gastrocnemius|soleus|plantaris|tibialis|'
     r'peroneus|fibularis|hallucis|of foot|calcane|achilles|plantar|'
     r'digitorum longus|digitorum brevis|semitendinosus|semimembranosus|'
     r'hamstring', 'Lower limb'),
]
NAME_REGIONS = [(re.compile(p), r) for p, r in NAME_REGIONS]


def read_glb(path):
    data = path.read_bytes()
    length = struct.unpack('<I', data[12:16])[0]
    return json.loads(data[20:20 + length])


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)]
            for i in range(4)]


def local_matrix(node):
    if 'matrix' in node:
        m = node['matrix']  # column-major
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    tx, ty, tz = node.get('translation', [0, 0, 0])
    sx, sy, sz = node.get('scale', [1, 1, 1])
    x, y, z, w = node.get('rotation', [0, 0, 0, 1])
    rot = [
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ]
    return [
        [rot[0][0] * sx, rot[0][1] * sy, rot[0][2] * sz, tx],
        [rot[1][0] * sx, rot[1][1] * sy, rot[1][2] * sz, ty],
        [rot[2][0] * sx, rot[2][1] * sy, rot[2][2] * sz, tz],
        [0, 0, 0, 1],
    ]


def centers(gltf):
    """World-space bounding-box centre of every named root node."""
    nodes, meshes, acc = gltf['nodes'], gltf['meshes'], gltf['accessors']
    out = {}

    def walk(i, parent, root_name):
        node = nodes[i]
        world = mat_mul(parent, local_matrix(node))
        if 'mesh' in node:
            for prim in meshes[node['mesh']]['primitives']:
                a = acc[prim['attributes']['POSITION']]
                lo, hi = a['min'], a['max']
                if a.get('normalized'):
                    # Quantized positions: min/max are stored as integers.
                    scale = {5120: 127, 5121: 255, 5122: 32767,
                             5123: 65535}[a['componentType']]
                    lo = [v / scale for v in lo]
                    hi = [v / scale for v in hi]
                for corner in ([lo[0], lo[1], lo[2]], [hi[0], hi[1], hi[2]]):
                    p = [sum(world[r][c] * corner[c] for c in range(3))
                         + world[r][3] for r in range(3)]
                    box = out.setdefault(root_name, [p[:], p[:]])
                    box[0] = [min(box[0][k], p[k]) for k in range(3)]
                    box[1] = [max(box[1][k], p[k]) for k in range(3)]
        for child in node.get('children', []):
            walk(child, world, root_name)

    identity = [[float(r == c) for c in range(4)] for r in range(4)]
    for i in gltf['scenes'][gltf.get('scene', 0)]['nodes']:
        name = nodes[i].get('name', '')
        if name:
            walk(i, identity, name)
    return {n: [(lo + hi) / 2 for lo, hi in zip(*box)]
            for n, box in out.items()}


def split_id(node_id):
    kind = 'muscle' if node_id.startswith('m_') else 'bone'
    base = node_id[2:]
    side = 'M'
    if base.endswith('_r'):
        side, base = 'R', base[:-2]
    elif base.endswith('_l'):
        side, base = 'L', base[:-2]
    name = base.replace('_', ' ')
    return kind, side, name[:1].upper() + name[1:]


def region_by_position(c, body):
    """Fallback for names the keywords don't know."""
    (x0, y0, z0), (x1, y1, z1) = body
    h = (c[1] - y0) / (y1 - y0)            # 0 = feet, 1 = top of head
    off = abs(c[0] - (x0 + x1) / 2) / ((x1 - x0) / 2)
    if h > 0.88:
        return 'Head'
    if h > 0.82:
        return 'Neck'
    if off > 0.45 and h > 0.45:
        return 'Upper limb'
    if h < 0.47:
        return 'Lower limb'
    if h < 0.56:
        return 'Pelvis'
    front = c[2] > (z0 + z1) / 2
    if h < 0.66:
        return 'Abdomen' if front else 'Back'
    return 'Chest' if front else 'Back'


def main():
    gltf = read_glb(ASSETS / 'body.glb')
    where = centers(gltf)
    pts = list(where.values())
    body = ([min(p[k] for p in pts) for k in range(3)],
            [max(p[k] for p in pts) for k in range(3)])

    muscles, bones = [], []
    for node_id in sorted(where):
        kind, side, name = split_id(node_id)
        if kind == 'bone':
            bones.append(dict(id=node_id, name=name, side=side))
            continue
        low = name.lower()
        region = next((r for p, r in NAME_REGIONS if p.search(low)), None)
        region = region or region_by_position(where[node_id], body)
        muscles.append(dict(id=node_id, name=name, side=side, region=region,
                            group=None, superficial=False, actions=[]))

    out = ASSETS / 'catalog.json'
    out.write_text(json.dumps(dict(muscles=muscles, bones=bones),
                              separators=(',', ':')))
    from collections import Counter
    print(f'{out}: {len(muscles)} muscles, {len(bones)} bones')
    print(Counter(m['region'] for m in muscles))


if __name__ == '__main__':
    main()
