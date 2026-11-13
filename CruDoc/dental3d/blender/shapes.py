"""Per-class shape parameters for the 16 tooth types (see toothlib.Tooth).

Coordinates: +X mesial, -Y facial / +Y lingual, +Z toward the crown tip, mm.
Ring tables are indexed by u = z / crownHeight (u=0 neck, u=1 incisal/occlusal).
xm / xd = mesial / distal half extent, yf / yl = facial / lingual half extent.
"""
import copy


def pk(a, b=None, s=(0.8, 0.8, 0.8, 0.8), r=0.7, cusp=False, k=0.25):
    return dict(a=a, b=b, s=s, r=r, cusp=cusp, k=k)


def scaled(base, fx, fy, fz, **over):
    s = copy.deepcopy(base)
    s['xm'] = [v * fx for v in s['xm']]
    s['xd'] = [v * fx for v in s['xd']]
    s['yf'] = [v * fy for v in s['yf']]
    s['yl'] = [v * fy for v in s['yl']]
    s['H'] = base['H'] * fz
    for p in s['peaks']:
        p['a'] = (p['a'][0] * fx, p['a'][1] * fy, p['a'][2] * fz)
        if p['b']:
            p['b'] = (p['b'][0] * fx, p['b'][1] * fy, p['b'][2] * fz)
    s['pits'] = [(x * fx, y * fy, d, sg) for (x, y, d, sg) in s['pits']]
    nf = []
    for ft in s['feats']:
        ft = list(ft)
        ft[2] *= fx
        ft[5] *= fz
        ft[6] *= fz if ft[0] == 'groove' or True else 1
        nf.append(tuple(ft))
    s['feats'] = nf
    for r in s['roots']:
        r['c0'] = (r['c0'][0] * fx, r['c0'][1] * fy)
        r['c1'] = (r['c1'][0] * fx, r['c1'][1] * fy)
        r['ex0'] *= fx
        r['ey0'] *= fy
    s.update(over)
    return s


def _root(**kw):
    return kw


SPECS = {}

# --------------------------------------------------------------- incisors
H = 10.5
SPECS['U1'] = dict(
    H=H, L=13, md=8.5, bl=7, n=2.7, tris=3000,
    us=[0, .15, .4, .7, .85, 1.0, 1.1],
    xm=[3.5, 3.62, 3.85, 4.1, 4.22, 4.25, 4.2],
    xd=[3.5, 3.58, 3.8, 4.0, 3.9, 3.2, 2.7],
    yf=[3.0, 3.45, 3.3, 2.6, 1.9, 1.0, 0.75],
    yl=[3.0, 3.9, 3.1, 1.6, 0.95, 0.5, 0.3],
    feats=[('blob', 'l', 0.0, 1.7, 0.75, 6.2, 1.8)],
    peaks=[pk((-4.6, 0, H - 0.5), (4.6, 0, H), s=(3, 3, 3, 3), r=0.3)],
    pits=[], ceil_k=0.45, trunk_len=1.0, trunk_f=0.82, trunk_cap=1.2, k_union=1.0,
    roots=[_root(name='root', L=13, c0=(0, 0), c1=(0, 0), ex0=2.85, ey0=2.75, ax=0.18, px=0.9,
                 ay=0.2, py=0.9, lr=1.5, dc=1.2, rc0=0.5)],
    pulp=dict(rx=2.8, ry=1.3, horns=[(-2.6, -0.2), (0.0, -0.2), (2.6, -0.2)], hr=0.55),
)
H = 9
SPECS['U2'] = dict(
    H=H, L=13, md=6.5, bl=6, n=2.7, tris=3000,
    us=[0, .15, .4, .7, .85, 1.0, 1.1],
    xm=[2.5, 2.9, 3.15, 3.25, 3.25, 3.2, 3.2],
    xd=[2.5, 2.8, 3.05, 3.15, 2.9, 2.1, 1.6],
    yf=[2.5, 2.85, 2.65, 2.1, 1.5, 0.85, 0.6],
    yl=[2.5, 3.1, 2.4, 1.3, 0.8, 0.4, 0.3],
    feats=[('blob', 'l', 0.0, 1.3, 0.8, 5.3, 1.6)],
    peaks=[pk((-3.6, 0, H - 0.7), (3.6, 0, H), s=(3, 3, 3, 3), r=0.3)],
    pits=[], ceil_k=0.45, trunk_len=1.0, trunk_f=0.82, trunk_cap=1.2, k_union=1.0,
    roots=[_root(name='root', L=13, c0=(0, 0), c1=(0, 0), ex0=2.1, ey0=2.3, ax=0.18, px=0.9,
                 ay=0.2, py=0.9, lr=1.5, dc=1.6, rc0=0.42)],
    pulp=dict(rx=2.2, ry=1.1, horns=[(-1.8, -0.2), (0.0, -0.2), (1.8, -0.2)], hr=0.5),
)
H = 9
SPECS['L1'] = dict(
    H=H, L=12.5, md=5, bl=6, n=2.7, tris=3000,
    us=[0, .15, .4, .7, .85, 1.0, 1.1],
    xm=[1.75, 2.1, 2.35, 2.45, 2.5, 2.5, 2.45],
    xd=[1.75, 2.05, 2.3, 2.4, 2.45, 2.3, 2.0],
    yf=[2.65, 2.9, 2.55, 1.9, 1.35, 0.75, 0.55],
    yl=[2.65, 3.1, 2.3, 1.3, 0.75, 0.4, 0.3],
    feats=[('blob', 'l', 0.0, 1.0, 0.45, 5.2, 1.5)],
    peaks=[pk((-2.8, 0, H - 0.2), (2.8, 0, H), s=(3, 3, 3, 3), r=0.3)],
    pits=[], ceil_k=0.4, trunk_len=1.0, trunk_f=0.85, trunk_cap=1.2, k_union=0.9,
    roots=[_root(name='root', L=12.5, c0=(0, 0), c1=(0, 0), ex0=1.55, ey0=2.5, ax=0.3, px=0.95,
                 ay=0.25, py=0.9, lr=1.5, dc=0.8, rc0=0.38)],
    pulp=dict(rx=1.9, ry=1.2, horns=[(-1.5, -0.1), (0.0, -0.1), (1.5, -0.1)], hr=0.45),
)
H = 9.5
SPECS['L2'] = dict(
    H=H, L=14, md=5.5, bl=6.5, n=2.7, tris=3000,
    us=[0, .15, .4, .7, .85, 1.0, 1.1],
    xm=[2.0, 2.35, 2.6, 2.7, 2.75, 2.75, 2.7],
    xd=[2.0, 2.3, 2.55, 2.65, 2.6, 2.3, 1.9],
    yf=[2.9, 3.2, 2.8, 2.1, 1.5, 0.85, 0.6],
    yl=[2.9, 3.3, 2.5, 1.4, 0.8, 0.4, 0.3],
    feats=[('blob', 'l', 0.0, 1.1, 0.5, 5.5, 1.6)],
    peaks=[pk((-3.0, 0, H - 0.4), (3.0, 0, H), s=(3, 3, 3, 3), r=0.3)],
    pits=[], ceil_k=0.4, trunk_len=1.0, trunk_f=0.85, trunk_cap=1.2, k_union=0.9,
    roots=[_root(name='root', L=14, c0=(0, 0), c1=(0, 0), ex0=1.8, ey0=2.8, ax=0.3, px=0.95,
                 ay=0.25, py=0.9, lr=1.5, dc=1.0, rc0=0.4)],
    pulp=dict(rx=2.0, ry=1.3, horns=[(-1.6, -0.1), (0.0, -0.1), (1.6, -0.1)], hr=0.45),
)

