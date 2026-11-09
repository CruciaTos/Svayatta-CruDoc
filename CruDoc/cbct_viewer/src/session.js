// How a scan gets on screen without the doctor ever seeing a blank panel:
// poster pictures first, a small preview volume next, the full volume last,
// each swap hidden behind a snapshot that fades. Also saved view state,
// key-image snapshots and the page API Flutter calls.
import { core, IDS, MPR, vp, planeExtents } from './core.js';
import { state, set, subscribe, bus, presetWindow } from './state.js';
import { showVolume, freeEverything, fitCameras, captureView, restoreView, applyContrast, applySlab, resetAll } from './engine.js';
import { refresh3D, aim3d, solidify, prepareSolidify, snapshot3dCanvas, fadeOutOverlay } from './view3d.js';
import { initLod } from './lod.js';
import { scheduleUpdate } from './overlays.js';

const POSTER_FILE = { axial: 'poster_axial.png', coronal: 'poster_coronal.png', sagittal: 'poster_sagittal.png', threeD: 'poster_3d.png' };
const STAGGER_ORDER = ['axial', 'coronal', 'sagittal', 'threeD'];

let ui = null;
let post = () => {};
let engineReady = null;
let base = '';
let savedPosters = {};
let marks = {};
let t0 = 0;
let saveTimer = null;
let sessionOpen = false;

const nextFrames = (n = 2) => new Promise((resolve) => {
  const tick = () => (--n <= 0 ? resolve() : requestAnimationFrame(tick));
  requestAnimationFrame(tick);
});
const mark = (name) => (marks[name] = Math.round(performance.now() - t0));

async function fetchJson(name, optional = false) {
  const res = await fetch(base + name);
  if (!res.ok) {
    if (optional) return null;
    throw new Error(name === 'meta.json' ? 'The scan information is missing.' : `Could not read ${name}.`);
  }
  return res.json();
}

// Streams a volume file into one preallocated array, reporting progress.
async function fetchVoxels(file, dims, onProgress) {
  const expected = dims[0] * dims[1] * dims[2] * 2;
  const res = await fetch(base + file);
  if (!res.ok) throw new Error('The scan data is missing.');
  const total = Number(res.headers.get('content-length')) || expected;
  const out = new Uint8Array(expected);
  const reader = res.body.getReader();
  let got = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    if (got + value.length > out.length) throw new Error('The scan data is larger than expected.');
    out.set(value, got);
    got += value.length;
    if (onProgress) onProgress(got / total);
  }
  if (got !== expected) throw new Error('The scan data is incomplete.');
  return new Int16Array(out.buffer);
}

export async function loadLevel(entry) {
  if (core.voxels && (entry.file === 'full.i16' || entry.factor === 1)) {
    return { data: core.voxels, geo: geoOf(entry, core.meta) };
  }
  const geo = geoOf(entry, core.meta);
  const data = await fetchVoxels(entry.file, geo.dims, (f) => set({ progress: f }));
  set({ progress: null });
  return { data, geo };
}

const geoOf = (entry, meta) => ({
  dims: entry.dims || meta.geometry.dims,
  spacing: entry.spacing || meta.geometry.spacing,
  origin: entry.origin || meta.geometry.origin,
  direction: meta.geometry.direction,
});

// ───────────────────────── Open ─────────────────────────

