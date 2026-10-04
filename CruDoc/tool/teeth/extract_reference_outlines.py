"""Step 1-2: trace every tooth's outline from the reference chart image and
draw the traced outlines back over it for checking.

Input: the reference chart (cheek views of the upper row, a biting-surface
row, cheek views of the lower row; tooth numbers along the bottom).
Output (in OUT): masks per tooth as .npy, and overlay_*.png for checking.
"""
import json, os, sys
import cv2
import numpy as np
from scipy.ndimage import gaussian_filter1d

SRC = sys.argv[1]
OUT = sys.argv[2]
# Optional: the same chart with transparent background (teeth opaque),
# which gives exact outlines and the real gaps between roots.
MASK_SRC = sys.argv[3] if len(sys.argv) > 3 else None
os.makedirs(OUT, exist_ok=True)
S = 3  # work at 3x for smoother outlines

img = cv2.imread(SRC)  # BGR
img = cv2.resize(img, None, fx=S, fy=S, interpolation=cv2.INTER_CUBIC)
H, W = img.shape[:2]
b, g, r = [img[..., i].astype(int) for i in range(3)]

# 1. Paint out the red gum line (it bridges the gaps between teeth).
red = (r > 110) & (r - (g + b) / 2 > 35)
red = cv2.dilate(red.astype(np.uint8), np.ones((7, 7), np.uint8))
clean = cv2.inpaint(img, red, 7, cv2.INPAINT_TELEA)
b, g, r = [clean[..., i].astype(int) for i in range(3)]
lum = (r + g + b) / 3

# Page: near-white area joined to the open background. A tooth is
# everything else, so a white crown enclosed by its grey edge counts as
# tooth even though it's as white as the page.
pageish = (lum >= 245) & (r - b < 9)
pageish = cv2.erode(pageish.astype(np.uint8), np.ones((3, 3), np.uint8))


# Between a molar's roots the page shows as thin near-white slits; looser
# and not thinned, so they stay open (roots stay separate). Only in the
# root zones (orig px), where there's no white crown to leak into.
ROOT_ZONES = [(52, 112), (352, 452)]
gapish = ((lum >= 236) & (r - b < 14)).astype(np.uint8)
for z0, z1 in ROOT_ZONES:
    pageish[z0 * S:z1 * S] |= gapish[z0 * S:z1 * S]


def page_mask(y0, y1):
    """Page in rows y0..y1: near-white pieces touching the band's top or
    bottom edge, or big ones."""
    p = pageish[y0:y1]
    n, lab, stats, _ = cv2.connectedComponentsWithStats(p, connectivity=4)
    keep = np.zeros(n, bool)
    for i in range(1, n):
        x, y, w, h, area = stats[i]
        if y == 0 or y + h >= p.shape[0] or area > 4000 * S * S:
            keep[i] = True
    page = keep[lab].astype(np.uint8)
    return cv2.dilate(page, np.ones((3, 3), np.uint8))


mask_alpha = mask_rgb = None
if MASK_SRC:
    from PIL import Image as _Image
    rgba = np.asarray(_Image.open(MASK_SRC).convert('RGBA'))
    a = rgba[..., 3] > 128
    # Drop the red gum line (it joins neighbours across the gaps), then
    # rejoin each tooth across the thin seam it leaves.
    rr, gg, bb_ = [rgba[..., i].astype(int) for i in range(3)]
    redline = (rr > 140) & (gg < 110) & (bb_ < 110)
    a = (a & ~redline).astype(np.uint8)
    a = cv2.morphologyEx(a, cv2.MORPH_CLOSE, np.ones((15, 1), np.uint8)) > 0
    # Keep only real pieces (no specks left from the line's ends).
    nl, lab_, st_, _ = cv2.connectedComponentsWithStats(a.astype(np.uint8))
    a = np.isin(lab_, [j for j in range(1, nl) if st_[j, cv2.CC_STAT_AREA] > 400])
    ys_, xs_ = np.nonzero(a)
    # The mask image is the reference scaled: line up the teeth's bounding
    # boxes (reference box measured from its traced outlines).
    REF_BOX = (30.84, 834.04, 59.28, 450.12)  # orig px x0, x1, y0, y1
    sx = (xs_.max() - xs_.min()) / (REF_BOX[1] - REF_BOX[0])
    sy = (ys_.max() - ys_.min()) / (REF_BOX[3] - REF_BOX[2])
    # mask px -> reference 3x px
    M = np.float32([[S / sx, 0, (REF_BOX[0] - xs_.min() / sx) * S],
                    [0, S / sy, (REF_BOX[2] - ys_.min() / sy) * S]])
    mask_alpha = cv2.warpAffine(a.astype(np.uint8), M, (W, H), flags=cv2.INTER_LINEAR)
    bgr = cv2.cvtColor(rgba[..., :3], cv2.COLOR_RGB2BGR)
    bgr[~a] = 255
    mask_rgb = cv2.warpAffine(bgr, M, (W, H), flags=cv2.INTER_LINEAR, borderValue=(255, 255, 255))


