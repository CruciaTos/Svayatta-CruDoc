// Cornerstone3D: rendering engine, the four viewports, the volume on screen,
// tools, and applying the store's contrast / slab / tool to the images.
import { init as csInit, RenderingEngine, Enums, volumeLoader, setVolumesForViewports, cache, eventTarget } from '@cornerstonejs/core';
import {
  init as toolsInit,
  Enums as ToolsEnums,
  addTool,
  ToolGroupManager,
  CrosshairsTool,
  StackScrollTool,
  ZoomTool,
  PanTool,
  WindowLevelTool,
  TrackballRotateTool,
  LengthTool,
  AngleTool,
  EllipticalROITool,
  annotation,
} from '@cornerstonejs/tools';
import { core, IDS, MPR, ENGINE_ID, vp, axes, dot, mul, add, sub, centre, worldToIndex, planeExtents } from './core.js';
import { state, set, subscribe, bus, matchPreset } from './state.js';
import { fitCamera } from './fit.js';
import { flyHome } from './view3d.js';
import { validPreset } from './presets3d.js';

const MB = ToolsEnums.MouseBindings;
const KB = ToolsEnums.KeyboardBindings;

// Straight display cameras (guide A3.8; matches Cornerstone's MPR constants).
const STRAIGHT = {
  axial: { viewPlaneNormal: [0, 0, -1], viewUp: [0, -1, 0] },
  coronal: { viewPlaneNormal: [0, -1, 0], viewUp: [0, 0, 1] },
  sagittal: { viewPlaneNormal: [1, 0, 0], viewUp: [0, 0, 1] },
};

let volCounter = 0;
let syncing = false;
let userDragging = false; // only a drag in a slice view changes the window; Cornerstone's own initial VOI events are ignored
let appliedContrast = '';
let lastTool = null;

// ───────────────────────── Start-up ─────────────────────────

export async function initEngine(hosts) {
  await csInit({ rendering: { webGlContextCount: 1 } });
  toolsInit();
  [CrosshairsTool, StackScrollTool, ZoomTool, PanTool, WindowLevelTool, TrackballRotateTool, LengthTool, AngleTool, EllipticalROITool].forEach((t) => addTool(t));
  core.hosts = hosts;
  core.engine = new RenderingEngine(ENGINE_ID);
  core.engine.setViewports(
    IDS.map((id) => ({
      viewportId: id,
      type: id === 'threeD' ? Enums.ViewportType.VOLUME_3D : Enums.ViewportType.ORTHOGRAPHIC,
      element: hosts[id],
      defaultOptions: id === 'threeD' ? { background: [0.055, 0.086, 0.149] } : { orientation: Enums.OrientationAxis[id.toUpperCase()], background: [0, 0, 0] },
    })),
  );

  // Any layout change resizes a viewport element: refit the render canvases once per frame.
  let pending = false;
  const observer = new ResizeObserver(() => {
    if (pending) return;
    pending = true;
    requestAnimationFrame(() => {
      pending = false;
      core.engine.resize(true, true);
    });
  });
  Object.values(hosts).forEach((h) => {
    observer.observe(h);
    h.addEventListener('contextmenu', (e) => e.preventDefault());
  });
  MPR.forEach((id) => {
    hosts[id].addEventListener('wheel', (e) => {
      if (!e.shiftKey) return;
      e.preventDefault();
      e.stopImmediatePropagation();
      scrollView(id, e.deltaY < 0 ? 10 : -10);
    }, { capture: true, passive: false });
    hosts[id].addEventListener(Enums.Events.VOI_MODIFIED, onVoiModified);
    hosts[id].addEventListener('pointerdown', () => (userDragging = true), true);
  });
  window.addEventListener('pointerup', () => setTimeout(() => (userDragging = false), 80));
  hosts.threeD.addEventListener('dblclick', (e) => e.stopPropagation());

  subscribe((s, changed) => {
    if (!core.volumeId) return;
    if (changed.has('contrast')) applyContrast();
    if (changed.has('slab')) applySlab();
    if (changed.has('tool')) refreshTools();
  });
  bus.on('scroll', ({ id, delta }) => scrollView(id, delta));
  bus.on('viewport-reset', ({ id }) => resetView(id));
}

