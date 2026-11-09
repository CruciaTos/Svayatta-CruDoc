// The 3D viewport: transfer-function presets, cut at crosshair, the orientation
// gizmo, the three plane outlines and click-to-place.
import { Enums, eventTarget } from '@cornerstonejs/core';
import { Enums as ToolsEnums } from '@cornerstonejs/tools';
import vtkPlane from '@kitware/vtk.js/Common/DataModel/Plane.js';
import { core, vp, MPR, COLORS, dot, cross, sub, add, mul, norm, boxCorners, valueAt, centre } from './core.js';
import { state, subscribe } from './state.js';
import { svgEl } from './chrome.js';

const hex = (h) => [parseInt(h.slice(1, 3), 16) / 255, parseInt(h.slice(3, 5), 16) / 255, parseInt(h.slice(5, 7), 16) / 255];
const IVORY_LOW = hex('#C8B48C');
const IVORY = hex('#ECE1C9');
const TEETH = hex('#F3EEE4');
const SKIN = hex('#D9A58A');

// The kept side is the side the normal points to: keep inferior, posterior, left.
const CUT_NORMAL = { axial: [0, 0, -1], coronal: [0, 1, 0], sagittal: [1, 0, 0] };
const cutPlane = vtkPlane.newInstance();

let frames = null;
let solid = 1; // 0..1, the first-open "solidify" opacity factor
let rampStart = 0; // real units where the 3D opacity starts (used by click-to-place)

const actorOf = () => {
  const v = vp('threeD');
  const a = v && v.getDefaultActor && v.getDefaultActor();
  return a && a.actor;
};

// ───────────────────────── Interactive quality ─────────────────────────
// While the doctor drags, zooms or moves the crosshair with a cut on, the 3D
// view takes half the samples along each ray (a quarter while rotating, as the
// rotate tool doubles it again); a moment after they stop, full quality comes
// back. Two traps found by measuring on Intel UHD: some sample-distance values
// (x3) make vtk compile a new shader the first time (a 1 s freeze), so we use x2
// and pre-compile it while the scan loads; and lowering the pixel density
// instead (image sample distance) was slower.

// Exposed (with ?debug) so the benchmark scripts can compare settings live.
export const tuning = { lowSampleDistance: 2, wheelSampleDistance: 4 };
let lowQuality = false; // the factor in use, or false
let sharpenTimer = null;
const baseSampling = new WeakMap(); // vtk objects are sealed: keep the normal value on the side

function baseOf(mapper) {
  if (!baseSampling.has(mapper)) baseSampling.set(mapper, mapper.getSampleDistance());
  return baseSampling.get(mapper);
}

export function is3dHidden() {
  return state.layout === 'single' && state.focus !== 'threeD';
}

let activeOverlay = null;
let activeOverlayAnim = null;

export function clearActiveOverlay() {
  if (activeOverlayAnim) {
    clearTimeout(activeOverlayAnim);
    activeOverlayAnim = null;
  }
  if (activeOverlay) {
    activeOverlay.remove();
    activeOverlay = null;
  }
}

export function snapshot3dCanvas() {
  clearActiveOverlay();
  const v = vp('threeD');
  if (!v || !frames?.threeD?.root) return null;
  const src = v.getCanvas();
  if (!src || !src.width || !src.height) return null;
  const overlay = document.createElement('canvas');
  overlay.className = 'overlay-3d-fade';
  overlay.width = src.width;
  overlay.height = src.height;
  overlay.style.position = 'absolute';
  overlay.style.inset = '0';
  overlay.style.width = '100%';
  overlay.style.height = '100%';
  overlay.style.pointerEvents = 'none';
  overlay.style.zIndex = '1';
  overlay.style.opacity = '1';
  const ctx = overlay.getContext('2d');
  ctx.drawImage(src, 0, 0);
  frames.threeD.root.append(overlay);
  activeOverlay = overlay;
  return overlay;
}

