import * as THREE from 'three';
import { SURFACES, SHADES, MATERIALS } from '../data/treatments.js';

export const ARCH_ORDER = {
  upper: [18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28],
  lower: [48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38],
};

export const archOfFdi = (fdi) => (ARCH_ORDER.upper.includes(+fdi) ? 'upper' : 'lower');

export function effectiveTooth(state, fdi) {
  fdi = +fdi;
  const raw = state?.teeth?.[fdi];
  if (!raw) return null;

  const t = JSON.parse(JSON.stringify(raw));
  const currentVisit = state.currentVisit ?? 0;
  const arch = archOfFdi(fdi);
  const profile = state.profile || { baseShade: 'A2' };

  const surfCaries = [0, 0, 0, 0, 0];
  const surfFill = Array.from({ length: 5 }, () => ({ r: 0, g: 0, b: 0, a: 0, metal: 0 }));

  if (Array.isArray(t.conditions)) {
    for (const c of t.conditions) {
      if (c && c.type === 'caries') {
        const surfs = (Array.isArray(c.surfaces) && c.surfaces.length) ? c.surfaces : ['O'];
        for (const s of surfs) {
          const idx = SURFACES.indexOf(s);
          if (idx >= 0) surfCaries[idx] = 1.0;
        }
      }
    }
  }

  const treatments = Array.isArray(state.treatments) ? state.treatments : [];
  for (const tr of treatments) {
    if (!tr) continue;
    const inEffect = tr.status === 'completed' || (tr.visit != null && tr.visit <= currentVisit);
    if (!inEffect) continue;

    const includesTooth = Array.isArray(tr.teeth) && tr.teeth.map(Number).includes(fdi);
    const includesArch = Array.isArray(tr.arches) && tr.arches.includes(arch);
    if (!includesTooth && !includesArch) continue;

    if (tr.type === 'filling' && includesTooth) {
      const surfs = (Array.isArray(tr.surfaces) && tr.surfaces.length) ? tr.surfaces : ['O'];
      const matKey = tr.material || 'composite';
      const matInfo = MATERIALS[matKey] || MATERIALS.composite;
      let fillCol;
      const metal = matInfo.metalness || 0;

      if (matInfo.color) {
        fillCol = new THREE.Color(matInfo.color);
      } else {
        const toothShadeKey = t.shade ?? profile.baseShade ?? 'A2';
        const hex = SHADES[toothShadeKey] || (/^#[0-9a-f]{6}$/i.test(toothShadeKey) ? toothShadeKey : SHADES.A2);
        fillCol = new THREE.Color(hex).multiplyScalar(1.04);
      }

      for (const s of surfs) {
        const idx = SURFACES.indexOf(s);
        if (idx >= 0) {
          surfCaries[idx] = 0.0;
          surfFill[idx] = { r: fillCol.r, g: fillCol.g, b: fillCol.b, a: 1.0, metal };
        }
      }
    }
  }

  t.surfCaries = surfCaries;
  t.surfFill = surfFill;
  return t;
}
