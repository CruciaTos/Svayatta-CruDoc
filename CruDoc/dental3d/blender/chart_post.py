"""Stage 2 of the chart pictures: crop the raw 1200 px renders to the tooth, fit to 480 px height with the
original margin (2 px for turns, 3 px for occlusal / apical), and save transparent WebP.
Edge colour is flood-filled from the solid interior and resized premultiplied, so there is no dark halo.

  python blender/chart_post.py <raw_dir> <out_dir>
(plain Python with numpy, scipy, Pillow - not Blender's)
"""
import os
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

H = 480
MARGIN = {'turn': 2, 'occlusal': 3, 'apical': 3}


def clean(a):
    """straight-alpha float RGBA (h,w,4) -> colours of translucent edge pixels replaced by the nearest solid ones."""
    al = a[..., 3]
    solid = al > 0.97
    if solid.sum() < 50:
        return a
    idx = ndimage.distance_transform_edt(~solid, return_distances=False, return_indices=True)
    rgb = a[..., :3][idx[0], idx[1]]
    out = a.copy()
    edge = ~solid
    out[..., :3][edge] = rgb[edge]
    return out


def process(src, dst, margin):
    im = Image.open(src).convert('RGBA')
    a = np.asarray(im).astype(np.float32) / 255.0
    ys, xs = np.nonzero(a[..., 3] > 0.03)
    if len(ys) == 0:
        raise SystemExit('empty render ' + src)
    a = a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    a = clean(a)
    h0, w0 = a.shape[:2]
    th = H - 2 * margin
    tw = max(1, int(round(w0 * th / h0)))
    pm = a.copy()
    pm[..., :3] *= pm[..., 3:4]
    chans = [np.asarray(Image.fromarray(pm[..., c], 'F').resize((tw, th), Image.LANCZOS)) for c in range(4)]
    r = np.stack(chans, -1)
    r[..., 3] = np.clip(r[..., 3], 0, 1)
    rgb = r[..., :3] / np.maximum(r[..., 3:4], 1e-4)
    out = np.zeros((H, tw + 2 * margin, 4), np.float32)
    out[margin:margin + th, margin:margin + tw, :3] = np.clip(rgb, 0, 1)
    out[margin:margin + th, margin:margin + tw, 3] = r[..., 3]
    out[..., :3] *= (out[..., 3:4] > 0.002)
    Image.fromarray((out * 255 + 0.5).astype(np.uint8), 'RGBA').save(dst, 'WEBP', quality=92, alpha_quality=95, method=4)


if __name__ == '__main__':
    raw, outd = sys.argv[1], sys.argv[2]
    os.makedirs(outd, exist_ok=True)
    n = 0
    for f in sorted(os.listdir(raw)):
        if not f.endswith('.png'):
            continue
        kind = 'turn' if '_turn' in f else ('occlusal' if 'occlusal' in f else 'apical')
        process(os.path.join(raw, f), os.path.join(outd, f[:-4] + '.webp'), MARGIN[kind])
        n += 1
    print('post-processed', n)
