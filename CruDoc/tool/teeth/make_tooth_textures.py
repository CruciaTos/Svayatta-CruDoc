"""Surface textures for the painted 2.5D tooth chart.

The chart draws every tooth itself (shape, size and pose from ToothSpec);
these give each drawn tooth the look of the real one. From the BoneBox
captures (BoneBox(TM) Dental by iso-form, used with permission) in
assets/images/teeth/{fdi}_{view}.webp, for each adult tooth:

  {fdi}_tex_crown.webp     crown, cheek side, biting edge toward the bite
  {fdi}_tex_root.webp      root(s), cheek side, apex away from the bite
  {fdi}_tex_occlusal.webp  biting surface, squared up

Each is opaque and has no silhouette of its own: the real surface is
stretched to fill it (row by row for crown and root, centre outwards for
the biting surface), so the drawn outline is real surface up to its edge.
"""
import math, os
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(__file__), '..', '..')
DIR = os.path.join(ROOT, 'assets', 'images', 'teeth')

# The capture facing the cheek side, where turn000 caught the tooth at an
# angle (canines and upper right lateral sit on the curve of the arch).
VIEW = {'12': 'turn045', '13': 'turn045', '43': 'turn045',
        '23': 'turn315', '33': 'turn315'}


def load(name):
    return Image.open(os.path.join(DIR, name + '.webp')).convert('RGBA')


def save(im, name, max_h):
    if im.height > max_h:
        im = im.resize((round(im.width * max_h / im.height), max_h), Image.LANCZOS)
    im.convert('RGB').save(os.path.join(DIR, name + '.webp'), 'WEBP', quality=84, method=4)


def principal_angle(alpha):
    ys, xs = np.nonzero(alpha > 0.5)
    w = alpha[ys, xs]
    cx, cy = np.average(xs, weights=w), np.average(ys, weights=w)
    cov = np.cov(np.vstack([xs - cx, ys - cy]), aweights=w)
    vals, vecs = np.linalg.eigh(cov)
    vx, vy = vecs[:, np.argmax(vals)]
    return math.degrees(math.atan2(vy, vx)), vals.max() / max(vals.min(), 1e-6)


def trim(im, pad=0):
    box = Image.fromarray((np.asarray(im)[..., 3] > 12).astype(np.uint8) * 255).getbbox()
    return im.crop((max(box[0] - pad, 0), max(box[1] - pad, 0),
                    min(box[2] + pad, im.width), min(box[3] + pad, im.height)))


def rotate(im, deg):
    return trim(im.rotate(deg, resample=Image.BICUBIC, expand=True))


def row_fill(im, keep, erode=3, soften=False):
    """Opaque texture with no silhouette: each row's tooth surface (its
    runs joined, the soft rim trimmed off) stretched edge to edge. Any
    drawn crown or root clipped from it shows real surface right up to
    its outline, side shading still at the sides. Only pixels [keep]
    accepts (enamel for the crown, root for the root) are used, so the
    curved neck doesn't leak one into the other."""
    a = np.asarray(im).astype(np.float64)
    solid = ndimage.binary_erosion(a[..., 3] > 200, np.ones((1, 2 * erode + 1)))
    solid &= keep(a)
    h, w = solid.shape
    out = np.zeros((h, w, 3))
    valid = np.zeros(h, bool)
    grid = np.linspace(0, 1, w)
    for y in range(h):
        xs = np.nonzero(solid[y])[0]
        if len(xs) < 4:
            continue
        src = np.linspace(0, 1, len(xs))
        for c in range(3):
            out[y, :, c] = np.interp(grid, src, a[y, xs, c])
        valid[y] = True
    rows = np.nonzero(valid)[0]
    for y in range(h):
        if not valid[y]:
            out[y] = out[rows[np.argmin(np.abs(rows - y))]]
    # A touch of vertical smoothing hides row-to-row jitter at the tips.
    out = ndimage.uniform_filter1d(out, size=3, axis=0)
    if soften:
        # Stretching magnifies ridges and highlights; keep the grain, halve
        # the larger marks.
        base = np.stack([ndimage.gaussian_filter(out[..., c], 6) for c in range(3)], -1)
        fine = np.stack([ndimage.gaussian_filter(out[..., c], 1.2) for c in range(3)], -1)
        out = base + 0.45 * (fine - base) + (out - fine)
        # Roots read as pale cream on a chart, not dark bone.
        out = out * 0.78 + np.array([240, 224, 190]) * 0.22
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), 'RGB')