# --------------------------------------------------------------- canines
H = 10
SPECS['U3'] = dict(
    H=H, L=17, md=7.5, bl=8, n=2.5, tris=3200,
    us=[0, .15, .4, .6, .8, .92, 1.0, 1.1],
    xm=[2.75, 3.2, 3.6, 3.75, 3.3, 2.2, 1.3, 0.8],
    xd=[2.75, 3.2, 3.7, 3.5, 2.7, 1.6, 0.9, 0.6],
    yf=[3.5, 3.9, 3.5, 3.0, 2.3, 1.6, 1.1, 0.8],
    yl=[3.5, 4.1, 3.1, 2.3, 1.5, 0.9, 0.6, 0.4],
    feats=[('blob', 'f', 0.2, 1.2, -0.35, 5.5, 3.0)],
    peaks=[pk((0.3, -0.2, H), None, s=(1.0, 0.9, 2.0, 2.0), r=0.85, cusp=True)],
    pits=[], ceil_k=0.5, trunk_len=1.0, trunk_f=0.82, trunk_cap=1.2, k_union=1.0,
    roots=[_root(name='root', L=17, c0=(0, 0), c1=(0, 0), ex0=2.5, ey0=3.4, ax=0.22, px=0.85,
                 ay=0.22, py=0.8, lr=1.6, dc=1.3, rc0=0.5)],
    pulp=dict(rx=2.4, ry=1.8, horns=[(0.3, -0.2)], hr=0.65),
)
H = 11
SPECS['L3'] = dict(
    H=H, L=16, md=7, bl=7.5, n=2.5, tris=3200,
    us=[0, .15, .4, .6, .8, .92, 1.0, 1.1],
    xm=[2.75, 3.1, 3.4, 3.5, 3.1, 2.0, 1.2, 0.8],
    xd=[2.75, 3.1, 3.5, 3.3, 2.5, 1.5, 0.9, 0.6],
    yf=[3.5, 3.7, 3.3, 2.8, 2.1, 1.5, 1.0, 0.8],
    yl=[3.5, 3.8, 2.9, 2.1, 1.4, 0.8, 0.55, 0.4],
    feats=[('blob', 'f', 0.2, 1.1, -0.3, 6.0, 3.2)],
    peaks=[pk((0.3, -0.2, H), None, s=(1.0, 0.9, 2.0, 2.0), r=0.85, cusp=True)],
    pits=[], ceil_k=0.5, trunk_len=1.0, trunk_f=0.82, trunk_cap=1.2, k_union=1.0,
    roots=[_root(name='root', L=16, c0=(0, 0), c1=(0, 0), ex0=2.45, ey0=3.2, ax=0.22, px=0.85,
                 ay=0.22, py=0.8, lr=1.6, dc=1.2, rc0=0.5)],
    pulp=dict(rx=2.2, ry=1.7, horns=[(0.3, -0.2)], hr=0.65),
)

