// All the HTML: top bar, viewport frames, right panel, status bar, help sheet.
// It reads and writes the store only; the engine and overlays fill the frames.
import { icon } from './icons.js';
import { state, set, subscribe, bus, presetWindow, matchPreset } from './state.js';
import { IDS, MPR, COLORS } from './core.js';
import { fitCamera } from './fit.js';

const VIEW_NAMES = { axial: 'Axial', threeD: '3D', coronal: 'Coronal', sagittal: 'Sagittal' };
const CONTRAST_CHIPS = [
  ['bone', 'Bone'],
  ['teeth', 'Teeth'],
  ['soft', 'Soft tissue'],
  ['fineBone', 'Fine bone'],
  ['full', 'Full range'],
];
const VIEW3D_CHIPS = [
  ['bone', 'Bone'],
  ['teeth', 'Teeth'],
  ['skinBone', 'Skin + bone'],
  ['xray', 'X-ray'],
  ['mip', 'MIP'],
];
const SLAB_MODES = [
  ['thin', 'Thin'],
  ['mip', 'MIP'],
  ['mean', 'Mean'],
  ['minip', 'MinIP'],
];
const CUT_MODES = [
  ['off', 'Off'],
  ['axial', 'Axial'],
  ['coronal', 'Coronal'],
  ['sagittal', 'Sagittal'],
];
const TOOLS = [
  { group: 'nav', id: 'crosshair', ico: 'crosshair', title: 'Crosshair (C)' },
  { group: 'nav', id: 'pan', ico: 'pan', title: 'Pan (P)' },
  { group: 'nav', id: 'zoom', ico: 'zoom', title: 'Zoom (Z)' },
  { group: 'nav', id: 'wl', ico: 'wl', title: 'Window / level (W)' },
  { group: 'measure', id: 'length', ico: 'length', title: 'Length (L)' },
  { group: 'measure', id: 'angle', ico: 'angle', title: 'Angle (A)' },
  { group: 'measure', id: 'ellipse', ico: 'ellipse', title: 'Ellipse ROI (E)' },
];
const SHORTCUTS = [
  ['C P Z W', 'Crosshair, pan, zoom, window / level'],
  ['L A E', 'Length, angle, ellipse measurement'],
  ['1 – 5', 'Contrast presets'],
  ['↑ ↓  PgUp PgDn', 'Slice ±1 / ±10 in the hovered view'],
  ['H', 'Hide or show lines, labels and measurements'],
  ['R', 'Reset views, window, slab, cut and invert'],
  ['S', 'Save the active view as a key image'],
  ['F', 'Maximise the hovered view'],
  [']', 'Show or hide the right panel'],
  ['?', 'This sheet'],
  ['Esc', 'Close this sheet, then leave the maximised view'],
  ['Left-drag', 'The active tool (3D: rotate)'],
  ['Right-drag', 'Window and level'],
  ['Middle-drag', 'Pan'],
  ['Wheel  ·  Shift + wheel', 'Scroll slices  ·  10 slices (3D: zoom)'],
  ['Ctrl + wheel', 'Zoom at the cursor'],
  ['Double-click', 'Maximise or restore a view'],
];

export function h(tag, props = {}, ...kids) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (v === undefined || v === null) continue;
    if (k === 'class') node.className = v;
    else if (k === 'text') node.textContent = v;
    else if (k.startsWith('on')) node.addEventListener(k.slice(2), v);
    else node.setAttribute(k, v);
  }
  kids.flat().forEach((c) => c != null && c !== false && node.append(c));
  return node;
}

const NS = 'http://www.w3.org/2000/svg';
export const svgEl = (tag, attrs = {}) => {
  const n = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, v);
  return n;
};

const fmt = (n) => (Number.isFinite(n) ? String(Math.round(n)) : '');

// ───────────────────────── Viewport frame ─────────────────────────

