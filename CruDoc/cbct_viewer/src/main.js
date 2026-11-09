import './styles/tokens.css';
import './styles/viewer.css';
import { version } from '../package.json';
import {
  init as csInit,
  RenderingEngine,
  Enums,
  volumeLoader,
  setVolumesForViewports,
  eventTarget,
} from '@cornerstonejs/core';
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
} from '@cornerstonejs/tools';
import vtkPlane from '@kitware/vtk.js/Common/DataModel/Plane.js';

console.log('CBCT viewer booted');

// ───────────────────────── Flutter bridge (handler 'cbct') ─────────────────────────

const outbox = [];
let bridgeReady = !!(window.flutter_inappwebview && typeof window.flutter_inappwebview.callHandler === 'function');

function flushOutbox() {
  bridgeReady = true;
  while (outbox.length) send(outbox.shift());
}
function send(msg) {
  try {
    window.flutter_inappwebview.callHandler('cbct', msg);
  } catch (err) {
    console.warn('CBCT viewer: could not post', msg.type, err);
  }
}
function post(msg) {
  console.log('[cbct->flutter]', JSON.stringify(msg));
  if (bridgeReady) send(msg);
  else outbox.push(msg);
}
window.addEventListener('flutterInAppWebViewPlatformReady', flushOutbox, { once: true });
post({ type: 'boot', version });

// ───────────────────────── Page chrome ─────────────────────────

const params = new URLSearchParams(location.search);
const BASE = params.get('base') || '/dev/phantom/';

const ENGINE_ID = 'cbctEngine';
const VOLUME_ID = 'cbctVolume'; // no ':' (Cornerstone treats it as an image-loader scheme)
const MPR = ['axial', 'coronal', 'sagittal'];
const VIEWS = [
  { id: 'axial', name: 'Axial', dot: 'var(--axial)', hex: '#e9ae45', orientation: Enums.OrientationAxis.AXIAL },
  { id: 'threeD', name: '3D', dot: 'var(--text2)', hex: '#8c94a3' },
  { id: 'coronal', name: 'Coronal', dot: 'var(--coronal)', hex: '#2fc1ae', orientation: Enums.OrientationAxis.CORONAL },
  { id: 'sagittal', name: 'Sagittal', dot: 'var(--sagittal)', hex: '#a193ff', orientation: Enums.OrientationAxis.SAGITTAL },
];
const LINE_COLOR = Object.fromEntries(VIEWS.map((v) => [v.id, v.hex]));

const CONTRAST_CHIPS = [
  ['bone', 'Bone'],
  ['teeth', 'Teeth'],
  ['soft', 'Soft'],
  ['fineBone', 'Fine'],
  ['full', 'Full'],
];
const LAYOUT_CHIPS = [
  ['2x2', '2 × 2'],
  ['1col', '1 + 3'],
  ['single', '1'],
];
const VIEW3D_CHIPS = [
  ['bone', 'Bone'],
  ['teeth', 'Teeth'],
  ['xray', 'X-ray'],
  ['mip', 'MIP'],
];
const CUT_CHIPS = [
  ['off', 'Off'],
  ['axial', 'Axial'],
  ['coronal', 'Coronal'],
  ['sagittal', 'Sagittal'],
];

function el(tag, props = {}, ...kids) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k === 'class') node.className = v;
    else if (k === 'text') node.textContent = v;
    else if (k.startsWith('on')) node.addEventListener(k.slice(2), v);
    else node.setAttribute(k, v);
  }
  kids.flat().forEach((c) => c && node.append(c));
  return node;
}

const ui = { chips: {}, hosts: {}, pills: {} };

function chipGroup(caption, items, key, onPick) {
  const wrap = el('div', { class: 'group' }, caption ? el('span', { class: 'cap', text: caption }) : null);
  ui.chips[key] = {};
  for (const [id, label] of items) {
    const b = el('button', { class: 'chip', type: 'button', text: label, onclick: () => onPick(id) });
    ui.chips[key][id] = b;
    wrap.append(b);
  }
  return wrap;
}
function mark(key, active) {
  for (const [id, b] of Object.entries(ui.chips[key])) b.classList.toggle('on', id === active);
}

