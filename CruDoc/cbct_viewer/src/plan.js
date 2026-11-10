// Treatment-plan geometry: the nerve canal path, implant cylinders and the
// distance between them. Plain numbers only (world mm, LPS: +x left,
// +y posterior, +z superior), so it is unit-tested without a GPU.

export const NERVE_RADIUS = 1.2; // mm: the inferior alveolar canal is about 2-3 mm wide
export const SAFE_MM = 2; // the usual safety margin between an implant and the canal
export const CLOSE_MM = 1;

const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const mul = (a, s) => [a[0] * s, a[1] * s, a[2] * s];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const len = (a) => Math.hypot(a[0], a[1], a[2]);
const norm = (a) => {
  const l = len(a) || 1;
  return [a[0] / l, a[1] / l, a[2] / l];
};
const clamp01 = (t) => Math.max(0, Math.min(1, t));

// A smooth path through the clicked points (centripetal-free uniform
// Catmull-Rom; the ends repeat their point). `step` mm between samples.
export function smoothPath(points, step = 0.5) {
  if (!points || points.length < 2) return points ? points.map((p) => [...p]) : [];
  const out = [[...points[0]]];
  for (let i = 0; i < points.length - 1; i++) {
    const p0 = points[Math.max(0, i - 1)];
    const p1 = points[i];
    const p2 = points[i + 1];
    const p3 = points[Math.min(points.length - 1, i + 2)];
    const n = Math.max(1, Math.ceil(len(sub(p2, p1)) / step));
    for (let s = 1; s <= n; s++) {
      const t = s / n;
      const t2 = t * t;
      const t3 = t2 * t;
      const c = (k) => 0.5 * (2 * p1[k] + (-p0[k] + p2[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2 + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3);
      out.push([c(0), c(1), c(2)]);
    }
  }
  return out;
}

// Closest distance between segments p1-q1 and p2-q2.
export function segmentDistance(p1, q1, p2, q2) {
  const d1 = sub(q1, p1);
  const d2 = sub(q2, p2);
  const r = sub(p1, p2);
  const a = dot(d1, d1);
  const e = dot(d2, d2);
  const f = dot(d2, r);
  let s;
  let t;
  if (a < 1e-12 && e < 1e-12) return len(r);
  if (a < 1e-12) {
    s = 0;
    t = clamp01(f / e);
  } else {
    const c = dot(d1, r);
    if (e < 1e-12) {
      t = 0;
      s = clamp01(-c / a);
    } else {
      const b = dot(d1, d2);
      const den = a * e - b * b;
      s = den > 1e-12 ? clamp01((b * f - c * e) / den) : 0;
      t = (b * s + f) / e;
      if (t < 0) {
        t = 0;
        s = clamp01(-c / a);
      } else if (t > 1) {
        t = 1;
        s = clamp01((b - c) / a);
      }
    }
  }
  return len(sub(add(p1, mul(d1, s)), add(p2, mul(d2, t))));
}

const deg = (x) => (x * Math.PI) / 180;

// An implant: { top, diameter, length, jaw: 'lower' | 'upper', tiltAP, tiltLR }.
// `top` is the platform (the end at the bone crest); the apex goes into the jaw:
// down for the lower jaw, up for the upper. tiltAP leans the apex toward
// posterior (+) or anterior (-); tiltLR toward the patient's left (+) or right (-).
export function implantAxis(im) {
  const down = im.jaw === 'upper' ? 1 : -1;
  const ap = deg(im.tiltAP || 0);
  const lr = deg(im.tiltLR || 0);
  const dir = norm([Math.sin(lr), Math.sin(ap), down * Math.cos(ap) * Math.cos(lr)]);
  return { top: [...im.top], apex: add(im.top, mul(dir, im.length)), dir };
}

// Free space in mm between the implant's surface and the nerve canal's wall
// (negative = they overlap), or null when no nerve has two points.
// The implant is treated as a capsule, which errs on the safe side at its ends.
export function clearance(im, nerves, nerveRadius = NERVE_RADIUS) {
  const { top, apex } = implantAxis(im);
  let best = Infinity;
  for (const pts of nerves) {
    if (!pts || pts.length < 2) continue;
    const path = smoothPath(pts, 1);
    for (let i = 0; i < path.length - 1; i++) best = Math.min(best, segmentDistance(top, apex, path[i], path[i + 1]));
  }
  return best === Infinity ? null : best - im.diameter / 2 - nerveRadius;
}

export function safety(mm) {
  if (mm == null) return 'unknown';
  return mm >= SAFE_MM ? 'safe' : mm >= CLOSE_MM ? 'close' : 'danger';
}

// Two unit vectors at right angles to `t`.
function sideAxes(t) {
  const helper = Math.abs(t[2]) < 0.9 ? [0, 0, 1] : [1, 0, 0];
  const u = norm(cross(t, helper));
  return [u, cross(t, u)];
}

// A tube along a path, `sides` around: { points, normals, polys } in vtk layout.
// Rings follow the path with parallel transport so the tube does not twist.
export function tubeMesh(path, radius, sides = 12) {
  const n = path.length;
  if (n < 2) return { points: new Float32Array(0), normals: new Float32Array(0), polys: new Uint32Array(0) };
  const points = new Float32Array(n * sides * 3);
  const normals = new Float32Array(n * sides * 3);
  let [u, v] = sideAxes(norm(sub(path[1], path[0])));
  for (let i = 0; i < n; i++) {
    const t = norm(sub(path[Math.min(n - 1, i + 1)], path[Math.max(0, i - 1)]));
    // Parallel transport: keep u at right angles to the new direction.
    u = norm(sub(u, mul(t, dot(u, t))));
    v = cross(t, u);
    for (let s = 0; s < sides; s++) {
      const a = (s / sides) * Math.PI * 2;
      const nn = add(mul(u, Math.cos(a)), mul(v, Math.sin(a)));
      const q = (i * sides + s) * 3;
      for (let k = 0; k < 3; k++) {
        points[q + k] = path[i][k] + nn[k] * radius;
        normals[q + k] = nn[k];
      }
    }
  }
  const polys = new Uint32Array((n - 1) * sides * 2 * 4);
  let w = 0;
  for (let i = 0; i < n - 1; i++) {
    for (let s = 0; s < sides; s++) {
      const a = i * sides + s;
      const b = i * sides + ((s + 1) % sides);
      const c = a + sides;
      const d = b + sides;
      polys.set([3, a, b, d, 3, a, d, c], w);
      w += 8;
    }
  }
  return { points, normals, polys };
}

// A closed cylinder from `top` to `apex` (sides + flat ends).
export function cylinderMesh(top, apex, radius, sides = 24) {
  const t = norm(sub(apex, top));
  const [u, v] = sideAxes(t);
  const pts = [];
  const nrm = [];
  const polys = [];
  const ring = (centre, normal) => {
    const start = pts.length / 3;
    for (let s = 0; s < sides; s++) {
      const a = (s / sides) * Math.PI * 2;
      const nn = add(mul(u, Math.cos(a)), mul(v, Math.sin(a)));
      pts.push(...add(centre, mul(nn, radius)));
      nrm.push(...(normal || nn));
    }
    return start;
  };
  const a = ring(top);
  const b = ring(apex);
  for (let s = 0; s < sides; s++) {
    const s1 = (s + 1) % sides;
    polys.push(3, a + s, b + s, b + s1, 3, a + s, b + s1, a + s1);
  }
  // Ends: their own rings with flat normals, a fan from a centre point.
  for (const [centre, normal] of [[top, mul(t, -1)], [apex, t]]) {
    const r0 = ring(centre, normal);
    const c = pts.length / 3;
    pts.push(...centre);
    nrm.push(...normal);
    for (let s = 0; s < sides; s++) polys.push(3, c, r0 + s, r0 + ((s + 1) % sides));
  }
  return { points: new Float32Array(pts), normals: new Float32Array(nrm), polys: new Uint32Array(polys) };
}

// Signed distance of a point from a plane through `origin` with unit `normal`.
export const planeDistance = (p, origin, normal) => dot(sub(p, origin), normal);