function createFrame(id) {
  const host = h('div', { class: 'host', 'data-id': id });
  const svg = svgEl('svg', { class: 'ov' });
  const poster = h('img', { class: 'poster', alt: '', draggable: 'false' });
  const dot = h('i');
  const sub = h('small', { text: id === 'threeD' ? 'Bone' : '' });
  const pill = h('div', { class: 'pill', style: `--dot:${COLORS[id]}` }, dot, h('span', { class: 'name', text: VIEW_NAMES[id] }), sub);
  const buttons = h(
    'div',
    { class: 'vpbtns' },
    h('button', { class: 'vpbtn', type: 'button', title: 'Reset this view', 'aria-label': 'Reset this view', onclick: () => bus.emit('viewport-reset', { id }) }, icon('reset', 14)),
    h('button', { class: 'vpbtn', type: 'button', title: 'Maximise or restore (F)', 'aria-label': 'Maximise or restore', onclick: () => toggleSingle(id) }, icon('maximize', 14)),
  );
  const letters = {
    top: h('span', { class: 'lt top' }),
    bottom: h('span', { class: 'lt bottom' }),
    left: h('span', { class: 'lt left' }),
    right: h('span', { class: 'lt right' }),
  };
  const info1 = h('div');
  const info2 = h('div');
  const info = h('div', { class: 'vpinfo' }, info1, info2);
  const scaleLbl = h('span', { class: 'lbl' });
  const scaleBar = h('i', { class: 'bar' });
  const scale = h('div', { class: 'scale' }, scaleLbl, scaleBar);
  const thumb = h('i', { class: 'thumb', style: `--c:${COLORS[id]}` });
  const sb = h('div', { class: 'sb' }, h('i', { class: 'track' }), thumb);
  const hint = h('div', { class: 'hint', text: 'Drag to rotate · scroll to zoom · click to place crosshair' });
  const gizmoSvg = svgEl('svg', { class: 'gizmo', width: 60, height: 60, viewBox: '0 0 60 60' });

  const root = h('section', { class: 'vp', 'data-id': id }, host, poster, svg, h('div', { class: 'letters' }, Object.values(letters)), pill, buttons, info, id === 'threeD' ? hint : scale, id === 'threeD' ? gizmoSvg : sb);
  root.addEventListener('mouseenter', () => set({ hovered: id }));
  root.addEventListener('mouseleave', () => {
    set({ hovered: null, status: null });
  });
  root.addEventListener('pointerdown', () => set({ active: id }), true);
  root.addEventListener('dblclick', (e) => {
    if (e.target.closest('.vpbtns,.sb,.thumb')) return;
    toggleSingle(id);
  });

  // Keep the overlay SVG's viewBox equal to its pixel size; refit a "plane" poster.
  let poseter = null;
  const resize = () => {
    const w = root.clientWidth;
    const hh = root.clientHeight;
    svg.setAttribute('viewBox', `0 0 ${w} ${hh}`);
    if (poseter) placePoster();
  };
  new ResizeObserver(resize).observe(root);

  function placePoster() {
    const { kind, extents } = poseter;
    const w = root.clientWidth;
    const hh = root.clientHeight;
    const s = poster.style;
    if (kind === 'plane' && extents) {
      const f = fitCamera(w, hh, extents[0], extents[1]);
      s.objectFit = 'fill';
      s.width = `${f.rectW}px`;
      s.height = `${f.rectH}px`;
      s.left = `${(w - f.rectW) / 2}px`;
      s.top = `${(hh - f.rectH) / 2}px`;
    } else {
      s.objectFit = 'contain';
      s.width = '100%';
      s.height = '100%';
      s.left = '0';
      s.top = '0';
    }
  }

  const frame = {
    id,
    root,
    host,
    svg,
    poster,
    gizmoSvg,
    setLabel({ oblique = false, sub: text } = {}) {
      if (id === 'threeD') sub.textContent = text || '';
      else sub.textContent = oblique ? 'Oblique' : '';
    },
    setOrientation({ top = '', bottom = '', left = '', right = '' }) {
      letters.top.textContent = top;
      letters.bottom.textContent = bottom;
      letters.left.textContent = left;
      letters.right.textContent = right;
    },
    setInfo(line1, line2) {
      info1.textContent = line1 || '';
      info2.textContent = line2 || '';
    },
    setScale(s) {
      scale.style.display = s ? '' : 'none';
      if (!s) return;
      scaleBar.style.width = `${s.px}px`;
      scaleLbl.textContent = s.label;
    },
    setScroll(t, visible = true) {
      sb.style.display = visible ? '' : 'none';
      thumb.style.top = `calc(48px + (100% - 96px - 18px) * ${Math.min(1, Math.max(0, t))})`;
    },
    onScroll(cb) {
      const move = (e) => {
        const r = sb.getBoundingClientRect();
        const top = r.top + 48;
        const span = r.height - 96 - 18;
        cb(Math.min(1, Math.max(0, (e.clientY - top - 9) / span)));
      };
      sb.addEventListener('pointerdown', (e) => {
        e.preventDefault();
        e.stopPropagation();
        sb.setPointerCapture(e.pointerId);
        move(e);
        const onMove = (ev) => move(ev);
        const onUp = () => {
          sb.removeEventListener('pointermove', onMove);
          sb.removeEventListener('pointerup', onUp);
        };
        sb.addEventListener('pointermove', onMove);
        sb.addEventListener('pointerup', onUp);
      });
    },
    setPoster(url, kind = 'plane', extents = null) {
      poseter = { kind, extents };
      poster.style.opacity = '1';
      poster.style.filter = '';
      poster.style.display = '';
      poster.onerror = () => (poster.style.display = 'none');
      poster.src = url;
      placePoster();
    },
    clearPoster() {
      poseter = null;
      poster.removeAttribute('src');
      poster.style.filter = '';
      poster.style.display = 'none';
    },
    fadePoster(ms) {
      return new Promise((resolve) => {
        const dur = state.reduced ? 80 : (ms || 500);
        const blur = !state.reduced;
        poster.style.transition = blur
          ? `opacity ${dur}ms var(--ease), filter ${dur}ms var(--ease)`
          : `opacity ${dur}ms var(--ease)`;
        poster.style.opacity = '0';
        if (blur) poster.style.filter = 'blur(1px)';
        setTimeout(() => {
          poster.style.display = 'none';
          poster.style.transition = '';
          poster.style.filter = '';
          resolve();
        }, dur);
      });
    },
    hasPoster: () => !!poster.getAttribute('src') && poster.style.display !== 'none',
  };
  frame.clearPoster();
  return frame;
}

