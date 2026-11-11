"""Hardware templates (implant fixture, abutment, healing cap, bracket, post).
Built in the Blender frame (mm).  Each builder returns dict(V, T, N)."""
import math
import numpy as np
import toothlib as tl


def _smooth_normals(V, T):
    a, b, c = V[T[:, 0]], V[T[:, 1]], V[T[:, 2]]
    fn = np.cross(b - a, c - a)
    N = np.zeros_like(V)
    for k in range(3):
        np.add.at(N, T[:, k], fn)
    ln = np.linalg.norm(N, axis=1, keepdims=True)
    return N / np.maximum(ln, 1e-12)


def _orient(V, T):
    """Flip all triangles if signed volume is negative (so normals point out)."""
    a, b, c = V[T[:, 0]], V[T[:, 1]], V[T[:, 2]]
    vol = np.einsum('ij,ij->i', a, np.cross(b, c)).sum() / 6.0
    if vol < 0:
        T = T[:, [0, 2, 1]]
    return T


def _grid_surface(rows, segs, closed_top=True, closed_bot=True):
    """rows: list of arrays shape (segs,3) (or single-point rows given as (3,))."""
    V = []
    idx = []
    for r in rows:
        r = np.asarray(r, float)
        if r.ndim == 1:
            idx.append(('pt', len(V)))
            V.append(r)
        else:
            idx.append(('ring', len(V)))
            V.extend(list(r))
    V = np.array(V)
    T = []
    for i in range(len(rows) - 1):
        (ka, a), (kb, b) = idx[i], idx[i + 1]
        for j in range(segs):
            j2 = (j + 1) % segs
            if ka == 'pt' and kb == 'ring':
                T.append((a, b + j, b + j2))
            elif ka == 'ring' and kb == 'pt':
                T.append((a + j, b, a + j2))
            elif ka == 'ring' and kb == 'ring':
                T.append((a + j, b + j, b + j2))
                T.append((a + j, b + j2, a + j2))
    T = np.array(T, np.int64)
    T = _orient(V, T)
    return V, T


def revolve(profile, segs=40, phase=None):
    """profile: list of (r, z) top to bottom; r==0 rows become single points."""
    rows = []
    for (r, z) in profile:
        if r <= 1e-6:
            rows.append(np.array([0.0, 0.0, z]))
        else:
            ph = np.arange(segs) * 2 * math.pi / segs
            rows.append(np.stack([r * np.cos(ph), r * np.sin(ph), np.full(segs, z)], axis=1))
    V, T = _grid_surface(rows, segs)
    return dict(V=V, T=T, N=_smooth_normals(V, T))


def fixture():
    pitch, segs = 0.8, 32
    ph = np.arange(segs) * 2 * math.pi / segs
    hexm = lambda p, r: r * (math.cos(math.pi / 6) / np.cos(((p % (math.pi / 3)) - math.pi / 6)))
    rows = [np.array([0.0, 0.0, -1.5])]
    for (r, z) in [(0.85, -1.5), (1.0, -0.1)]:
        rr = hexm(ph, r)
        rows.append(np.stack([rr * np.cos(ph), rr * np.sin(ph), np.full(segs, z)], axis=1))
    for (r, z) in [(1.2, 0.0), (1.9, 0.0), (2.05, -0.15), (2.05, -0.75), (1.85, -1.0), (1.75, -1.2)]:
        rows.append(np.stack([r * np.cos(ph), r * np.sin(ph), np.full(segs, z)], axis=1))
    # threaded body
    z = -1.3
    L = 11.5
    while z > -(L - 0.9):
        zz = z
        core = 1.65 - 0.75 * tl.ss((-zz - 8.0) / 3.0)
        depth = 0.4 * (1.0 - tl.ss((-zz - 7.5) / 3.2)) + 0.12 * tl.ss((-zz - 7.5) / 3.2)
        s = ((-zz) / pitch - ph / (2 * math.pi)) % 1.0
        tri = 1 - np.abs(2 * s - 1)
        w = tl.ss(np.clip((tri - 0.18) / 0.55, 0, 1))
        r = core + depth * w
        rows.append(np.stack([r * np.cos(ph), r * np.sin(ph), np.full(segs, zz)], axis=1))
        z -= pitch / 8
    # rounded tip
    r0 = 0.9
    for a in np.linspace(0.0, 1.0, 6)[:-1]:
        rr = r0 * math.sqrt(max(1 - a * a, 0.0))
        zz = -(L - 0.9) - 0.9 * a
        rows.append(np.stack([rr * np.cos(ph), rr * np.sin(ph), np.full(segs, zz)], axis=1))
    rows.append(np.array([0.0, 0.0, -L]))
    V, T = _grid_surface(rows, segs)
    V[:, 2] = np.minimum(V[:, 2], 0.0)
    return dict(V=V, T=T, N=_smooth_normals(V, T))


