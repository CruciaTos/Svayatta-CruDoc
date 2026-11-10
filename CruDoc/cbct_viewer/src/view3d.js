// The 3D viewport: the looks (presets3d.js), how it is drawn while the picture
// moves and when it is still, camera moves, cut at crosshair, the orientation
// gizmo, the three plane outlines and click-to-place.
import { Enums, eventTarget } from '@cornerstonejs/core';
import { Enums as ToolsEnums } from '@cornerstonejs/tools';
import vtkPlane from '@kitware/vtk.js/Common/DataModel/Plane.js';
import { core, vp, MPR, COLORS, dot, cross, sub, add, mul, norm, boxCorners, valueAt, centre } from './core.js';
import { state, subscribe } from './state.js';
import { svgEl } from './chrome.js';
import { buildLook } from './presets3d.js';
import { flyTo, cancelFlight, smoothZoom } from './motion.js';
import { buildSurfaces, placeSurfaces, discardSurfaces, dropSurfaces, keepPlaced, styleSurfaces, surfaceActors, surfaceKey, shownKey, meshStats } from './surface.js';

// The kept side is the side the normal points to: keep inferior, posterior, left.
const CUT_NORMAL = { axial: [0, 0, -1], coronal: [0, 1, 0], sagittal: [1, 0, 0] };
const cutPlane = vtkPlane.newInstance();
const FINE_UID = 'cbctFine'; // the same id engine.js gives the sharper copy

let frames = null;
let solid = 1; // 0..1, the first-open "solidify" opacity factor
let rampStart = 0; // real units where the 3D opacity starts (used by click-to-place)
let homeScale = 0; // parallel scale of the whole-scan view

const v3 = () => vp('threeD');
// The light copy (always there) and the sharper one (only when the zoom needs it).
const fastActor = () => {
  const e = v3() && v3().getDefaultActor && v3().getDefaultActor();
  return e && e.actor;
};
const fineActor = () => {
  const e = v3() && v3().getActor && v3().getActor(FINE_UID);
  return e && e.actor;
};
const nextFrames = (n = 2) => new Promise((resolve) => {
  const tick = () => (--n <= 0 ? resolve() : requestAnimationFrame(tick));
  requestAnimationFrame(tick);
});

export function is3dHidden() {
  return state.layout === 'single' && state.focus !== 'threeD';
}

// ───────────────────────── Moving and still ─────────────────────────
// Like a game: while the picture moves (rotate, zoom, a camera move, a slider)
// it must never drop a frame, so it is drawn light; the moment it stops, the
// sharp picture fades in over it. The cost of a frame is the number of samples
// along the rays (not the size of the volume), so "light" is one of these plans,
// cheapest first:
const PLANS = [
  [false, 4], // the light copy, a quarter of the samples   (weak graphics chips)
  [false, 2], // the light copy, half the samples
  [false, 1], // the light copy, every sample
  [true, 2], // the sharp copy, half the samples
  [true, 1], // the sharp copy as it is: moving looks the same as still
];
// Which plan this computer can hold at full frame rate is MEASURED, hidden
// behind the poster or a snapshot of the view (calibrate below): a few frames
// of each plan, cheapest first, until one is too slow. That also compiles each
// plan's shader ahead: vtk compiles a new shader for every new sample count,
// which would be a 1 s freeze on the first drag.

// Exposed (with ?debug) so the benchmark scripts can read and force the plan.
export const tuning = { plan: 0, frameMs: 16.7, auto: true };
let moving = false;
let sharpenTimer = null;
const baseSampling = new WeakMap(); // vtk objects are sealed: keep the normal value on the side
const calibrated = new Map(); // signature of (look, view size, copies) -> plan
const actorIds = new WeakMap();
let actorCount = 0;

function baseOf(mapper) {
  if (!baseSampling.has(mapper)) baseSampling.set(mapper, mapper.getSampleDistance());
  return baseSampling.get(mapper);
}
function idOf(actor) {
  if (!actor) return 0;
  if (!actorIds.has(actor)) actorIds.set(actor, ++actorCount);
  return actorIds.get(actor);
}

export const isMoving = () => moving;

// True while the look on screen is drawn as surface meshes (surface.js): no
// ray casting, so nothing to switch between moving and still.
let meshLook = false;
export const isSurfaceMode = () => meshLook;