// ───────────────────────── Layout ─────────────────────────

let gridEl = null;
function applyLayout() {
  if (!gridEl) return;
  gridEl.dataset.layout = state.layout;
  for (const s of gridEl.querySelectorAll('.vp')) s.classList.toggle('focus', s.dataset.id === state.focus);
}
function toggleSingle(id) {
  if (state.layout === 'single' && state.focus === id) set({ layout: '2x2' });
  else set({ layout: 'single', focus: id });
}
export function setLayoutMode(mode) {
  const focus = state.hovered || state.focus;
  set({ layout: mode, focus: mode === '2x2' ? state.focus : focus });
}

// ───────────────────────── Controls ─────────────────────────

function chipRow(items, onPick, { digits = false } = {}) {
  const wrap = h('div', { class: 'chips' });
  const buttons = {};
  items.forEach(([key, label], i) => {
    const b = h('button', { class: 'chip', type: 'button', onclick: () => onPick(key) }, label, digits ? h('kbd', { text: String(i + 1) }) : null);
    buttons[key] = b;
    wrap.append(b);
  });
  return { el: wrap, mark: (active) => Object.entries(buttons).forEach(([k, b]) => b.classList.toggle('on', k === active)) };
}

function segmented(items, onPick) {
  const wrap = h('div', { class: 'seg' });
  const buttons = {};
  for (const [key, label] of items) {
    const b = h('button', { type: 'button', text: label, onclick: () => onPick(key) });
    buttons[key] = b;
    wrap.append(b);
  }
  return { el: wrap, mark: (active) => Object.entries(buttons).forEach(([k, b]) => b.classList.toggle('on', k === active)) };
}

