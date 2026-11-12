import * as THREE from 'three';
import { STATUS_COLORS, MATERIALS } from '../data/treatments.js';
import { createToothMaterial, setTint, NEUTRAL_LIGHT } from './toothMaterial.js';
import { createGhostMaterial, createPulpMaterial } from './materials.js';
import { effectiveTooth } from '../treatments/effective.js';

const SELECT = '#3B82F6';
const HOVER = '#93C5FD';
export const MODES = ['pbr', 'xray', 'heatmap'];

// Applies mode / selection / hover / status / layer state to materials and
// visibility. Called from the store subscriber; cheap enough to run in full.
export function createAppearance(registry, store, stage, gums) {
  const ghost = createGhostMaterial();
  const pulpMat = createPulpMaterial();
  const pulpSel = createPulpMaterial();
  pulpSel.color.set('#FF5A4F'); pulpSel.emissiveIntensity = 0.9;
  const pulpRct = createPulpMaterial();
  pulpRct.color.set(MATERIALS.guttaPercha.color);
  pulpRct.emissive.set(MATERIALS.guttaPercha.color);
  pulpRct.emissiveIntensity = 0.5;
  const white = new THREE.Color();

  const toothMats = new Map();
  for (const [fdi, obj] of registry.teeth) {
    const part = obj.userData.part;
    const hasColor = obj.userData.meshes.some((m) => m.geometry.attributes.color);
    const mat = createToothMaterial(part, { vertexColors: hasColor });
    toothMats.set(fdi, mat);
    for (const m of obj.userData.meshes) { m.material = mat; m.userData.natural = mat; }
  }
  for (const obj of registry.pulps.values()) {
    for (const m of obj.userData.meshes) { m.material = pulpMat; m.visible = false; }
  }
  const runtime = [...Object.values(gums.meshes)];
  for (const m of runtime) m.userData.natural = m.material;

  function heatColor(t, selected, hovered) {
    let hex = selected ? STATUS_COLORS.selected : (t.statusColor || STATUS_COLORS[t.status] || NEUTRAL_LIGHT);
    if (!hex) hex = NEUTRAL_LIGHT;
    if (hovered && !selected) { white.set(hex).lerp(new THREE.Color('#FFFFFF'), 0.35); hex = '#' + white.getHexString(); }
    return hex;
  }

  function refresh() {
    const s = store.get();
    const L = s.layers;
    const high = s.quality === 'high';
    registry.nodes.arch_upper.visible = L.upper;
    registry.nodes.arch_lower.visible = L.lower;
    let ghostActive = false;
    const xray = s.mode === 'xray';

    for (const [fdi, obj] of registry.teeth) {
      const t = effectiveTooth(s, fdi) || s.teeth[fdi];
      const id = obj.name;
      const sel = s.selectedId === id;
      const hov = s.hoveredId === id && !sel;
      obj.visible = t.present;
      const mat = toothMats.get(fdi);
      const pulp = registry.pulps.get(fdi);
      const wasTransparent = mat.transparent;
      mat.transparent = false; mat.opacity = 1; mat.depthWrite = true;
      mat.emissive.set('#000000'); mat.emissiveIntensity = 1;
      let useGhost = false;
      if (s.mode === 'heatmap') {
        setTint(mat, heatColor(t, sel, hov), 1);
      } else if (xray && !sel) {
        useGhost = true;
      } else if (xray && sel) {
        setTint(mat, SELECT, 0.18);
        mat.transparent = true; mat.opacity = 0.5;   // glassy, so the pulp inside is visible
      } else {
        setTint(mat, sel ? SELECT : HOVER, sel ? 0.45 : hov ? 0.3 : 0);
      }
      if (sel && high) { mat.emissive.set('#4F8EF7'); mat.emissiveIntensity = 6.0; }
      if (wasTransparent !== mat.transparent) mat.needsUpdate = true; // OPAQUE define depends on it
      for (const m of obj.userData.meshes) m.material = useGhost ? ghost : mat;
      if (useGhost) ghostActive = true;
      if (pulp) {
        pulp.visible = xray && t.present;
        const targetPulpMat = pulp.userData.matOverride || (sel ? pulpSel : (t.rctDone ? pulpRct : pulpMat));
        for (const m of pulp.userData.meshes) m.material = targetPulpMat;
      }
    }

    for (const m of runtime) {
      const id = m.name;
      const isGum = m.userData.kind === 'gum';
      m.visible = isGum ? L.gums : (L.bone && (!L.gums || xray));
      const sel = s.selectedId === id;
      const hov = s.hoveredId === id && !sel;
      const useGhost = xray && !sel;
      m.material = useGhost ? ghost : m.userData.natural;
      if (useGhost) ghostActive = true;
      const nat = m.userData.natural;
      if (nat.emissive) {
        nat.emissive.set(sel ? SELECT : hov ? HOVER : '#000000');
        nat.emissiveIntensity = sel ? 0.28 : hov ? 0.18 : 1;
      }
    }
    stage.flags.ghost = ghostActive;
    stage.invalidate();
  }

  return { refresh, ghost, toothMats };
}