def abutment():
    prof = [(0, 5.5), (0.9, 5.5), (1.3, 5.45), (1.4, 5.3), (1.45, 4.8), (1.6, 3.0), (1.78, 1.2),
            (1.85, 0.75), (2.0, 0.65), (2.05, 0.5), (2.05, 0.1), (1.95, 0.0), (0, 0.0)]
    return revolve(prof, 48)


def healing_cap():
    prof = [(0, 0.0), (2.0, 0.0), (2.3, 0.1), (2.3, 0.6), (2.2, 0.9)]
    for a in np.linspace(0.0, 1.0, 9)[1:]:
        ang = a * math.pi / 2
        prof.append((2.2 * math.cos(ang) * 0.97 + 0.0, 0.9 + 2.1 * math.sin(ang)))
    prof[-1] = (0, 3.0)
    return revolve(prof, 48)


def post():
    prof = [(0, 0.0), (0.55, 0.0), (0.75, -0.1), (0.75, -0.9)]
    z = -0.9
    while z > -8.2:
        base = 0.75 - 0.3 * (-z / 9.0)
        wav = 0.05 * (0.5 - 0.5 * math.cos(2 * math.pi * (-z) / 1.2))
        prof.append((base - wav, z))
        z -= 0.15
    for a in np.linspace(0, 1, 6)[:-1]:
        r0 = 0.75 - 0.3 * (8.2 / 9.0)
        prof.append((r0 * math.sqrt(1 - a * a), -8.2 - 0.8 * a))
    prof.append((0, -9.0))
    return revolve(prof, 28)


def _rbox(X, Y, Z, c, hs, r):
    qx = np.abs(X - c[0]) - (hs[0] - r)
    qy = np.abs(Y - c[1]) - (hs[1] - r)
    qz = np.abs(Z - c[2]) - (hs[2] - r)
    out = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2 + np.maximum(qz, 0) ** 2)
    ins = np.minimum(np.maximum(qx, np.maximum(qy, qz)), 0)
    return out + ins - r


def bracket():
    def F(X, Y, Z):
        pad = _rbox(X, Y, Z, (0, 0, 0.19), (1.6, 1.4, 0.19), 0.1)
        # web joining the pad to the wings
        web = _rbox(X, Y, Z, (0, 0, 0.55), (1.45, 1.1, 0.4), 0.15)
        f = tl.smin(pad, web, 0.12)
        for sx in (-1, 1):
            for sy in (-1, 1):
                wing = _rbox(X, Y, Z, (sx * 0.95, sy * 0.86, 1.0), (0.6, 0.58, 0.9), 0.2)
                # hook on the tie wing tip
                f = tl.smin(f, wing, 0.1)
        # archwire slot floor (horizontal, along X) cut into the web
        slot = _rbox(X, Y, Z, (0, 0, 1.6), (3.0, 0.28, 0.65), 0.04)
        f = tl.smax(f, -slot, 0.04)
        return f

    lo, hi = (-1.9, -1.7, -0.25), (1.9, 1.7, 2.15)
    res = tl.mesh_from_field(F, lo, hi, 0.07, 3600, mask=False, proj_iters=2)
    # viewer frame -> blender frame (x, -z, y); proper rotation
    def conv(A):
        return np.stack([A[:, 0], -A[:, 2], A[:, 1]], axis=1)
    return dict(V=conv(res['V']), T=res['T'], N=conv(res['N']))
