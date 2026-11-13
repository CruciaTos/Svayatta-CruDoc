"""
toothlib - shared engine for the dental viewer meshes.

Every tooth is an analytic implicit field (loft of super-ellipse rings + an
occlusal ceiling built from cusp / ridge cones + root lofts, smooth-unioned).
The field is sampled on a grid, meshed with naive surface nets (all quads),
projected back onto the exact surface, decimated to the triangle budget, and
re-projected.  Normals come from the analytic gradient and the crevice mask
(vertex colour) from a blurred distance field.

Canonical local frame: origin = cervical centre, +Z = crown tip, -Y = facial,
+X = mesial.  Units: millimetres.
"""
import math
import numpy as np

# --------------------------------------------------------------------------
# small numeric helpers
# --------------------------------------------------------------------------


def ss(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def smin(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


class Curve:
    """Monotone cubic (PCHIP) through control points; constant outside."""

    def __init__(self, xs, ys):
        xs = np.asarray(xs, float)
        ys = np.asarray(ys, float)
        self.xs, self.ys = xs, ys
        h = np.diff(xs)
        d = np.diff(ys) / h
        m = np.zeros(len(xs))
        m[0] = d[0]
        m[-1] = 0.0
        for i in range(1, len(xs) - 1):
            if d[i - 1] * d[i] <= 0:
                m[i] = 0.0
            else:
                w1 = 2 * h[i] + h[i - 1]
                w2 = h[i] + 2 * h[i - 1]
                m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
        self.h, self.m = h, m

    def __call__(self, x):
        xs, ys, h, m = self.xs, self.ys, self.h, self.m
        x = np.clip(x, xs[0], xs[-1])
        i = np.clip(np.searchsorted(xs, x) - 1, 0, len(xs) - 2)
        t = (x - xs[i]) / h[i]
        t2 = t * t
        t3 = t2 * t
        return ((2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h[i] * m[i]
                + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h[i] * m[i + 1])


# --------------------------------------------------------------------------
# tooth field
# --------------------------------------------------------------------------


def _ring(dx, dy, ex, ey, n):
    """Super-ellipse ring, returns (R-1)*sqrt(ex*ey)  (approx distance)."""
    ex = np.maximum(ex, 0.03)
    ey = np.maximum(ey, 0.03)
    R = (np.abs(dx) / ex) ** n + (np.abs(dy) / ey) ** n
    R = R ** (1.0 / n)
    return (R - 1.0) * np.sqrt(ex * ey)


class Root:
    """One root.  Classic mode: ring that tapers with (ax, px) and drifts to c1 / distal by dc.
    Path mode (opt-in, `path` + `prof`): the centre line is a smooth curve through (t, x, y) points and the
    half-extents are ex0 * fx(t), ey0 * fy(t) through (t, fx, fy) points (t = depth / L, 0 = cervical line),
    so roots can fan out, curve in the apical third and end in a rounded point."""

    def __init__(self, r, L_total):
        self.name = r.get('name', 'root')
        self.L = r['L']
        self.c0 = r.get('c0', (0.0, 0.0))
        self.c1 = r.get('c1', self.c0)
        self.ts = r.get('ts', 0.3)
        self.ex0 = r['ex0']
        self.ey0 = r['ey0']
        self.ax = r.get('ax', 0.2)
        self.px = r.get('px', 1.2)
        self.ay = r.get('ay', self.ax)
        self.py = r.get('py', self.px)
        self.lr = r.get('lr', 1.4)
        self.dc = r.get('dc', 1.0)
        self.dcy = r.get('dcy', 0.0)
        self.n = r.get('n', 2.2)
        self.rc0 = r.get('rc0', 0.45)
        self.path = r.get('path')
        if self.path is not None:
            ts_ = [p[0] for p in self.path]
            self.pcx = Curve(ts_, [p[1] for p in self.path])
            self.pcy = Curve(ts_, [p[2] for p in self.path])
            pr = r['prof']
            tp = [p[0] for p in pr]
            self.pfx = Curve(tp, [p[1] for p in pr])
            self.pfy = Curve(tp, [p[2] if len(p) > 2 else p[1] for p in pr])

    def set_neck(self, cx, cy, ex, ey):
        """Make the root's top section match the crown's cervical section (centre cx, cy; half-extents ex, ey,
        in this root's own frame): no ledge or bulge at the junction.  The centre line eases from the
        crown's centre towards its own axis (path mode: keeps 30 % of the offset at the apex)."""
        self.ex0, self.ey0 = ex, ey
        if self.path is not None:
            ox, oy = cx - self.path[0][1], cy - self.path[0][2]
            self.path = [(t, x + ox * (1 - 0.7 * ss(t)), y + oy * (1 - 0.7 * ss(t))) for (t, x, y) in self.path]
            ts_ = [p[0] for p in self.path]
            self.pcx = Curve(ts_, [p[1] for p in self.path])
            self.pcy = Curve(ts_, [p[2] for p in self.path])
        else:
            self.c0 = (cx, cy)
            self.ts = 0.0

    def centre(self, Z):
        t = np.clip(-Z / self.L, 0.0, 1.0)
        if self.path is not None:
            return self.pcx(t), self.pcy(t)
        s = ss(np.clip((t - self.ts) / (1 - self.ts), 0.0, 1.0))
        u = np.clip((t - 0.62) / 0.38, 0.0, 1.0)
        cx = self.c0[0] + (self.c1[0] - self.c0[0]) * s - self.dc * u * u
        cy = self.c0[1] + (self.c1[1] - self.c0[1]) * s + self.dcy * u * u
        return cx, cy

    def extents(self, Z):
        t = np.clip(-Z / self.L, 0.0, 1.0)
        if self.path is not None:
            return self.ex0 * self.pfx(t), self.ey0 * self.pfy(t)
        ex = self.ex0 * (self.ax + (1 - self.ax) * (1 - t) ** self.px)
        ey = self.ey0 * (self.ay + (1 - self.ay) * (1 - t) ** self.py)
        return ex, ey

    def F0(self, X, Y, Z):
        """root ring field, open at the top (no cervical cut)"""
        cx, cy = self.centre(Z)
        ex, ey = self.extents(Z)
        f = _ring(X - cx, Y - cy, ex, ey, self.n)
        return smax(f, -Z - self.L, self.lr * 0.45)

    def F(self, X, Y, Z):
        return smax(self.F0(X, Y, Z), Z - 0.3, 0.3)


class Tooth:
    def __init__(self, spec):
        self.s = spec
        self.H = spec['H']
        self.L = spec['L']
        H = self.H
        us = np.array(spec['us'], float)
        self.cur = {k: Curve(us * H, spec[k]) for k in ('xm', 'xd', 'yf', 'yl')}
        self.n = spec.get('n', 2.5)
        if 'nz' in spec:
            self.ncur = Curve(np.array(spec['nz'][0], float) * H, spec['nz'][1])
        else:
            self.ncur = None
        self.shear = spec.get('shear', 0.0)
        self.trunk_len = spec.get('trunk_len', 1.2)
        self.trunk_f = spec.get('trunk_f', 0.8)
        self.trunk_cap = spec.get('trunk_cap', 1.2)
        self.feats = spec.get('feats', [])
        self.peaks = spec['peaks']
        self.pits = spec.get('pits', [])
        self.ceil_k = spec.get('ceil_k', 0.5)
        self.k_union = spec.get('k_union', 1.0)
        self.hnarrow = spec.get('heart', 0.0)
        self.bow_f = spec.get('bow_f', 0.0)
        self.bow_l = spec.get('bow_l', 0.0)
        self.roots = [Root(r, self.L) for r in spec['roots']]
        self.k_root = spec.get('k_root', 0.5)
        # roots must start inside the neck (no ledge / rib at the CEJ)
        cx_m, cx_d = spec['xm'][0], spec['xd'][0]
        cy_f, cy_l = spec['yf'][0], spec['yl'][0]
        for r in self.roots:
            r.ex0 = max(0.5, min(r.ex0, cx_m - 0.08 - r.c0[0], cx_d - 0.08 + r.c0[0]))
            r.ey0 = max(0.5, min(r.ey0, cy_l - 0.08 - r.c0[1], cy_f - 0.08 + r.c0[1]))
        # trunk taper exponent per extent so the neck is C1 (one smooth waist)
        self.trunk_p = {}
        for k in ('xm', 'xd', 'yf', 'yl'):
            ys = np.array(spec[k], float)
            d0 = (ys[1] - ys[0]) / (us[1] * H - us[0] * H)
            self.trunk_p[k] = float(np.clip(d0 * self.trunk_len / max((1 - self.trunk_f) * ys[0], 1e-6), 1.0, 3.0))

    # ceiling ------------------------------------------------------------
    def ceiling(self, X, Y):
        best = None
        for pk in self.peaks:
            ax, ay, ah = pk['a']
            bx, by, bh = pk.get('b') or pk['a']
            sm, sd, sf, sl = pk['s']
            r = pk.get('r', 0.7)
            dxs_, dys_ = bx - ax, by - ay
            dd = dxs_ * dxs_ + dys_ * dys_
            if dd < 1e-9:
                t = 0.0 * X
            else:
                t = np.clip(((X - ax) * dxs_ + (Y - ay) * dys_) / dd, 0.0, 1.0)
            px = ax + t * dxs_
            py = ay + t * dys_
            h = ah + t * (bh - ah)
            dx = X - px
            dy = Y - py
            dxs = dx * np.where(dx > 0, sm, sd)
            dys = dy * np.where(dy > 0, sl, sf)
            d = np.sqrt(dxs * dxs + dys * dys)
            val = h - (np.sqrt(d * d + r * r) - r)
            best = val if best is None else smax(best, val, pk.get('k', 0.25))
        for (x, y, depth, sg) in self.pits:
            best = best - depth * np.exp(-((X - x) ** 2 + (Y - y) ** 2) / (2 * sg * sg))
        return best

    # crown + trunk -------------------------------------------------------
    def crown_F(self, X, Y, Z):
        zc = np.maximum(Z, 0.0)
        ext = {k: c(zc) for k, c in self.cur.items()}
        tt = np.clip(-Z / self.trunk_len, 0.0, 1.0)
        capS = np.clip((-Z - self.trunk_len) / self.trunk_cap, 0.0, 1.0)
        capf = np.maximum(np.sqrt(np.maximum(1.0 - capS * capS, 0.0)), 0.25)
        def fk(k):
            g = 1.0 - (1.0 - tt) ** self.trunk_p[k]
            return (1.0 - (1.0 - self.trunk_f) * g) * capf
        xm = ext['xm'] * fk('xm')
        xd = ext['xd'] * fk('xd')
        yf = ext['yf'] * fk('yf')
        yl = ext['yl'] * fk('yl')
        # wall features (grooves / bulges)
        for ft in self.feats:
            kind, side, x0, sx, depth = ft[0], ft[1], ft[2], ft[3], ft[4]
            gx = np.exp(-((X - x0) ** 2) / (2 * sx * sx))
            if kind == 'blob':
                zc0, sz = ft[5], ft[6]
                m = depth * gx * np.exp(-((Z - zc0) ** 2) / (2 * sz * sz))
            else:  # groove running down from the rim
                z0, z1 = ft[5], ft[6]
                m = depth * gx * ss((Z - z0) / (z1 - z0))
            if side == 'f':
                yf = yf - m
            else:
                yl = yl - m
        xs = X + self.shear * Y
        if self.bow_f or self.bow_l:
            exl = np.maximum(np.where(xs >= 0, xm, xd), 0.1)
            q = np.clip((xs / exl) ** 2, 0.0, 1.2)
            win = ss(Z / 1.5)
            yf = np.maximum(yf - self.bow_f * q * win * np.minimum(1.0, yf / 2.5), 0.25)
            yl = np.maximum(yl - self.bow_l * q * win * np.minimum(1.0, yl / 2.5), 0.25)
        ex = np.where(xs >= 0, xm, xd)
        if self.hnarrow:
            ex = ex * (1.0 - self.hnarrow * ss(np.clip(Y / np.maximum(yl, 0.1), 0, 1)) ** 1.5)
        ey = np.where(Y >= 0, yl, yf)
        nn = self.ncur(zc) if self.ncur is not None else self.n
        f = _ring(xs, Y, ex, ey, nn)
        ce = self.ceiling(X, Y)
        f = smax(f, (Z - ce) * 0.85, self.ceil_k)
        f = smax(f, (-self.trunk_len - self.trunk_cap) - Z, 0.5)
        return f

    def F(self, X, Y, Z):
        f = self.crown_F(X, Y, Z)
        ku = self.k_union
        rf = None
        for r in self.roots:
            fr = r.F(X, Y, Z)
            rf = fr if rf is None else smin(rf, fr, self.k_root)
        if rf is not None:
            f = smin(f, rf, ku)
        return f


# --------------------------------------------------------------------------
# grid, surface nets, projection
# --------------------------------------------------------------------------


def make_grid(lo, hi, h):
    xs = np.arange(lo[0], hi[0] + h, h, dtype=np.float32)
    ys = np.arange(lo[1], hi[1] + h, h, dtype=np.float32)
    zs = np.arange(lo[2], hi[2] + h, h, dtype=np.float32)
    return xs, ys, zs


def eval_grid(Ffun, xs, ys, zs):
    X = xs[:, None, None]
    Y = ys[None, :, None]
    Z = zs[None, None, :]
    return np.broadcast_to(Ffun(X, Y, Z), (len(xs), len(ys), len(zs))).astype(np.float32)


def grad_grid(F, h):
    gx, gy, gz = np.gradient(F, h)
    return np.sqrt(gx * gx + gy * gy + gz * gz)


def surface_nets(F, h, origin):
    nx, ny, nz = F.shape
    csh = (nx - 1, ny - 1, nz - 1)
    ins = F < 0
    vs = np.zeros(csh + (3,), np.float32)
    cn = np.zeros(csh, np.int8)

    def sl(o):
        return (slice(o[0], o[0] + csh[0]), slice(o[1], o[1] + csh[1]), slice(o[2], o[2] + csh[2]))

    for ax in range(3):
        for a0 in (0, 1):
            for a1 in (0, 1):
                a = [0, 0, 0]
                oth = [d for d in range(3) if d != ax]
                a[oth[0]] = a0
                a[oth[1]] = a1
                b = list(a)
                b[ax] = 1
                Fa = F[sl(a)]
                Fb = F[sl(b)]
                m = (Fa < 0) != (Fb < 0)
                den = np.where(m, Fa - Fb, 1.0)
                t = np.where(m, Fa / den, 0.0)
                for d in range(3):
                    pos = (a[d] + t) if d == ax else float(a[d])
                    vs[..., d] += np.where(m, pos, 0.0)
                cn += m
    active = cn > 0
    idx = np.argwhere(active)
    nv = len(idx)
    vid = -np.ones(csh, np.int32)
    vid[active] = np.arange(nv, dtype=np.int32)
    V = (idx + vs[active] / cn[active][:, None]) * h + np.asarray(origin, np.float32)

    quads = []
    # x-axis edges: nodes (i, j, k), i in [0,nx-2], j in [1,ny-2], k in [1,nz-2]
    def collect(ax):
        sl_lo = [slice(0, nx - 1), slice(0, ny - 1), slice(0, nz - 1)]
        # node ranges where the 4 neighbouring cells exist
        rng = [slice(0, nx), slice(0, ny), slice(0, nz)]
        # edge from node n to n+1 along ax
        lo = [slice(1, n - 1) for n in (nx, ny, nz)]
        lo[ax] = slice(0, (nx, ny, nz)[ax] - 1)
        hi = list(lo)
        hi[ax] = slice(1, (nx, ny, nz)[ax])
        a_in = ins[tuple(lo)]
        b_in = ins[tuple(hi)]
        m = a_in != b_in
        ijk = np.argwhere(m)
        off = np.array([lo[d].start for d in range(3)])
        ijk = ijk + off
        start_in = a_in[m]
        i, j, k = ijk[:, 0], ijk[:, 1], ijk[:, 2]
        if ax == 0:
            cells = [(i, j - 1, k - 1), (i, j, k - 1), (i, j, k), (i, j - 1, k)]
        elif ax == 1:
            cells = [(i - 1, j, k - 1), (i - 1, j, k), (i, j, k), (i, j, k - 1)]
        else:
            cells = [(i - 1, j - 1, k), (i, j - 1, k), (i, j, k), (i - 1, j, k)]
        q = np.stack([vid[c] for c in cells], axis=1)
        q[~start_in] = q[~start_in][:, ::-1]
        return q

    for ax in range(3):
        quads.append(collect(ax))
    Q = np.concatenate(quads, axis=0)
    Q = Q[(Q >= 0).all(axis=1)]
    tris = np.concatenate([Q[:, [0, 1, 2]], Q[:, [0, 2, 3]]], axis=0)
    return V.astype(np.float64), tris.astype(np.int64)


def grad_at(Ffun, P, eps=0.04):
    X, Y, Z = P[:, 0], P[:, 1], P[:, 2]
    gx = (Ffun(X + eps, Y, Z) - Ffun(X - eps, Y, Z)) / (2 * eps)
    gy = (Ffun(X, Y + eps, Z) - Ffun(X, Y - eps, Z)) / (2 * eps)
    gz = (Ffun(X, Y, Z + eps) - Ffun(X, Y, Z - eps)) / (2 * eps)
    return np.stack([gx, gy, gz], axis=1)


def project(Ffun, P, iters=3, max_step=0.35):
    P = P.copy()
    for _ in range(iters):
        f = Ffun(P[:, 0], P[:, 1], P[:, 2])
        g = grad_at(Ffun, P)
        g2 = np.maximum((g * g).sum(1), 1e-6)
        step = (f / g2)[:, None] * g
        ln = np.linalg.norm(step, axis=1)
        sc = np.minimum(1.0, max_step / np.maximum(ln, 1e-9))
        P = P - step * sc[:, None]
    return P


def components_keep(tris, nv, min_tris=30):
    lab = np.arange(nv)
    t = tris
    for _ in range(400):
        fm = lab[t].min(axis=1)
        new = lab.copy()
        np.minimum.at(new, t.ravel(), np.repeat(fm, 3))
        if (new == lab).all():
            break
        lab = new
    # pointer jumping not needed; labels converge to min index per component
    fl = lab[t[:, 0]]
    ids, counts = np.unique(fl, return_counts=True)
    keep = ids[counts >= min_tris]
    if len(keep) == 0:
        keep = ids[np.argmax(counts)][None]
    return t[np.isin(fl, keep)]


def box_blur3(A, r, passes=2):
    w = 2 * r + 1
    for _ in range(passes):
        for ax in range(3):
            pad = [(0, 0)] * 3
            pad[ax] = (r + 1, r)
            Ap = np.pad(A, pad, mode='edge')
            c = np.cumsum(Ap, axis=ax, dtype=np.float64)
            n = A.shape[ax]
            hi = np.take(c, np.arange(w, w + n), axis=ax)
            lo = np.take(c, np.arange(0, n), axis=ax)
            A = ((hi - lo) / w).astype(np.float32)
    return A


def trilinear(A, origin, h, P):
    g = (P - np.asarray(origin)) / h
    i0 = np.floor(g).astype(int)
    i0 = np.clip(i0, 0, np.array(A.shape) - 2)
    f = np.clip(g - i0, 0.0, 1.0)
    out = np.zeros(len(P))
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1]) * (f[:, 2] if dz else 1 - f[:, 2])
                out += w * A[i0[:, 0] + dx, i0[:, 1] + dy, i0[:, 2] + dz]
    return out


def decimate_tris(V, T, target):
    import bpy
    me = bpy.data.meshes.new('_dec')
    me.vertices.add(len(V))
    me.vertices.foreach_set('co', V.astype(np.float32).ravel())
    me.loops.add(len(T) * 3)
    me.polygons.add(len(T))
    me.loops.foreach_set('vertex_index', T.astype(np.int32).ravel())
    me.polygons.foreach_set('loop_start', np.arange(0, len(T) * 3, 3, dtype=np.int32))
    me.polygons.foreach_set('loop_total', np.full(len(T), 3, np.int32))
    me.update(calc_edges=True)
    ob = bpy.data.objects.new('_dec', me)
    bpy.context.scene.collection.objects.link(ob)
    md = ob.modifiers.new('d', 'DECIMATE')
    md.decimate_type = 'COLLAPSE'
    md.ratio = min(1.0, target / max(len(T), 1))
    md.use_collapse_triangulate = True
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    m2 = ev.to_mesh()
    n = len(m2.vertices)
    co = np.empty(n * 3, np.float32)
    m2.vertices.foreach_get('co', co)
    m2.calc_loop_triangles()
    nt = len(m2.loop_triangles)
    tri = np.empty(nt * 3, np.int32)
    m2.loop_triangles.foreach_get('vertices', tri)
    ev.to_mesh_clear()
    bpy.data.objects.remove(ob)
    bpy.data.meshes.remove(me)
    return co.reshape(-1, 3).astype(np.float64), tri.reshape(-1, 3).astype(np.int64)


def clean_unused(V, T):
    used = np.unique(T)
    remap = -np.ones(len(V), np.int64)
    remap[used] = np.arange(len(used))
    return V[used], remap[T]


def mesh_from_field(Ffun, lo, hi, h, target, mask=True, mask_r=3, proj_iters=3, decimate=True, field_for_mask=None):
    """Full pipeline.  Returns dict(V, T, N, C)."""
    xs, ys, zs = make_grid(lo, hi, h)
    F = eval_grid(Ffun, xs, ys, zs)
    origin = (xs[0], ys[0], zs[0])
    V, T = surface_nets(F, h, origin)
    V = project(Ffun, V, proj_iters)
    T = components_keep(T, len(V))
    V, T = clean_unused(V, T)
    if decimate and len(T) > target:
        V, T = decimate_tris(V, T, target)
        T = components_keep(T, len(V), 10)
        V, T = clean_unused(V, T)
        V = project(Ffun, V, 3)
    g = grad_at(Ffun, V)
    N = g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)
    C = np.ones(len(V))
    if mask:
        gm = np.maximum(grad_grid(F, h), 0.25)
        Fn = np.clip(F / gm, -3.0, 3.0)
        B = box_blur3(Fn, mask_r, 2)
        c = -trilinear(B, origin, h, V)
        C = 1.0 - 0.45 * np.clip(c / 0.14, 0.0, 1.0)
    return dict(V=V, T=T, N=N, C=C)


