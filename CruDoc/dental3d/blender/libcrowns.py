"""
libcrowns - real sculpted crowns from a free tooth library, joined to the generated roots.

The raw library (EOFF crown meshes + xml metadata) is third-party data that is NOT part
of the repo.  It lives in dental3d/tmp/library (git-ignored).  Everything here only reads it
as data.  build.py falls back to the formula teeth when the folder is absent.

Library conventions (worked out from the geometry, see README of this module's report):
  * .eoff = ASCII "OFF BINARY\\n", int32 nV,nF,nE, nV*3 float32, then faces as
    uint16 count(=3) + 3 x int32 (14 bytes/face), then ~edge bytes that are ignored.
  * vertices are already in a per-tooth LOCAL frame (not the arch frame of the xml);
    +Z = coronal (cusp / incisal edge), +Y = facial, open sleeve at -Z.
  * upper files: +X = mesial.  lower files: +X = distal (same physical side, patient right).
  * each file carries ~6-8 mm of cervical sleeve below the cemento-enamel region and its
    crown is ~1.05-1.35x the manifest dimensions, so crowns are cut at a CEJ height that
    reproduces the manifest crownHeight with a uniform scale (see fit_crown).
Our canonical tooth frame: +X mesial, -Y facial, +Z coronal, origin = cervical centre.
"""
import os
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
D = os.path.dirname(HERE)
LIB_DIR = os.path.join(D, 'tmp', 'library')
LIB_TEETH = os.path.join(LIB_DIR, 'teeth', 'M.O.D Round')

# library -> canonical sign of X (mesial) for each jaw file set; Y is always flipped (facial +Y -> -Y)
SX = {'upper': +1.0, 'lower': +1.0}
CLASS_TRIS = {1: 5000, 2: 5000, 3: 5000, 4: 6000, 5: 6000, 6: 9000, 7: 9000, 8: 9000}


def library_present():
    return os.path.isdir(LIB_TEETH) and os.path.exists(os.path.join(LIB_TEETH, 'upperjaw', '1.eoff'))


def eoff_path(tid):
    arch = 'upperjaw' if tid[0] == 'U' else 'lowerjaw'
    return os.path.join(LIB_TEETH, arch, '%s.eoff' % tid[1])


def load_eoff(path):
    import struct
    b = open(path, 'rb').read()
    i = b.index(b'\n') + 1
    nV, nF, _nE = struct.unpack('<3i', b[i:i + 12])
    i += 12
    V = np.frombuffer(b[i:i + nV * 12], '<f4').reshape(-1, 3).astype(np.float64)
    i += nV * 12
    dt = np.dtype([('c', '<u2'), ('v', '<i4', 3)])
    F = np.frombuffer(b[i:i + nF * 14], dt)
    assert (F['c'] == 3).all() and F['v'].max() < nV and F['v'].min() >= 0
    return V, F['v'].astype(np.int64)


def load_xml(path):
    """ModelTooth Number -> (Position, AxisOcclusal, AxisMesial) in the arch frame (reference only)."""
    import xml.etree.ElementTree as ET
    r = ET.parse(path).getroot()
    out = {}
    for t in r.iter('ModelTooth'):
        def g(k):
            return np.array([float(t.find(k).find(a).text) for a in 'xyz'])
        out[int(t.find('Number').text)] = (g('Position'), g('AxisOcclusal'), g('AxisMesial'))
    return out


def crown_canonical(tid):
    """Library crown of type tid mapped into the canonical frame (X mesial, Y lingual, Z coronal),
    outward winding.  Returns V (n,3), F (m,3)."""
    V, F = load_eoff(eoff_path(tid))
    sx = SX['upper' if tid[0] == 'U' else 'lower']
    V = V * np.array([sx, -1.0, 1.0])
    if sx * -1.0 < 0:  # reflection -> flip winding to keep orientation
        F = F[:, [0, 2, 1]]
    # make sure winding is outward: normal of the face holding the top vertex must point +Z
    top = int(np.argmax(V[:, 2]))
    fi = np.where((F == top).any(axis=1))[0]
    a, b, c = V[F[fi, 0]], V[F[fi, 1]], V[F[fi, 2]]
    n = np.cross(b - a, c - a)
    if n[:, 2].sum() < 0:
        F = F[:, [0, 2, 1]]
    return cap_open_loops(V, F)