# --------------------------------------------------------------- premolars
H = 8.5
_pm_us = [0, .15, .35, .6, .85, 1.0, 1.1]
SPECS['U4'] = dict(
    H=H, L=14, md=7, bl=9, n=2.3, tris=4500, us=_pm_us,
    xm=[2.5, 2.95, 3.3, 3.5, 3.4, 3.1, 2.9],
    xd=[2.5, 2.9, 3.2, 3.4, 3.3, 3.0, 2.8],
    yf=[4.0, 4.5, 4.6, 4.2, 3.7, 3.3, 3.0],
    yl=[4.0, 4.3, 4.4, 4.4, 3.8, 3.2, 2.9],
    feats=[('blob', 'f', 0.3, 1.4, -0.3, 4.5, 2.5)],
    peaks=[
        pk((0.3, -2.3, H), None, s=(0.75, 0.75, 1.4, 0.8), r=0.8, cusp=True),
        pk((0.1, 2.4, H - 1.0), None, s=(0.75, 0.75, 0.8, 1.4), r=0.8, cusp=True),
        pk((2.7, -1.8, H - 1.6), (2.7, 1.8, H - 1.9), s=(1.6, 1.0, 1.5, 1.5), r=0.5),
        pk((-2.7, -1.8, H - 1.8), (-2.7, 1.8, H - 2.0), s=(1.0, 1.6, 1.5, 1.5), r=0.5),
    ],
    pits=[(2.0, 0.7, 0.5, 0.7), (-2.0, 0.7, 0.5, 0.7)],
    ceil_k=0.5, trunk_len=5.0, trunk_f=0.82, trunk_cap=2.2, k_union=1.0,
    roots=[
        _root(name='rootB', L=13.2, c0=(0, -2.0), c1=(-0.3, -3.4), ts=0.4, ex0=1.9, ey0=1.55,
              ax=0.3, px=0.9, lr=1.3, dc=0.9, rc0=0.38),
        _root(name='rootP', L=14, c0=(0, 2.0), c1=(0, 3.2), ts=0.4, ex0=1.9, ey0=1.6,
              ax=0.3, px=0.9, lr=1.3, dc=0.7, rc0=0.38),
    ],
    pulp=dict(rx=2.4, ry=3.0, hr=0.6),
)
SPECS['U5'] = dict(
    H=H, L=14, md=7, bl=9, n=2.3, tris=4500, us=_pm_us,
    xm=[2.5, 2.95, 3.3, 3.5, 3.4, 3.1, 2.9],
    xd=[2.5, 2.9, 3.2, 3.4, 3.3, 3.0, 2.8],
    yf=[4.0, 4.5, 4.6, 4.2, 3.7, 3.3, 3.0],
    yl=[4.0, 4.3, 4.4, 4.4, 3.8, 3.2, 2.9],
    feats=[('blob', 'f', 0.3, 1.4, -0.25, 4.5, 2.5)],
    peaks=[
        pk((0.2, -2.2, H), None, s=(0.75, 0.75, 1.4, 0.8), r=0.8, cusp=True),
        pk((0.1, 2.2, H - 0.3), None, s=(0.75, 0.75, 0.8, 1.4), r=0.8, cusp=True),
        pk((2.7, -1.8, H - 1.6), (2.7, 1.8, H - 1.8), s=(1.6, 1.0, 1.5, 1.5), r=0.5),
        pk((-2.7, -1.8, H - 1.7), (-2.7, 1.8, H - 1.9), s=(1.0, 1.6, 1.5, 1.5), r=0.5),
    ],
    pits=[(2.0, 0.0, 0.5, 0.7), (-2.0, 0.0, 0.5, 0.7)],
    ceil_k=0.5, trunk_len=1.0, trunk_f=0.84, trunk_cap=1.2, k_union=1.0,
    roots=[_root(name='root', L=14, c0=(0, 0), c1=(0, 0), ex0=2.1, ey0=3.4, ax=0.25, px=0.9,
                 ay=0.25, py=0.8, lr=1.5, dc=1.2, rc0=0.5)],
    pulp=dict(rx=2.4, ry=3.0, hr=0.6),
)
H = 8.5
SPECS['L4'] = dict(
    H=H, L=14, md=7, bl=7.5, n=2.2, tris=4500, us=_pm_us,
    xm=[2.5, 2.95, 3.3, 3.5, 3.35, 3.0, 2.8],
    xd=[2.5, 2.9, 3.2, 3.4, 3.25, 2.9, 2.7],
    yf=[3.25, 3.75, 3.85, 3.6, 3.2, 2.8, 2.6],
    yl=[3.25, 3.5, 3.5, 3.0, 2.3, 1.8, 1.5],
    feats=[('blob', 'f', 0.2, 1.3, -0.25, 4.5, 2.5)],
    peaks=[
        pk((0.2, -1.6, H), None, s=(0.8, 0.8, 1.3, 0.9), r=0.8, cusp=True),
        pk((0.2, 2.0, H - 2.9), None, s=(0.9, 0.9, 0.9, 1.4), r=0.6, cusp=True),
        pk((0.2, -1.6, H - 0.4), (0.2, 1.6, H - 2.7), s=(1.2, 1.2, 1.2, 1.2), r=0.5),
        pk((2.6, -1.4, H - 2.3), (2.6, 1.2, H - 2.7), s=(1.5, 1.0, 1.4, 1.4), r=0.5),
        pk((-2.6, -1.4, H - 2.4), (-2.6, 1.2, H - 2.8), s=(1.0, 1.5, 1.4, 1.4), r=0.5),
    ],
    pits=[], ceil_k=0.5, trunk_len=1.0, trunk_f=0.84, trunk_cap=1.2, k_union=1.0,
    roots=[_root(name='root', L=14, c0=(0, 0), c1=(0, 0), ex0=2.1, ey0=2.9, ax=0.25, px=0.9,
                 ay=0.25, py=0.8, lr=1.5, dc=1.2, rc0=0.5)],
    pulp=dict(rx=2.4, ry=2.4, hr=0.6, horns=[(0.2, -1.6), (0.2, 1.4)]),
)
H = 8
SPECS['L5'] = dict(
    H=H, L=14.5, md=7, bl=8, n=2.1, tris=4500, us=_pm_us,
    xm=[2.5, 2.95, 3.3, 3.5, 3.4, 3.1, 2.9],
    xd=[2.5, 2.9, 3.2, 3.4, 3.3, 3.0, 2.8],
    yf=[3.5, 4.0, 4.0, 3.7, 3.3, 2.9, 2.6],
    yl=[3.5, 3.9, 4.0, 3.7, 3.1, 2.6, 2.3],
    feats=[('blob', 'f', 0.2, 1.3, -0.25, 4.2, 2.5)],
    peaks=[
        pk((0.2, -1.9, H), None, s=(0.75, 0.75, 1.3, 0.8), r=0.8, cusp=True),
        pk((1.7, 2.2, H - 1.5), None, s=(0.8, 0.8, 0.8, 1.3), r=0.65, cusp=True),
        pk((-1.7, 2.2, H - 2.1), None, s=(0.8, 0.8, 0.8, 1.3), r=0.6, cusp=True),
        pk((2.7, -1.4, H - 2.0), (2.7, 1.6, H - 2.3), s=(1.6, 1.0, 1.4, 1.4), r=0.5),
        pk((-2.7, -1.4, H - 2.1), (-2.7, 1.6, H - 2.5), s=(1.0, 1.6, 1.4, 1.4), r=0.5),
    ],
    pits=[(0.0, 0.2, 0.4, 0.6)],
    ceil_k=0.5, trunk_len=1.0, trunk_f=0.84, trunk_cap=1.2, k_union=1.0,
    roots=[_root(name='root', L=14.5, c0=(0, 0), c1=(0, 0), ex0=2.1, ey0=3.0, ax=0.25, px=0.9,
                 ay=0.25, py=0.8, lr=1.5, dc=1.2, rc0=0.5)],
    pulp=dict(rx=2.4, ry=2.6, hr=0.55),
)

