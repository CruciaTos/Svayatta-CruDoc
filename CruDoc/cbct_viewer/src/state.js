// One small store. The UI writes what the user sets; the engine applies it and
// writes back what it learns (window/level drags, hovered position...).
// set() merges one level deep for object values and notifies once, synchronously.

export const state = {
  meta: null,
  display: null, // { title, chip, badge }
  deviceClass: 'pc',
  reduced: false,
  phase: 'empty', // empty | poster | preview | full
  progress: null, // null | 0..1 | 'busy'
  layout: '2x2', // 2x2 | 1col | single
  focus: 'axial',
  panelOpen: true,
  helpOpen: false,
  overlays: true,
  tool: 'crosshair', // crosshair pan zoom wl length angle ellipse
  contrast: { preset: 'bone', low: -600, high: 3000, invert: false },
  slab: { mode: 'thin', thickness: 0 }, // thin mip mean minip
  view3d: { preset: 'bone', threshold: 0, opacity: 100, cut: 'off', cutFlip: false },
  hovered: null,
  active: 'axial',
  status: null, // { viewport, x, y, z, value }
  histogram: null, // 256 heights 0..1
};

const listeners = new Set();

export function set(patch) {
  const changed = new Set();
  for (const [key, value] of Object.entries(patch)) {
    const cur = state[key];
    if (value && typeof value === 'object' && !Array.isArray(value) && cur && typeof cur === 'object' && !ArrayBuffer.isView(value) && key !== 'meta') {
      Object.assign(cur, value);
    } else {
      state[key] = value;
    }
    changed.add(key);
  }
  for (const fn of [...listeners]) fn(state, changed);
}

export function subscribe(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

export const bus = {
  map: new Map(),
  on(name, fn) {
    if (!this.map.has(name)) this.map.set(name, new Set());
    this.map.get(name).add(fn);
    return () => this.map.get(name).delete(fn);
  },
  emit(name, payload) {
    (this.map.get(name) || []).forEach((fn) => fn(payload));
  },
};

// ---- window helpers (all values are REAL units, see meta.values.valueOffset) ----

export function presetWindow(meta, key) {
  const p = meta && meta.presets && meta.presets[key];
  return p ? { low: p.low, high: p.high } : null;
}

export function matchPreset(meta, low, high) {
  if (!meta) return null;
  const tol = (meta.values.max - meta.values.min) * 0.005;
  for (const [key, p] of Object.entries(meta.presets)) {
    if (Math.abs(p.low - low) < tol && Math.abs(p.high - high) < tol) return key;
  }
  return null;
}