# Tooth centres from the number row (orig px), 18..28 left to right.
CENTERS = [57, 112, 171, 222, 264, 311, 359, 406, 458, 505, 553, 600, 642, 693, 752, 808]
ROWS = {  # orig px y ranges
    'upper': (52, 214),
    'occlusal': (214, 292),
    'lower': (292, 452),
}

result = {}
for row, (y0, y1) in ROWS.items():
    Y0, Y1 = y0 * S, y1 * S
    if mask_alpha is not None:
        sub = mask_rgb[Y0:Y1].copy()
        tm = mask_alpha[Y0:Y1].copy()
        page = (1 - tm).astype(np.uint8)
    else:
        sub = clean[Y0:Y1].copy()
        page = page_mask(Y0, Y1)
        tm = (1 - page).astype(np.uint8)
    tm = cv2.morphologyEx(tm, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    markers = np.zeros(tm.shape, np.int32)
    markers[cv2.erode(page, np.ones((5, 5), np.uint8)) > 0] = 1
    for i, cx in enumerate(CENTERS):
        X = cx * S
        band = np.zeros_like(tm)
        band[:, X - 4 * S: X + 4 * S] = 1
        seed = cv2.erode(tm, np.ones((9, 9), np.uint8)) & band
        markers[seed > 0] = i + 2
    cv2.watershed(sub, markers)
    for i in range(len(CENTERS)):
        m = (markers == i + 2).astype(np.uint8)
        # Tidy: largest piece, holes filled, edges smoothed.
        n, lab, stats, _ = cv2.connectedComponentsWithStats(m)
        if n <= 1:
            continue
        big = 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
        m = (lab == big).astype(np.uint8)
        cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
        m = np.zeros_like(m)
        cv2.drawContours(m, cnts, -1, 1, -1)
        m = cv2.morphologyEx(m, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5)))
        full = np.zeros((H, W), np.uint8)
        full[Y0:Y1] = m
        np.save(os.path.join(OUT, f'{row}_{i}.npy'), full)
        result[f'{row}_{i}'] = int(m.sum())

# 2. Overlays for checking.
colors = [(230, 60, 60), (40, 160, 60), (40, 90, 230), (200, 120, 0)]
over = img.copy()
for key in result:
    m = np.load(os.path.join(OUT, key + '.npy'))
    cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    i = int(key.split('_')[1])
    cv2.drawContours(over, cnts, -1, colors[i % 4], 2)
cv2.imwrite(os.path.join(OUT, 'overlay_all.png'), over)
for name, (x0, x1) in {'left': (0, 300), 'mid': (280, 590), 'right': (570, 864)}.items():
    cv2.imwrite(os.path.join(OUT, f'overlay_{name}.png'), over[50 * S:455 * S, x0 * S:x1 * S])
json.dump(result, open(os.path.join(OUT, 'areas.json'), 'w'))
print(len(result), 'regions')


# 3. Finished outlines: smooth, swap marked teeth for their mirror twin,
#    split crown from root, export.
FDI = ['18', '17', '16', '15', '14', '13', '12', '11',
       '21', '22', '23', '24', '25', '26', '27', '28']
# Teeth with markers drawn over them in the reference -> their twin.
TWIN = {'upper': {'12': '22', '14': '24', '21': '11', '23': '13'},
        'occlusal': {'12': '22', '11': '21'},
        'lower': {'12': '22', '14': '24', '23': '13'}}


def smooth_mask(m, closing, blur=2.6):
    if closing > 1:
        k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (closing, closing))
        m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, k)
    m = cv2.GaussianBlur(m.astype(np.float32), (0, 0), blur) > 0.5
    return m.astype(np.uint8)