# --------------------------------------------------------------- upper molars
H = 7.5
_um_us = [0, .15, .35, .6, .85, 1.0, 1.1]
SPECS['U6'] = dict(
    H=H, L=12.5, md=10, bl=11, n=2.5, tris=7000, us=_um_us, shear=0.17,
    xm=[4.0, 4.4, 4.6, 4.6, 4.35, 4.0, 3.8],
    xd=[4.0, 4.3, 4.5, 4.4, 4.1, 3.8, 3.6],
    yf=[5.0, 5.4, 5.3, 5.0, 4.4, 3.8, 3.4],
    yl=[5.0, 5.2, 5.5, 5.5, 4.8, 4.0, 3.6],
    feats=[('groove', 'f', 0.35, 0.5, 0.8, 2.6, 7.2), ('groove', 'l', -0.3, 0.5, 0.8, 2.8, 7.2)],
    peaks=[
        pk((2.5, -2.8, H - 0.2), None, s=(0.7, 0.7, 1.2, 0.8), r=0.8, cusp=True),
        pk((-1.8, -3.0, H - 0.5), None, s=(0.7, 0.7, 1.2, 0.8), r=0.8, cusp=True),
        pk((2.4, 2.9, H), None, s=(0.6, 0.6, 0.8, 1.2), r=0.9, cusp=True),
        pk((-2.2, 3.0, H - 1.0), None, s=(0.85, 0.85, 0.8, 1.3), r=0.7, cusp=True),
        pk((2.4, 2.9, H - 0.2), (0.3, 0.1, H - 1.5), s=(1.1, 1.1, 1.1, 1.1), r=0.5),
        pk((0.3, 0.1, H - 1.5), (-1.8, -3.0, H - 0.7), s=(1.1, 1.1, 1.1, 1.1), r=0.5),
        pk((3.7, -2.0, H - 1.7), (3.7, 2.4, H - 1.7), s=(1.6, 1.0, 1.4, 1.4), r=0.5),
        pk((-3.6, -1.8, H - 2.0), (-3.6, 2.4, H - 2.2), s=(1.0, 1.6, 1.4, 1.4), r=0.5),
    ],
    pits=[(0.0, 0.8, 0.4, 0.7)],
    ceil_k=0.6, trunk_len=4.0, trunk_f=0.78, trunk_cap=2.4, k_union=1.1,
    roots=[
        _root(name='rootMB', L=11.8, c0=(1.8, -2.4), c1=(2.9, -4.0), ts=0.3, ex0=1.9, ey0=2.6,
              ax=0.28, px=0.85, lr=1.4, dc=1.1, rc0=0.4),
        _root(name='rootDB', L=11.6, c0=(-1.9, -2.4), c1=(-2.6, -3.9), ts=0.3, ex0=1.7, ey0=1.8,
              ax=0.28, px=0.85, lr=1.4, dc=1.0, rc0=0.38),
        _root(name='rootP', L=12.5, c0=(0.0, 2.6), c1=(0.5, 6.6), ts=0.3, ex0=2.3, ey0=2.1,
              ax=0.28, px=0.85, lr=1.4, dc=0.2, dcy=-0.8, rc0=0.5),
    ],
    pulp=dict(rx=3.3, ry=3.6, hr=0.6, zc=2.0, rz=2.1),
)
SPECS['U7'] = scaled(SPECS['U6'], 0.9, 1.0, 7.0 / 7.5, md=9, bl=11, L=11.5)
SPECS['U7']['roots'] = [
    _root(name='rootMB', L=10.8, c0=(1.6, -2.4), c1=(2.2, -3.6), ts=0.3, ex0=1.75, ey0=2.5,
          ax=0.28, px=0.85, lr=1.4, dc=1.0, rc0=0.38),
    _root(name='rootDB', L=10.6, c0=(-1.7, -2.4), c1=(-1.9, -3.5), ts=0.3, ex0=1.6, ey0=1.7,
          ax=0.28, px=0.85, lr=1.4, dc=0.9, rc0=0.36),
    _root(name='rootP', L=11.5, c0=(0.0, 2.6), c1=(0.3, 5.8), ts=0.3, ex0=2.2, ey0=2.0,
          ax=0.28, px=0.85, lr=1.4, dc=0.2, dcy=-0.6, rc0=0.48),
]
SPECS['U7']['tris'] = 6800
H = 6.5
SPECS['U8'] = dict(
    H=H, L=11, md=8.5, bl=10, n=2.4, tris=6000, us=_um_us, shear=0.1, heart=0.35,
    xm=[3.25, 3.7, 3.95, 4.0, 3.75, 3.4, 3.2],
    xd=[3.25, 3.6, 3.8, 3.8, 3.5, 3.2, 3.0],
    yf=[4.75, 5.1, 5.0, 4.7, 4.1, 3.5, 3.2],
    yl=[4.75, 5.0, 5.0, 4.8, 4.2, 3.5, 3.2],
    feats=[('groove', 'f', 0.2, 0.5, 0.7, 2.2, 6.2)],
    peaks=[
        pk((2.0, -2.6, H - 0.1), None, s=(0.7, 0.7, 1.2, 0.8), r=0.85, cusp=True),
        pk((-1.7, -2.5, H - 0.8), None, s=(0.7, 0.7, 1.2, 0.8), r=0.8, cusp=True),
        pk((0.1, 2.4, H - 0.3), None, s=(0.6, 0.6, 0.8, 1.2), r=0.95, cusp=True),
        pk((3.0, -1.6, H - 1.7), (3.0, 1.8, H - 1.9), s=(1.6, 1.0, 1.4, 1.4), r=0.5),
        pk((-3.0, -1.4, H - 1.9), (-3.0, 1.6, H - 2.0), s=(1.0, 1.6, 1.4, 1.4), r=0.5),
    ],
    pits=[(0.0, 0.0, 0.4, 0.7)],
    ceil_k=0.6, trunk_len=6.0, trunk_f=0.75, trunk_cap=2.5, k_union=1.8,
    roots=[
        _root(name='rootMB', L=10.5, c0=(1.2, -2.4), c1=(1.6, -2.8), ts=0.3, ex0=2.0, ey0=2.2,
              ax=0.3, px=0.85, lr=1.6, dc=0.7, rc0=0.4),
        _root(name='rootDB', L=10.0, c0=(-1.2, -2.4), c1=(-1.4, -2.6), ts=0.3, ex0=2.0, ey0=2.0,
              ax=0.3, px=0.85, lr=1.6, dc=0.7, rc0=0.38),
        _root(name='rootP', L=11.0, c0=(0.0, 2.2), c1=(0.2, 3.0), ts=0.3, ex0=2.3, ey0=2.2,
              ax=0.3, px=0.85, lr=1.6, dc=0.2, rc0=0.45),
    ],
    pulp=dict(rx=2.8, ry=3.4, hr=0.6, zc=1.7, rz=1.9),
)