function slider(min, max, step, onInput) {
  const input = h('input', { class: 'range', type: 'range', min, max, step });
  const paint = () => input.style.setProperty('--p', `${((Number(input.value) - Number(input.min)) / (Number(input.max) - Number(input.min) || 1)) * 100}%`);
  input.addEventListener('input', () => {
    paint();
    onInput(Number(input.value));
  });
  return {
    el: input,
    set(v, lo, hi) {
      if (lo !== undefined) {
        input.min = lo;
        input.max = hi;
      }
      input.value = v;
      paint();
    },
  };
}

function numInput(onCommit, { min, step = 1, suffix } = {}) {
  const input = h('input', { class: 'num', type: 'number', step, min });
  const commit = () => {
    const v = Number(input.value);
    if (Number.isFinite(v) && input.value !== '') onCommit(v);
  };
  input.addEventListener('change', commit);
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') input.blur();
    e.stopPropagation();
  });
  const el = suffix ? h('span', { class: 'numwrap' }, input, h('em', { text: suffix })) : input;
  return {
    el,
    set(v) {
      if (document.activeElement !== input) input.value = v;
    },
    input,
  };
}

const row = (label, ...ctl) => h('div', { class: 'prow' }, h('label', { text: label }), ...ctl);
const section = (title, ...kids) => h('section', { class: 'psec' }, h('h3', { text: title }), ...kids);

// ───────────────────────── Mount ─────────────────────────