def cap_open_loops(V, F):
    """Close the open cervical sleeve end with a centroid fan per boundary loop, so the crown
    is a watertight solid (needed for a reliable inside/outside test)."""
    de = {}
    for f in F:
        for k in range(3):
            de[(int(f[k]), int(f[(k + 1) % 3]))] = True
    bnd = [(a, b) for (a, b) in de if (b, a) not in de]
    if not bnd:
        return V, F
    nxt = {}
    for a, b in bnd:
        nxt.setdefault(a, []).append(b)
    seen, loops = set(), []
    for a, b in bnd:
        if (a, b) in seen:
            continue
        loop, cur, nx = [], a, b
        while (cur, nx) not in seen:
            seen.add((cur, nx))
            loop.append(cur)
            cur = nx
            cand = [x for x in nxt.get(cur, []) if (cur, x) not in seen]
            if not cand:
                break
            nx = cand[0]
        loops.append(loop)
    V = [v for v in V]
    out = [f for f in F]
    for loop in loops:
        if len(loop) < 3:
            continue
        c = np.mean([V[i] for i in loop], axis=0)
        ci = len(V)
        V.append(c)
        for k in range(len(loop)):
            a, b = loop[k], loop[(k + 1) % len(loop)]
            out.append(np.array([b, a, ci]))
    return np.array(V), np.array(out)


def fit_crown(V, dims, centre_xy, cerv=None, zc_search=(-4.0, 3.0)):
    """Scale / place the library crown.  md exact, crownHeight exact, bl and the z scale within
    12% of the md scale.  The origin (CEJ) height is chosen so that the library section there
    matches the manifest cervical dimensions (cerv = (cervMd, cervBl)); that makes the crown
    flow into the generated neck without a step.  Returns V_fit, info (z=0 at the CEJ,
    crown bbox centred at centre_xy)."""
    H, md, bl = dims
    ztop = V[:, 2].max()

    def scales(zc):
        s = md / np.ptp(V[:, 0])
        for _ in range(8):
            m = V[:, 2] > zc + 0.6 / s
            s_new = md / np.ptp(V[m, 0])
            if abs(s_new - s) < 1e-6:
                break
            s = s_new
        m = V[:, 2] > zc + 0.6 / s
        sy = float(np.clip(bl / np.ptp(V[m, 1]), 0.86 * s, 1.14 * s))
        return s, sy, m

    best = None
    for zc in np.arange(zc_search[0], zc_search[1] + 1e-9, 0.1):
        s, sy, m = scales(zc)
        sz = H / (ztop - zc)
        if not (0.86 * s <= sz <= 1.14 * s):
            continue
        if cerv is None:
            cost = abs(sz / s - 1.0)
        else:
            sl = (V[:, 2] > zc - 0.4) & (V[:, 2] < zc + 0.4)
            if sl.sum() < 10:
                continue
            wx, wy = np.ptp(V[sl, 0]) * s, np.ptp(V[sl, 1]) * sy
            cost = ((wx - cerv[0]) / cerv[0]) ** 2 + ((wy - cerv[1]) / cerv[1]) ** 2 + 0.3 * (sz / s - 1.0) ** 2
        if best is None or cost < best[0]:
            best = (cost, zc, s, sy, sz)
    if best is None:  # fall back to a uniform scale
        zc = ztop - H / (md / np.ptp(V[:, 0]))
        s, sy, m = scales(zc)
        best = (0.0, zc, s, sy, H / (ztop - zc))
    _, zc, s, sy, sz = best
    m = V[:, 2] > zc + 0.6 / s
    sy_need = bl / np.ptp(V[m, 1])
    Q = V.copy()
    Q[:, 0] *= s
    Q[:, 1] *= sy
    Q[:, 2] = (Q[:, 2] - zc) * sz
    mm = Q[:, 2] > 0.6
    cx = 0.5 * (Q[mm, 0].max() + Q[mm, 0].min())
    cy = 0.5 * (Q[mm, 1].max() + Q[mm, 1].min())
    Q[:, 0] += centre_xy[0] - cx
    Q[:, 1] += centre_xy[1] - cy
    sl = (Q[:, 2] > -0.4) & (Q[:, 2] < 0.4)
    info = dict(s=float(s), sy=sy, sz=float(sz), sy_need=float(sy_need), zcut_lib=float(zc),
                md=float(np.ptp(Q[mm, 0])), bl=float(np.ptp(Q[mm, 1])), H=float(Q[:, 2].max()),
                cerv_md=float(np.ptp(Q[sl, 0])), cerv_bl=float(np.ptp(Q[sl, 1])))
    return Q, info