const app = document.getElementById('app');
const msg = el('div', { class: 'msg', text: 'Loading scan…' });
ui.w = el('input', { class: 'num', type: 'number', min: '1', step: '1', 'aria-label': 'Window width' });
ui.l = el('input', { class: 'num', type: 'number', step: '1', 'aria-label': 'Window level' });
ui.w.addEventListener('change', commitWindow);
ui.l.addEventListener('change', commitWindow);
ui.readout = el('span', { class: 'wl' }, 'W ', ui.w, ' L ', ui.l);
ui.invert = el('button', { class: 'chip', type: 'button', text: 'Invert', title: 'Invert the greyscale', onclick: () => toggleInvert() });
const contrastGroup = chipGroup('Contrast', CONTRAST_CHIPS, 'contrast', (id) => applyPreset(id));
contrastGroup.append(ui.invert);
ui.flip = el('button', { class: 'chip', type: 'button', text: '⇅', title: 'Flip the kept side', onclick: () => setCut(state.cut, !state.cutFlip) });

const bar = el(
  'header',
  { class: 'bar' },
  el('button', { class: 'back', type: 'button', text: '‹', 'aria-label': 'Back', title: 'Back (Esc)', onclick: () => post({ type: 'close' }) }),
  el('span', { class: 'title', text: params.get('title') || 'CBCT' }),
  el('span', { class: 'info', text: params.get('chip') || '' }),
  el('span', { class: 'spacer' }),
  contrastGroup,
  chipGroup('3D', VIEW3D_CHIPS, 'view3d', (id) => apply3D(id)),
  el('div', { class: 'group' }, el('span', { class: 'cap', text: 'Cut' }), ...cutButtons(), ui.flip),
  el('button', { class: 'reset', type: 'button', text: 'Reset', title: 'Reset (R)', onclick: () => resetAll() }),
);

function cutButtons() {
  ui.chips.cut = {};
  return CUT_CHIPS.map(([id, label]) => {
    const b = el('button', { class: 'chip', type: 'button', text: label, onclick: () => setCut(id, state.cutFlip) });
    ui.chips.cut[id] = b;
    return b;
  });
}

const grid = el('main', { class: 'grid' });
for (const v of VIEWS) {
  const host = el('div', { class: 'host', 'data-id': v.id });
  const pill = el('div', { class: 'pill', style: `--dot:${v.dot}` }, el('i'), el('span', { text: v.name }), el('small', { text: v.id === 'threeD' ? 'Bone' : '' }));
  ui.hosts[v.id] = host;
  ui.pills[v.id] = pill.querySelector('small');
  const buttons = el(
    'div',
    { class: 'vpbtns' },
    el('button', { class: 'vpbtn', type: 'button', text: '↺', title: 'Reset this view', onclick: () => resetView(v.id) }),
    el('button', { class: 'vpbtn', type: 'button', text: '⛶', title: 'Maximise or restore (F)', onclick: () => toggleSingle(v.id) }),
  );
  const section = el('section', { class: 'vp', 'data-id': v.id }, host, pill, buttons);
  section.addEventListener('mouseenter', () => (lastHovered = v.id));
  section.addEventListener('dblclick', () => toggleSingle(v.id));
  if (v.id === 'threeD') section.append(el('div', { class: 'hint', text: 'Drag to rotate · scroll to zoom' }));
  grid.append(section);
}

const status = el(
  'footer',
  { class: 'status' },
  ui.readout,
  el('div', { class: 'right' }, chipGroup('', LAYOUT_CHIPS, 'layout', (id) => setLayout(id, lastHovered)), el('span', { class: 'net', text: 'No network access' })),
);
const help = buildHelp();
app.append(bar, grid, status, msg, help);

function showMessage(text, isError = false) {
  msg.textContent = text;
  msg.classList.toggle('error', isError);
  msg.classList.remove('hidden');
}

// ───────────────────────── State ─────────────────────────

const state = { preset: 'bone', preset3d: 'bone', cut: 'off', cutFlip: false };
let meta = null;
let engine = null;
let toolGroupMpr = null;
let crosshair = null;
let v3 = null;
let valueOffset = 0;
let syncing = false;
const cutPlane = vtkPlane.newInstance();
const layout = { mode: '2x2', focus: 'axial' };
let lastHovered = 'axial';
let invert = false;
let resizePending = false;