// For the test scripts (with ?debug): what is on screen right now.
export function debug3d() {
  const f = fastActor();
  const g = fineActor();
  const k = (a) => (a ? Math.round((a.getMapper().getSampleDistance() / baseOf(a.getMapper())) * 10) / 10 : null);
  return { plan: tuning.plan, budget: Math.round(budget()), moving, fast: f ? f.getVisibility() : null, fastX: k(f), fine: g ? g.getVisibility() : null, fineX: k(g), mesh: meshLook, tris: meshStats.triangles, meshMs: meshStats.ms, grid: meshStats.grid && meshStats.grid.join('x') };
}

// Shows one of the two copies at a sample factor (both hidden in mesh mode:
// a visible volume next to a mesh costs a depth texture and another shader).
function present(useFine, factor) {
  const f = fastActor();
  if (!f) return;
  const g = fineActor();
  if (meshLook) {
    f.setVisibility(false);
    if (g) g.setVisibility(false);
    return;
  }
  const on = useFine && g ? g : f;
  if (g) g.setVisibility(on === g);
  f.setVisibility(on === f);
  const m = on.getMapper();
  m.setSampleDistance(baseOf(m) * (useFine && !g ? 1 : factor));
}
const presentStill = () => present(true, 1);
const presentMoving = () => present(...PLANS[tuning.plan]);

// ---- the snapshot that hides every swap ----

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
  const v = v3();
  if (!v || !frames || !frames.threeD || !frames.threeD.root || is3dHidden()) return null;
  const src = v.getCanvas();
  if (!src || !src.width || !src.height) return null;
  const overlay = document.createElement('canvas');
  overlay.className = 'overlay-3d-fade';
  overlay.width = src.width;
  overlay.height = src.height;
  overlay.getContext('2d').drawImage(src, 0, 0);
  frames.threeD.root.append(overlay);
  activeOverlay = overlay;
  return overlay;
}

export function fadeOutOverlay(overlay, ms = 260) {
  if (!overlay) return Promise.resolve();
  const dur = state.reduced ? 80 : ms;
  return new Promise((resolve) => {
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        if (!overlay.isConnected || overlay !== activeOverlay) {
          resolve();
          return;
        }
        overlay.style.transition = `opacity ${dur}ms var(--ease)`;
        overlay.style.opacity = '0';
        activeOverlayAnim = setTimeout(() => {
          if (overlay === activeOverlay) clearActiveOverlay();
          else overlay.remove();
          resolve();
        }, dur);
      });
    });
  });
}

// ---- measuring ----

const nextFrame = () => new Promise((resolve) => requestAnimationFrame(resolve));
// A moving frame may take this long: every refresh of a 60 Hz screen, 60 a second on a faster one.
const budget = () => Math.max(tuning.frameMs * 1.2, 17);

// The frame time of the screen itself, so "no dropped frames" means the same on 60 and 144 Hz.
function measureDisplay() {
  const got = [];
  let last = 0;
  const tick = (t) => {
    if (last) got.push(t - last);
    last = t;
    if (got.length < 24) requestAnimationFrame(tick);
    else tuning.frameMs = Math.min(34, Math.max(4, got.sort((a, b) => a - b)[6]));
  };
  requestAnimationFrame(tick);
}

// What a measurement belongs to: the look and the size of the view (a step is
// about 40 % more pixels). The plans that use the sharp copy also depend on it.
function signature() {
  const canvas = v3().getCanvas();
  const size = Math.round(Math.log2(Math.max(1, canvas.width * canvas.height)) * 2);
  return `${fastActor().getMapper().getBlendMode()}|${size}`;
}
const LIGHT_PLANS = 3; // the first three plans draw the light copy

// True when the look or the size of the view changed since the last measurement.
export const needsCalibration = () => !meshLook && !!fastActor() && !is3dHidden() && tuning.auto && !calibrated.has(signature());

// A few frames of one plan: its usual frame time in ms, or null if interrupted.
async function costOf(useFine, factor, limit) {
  const v = v3();
  present(useFine, factor);
  v.render();
  await nextFrames(2); // the shader compiles here
  const got = [];
  let last = await nextFrame();
  for (let n = 0; n < 4 && !moving; n++) {
    v.render();
    const t = await nextFrame();
    got.push(t - last);
    last = t;
    if (got[n] > limit * 2) break; // far too slow: no need to keep looking
  }
  if (moving || !got.length) return null;
  got.sort((x, y) => x - y);
  return got[Math.floor(got.length / 2)];
}