// ───────────────────────── Volumes ─────────────────────────

// Volumes on screen. The slice views hold one (`mpr`). The 3D view holds a light
// copy that is always there (`fast`, drawn while the picture moves) and, when
// the zoom calls for it, a sharper one (`fine`, drawn when the picture is still).
// `fine` may be the slice views' own volume: the GPU texture is shared, so it
// costs no extra memory.
const held = { mpr: null, fast: null, fine: null };
export const FINE_UID = 'cbctFine';

async function makeVolume(voxels, geo) {
  const [nx, ny] = geo.dims;
  const id = `cbctVol${++volCounter}`;
  await volumeLoader.createLocalVolume(id, {
    scalarData: voxels,
    dimensions: geo.dims,
    spacing: geo.spacing,
    origin: geo.origin,
    direction: geo.direction,
    metadata: {
      BitsAllocated: 16,
      BitsStored: 16,
      HighBit: 15,
      PixelRepresentation: 1,
      SamplesPerPixel: 1,
      PhotometricInterpretation: 'MONOCHROME2',
      FrameOfReferenceUID: 'cbct-frame',
      Modality: 'CT',
      Columns: nx,
      Rows: ny,
      ImageOrientationPatient: geo.direction.slice(0, 6),
      PixelSpacing: [geo.spacing[1], geo.spacing[0]],
    },
  });
  return id;
}

// Frees every volume no view holds any more.
function sweep(before) {
  const keep = new Set([held.mpr, held.fast, held.fine]);
  for (const id of before) if (id && !keep.has(id)) removeVolume(id);
}

// Puts a volume on the listed viewports (all four by default). In the 3D view
// it becomes the light copy and any sharper one is dropped.
// Cameras are reset by Cornerstone: the caller restores or refits them.
export async function showVolume(voxels, geo, valueOffset, views = IDS) {
  const before = [held.mpr, held.fast, held.fine];
  const slices = views.includes('axial');
  // A sharper 3D copy that borrows the slice views' volume goes with it.
  if (slices && held.fine && held.fine === held.mpr && !views.includes('threeD')) dropFine();
  const id = await makeVolume(voxels, geo);
  await setVolumesForViewports(core.engine, [{ volumeId: id }], views);
  if (slices) {
    held.mpr = id;
    core.volumeId = id;
    core.voxels = voxels;
    core.geo = geo;
    core.valueOffset = valueOffset;
    appliedContrast = '';
  }
  if (views.includes('threeD')) {
    held.fast = id;
    held.fine = null;
  }
  sweep(before);
  if (!core.tgMpr && slices) setupTools();
  logVolumeMemory(`volume shown on [${views.join(',')}]`);
}

function dropFine() {
  const v = vp('threeD');
  if (v && v.getActor(FINE_UID)) v.removeVolumeActors([FINE_UID]);
  held.fine = null;
}

// Gives the 3D view its sharper copy, hidden until view3d.js shows it.
// `level` is { data, geo } for a copy of its own, 'slices' to borrow the slice
// views' volume, or null for none. The camera is left exactly as it was.
export async function setFine3d(level) {
  const v = vp('threeD');
  if (!v) return;
  const before = [held.mpr, held.fast, held.fine];
  const c = v.getCamera();
  const cam = { viewUp: c.viewUp, viewPlaneNormal: c.viewPlaneNormal, position: c.position, focalPoint: c.focalPoint, parallelScale: c.parallelScale };
  dropFine();
  if (level) {
    const id = level === 'slices' ? held.mpr : await makeVolume(level.data, level.geo);
    await v.addVolumes([{ volumeId: id, actorUID: FINE_UID, visibility: false }], false, true);
    held.fine = id;
    v.setCamera(cam);
  }
  sweep(before);
  logVolumeMemory(`3D sharp copy: ${level ? (level === 'slices' ? 'slice volume' : level.geo.dims.join('x')) : 'none'}`);
}