# ---------------------------------------------------------------------------- SDF
def _bvh(V, F):
    from mathutils.bvhtree import BVHTree
    return BVHTree.FromPolygons([tuple(v) for v in V], [tuple(f) for f in F], all_triangles=True)


def _shift_or(out, free):
    n = out.copy()
    n[1:] |= out[:-1]
    n[:-1] |= out[1:]
    n[:, 1:] |= out[:, :-1]
    n[:, :-1] |= out[:, 1:]
    n[:, :, 1:] |= out[:, :, :-1]
    n[:, :, :-1] |= out[:, :, 1:]
    return n & free


def sdf_slab(bvh, xs, ys, zs, h, clamp=3.0):
    """Signed distance (negative inside) of an open-bottomed crown mesh on a grid slab.
    Magnitude: BVH nearest; sign: flood fill from the slab sides/top (the bottom face is
    treated as closed) with the face normal deciding inside the thin barrier shell."""
    from mathutils import Vector
    nx, ny, nz = len(xs), len(ys), len(zs)
    d = np.full((nx, ny, nz), clamp, np.float32)
    sn = np.ones((nx, ny, nz), np.float32)
    fn = bvh.find_nearest
    for i in range(nx):
        x = float(xs[i])
        for j in range(ny):
            y = float(ys[j])
            for k in range(nz):
                r = fn(Vector((x, y, float(zs[k]))), clamp)
                if r[0] is not None:
                    d[i, j, k] = r[3]
                    if (Vector((x, y, float(zs[k]))) - r[0]).dot(r[1]) < 0:
                        sn[i, j, k] = -1.0
    delta = 0.5 * h
    free = d >= delta
    out = np.zeros((nx, ny, nz), bool)
    seed = np.zeros_like(out)
    seed[0] = seed[-1] = True
    seed[:, 0] = seed[:, -1] = True
    seed[:, :, -1] = True
    out = seed & free
    for _ in range(2000):
        n = _shift_or(out, free) | out
        if (n == out).all():
            break
        out = n
    sign = np.where(free, np.where(out, 1.0, -1.0), sn).astype(np.float32)
    return d * sign