// Tries the plans cheapest first and keeps the best one that fits the budget.
// The caller covers the view. Stops at once if the doctor starts to interact
// (the plan found so far is used until the next chance).
async function calibrate() {
  if (meshLook || !v3() || !fastActor() || is3dHidden()) return;
  const sig = signature();
  const limit = budget();
  if (!calibrated.has(sig)) {
    if (!tuning.auto) return;
    let best = 0;
    for (let i = 0; i < LIGHT_PLANS; i++) {
      const cost = await costOf(PLANS[i][0], PLANS[i][1], limit);
      if (cost === null) return;
      if (i > 0 && cost > limit) break;
      best = i;
    }
    calibrated.set(sig, best);
  }
  tuning.plan = calibrated.get(sig);
  // The light copy at every sample is free on this computer: try the sharp copy too.
  const g = fineActor();
  if (!g || tuning.plan < LIGHT_PLANS - 1 || !tuning.auto) return;
  const fineSig = `${sig}|${idOf(g)}`;
  if (!calibrated.has(fineSig)) {
    let best = LIGHT_PLANS - 1;
    for (let i = LIGHT_PLANS; i < PLANS.length; i++) {
      const cost = await costOf(PLANS[i][0], PLANS[i][1], limit);
      if (cost === null) return;
      if (cost > limit) break;
      best = i;
    }
    calibrated.set(fineSig, best);
  }
  tuning.plan = calibrated.get(fineSig);
}

// ---- while it moves: step down if real use turns out heavier than the measurement ----

let meterOn = false;
let measured = true;
let rendered = false;
let renderedBefore = false;
let lastRaf = 0;
let slowRun = 0;
let samples = [];
let stillCost = 0; // ms the last sharp frame took
export const stillMs = () => stillCost;

function cheaper() {
  if (tuning.plan === 0 || !tuning.auto) return;
  tuning.plan -= 1;
  try {
    const sig = signature();
    calibrated.set(sig, Math.min(tuning.plan, LIGHT_PLANS - 1));
    if (fineActor()) calibrated.set(`${sig}|${idOf(fineActor())}`, tuning.plan);
  } catch {
    /* no view right now */
  }
}

function meter(t) {
  if (!meterOn) return;
  if (renderedBefore && lastRaf) {
    const d = t - lastRaf;
    samples.push(d);
    slowRun = d > Math.max(50, budget() * 2.5) ? slowRun + 1 : 0;
    // Clearly too heavy: do not wait for the end of the drag.
    if (slowRun >= 5 && measured) {
      slowRun = 0;
      samples = [];
      cheaper();
      presentMoving();
    }
  }
  renderedBefore = rendered;
  rendered = false;
  lastRaf = t;
  requestAnimationFrame(meter);
}

// Start of anything that moves the picture. Safe to call every frame.
// `measure` false: this motion is not a fair sample of what a plan costs.
export function lowerQuality(measure = true) {
  clearTimeout(sharpenTimer);
  sharpenTimer = null;
  if (moving) return;
  clearActiveOverlay();
  moving = true;
  measured = measure && !meshLook; // mesh frames say nothing about the ray-cast plans
  samples = [];
  slowRun = 0;
  lastRaf = 0;
  rendered = false;
  renderedBefore = false;
  presentMoving();
  if (!meterOn) {
    meterOn = true;
    requestAnimationFrame(meter);
  }
}

// The picture stopped: the sharp one fades in over the last moving frame.
async function settle() {
  sharpenTimer = null;
  if (!moving) return;
  moving = false;
  meterOn = false;
  if (measured && samples.length >= 15) {
    const sorted = [...samples].sort((a, b) => a - b);
    if (sorted[Math.floor(sorted.length * 0.75)] > budget() * 2) cheaper();
  }
  if (meshLook) return; // the moving picture already is the still one
  const overlay = snapshot3dCanvas();
  presentStill();
  if (is3dHidden()) return;
  v3().render();
  const t0 = await nextFrame();
  fadeOutOverlay(overlay, 260);
  const t1 = await nextFrame();
  const t2 = await nextFrame();
  if (!moving) stillCost = Math.max(t1 - t0, t2 - t1);
}