def contour(m, n_pts, sigma=2.4):
    cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    c = max(cnts, key=cv2.contourArea)[:, 0, :].astype(np.float64)
    # Even spacing along the outline.
    d = np.r_[0, np.cumsum(np.hypot(*np.diff(np.r_[c, c[:1]], axis=0).T))]
    t = np.linspace(0, d[-1], n_pts, endpoint=False)
    x = np.interp(t, d, np.r_[c[:, 0], c[0, 0]])
    y = np.interp(t, d, np.r_[c[:, 1], c[0, 1]])
    # Smooth along the outline (about [sigma] orig px): no pixel wobble,
    # root tips still pointed.
    step = d[-1] / n_pts
    k = sigma * S / step
    x = gaussian_filter1d(x, k, mode='wrap')
    y = gaussian_filter1d(y, k, mode='wrap')
    return np.stack([x, y], 1) / S  # orig px


def mirror_about(pts, from_cx, to_cx):
    out = pts.copy()
    out[:, 0] = to_cx + (from_cx - pts[:, 0])
    return out[::-1]


def valley_lines(lum_s, roots, reach=4, depth=7):
    """Thin lines along the darkest path between roots: in each row, the
    points darker (by [depth]) than both sides [reach] orig px away."""
    k = reach * S
    out = np.zeros(roots.shape, np.uint8)
    ys = np.nonzero(roots.any(axis=1))[0]
    for y in ys:
        xs = np.nonzero(roots[y])[0]
        if len(xs) < 2 * k + 3:
            continue
        p = lum_s[y]
        for x in range(xs.min() + k, xs.max() - k):
            if not roots[y, x]:
                continue
            v = p[x]
            if v < p[x - k] - depth and v < p[x + k] - depth and v <= p[x - 1] and v <= p[x + 1]:
                out[y, x] = 1
    # Join the per-row points into lines.
    out = cv2.dilate(out, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (S + 2, 2 * S + 1)))
    return out


# Gum line in the reference (orig px): roots are on the far side of it.
NECK_Y = {'upper': 112, 'lower': 350}


def split_roots(m, row):
    """A molar's roots overlap in the reference; a darker shaded band marks
    where one ends and the next begins. Follow that band through the tip
    end of the roots only (they stay joined at the trunk under the crown)
    and carry it out through the tips, so each root is its own prong."""
    upper = row == 'upper'
    ys, xs = np.nonzero(m)
    if not len(ys):
        return m
    apex = ys.min() if upper else ys.max()
    neck = NECK_Y[row] * S
    # Rows from the tips up to 30% of the way back to the neck.
    # Upper molar roots fork higher and their bands are fainter.
    reach, depth, tall = (0.15, 10, 0.8) if upper else (0.3, 14, 1.2)
    lim = neck - reach * (neck - apex) if upper else neck + reach * (apex - neck)
    zone = np.zeros_like(m)
    if upper:
        zone[:int(lim)] = 1
    else:
        zone[int(lim):] = 1
    roots = (m > 0) & (zone > 0)
    if roots.sum() < 200:
        return m
    lum_s = cv2.GaussianBlur(lum.astype(np.float32), (0, 0), 1.5)
    med = np.median(lum_s[roots])
    if upper:
        # Upper molars: the shade between roots is broad, so take only its
        # valley line (darker than both sides a few px away), not the area.
        dark = valley_lines(lum_s, roots)
    else:
        dark = (roots & (lum_s < med - depth)).astype(np.uint8)
    if not upper:
        dark = cv2.morphologyEx(dark, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    left, right = xs.min(), xs.max()
    width = right - left
    n, lab, stats, cent = cv2.connectedComponentsWithStats(dark)
    cut = np.zeros_like(m)
    for j in range(1, n):
        x, y, w, h, area = stats[j]
        cx = cent[j][0]
        inner = left + 0.2 * width < cx < right - 0.2 * width
        if not (inner and h > tall * w and area > (12 if upper else 30) * S):
            continue
        cut[lab == j] = 1
        # Carry the band out through the tips.
        py, px = np.nonzero(lab == j)
        k = np.argmin(py) if upper else np.argmax(py)
        tip = (int(px[k]), int(py[k]))
        out = (tip[0], int(apex - 6 * S) if upper else int(apex + 6 * S))
        cv2.line(cut, tip, out, 1, 2 * S)
    if not cut.any():
        return m
    # A slit about 2 px wide (orig): clearly separate prongs.
    cut = cv2.dilate(cut, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * S + 1, 2 * S + 1)))
    out = (m & (1 - cut)).astype(np.uint8)
    nl, lab2, st, _ = cv2.connectedComponentsWithStats(out)
    if nl > 2:
        out = (lab2 == 1 + np.argmax(st[1:, cv2.CC_STAT_AREA])).astype(np.uint8)
    return out


