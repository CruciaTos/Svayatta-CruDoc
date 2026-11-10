// Automatic helpers for the implant plan and the scan (no AI models: plain
// image measurements). Pure functions on a voxel volume, so they are unit-tested:
//   traceCanal   follows the nerve canal between two clicked points
//   siteMeasure  bone crest, width and available height at an implant
//   suggestSize  a standard implant that fits those measurements
//   findDense    boxes around metal / very dense objects (implants, crowns, fillings)
// Volumes: `voxels` (Int16Array, stored units) with `geo` { dims, spacing, origin,
// direction }. Levels (`lv`) are in the same stored units: { air, soft, bone, ... }.
import { worldToIndex, indexToWorld } from './core.js';
import { implantAxis, smoothPath, NERVE_RADIUS, SAFE_MM } from './plan.js';

const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const mul = (a, s) => [a[0] * s, a[1] * s, a[2] * s];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const len = (a) => Math.hypot(a[0], a[1], a[2]);
const norm = (a) => mul(a, 1 / (len(a) || 1));

// Nearest-voxel value at a world point, or null outside.
export function sampler(voxels, geo) {
  const [nx, ny, nz] = geo.dims;
  return (p) => {
    const q = worldToIndex(p, geo);
    const i = Math.round(q[0]);
    const j = Math.round(q[1]);
    const k = Math.round(q[2]);
    if (i < 0 || j < 0 || k < 0 || i >= nx || j >= ny || k >= nz) return null;
    return voxels[i + nx * (j + ny * k)];
  };
}

// ───────────────────────── Nerve canal ─────────────────────────

// A min-heap of (cost, node) on typed arrays.
function makeHeap(cap) {
  let keys = new Float64Array(cap);
  let vals = new Int32Array(cap);
  let n = 0;
  return {
    get size() {
      return n;
    },
    push(k, v) {
      if (n === keys.length) {
        const k2 = new Float64Array(n * 2);
        k2.set(keys);
        keys = k2;
        const v2 = new Int32Array(n * 2);
        v2.set(vals);
        vals = v2;
      }
      let i = n++;
      while (i > 0) {
        const p = (i - 1) >> 1;
        if (keys[p] <= k) break;
        keys[i] = keys[p];
        vals[i] = vals[p];
        i = p;
      }
      keys[i] = k;
      vals[i] = v;
    },
    pop() {
      const top = vals[0];
      const k = keys[--n];
      const v = vals[n];
      let i = 0;
      for (;;) {
        let c = 2 * i + 1;
        if (c >= n) break;
        if (c + 1 < n && keys[c + 1] < keys[c]) c++;
        if (keys[c] >= k) break;
        keys[i] = keys[c];
        vals[i] = vals[c];
        i = c;
      }
      keys[i] = k;
      vals[i] = v;
      return top;
    },
    topKey: () => keys[0],
  };
}