export function sharpenSoon(ms = 160) {
  clearTimeout(sharpenTimer);
  sharpenTimer = setTimeout(settle, ms);
}

// ───────────────────────── Camera ─────────────────────────

// Anterior view turned 30° toward the right of the patient and raised 20°
// (LPS: +x Left, +y Posterior, +z Superior), plus an optional azimuth offset.
function homeAim(offsetDeg = 0) {
  const az = ((30 + offsetDeg) * Math.PI) / 180;
  const el = (20 * Math.PI) / 180;
  const n = [-Math.sin(az) * Math.cos(el), -Math.cos(az) * Math.cos(el), Math.sin(el)];
  const k = n[2];
  return { viewPlaneNormal: n, viewUp: norm([-k * n[0], -k * n[1], 1 - k * n[2]]) };
}

const pickCam = (c) => ({ viewUp: c.viewUp, viewPlaneNormal: c.viewPlaneNormal, position: c.position, focalPoint: c.focalPoint, parallelScale: c.parallelScale });

// Jumps to the whole-scan view (used before the first frame is shown).
export function aim3d(offsetDeg = 0) {
  const v = v3();
  if (!v) return;
  v.setCamera(homeAim(offsetDeg));
  v.resetCamera();
  homeScale = v.getCamera().parallelScale;
  v.render();
}

const moveHooks = { begin: () => lowerQuality(), end: () => sharpenSoon(60) };

// Turns and zooms back to the whole-scan view.
export function flyHome(ms = 420) {
  const v = v3();
  if (!v) return;
  const now = pickCam(v.getCamera());
  v.setCamera(homeAim());
  v.resetCamera();
  const target = pickCam(v.getCamera());
  homeScale = target.parallelScale;
  v.setCamera(now);
  flyTo(target, ms, moveHooks);
}

// Turns to look at the scan from one side (a gizmo letter), keeping the zoom.
function flyToSide(axis, ms = 380) {
  flyTo({ viewPlaneNormal: axis, viewUp: axis[2] ? [0, -1, 0] : [0, 0, 1] }, ms, moveHooks);
}

// ───────────────────────── Looks ─────────────────────────

const blendOf = (name) => ({ composite: Enums.BlendModes.COMPOSITE, mip: Enums.BlendModes.MAXIMUM_INTENSITY_BLEND, mean: Enums.BlendModes.AVERAGE_INTENSITY_BLEND })[name];

function paint(actor, look, unit) {
  const m = core.meta;
  const lo = m.values.min - core.valueOffset;
  const hi = m.values.max - core.valueOffset;
  // Real units -> stored units, kept inside the stored range.
  const X = (x) => (x === -Infinity ? lo : x === Infinity ? hi : Math.min(hi - 1, Math.max(lo + 1, x - core.valueOffset)));
  const prop = actor.getProperty();
  const cfun = prop.getRGBTransferFunction(0);
  const ofun = prop.getScalarOpacity(0);
  cfun.removeAllPoints();
  ofun.removeAllPoints();
  prop.setUseGradientOpacity(0, false);
  actor.getMapper().setBlendMode(blendOf(look.blend));
  for (const [x, c] of look.color) cfun.addRGBPoint(X(x), c[0], c[1], c[2]);
  for (const [x, a] of look.alpha) ofun.addPoint(X(x), a);
  // Opacity is "per this much depth", the same for both copies, so the light
  // and the sharp picture look alike and a scan with coarse voxels is not foggy.
  prop.setScalarOpacityUnitDistance(0, unit);
  prop.setShade(look.shade);
  if (look.shade) {
    prop.setAmbient(0.22);
    prop.setDiffuse(0.82);
    prop.setSpecular(0.28);
    prop.setSpecularPower(18);
  }
}