export function fadeOutOverlay(overlay, ms = 260) {
  if (!overlay) return Promise.resolve();
  const dur = state.reduced ? 80 : ms;
  const blur = !state.reduced;
  return new Promise((resolve) => {
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        if (!overlay.isConnected || overlay !== activeOverlay) {
          resolve();
          return;
        }
        overlay.style.transition = blur
          ? `opacity ${dur}ms var(--ease), filter ${dur}ms var(--ease)`
          : `opacity ${dur}ms var(--ease)`;
        overlay.style.opacity = '0';
        if (blur) overlay.style.filter = 'blur(1px)';
        activeOverlayAnim = setTimeout(() => {
          if (overlay === activeOverlay) {
            clearActiveOverlay();
          } else {
            overlay.remove();
          }
          resolve();
        }, dur);
      });
    });
  });
}

function setQuality(factor) {
  const actor = actorOf();
  if (!actor) return;
  const mapper = actor.getMapper();
  if (factor) {
    clearActiveOverlay();
    mapper.setSampleDistance(baseOf(mapper) * factor);
    lowQuality = factor;
  } else {
    if (lowQuality) {
      const overlay = snapshot3dCanvas();
      mapper.setSampleDistance(baseOf(mapper));
      lowQuality = false;
      if (!is3dHidden()) vp('threeD').render();
      fadeOutOverlay(overlay, 260);
    } else {
      mapper.setSampleDistance(baseOf(mapper));
      lowQuality = false;
      if (!is3dHidden()) vp('threeD').render();
    }
  }
}

// Renders one frame at the interaction setting and one back at full quality,
// so any shader compile happens while the scan is loading, not on the first drag.
// Cornerstone renders on the next animation frame, so wait between the two.
const prewarmed = new WeakSet();
function prewarm() {
  const actor = actorOf();
  if (!actor) return;
  const mapper = actor.getMapper();
  if (prewarmed.has(mapper) || tuning.lowSampleDistance === 1) return;
  prewarmed.add(mapper);
  const v = vp('threeD');
  const steps = [tuning.lowSampleDistance, tuning.wheelSampleDistance, 1];
  const next = () => {
    if (lowQuality) return; // the doctor is already interacting
    mapper.setSampleDistance(baseOf(mapper) * steps.shift());
    v.render();
    if (steps.length) requestAnimationFrame(() => requestAnimationFrame(next));
  };
  next();
}

export function lowerQuality(factor = tuning.lowSampleDistance) {
  clearTimeout(sharpenTimer);
  clearActiveOverlay();
  if (lowQuality !== factor) setQuality(factor);
}

export function sharpenSoon(ms = 160) {
  clearTimeout(sharpenTimer);
  sharpenTimer = setTimeout(() => setQuality(0), ms);
}

// ───────────────────────── Camera ─────────────────────────

// Anterior view turned 30° toward the patient's right and raised 20°
// (LPS: +x Left, +y Posterior, +z Superior), plus an optional azimuth offset.
export function aim3d(offsetDeg = 0) {
  const v = vp('threeD');
  if (!v) return;
  const az = ((30 + offsetDeg) * Math.PI) / 180;
  const el = (20 * Math.PI) / 180;
  const n = [-Math.sin(az) * Math.cos(el), -Math.cos(az) * Math.cos(el), Math.sin(el)];
  const k = n[2];
  const up = norm([-k * n[0], -k * n[1], 1 - k * n[2]]);
  v.setCamera({ viewPlaneNormal: n, viewUp: up });
  v.resetCamera();
  v.render();
}

// ───────────────────────── Transfer functions ─────────────────────────