export function logVolumeMemory(label = '') {
  try {
    const cacheSize = cache.getCacheSize();
    const vols = [];
    if (held.mpr) {
      const v = cache.getVolume(held.mpr);
      if (v) vols.push(`mpr ${held.mpr} (${v.dimensions.join('x')}: ${v.dimensions.reduce((a, b) => a * b, 1) * 2} B)`);
    }
    for (const k of ['fast', 'fine']) {
      const v = held[k] && held[k] !== held.mpr && cache.getVolume(held[k]);
      if (v) vols.push(`3D ${k} ${held[k]} (${v.dimensions.join('x')}: ${v.dimensions.reduce((a, b) => a * b, 1) * 2} B)`);
    }
    if (held.fine && held.fine === held.mpr) vols.push('3D fine = mpr (shared)');
    console.log(`[cbct memory] ${label ? label + ': ' : ''}cacheSize: ${cacheSize} bytes | ${vols.join(', ')}`);
  } catch (err) {
    console.warn('[cbct memory]', err);
  }
}

function removeVolume(id) {
  try {
    const volume = cache.getVolume(id);
    const imageIds = (volume && volume.imageIds) || [];
    cache.removeVolumeLoadObject(id);
    imageIds.forEach((i) => {
      try {
        cache.removeImageLoadObject(i);
      } catch {
        /* already gone */
      }
    });
    logVolumeMemory(`freed volume ${id}`);
  } catch (err) {
    console.warn('CBCT viewer: could not free a volume', err);
  }
}

export function freeEverything() {
  for (const id of new Set([held.mpr, held.fast, held.fine])) if (id) removeVolume(id);
  held.mpr = null;
  held.fast = null;
  held.fine = null;
  core.volumeId = null;
  core.voxels = null;
}

// ───────────────────────── Tools ─────────────────────────

function setupTools() {
  const g = ToolGroupManager.createToolGroup('cbctMpr') || ToolGroupManager.getToolGroup('cbctMpr');
  MPR.forEach((id) => g.addViewport(id, ENGINE_ID));
  g.addTool(CrosshairsTool.toolName, {
    getReferenceLineColor: (viewportId) => ({ axial: '#e9ae45', coronal: '#2fc1ae', sagittal: '#a193ff' })[viewportId],
    referenceLinesCenterGapRadius: 0,
    mobile: { enabled: false },
  });
  [StackScrollTool, ZoomTool, PanTool, WindowLevelTool, LengthTool, AngleTool, EllipticalROITool].forEach((t) => g.addTool(t.toolName));
  core.tgMpr = g;
  core.crosshair = g.getToolInstance(CrosshairsTool.toolName);

  const g3 = ToolGroupManager.createToolGroup('cbct3d') || ToolGroupManager.getToolGroup('cbct3d');
  g3.addViewport('threeD', ENGINE_ID);
  // view3d.js alone decides the quality while the picture moves, so the rotate
  // tool's own "fewer samples while dragging" is switched off (factor 1).
  g3.addTool(TrackballRotateTool.toolName, { rotateSampleDistanceFactor: 1 });
  [ZoomTool, PanTool].forEach((t) => g3.addTool(t.toolName));
  g3.setToolActive(TrackballRotateTool.toolName, { bindings: [{ mouseButton: MB.Primary }] });
  g3.setToolActive(ZoomTool.toolName, { bindings: [{ mouseButton: MB.Wheel }] });
  g3.setToolActive(PanTool.toolName, { bindings: [{ mouseButton: MB.Secondary }, { mouseButton: MB.Auxiliary }] });
  core.tg3d = g3;

  try {
    // setDefaultToolStyles replaces Cornerstone's defaults, so the flags we do
    // not override (text box visibility) must be restated or the number vanishes.
    annotation.config.style.setDefaultToolStyles({
      global: {
        textBoxVisibility: true,
        color: 'rgb(231,234,240)',
        colorHighlighted: 'rgb(77,142,247)',
        colorSelected: 'rgb(77,142,247)',
        lineWidth: '1.5',
        textBoxFontFamily: 'Geist Mono, Consolas, monospace',
        textBoxFontSize: '11px',
        textBoxColor: 'rgb(231,234,240)',
        textBoxBackground: 'rgba(0,0,0,0.72)',
        textBoxLinkLineColor: 'rgb(77,142,247)',
        showHandlesAlways: true,
      },
    });
  } catch (err) {
    console.warn('CBCT viewer: could not style measurements', err);
  }
  lastTool = null;
  refreshTools();
}

