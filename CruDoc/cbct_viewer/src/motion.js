// Camera motion for the 3D view: every change of view is a move, never a jump.
// flyTo() turns/zooms the camera to a target along the shortest arc; smoothZoom()
// replaces the wheel's notch-by-notch zoom with one that glides to its target
// and keeps the point under the cursor where it is.
//
// The caller passes `begin` (called every moving frame: draw light) and `end`
// (the move is over: sharpen).
import { vp, dot, cross, sub, add, mul, norm } from './core.js';
import { state } from './state.js';

// ---------- quaternions [x, y, z, w] from a camera's (right, up, normal) basis ----------

function quatOf(up, normal) {
  const r = cross(up, normal);
  const m = [r[0], up[0], normal[0], r[1], up[1], normal[1], r[2], up[2], normal[2]];
  const tr = m[0] + m[4] + m[8];
  let q;
  if (tr > 0) {
    const s = Math.sqrt(tr + 1) * 2;
    q = [(m[7] - m[5]) / s, (m[2] - m[6]) / s, (m[3] - m[1]) / s, s / 4];
  } else if (m[0] > m[4] && m[0] > m[8]) {
    const s = Math.sqrt(1 + m[0] - m[4] - m[8]) * 2;
    q = [s / 4, (m[1] + m[3]) / s, (m[2] + m[6]) / s, (m[7] - m[5]) / s];
  } else if (m[4] > m[8]) {
    const s = Math.sqrt(1 + m[4] - m[0] - m[8]) * 2;
    q = [(m[1] + m[3]) / s, s / 4, (m[5] + m[7]) / s, (m[2] - m[6]) / s];
  } else {
    const s = Math.sqrt(1 + m[8] - m[0] - m[4]) * 2;
    q = [(m[2] + m[6]) / s, (m[5] + m[7]) / s, s / 4, (m[3] - m[1]) / s];
  }
  return q;
}

export function slerp(a, b, t) {
  let d = a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3];
  const e = d < 0 ? b.map((x) => -x) : b;
  d = Math.abs(d);
  if (d > 0.9995) {
    const q = a.map((x, i) => x + (e[i] - x) * t);
    const l = Math.hypot(...q) || 1;
    return q.map((x) => x / l);
  }
  const th = Math.acos(d);
  const sa = Math.sin((1 - t) * th) / Math.sin(th);
  const sb = Math.sin(t * th) / Math.sin(th);
  return a.map((x, i) => x * sa + e[i] * sb);
}

// The camera's up and normal for a quaternion.
export function basisOf([x, y, z, w]) {
  const up = [2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w)];
  const normal = [2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y)];
  return { viewUp: norm(up), viewPlaneNormal: norm(normal) };
}

export const cameraQuat = (cam) => quatOf(norm(cam.viewUp), norm(cam.viewPlaneNormal));

// ---------- fly ----------

let flight = 0;
export const cancelFlight = () => {
  flight++;
};

// target: { viewPlaneNormal, viewUp, focalPoint?, parallelScale? }
export function flyTo(target, ms, { begin, end }) {
  const v = vp('threeD');
  if (!v) return;
  const from = v.getCamera();
  const dist = Math.hypot(...sub(from.position, from.focalPoint)) || 1;
  const f1 = target.focalPoint || from.focalPoint;
  const s1 = target.parallelScale || from.parallelScale;
  const id = ++flight;
  const apply = (rot, focal, scale) => {
    v.setCamera({ ...rot, focalPoint: focal, position: add(focal, mul(rot.viewPlaneNormal, dist)), parallelScale: scale });
    v.render();
  };
  if (state.reduced || ms <= 0) {
    apply({ viewUp: norm(target.viewUp), viewPlaneNormal: norm(target.viewPlaneNormal) }, f1, s1);
    end();
    return;
  }
  const q0 = cameraQuat(from);
  const q1 = cameraQuat(target);
  const t0 = performance.now();
  const step = (now) => {
    if (id !== flight) return;
    const t = Math.min(1, (now - t0) / ms);
    const e = 1 - Math.pow(1 - t, 3); // easeOutCubic
    begin();
    const focal = add(from.focalPoint, mul(sub(f1, from.focalPoint), e));
    apply(basisOf(slerp(q0, q1, e)), focal, from.parallelScale * Math.pow(s1 / from.parallelScale, e));
    if (t < 1) requestAnimationFrame(step);
    else end();
  };
  begin();
  requestAnimationFrame(step);
}

// ---------- wheel zoom ----------

// `limits()` returns [smallest, largest] parallel scale allowed.
export function smoothZoom(host, { begin, end, limits }) {
  let target = null;
  let anchor = null;
  let raf = 0;
  let last = 0;
  const tick = (now) => {
    const v = vp('threeD');
    if (!v || target === null) {
      raf = 0;
      return;
    }
    const cam = v.getCamera();
    const dt = Math.min(50, now - last);
    last = now;
    const s0 = cam.parallelScale;
    let s1 = s0 + (target - s0) * (1 - Math.exp(-dt / 70));
    const done = state.reduced || Math.abs(target - s1) / target < 0.003;
    if (done) s1 = target;
    // Keep the point under the cursor in place: move the camera toward it as it zooms in.
    const k = s1 / s0;
    let shift = mul(sub(cam.focalPoint, anchor), k - 1);
    shift = sub(shift, mul(cam.viewPlaneNormal, dot(shift, cam.viewPlaneNormal)));
    begin();
    v.setCamera({ parallelScale: s1, focalPoint: add(cam.focalPoint, shift), position: add(cam.position, shift) });
    v.render();
    if (done) {
      raf = 0;
      target = null;
      end();
    } else {
      raf = requestAnimationFrame(tick);
    }
  };
  host.addEventListener('wheel', (e) => {
    const v = vp('threeD');
    if (!v) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    cancelFlight();
    const cam = v.getCamera();
    const dy = e.deltaMode === 1 ? e.deltaY * 40 : e.deltaY;
    const [lo, hi] = limits();
    target = Math.min(hi, Math.max(lo, (target === null ? cam.parallelScale : target) * Math.exp(dy * 0.0016)));
    const r = host.getBoundingClientRect();
    anchor = v.canvasToWorld([e.clientX - r.left, e.clientY - r.top]);
    begin();
    if (!raf) {
      last = performance.now();
      raf = requestAnimationFrame(tick);
    }
  }, { capture: true, passive: false });
}