export function apply3D() {
  const actor = actorOf();
  if (!actor || !core.meta) return;
  const { preset, threshold, opacity } = state.view3d;
  const m = core.meta;
  const L = m.landmarks;
  const S = (x) => x - core.valueOffset;
  const lo = S(m.values.min);
  const hi = S(m.values.max);
  const d = 0.08 * (L.teeth - L.soft);
  const prop = actor.getProperty();
  const mapper = actor.getMapper();
  const cfun = prop.getRGBTransferFunction(0);
  const ofun = prop.getScalarOpacity(0);
  cfun.removeAllPoints();
  ofun.removeAllPoints();
  prop.setUseGradientOpacity(0, false);
  const clampX = (x) => Math.min(hi - 1, Math.max(lo + 1, x));

  if (preset === 'xray' || preset === 'mip') {
    const xray = preset === 'xray';
    mapper.setBlendMode(xray ? Enums.BlendModes.AVERAGE_INTENSITY_BLEND : Enums.BlendModes.MAXIMUM_INTENSITY_BLEND);
    const a = S(xray ? m.presets.bone.low : L.soft);
    const b = S(xray ? m.presets.bone.high : m.values.max);
    cfun.addRGBPoint(lo, 0, 0, 0);
    cfun.addRGBPoint(clampX(a), 0, 0, 0);
    cfun.addRGBPoint(clampX(Math.max(b, a + 1)), 1, 1, 1);
    cfun.addRGBPoint(hi, 1, 1, 1);
    ofun.addPoint(lo, 1);
    ofun.addPoint(hi, 1);
    prop.setShade(false);
    rampStart = L.bone;
  } else {
    mapper.setBlendMode(Enums.BlendModes.COMPOSITE);
    const teeth = preset === 'teeth';
    const start = (teeth ? L.teeth - 2 * d : L.bone - d) + threshold;
    const full = (teeth ? L.teeth : L.bone + d) + threshold;
    rampStart = start;
    const peak = Math.min(1, 0.85 * (opacity / 100) * solid);
    const lowCol = teeth ? TEETH : IVORY_LOW;
    const highCol = teeth ? TEETH : IVORY;
    if (preset === 'skinBone') {
      // A thin skin layer from air up to soft tissue, then the bone ramp.
      cfun.addRGBPoint(lo, ...SKIN);
      cfun.addRGBPoint(clampX(S(start)), ...SKIN);
      cfun.addRGBPoint(clampX(S(L.teeth)), ...highCol);
      cfun.addRGBPoint(hi, ...highCol);
      ofun.addPoint(lo, 0);
      ofun.addPoint(clampX(S(L.air)), 0);
      ofun.addPoint(clampX(S(L.soft)), 0.12 * solid);
      ofun.addPoint(clampX(S(start)), 0.12 * solid);
      ofun.addPoint(clampX(S(full)), peak);
      ofun.addPoint(hi, peak);
    } else {
      cfun.addRGBPoint(lo, ...lowCol);
      cfun.addRGBPoint(clampX(S(start)), ...lowCol);
      cfun.addRGBPoint(clampX(S(L.teeth)), ...highCol);
      cfun.addRGBPoint(hi, ...highCol);
      ofun.addPoint(lo, 0);
      ofun.addPoint(clampX(S(start)), 0);
      ofun.addPoint(clampX(S(full)), peak);
      ofun.addPoint(hi, peak);
    }
    prop.setShade(true);
    prop.setAmbient(0.2);
    prop.setDiffuse(0.85);
    prop.setSpecular(0.25);
    prop.setSpecularPower(12);
  }
  if (!is3dHidden()) vp('threeD').render();
}

export function prepareSolidify() {
  solid = 0;
  aim3d(-10);
}

// The first-ever open: the jaw solidifies and turns the last 10°.
export function solidify(ms = 500) {
  const t0 = performance.now();
  solid = 0;
  aim3d(-10);
  lowerQuality();
  const step = (now) => {
    const t = Math.min(1, (now - t0) / ms);
    const e = 1 - Math.pow(1 - t, 3); // easeOutCubic
    solid = e;
    aim3d(-10 * (1 - e));
    apply3D();
    if (t < 1) requestAnimationFrame(step);
    else sharpenSoon(0);
  };
  requestAnimationFrame(step);
}

// ───────────────────────── Cut at crosshair ─────────────────────────

// The mapper always holds exactly this one plane: adding or removing a plane
// changes vtk's shader and freezes the view while it recompiles. "Off" parks the
// plane far below the volume, facing up, so it keeps everything.
export function applyCut() {
  const actor = actorOf();
  if (!actor) return;
  const mapper = actor.getMapper();
  const planes = mapper.getClippingPlanes();
  if (planes.length !== 1 || planes[0] !== cutPlane) {
    mapper.removeAllClippingPlanes();
    mapper.addClippingPlane(cutPlane);
  }
  const { cut, cutFlip } = state.view3d;
  if (cut === 'off') {
    cutPlane.setNormal(0, 0, 1);
    cutPlane.setOrigin(0, 0, -1e5);
  } else {
    const c = (core.crosshair && core.crosshair.toolCenter) || centre();
    const sign = cutFlip ? -1 : 1;
    cutPlane.setNormal(...CUT_NORMAL[cut].map((x) => x * sign));
    cutPlane.setOrigin(...c);
  }
  if (!is3dHidden()) vp('threeD').render();
}