export function apply3D(render = true) {
  if (!fastActor() || !core.meta) return;
  const look = buildLook(core.meta, state.view3d, solid);
  rampStart = look.rampStart;
  // "Smoothness": how deep a ray goes before the surface is solid, in voxels of the full scan.
  const soft = state.view3d.soft == null ? 40 : state.view3d.soft;
  const unit = Math.min(...core.meta.geometry.spacing) * (0.6 + (soft / 100) * 5.4);
  for (const a of [fastActor(), fineActor()]) if (a) paint(a, look, unit);
  // A mesh that turns fully opaque moves to vtk's opaque pass and the picture
  // jumps, so the first-open "solidify" fades the whole 3D picture instead.
  const meshSpecs = meshLook && solid < 1 ? buildLook(core.meta, state.view3d, 1).surfaces : look.surfaces;
  styleSurfaces(meshSpecs || [], meshLook && !!look.surfaces);
  const canvas = v3().getCanvas();
  if (canvas) canvas.style.opacity = meshLook && solid < 1 ? String(solid) : '';
  if (render && !is3dHidden()) v3().render();
}

// "Smooth" for meshes: rounds of smoothing of the grid before the surface is cut.
const smoothPasses = () => {
  const s = state.view3d.soft == null ? 40 : state.view3d.soft;
  return s < 15 ? 0 : s < 50 ? 1 : s < 85 ? 2 : 3;
};

// Makes the meshes on the view match the look: 'ok', 'stale' (a newer request
// took over) or 'failed'. A rebuild swaps under a snapshot that fades (`fade`).
async function syncSurfaces(look, fade) {
  const passes = smoothPasses();
  if (surfaceKey(look.surfaces, passes) === shownKey()) {
    keepPlaced(v3());
    return 'ok';
  }
  let built;
  try {
    built = await buildSurfaces(look.surfaces, passes);
  } catch (err) {
    console.warn('CBCT viewer: 3D surface', err);
    return 'failed';
  }
  if (!built) return 'stale';
  const now = buildLook(core.meta, state.view3d, solid);
  if (!v3() || !now.surfaces || surfaceKey(now.surfaces, smoothPasses()) !== built.key) {
    discardSurfaces(built);
    return 'stale';
  }
  const overlay = fade ? snapshot3dCanvas() : null;
  placeSurfaces(v3(), built);
  if (overlay) {
    // The new meshes are drawn by refresh3D right after this; fade once they are.
    nextFrames(2).then(() => fadeOutOverlay(overlay, 260));
  }
  return 'ok';
}

let rebuildTimer = null;
const rebuildSoon = (ms = 260) => {
  clearTimeout(rebuildTimer);
  rebuildTimer = setTimeout(() => refresh3D(), ms);
};