# --------------------------------------------------------------- lower molars
H = 7.5
SPECS['L6'] = dict(
    H=H, L=14, md=11, bl=10.5, n=3.0, tris=7000, us=_um_us,
    xm=[4.5, 4.9, 5.1, 5.1, 4.85, 4.5, 4.3],
    xd=[4.5, 4.8, 5.0, 5.0, 4.8, 4.5, 4.3],
    yf=[4.5, 5.0, 5.3, 5.0, 4.4, 3.8, 3.4],
    yl=[4.5, 4.9, 5.2, 5.2, 4.6, 3.8, 3.4],
    feats=[('groove', 'f', 1.6, 0.5, 0.8, 3.0, 7.2), ('groove', 'f', -1.6, 0.5, 0.8, 3.0, 7.2),
           ('groove', 'l', 0.1, 0.5, 0.8, 3.0, 7.2)],
    peaks=[
        pk((3.0, -2.9, H - 0.3), None, s=(0.7, 0.7, 1.1, 0.8), r=0.8, cusp=True),
        pk((0.0, -3.0, H - 0.4), None, s=(0.7, 0.7, 1.1, 0.8), r=0.8, cusp=True),
        pk((-3.2, -2.4, H - 1.6), None, s=(0.9, 0.9, 1.1, 0.8), r=0.7, cusp=True),
        pk((3.0, 2.8, H), None, s=(0.75, 0.75, 0.8, 1.3), r=0.7, cusp=True),
        pk((-0.9, 2.9, H - 0.1), None, s=(0.75, 0.75, 0.8, 1.3), r=0.7, cusp=True),
        pk((4.2, -2.2, H - 1.5), (4.2, 2.2, H - 1.5), s=(1.6, 1.0, 1.4, 1.4), r=0.5),
        pk((-4.3, -1.4, H - 2.0), (-4.3, 1.8, H - 2.0), s=(1.0, 1.6, 1.4, 1.4), r=0.5),
    ],
    pits=[(1.8, 0.2, 0.4, 0.7), (-2.0, 0.2, 0.4, 0.7)],
    ceil_k=0.6, trunk_len=3.5, trunk_f=0.85, trunk_cap=2.2, k_union=1.1,
    roots=[
        _root(name='rootM', L=14, c0=(2.4, 0), c1=(3.4, 0), ts=0.25, ex0=2.1, ey0=3.5,
              ax=0.25, px=0.9, ay=0.3, py=0.9, lr=1.5, dc=1.8, rc0=0.45),
        _root(name='rootD', L=13.2, c0=(-2.4, 0), c1=(-3.0, 0), ts=0.25, ex0=2.0, ey0=3.1,
              ax=0.25, px=0.9, ay=0.3, py=0.9, lr=1.5, dc=0.8, rc0=0.42),
    ],
    pulp=dict(rx=3.6, ry=3.4, hr=0.6, zc=2.0, rz=2.1),
)
SPECS['L7'] = scaled(SPECS['L6'], 10.5 / 11, 10 / 10.5, 7 / 7.5, md=10.5, bl=10, L=13)
H7 = 7.0
SPECS['L7']['peaks'] = [
    pk((2.4, -2.7, H7 - 0.3), None, s=(0.7, 0.7, 1.1, 0.8), r=0.8, cusp=True),
    pk((-2.4, -2.8, H7 - 0.4), None, s=(0.7, 0.7, 1.1, 0.8), r=0.8, cusp=True),
    pk((2.5, 2.6, H7), None, s=(0.75, 0.75, 0.8, 1.3), r=0.7, cusp=True),
    pk((-2.3, 2.7, H7 - 0.1), None, s=(0.75, 0.75, 0.8, 1.3), r=0.7, cusp=True),
    pk((4.0, -2.0, H7 - 1.5), (4.0, 2.0, H7 - 1.5), s=(1.6, 1.0, 1.4, 1.4), r=0.5),
    pk((-4.0, -2.0, H7 - 1.8), (-4.0, 2.0, H7 - 1.8), s=(1.0, 1.6, 1.4, 1.4), r=0.5),
]
SPECS['L7']['feats'] = [('groove', 'f', 0.0, 0.5, 0.8, 2.8, 6.8), ('groove', 'l', 0.0, 0.5, 0.8, 2.8, 6.8)]
SPECS['L7']['pits'] = [(0.0, 0.0, 0.4, 0.7)]
SPECS['L7']['roots'] = [
    _root(name='rootM', L=13, c0=(2.3, 0), c1=(3.0, 0), ts=0.25, ex0=2.0, ey0=3.3,
          ax=0.25, px=0.9, ay=0.3, py=0.9, lr=1.5, dc=1.4, rc0=0.42),
    _root(name='rootD', L=12.3, c0=(-2.3, 0), c1=(-2.7, 0), ts=0.25, ex0=1.9, ey0=3.0,
          ax=0.25, px=0.9, ay=0.3, py=0.9, lr=1.5, dc=0.8, rc0=0.4),
]
SPECS['L7']['tris'] = 6800
H8 = 7.0
SPECS['L8'] = scaled(SPECS['L7'], 10 / 10.5, 9.5 / 10, 1.0, md=10, bl=9.5, L=11)
SPECS['L8']['n'] = 2.5
SPECS['L8']['trunk_len'] = 5.5
SPECS['L8']['trunk_f'] = 0.8
SPECS['L8']['trunk_cap'] = 2.6
SPECS['L8']['k_union'] = 1.6
SPECS['L8']['roots'] = [
    _root(name='rootM', L=11, c0=(2.0, 0), c1=(2.4, 0), ts=0.25, ex0=2.2, ey0=3.0,
          ax=0.3, px=0.9, ay=0.3, py=0.9, lr=1.6, dc=1.0, rc0=0.4),
    _root(name='rootD', L=10.4, c0=(-2.0, 0), c1=(-2.2, 0), ts=0.25, ex0=2.1, ey0=2.8,
          ax=0.3, px=0.9, ay=0.3, py=0.9, lr=1.6, dc=0.8, rc0=0.38),
]
SPECS['L8']['tris'] = 6500
SPECS['L8']['pulp'] = dict(rx=3.2, ry=3.2, hr=0.6, zc=1.9, rz=2.0)
SPECS['L7']['pulp'] = dict(rx=3.4, ry=3.3, hr=0.6, zc=1.9, rz=2.0)
SPECS['U7']['pulp'] = dict(rx=3.0, ry=3.5, hr=0.6, zc=1.9, rz=2.0)