// Everything that has to be redone when a new volume (preview -> full) is shown.
export function refresh3D() {
  apply3D();
  applyCut();
  prewarm();
  scheduleDraw();
}

// ───────────────────────── Gizmo, plane outlines, centre dot ─────────────────────────

const AXES = [
  { l: 'L', v: [1, 0, 0], c: '#E8674F', pos: true },
  { l: 'R', v: [-1, 0, 0], c: '#E8674F', pos: false },
  { l: 'P', v: [0, 1, 0], c: '#4FB47E', pos: true },
  { l: 'A', v: [0, -1, 0], c: '#4FB47E', pos: false },
  { l: 'S', v: [0, 0, 1], c: '#5AA2F0', pos: true },
  { l: 'I', v: [0, 0, -1], c: '#5AA2F0', pos: false },
];

function drawGizmo(cam) {
  const svg = frames.threeD.gizmoSvg;
  svg.replaceChildren();
  const right = cross(cam.viewUp, cam.viewPlaneNormal);
  const items = AXES.map((a) => ({ ...a, x: 30 + dot(a.v, right) * 19, y: 30 - dot(a.v, cam.viewUp) * 19, depth: dot(a.v, cam.viewPlaneNormal) })).sort((p, q) => p.depth - q.depth);
  for (const it of items) {
    svg.append(svgEl('line', { x1: 30, y1: 30, x2: it.x, y2: it.y, stroke: it.c, 'stroke-width': 1.5, 'stroke-opacity': it.pos ? 1 : 0.55 }));
    svg.append(svgEl('circle', { cx: it.x, cy: it.y, r: 8, fill: it.pos ? it.c : '#141A24', stroke: it.c, 'stroke-width': it.pos ? 0 : 1 }));
    const t = svgEl('text', { x: it.x, y: it.y + 3.5, 'text-anchor': 'middle', 'font-size': 10, 'font-weight': 600, fill: it.pos ? '#0B0E14' : '#8C94A3', 'font-family': 'Geist, system-ui, sans-serif' });
    t.textContent = it.l;
    svg.append(t);
  }
}

// A plane through `point` with `normal`, cut by the volume's box: a 3 to 6 sided polygon.
function planePolygon(point, normal) {
  const corners = boxCorners();
  const edges = [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]];
  const pts = [];
  for (const [a, b] of edges) {
    const da = dot(sub(corners[a], point), normal);
    const db = dot(sub(corners[b], point), normal);
    if (da > 0 !== db > 0 && da !== db) pts.push(add(corners[a], mul(sub(corners[b], corners[a]), da / (da - db))));
  }
  if (pts.length < 3) return pts;
  const cen = mul(pts.reduce(add, [0, 0, 0]), 1 / pts.length);
  const e1 = norm(sub(pts[0], cen));
  const e2 = cross(normal, e1);
  const angle = (p) => Math.atan2(dot(sub(p, cen), e2), dot(sub(p, cen), e1));
  return pts.sort((p, q) => angle(p) - angle(q));
}