def fix_winding(V, T, N):
    """Make triangle winding agree with the outward normals."""
    a, b, c = V[T[:, 0]], V[T[:, 1]], V[T[:, 2]]
    fn = np.cross(b - a, c - a)
    vn = N[T].sum(axis=1)
    bad = (fn * vn).sum(axis=1) < 0
    T = T.copy()
    T[bad] = T[bad][:, [0, 2, 1]]
    return T


# --------------------------------------------------------------------------
# tooth + pulp generation
# --------------------------------------------------------------------------


def tooth_bounds(spec):
    H, L = spec['H'], spec['L']
    bx = spec['md'] * 0.62 + abs(spec.get('shear', 0.0)) * spec['bl'] * 0.5 + 1.5
    by = spec['bl'] * 0.62 + 1.5
    for r in spec['roots']:
        bx = max(bx, abs(r.get('c1', r.get('c0', (0, 0)))[0]) + r['ex0'] + r.get('dc', 1.0) + 1.5,
                 abs(r.get('c0', (0, 0))[0]) + r['ex0'] + 1.5)
        by = max(by, abs(r.get('c1', r.get('c0', (0, 0)))[1]) + r['ey0'] + 1.5,
                 abs(r.get('c0', (0, 0))[1]) + r['ey0'] + 1.5)
    return (-bx, -by, -L - 1.2), (bx, by, H + 1.2)