// ───────────────────────── Loading ─────────────────────────

async function fetchMeta() {
  const res = await fetch(BASE + 'meta.json');
  if (!res.ok) throw new Error('The scan information is missing.');
  return res.json();
}

async function fetchVoxels(expectedBytes) {
  const res = await fetch(BASE + 'full.i16');
  if (!res.ok) throw new Error('The scan data is missing.');
  const total = Number(res.headers.get('content-length')) || expectedBytes;
  const out = new Uint8Array(expectedBytes);
  const reader = res.body.getReader();
  let got = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    if (got + value.length > out.length) throw new Error('The scan data is larger than expected.');
    out.set(value, got);
    got += value.length;
    msg.textContent = `Loading scan… ${Math.round((got / total) * 100)}%`;
  }
  if (got !== expectedBytes) throw new Error('The scan data is incomplete.');
  return new Int16Array(out.buffer);
}

async function start() {
  meta = await fetchMeta();
  const g = meta.geometry;
  valueOffset = (meta.values && meta.values.valueOffset) || 0;
  const [dx, dy, dz] = g.dims;
  const data = await fetchVoxels(dx * dy * dz * 2);

  await csInit({ rendering: { webGlContextCount: 1 } });
  toolsInit();
  [CrosshairsTool, StackScrollTool, ZoomTool, PanTool, WindowLevelTool, TrackballRotateTool].forEach((t) => addTool(t));

  engine = new RenderingEngine(ENGINE_ID);
  engine.setViewports(
    VIEWS.map((v) => ({
      viewportId: v.id,
      type: v.id === 'threeD' ? Enums.ViewportType.VOLUME_3D : Enums.ViewportType.ORTHOGRAPHIC,
      element: ui.hosts[v.id],
      defaultOptions:
        v.id === 'threeD'
          ? { background: [0.055, 0.086, 0.149] }
          : { orientation: v.orientation, background: [0, 0, 0] },
    })),
  );

  await volumeLoader.createLocalVolume(VOLUME_ID, {
    scalarData: data,
    dimensions: g.dims,
    spacing: g.spacing,
    origin: g.origin,
    direction: g.direction,
    metadata: {
      BitsAllocated: 16,
      BitsStored: 16,
      HighBit: 15,
      PixelRepresentation: 1,
      SamplesPerPixel: 1,
      PhotometricInterpretation: 'MONOCHROME2',
      FrameOfReferenceUID: 'cbct-frame',
      Modality: 'CT',
      Columns: dx,
      Rows: dy,
      ImageOrientationPatient: g.direction.slice(0, 6),
      PixelSpacing: [g.spacing[1], g.spacing[0]],
    },
  });
  await setVolumesForViewports(engine, [{ volumeId: VOLUME_ID }], VIEWS.map((v) => v.id));
  v3 = engine.getViewport('threeD');

  setupTools();
  MPR.forEach((id) => ui.hosts[id].addEventListener(Enums.Events.VOI_MODIFIED, onVoiModified));
  applyPreset('bone');
  apply3D('bone');
  setCut('off', false);
  aim3d();
  setLayout('2x2', 'axial');

  engine.renderViewports(VIEWS.map((v) => v.id));
  // Any layout change resizes a viewport element: refit the render canvases once per frame.
  const observer = new ResizeObserver(() => {
    if (resizePending) return;
    resizePending = true;
    requestAnimationFrame(() => {
      resizePending = false;
      engine.resize(true, true);
    });
  });
  Object.values(ui.hosts).forEach((h) => observer.observe(h));
  window.addEventListener('keydown', onKey);
  msg.classList.add('hidden');
  post({ type: 'full' });
}

// ───────────────────────── Tools ─────────────────────────