// The left button runs the toolbar's tool; right = window/level, middle = pan,
// Ctrl+wheel = zoom, wheel = scroll slices. Tools that are not selected stay
// passive so existing measurements keep showing.
export function refreshTools() {
  const g = core.tgMpr;
  if (!g) return;
  const tool = state.tool;
  const plans = [
    [PanTool, [{ mouseButton: MB.Auxiliary }], tool === 'pan'],
    [ZoomTool, [{ mouseButton: MB.Wheel, modifierKey: KB.Ctrl }], tool === 'zoom'],
    [WindowLevelTool, [{ mouseButton: MB.Secondary }], tool === 'wl'],
    [LengthTool, [], tool === 'length'],
    [AngleTool, [], tool === 'angle'],
    [EllipticalROITool, [], tool === 'ellipse'],
  ];
  for (const [Tool, extra, primary] of plans) {
    const bindings = [...extra, ...(primary ? [{ mouseButton: MB.Primary }] : [])];
    if (bindings.length) g.setToolActive(Tool.toolName, { bindings });
    else g.setToolPassive(Tool.toolName);
  }
  g.setToolActive(StackScrollTool.toolName, { bindings: [{ mouseButton: MB.Wheel }] });
  // The crosshair tool re-centres itself when activated: keep its centre.
  if (tool === 'crosshair') {
    if (lastTool !== 'crosshair') {
      const keep = core.crosshair && core.crosshair.toolCenter && [...core.crosshair.toolCenter];
      g.setToolActive(CrosshairsTool.toolName, { bindings: [{ mouseButton: MB.Primary }] });
      if (keep && lastTool) core.crosshair.setToolCenter(keep);
    }
  } else if (lastTool === 'crosshair' || lastTool === null) {
    g.setToolPassive(CrosshairsTool.toolName);
  }
  lastTool = tool;
}

// ───────────────────────── Contrast / slab ─────────────────────────

export function applyContrast(force = false) {
  if (!core.engine || !core.volumeId) return;
  const { low, high, invert } = state.contrast;
  const off = core.valueOffset;
  const sig = `${low}|${high}|${invert}|${off}|${core.volumeId}`;
  if (!force && sig === appliedContrast) return;
  appliedContrast = sig;
  syncing = true;
  try {
    for (const id of MPR) vp(id).setProperties({ voiRange: { lower: low - off, upper: high - off }, invert });
  } finally {
    syncing = false;
  }
  core.engine.renderViewports(MPR);
}

// Window/level dragging changes only the dragged view: copy it to the others.
function onVoiModified(e) {
  if (syncing || !core.volumeId || !userDragging) return;
  const range = e.detail && e.detail.range;
  if (!range) return;
  const off = core.valueOffset;
  const low = range.lower + off;
  const high = range.upper + off;
  const cur = state.contrast;
  if (Math.abs(low - cur.low) < 0.01 && Math.abs(high - cur.high) < 0.01) return;
  syncing = true;
  try {
    for (const id of MPR) if (id !== e.detail.viewportId) vp(id).setProperties({ voiRange: range });
  } finally {
    syncing = false;
  }
  core.engine.renderViewports(MPR);
  appliedContrast = `${low}|${high}|${cur.invert}|${off}|${core.volumeId}`;
  set({ contrast: { low, high, preset: matchPreset(core.meta, low, high) } });
}

export function applySlab() {
  if (!core.engine || !core.volumeId) return;
  const { mode, thickness } = state.slab;
  const M = Enums.BlendModes;
  const blend = { thin: M.COMPOSITE, mip: M.MAXIMUM_INTENSITY_BLEND, mean: M.AVERAGE_INTENSITY_BLEND, minip: M.MINIMUM_INTENSITY_BLEND }[mode];
  for (const id of MPR) {
    try {
      const v = vp(id);
      v.setBlendMode(blend);
      v.setSlabThickness(thickness / 2); // Cornerstone's thickness is the half thickness
    } catch (err) {
      console.warn('CBCT viewer: slab', err);
    }
  }
  try {
    core.tgMpr.setToolConfiguration(CrosshairsTool.toolName, { slabThicknessBlendMode: blend });
  } catch {
    /* optional */
  }
  core.engine.renderViewports(MPR);
}

// ───────────────────────── Cameras ─────────────────────────