function drawPlanes() {
  const v3 = vp('threeD');
  if (!v3 || !core.geo || !frames) return;
  drawGizmo(v3.getCamera());
  const svg = frames.threeD.svg;
  svg.replaceChildren();
  const c = (core.crosshair && core.crosshair.toolCenter) || centre();
  for (const id of MPR) {
    const n = vp(id).getCamera().viewPlaneNormal;
    const pts = planePolygon(c, n).map((p) => v3.worldToCanvas(p));
    if (pts.length < 3) continue;
    svg.append(svgEl('polygon', { points: pts.map((p) => `${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(' '), fill: COLORS[id], 'fill-opacity': 0.05, stroke: COLORS[id], 'stroke-width': 1.25 }));
  }
  const p = v3.worldToCanvas(c);
  svg.append(svgEl('circle', { cx: p[0], cy: p[1], r: 4, fill: '#fff', stroke: '#0B0E14', 'stroke-width': 1.5 }));
}

let drawPending = false;
export function scheduleDraw() {
  if (drawPending || is3dHidden()) return;
  drawPending = true;
  requestAnimationFrame(() => {
    drawPending = false;
    if (is3dHidden()) return;
    try {
      drawPlanes();
    } catch (err) {
      console.warn('CBCT viewer: 3D overlay', err);
    }
  });
}

// ───────────────────────── Click to place ─────────────────────────

// A click (no drag) on the 3D view casts a ray into the loaded volume and puts
// the crosshair on the first voxel at or above the current opacity threshold.
function pick(clientX, clientY) {
  const host = core.hosts.threeD;
  const v = vp('threeD');
  const r = host.getBoundingClientRect();
  const cam = v.getCamera();
  const onFocalPlane = v.canvasToWorld([clientX - r.left, clientY - r.top]);
  const g = core.geo;
  const diag = Math.hypot(...g.spacing.map((s, i) => s * g.dims[i]));
  const start = add(onFocalPlane, mul(cam.viewPlaneNormal, diag));
  const dir = mul(cam.viewPlaneNormal, -1);
  const step = 0.5 * Math.min(...g.spacing);
  const steps = Math.ceil((2 * diag) / step);
  for (let i = 0; i < steps; i++) {
    const p = add(start, mul(dir, step * i));
    const val = valueAt(p);
    if (val !== null && val >= rampStart) {
      core.crosshair.setToolCenter(p);
      return;
    }
  }
}

// ───────────────────────── Wiring ─────────────────────────

export function init3d(ui) {
  frames = ui.frames;
  const host = core.hosts.threeD;
  const redraw = () => scheduleDraw();
  host.addEventListener(Enums.Events.CAMERA_MODIFIED, redraw);
  for (const id of MPR) core.hosts[id].addEventListener(Enums.Events.CAMERA_MODIFIED, redraw);
  // Moving the crosshair with a cut on re-renders the 3D view: at most every 90 ms.
  let cutTimer = null;
  let cutPending = false;
  const cutSoon = () => {
    if (cutTimer) {
      cutPending = true;
      return;
    }
    applyCut();
    cutTimer = setTimeout(() => {
      cutTimer = null;
      if (cutPending) {
        cutPending = false;
        applyCut();
      }
    }, 90);
  };
  eventTarget.addEventListener(ToolsEnums.Events.CROSSHAIR_TOOL_CENTER_CHANGED, () => {
    if (state.view3d.cut !== 'off') cutSoon();
    redraw();
  });

  // Fewer samples while interacting, full quality a moment after.
  host.addEventListener('pointerdown', () => {
    clearActiveOverlay();
    lowerQuality();
  }, true);
  host.addEventListener('wheel', () => {
    clearActiveOverlay();
    lowerQuality(tuning.wheelSampleDistance);
    sharpenSoon(250);
  }, { capture: true, passive: true });
  for (const id of MPR) {
    core.hosts[id].addEventListener('pointerdown', () => {
      if (state.view3d.cut !== 'off') lowerQuality();
    }, true);
  }
  window.addEventListener('pointerup', () => {
    if (lowQuality) sharpenSoon(160);
  });

  let down = null;
  host.addEventListener('pointerdown', (e) => {
    if (e.button === 0) down = { x: e.clientX, y: e.clientY };
  }, true);
  host.addEventListener('pointerup', (e) => {
    if (!down || !core.volumeId) return;
    const moved = Math.hypot(e.clientX - down.x, e.clientY - down.y) > 4;
    down = null;
    if (!moved) pick(e.clientX, e.clientY);
  }, true);

  let wasHidden = is3dHidden();
  subscribe((s, changed) => {
    if (!core.volumeId) return;
    const nowHidden = is3dHidden();
    if (wasHidden && !nowHidden) {
      wasHidden = nowHidden;
      refresh3D();
      return;
    }
    wasHidden = nowHidden;
    if (changed.has('view3d')) {
      apply3D();
      applyCut();
    }
  });
}