// The cheapest path from `a` to `b` (world mm) through soft-tissue-dark voxels
// that are walled in by bone: that is what the canal looks like on a CBCT.
// Returns the points strictly between a and b, about every `everyMm` mm, or []
// when nothing sensible was found (the caller then joins a and b straight).
export function traceCanal(voxels, geo, a, b, lv, { stepMm = 0.5, padMm = 6, maxNodes = 250000, everyMm = 2.5 } = {}) {
  const [nx, ny, nz] = geo.dims;
  const sp = geo.spacing;
  const ia = worldToIndex(a, geo);
  const ib = worldToIndex(b, geo);
  const lo = [0, 1, 2].map((k) => Math.max(0, Math.floor(Math.min(ia[k], ib[k]) - padMm / sp[k])));
  const hi = [0, 1, 2].map((k) => Math.min(geo.dims[k] - 1, Math.ceil(Math.max(ia[k], ib[k]) + padMm / sp[k])));
  if (hi.some((h, k) => h < lo[k])) return [];
  // Grid step in voxels per axis (about stepMm), coarser until the grid is small enough.
  let mm = stepMm;
  let st;
  let gd;
  for (;;) {
    st = sp.map((s) => Math.max(1, Math.round(mm / s)));
    gd = [0, 1, 2].map((k) => Math.floor((hi[k] - lo[k]) / st[k]) + 1);
    if (gd[0] * gd[1] * gd[2] <= maxNodes) break;
    mm *= 1.25;
  }
  const [gx, gy, gz] = gd;
  const total = gx * gy * gz;
  const at = (i, j, k) => (i < 0 || j < 0 || k < 0 || i >= nx || j >= ny || k >= nz ? lv.air : voxels[i + nx * (j + ny * k)]);
  // Cost of standing on each grid node.
  const probe = sp.map((s) => Math.max(1, Math.round(2.2 / s))); // 2.2 mm: past the canal wall
  const airLine = (lv.air + lv.soft) / 2;
  const cost = new Float32Array(total);
  for (let k = 0; k < gz; k++) {
    for (let j = 0; j < gy; j++) {
      for (let i = 0; i < gx; i++) {
        const I = lo[0] + i * st[0];
        const J = lo[1] + j * st[1];
        const K = lo[2] + k * st[2];
        const v = at(I, J, K);
        let c;
        if (v < airLine) c = 100; // air: never through the mouth or a sinus
        else {
          const dense = Math.min(1, Math.max(0, (v - lv.soft) / (lv.bone - lv.soft)));
          let wall = 0;
          if (at(I + probe[0], J, K) >= lv.bone) wall++;
          if (at(I - probe[0], J, K) >= lv.bone) wall++;
          if (at(I, J + probe[1], K) >= lv.bone) wall++;
          if (at(I, J - probe[1], K) >= lv.bone) wall++;
          if (at(I, J, K + probe[2]) >= lv.bone) wall++;
          if (at(I, J, K - probe[2]) >= lv.bone) wall++;
          c = 1 + 8 * dense + 6 * (Math.max(0, 4 - wall) / 4);
        }
        cost[i + gx * (j + gy * k)] = c;
      }
    }
  }
  const node = (q) => {
    const g = [0, 1, 2].map((k) => Math.round((q[k] - lo[k]) / st[k]));
    return Math.min(gx - 1, Math.max(0, g[0])) + gx * (Math.min(gy - 1, Math.max(0, g[1])) + gy * Math.min(gz - 1, Math.max(0, g[2])));
  };
  const start = node(ia);
  const goal = node(ib);
  // 26 neighbours, each with its length in mm.
  const nb = [];
  for (let dk = -1; dk <= 1; dk++) for (let dj = -1; dj <= 1; dj++) for (let di = -1; di <= 1; di++) {
    if (di || dj || dk) nb.push([di, dj, dk, Math.hypot(di * st[0] * sp[0], dj * st[1] * sp[1], dk * st[2] * sp[2])]);
  }
  const dist = new Float64Array(total).fill(Infinity);
  const prev = new Int32Array(total).fill(-1);
  const heap = makeHeap(1024);
  dist[start] = 0;
  heap.push(0, start);
  while (heap.size) {
    const d = heap.topKey();
    const u = heap.pop();
    if (d > dist[u]) continue;
    if (u === goal) break;
    const ui = u % gx;
    const uj = ((u / gx) | 0) % gy;
    const uk = (u / (gx * gy)) | 0;
    for (const [di, dj, dk, l] of nb) {
      const vi = ui + di;
      const vj = uj + dj;
      const vk = uk + dk;
      if (vi < 0 || vj < 0 || vk < 0 || vi >= gx || vj >= gy || vk >= gz) continue;
      const v = vi + gx * (vj + gy * vk);
      const nd = d + l * 0.5 * (cost[u] + cost[v]);
      if (nd < dist[v]) {
        dist[v] = nd;
        prev[v] = u;
        heap.push(nd, v);
      }
    }
  }
  if (prev[goal] < 0 && goal !== start) return [];
  const chain = [];
  for (let u = goal; u >= 0; u = prev[u]) {
    const i = u % gx;
    const j = ((u / gx) | 0) % gy;
    const k = (u / (gx * gy)) | 0;
    chain.push(indexToWorld([lo[0] + i * st[0], lo[1] + j * st[1], lo[2] + k * st[2]], geo));
  }
  chain.reverse();
  // Smooth the staircase, then keep a point every `everyMm` mm (the ends are the clicks).
  const sm = chain.map((_, i) => {
    let s = [0, 0, 0];
    let n = 0;
    for (let w = -2; w <= 2; w++) {
      const q = chain[Math.min(chain.length - 1, Math.max(0, i + w))];
      s = add(s, q);
      n++;
    }
    return mul(s, 1 / n);
  });
  const out = [];
  let run = 0;
  for (let i = 1; i < sm.length - 1; i++) {
    run += len(sub(sm[i], sm[i - 1]));
    if (run >= everyMm && len(sub(sm[i], b)) > everyMm / 2) {
      out.push(sm[i]);
      run = 0;
    }
  }
  return out;
}

// ───────────────────────── Implant site ─────────────────────────

