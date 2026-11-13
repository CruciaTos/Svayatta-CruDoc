import { MODES } from './modes.js';
import { QUALITY_LEVELS } from './quality.js';
import { PRESET_NAMES } from './camera.js';
import { FDI_LIST } from '../state/store.js';
import { TREATMENTS } from '../data/treatments.js';
import { PRESETS } from '../data/presets.js';

export const STATUSES = ['normal', 'flagged', 'planned', 'inProgress', 'completed'];
const VALID_TREATMENT_TYPES = new Set(TREATMENTS.map((t) => t.id));

const clamp = (v, min, max, def = 0) => {
  const n = Number(v);
  return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : def;
};
const clamp01 = (v) => clamp(v, 0, 1, 0);
const clampShift = (v) => clamp(v, -6, 6, 0);
const clampRotate = (v) => clamp(v, -45, 45, 0);
const clampScale = (v, def = 1) => clamp(v, 0.7, 1.3, def);
const clampWear = (v) => clamp(v, 0, 4, 0);
const clampRecession = (v) => clamp(v, 0, 8, 0);

function sanitizeToothPatch(t, cur = {}) {
  const o = {};
  if ('present' in t) o.present = !!t.present;
  if (STATUSES.includes(t.status)) o.status = t.status;
  if ('statusColor' in t) o.statusColor = /^#[0-9a-f]{6}$/i.test(t.statusColor || '') ? t.statusColor : null;
  if ('shade' in t) o.shade = t.shade || null;
  if ('stain' in t) o.stain = clamp01(t.stain);
  if ('chip' in t) o.chip = clamp01(t.chip);
  if ('wear' in t) o.wear = clampWear(t.wear);
  if ('recession' in t) o.recession = clampRecession(t.recession);
  if ('inflammation' in t) o.inflammation = clamp01(t.inflammation);
  if ('calculus' in t) o.calculus = clamp01(t.calculus);
  if ('boneLoss' in t) o.boneLoss = clampRecession(t.boneLoss);

  if (t.shift && typeof t.shift === 'object') {
    const curShift = cur.shift || { md: 0, bl: 0, v: 0 };
    o.shift = {
      md: 'md' in t.shift ? clampShift(t.shift.md) : curShift.md,
      bl: 'bl' in t.shift ? clampShift(t.shift.bl) : curShift.bl,
      v: 'v' in t.shift ? clampShift(t.shift.v) : curShift.v,
    };
  }
  if (t.rotate && typeof t.rotate === 'object') {
    const curRot = cur.rotate || { tip: 0, torque: 0, spin: 0 };
    o.rotate = {
      tip: 'tip' in t.rotate ? clampRotate(t.rotate.tip) : curRot.tip,
      torque: 'torque' in t.rotate ? clampRotate(t.rotate.torque) : curRot.torque,
      spin: 'spin' in t.rotate ? clampRotate(t.rotate.spin) : curRot.spin,
    };
  }
  if (t.scale && typeof t.scale === 'object') {
    const curScale = cur.scale || { w: 1, h: 1 };
    o.scale = {
      w: 'w' in t.scale ? clampScale(t.scale.w, 1) : curScale.w,
      h: 'h' in t.scale ? clampScale(t.scale.h, 1) : curScale.h,
    };
  }
  if ('conditions' in t && Array.isArray(t.conditions)) {
    o.conditions = t.conditions.map((c) => ({
      type: String(c.type || ''),
      ...(Array.isArray(c.surfaces) ? { surfaces: c.surfaces.map(String) } : {}),
    }));
  }
  return o;
}