def build_tooth_mesh(spec, h=0.22):
    tooth = Tooth(spec)
    lo, hi = tooth_bounds(spec)
    res = mesh_from_field(tooth.F, lo, hi, h, spec['tris'])
    # contract fit: scale crown width/thickness and heights
    V = res['V']
    crown = V[V[:, 2] > 0.6]
    mdm = crown[:, 0].max() - crown[:, 0].min()
    blm = crown[:, 1].max() - crown[:, 1].min()
    sx = spec['md'] / mdm
    sy = spec['bl'] / blm
    szt = spec['H'] / V[:, 2].max()
    szb = spec['L'] / (-V[:, 2].min())
    T = np.array([sx, sy, szt, szb])
    res['fit'] = T
    res['tooth'] = tooth
    return res


def apply_fit(P, fit):
    sx, sy, szt, szb = fit
    Q = P.copy()
    Q[:, 0] *= sx
    Q[:, 1] *= sy
    Q[:, 2] = np.where(P[:, 2] > 0, P[:, 2] * szt, P[:, 2] * szb)
    return Q


def apply_fit_normals(N, fit):
    sx, sy, szt, szb = fit
    M = N / np.array([sx, sy, 1.0])  # approximate inverse-transpose
    # z scale handled separately per hemisphere is negligible for normals
    M[:, 2] = N[:, 2] / 1.0
    return M / np.maximum(np.linalg.norm(M, axis=1, keepdims=True), 1e-9)