// The scan closes: free its meshes; the next scan starts ray-cast until its own are built.
export function close3d() {
  clearTimeout(rebuildTimer);
  dropSurfaces(v3());
  meshLook = false;
  const canvas = v3() && v3().getCanvas();
  if (canvas) canvas.style.opacity = '';
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
  lowerQuality(false);
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

// Each mapper always holds exactly this one plane: adding or removing a plane
// changes the vtk shader and freezes the view while it recompiles. "Off" parks
// the plane far below the volume, facing up, so it keeps everything.
export function applyCut(render = true) {
  const actors = [fastActor(), fineActor(), ...surfaceActors()].filter(Boolean);
  if (!actors.length) return;
  for (const actor of actors) {
    const mapper = actor.getMapper();
    const planes = mapper.getClippingPlanes();
    if (planes.length !== 1 || planes[0] !== cutPlane) {
      mapper.removeAllClippingPlanes();
      mapper.addClippingPlane(cutPlane);
    }
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
  if (render && !is3dHidden()) v3().render();
}

// Everything that has to be redone when the 3D view gets a new volume, a new
// sharper copy or a new look. With `cover` the work is hidden behind a snapshot
// of the view that fades away when the new picture is ready.
export async function refresh3D({ cover = true } = {}) {
  if (!fastActor()) return;
  const look = buildLook(core.meta, state.view3d, solid);
  if (look.surfaces) {
    // Surfaces: the old picture stays until the meshes are built, then fades.
    const result = await syncSurfaces(look, cover && !is3dHidden());
    if (result === 'stale') return;
    if (result === 'ok') {
      meshLook = true;
      apply3D(false);
      applyCut(false);
      presentStill();
      if (!is3dHidden()) v3().render();
      scheduleDraw();
      return;
    }
    // 'failed': draw this look by ray casting instead.
  }
  meshLook = false;
  const overlay = cover ? snapshot3dCanvas() : null;
  apply3D(false);
  applyCut(false);
  await calibrate();
  if (moving) presentMoving();
  else presentStill();
  if (!is3dHidden()) v3().render();
  scheduleDraw();
  if (overlay) fadeOutOverlay(overlay, 260);
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
  const items = AXES.map((a, i) => ({ ...a, i, x: 30 + dot(a.v, right) * 19, y: 30 - dot(a.v, cam.viewUp) * 19, depth: dot(a.v, cam.viewPlaneNormal) })).sort((p, q) => p.depth - q.depth);
  for (const it of items) {
    svg.append(svgEl('line', { x1: 30, y1: 30, x2: it.x, y2: it.y, stroke: it.c, 'stroke-width': 1.5, 'stroke-opacity': it.pos ? 1 : 0.55 }));
    // A letter is a button: the view turns to look from that side.
    svg.append(svgEl('circle', { cx: it.x, cy: it.y, r: 8, fill: it.pos ? it.c : '#141A24', stroke: it.c, 'stroke-width': it.pos ? 0 : 1, 'data-axis': it.i }));
    const t = svgEl('text', { x: it.x, y: it.y + 3.5, 'text-anchor': 'middle', 'font-size': 10, 'font-weight': 600, fill: it.pos ? '#0B0E14' : '#8C94A3', 'font-family': 'Geist, system-ui, sans-serif' });
    t.textContent = it.l;
    svg.append(t);
  }
}

// A plane through `point` with `normal`, cut by the box of the volume: a 3 to 6 sided polygon.
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
  const v = v3();
  if (!v || !core.geo || !frames) return;
  drawGizmo(v.getCamera());
  const svg = frames.threeD.svg;
  svg.replaceChildren();
  const c = (core.crosshair && core.crosshair.toolCenter) || centre();
  for (const id of MPR) {
    const n = vp(id).getCamera().viewPlaneNormal;
    const pts = planePolygon(c, n).map((p) => v.worldToCanvas(p));
    if (pts.length < 3) continue;
    svg.append(svgEl('polygon', { points: pts.map((p) => `${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(' '), fill: COLORS[id], 'fill-opacity': 0.05, stroke: COLORS[id], 'stroke-width': 1.25 }));
  }
  const p = v.worldToCanvas(c);
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
  const v = v3();
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

  // Light while the picture moves, sharp a moment after it stops.
  host.addEventListener(Enums.Events.IMAGE_RENDERED, () => {
    rendered = true;
  });
  measureDisplay();
  host.addEventListener('pointerdown', () => {
    cancelFlight();
    lowerQuality();
  }, true);
  smoothZoom(host, {
    begin: () => lowerQuality(),
    end: () => sharpenSoon(140),
    limits: () => {
      const home = homeScale || v3().getCamera().parallelScale;
      return [home * 0.03, home * 3];
    },
  });
  for (const id of MPR) {
    core.hosts[id].addEventListener('pointerdown', () => {
      if (state.view3d.cut !== 'off') lowerQuality(false);
    }, true);
  }
  window.addEventListener('pointerup', () => {
    if (moving) sharpenSoon(160);
  });
  frames.threeD.gizmoSvg.addEventListener('click', (e) => {
    const i = e.target && e.target.dataset ? e.target.dataset.axis : undefined;
    if (i !== undefined && core.volumeId) flyToSide(AXES[Number(i)].v);
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
  let lastPreset = state.view3d.preset;
  subscribe((s, changed) => {
    if (!core.volumeId) return;
    const nowHidden = is3dHidden();
    if (wasHidden && !nowHidden) {
      wasHidden = nowHidden;
      lastPreset = s.view3d.preset;
      refresh3D({ cover: false });
      return;
    }
    wasHidden = nowHidden;
    if (!changed.has('view3d')) return;
    if (s.view3d.preset !== lastPreset) {
      // A new look crossfades in (its shaders compile behind the old picture).
      lastPreset = s.view3d.preset;
      refresh3D();
    } else {
      // Sliders and the cut: light frames while they change, sharp after.
      lowerQuality(false);
      apply3D(false);
      applyCut();
      sharpenSoon(220);
      // Meshes: a new threshold or smoothing needs new meshes once the slider rests.
      if (meshLook) rebuildSoon();
    }
  });
}