export function mountChrome(root) {
  const ui = { frames: {}, hosts: {} };
  const post = (msg) => bus.emit('post', msg);

  // ---- top bar ----
  const title = h('span', { class: 'title' });
  const info = h('span', { class: 'info' });
  const toolBtns = {};
  const group = (name) => h('div', { class: 'tgroup' }, TOOLS.filter((t) => t.group === name).map((t) => {
    const b = h('button', { class: 'tbtn', type: 'button', title: t.title, 'aria-label': t.title, onclick: () => set({ tool: t.id }) }, icon(t.ico));
    toolBtns[t.id] = b;
    return b;
  }));
  const layoutBtns = {};
  const layoutGroup = h(
    'div',
    { class: 'tgroup' },
    ...[
      ['2x2', 'grid', '2 × 2'],
      ['1col', 'panelRight', 'One large view and three small'],
      ['single', 'square', 'One view (F)'],
    ].map(([mode, ico, label]) => {
      const b = h('button', { class: 'tbtn', type: 'button', title: label, 'aria-label': label, onclick: () => setLayoutMode(mode) }, icon(ico));
      layoutBtns[mode] = b;
      return b;
    }),
  );
  const overlaysBtn = h('button', { class: 'tbtn', type: 'button', title: 'Show or hide overlays (H)', 'aria-label': 'Overlays', onclick: () => set({ overlays: !state.overlays }) }, icon('eye'));
  const panelBtn = h('button', { class: 'tbtn', type: 'button', title: 'Right panel (])', 'aria-label': 'Right panel', onclick: () => set({ panelOpen: !state.panelOpen }) }, icon('panelRight'));
  const viewGroup = h(
    'div',
    { class: 'tgroup' },
    overlaysBtn,
    h('button', { class: 'tbtn', type: 'button', title: 'Reset (R)', 'aria-label': 'Reset', onclick: () => bus.emit('reset') }, icon('reset')),
    h('button', { class: 'tbtn', type: 'button', title: 'Save key image (S)', 'aria-label': 'Snapshot', onclick: () => bus.emit('snapshot') }, icon('camera')),
    panelBtn,
    h('button', { class: 'tbtn', type: 'button', title: 'Shortcuts (?)', 'aria-label': 'Shortcuts', onclick: () => set({ helpOpen: !state.helpOpen }) }, icon('help')),
  );
  const bar = h(
    'header',
    { class: 'bar' },
    h('button', { class: 'back', type: 'button', title: 'Back', 'aria-label': 'Back', onclick: () => bus.emit('close-request') }, icon('back', 18)),
    h('span', { class: 'toothico' }, icon('tooth', 18)),
    title,
    info,
    h('span', { class: 'spacer' }),
    group('nav'),
    group('measure'),
    layoutGroup,
    viewGroup,
  );
  const progress = h('div', { class: 'progress' }, h('i'));

  // ---- viewports ----
  const grid = h('main', { class: 'grid' });
  gridEl = grid;
  for (const id of IDS) {
    const frame = createFrame(id);
    ui.frames[id] = frame;
    ui.hosts[id] = frame.host;
    grid.append(frame.root);
  }

  // ---- right panel ----
  const contrastChips = chipRow(CONTRAST_CHIPS, (key) => {
    const w = presetWindow(state.meta, key);
    if (w) set({ contrast: { ...w, preset: key } });
  }, { digits: true });

  const histCanvas = h('canvas', { class: 'histcv' });
  const histLabels = h('div', { class: 'histlabels' });
  const hist = h('div', { class: 'hist' }, histCanvas);

  const rangeOf = () => (state.meta ? [state.meta.values.min, state.meta.values.max] : [-1000, 4000]);
  const setWindow = (low, high) => {
    const [mn, mx] = rangeOf();
    low = Math.max(mn, Math.min(low, mx - 1));
    high = Math.max(low + 1, Math.min(high, mx));
    set({ contrast: { low, high, preset: matchPreset(state.meta, low, high) } });
  };
  const levelNum = numInput((v) => setWindow(v - (state.contrast.high - state.contrast.low) / 2, v + (state.contrast.high - state.contrast.low) / 2));
  const widthNum = numInput((v) => {
    const l = (state.contrast.low + state.contrast.high) / 2;
    setWindow(l - Math.max(1, v) / 2, l + Math.max(1, v) / 2);
  }, { min: 1 });
  const levelSlider = slider(0, 1, 1, (v) => {
    const w = state.contrast.high - state.contrast.low;
    setWindow(v - w / 2, v + w / 2);
  });
  const widthSlider = slider(1, 2, 1, (v) => {
    const l = (state.contrast.low + state.contrast.high) / 2;
    setWindow(l - v / 2, l + v / 2);
  });
  const invert = h('button', { class: 'toggle', type: 'button', role: 'switch', 'aria-label': 'Invert', onclick: () => set({ contrast: { invert: !state.contrast.invert } }) }, h('i'));

  const slabSeg = segmented(SLAB_MODES, (mode) => {
    if (mode === 'thin') set({ slab: { mode, thickness: 0 } });
    else set({ slab: { mode, thickness: state.slab.thickness > 0 ? state.slab.thickness : 5 } });
  });
  const applyThickness = (t) => {
    t = Math.max(0, Math.min(20, Math.round(t * 10) / 10));
    if (t === 0) set({ slab: { mode: 'thin', thickness: 0 } });
    else set({ slab: { mode: state.slab.mode === 'thin' ? 'mip' : state.slab.mode, thickness: t } });
  };
  const thickNum = numInput(applyThickness, { min: 0, step: 0.1, suffix: 'mm' });
  const thickSlider = slider(0, 20, 0.1, applyThickness);

  const view3dChips = chipRow(VIEW3D_CHIPS, (preset) => set({ view3d: { preset } }));
  const thresholdVal = h('span', { class: 'val' });
  const thresholdSlider = slider(-300, 500, 1, (v) => set({ view3d: { threshold: v } }));
  const opacityVal = h('span', { class: 'val' });
  const opacitySlider = slider(0, 260, 1, (v) => set({ view3d: { opacity: v } }));
  const cutSeg = segmented(CUT_MODES, (cut) => set({ view3d: { cut } }));
  const flipBtn = h('button', { class: 'iconbtn', type: 'button', title: 'Flip the kept side', 'aria-label': 'Flip the kept side', onclick: () => set({ view3d: { cutFlip: !state.view3d.cutFlip } }) }, icon('flip', 14));

  const panel = h(
    'aside',
    { class: 'panel' },
    h(
      'div',
      { class: 'pin' },
      section('Contrast', contrastChips.el, hist, histLabels, row('Level', levelNum.el, levelSlider.el), row('Width', widthNum.el, widthSlider.el), h('div', { class: 'prow' }, h('label', { text: 'Invert' }), invert)),
      section('Slab', slabSeg.el, row('Thickness', thickNum.el, thickSlider.el)),
      section('3D view', view3dChips.el, row('Threshold', thresholdSlider.el, thresholdVal), row('Opacity', opacitySlider.el, opacityVal), h('div', { class: 'prow cutrow' }, h('label', { text: 'Cut at crosshair' }), flipBtn), cutSeg.el),
    ),
  );
  const main = h('div', { class: 'main' }, grid, panel);

  // ---- status bar, help, messages ----
  const readout = h('span', { class: 'readout' });
  const status = h('footer', { class: 'status' }, readout, h('span', { class: 'net', text: 'No network access' }));
  const sheet = h('div', { class: 'sheet' }, h('h2', { text: 'Shortcuts' }), SHORTCUTS.map(([k, d]) => h('div', { class: 'row' }, h('kbd', { text: k }), h('span', { text: d }))));
  const help = h('div', { class: 'help', onclick: (e) => e.target === help && set({ helpOpen: false }) }, sheet);
  const msg = h('div', { class: 'msg', text: 'Loading scan…' });
  root.append(bar, progress, main, status, help, msg);

  // ---- histogram drawing and dragging ----
  const hctx = histCanvas.getContext('2d');
  let hw = 240;
  const HH = 96;
  const valueToX = (v) => {
    const [mn, mx] = rangeOf();
    return ((v - mn) / (mx - mn || 1)) * hw;
  };
  const xToValue = (x) => {
    const [mn, mx] = rangeOf();
    return mn + (x / hw) * (mx - mn);
  };
  function drawHistogram() {
    const dpr = window.devicePixelRatio || 1;
    hw = hist.clientWidth || 240;
    if (histCanvas.width !== Math.round(hw * dpr)) {
      histCanvas.width = Math.round(hw * dpr);
      histCanvas.height = Math.round(HH * dpr);
      histCanvas.style.width = `${hw}px`;
      histCanvas.style.height = `${HH}px`;
    }
    hctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    hctx.clearRect(0, 0, hw, HH);
    const bins = state.histogram;
    const { low, high } = state.contrast;
    const xl = valueToX(low);
    const xh = valueToX(high);
    if (bins) {
      const bw = hw / bins.length;
      const grad = hctx.createLinearGradient(0, 0, 0, HH);
      grad.addColorStop(0, '#c3cad5');
      grad.addColorStop(1, '#8e97a5');
      for (let i = 0; i < bins.length; i++) {
        const x = i * bw;
        const bh = bins[i] * (HH - 14);
        hctx.fillStyle = x + bw >= xl && x <= xh ? grad : '#3a4250';
        hctx.fillRect(x, HH - bh, Math.ceil(bw), bh);
      }
    }
    // ramp: low at the bottom to high at the top, clipped to the box
    hctx.strokeStyle = '#4d8ef7';
    hctx.lineWidth = 1.5;
    hctx.beginPath();
    hctx.moveTo(xl, HH);
    hctx.lineTo(xh, 0);
    hctx.stroke();
    hctx.lineWidth = 1;
    for (const x of [xl, xh]) {
      hctx.beginPath();
      hctx.moveTo(x + 0.5, 0);
      hctx.lineTo(x + 0.5, HH);
      hctx.stroke();
      hctx.fillStyle = '#4d8ef7';
      hctx.beginPath();
      hctx.roundRect(x - 3, HH / 2 - 7, 6, 14, 3);
      hctx.fill();
    }
  }
  function drawLabels() {
    histLabels.replaceChildren();
    const m = state.meta;
    if (!m) return;
    const L = m.landmarks;
    const items = [['Air', L.air], ['Soft', L.soft], ['Bone', L.bone], ['Teeth', L.teeth], ...(L.metal != null ? [['Metal', L.metal]] : [])];
    let prev = -1e9;
    for (const [name, v] of items) {
      const x = valueToX(v);
      if (x - prev < 28) continue;
      prev = x;
      histLabels.append(h('span', { text: name, style: `left:${x}px` }));
    }
  }
  let dragging = null;
  histCanvas.addEventListener('pointerdown', (e) => {
    const x = e.offsetX;
    const xl = valueToX(state.contrast.low);
    const xh = valueToX(state.contrast.high);
    if (Math.abs(x - xl) < 8) dragging = { part: 'low' };
    else if (Math.abs(x - xh) < 8) dragging = { part: 'high' };
    else if (x > xl && x < xh) dragging = { part: 'move', start: xToValue(x), low: state.contrast.low, high: state.contrast.high };
    if (dragging) histCanvas.setPointerCapture(e.pointerId);
  });
  histCanvas.addEventListener('pointermove', (e) => {
    if (!dragging) return;
    const v = xToValue(Math.max(0, Math.min(hw, e.offsetX)));
    if (dragging.part === 'low') setWindow(v, state.contrast.high);
    else if (dragging.part === 'high') setWindow(state.contrast.low, v);
    else setWindow(dragging.low + (v - dragging.start), dragging.high + (v - dragging.start));
  });
  histCanvas.addEventListener('pointerup', () => (dragging = null));
  new ResizeObserver(() => {
    drawHistogram();
    drawLabels();
  }).observe(hist);

  // ---- state -> controls ----
  function render(s, changed) {
    const all = !changed;
    const has = (k) => all || changed.has(k);
    if (has('display') && s.display) {
      title.textContent = s.display.title || 'CBCT';
      info.replaceChildren();
      const chip = s.display.chip || '';
      if (chip) info.append(chip);
      if (s.display.badge) info.append(' · ', h('span', { class: 'badge' }, icon('shield', 13), s.display.badge));
      info.style.display = chip || s.display.badge ? '' : 'none';
    }
    if (has('tool')) for (const [id, b] of Object.entries(toolBtns)) b.classList.toggle('on', id === s.tool);
    if (has('layout') || has('focus')) {
      applyLayout();
      for (const [mode, b] of Object.entries(layoutBtns)) b.classList.toggle('on', mode === s.layout);
    }
    if (has('overlays')) {
      root.classList.toggle('no-overlay', !s.overlays);
      overlaysBtn.classList.toggle('on', s.overlays);
    }
    if (has('panelOpen')) {
      main.dataset.panel = s.panelOpen ? 'open' : 'closed';
      panelBtn.classList.toggle('on', s.panelOpen);
    }
    if (has('helpOpen')) help.classList.toggle('open', s.helpOpen);
    if (has('progress')) {
      progress.classList.toggle('busy', s.progress === 'busy');
      progress.classList.toggle('on', s.progress !== null);
      progress.firstChild.style.width = typeof s.progress === 'number' ? `${s.progress * 100}%` : '';
    }
    if (has('contrast') || has('meta')) {
      const c = s.contrast;
      contrastChips.mark(c.preset);
      const [mn, mx] = rangeOf();
      const level = (c.low + c.high) / 2;
      const width = c.high - c.low;
      levelNum.set(fmt(level));
      widthNum.set(fmt(width));
      levelSlider.set(level, mn, mx);
      widthSlider.set(width, 1, Math.max(2, mx - mn));
      invert.classList.toggle('on', c.invert);
      invert.setAttribute('aria-checked', String(c.invert));
      drawHistogram();
    }
    if (has('slab')) {
      slabSeg.mark(s.slab.mode);
      thickNum.set(s.slab.thickness);
      thickSlider.set(s.slab.thickness);
    }
    if (has('view3d')) {
      const v = s.view3d;
      view3dChips.mark(v.preset);
      thresholdSlider.set(v.threshold);
      thresholdVal.textContent = v.threshold;
      opacitySlider.set(v.opacity);
      opacityVal.textContent = `${Math.round(v.opacity)}%`;
      cutSeg.mark(v.cut);
      flipBtn.classList.toggle('on', v.cutFlip);
      ui.frames.threeD.setLabel({ sub: v.cut === 'off' ? presetName(v.preset) : `${presetName(v.preset)} · cut ${v.cut}` });
    }
    if (has('histogram')) drawHistogram();
    if (has('meta')) drawLabels();
    if (has('status')) {
      const st = s.status;
      readout.textContent = st ? `${VIEW_NAMES[st.viewport]}   x ${st.x.toFixed(2)}   y ${st.y.toFixed(2)}   z ${st.z.toFixed(2)} mm   ·   value ${st.value == null ? '–' : Math.round(st.value)}` : '';
    }
    if (has('hovered')) root.dataset.hovered = s.hovered || '';
    if (has('reduced')) document.documentElement.classList.toggle('reduced', !!s.reduced);
  }
  subscribe(render);
  render(state, null);

  // ---- ui api ----
  ui.setDisplay = (d) => set({ display: d });
  ui.setMeta = (m) => set({ meta: m });
  ui.setProgress = (p) => set({ progress: p });
  ui.message = (text, isError = false) => {
    msg.textContent = text;
    msg.classList.toggle('error', isError);
    msg.classList.remove('hidden');
  };
  ui.hideMessage = () => msg.classList.add('hidden');
  ui.decodePosters = () => Promise.all(IDS.map((id) => (ui.frames[id].hasPoster() ? ui.frames[id].poster.decode().catch(() => {}) : null)));
  ui.post = post;
  return ui;
}