rb = ndimage_rb = cv2.GaussianBlur((r - b).astype(np.float32), (0, 0), 2.0)
export = {}
for row in ROWS:
    shapes = {}
    for i, n in enumerate(FDI):
        m = np.load(os.path.join(OUT, f'{row}_{i}.npy'))
        m = smooth_mask(m, 61) if row == 'occlusal' else smooth_mask(m, 0, blur=1.2)
        if row != 'occlusal' and mask_alpha is None:
            m = split_roots(m, row)
        entry = {'cx': CENTERS[i], 'outline': contour(m, 260 if row != 'occlusal' else 160, sigma=4.5 if row != 'occlusal' else 6.0).tolist()}
        if row != 'occlusal':
            # Crown = the white part at the biting end; root is yellow.
            ys, xs = np.nonzero(m)
            crown = (m > 0) & (rb < 24)
            crown = cv2.morphologyEx(crown.astype(np.uint8), cv2.MORPH_OPEN, np.ones((7, 7), np.uint8))
            nlab, lab, stats, _ = cv2.connectedComponentsWithStats(crown)
            # The piece nearest the bite (lowest for upper, highest for lower).
            best, best_y = 0, None
            for j in range(1, nlab):
                if stats[j, cv2.CC_STAT_AREA] < 200 * S:
                    continue
                cy = stats[j, cv2.CC_STAT_TOP] + stats[j, cv2.CC_STAT_HEIGHT] / 2
                if best_y is None or (cy > best_y if row == 'upper' else cy < best_y):
                    best, best_y = j, cy
            cm = (lab == best).astype(np.uint8)
            cnts, _ = cv2.findContours(cm, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
            filled = np.zeros_like(cm)
            cv2.drawContours(filled, cnts, -1, 1, -1)
            k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (31, 31))
            cm = cv2.morphologyEx(filled & m, cv2.MORPH_OPEN, k)
            cm = smooth_mask(cm, 31) & m
            if cm.sum() < 100:
                print('no crown found:', row, n)
            else:
                entry['crown'] = contour(cm, 160, sigma=6.0).tolist()
            # Neck: crown edge points that border root, left to right.
            edge = cm - cv2.erode(cm, np.ones((3, 3), np.uint8))
            rootside = cv2.dilate(((m > 0) & (cm == 0)).astype(np.uint8), np.ones((5, 5), np.uint8))
            ny, nx = np.nonzero(edge & rootside)
            if len(nx):
                bins = np.linspace(nx.min(), nx.max(), 10)
                neck = []
                for a0, a1 in zip(bins[:-1], bins[1:]):
                    sel = (nx >= a0) & (nx <= a1)
                    if sel.any():
                        neck.append([float(nx[sel].mean()) / S, float(ny[sel].mean()) / S])
                entry['neck'] = neck
        shapes[n] = entry
    for n, twin in TWIN[row].items():
        t, e = shapes[twin], shapes[n]
        tw = {'cx': e['cx'], 'twin': twin}
        for key in ('outline', 'crown'):
            if key in t:
                tw[key] = mirror_about(np.array(t[key]), t['cx'], e['cx']).tolist()
        if 'neck' in t:
            tw['neck'] = mirror_about(np.array(t['neck']), t['cx'], e['cx'])[::-1].tolist()
        shapes[n] = tw
    export[row] = shapes
json.dump(export, open(os.path.join(OUT, 'outlines.json'), 'w'))

# 4. Check: finished outlines (cyan) and crowns (magenta) over the reference.
check = cv2.imread(SRC)
check = cv2.resize(check, None, fx=S, fy=S, interpolation=cv2.INTER_CUBIC)
for row, shapes in export.items():
    for n, e in shapes.items():
        pts = (np.array(e['outline']) * S).astype(np.int32)
        cv2.polylines(check, [pts], True, (200, 170, 0), 2)
        if 'crown' in e:
            cpts = (np.array(e['crown']) * S).astype(np.int32)
            cv2.polylines(check, [cpts], True, (180, 0, 200), 2)
        if 'twin' in e:
            cv2.putText(check, 'twin', (int(e['cx'] * S) - 30, ROWS[row][0] * S + 40),
                        cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 0, 255), 2)
for name, (x0, x1) in {'left': (0, 300), 'mid': (280, 590), 'right': (570, 864)}.items():
    cv2.imwrite(os.path.join(OUT, f'check_{name}.png'), check[50 * S:455 * S, x0 * S:x1 * S])
print('exported')