export async function open(args) {
  t0 = performance.now();
  marks = { open: 0 };
  base = args.base;
  sessionOpen = true;
  const ms = args.reducedMotion ? 80 : 200;
  set({ deviceClass: args.deviceClass || 'pc', reduced: !!args.reducedMotion, phase: 'empty', progress: 'busy' });
  ui.setDisplay({ title: args.title || 'CBCT', chip: args.chip || '', badge: args.badge || '' });

  const [meta, saved] = await Promise.all([fetchJson('meta.json'), fetchJson('state.json', true)]);
  core.meta = meta;
  core.valueOffset = (meta.values && meta.values.valueOffset) || 0;
  ui.setMeta(meta);
  applySavedUi(saved, meta);
  savedPosters = (saved && saved.posters) || {};

  // Layer B: the prepared pictures, in the exact cells the live canvases will fill.
  for (const id of IDS) {
    const kind = id !== 'threeD' && !(savedPosters[id] && savedPosters[id].kind === 'canvas') ? 'plane' : 'canvas';
    ui.frames[id].setPoster(base + POSTER_FILE[id], kind, kind === 'plane' ? planeExtents(id, meta.geometry) : null);
  }
  ui.hideMessage();
  await ui.decodePosters();
  await nextFrames(2);
  set({ phase: 'poster' });
  mark('shown');
  post({ type: 'shown' });

  await engineReady;
  const first = args.firstOpen && !(saved && saved.cameras) && !args.reducedMotion;
  const preview = meta.volumes && meta.volumes.preview;
  const wantMid = args.deviceClass === 'tablet' && meta.volumes && meta.volumes.mid;
  const full = wantMid ? meta.volumes.mid : meta.volumes.full;
  // The 3D ray caster is the expensive part: it draws a smaller copy when the pack has one.
  const mid3d = !wantMid && meta.volumes && meta.volumes.mid;

  if (preview) {
    const data = await fetchVoxels(preview.file, geoOf(preview, meta).dims);
    await showVolume(data, geoOf(preview, meta), core.valueOffset);
    await applyEverything(saved, first);
    initLod(data, geoOf(preview, meta), meta);
    await revealLive(ms);
    if (first) solidify(500);
    set({ phase: 'preview' });
    mark('preview');
    post({ type: 'preview', ms: marks.preview });
  }

  const geoFull = geoOf(full, meta);
  const voxels = await fetchVoxels(full.file, geoFull.dims, (f) => set({ progress: f }));
  await swapToFull(voxels, geoFull, preview ? ms : 0, !preview, saved, first, true);
  set({ phase: 'full' });
  mark('full');
  post({ type: 'full', ms: marks.full });
  post({ type: 'timing', marks });
  setTimeout(() => set({ progress: null }), 300);
  wireAutosave();
}

// Restores the saved panel/tool state before the first live frame.
function applySavedUi(saved, meta) {
  const bone = presetWindow(meta, 'bone');
  const patch = { contrast: { ...(bone || {}), preset: 'bone', invert: false } };
  if (saved) {
    for (const k of ['layout', 'focus', 'panelOpen', 'tool', 'overlays']) if (saved[k] !== undefined) patch[k] = saved[k];
    if (saved.contrast) patch.contrast = { ...patch.contrast, ...saved.contrast };
    if (saved.slab) patch.slab = saved.slab;
    if (saved.view3d) patch.view3d = saved.view3d;
  }
  if (window.innerWidth < 1100 && !(saved && saved.panelOpen !== undefined)) patch.panelOpen = false;
  set(patch);
}

// Cameras, window, slab, 3D look: the live frame must equal the poster.
async function applyEverything(saved, first) {
  const restored = saved && saved.cameras && restoreView({ cameras: saved.cameras, centre: saved.centre });
  if (!restored) {
    fitCameras(true);
    if (first) prepareSolidify();
    else aim3d();
  }
  applyContrast(true);
  applySlab();
  refresh3D();
  core.engine.renderViewports(IDS);
  scheduleUpdate();
}

// Each poster fades out over its live canvas, all four together.
async function revealLive(ms) {
  await nextFrames(2);
  const dur = state.reduced ? 80 : (ms || 500);
  await Promise.all(IDS.map((id) => ui.frames[id].fadePoster(dur)));
}

// The focus pull: a snapshot of the preview sits on top while the full volume
// replaces it underneath, then fades away.
async function swapToFull(voxels, geo, hadPreview, onlyFull, saved, first, splitThreeD = false) {
  if (hadPreview === 0 || onlyFull) {
    await showVolume(voxels, geo, core.valueOffset);
    await applyEverything(saved, first);
    await revealLive(500);
    return;
  }
  const views = splitThreeD ? MPR : IDS; // the 3D view keeps its smaller copy
  const view = captureView();
  for (const id of views) {
    try {
      const url = vp(id).getCanvas().toDataURL('image/png');
      ui.frames[id].setPoster(url, 'canvas');
    } catch {
      /* no snapshot: the swap is simply direct */
    }
  }
  await showVolume(voxels, geo, core.valueOffset, views);
  core.engine.renderViewports(views);
  await nextFrames(2);
  restoreView(view);
  applyContrast(true);
  applySlab();
  refresh3D();
  core.engine.renderViewports(IDS);
  scheduleUpdate();
  await nextFrames(2);
  await Promise.all(views.map((id) => ui.frames[id].fadePoster(state.reduced ? 80 : 600)));
}

// Gives the 3D view its own, smaller volume and keeps its camera.
async function swap3d(entry, meta) {
  const geo = geoOf(entry, meta);
  const data = await fetchVoxels(entry.file, geo.dims);
  const overlay = snapshot3dCanvas();
  const cam = vp('threeD').getCamera();
  await showVolume(data, geo, core.valueOffset, ['threeD']);
  vp('threeD').setCamera({ viewUp: cam.viewUp, viewPlaneNormal: cam.viewPlaneNormal, position: cam.position, focalPoint: cam.focalPoint, parallelScale: cam.parallelScale });
  refresh3D();
  await fadeOutOverlay(overlay, 450);
}

