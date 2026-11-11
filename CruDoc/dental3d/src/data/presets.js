import { defaultToothState, defaultSnapshot, ALL_FDI } from '../state/schema.js';

export function makeFreshSnapshot() {
  const s = defaultSnapshot();
  for (const f of ALL_FDI) {
    s.teeth[f] = defaultToothState();
  }
  return s;
}

export const healthy = makeFreshSnapshot();

export const gap_stained_front = (() => {
  const snap = makeFreshSnapshot();
  snap.teeth[11] = {
    ...snap.teeth[11],
    shift: { md: -1.2, bl: 0, v: 0 },
    scale: { w: 0.9, h: 1 },
    shade: 'A35',
  };
  snap.teeth[21] = {
    ...snap.teeth[21],
    shift: { md: -1.2, bl: 0, v: 0 },
    scale: { w: 0.9, h: 1 },
    shade: 'A4',
    stain: 0.6,
  };
  snap.visits = [
    { id: 1, label: 'Visit 1 – caps' },
    { id: 2, label: 'Visit 2 – whitening' },
  ];
  snap.treatments = [
    { id: 't_crown_11', type: 'crown', teeth: [11], material: 'emax', visit: 1, status: 'planned', options: { shade: 'A1', shape: { w: 1.1, md: 1.2 } } },
    { id: 't_crown_21', type: 'crown', teeth: [21], material: 'emax', visit: 1, status: 'planned', options: { shade: 'A1', shape: { w: 1.1, md: 1.2 } } },
    { id: 't_whitening', type: 'whitening', teeth: [], arches: ['upper', 'lower'], visit: 2, status: 'planned', options: { targetShade: 'A1' } },
  ];
  snap.currentVisit = 0;
  return snap;
})();

export const missing_front = (() => {
  const snap = makeFreshSnapshot();
  snap.teeth[11] = { ...snap.teeth[11], present: false };
  snap.teeth[21] = { ...snap.teeth[21], rotate: { tip: 0, torque: 10, spin: 0 }, shift: { md: -1.5, bl: 0, v: 0 } };
  snap.teeth[12] = { ...snap.teeth[12], shift: { md: -1.0, bl: 0, v: 0 } };
  snap.teeth[41] = { ...snap.teeth[41], present: false };
  snap.teeth[31] = { ...snap.teeth[31], rotate: { tip: 8, torque: 0, spin: 0 } };
  snap.visits = [
    { id: 1, label: 'Visit 1 – implants placed' },
    { id: 2, label: 'Visit 2 – healing check' },
    { id: 3, label: 'Visit 3 – new teeth' },
  ];
  snap.treatments = [
    { id: 't_implant_11', type: 'implant', teeth: [11], material: 'zirconia', visit: 3, status: 'planned' },
    { id: 't_implant_41', type: 'implant', teeth: [41], material: 'zirconia', visit: 3, status: 'planned' },
    { id: 't_crown_21', type: 'crown', teeth: [21], visit: 3, status: 'planned', options: { shape: { md: 1.5, torque: -10 } } },
  ];
  snap.currentVisit = 0;
  return snap;
})();

export const crowding = (() => {
  const snap = makeFreshSnapshot();
  snap.profile.archWidth = 0.95;
  snap.teeth[41] = { ...snap.teeth[41], rotate: { tip: 0, torque: 0, spin: 18 }, shift: { md: 0, bl: 1.2, v: 0 } };
  snap.teeth[31] = { ...snap.teeth[31], rotate: { tip: 0, torque: 0, spin: -15 }, shift: { md: 0, bl: -1.0, v: 0 } };
  snap.teeth[42] = { ...snap.teeth[42], shift: { md: 0, bl: -1.5, v: 0 }, rotate: { tip: 0, torque: 0, spin: 10 } };
  snap.teeth[32] = { ...snap.teeth[32], rotate: { tip: 0, torque: 0, spin: -12 }, shift: { md: 0, bl: 0.8, v: 0 } };
  snap.teeth[12] = { ...snap.teeth[12], shift: { md: 0, bl: -1.8, v: 0 } };
  snap.teeth[22] = { ...snap.teeth[22], shift: { md: 0, bl: -1.5, v: 0 } };
  snap.teeth[13] = { ...snap.teeth[13], shift: { md: 0, bl: 1.5, v: -1.5 } };
  snap.visits = [
    { id: 1, label: 'Visit 1 – braces on' },
    { id: 2, label: 'Visit 2 – half way' },
    { id: 3, label: 'Visit 3 – braces off' },
  ];
  snap.treatments = [
    { id: 't_braces', type: 'braces', teeth: [], arches: ['upper', 'lower'], visit: 1, status: 'planned', options: { endVisit: 3 } },
    { id: 't_whitening', type: 'whitening', teeth: [], arches: ['upper', 'lower'], visit: 3, status: 'planned' },
  ];
  snap.currentVisit = 0;
  return snap;
})();

export const worn_gum_disease = (() => {
  const snap = makeFreshSnapshot();
  for (const f of [42, 41, 31, 32]) {
    snap.teeth[f] = {
      ...snap.teeth[f],
      wear: 1.5,
      recession: 2.5,
      calculus: 0.7,
      inflammation: 0.6,
      boneLoss: 2,
    };
  }
  snap.teeth[16] = { ...snap.teeth[16], recession: 2 };
  snap.teeth[26] = { ...snap.teeth[26], recession: 2 };
  snap.teeth[36] = { ...snap.teeth[36], conditions: [{ type: 'caries', surfaces: ['O', 'D'] }] };
  snap.teeth[46] = { ...snap.teeth[46], present: false };
  snap.visits = [
    { id: 1, label: 'Visit 1 – cleaning + filling' },
    { id: 2, label: 'Visit 2 – implant' },
    { id: 3, label: 'Visit 3 – new tooth' },
  ];
  snap.treatments = [
    { id: 't_scaling', type: 'scaling', teeth: [], arches: ['upper', 'lower'], visit: 1, status: 'planned' },
    { id: 't_filling_36', type: 'filling', teeth: [36], surfaces: ['O', 'D'], material: 'composite', visit: 1, status: 'planned' },
    { id: 't_implant_46', type: 'implant', teeth: [46], visit: 3, status: 'planned' },
  ];
  snap.currentVisit = 0;
  return snap;
})();

export const PRESET_LIST = [
  { id: 'healthy', label: 'Healthy', snapshot: healthy },
  { id: 'gap_stained_front', label: 'Gap & stained front', snapshot: gap_stained_front },
  { id: 'missing_front', label: 'Missing front', snapshot: missing_front },
  { id: 'crowding', label: 'Crowding', snapshot: crowding },
  { id: 'worn_gum_disease', label: 'Worn & gum disease', snapshot: worn_gum_disease },
];

export const PRESETS = {
  healthy,
  gap_stained_front,
  missing_front,
  crowding,
  worn_gum_disease,
};