function setupTools() {
  const { Primary, Secondary, Auxiliary, Wheel } = ToolsEnums.MouseBindings;
  const { Ctrl } = ToolsEnums.KeyboardBindings;

  toolGroupMpr = ToolGroupManager.createToolGroup('cbctMpr');
  MPR.forEach((id) => toolGroupMpr.addViewport(id, ENGINE_ID));
  toolGroupMpr.addTool(CrosshairsTool.toolName, {
    getReferenceLineColor: (viewportId) => LINE_COLOR[viewportId],
    referenceLinesCenterGapRadius: 0,
    mobile: { enabled: false },
  });
  [StackScrollTool, ZoomTool, PanTool, WindowLevelTool].forEach((t) => toolGroupMpr.addTool(t.toolName));
  toolGroupMpr.setToolActive(CrosshairsTool.toolName, { bindings: [{ mouseButton: Primary }] });
  toolGroupMpr.setToolActive(StackScrollTool.toolName, { bindings: [{ mouseButton: Wheel }] });
  toolGroupMpr.setToolActive(ZoomTool.toolName, { bindings: [{ mouseButton: Wheel, modifierKey: Ctrl }] });
  toolGroupMpr.setToolActive(WindowLevelTool.toolName, { bindings: [{ mouseButton: Secondary }] });
  toolGroupMpr.setToolActive(PanTool.toolName, { bindings: [{ mouseButton: Auxiliary }] });
  crosshair = toolGroupMpr.getToolInstance(CrosshairsTool.toolName);

  const tg3d = ToolGroupManager.createToolGroup('cbct3d');
  tg3d.addViewport('threeD', ENGINE_ID);
  [TrackballRotateTool, ZoomTool, PanTool].forEach((t) => tg3d.addTool(t.toolName));
  tg3d.setToolActive(TrackballRotateTool.toolName, { bindings: [{ mouseButton: Primary }] });
  tg3d.setToolActive(ZoomTool.toolName, { bindings: [{ mouseButton: Wheel }] });
  tg3d.setToolActive(PanTool.toolName, { bindings: [{ mouseButton: Secondary }, { mouseButton: Auxiliary }] });

  eventTarget.addEventListener(ToolsEnums.Events.CROSSHAIR_TOOL_CENTER_CHANGED, (e) => {
    if (state.cut !== 'off') updateCutPlane(e.detail && e.detail.toolCenter);
  });
}

// ───────────────────────── Contrast (the three slice views) ─────────────────────────

function setVoi(low, high) {
  syncing = true;
  try {
    for (const id of MPR) {
      engine.getViewport(id).setProperties({ voiRange: { lower: low - valueOffset, upper: high - valueOffset } });
    }
    engine.renderViewports(MPR);
  } finally {
    syncing = false;
  }
  showWindow(low, high);
}

function applyPreset(key) {
  const p = meta.presets[key];
  if (!p) return;
  setVoi(p.low, p.high);
  mark('contrast', key);
}

// Window/level dragging changes only the dragged view: copy it to the others.
function onVoiModified(e) {
  if (syncing) return;
  const range = e.detail && e.detail.range;
  if (!range) return;
  syncing = true;
  try {
    for (const id of MPR) {
      if (id === e.detail.viewportId) continue;
      engine.getViewport(id).setProperties({ voiRange: range });
    }
    engine.renderViewports(MPR);
  } finally {
    syncing = false;
  }
  const low = range.lower + valueOffset;
  const high = range.upper + valueOffset;
  showWindow(low, high);
  markMatch(low, high);
}

// Highlights the preset chip the window equals, or none.
function markMatch(low, high) {
  const tol = (meta.values.max - meta.values.min) * 0.005;
  const match = Object.entries(meta.presets).find(([, p]) => Math.abs(p.low - low) < tol && Math.abs(p.high - high) < tol);
  mark('contrast', match ? match[0] : null);
}

function showWindow(low, high) {
  ui.w.value = Math.round(high - low);
  ui.l.value = Math.round((low + high) / 2);
}

// The Width and Level boxes: typing a value and pressing Enter (or leaving the box) applies it.
function commitWindow() {
  const w = Math.max(1, Number(ui.w.value));
  const l = Number(ui.l.value);
  if (!Number.isFinite(w) || !Number.isFinite(l)) return;
  setVoi(l - w / 2, l + w / 2);
  markMatch(l - w / 2, l + w / 2);
}

function toggleInvert() {
  invert = !invert;
  MPR.forEach((id) => engine.getViewport(id).setProperties({ invert }));
  engine.renderViewports(MPR);
  ui.invert.classList.toggle('on', invert);
}