// ───────────────────────── Saving ─────────────────────────

function snapshotState() {
  const { layout, focus, panelOpen, tool, overlays, contrast, slab, view3d } = state;
  const v = core.volumeId ? captureView() : { cameras: null, centre: null };
  return { version: 1, layout, focus, panelOpen, tool, overlays, contrast: { ...contrast }, slab: { ...slab }, view3d: { ...view3d }, cameras: v.cameras, centre: v.centre, posters: savedPosters, savedAt: new Date().toISOString() };
}

async function put(name, body) {
  try {
    const res = await fetch(base + name, { method: 'PUT', body });
    return res.ok;
  } catch {
    return false;
  }
}

async function saveState() {
  if (!sessionOpen || !core.volumeId) return false;
  return put('state.json', JSON.stringify(snapshotState()));
}

function wireAutosave() {
  const later = () => {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(saveState, 2000);
  };
  subscribe((s, changed) => {
    if (['layout', 'focus', 'panelOpen', 'tool', 'overlays', 'contrast', 'slab', 'view3d'].some((k) => changed.has(k))) later();
  });
}

const toBlob = (canvas) => new Promise((resolve) => canvas.toBlob(resolve, 'image/png'));

// Called before the viewer closes: fresh posters of what is on screen plus the state.
export async function prepareClose() {
  if (!sessionOpen || !core.volumeId) return;
  const work = (async () => {
    const posters = {};
    await Promise.all(IDS.map(async (id) => {
      const canvas = vp(id).getCanvas();
      // A view hidden by the single layout is only a few pixels wide: keep its older poster.
      if (!canvas || !canvas.width || core.hosts[id].clientWidth < 80 || core.hosts[id].clientHeight < 80) return;
      const blob = await toBlob(canvas);
      // Flutter reads the 3D view under the key "3d".
    if (blob && (await put(POSTER_FILE[id], blob))) posters[id === 'threeD' ? '3d' : id] = { kind: 'canvas', w: core.hosts[id].clientWidth, h: core.hosts[id].clientHeight };
    }));
    savedPosters = { ...savedPosters, ...posters };
    await saveState();
  })();
  await Promise.race([work, new Promise((resolve) => setTimeout(resolve, 300))]);
}

export function close() {
  sessionOpen = false;
  clearTimeout(saveTimer);
  freeEverything();
  set({ phase: 'empty', progress: null });
}

// ───────────────────────── Key-image snapshot ─────────────────────────

function drawSvgOnto(ctx, svg, w, h) {
  return new Promise((resolve) => {
    try {
      const clone = svg.cloneNode(true);
      clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
      clone.setAttribute('width', w);
      clone.setAttribute('height', h);
      const img = new Image();
      img.onload = () => {
        ctx.drawImage(img, 0, 0, ctx.canvas.width, ctx.canvas.height);
        resolve();
      };
      img.onerror = () => resolve();
      img.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(new XMLSerializer().serializeToString(clone))}`;
    } catch {
      resolve();
    }
  });
}

export async function takeSnapshot() {
  const id = state.active;
  const v = vp(id);
  if (!v || !core.volumeId) return;
  const canvas = v.getCanvas();
  const host = core.hosts[id];
  const out = document.createElement('canvas');
  out.width = canvas.width;
  out.height = canvas.height;
  const ctx = out.getContext('2d');
  ctx.drawImage(canvas, 0, 0);
  for (const svg of [host.querySelector('.svg-layer'), ui.frames[id].svg]) if (svg) await drawSvgOnto(ctx, svg, host.clientWidth, host.clientHeight);
  const blob = await toBlob(out);
  if (!blob) return;
  const name = `snap_${Date.now() % 1000000000}.png`;
  if (await put(name, blob)) {
    post({ type: 'snapshot', file: name, view: id });
    return;
  }
  // Outside the app (dev harness): offer the picture as a download.
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 4000);
}

// ───────────────────────── Install ─────────────────────────

export function installSession(userInterface, postFn, engineStarted) {
  ui = userInterface;
  post = postFn;
  engineReady = engineStarted;
  bus.on('reset', () => core.volumeId && resetAll());
  bus.on('snapshot', () => takeSnapshot());
  bus.on('close-request', async () => {
    await prepareClose();
    post({ type: 'close' });
  });
  window.CbctViewer = { open: (a) => open(a).catch(fail), prepareClose, close };
}

export function fail(err) {
  console.error(err);
  const text = err && err.message ? err.message : 'The 3D viewer could not start.';
  ui.message(text, true);
  post({ type: 'error', message: text });
}