# ---------------------------------------------------------------------------- build
def ss(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def grid_fun(A, origin, h):
    import toothlib as tl

    def f(P):
        return tl.trilinear(A, origin, h, P)
    return f


def project_grid(A, origin, h, P, iters=3, max_step=0.4):
    import toothlib as tl
    P = P.copy()
    e = 0.6 * h
    for _ in range(iters):
        f = tl.trilinear(A, origin, h, P)
        g = np.stack([(tl.trilinear(A, origin, h, P + np.eye(3)[a] * e) - tl.trilinear(A, origin, h, P - np.eye(3)[a] * e)) / (2 * e)
                      for a in range(3)], axis=1)
        g2 = np.maximum((g * g).sum(1), 1e-4)
        step = (f / g2)[:, None] * g
        ln = np.linalg.norm(step, axis=1)
        P = P - step * np.minimum(1.0, max_step / np.maximum(ln, 1e-9))[:, None]
    return P


def make_manifold(V, T, rounds=6):
    """Remove faces around non-manifold edges / vertices (naive surface nets can create a few in
    thin fissures) and fill the holes again with bmesh.  Returns cleaned (V, T)."""
    import bmesh
    for _ in range(rounds):
        bm = bmesh.new()
        bv = [bm.verts.new(tuple(v)) for v in V]
        bm.verts.ensure_lookup_table()
        for t in T:
            try:
                bm.faces.new((bv[t[0]], bv[t[1]], bv[t[2]]))
            except ValueError:
                pass
        bad = set()
        for e in bm.edges:
            if not e.is_manifold:
                bad.update(f for f in e.link_faces)
        for v in bm.verts:
            if v.link_faces and not v.is_manifold:
                bad.update(v.link_faces)
        if not bad:
            bm.free()
            break
        bmesh.ops.delete(bm, geom=list(bad), context='FACES_ONLY')
        bnd = [e for e in bm.edges if e.is_boundary]
        if bnd:
            bmesh.ops.holes_fill(bm, edges=bnd, sides=400)
            big = [f for f in bm.faces if len(f.verts) > 3]
            if big:
                bmesh.ops.triangulate(bm, faces=big)
        bm.verts.ensure_lookup_table()
        bm.verts.index_update()
        V = np.array([v.co[:] for v in bm.verts], np.float64)
        T = np.array([[l.vert.index for l in f.loops] for f in bm.faces], np.int64)
        bm.free()
        # holes_fill may produce n-gons -> triangulate by fan if needed
        T = T if T.shape[1] == 3 else None
        if T is None:
            raise RuntimeError('non-triangle faces after fill')
    import toothlib as tl
    T = tl.components_keep(T, len(V))
    return tl.clean_unused(V, T)


def orient(F, origin, h, V, T):
    import toothlib as tl
    e = 0.7 * h
    g = np.stack([(tl.trilinear(F, origin, h, V + np.eye(3)[a] * e) - tl.trilinear(F, origin, h, V - np.eye(3)[a] * e)) / (2 * e)
                  for a in range(3)], axis=1)
    return tl.fix_winding(V, T, g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9))


def vertex_normals(V, T):
    a, b, c = V[T[:, 0]], V[T[:, 1]], V[T[:, 2]]
    fn = np.cross(b - a, c - a)
    N = np.zeros_like(V)
    for k in range(3):
        np.add.at(N, T[:, k], fn)
    return N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)