// ───────────────────────── 3D look ─────────────────────────

const IVORY_LOW = [0.784, 0.706, 0.549]; // #C8B48C
const IVORY = [0.925, 0.882, 0.788]; // #ECE1C9
const IVORY_TEETH = [0.953, 0.933, 0.894]; // #F3EEE4

function apply3D(kind) {
  state.preset3d = kind;
  mark('view3d', kind);
  const actor = v3 && v3.getDefaultActor() && v3.getDefaultActor().actor;
  if (!actor) return;
  const prop = actor.getProperty();
  const mapper = actor.getMapper();
  const cfun = prop.getRGBTransferFunction(0);
  const ofun = prop.getScalarOpacity(0);
  const L = meta.landmarks;
  const S = (v) => v - valueOffset;
  const lo = S(meta.values.min);
  const hi = S(meta.values.max);
  const d = 0.08 * (L.teeth - L.soft);

  cfun.removeAllPoints();
  ofun.removeAllPoints();
  prop.setUseGradientOpacity(0, false);

  if (kind === 'xray' || kind === 'mip') {
    mapper.setBlendMode(kind === 'xray' ? Enums.BlendModes.AVERAGE_INTENSITY_BLEND : Enums.BlendModes.MAXIMUM_INTENSITY_BLEND);
    cfun.addRGBPoint(lo, 0, 0, 0);
    cfun.addRGBPoint(S(L.soft), 0, 0, 0);
    cfun.addRGBPoint(S(L.teeth), 1, 1, 1);
    cfun.addRGBPoint(hi, 1, 1, 1);
    ofun.addPoint(lo, 1);
    ofun.addPoint(hi, 1);
    prop.setShade(false);
  } else {
    mapper.setBlendMode(Enums.BlendModes.COMPOSITE);
    const teethOnly = kind === 'teeth';
    const start = teethOnly ? L.teeth - 2 * d : L.bone - d;
    const full = teethOnly ? L.teeth : L.bone + d;
    const colourLow = teethOnly ? IVORY_TEETH : IVORY_LOW;
    const colourHigh = teethOnly ? IVORY_TEETH : IVORY;
    cfun.addRGBPoint(lo, ...colourLow);
    cfun.addRGBPoint(S(start), ...colourLow);
    cfun.addRGBPoint(S(L.teeth), ...colourHigh);
    cfun.addRGBPoint(hi, ...colourHigh);
    ofun.addPoint(lo, 0);
    ofun.addPoint(S(start), 0);
    ofun.addPoint(S(full), 0.85);
    ofun.addPoint(hi, 0.85);
    prop.setShade(true);
    prop.setAmbient(0.2);
    prop.setDiffuse(0.85);
    prop.setSpecular(0.25);
    prop.setSpecularPower(12);
  }
  v3.render();
  updatePill();
}

// Anterior view turned 30° toward the patient's right and raised 20° (LPS: +x Left, +y Posterior, +z Superior).
function aim3d() {
  const az = (30 * Math.PI) / 180;
  const el = (20 * Math.PI) / 180;
  const n = [-Math.sin(az) * Math.cos(el), -Math.cos(az) * Math.cos(el), Math.sin(el)];
  const k = n[2]; // up = z minus its part along n
  const up = [-k * n[0], -k * n[1], 1 - k * n[2]];
  const len = Math.hypot(...up);
  v3.setCamera({ viewPlaneNormal: n, viewUp: up.map((x) => x / len) });
  v3.resetCamera();
  v3.render();
}

// ───────────────────────── Cut at crosshair ─────────────────────────

// The kept side is the side the normal points to: keep inferior, posterior, left.
const CUT_NORMAL = { axial: [0, 0, -1], coronal: [0, 1, 0], sagittal: [1, 0, 0] };

function updateCutPlane(centre) {
  const mapper = v3.getDefaultActor().actor.getMapper();
  mapper.removeAllClippingPlanes();
  if (state.cut === 'off') return;
  const c = centre || (crosshair && crosshair.toolCenter);
  if (!c) return;
  const sign = state.cutFlip ? -1 : 1;
  cutPlane.setNormal(...CUT_NORMAL[state.cut].map((x) => x * sign));
  cutPlane.setOrigin(...c);
  mapper.addClippingPlane(cutPlane);
  v3.render();
}