// Fits every slice view to its viewport (our own fit rule, never resetCamera),
// centred on the volume; straight orientation when `straight` is set.
export function fitCameras(straight = true) {
  if (!core.geo) return;
  const c = centre();
  for (const id of MPR) {
    const v = vp(id);
    const host = core.hosts[id];
    const cam = v.getCamera();
    const base = straight ? STRAIGHT[id] : { viewPlaneNormal: cam.viewPlaneNormal, viewUp: cam.viewUp };
    const [u, w] = planeExtents(id);
    const f = fitCamera(host.clientWidth || 1, host.clientHeight || 1, u, w);
    const dist = Math.hypot(...sub(cam.position, cam.focalPoint)) || Math.max(...core.geo.dims.map((d, i) => d * core.geo.spacing[i]));
    v.setCamera({ ...base, focalPoint: c, position: add(c, mul(base.viewPlaneNormal, dist)), parallelScale: f.parallelScale });
    core.fit[id] = f;
  }
  if (core.crosshair && core.crosshair.setToolCenter) {
    try {
      core.crosshair.setToolCenter(c);
    } catch {
      /* the tool has not been activated yet */
    }
  }
}

export function captureView() {
  const cameras = {};
  for (const id of IDS) {
    const c = vp(id).getCamera();
    cameras[id] = { viewUp: c.viewUp, viewPlaneNormal: c.viewPlaneNormal, position: c.position, focalPoint: c.focalPoint, parallelScale: c.parallelScale };
  }
  const centreNow = core.crosshair && core.crosshair.toolCenter ? [...core.crosshair.toolCenter] : null;
  return { cameras, centre: centreNow };
}

export function restoreView(saved) {
  if (!saved || !saved.cameras) return false;
  try {
    for (const id of IDS) if (saved.cameras[id]) vp(id).setCamera(saved.cameras[id]);
    if (saved.centre && core.crosshair) core.crosshair.setToolCenter(saved.centre);
    return true;
  } catch (err) {
    console.warn('CBCT viewer: could not restore the view', err);
    return false;
  }
}

// ───────────────────────── Scrolling and resets ─────────────────────────

export function scrollView(id, delta) {
  const v = vp(id);
  if (!v || id === 'threeD' || !core.geo) return;
  const cam = v.getCamera();
  const n = cam.viewPlaneNormal;
  const a = axes();
  const comps = [dot(n, a.x), dot(n, a.y), dot(n, a.z)];
  const k = comps.map(Math.abs).indexOf(Math.max(...comps.map(Math.abs)));
  const along = Math.sign(comps[k]) || 1;
  const move = mul(n, along * delta * core.geo.spacing[k]); // positive delta = higher slice index
  const idx = worldToIndex(add(cam.focalPoint, move))[k];
  if (idx < -0.5 || idx > core.geo.dims[k] - 0.5) return;
  v.setCamera({ focalPoint: add(cam.focalPoint, move), position: add(cam.position, move) });
  v.render();
}

export function resetView(id) {
  if (id === 'threeD') {
    flyHome();
    return;
  }
  const v = vp(id);
  const c = centre();
  const [u, w] = planeExtents(id);
  const host = core.hosts[id];
  const f = fitCamera(host.clientWidth || 1, host.clientHeight || 1, u, w);
  const dist = Math.hypot(...sub(v.getCamera().position, v.getCamera().focalPoint)) || 100;
  v.setCamera({ ...STRAIGHT[id], focalPoint: c, position: add(c, mul(STRAIGHT[id].viewPlaneNormal, dist)), parallelScale: f.parallelScale });
  core.fit[id] = f;
  if (core.crosshair) core.crosshair.setToolCenter(c);
  core.engine.renderViewports(MPR);
}

export function resetAll() {
  fitCameras(true);
  flyHome();
  set({
    contrast: { ...(core.meta ? { low: core.meta.presets.bone.low, high: core.meta.presets.bone.high } : {}), preset: 'bone', invert: false },
    slab: { mode: 'thin', thickness: 0 },
    view3d: { preset: validPreset(core.meta, 'bone'), threshold: 0, opacity: 100, soft: 40, cut: 'off', cutFlip: false },
  });
  core.engine.renderViewports(MPR);
}

export { eventTarget, Enums, ToolsEnums, annotation };