// Two unit vectors at right angles to `t`.
function sideAxes(t) {
  const helper = Math.abs(t[2]) < 0.9 ? [0, 0, 1] : [1, 0, 0];
  const u = norm(cross(t, helper));
  return [u, cross(t, u)];
}

// Narrowest bone chord through `c` across the plane at right angles to `dir` (mm), or null.
function boneWidth(val, c, dir, inBone) {
  const v0 = val(c);
  if (v0 == null || v0 < inBone) return null;
  const [u, w] = sideAxes(dir);
  let best = Infinity;
  for (let a = 0; a < 180; a += 15) {
    const r = (a * Math.PI) / 180;
    const d = add(mul(u, Math.cos(r)), mul(w, Math.sin(r)));
    let width = 0;
    for (const sgn of [1, -1]) {
      let gap = 0;
      let last = 0;
      for (let t = 0.25; t <= 15; t += 0.25) {
        const x = val(add(c, mul(d, sgn * t)));
        if (x != null && x >= inBone) {
          last = t;
          gap = 0;
        } else if ((gap += 0.25) > 0.5) break;
      }
      width += last;
    }
    best = Math.min(best, width);
  }
  return best === Infinity ? null : best;
}

// Measurements along an implant (all mm):
//   crest          world point where the axis enters the bone (null: no bone on the axis)
//   crestOffset    how far the implant top sits above (+) or below (-) that crest
//   widthCrest     narrowest bone width 2 mm below the crest
//   widthMid       the same at the middle of the planned implant
//   heightToNerve  from the crest along the axis to the canal's roof (lower jaw; null: no
//                  traced canal under this site)
//   heightToAir    from the crest along the axis to the first air (sinus or nose floor
//                  in the upper jaw; null: none within 40 mm)
export function siteMeasure(voxels, geo, im, lv, nerves = []) {
  const val = sampler(voxels, geo);
  const { top, dir } = implantAxis(im);
  const ridge = lv.soft + 0.5 * (lv.bone - lv.soft);
  const inBone = lv.soft + 0.3 * (lv.bone - lv.soft);
  const airLine = (lv.air + lv.soft) / 2;
  let crestT = null;
  for (let t = -8; t <= im.length; t += 0.2) {
    const x = val(add(top, mul(dir, t)));
    if (x != null && x >= ridge) {
      crestT = t;
      break;
    }
  }
  if (crestT == null) return { crest: null, crestOffset: null, widthCrest: null, widthMid: null, heightToNerve: null, heightToAir: null };
  const crest = add(top, mul(dir, crestT));
  let heightToAir = null;
  let airRun = 0;
  for (let t = 0; t <= 40; t += 0.2) {
    const x = val(add(crest, mul(dir, t)));
    if (x != null && x < airLine) {
      airRun += 0.2;
      if (airRun >= 1) {
        heightToAir = t - airRun + 0.2;
        break;
      }
    } else airRun = 0;
  }
  let heightToNerve = null;
  for (const pts of nerves) {
    if (!pts || pts.length < 2) continue;
    for (const q of smoothPath(pts, 0.5)) {
      const r = sub(q, crest);
      const along = dot(r, dir);
      const side = len(sub(r, mul(dir, along)));
      if (along > 0 && side <= 5) heightToNerve = Math.min(heightToNerve == null ? Infinity : heightToNerve, along - NERVE_RADIUS);
    }
  }
  return {
    crest,
    crestOffset: crestT,
    widthCrest: boneWidth(val, add(crest, mul(dir, 2)), dir, inBone),
    widthMid: boneWidth(val, add(crest, mul(dir, Math.max(2, im.length / 2))), dir, inBone),
    heightToNerve,
    heightToAir,
  };
}

export const DIAMETERS = [3.0, 3.3, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0];
export const LENGTHS = [6, 7, 8, 8.5, 10, 11.5, 13, 14, 16];

// A standard implant for a measured site: 1.5 mm of bone on each side, 2 mm above
// the nerve canal, 1 mm below a sinus. Returns { diameter, length, notes }.
export function suggestSize(m, jaw) {
  const notes = [];
  const widths = [m.widthCrest, m.widthMid].filter((w) => w != null);
  let diameter = 4.0;
  if (widths.length) {
    const room = Math.min(...widths) - 3;
    const fit = DIAMETERS.filter((d) => d <= room + 1e-9);
    diameter = fit.length ? fit[fit.length - 1] : DIAMETERS[0];
    if (!fit.length) notes.push('Narrow ridge: less than 1.5 mm of bone around the smallest implant.');
  } else notes.push('Bone width not found at this site.');
  let room = null;
  if (jaw === 'upper' && m.heightToAir != null) room = m.heightToAir - 1;
  else if (jaw !== 'upper' && m.heightToNerve != null) room = m.heightToNerve - SAFE_MM;
  let length = 10;
  if (room == null) notes.push(jaw === 'upper' ? 'No sinus floor found along the implant.' : 'Trace the nerve canal to size the length.');
  else {
    const fit = LENGTHS.filter((l) => l <= room + 1e-9);
    length = fit.length ? fit[fit.length - 1] : LENGTHS[0];
    if (!fit.length) notes.push(jaw === 'upper' ? 'Less than 7 mm under the sinus: consider a sinus lift.' : 'Less than 8 mm above the canal: very short bone.');
  }
  return { diameter, length, notes };
}

