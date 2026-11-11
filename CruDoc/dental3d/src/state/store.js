// Plain observable store. `set(patch)` shallow-merges top-level keys (layers and
// per-tooth objects are merged one level deeper) and notifies subscribers with
// the set of changed top-level keys.

import { defaultToothState, defaultSnapshot } from './schema.js';

export const FDI_LIST = [
  18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28,
  48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38,
];

export const defaultTooth = defaultToothState;

export function createStore() {
  const teeth = {};
  for (const f of FDI_LIST) teeth[f] = defaultToothState();
  const def = defaultSnapshot();
  let state = {
    mode: 'pbr',
    explode: 0,
    jawOpen: 0,
    layers: { gums: true, bone: true, upper: true, lower: true },
    quality: 'medium',
    selectedId: null,
    hoveredId: null,
    profile: def.profile,
    treatments: def.treatments,
    visits: def.visits,
    currentVisit: def.currentVisit,
    teeth,
  };
  const subs = new Set();
  // Which teeth changed since the last notification (lets gums rebuild per arch).
  let changedTeeth = new Set();

  function notify(changed) {
    const ct = changedTeeth;
    changedTeeth = new Set();
    for (const fn of [...subs]) fn(state, changed, ct);
  }

  return {
    get: () => state,
    subscribe(fn) { subs.add(fn); return () => subs.delete(fn); },
    set(patch) {
      const changed = new Set();
      const next = { ...state };
      for (const [k, v] of Object.entries(patch)) {
        if (k === 'layers') {
          const l = { ...state.layers, ...v };
          if (JSON.stringify(l) !== JSON.stringify(state.layers)) { next.layers = l; changed.add('layers'); }
        } else if (k === 'profile') {
          const p = { ...state.profile, ...v };
          if (JSON.stringify(p) !== JSON.stringify(state.profile)) { next.profile = p; changed.add('profile'); }
        } else if (k === 'teeth') {
          const t = { ...state.teeth };
          for (const [fdi, tp] of Object.entries(v)) {
            if (!t[fdi]) continue;
            const cur = t[fdi];
            const merged = {
              ...cur,
              ...tp,
              shift: tp.shift ? { ...cur.shift, ...tp.shift } : cur.shift,
              rotate: tp.rotate ? { ...cur.rotate, ...tp.rotate } : cur.rotate,
              scale: tp.scale ? { ...cur.scale, ...tp.scale } : cur.scale,
            };
            if (JSON.stringify(merged) !== JSON.stringify(t[fdi])) { t[fdi] = merged; changed.add('teeth'); changedTeeth.add(+fdi); }
          }
          next.teeth = t;
        } else if (k === 'treatments' || k === 'visits') {
          if (JSON.stringify(state[k]) !== JSON.stringify(v)) {
            next[k] = v;
            changed.add(k);
          }
        } else if (state[k] !== v) {
          next[k] = v; changed.add(k);
        }
      }
      if (!changed.size) return;
      state = next;
      notify(changed);
    },
    setTooth(fdi, patch) { this.set({ teeth: { [fdi]: patch } }); },
    snapshot: () => JSON.parse(JSON.stringify(state)),
  };
}