def build_lib_tooth(tooth, spec, fit, Vc, Fc, target, h=0.15, band=(-3.0, 0.3), smooth_z=(0.6, 2.6), smooth_r=0.6):
    """Return dict(V,T,N,C, grid=(F,origin,h)) in the FITTED tooth frame (z=0 at CEJ)."""
    import toothlib as tl
    sx, sy, szt, szb = fit
    fs = 0.5 * (sx + sy)

    def Ff(X, Y, Z):
        # generated ROOT field only (no formula crown / trunk): open at the top so it can be
        # blended with the library crown / sleeve without the formula's own cervical ring
        Zu = np.where(Z > 0, Z / szt, Z / szb)
        Xu, Yu = X / sx, Y / sy
        rf = None
        for r in tooth.roots:
            f = r.F0(Xu, Yu, Zu)
            rf = f if rf is None else tl.smin(rf, f, tooth.k_root)
        return rf * fs

    lo, hi = tl.tooth_bounds(spec)
    lo = np.array([lo[0] * sx, lo[1] * sy, lo[2] * szb])
    hi = np.array([hi[0] * sx, hi[1] * sy, hi[2] * szt])
    lo = np.minimum(lo, Vc.min(0) - 0.8)
    hi = np.maximum(hi, Vc.max(0) + 0.8)
    lo[2] = -spec['L'] * szb - 1.2
    xs, ys, zs = tl.make_grid(lo, hi, h)
    origin = (float(xs[0]), float(ys[0]), float(zs[0]))
    F = tl.eval_grid(Ff, xs, ys, zs)
    z0, z1 = band
    k0 = int(np.searchsorted(zs, z0))
    bvh = _bvh(Vc, Fc)
    Fc_s = sdf_slab(bvh, xs, ys, zs[k0:], h)
    # soften the sculpted cervical ledge of the library crown: blend towards a blurred copy of the
    # signed distance below sm_z[0], fading out by sm_z[1] (the occlusal two thirds stay crisp)
    sm0, sm1 = smooth_z
    mz = (1.0 - ss((zs[k0:] - sm0) / (sm1 - sm0))).astype(np.float32)[None, None, :]
    Fc_b = tl.box_blur3(Fc_s, max(1, int(round(smooth_r / h))), 2)
    Fc_s = Fc_s * (1 - mz) + Fc_b * mz
    del Fc_b
    w = ss((zs[k0:] - z0) / (z1 - z0)).astype(np.float32)[None, None, :]
    F[:, :, k0:] = (1 - w) * F[:, :, k0:] + w * Fc_s
    del Fc_s
    V, T = tl.surface_nets(F, h, origin)
    V = project_grid(F, origin, h, V, 2)
    T = tl.components_keep(T, len(V))
    V, T = tl.clean_unused(V, T)
    V, T = make_manifold(V, T)
    T = orient(F, origin, h, V, T)

    def wz(z):
        return ss((z - z0) / (z1 - z0))

    def snap(V):
        w_v = wz(V[:, 2])
        ws = ss((w_v - 0.8) / 0.2) * ss((V[:, 2] - smooth_z[0]) / (smooth_z[1] - smooth_z[0]))
        P = V.copy()
        idx = np.where(ws > 0)[0]
        from mathutils import Vector
        for i in idx:
            r = bvh.find_nearest(Vector(V[i]), 1.5)
            if r[0] is not None:
                P[i] = V[i] + ws[i] * (np.array(r[0]) - V[i])
        return P

    V = snap(V)
    if len(T) > target:
        V, T = tl.decimate_tris(V, T, target)
        T = tl.components_keep(T, len(V), 10)
        V, T = tl.clean_unused(V, T)
        V, T = make_manifold(V, T)
        T = orient(F, origin, h, V, T)
        V = project_grid(F, origin, h, V, 2)
        V = snap(V)
    # normals: grid gradient in the root/neck, mesh normals on the crown
    e = 0.7 * h
    g = np.stack([(tl.trilinear(F, origin, h, V + np.eye(3)[a] * e) - tl.trilinear(F, origin, h, V - np.eye(3)[a] * e)) / (2 * e)
                  for a in range(3)], axis=1)
    Ng = g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)
    Nm = vertex_normals(V, T)
    Nm = np.where((Nm * Ng).sum(1, keepdims=True) < 0, -Nm, Nm)
    # one smoothing pass of mesh normals over vertex neighbours
    nb = np.zeros_like(Nm)
    for k in range(3):
        np.add.at(nb, T[:, k], Nm[T[:, (k + 1) % 3]] + Nm[T[:, (k + 2) % 3]])
    Nm2 = Nm + 0.5 * nb / 2.0
    Nm2 /= np.maximum(np.linalg.norm(Nm2, axis=1, keepdims=True), 1e-9)
    wc = ss((wz(V[:, 2]) - 0.3) / 0.7)[:, None]
    N = Ng * (1 - wc) + Nm2 * wc
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
    # crevice mask from the blurred normalised field (same recipe as toothlib, same physical radius)
    gm = np.maximum(tl.grad_grid(F, h), 0.25)
    Fn = np.clip(F / gm, -3.0, 3.0)
    B = tl.box_blur3(Fn, max(1, int(round(0.66 / h))), 2)
    c = -tl.trilinear(B, origin, h, V)
    C = 1.0 - 0.45 * np.clip(c / 0.14, 0.0, 1.0)
    wall = np.clip(F / np.maximum(tl.grad_grid(F, h), 0.3), -6.0, 6.0).astype(np.float32)
    return dict(V=V, T=T, N=N, C=C, grid=(wall, origin, h))