// ───────────────────────── Dense objects ─────────────────────────

// Boxes around connected voxels at or above `threshold` (stored units): metal
// implants, crowns, fillings, root fillings. Works on a grid of at most
// `maxGrid` voxels per axis. Returns up to `maxCount` boxes, largest first:
// { min, max (world, corners of the voxel box), centre, sizeMm, volumeMm3 }.
export function findDense(voxels, geo, threshold, { maxGrid = 192, minMm3 = 1, maxCount = 40 } = {}) {
  const [nx, ny, nz] = geo.dims;
  const s = Math.max(1, Math.ceil(Math.max(nx, ny, nz) / maxGrid));
  const g = [Math.ceil(nx / s), Math.ceil(ny / s), Math.ceil(nz / s)];
  const [gx, gy, gz] = g;
  const mask = new Uint8Array(gx * gy * gz);
  for (let k = 0; k < gz; k++) for (let j = 0; j < gy; j++) for (let i = 0; i < gx; i++) {
    if (voxels[i * s + nx * (j * s + ny * (k * s))] >= threshold) mask[i + gx * (j + gy * k)] = 1;
  }
  const voxelMm3 = geo.spacing[0] * geo.spacing[1] * geo.spacing[2] * s * s * s;
  const stack = new Int32Array(mask.length);
  const found = [];
  for (let start = 0; start < mask.length; start++) {
    if (mask[start] !== 1) continue;
    mask[start] = 2;
    let top = 0;
    stack[top++] = start;
    let count = 0;
    const lo = [Infinity, Infinity, Infinity];
    const hi = [-Infinity, -Infinity, -Infinity];
    while (top) {
      const u = stack[--top];
      count++;
      const i = u % gx;
      const j = ((u / gx) | 0) % gy;
      const k = (u / (gx * gy)) | 0;
      if (i < lo[0]) lo[0] = i;
      if (j < lo[1]) lo[1] = j;
      if (k < lo[2]) lo[2] = k;
      if (i > hi[0]) hi[0] = i;
      if (j > hi[1]) hi[1] = j;
      if (k > hi[2]) hi[2] = k;
      if (i > 0 && mask[u - 1] === 1) { mask[u - 1] = 2; stack[top++] = u - 1; }
      if (i < gx - 1 && mask[u + 1] === 1) { mask[u + 1] = 2; stack[top++] = u + 1; }
      if (j > 0 && mask[u - gx] === 1) { mask[u - gx] = 2; stack[top++] = u - gx; }
      if (j < gy - 1 && mask[u + gx] === 1) { mask[u + gx] = 2; stack[top++] = u + gx; }
      if (k > 0 && mask[u - gx * gy] === 1) { mask[u - gx * gy] = 2; stack[top++] = u - gx * gy; }
      if (k < gz - 1 && mask[u + gx * gy] === 1) { mask[u + gx * gy] = 2; stack[top++] = u + gx * gy; }
    }
    const volumeMm3 = count * voxelMm3;
    if (volumeMm3 < minMm3) continue;
    // Index box (full resolution, voxel edges), then its world corners.
    const a = lo.map((x) => x * s - 0.5);
    const b = hi.map((x, q) => Math.min(geo.dims[q] - 1, x * s + s - 1) + 0.5);
    const corners = [];
    for (const x of [a[0], b[0]]) for (const y of [a[1], b[1]]) for (const z of [a[2], b[2]]) corners.push(indexToWorld([x, y, z], geo));
    const min = [0, 1, 2].map((q) => Math.min(...corners.map((c) => c[q])));
    const max = [0, 1, 2].map((q) => Math.max(...corners.map((c) => c[q])));
    found.push({ min, max, centre: mul(add(min, max), 0.5), sizeMm: sub(max, min), volumeMm3 });
  }
  found.sort((p, q) => q.volumeMm3 - p.volumeMm3);
  return found.slice(0, maxCount);
}
