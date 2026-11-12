import { h, icon } from './dom.js';
import { QUALITY_LEVELS } from '../engine/quality.js';
import { PRESET_LIST } from '../data/presets.js';

const MODE_LABEL = { pbr: 'Natural', xray: 'X-ray', heatmap: 'Status' };
const VIEWS = [['front', 'Front'], ['upper', 'Upper'], ['lower', 'Lower'], ['left', 'Left'], ['right', 'Right']];
const LAYERS = [['bone', 'Bone'], ['upper', 'Upper arch'], ['lower', 'Lower arch']];
const GUM_STYLES = [['solid', 'Solid'], ['glass', 'Glass'], ['off', 'Off']];

export function createToolbar({ store, actions }) {
  const pops = [];
  const closeAll = (except) => pops.forEach((p) => { if (p !== except) p.classList.remove('open'); });
  const popBtn = (name, label, content, extra) => {
    const pop = h('div', { class: 'popover ' + (extra || '') }, content);
    const btn = h('button', {
      class: 'tb-btn', type: 'button', title: label, 'aria-label': label, 'data-pop': name,
      onclick: (e) => { e.stopPropagation(); const open = !pop.classList.contains('open'); closeAll(); pop.classList.toggle('open', open); },
    }, icon(name === 'adjust' ? 'sliders' : name));
    pops.push(pop);
    return { btn, pop };
  };

  // mode toggle
  const seg = h('div', { class: 'seg', role: 'group', 'aria-label': 'Display mode' });
  const modeBtns = Object.entries(MODE_LABEL).map(([m, label]) => {
    const b = h('button', { type: 'button', 'data-mode': m, onclick: () => actions.setMode(m) }, label);
    seg.append(b); return b;
  });

  // sliders
  const slider = (label, id, onInput) => {
    const input = h('input', { type: 'range', min: 0, max: 100, value: 0, id, 'aria-label': label });
    input.addEventListener('input', () => onInput(input.value / 100));
    return { el: h('label', { class: 'sl' }, h('span', null, label), input), input };
  };
  const ex = slider('Explode', 'sl-explode', (v) => actions.setExplode(v));
  const jaw = slider('Open mouth', 'sl-jaw', (v) => actions.setJawOpen(v));
  const sliders = h('div', { class: 'tb-sliders' }, ex.el, jaw.el);
  const adjustBtn = h('button', {
    class: 'tb-btn tb-adjust', type: 'button', title: 'Explode and open mouth', 'aria-label': 'Explode and open mouth',
    onclick: (e) => { e.stopPropagation(); const o = !sliders.classList.contains('open'); closeAll(); sliders.classList.toggle('open', o); },
  }, icon('sliders'));
  pops.push(sliders);

  // layers
  const layerChecks = {};
  const layerList = h('div', { class: 'pop-list' }, LAYERS.map(([k, label]) => {
    const cb = h('input', { type: 'checkbox', checked: true, 'data-layer': k });
    cb.addEventListener('change', () => actions.setLayer(k, cb.checked));
    layerChecks[k] = cb;
    return h('label', { class: 'pop-row' }, cb, h('span', null, label));
  }));
  // gums: Solid / Glass / Off
  const gumSeg = h('div', { class: 'seg gum-seg', role: 'group', 'aria-label': 'Gums' });
  const gumBtns = GUM_STYLES.map(([k, label]) => {
    const b = h('button', {
      type: 'button', 'data-gum': k,
      onclick: () => { if (k === 'off') actions.setLayer('gums', false); else { actions.setGumStyle(k); actions.setLayer('gums', true); } },
    }, label);
    gumSeg.append(b); return b;
  });
  const layers = popBtn('layers', 'Layers', [h('div', { class: 'pop-title' }, 'Gums'), gumSeg, h('div', { class: 'pop-title gum-gap' }, 'Layers'), layerList]);

  // views
  const views = popBtn('view', 'View', [
    h('div', { class: 'pop-title' }, 'View'),
    h('div', { class: 'pop-grid' }, VIEWS.map(([k, label]) => h('button', {
      type: 'button', class: 'pill-btn', 'data-view': k, onclick: () => { actions.setCameraPreset(k); closeAll(); },
    }, label))),
    h('div', { class: 'pop-grid' },
      h('button', { type: 'button', class: 'pill-btn', 'data-zoom': 'in', 'aria-label': 'Zoom in', onclick: () => actions.zoom(0.8) }, 'Zoom in'),
      h('button', { type: 'button', class: 'pill-btn', 'data-zoom': 'out', 'aria-label': 'Zoom out', onclick: () => actions.zoom(1.25) }, 'Zoom out')),
    h('button', { type: 'button', class: 'pill-btn wide', onclick: () => { actions.resetCamera(); closeAll(); } }, 'Reset view'),
  ]);

  // quality
  const qBtns = QUALITY_LEVELS.map((q) => h('button', {
    type: 'button', class: 'pill-btn', 'data-quality': q, onclick: () => { actions.setQuality(q); closeAll(); },
  }, q[0].toUpperCase() + q.slice(1)));
  const quality = popBtn('quality', 'Quality', [h('div', { class: 'pop-title' }, 'Quality'), h('div', { class: 'pop-grid' }, qBtns)]);

  // patients
  const patientBtns = PRESET_LIST.map((p) => h('button', {
    type: 'button', class: 'pill-btn wide', 'data-preset': p.id,
    onclick: () => { actions.applyStateSnapshot(JSON.parse(JSON.stringify(p.snapshot))); closeAll(); },
  }, p.label));
  const patients = popBtn('patients', 'Example patient', [h('div', { class: 'pop-title' }, 'Example patient'), h('div', { class: 'pop-list' }, patientBtns)]);

  const wrap = (x) => h('div', { class: 'pop-wrap' }, x.btn, x.pop);
  const el = h('div', { class: 'toolbar', role: 'toolbar', 'aria-label': 'Viewer controls' },
    seg, h('div', { class: 'tb-sep' }), h('div', { class: 'pop-wrap' }, adjustBtn, sliders), wrap(patients), wrap(layers), wrap(views), wrap(quality));
  document.addEventListener('click', (e) => { if (!el.contains(e.target)) closeAll(); });
  // keyboard: + / - zoom, 0 resets the view (not while typing)
  window.addEventListener('keydown', (e) => {
    if (e.ctrlKey || e.metaKey || e.altKey || /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement?.tagName || '')) return;
    if (e.key === '+' || e.key === '=') actions.zoom(0.85);
    else if (e.key === '-' || e.key === '_') actions.zoom(1 / 0.85);
    else if (e.key === '0') actions.resetCamera();
  });
  el.addEventListener('click', (e) => { if (e.target.closest('.popover, .tb-sliders')) e.stopPropagation(); });
  el.addEventListener('pointerdown', (e) => e.stopPropagation());

  function sync(s) {
    modeBtns.forEach((b) => b.classList.toggle('on', b.dataset.mode === s.mode));
    if (document.activeElement !== ex.input) ex.input.value = Math.round(s.explode * 100);
    if (document.activeElement !== jaw.input) jaw.input.value = Math.round(s.jawOpen * 100);
    for (const [k, cb] of Object.entries(layerChecks)) cb.checked = s.layers[k];
    const gumNow = s.layers.gums ? (s.gumStyle || 'solid') : 'off';
    gumBtns.forEach((b) => b.classList.toggle('on', b.dataset.gum === gumNow));
    qBtns.forEach((b) => b.classList.toggle('on', b.dataset.quality === s.quality));
    quality.btn.title = `Quality: ${s.quality}`;
  }
  store.subscribe((s) => sync(s));
  sync(store.get());
  return { el, closeAll };
}