def radial_fill(im, erode=2, p=3.0):
    """Opaque biting-surface texture: the crown's outline is mapped onto
    the texture's rounded-square edge (centre outwards), so the drawn
    outline shows the crown's rim at its rim and no gaps."""
    a = np.asarray(im).astype(np.float64)
    lum = a[..., :3].mean(axis=2)
    enamel = (a[..., 3] > 200) & (yellowness(a) < 30)
    enamel &= lum > np.median(lum[enamel]) * 0.6
    enamel = ndimage.binary_fill_holes(enamel)
    lab, k = ndimage.label(enamel)
    if k:
        sizes = ndimage.sum(np.ones(lab.shape), lab, range(1, k + 1))
        enamel = lab == np.argmax(sizes) + 1
    whole = a[..., 3] > 200
    # Only trust the cleaner mask if it kept most of the crown.
    base = enamel if enamel.sum() > 0.7 * whole.sum() else whole
    solid = ndimage.binary_erosion(base, iterations=erode)
    h, w = solid.shape
    cy, cx = ndimage.center_of_mass(solid)
    n = 720
    angles = np.linspace(-math.pi, math.pi, n, endpoint=False)
    radius = np.zeros(n)
    steps = np.arange(0, max(h, w), 0.5)
    for i, t in enumerate(angles):
        ys = np.clip((cy + np.sin(t) * steps).round().astype(int), 0, h - 1)
        xs = np.clip((cx + np.cos(t) * steps).round().astype(int), 0, w - 1)
        inside = solid[ys, xs]
        out_at = np.argmax(~inside) if (~inside).any() else len(steps) - 1
        radius[i] = steps[max(out_at - 1, 0)]
    radius = ndimage.uniform_filter1d(radius, size=9, mode='wrap')
    v, u = np.mgrid[0:h, 0:w].astype(np.float64)
    du, dv = (u - cx) / (w / 2), (v - cy) / (h / 2)
    rho = (np.abs(du) ** p + np.abs(dv) ** p) ** (1 / p)
    theta = np.arctan2(v - cy, u - cx)
    idx = ((theta + math.pi) / (2 * math.pi) * n).astype(int) % n
    r = np.minimum(rho, 1.0) * radius[idx] * 0.97
    sy, sx = cy + np.sin(theta) * r, cx + np.cos(theta) * r
    rgb = np.stack([ndimage.map_coordinates(a[..., c], [sy, sx], order=1) for c in range(3)], -1)
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), 'RGB')


def root_surface(a):
    """Root-coloured and lit: drops the shadow between a molar's roots
    (the drawn roots split in their own place)."""
    lum = a[..., :3].mean(axis=2)
    keep = (yellowness(a) > 30) & (a[..., 3] > 200)
    med = np.array([np.median(lum[y][keep[y]]) if keep[y].sum() > 3 else 0
                    for y in range(a.shape[0])])
    return keep & (lum > med[:, None] * 0.8)


def yellowness(a):
    return ndimage.uniform_filter(a[..., 0] - a[..., 2], size=7)


for q in (1, 2, 3, 4):
    for t in range(1, 9):
        n = f'{q}{t}'
        upper = q in (1, 2)
        im = load(f'{n}_{VIEW.get(n, "turn000")}')
        alpha = np.asarray(im)[..., 3] / 255.0
        ang, _ = principal_angle(alpha)
        # Long axis vertical.
        im = rotate(im, ang - 90 if ang > 0 else ang + 90)
        a = np.asarray(im).astype(np.float64)
        solid = a[..., 3] > 128
        root = solid & (yellowness(a) > 31)
        rows = solid.sum(axis=1)
        frac = np.where(rows > 0, root.sum(axis=1) / np.maximum(rows, 1), 0)
        # Crown at the bottom for upper teeth, top for lower; if not, turn.
        h = a.shape[0]
        top_root = frac[: h // 3].mean() > frac[2 * h // 3:].mean()
        if top_root != upper:
            im = im.rotate(180)
            a = np.asarray(im).astype(np.float64)
            solid = a[..., 3] > 128
            root = solid & (yellowness(a) > 31)
            rows = solid.sum(axis=1)
            frac = np.where(rows > 0, root.sum(axis=1) / np.maximum(rows, 1), 0)
        # The neck: walking from the crown end, the first row that is
        # mostly root.
        order = range(h - 1, -1, -1) if upper else range(h)
        cej = next(y for y in order if rows[y] > 3 and frac[y] > 0.5)
        if upper:
            crown, rootim = im.crop((0, cej, im.width, h)), im.crop((0, 0, im.width, cej))
        else:
            crown, rootim = im.crop((0, 0, im.width, cej)), im.crop((0, cej, im.width, h))
        save(row_fill(trim(crown), lambda a: yellowness(a) < 28), f'{n}_tex_crown', 200)
        save(row_fill(trim(rootim), root_surface, soften=True), f'{n}_tex_root', 260)

        # Biting surface: drop root showing past the crown, square it up
        # (the long axis lies across for incisors and lower molars, along
        # the cheek-tongue line for the rest), turning as little as can.
        o = load(f'{n}_occlusal')
        oa = np.asarray(o).astype(np.float64)
        osolid = oa[..., 3] > 40
        orootish = osolid & (yellowness(oa) > 31)
        lab, cnt = ndimage.label(orootish)
        if cnt:
            edge = ndimage.binary_dilation(~osolid, iterations=2)
            touch = np.unique(lab[edge & orootish])
            drop = np.isin(lab, touch[touch > 0])
            oa[..., 3][ndimage.binary_dilation(drop, iterations=1) & osolid] = 0
            keep, k = ndimage.label(oa[..., 3] > 40)
            if k > 1:
                sizes = ndimage.sum(np.ones(keep.shape), keep, range(1, k + 1))
                oa[..., 3][(keep != np.argmax(sizes) + 1) & (keep > 0)] = 0
        o = trim(Image.fromarray(oa.astype(np.uint8), 'RGBA'))
        oang, elong = principal_angle(np.asarray(o)[..., 3] / 255.0)
        across = t <= 2 if upper else t >= 6
        target = 0 if across else 90
        if elong > 1.15:
            turn = (oang - target + 90) % 180 - 90
            o = rotate(o, turn)
        save(radial_fill(o), f'{n}_tex_occlusal', 200)
print('ok')