// Single entry point for every state change (UI, picking and the Flutter bridge).
export function createActions({ store, registry, cameraRig }) {
  const exists = (id) => registry.map.has(id);
  const actions = {
    select(id, { fly = false } = {}) {
      if (id !== null && !exists(id)) return false;
      store.set({ selectedId: id });
      if (id && fly) cameraRig.flyTo(id);
      return true;
    },
    hover(id) { if (id === null || exists(id)) store.set({ hoveredId: id }); },
    setPartStatus(nodeId, status, hex) {
      const obj = registry.get(nodeId);
      if (!obj || obj.userData.part.kind !== 'tooth' || !STATUSES.includes(status)) return false;
      store.setTooth(obj.userData.part.fdi, { status, statusColor: /^#[0-9a-f]{6}$/i.test(hex || '') ? hex : null });
      return true;
    },
    setExplode: (f) => store.set({ explode: clamp01(f) }),
    setJawOpen: (f) => store.set({ jawOpen: clamp01(f) }),
    setMode(m) { if (MODES.includes(m)) store.set({ mode: m }); },
    setLayer(name, on) { if (name in store.get().layers) store.set({ layers: { [name]: !!on } }); },
    setGumStyle(name) { if (name === 'solid' || name === 'glass') store.set({ gumStyle: name }); },
    setQuality(q) { if (QUALITY_LEVELS.includes(q)) store.set({ quality: q }); },
    resetCamera: () => cameraRig.reset(),
    zoom: (factor) => cameraRig.zoomBy(factor),
    setCameraPreset(name) { if (PRESET_NAMES.includes(name)) cameraRig.preset(name); },
    flyTo: (id) => cameraRig.flyTo(id),
    loadPreset(name) {
      const p = PRESETS[name];
      if (p) actions.applyStateSnapshot(JSON.parse(JSON.stringify(p)));
    },
    playExplainer: () => false,
    closeExplainer: () => false,
    getPersist() {
      const s = store.get();
      return {
        schema: 1,
        profile: JSON.parse(JSON.stringify(s.profile)),
        teeth: JSON.parse(JSON.stringify(s.teeth)),
        treatments: JSON.parse(JSON.stringify(s.treatments)),
        visits: JSON.parse(JSON.stringify(s.visits)),
        currentVisit: s.currentVisit,
        gumStyle: s.gumStyle,
      };
    },
    applyStateSnapshot(snap) {
      if (typeof snap === 'string') { try { snap = JSON.parse(snap); } catch { return false; } }
      if (!snap || typeof snap !== 'object') return false;

      if (snap.saved && typeof snap.saved === 'object') {
        const saved = snap.saved;
        const current = { ...snap };
        delete current.saved;

        const savedTreatments = Array.isArray(saved.treatments)
          ? saved.treatments.filter((t) => t && VALID_TREATMENT_TYPES.has(t.type))
          : [];
        const savedMap = new Map(savedTreatments.map((t) => [t.id, t]));

        actions.applyStateSnapshot(saved);

        if (Array.isArray(current.treatments)) {
          const mergedTreatments = current.treatments
            .filter((t) => t && VALID_TREATMENT_TYPES.has(t.type))
            .map((t) => {
              const prev = savedMap.get(t.id);
              if (prev && 'visit' in prev) return { ...t, visit: prev.visit };
              return t;
            });
          const seenIds = new Set(mergedTreatments.map((t) => t.id));
          for (const st of savedTreatments) {
            if (st.origin !== 'chart' && !seenIds.has(st.id)) {
              mergedTreatments.push(st);
            }
          }
          current.treatments = mergedTreatments;
        }
        return actions.applyStateSnapshot(current);
      }

      const patch = {};
      if (MODES.includes(snap.mode)) patch.mode = snap.mode;
      if ('explode' in snap) patch.explode = clamp01(snap.explode);
      if ('jawOpen' in snap) patch.jawOpen = clamp01(snap.jawOpen);
      if (QUALITY_LEVELS.includes(snap.quality)) patch.quality = snap.quality;
      if (snap.gumStyle === 'solid' || snap.gumStyle === 'glass') patch.gumStyle = new URLSearchParams(window.location.search).get('app') === '1' ? 'glass' : snap.gumStyle;
      if ('selectedId' in snap && (snap.selectedId === null || exists(snap.selectedId))) patch.selectedId = snap.selectedId;
      if (snap.layers && typeof snap.layers === 'object') {
        patch.layers = {};
        for (const k of Object.keys(store.get().layers)) if (k in snap.layers) patch.layers[k] = !!snap.layers[k];
      }
      if (snap.profile && typeof snap.profile === 'object') {
        patch.profile = { ...store.get().profile, ...snap.profile };
        if ('archWidth' in snap.profile) patch.profile.archWidth = clamp(snap.profile.archWidth, 0.5, 2.0, 1);
        if ('archDepth' in snap.profile) patch.profile.archDepth = clamp(snap.profile.archDepth, 0.5, 2.0, 1);
      }
      if (snap.visits && Array.isArray(snap.visits)) {
        patch.visits = snap.visits.map((v, idx) => {
          if (typeof v === 'string') return { id: idx + 1, label: v };
          return { id: idx + 1, ...v };
        });
      }
      const visitsLen = (patch.visits ?? store.get().visits).length;
      if ('currentVisit' in snap) {
        patch.currentVisit = clamp(Math.round(Number(snap.currentVisit) || 0), 0, visitsLen, 0);
      }
      if (snap.treatments && Array.isArray(snap.treatments)) {
        patch.treatments = snap.treatments.filter((t) => t && typeof t === 'object' && VALID_TREATMENT_TYPES.has(t.type));
      }
      if (snap.teeth && typeof snap.teeth === 'object') {
        patch.teeth = {};
        const curTeeth = store.get().teeth;
        for (const [fdi, t] of Object.entries(snap.teeth)) {
          if (!FDI_LIST.includes(+fdi) || !t) continue;
          patch.teeth[fdi] = sanitizeToothPatch(t, curTeeth[fdi]);
        }
      }
      store.set(patch);
      return true;
    },
  };
  return actions;
}