# ---- post tuning (pass 2): single-root necks, boxy incisors
_single = {'U1': (3.1, 2.85), 'U2': (2.3, 2.35), 'L1': (1.65, 2.5), 'L2': (1.9, 2.75), 'U3': (2.6, 3.4),
           'L3': (2.6, 3.3), 'U5': (2.2, 3.6), 'L4': (2.25, 3.0), 'L5': (2.25, 3.2)}
for _t, (_ex, _ey) in _single.items():
    _s = SPECS[_t]
    _s['trunk_len'] = 0.6
    _s['trunk_f'] = 0.9
    _s['trunk_cap'] = 0.5
    _s['roots'][0]['ex0'] = _ex
    _s['roots'][0]['ey0'] = _ey
    _s['k_union'] = 1.2
for _t in ('U1', 'U2', 'L1', 'L2'):
    SPECS[_t]['ceil_k'] = 0.8

# ---- post tuning (pass 3): thicker molar roots, softer necks
for _t in _single:
    SPECS[_t]['trunk_len'] = 0.4
    SPECS[_t]['trunk_f'] = 0.93
    SPECS[_t]['trunk_cap'] = 0.4
for _t in ('U6', 'U7', 'L6', 'L7'):
    _s = SPECS[_t]
    _s['trunk_len'] *= 0.75
    _s['k_union'] = 1.4
    for _r in _s['roots']:
        _r['ax'] = 0.42
        _r['ay'] = 0.45 if _t[0] == 'L' else 0.42
        _r['px'] = 0.7
        _r['py'] = 0.7
        _r['ex0'] *= 1.1
for _t in ('U8', 'L8'):
    for _r in SPECS[_t]['roots']:
        _r['ax'] = 0.45
        _r['px'] = 0.7
for _t in ('U4',):
    for _r in SPECS[_t]['roots']:
        _r['ax'] = 0.4
        _r['px'] = 0.75

# ---- post tuning (pass 4): root starts at the cervical width (no collar ledge)
_cerv = {'U1': (3.5, 3.0), 'U2': (2.5, 2.5), 'L1': (1.75, 2.65), 'L2': (2.0, 2.9), 'U3': (2.75, 3.5),
         'L3': (2.75, 3.5), 'U5': (2.5, 4.0), 'L4': (2.5, 3.25), 'L5': (2.5, 3.5)}
for _t, (_cx, _cy) in _cerv.items():
    _s = SPECS[_t]
    _s['roots'][0]['ex0'] = _cx * 0.95
    _s['roots'][0]['ey0'] = _cy * 0.95
    _s['trunk_len'] = 0.3
    _s['trunk_f'] = 0.97
    _s['trunk_cap'] = 0.3
    _s['k_union'] = 0.6

# ---- post tuning (pass 5)
for _t, (_cx, _cy) in _cerv.items():
    _s = SPECS[_t]
    _s['roots'][0]['ex0'] = _cx * 1.0
    _s['roots'][0]['ey0'] = _cy * 1.0
    _s['trunk_len'] = 0.3
    _s['trunk_f'] = 1.0
    _s['trunk_cap'] = 0.1
    _s['k_union'] = 0.5

# ---- post tuning (pass 6): neck seam hidden inside the root, premolar relief
for _t in _cerv:
    _s = SPECS[_t]
    _s['trunk_len'] = 1.0
    _s['trunk_f'] = 0.86
    _s['trunk_cap'] = 0.6
    _s['k_union'] = 0.5
_H = 8.5
SPECS['L4']['peaks'] = [
    pk((0.2, -1.6, _H), None, s=(1.0, 1.0, 1.3, 0.9), r=0.8, cusp=True),
    pk((0.2, 2.0, _H - 2.7), None, s=(1.0, 1.0, 0.9, 1.4), r=0.6, cusp=True),
    pk((0.2, -1.6, _H - 0.4), (0.2, 1.6, _H - 2.5), s=(1.5, 1.5, 1.2, 1.2), r=0.5),
    pk((2.6, -1.4, _H - 2.0), (2.6, 1.2, _H - 2.4), s=(1.5, 1.0, 1.4, 1.4), r=0.5),
    pk((-2.6, -1.4, _H - 2.1), (-2.6, 1.2, _H - 2.5), s=(1.0, 1.5, 1.4, 1.4), r=0.5),
]
SPECS['L4']['pits'] = [(1.5, 0.2, 0.6, 0.6), (-1.5, 0.2, 0.6, 0.6)]
_H = 8.0
SPECS['L5']['peaks'] = [
    pk((0.2, -1.9, _H), None, s=(0.9, 0.9, 1.3, 0.9), r=0.8, cusp=True),
    pk((1.8, 2.2, _H - 1.4), None, s=(0.95, 0.95, 0.9, 1.4), r=0.65, cusp=True),
    pk((-1.8, 2.2, _H - 1.8), None, s=(0.95, 0.95, 0.9, 1.4), r=0.6, cusp=True),
    pk((2.7, -1.4, _H - 2.0), (2.7, 1.6, _H - 2.3), s=(1.6, 1.0, 1.4, 1.4), r=0.5),
    pk((-2.7, -1.4, _H - 2.1), (-2.7, 1.6, _H - 2.5), s=(1.0, 1.6, 1.4, 1.4), r=0.5),
]
SPECS['L5']['pits'] = [(0.0, 0.6, 0.6, 0.6)]