def pulp_field(tooth, spec, Ffun_wall):
    H = tooth.H
    p = spec.get('pulp', {})
    zc = p.get('zc', 0.27 * H)
    rz = p.get('rz', 0.21 * H)
    rx = p.get('rx', 0.34 * spec['md'])
    ry = p.get('ry', 0.32 * spec['bl'])
    cx0, cy0 = p.get('c', (0.0, 0.0))
    horns = p.get('horns')
    if horns is None:
        horns = [(pk['a'][0], pk['a'][1]) for pk in spec['peaks'] if pk.get('cusp')]
    htop = 0.55 * H
    hbase = 0.30 * H
    hr0 = p.get('hr', 0.6)
    shear = spec.get('shear', 0.0)

    def F(X, Y, Z):
        # chamber ellipsoid
        q = np.sqrt(((X - cx0) / rx) ** 2 + ((Y - cy0) / ry) ** 2 + ((Z - zc) / rz) ** 2)
        f = (q - 1.0) * min(rx, ry, rz) * 0.9
        for (hx, hy) in horns:
            tt = np.clip((Z - hbase) / (htop - hbase), 0.0, 1.0)
            rad = hr0 * (1.0 - 0.7 * tt)
            hxx = hx * 0.8
            hyy = hy * 0.8
            fh = np.sqrt((X - hxx) ** 2 + (Y - hyy) ** 2) - rad
            fh = smax(fh, Z - htop, 0.15)
            fh = smax(fh, hbase - 0.5 - Z, 0.2)
            f = smin(f, fh, 0.5)
        for r in tooth.roots:
            cx, cy = r.centre(Z)
            tt = np.clip(-Z / r.L, 0.0, 1.0)
            rc = r.rc0 * (1.0 - 0.6 * tt)
            fc = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2) - rc
            fc = smax(fc, Z - 0.9, 0.3)
            fc = smax(fc, -Z - (r.L - 1.0), 0.2)
            f = smin(f, fc, 0.5)
        # keep >= 1 mm of wall: tooth distance field offset
        d = Ffun_wall(X, Y, Z)
        Lm = tooth.L
        wall = 1.0 - 0.5 * ss((-Z - 0.62 * Lm) / (0.12 * Lm))
        f = smax(f, d + wall, 0.25)
        return f

    return F


def build_pulp_mesh(tooth, spec, fit, h=0.16):
    # metric tooth distance: F / |grad F| evaluated analytically
    def wall(X, Y, Z):
        e = 0.05
        f = tooth.F(X, Y, Z)
        gx = (tooth.F(X + e, Y, Z) - tooth.F(X - e, Y, Z)) / (2 * e)
        gy = (tooth.F(X, Y + e, Z) - tooth.F(X, Y - e, Z)) / (2 * e)
        gz = (tooth.F(X, Y, Z + e) - tooth.F(X, Y, Z - e)) / (2 * e)
        g = np.sqrt(gx * gx + gy * gy + gz * gz)
        return f / np.maximum(g, 0.3)

    Fp = pulp_field(tooth, spec, wall)
    lo, hi = tooth_bounds(spec)
    H = spec['H']
    lo = (lo[0], lo[1], -spec['L'])
    hi = (hi[0], hi[1], 0.62 * H)
    res = mesh_from_field(Fp, lo, hi, h, 520, mask=False, proj_iters=2)
    return res




