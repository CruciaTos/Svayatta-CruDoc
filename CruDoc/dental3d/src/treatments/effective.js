import * as THREE from 'three';
import { SURFACES, SHADES, MATERIALS } from '../data/treatments.js';

export const ARCH_ORDER = {
  upper: [18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28],
  lower: [48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38],
};

export const archOfFdi = (fdi) => (ARCH_ORDER.upper.includes(+fdi) ? 'upper' : 'lower');

const clamp = (v, min, max) => Math.min(max, Math.max(min, v));

export function effectiveTooth(state, fdi) {
  fdi = +fdi;
  const raw = state?.teeth?.[fdi];
  if (!raw) return null;

  // Clone tooth state deeply
  const t = JSON.parse(JSON.stringify(raw));
  if (!t.shift) t.shift = { md: 0, bl: 0, v: 0 };
  if (!t.rotate) t.rotate = { tip: 0, torque: 0, spin: 0 };
  if (!t.scale) t.scale = { w: 1, h: 1 };

  const currentVisit = state.currentVisit ?? 0;
  const arch = archOfFdi(fdi);
  const profile = state.profile || { baseShade: 'A2' };

  // Track surface states: 5 surfaces M, O, D, B, L
  const surfCaries = [0, 0, 0, 0, 0];
  const surfFill = Array.from({ length: 5 }, () => ({ r: 0, g: 0, b: 0, a: 0, metal: 0 }));

  // Check initial conditions
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

  // Treatment flags for visuals
  t.rctDone = false;
  t.crowned = false;
  t.veneer = false;
  t.implant = false;
  t.pontic = false;
  t.brackets = false;

  const treatments = Array.isArray(state.treatments) ? state.treatments : [];
  // The explainer shows one treatment before / after its result: `preview` overrides when it counts.
  const pv = state.preview || null;
  const inEffectOf = (tr) => (pv && pv.id === tr.id
    ? !!pv.on
    : tr.status === 'completed' || (tr.visit != null && tr.visit <= currentVisit));

  // Pass 1: Orthodontic alignment (braces)
  for (const tr of treatments) {
    if (!tr) continue;
    if (!inEffectOf(tr)) continue;

    const includesArch = Array.isArray(tr.arches) ? tr.arches.includes(arch) : (!tr.teeth || !tr.teeth.length);
    if (tr.type === 'braces' && includesArch) {
      const visit = tr.visit ?? 1;
      const endVisit = tr.options?.endVisit ?? (visit + 2);
      const span = endVisit - visit + 1;
      const previewing = pv && pv.id === tr.id;
      const progress = previewing
        ? clamp(pv.progress ?? 0, 0, 1)
        : clamp((currentVisit - visit + 1) / (span || 1), 0, 1);
      const factor = 1 - progress;

      t.shift.md *= factor;
      t.shift.bl *= factor;
      t.shift.v *= factor;
      t.rotate.tip *= factor;
      t.rotate.torque *= factor;
      t.rotate.spin *= factor;

      if (previewing ? pv.brackets !== false : (visit <= currentVisit && currentVisit < endVisit)) {
        t.brackets = true;
      }
    }
  }

  // Pass 2: Tooth-specific & arch treatments
  for (const tr of treatments) {
    if (!tr) continue;
    if (!inEffectOf(tr)) continue;

    const includesTooth = Array.isArray(tr.teeth) && tr.teeth.map(Number).includes(fdi);
    const includesArch = Array.isArray(tr.arches) ? tr.arches.includes(arch) : (!tr.teeth || !tr.teeth.length);

    // Scaling
    if (tr.type === 'scaling' && (includesArch || includesTooth)) {
      t.calculus = 0;
      t.inflammation = 0;
    }

    // Extraction
    if (tr.type === 'extraction' && includesTooth) {
      t.present = false;
    }

    // Root canal treatment
    if (tr.type === 'rct' && includesTooth) {
      t.conditions = (t.conditions || []).filter((c) => c.type !== 'abscess');
      t.rctDone = true;
    }

    // Filling
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

    // Crown
    if (tr.type === 'crown' && includesTooth) {
      t.crowned = true;
      t.crownMaterial = tr.material || 'emax';
      t.shade = tr.options?.shade ?? 'A1';
      t.stain = 0;
      t.chip = 0;
      t.wear = 0;
      if (tr.options?.shape) {
        if ('w' in tr.options.shape) t.scale.w *= tr.options.shape.w;
        if ('md' in tr.options.shape) t.shift.md += tr.options.shape.md;
        if ('torque' in tr.options.shape) t.rotate.torque += tr.options.shape.torque;
      }
    }

    // Veneer
    if (tr.type === 'veneer' && includesTooth) {
      t.veneer = true;
      t.veneerMaterial = tr.material || 'emax';
      t.shade = tr.options?.shade ?? 'A1';
      t.stain = 0;
      t.chip = 0;
      t.wear = 0;
      if (tr.options?.shape) {
        if ('w' in tr.options.shape) t.scale.w *= tr.options.shape.w;
        if ('md' in tr.options.shape) t.shift.md += tr.options.shape.md;
        if ('torque' in tr.options.shape) t.rotate.torque += tr.options.shape.torque;
      }
    }

    // Implant
    if (tr.type === 'implant' && includesTooth) {
      t.present = true;
      t.implant = true;
      t.implantMaterial = tr.material || 'zirconia';
      t.shade = tr.options?.shade ?? 'A1';
      t.stain = 0;
      t.chip = 0;
      t.wear = 0;
    }

    // Bridge
    if (tr.type === 'bridge' && Array.isArray(tr.teeth) && tr.teeth.length >= 2) {
      const bridgeTeeth = tr.teeth.map(Number);
      const toothIdx = bridgeTeeth.indexOf(fdi);
      if (toothIdx >= 0) {
        if (toothIdx === 0 || toothIdx === bridgeTeeth.length - 1) {
          t.crowned = true;
          t.crownMaterial = tr.material || 'zirconia';
          t.shade = tr.options?.shade ?? 'A1';
          t.stain = 0;
          t.chip = 0;
          t.wear = 0;
        } else {
          t.pontic = true;
          t.present = true;
          t.crownMaterial = tr.material || 'zirconia';
          t.shade = tr.options?.shade ?? 'A1';
          t.stain = 0;
          t.chip = 0;
          t.wear = 0;
        }
      }
    }

    // Whitening (only if not crowned and not implant)
    if (tr.type === 'whitening' && (includesArch || includesTooth)) {
      if (!t.crowned && !t.implant && !t.pontic && !t.veneer) {
        t.shade = tr.options?.targetShade ?? 'BL3';
      }
    }
  }

  t.surfCaries = surfCaries;
  t.surfFill = surfFill;
  return t;
}