# ---- pass 3: anatomical incisors / canines (generated ring tables)
import math as _m
import numpy as _np
import toothlib as _tl


def _incisor(tid, H, cerv, mxm, mxd, rd, fy, bowf, bowl, fossa, gap):
    cx, cy = cerv
    ycf = [0, .12, .3, .5, .7, .85, 1.0, 1.1]
    yf_c = [cy, 3.45 * fy, 3.5 * fy, 3.2 * fy, 2.55 * fy, 1.8 * fy, 0.72, 0.5]
    yl_c = [cy, 3.85 * fy, 3.3 * fy, 2.1 * fy, 1.3 * fy, 0.9 * fy, 0.5, 0.4]
    yf_c[1] = max(yf_c[1], cy + 0.25)
    yl_c[1] = max(yl_c[1], cy + 0.45)
    cf, cl = _tl.Curve(ycf, yf_c), _tl.Curve(ycf, yl_c)
    uc = (H - rd) / H
    base = [u for u in (0, .1, .2, .3, .45, .6, .75) if u < uc - 0.04]
    th = [0, _m.radians(35), _m.radians(60), _m.radians(80), _m.radians(90)]
    corner = [((H - rd + rd * _m.sin(a)) / H, (mxd - rd) + rd * _m.cos(a)) for a in th]
    us = base + [c[0] for c in corner] + [1.1]
    xm, xd, yf, yl = [], [], [], []
    for u in us:
        xm.append(cx + (mxm - cx) * _m.sin(_m.pi / 2 * min(u / 0.85, 1.0)))
        if u <= uc:
            v = cx + (mxd - cx) * _m.sin(_m.pi / 2 * min(u / 0.65, 1.0))
            v = v - 0.06 * max(0.0, (u - 0.65) / max(uc - 0.65, 1e-3))
            xd.append(v)
        yf.append(float(cf(min(u, 1.1))))
        yl.append(float(cl(min(u, 1.1))))
    xd = xd[:len(base)] + [c[1] - (0.06 if i == 0 else 0.0) for i, c in enumerate(corner)] + [mxd - rd - 0.4]
    s = SPECS[tid]
    s.update(us=us, xm=xm, xd=xd, yf=yf, yl=yl, n=2.3, bow_f=bowf, bow_l=bowl, ceil_k=0.45)
    s['feats'] = [('blob', 'l', 0.0, gap, fossa, 0.55 * H, 0.17 * H)]
    s['peaks'] = [pk((-mxd - 0.5, 0, H - 0.3), (mxm + 0.5, 0, H), s=(0.6, 0.6, 0.5, 0.5), r=0.25)]


_incisor('U1', 10.5, (3.5, 3.0), 4.25, 4.1, 1.2, 1.0, 0.6, 0.35, 0.45, 1.7)
_incisor('U2', 9.0, (2.5, 2.5), 3.3, 3.15, 1.8, 0.86, 0.5, 0.3, 0.4, 1.3)
_incisor('L1', 9.0, (1.75, 2.65), 2.55, 2.45, 0.8, 0.88, 0.4, 0.25, 0.35, 1.0)
_incisor('L2', 9.5, (2.0, 2.9), 2.85, 2.7, 1.0, 0.95, 0.45, 0.3, 0.4, 1.1)

# canines: rounded cusp, soft labial ridge, cingulum
_cus = [0, .15, .4, .6, .8, .92, 1.0, 1.1]
SPECS['U3'].update(yf=[3.5, 3.9, 3.5, 3.0, 2.3, 1.7, 1.4, 1.0], yl=[3.5, 4.1, 3.1, 2.3, 1.6, 1.1, 0.9, 0.6],
                   n=2.3, bow_f=0.6, bow_l=0.3, ceil_k=0.7)
SPECS['U3']['peaks'] = [pk((0.3, -0.2, 10), None, s=(1.0, 0.9, 0.8, 0.8), r=1.1, cusp=True)]
SPECS['U3']['feats'] = [('blob', 'f', 0.2, 1.0, -0.45, 6.0, 3.5), ('blob', 'l', 0.2, 1.0, -0.3, 6.5, 2.5)]
SPECS['L3'].update(yf=[3.5, 3.7, 3.3, 2.8, 2.1, 1.6, 1.3, 0.9], yl=[3.5, 3.8, 2.9, 2.1, 1.5, 1.0, 0.8, 0.55],
                   n=2.3, bow_f=0.5, bow_l=0.3, ceil_k=0.7)
SPECS['L3']['peaks'] = [pk((0.3, -0.2, 11), None, s=(1.0, 0.9, 0.8, 0.8), r=1.1, cusp=True)]
SPECS['L3']['feats'] = [('blob', 'f', 0.2, 1.0, -0.4, 6.5, 3.8), ('blob', 'l', 0.2, 1.0, -0.3, 7.0, 2.5)]

# ---- pass 3b: soften cingulum, squarer incisal-third rings (D-shaped occlusal outline)
for _t in ('U1', 'U2', 'L1', 'L2'):
    SPECS[_t]['nz'] = ([0, .2, .5, .85, 1.0], [2.1, 2.3, 2.8, 3.2, 3.4])
    _s = SPECS[_t]
    # cingulum bulge spread over the cervical third (indices follow the generated us table)
    _us = _s['us']
    for _i, _u in enumerate(_us):
        if 0.05 < _u < 0.35:
            _s['yl'][_i] = min(_s['yl'][_i], _s['yl'][0] + 0.55 * (_s['yl'][_i] - _s['yl'][0]) + 0.0)
SPECS['U3']['yl'] = [3.5, 3.9, 3.5, 2.5, 1.7, 1.1, 0.9, 0.6]
SPECS['L3']['yl'] = [3.5, 3.7, 3.3, 2.4, 1.6, 1.0, 0.8, 0.55]


# ---- pass 7: natural roots (path + profile mode of toothlib.Root).  t = depth / L from the gum line.
#      Molars: short common trunk, clear furcation, roots taper to rounded apices and curve distally in the
#      apical third.  Premolars: one smooth tapering root (upper first premolar splits in the apical half).
def _proot(name, L, path, ex0, ey0, fx, fy=None, lr=1.4, rc0=0.4, n=2.3):
    fy = fy or fx
    return dict(name=name, L=L, path=path, prof=[(t, a, b) for (t, a), (_, b) in zip(fx, fy)],
                c0=(path[0][1], path[0][2]), c1=(path[-1][1], path[-1][2]), ex0=ex0, ey0=ey0, dc=0.0,
                lr=lr, rc0=rc0, n=n, ts=0.3, ax=0.2, px=1.0)