def build_pulp(tooth, spec, fit, wall_grid, offset=0.3):
    """Same pulp as toothlib.build_pulp_mesh but with the wall distance taken from the new tooth."""
    import toothlib as tl
    sx, sy, szt, szb = fit
    fs = 0.5 * (sx + sy)
    A, origin, h = wall_grid

    def wall(X, Y, Z):
        X, Y, Z = np.broadcast_arrays(X, Y, Z)
        P = np.stack([(X * sx).ravel(), (Y * sy).ravel(), np.where(Z > 0, Z * szt, Z * szb).ravel()], axis=1)
        return (tl.trilinear(A, origin, h, P) / fs + offset).reshape(X.shape)

    Fp = tl.pulp_field(tooth, spec, wall)
    lo, hi = tl.tooth_bounds(spec)
    H = spec['H']
    lo = (lo[0], lo[1], -spec['L'])
    hi = (hi[0], hi[1], 0.62 * H)
    return tl.mesh_from_field(Fp, lo, hi, 0.16, 520, mask=False, proj_iters=2)


def pulp_clearance(bvh, PV):
    from mathutils import Vector
    m = 9.0
    for p in PV:
        r = bvh.find_nearest(Vector(p), 6.0)
        if r[0] is not None:
            d = r[3] if (Vector(p) - r[0]).dot(r[1]) < 0 else -r[3]
            m = min(m, d)
    return m


def build_lib_type(tid, spec, formula, cerv=None, h=0.15):
    """formula = the cached formula build (V,fit...) of the same type.  Returns the same
    dict layout as build.build_type (V,T,N,C,PV,PT,PN,fit) plus stats."""
    import toothlib as tl
    fit = formula['fit']
    tooth = tl.Tooth(spec)
    fV = formula['V']
    cr = fV[fV[:, 2] > 0.6]
    centre = (0.5 * (cr[:, 0].max() + cr[:, 0].min()), 0.5 * (cr[:, 1].max() + cr[:, 1].min()))
    Vl, Fl = crown_canonical(tid)
    Vc, info = fit_crown(Vl, (spec['H'], spec['md'], spec['bl']), centre, cerv)
    target = CLASS_TRIS[int(tid[1])]
    if len(tooth.roots) == 1:
        # single root: start exactly at the crown's cervical section, then taper
        sx, sy = fit[0], fit[1]
        sl = Vc[np.abs(Vc[:, 2]) < 0.3]
        if len(sl) > 20:
            x0, x1, y0, y1 = sl[:, 0].min(), sl[:, 0].max(), sl[:, 1].min(), sl[:, 1].max()
            tooth.roots[0].set_neck(0.5 * (x0 + x1) / sx, 0.5 * (y0 + y1) / sy, 0.5 * (x1 - x0) / sx * 1.02,
                                    0.5 * (y1 - y0) / sy * 1.02)
    r = build_lib_tooth(tooth, spec, fit, Vc, Fl, target, h)
    V, T, N = r['V'], r['T'], r['N']
    T = tl.fix_winding(V, T, N)
    bv = _bvh(V, T)
    offset = 0.3
    for _ in range(4):
        p = build_pulp(tooth, spec, fit, r['grid'], offset)
        PV = tl.apply_fit(p['V'], fit)
        PN = tl.apply_fit_normals(p['N'], fit)
        PT = tl.fix_winding(PV, p['T'], PN)
        clr = pulp_clearance(bv, PV)
        if clr >= 0.65:
            break
        offset += 0.7 - clr
    info['tris'] = int(len(T))
    info['pulp_clr'] = float(clr)
    return dict(V=V, T=T, N=N, C=r['C'], PV=PV, PT=PT, PN=PN, fit=fit, info=info)