function setCut(cut, flip) {
  state.cut = cut;
  state.cutFlip = flip;
  mark('cut', cut);
  ui.flip.classList.toggle('on', flip);
  updateCutPlane();
  if (cut === 'off') v3.render();
  updatePill();
}

function updatePill() {
  const name = { bone: 'Bone', teeth: 'Teeth', xray: 'X-ray', mip: 'MIP' }[state.preset3d];
  ui.pills.threeD.textContent = state.cut === 'off' ? name : `${name} · cut ${state.cut}`;
}

// ───────────────────────── Reset and keys ─────────────────────────

function resetAll() {
  MPR.forEach((id) => engine.getViewport(id).resetCamera());
  if (crosshair && crosshair.resetCrosshairs) crosshair.resetCrosshairs();
  if (invert) toggleInvert();
  applyPreset('bone');
  apply3D('bone');
  setCut('off', false);
  aim3d();
  engine.renderViewports(VIEWS.map((v) => v.id));
}

// ───────────────────────── Layouts, help, overlays ─────────────────────────

function setLayout(mode, focus) {
  layout.mode = mode;
  layout.focus = focus || layout.focus;
  grid.dataset.layout = mode;
  for (const s of grid.querySelectorAll('.vp')) s.classList.toggle('focus', s.dataset.id === layout.focus);
  mark('layout', mode);
}

// One viewport fills the grid; again restores 2 × 2.
function toggleSingle(id) {
  if (layout.mode === 'single' && layout.focus === id) setLayout('2x2', id);
  else setLayout('single', id);
}

function resetView(id) {
  if (id === 'threeD') aim3d();
  else {
    engine.getViewport(id).resetCamera();
    engine.renderViewports([id]);
  }
}

function buildHelp() {
  const rows = [
    ['1 – 5', 'Contrast presets'],
    ['R', 'Reset views, window, cut and invert'],
    ['H', 'Hide or show lines and labels'],
    ['F', 'Maximise the hovered view'],
    ['?', 'This sheet'],
    ['Esc', 'Close this sheet, or leave the maximised view'],
    ['Left-drag', 'Move the crosshair (3D: rotate)'],
    ['Wheel', 'Scroll slices (3D: zoom)'],
    ['Right-drag', 'Window and level'],
    ['Middle-drag', 'Pan'],
    ['Ctrl + wheel', 'Zoom'],
    ['Double-click', 'Maximise or restore a view'],
  ];
  const sheet = el('div', { class: 'sheet' }, el('h2', { text: 'Shortcuts' }), ...rows.map(([k, d]) => el('div', { class: 'row' }, el('kbd', { text: k }), el('span', { text: d }))));
  const node = el('div', { class: 'help', onclick: (e) => e.target === node && toggleHelp(false) }, sheet);
  return node;
}

function toggleHelp(open) {
  help.classList.toggle('open', open ?? !help.classList.contains('open'));
}

function onKey(e) {
  if (e.ctrlKey || e.metaKey || e.altKey) return;
  if (e.target instanceof HTMLInputElement) {
    if (e.key === 'Enter') e.target.blur();
    return;
  }
  const key = e.key.toLowerCase();
  const preset = CONTRAST_CHIPS[Number(key) - 1];
  if (preset) applyPreset(preset[0]);
  else if (key === 'r') resetAll();
  else if (key === 'h') app.classList.toggle('no-overlay');
  else if (key === 'f') toggleSingle(lastHovered);
  else if (key === '?') toggleHelp();
  else if (key === 'escape') {
    // Close the sheet, then leave a maximised view; the back button closes the viewer.
    if (help.classList.contains('open')) toggleHelp(false);
    else if (layout.mode !== '2x2') setLayout('2x2');
  }
}

// ───────────────────────── Go ─────────────────────────

start().catch((err) => {
  console.error(err);
  const text = err && err.message ? err.message : 'The 3D viewer could not start.';
  showMessage(text, true);
  post({ type: 'error', message: text });
});