def _mol_prof(tip=0.22):
    return [(0, 1.0), (.2, .95), (.4, .79), (.7, .57), (.9, .4), (1.0, tip)]


def _fan(pts, sx=1.0, sy=1.0):
    return [(t, x * sx, y * sy) for (t, x, y) in pts]


# upper molars: trunk (roots still one mass) ~4.5 mm, then rounded furcation, little splay
_UM_MB = [(0, 1.55, -2.3), (.3, 1.75, -2.4), (.4, 1.9, -2.5), (.55, 2.2, -2.7), (.75, 2.4, -2.95), (.9, 2.5, -3.1), (1.0, 2.3, -3.2)]
_UM_DB = [(0, -1.55, -2.3), (.3, -1.7, -2.4), (.4, -1.85, -2.5), (.55, -2.1, -2.65), (.75, -2.3, -2.8), (1.0, -2.7, -2.9)]
_UM_P = [(0, 0.0, 2.3), (.3, 0.05, 2.7), (.5, 0.2, 3.5), (.75, 0.4, 4.4), (.9, 0.4, 4.8), (1.0, 0.25, 4.9)]
SPECS['U6']['roots'] = [
    _proot('rootMB', 11.8, _UM_MB, 2.4, 2.55, _mol_prof()),
    _proot('rootDB', 11.2, _UM_DB, 2.3, 1.9, _mol_prof()),
    _proot('rootP', 12.5, _UM_P, 2.0, 2.1, _mol_prof(), rc0=0.45),
]
SPECS['U7']['roots'] = [
    _proot('rootMB', 10.8, _fan(_UM_MB, 0.9, 0.95), 2.1, 2.4, _mol_prof()),
    _proot('rootDB', 10.3, _fan(_UM_DB, 0.88, 0.95), 2.0, 1.75, _mol_prof()),
    _proot('rootP', 11.5, _fan(_UM_P, 0.85, 0.92), 1.9, 2.0, _mol_prof(), rc0=0.45),
]
# third molar: shorter, converging, partly fused but tapered
SPECS['U8']['roots'] = [
    _proot('rootMB', 9.6, _fan(_UM_MB, 0.55, 0.8), 2.0, 2.3, _mol_prof(tip=0.26)),
    _proot('rootDB', 9.2, _fan(_UM_DB, 0.5, 0.8), 1.9, 2.1, _mol_prof(tip=0.26)),
    _proot('rootP', 10.5, _fan(_UM_P, 0.6, 0.62), 2.1, 2.2, _mol_prof(tip=0.26), rc0=0.45),
]

# lower molars: trunk ~4.5 mm, rounded furcation, apices inside the crown width, slight distal curve
_LM_M = [(0, 1.9, 0), (.28, 2.05, 0), (.4, 2.25, 0), (.65, 2.45, 0), (.9, 2.5, 0), (1.0, 2.3, 0)]
_LM_D = [(0, -1.9, 0), (.28, -2.0, 0), (.4, -2.2, 0), (.65, -2.4, 0), (1.0, -2.5, 0)]
_LM_FY = [(0, 1.0), (.25, .96), (.5, .83), (.75, .63), (.9, .45), (1.0, .16)]
SPECS['L6']['roots'] = [
    _proot('rootM', 14.0, _LM_M, 2.4, 3.4, _mol_prof(), _LM_FY),
    _proot('rootD', 13.2, _LM_D, 2.3, 3.2, _mol_prof(), _LM_FY),
]
SPECS['L7']['roots'] = [
    _proot('rootM', 13.0, _fan(_LM_M, 0.95), 2.3, 3.2, _mol_prof(), _LM_FY),
    _proot('rootD', 12.3, _fan(_LM_D, 0.95), 2.2, 3.0, _mol_prof(), _LM_FY),
]
SPECS['L8']['roots'] = [
    _proot('rootM', 11.0, _fan(_LM_M, 0.72), 2.4, 2.9, _mol_prof(tip=0.26), _LM_FY),
    _proot('rootD', 10.4, _fan(_LM_D, 0.7), 2.3, 2.7, _mol_prof(tip=0.26), _LM_FY),
]
for _t in ('U6', 'U7', 'U8', 'L6', 'L7', 'L8'):
    SPECS[_t]['k_root'] = 1.1   # round (arch-shaped) furcation

_PM_FX = [(0, 1.0), (.15, .95), (.4, .78), (.65, .6), (.85, .44), (1.0, .24)]
_PM_FY = [(0, 1.0), (.2, .93), (.5, .74), (.8, .52), (1.0, .22)]
_PM_PATH = [(0, 0.0, 0.0), (.6, 0.0, 0.0), (.8, -0.2, 0.1), (1.0, -0.55, 0.2)]
SPECS['U5']['roots'] = [_proot('root', 14.0, _PM_PATH, 2.5, 4.0, _PM_FX, _PM_FY)]
SPECS['L4']['roots'] = [_proot('root', 14.0, _PM_PATH, 2.5, 3.25, _PM_FX, _PM_FY)]
SPECS['L5']['roots'] = [_proot('root', 14.5, _PM_PATH, 2.5, 3.5, _PM_FX, _PM_FY)]
_U4_FX = [(0, 1.0), (.3, .9), (.6, .7), (.85, .5), (1.0, .22)]
_U4_FY = [(0, 1.0), (.3, .88), (.6, .66), (.85, .5), (1.0, .26)]
SPECS['U4']['roots'] = [
    _proot('rootB', 13.5, [(0, 0.0, -1.5), (.45, 0.0, -1.8), (.7, -0.1, -2.3), (1.0, -0.4, -2.9)], 2.2, 2.2, _U4_FX, _U4_FY),
    _proot('rootP', 13.8, [(0, 0.0, 1.5), (.45, 0.0, 1.8), (.7, 0.0, 2.3), (1.0, -0.3, 2.9)], 2.2, 2.2, _U4_FX, _U4_FY),
]