function presetName(p) {
  return { bone: 'Bone', teeth: 'Teeth', skinBone: 'Skin + bone', xray: 'X-ray', mip: 'MIP' }[p] || '';
}

// ───────────────────────── Keyboard ─────────────────────────

export function installKeys() {
  const TOOL_KEYS = { c: 'crosshair', p: 'pan', z: 'zoom', w: 'wl', l: 'length', a: 'angle', e: 'ellipse' };
  window.addEventListener('keydown', (e) => {
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    if (e.target instanceof HTMLInputElement && e.key !== 'Escape') return;
    const key = e.key.toLowerCase();
    const id = state.hovered || state.active;
    if (TOOL_KEYS[key]) set({ tool: TOOL_KEYS[key] });
    else if (key >= '1' && key <= '5') {
      const preset = CONTRAST_CHIPS[Number(key) - 1][0];
      const w = presetWindow(state.meta, preset);
      if (w) set({ contrast: { ...w, preset } });
    } else if (key === 'h') set({ overlays: !state.overlays });
    else if (key === 'r') bus.emit('reset');
    else if (key === 's') bus.emit('snapshot');
    else if (key === 'f') toggleSingle(state.hovered || state.focus);
    else if (key === ']') set({ panelOpen: !state.panelOpen });
    else if (key === '?') set({ helpOpen: !state.helpOpen });
    else if (key === 'arrowup') bus.emit('scroll', { id, delta: 1 });
    else if (key === 'arrowdown') bus.emit('scroll', { id, delta: -1 });
    else if (key === 'pageup') bus.emit('scroll', { id, delta: 10 });
    else if (key === 'pagedown') bus.emit('scroll', { id, delta: -10 });
    else if (key === 'escape') {
      // Close the sheet, then leave a maximised view; the back button closes the viewer.
      if (state.helpOpen) set({ helpOpen: false });
      else if (state.layout !== '2x2') set({ layout: '2x2' });
    } else return;
    e.preventDefault();
  });
}
