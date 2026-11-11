// Generates scene_manifest.json - the single contract shared by the Blender
// build (blender/*.py) and the Three.js viewer (src/*).
//
//   node tools/gen_manifest.mjs            -> writes scene_manifest.json
//   node tools/gen_manifest.mjs --report   -> also prints arch widths
//
// World space (viewer / glTF): units = millimetres,
//   +X = patient's left, +Y = up, +Z = anterior (towards the lips).
// Occlusal plane is y = 0. Upper teeth hang down to it, lower teeth rise to it.
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const OUT = join(here, '..', 'scene_manifest.json');
const rad = (d) => (d * Math.PI) / 180;
const r3 = (n) => Math.round(n * 1000) / 1000;
const v3 = (v) => v.map(r3);

// ---------------------------------------------------------------- anatomy
// Average adult dimensions (Wheeler). md = mesio-distal crown width,
// bl = bucco-lingual crown width, cerv* = the same at the neck (CEJ).
const TYPES = {
  U1: { name: 'Central Incisor', cls: 'incisor', crownHeight: 10.5, rootLength: 13.0, md: 8.5, bl: 7.0, cervMd: 7.0, cervBl: 6.0, roots: 1, cusps: 0 },
  U2: { name: 'Lateral Incisor', cls: 'incisor', crownHeight: 9.0, rootLength: 13.0, md: 6.5, bl: 6.0, cervMd: 5.0, cervBl: 5.0, roots: 1, cusps: 0 },
  U3: { name: 'Canine', cls: 'canine', crownHeight: 10.0, rootLength: 17.0, md: 7.5, bl: 8.0, cervMd: 5.5, cervBl: 7.0, roots: 1, cusps: 1 },
  U4: { name: 'First Premolar', cls: 'premolar', crownHeight: 8.5, rootLength: 14.0, md: 7.0, bl: 9.0, cervMd: 5.0, cervBl: 8.0, roots: 2, cusps: 2 },
  U5: { name: 'Second Premolar', cls: 'premolar', crownHeight: 8.5, rootLength: 14.0, md: 7.0, bl: 9.0, cervMd: 5.0, cervBl: 8.0, roots: 1, cusps: 2 },
  U6: { name: 'First Molar', cls: 'molar', crownHeight: 7.5, rootLength: 12.5, md: 10.0, bl: 11.0, cervMd: 8.0, cervBl: 10.0, roots: 3, cusps: 4 },
  U7: { name: 'Second Molar', cls: 'molar', crownHeight: 7.0, rootLength: 11.5, md: 9.0, bl: 11.0, cervMd: 7.0, cervBl: 10.0, roots: 3, cusps: 4 },
  U8: { name: 'Third Molar', cls: 'molar', crownHeight: 6.5, rootLength: 11.0, md: 8.5, bl: 10.0, cervMd: 6.5, cervBl: 9.5, roots: 3, cusps: 3 },
  L1: { name: 'Central Incisor', cls: 'incisor', crownHeight: 9.0, rootLength: 12.5, md: 5.0, bl: 6.0, cervMd: 3.5, cervBl: 5.3, roots: 1, cusps: 0 },
  L2: { name: 'Lateral Incisor', cls: 'incisor', crownHeight: 9.5, rootLength: 14.0, md: 5.5, bl: 6.5, cervMd: 4.0, cervBl: 5.8, roots: 1, cusps: 0 },
  L3: { name: 'Canine', cls: 'canine', crownHeight: 11.0, rootLength: 16.0, md: 7.0, bl: 7.5, cervMd: 5.5, cervBl: 7.0, roots: 1, cusps: 1 },
  L4: { name: 'First Premolar', cls: 'premolar', crownHeight: 8.5, rootLength: 14.0, md: 7.0, bl: 7.5, cervMd: 5.0, cervBl: 6.5, roots: 1, cusps: 2 },
  L5: { name: 'Second Premolar', cls: 'premolar', crownHeight: 8.0, rootLength: 14.5, md: 7.0, bl: 8.0, cervMd: 5.0, cervBl: 7.0, roots: 1, cusps: 3 },
  L6: { name: 'First Molar', cls: 'molar', crownHeight: 7.5, rootLength: 14.0, md: 11.0, bl: 10.5, cervMd: 9.0, cervBl: 9.0, roots: 2, cusps: 5 },
  L7: { name: 'Second Molar', cls: 'molar', crownHeight: 7.0, rootLength: 13.0, md: 10.5, bl: 10.0, cervMd: 8.0, cervBl: 9.0, roots: 2, cusps: 4 },
  L8: { name: 'Third Molar', cls: 'molar', crownHeight: 7.0, rootLength: 11.0, md: 10.0, bl: 9.5, cervMd: 7.5, cervBl: 9.0, roots: 2, cusps: 4 },
};

// Long-axis inclination per position 1..8 (degrees).
// torque: + = crown leans towards the lips/cheek. tip: + = crown leans mesially.
const TORQUE = { U: [20, 18, 12, 4, 3, 4, 4, 6], L: [16, 15, 9, 2, -2, -8, -10, -12] };
const TIP = { U: [3, 6, 7, 2, 2, 3, 3, 2], L: [1, 2, 4, 2, 2, 2, 3, 4] };
// World y of the incisal edge / highest cusp tip (overbite 2 mm in front).
const TIP_Y = { U: [-1.2, -0.6, -1.0, -0.8, -0.8, -0.8, -0.6, -0.2], L: [0.8, 0.8, 0.9, 0.6, 0.6, 0.6, 0.5, 0.3] };

// Arch form = quarter super-ellipse through the CROWN CENTRES (60 % of crown
// height), then straight back past the widest point.
//   x = a * sin(u)^(2/p),  z = zFront - b * (1 - cos(u)^(2/p)),  u in [0, pi/2]
const ARCH = {
  U: { a: 25.4, b: 53.0, p: 2.3, zFront: 28.0 },
  L: { a: 23.4, b: 51.0, p: 2.25, zFront: 24.6 },
};
const CROWN_CENTRE_FRAC = 0.6;

// ---------------------------------------------------------------- math
const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const mul = (a, k) => [a[0] * k, a[1] * k, a[2] * k];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const norm = (a) => { const l = Math.hypot(...a) || 1; return [a[0] / l, a[1] / l, a[2] / l]; };
// 3x3 as columns [c0, c1, c2]
const matMul = (A, B) => B.map((c) => add(add(mul(A[0], c[0]), mul(A[1], c[1])), mul(A[2], c[2])));
const matVec = (A, v) => add(add(mul(A[0], v[0]), mul(A[1], v[1])), mul(A[2], v[2]));
const rotX = (t) => [[1, 0, 0], [0, Math.cos(t), Math.sin(t)], [0, -Math.sin(t), Math.cos(t)]];
const rotZ = (t) => [[Math.cos(t), Math.sin(t), 0], [-Math.sin(t), Math.cos(t), 0], [0, 0, 1]];
function quatFromCols(c) {
  const m00 = c[0][0], m10 = c[0][1], m20 = c[0][2];
  const m01 = c[1][0], m11 = c[1][1], m21 = c[1][2];
  const m02 = c[2][0], m12 = c[2][1], m22 = c[2][2];
  const tr = m00 + m11 + m22; let x, y, z, w;
  if (tr > 0) { const s = Math.sqrt(tr + 1) * 2; w = s / 4; x = (m21 - m12) / s; y = (m02 - m20) / s; z = (m10 - m01) / s; }
  else if (m00 > m11 && m00 > m22) { const s = Math.sqrt(1 + m00 - m11 - m22) * 2; w = (m21 - m12) / s; x = s / 4; y = (m01 + m10) / s; z = (m02 + m20) / s; }
  else if (m11 > m22) { const s = Math.sqrt(1 + m11 - m00 - m22) * 2; w = (m02 - m20) / s; x = (m01 + m10) / s; y = s / 4; z = (m12 + m21) / s; }
  else { const s = Math.sqrt(1 + m22 - m00 - m11) * 2; w = (m10 - m01) / s; x = (m02 + m20) / s; y = (m12 + m21) / s; z = s / 4; }
  return [x, y, z, w];
}
// viewer (x, y, z) -> Blender (x, -z, y)
const toBlender = (v) => [v[0], -v[2], v[1]];

// ---------------------------------------------------------------- arch curve
function buildCurve({ a, b, p, zFront }) {
  const pts = []; const N = 6000;
  for (let i = 0; i <= N; i++) {
    const u = (i / N) * (Math.PI / 2);
    pts.push([a * Math.pow(Math.sin(u), 2 / p), zFront - b * (1 - Math.pow(Math.cos(u), 2 / p))]);
  }
  const zEnd = zFront - b;
  for (let i = 1; i <= 400; i++) pts.push([a, zEnd - i * 0.05]); // straight tail, 20 mm
  const s = [0];
  for (let i = 1; i < pts.length; i++) s.push(s[i - 1] + Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]));
  const at = (len) => {
    let lo = 0, hi = s.length - 1;
    while (hi - lo > 1) { const m = (lo + hi) >> 1; if (s[m] < len) lo = m; else hi = m; }
    const t = (len - s[lo]) / (s[hi] - s[lo] || 1);
    return [pts[lo][0] + (pts[hi][0] - pts[lo][0]) * t, pts[lo][1] + (pts[hi][1] - pts[lo][1]) * t];
  };
  return {
    point: at,
    tangent: (len) => { const p0 = at(Math.max(0, len - 0.4)), p1 = at(len + 0.4); return norm([p1[0] - p0[0], 0, p1[1] - p0[1]]); },
  };
}

// ---------------------------------------------------------------- parts
const QUADRANTS = [
  { q: 1, arch: 'U', side: -1, label: 'Upper Right' },
  { q: 2, arch: 'U', side: 1, label: 'Upper Left' },
  { q: 3, arch: 'L', side: 1, label: 'Lower Left' },
  { q: 4, arch: 'L', side: -1, label: 'Lower Right' },
];
const ARCH_EXPLODE = { U: [0, 22, 0], L: [0, -22, 0] };
const ACTIONS = {
  incisor: ['filling', 'bonding', 'veneer', 'crown', 'rct', 'extraction', 'implant', 'bridge', 'whitening'],
  canine: ['filling', 'bonding', 'veneer', 'crown', 'rct', 'extraction', 'implant', 'bridge', 'whitening'],
  premolar: ['filling', 'sealant', 'crown', 'rct', 'extraction', 'implant', 'bridge', 'whitening'],
  molar: ['filling', 'sealant', 'crown', 'rct', 'extraction', 'implant', 'bridge'],
};

const parts = [];
const report = [];
for (const quad of QUADRANTS) {
  const curve = buildCurve(ARCH[quad.arch]);
  let s = 0;
  for (let i = 1; i <= 8; i++) {
    const typeId = `${quad.arch}${i}`; const T = TYPES[typeId];
    const sc = s + T.md / 2; s += T.md;
    const [cx, cz] = curve.point(sc);
    const t = curve.tangent(sc);                       // distal direction on the +X side
    const tangentDistal = [t[0] * quad.side, 0, t[2]];
    const facial = norm([-t[2] * quad.side, 0, t[0]]); // outward normal
    const coronal = quad.arch === 'U' ? [0, -1, 0] : [0, 1, 0];
    const lx = norm(cross(coronal, facial));           // right-handed local X
    const mesialSign = dot(lx, tangentDistal) < 0 ? 1 : -1;
    const base = [lx, coronal, facial];
    const torque = rad(TORQUE[quad.arch][i - 1]);
    const tip = rad(TIP[quad.arch][i - 1]);
    const M = matMul(matMul(base, rotZ(-mesialSign * tip)), rotX(torque));
    const axis = matVec(M, [0, 1, 0]);                 // long axis, root -> crown
    const H = T.crownHeight;
    const tipY = TIP_Y[quad.arch][i - 1];
    // crown centre sits on the arch curve; tip sits at tipY
    const crownCentre = [cx * quad.side, tipY - axis[1] * H * (1 - CROWN_CENTRE_FRAC), cz];
    const anchor = sub(crownCentre, mul(axis, H * CROWN_CENTRE_FRAC)); // cervical centre = node origin
    const fdi = quad.q * 10 + i;
    const archEx = ARCH_EXPLODE[quad.arch];
    const explode = add(add(mul(facial, 8), mul(coronal, 12)), archEx);
    const bcols = [toBlender(M[0]), toBlender(mul(M[2], -1)), toBlender(M[1])];
    const bpos = toBlender(anchor);
    parts.push({
      nodeId: `tooth_${fdi}`,
      kind: 'tooth',
      source: 'glb',
      parent: quad.arch === 'U' ? 'arch_upper' : 'arch_lower',
      fdi, quadrant: quad.q, index: i, arch: quad.arch === 'U' ? 'upper' : 'lower', side: quad.side < 0 ? 'right' : 'left',
      typeId, toothClass: T.cls,
      displayName: `${quad.label} ${T.name}`,
      category: T.cls,
      position: v3(anchor),
      quaternion: quatFromCols(M).map((n) => Math.round(n * 1e6) / 1e6),
      mesialSign,
      frame: { tangentDistal: v3(tangentDistal), facial: v3(facial), coronal, longAxis: v3(axis) },
      dims: { crownHeight: T.crownHeight, rootLength: T.rootLength, md: T.md, bl: T.bl, cervMd: T.cervMd, cervBl: T.cervBl, roots: T.roots, cusps: T.cusps },
      inclination: { torqueDeg: TORQUE[quad.arch][i - 1], tipDeg: TIP[quad.arch][i - 1] },
      // Blender world matrix, row-major 4x4 (Blender: X = patient left, -Y = anterior, Z = up)
      blenderMatrix: [0, 1, 2].map((r) => [r3(bcols[0][r]), r3(bcols[1][r]), r3(bcols[2][r]), r3(bpos[r])]).concat([[0, 0, 0, 1]]),
      explodeVector: v3(explode),
      cameraFocusOffset: v3(add(mul(facial, 44), mul(coronal, 9))),
      children: [`pulp_${fdi}`],
      statusFlags: { status: 'normal', present: true },
      interactiveActions: ACTIONS[T.cls],
    });
    parts.push({
      nodeId: `pulp_${fdi}`, kind: 'pulp', source: 'glb', parent: `tooth_${fdi}`, fdi,
      displayName: `${quad.label} ${T.name} - pulp & canals`, category: 'pulp',
      position: [0, 0, 0], quaternion: [0, 0, 0, 1],
      explodeVector: [0, 0, 0], cameraFocusOffset: v3(add(mul(facial, 44), mul(coronal, 9))),
      statusFlags: { status: 'normal' }, interactiveActions: [],
    });
    report.push({ fdi, x: r3(crownCentre[0]), z: r3(crownCentre[2]), y: r3(anchor[1]) });
  }
}

const runtimePart = (nodeId, displayName, category, arch, k) => ({
  nodeId, kind: category, source: 'runtime', parent: arch === 'U' ? 'arch_upper' : 'arch_lower',
  arch: arch === 'U' ? 'upper' : 'lower', displayName, category,
  position: [0, 0, 0], quaternion: [0, 0, 0, 1],
  explodeVector: mul(ARCH_EXPLODE[arch], k), cameraFocusOffset: [0, arch === 'U' ? -18 : 18, 95],
  statusFlags: { status: 'normal' }, interactiveActions: [],
});
parts.push(runtimePart('gum_upper', 'Upper Gum', 'gum', 'U', 1));
parts.push(runtimePart('gum_lower', 'Lower Gum', 'gum', 'L', 1));
parts.push(runtimePart('bone_upper', 'Upper Jaw Bone', 'bone', 'U', 1.45));
parts.push(runtimePart('bone_lower', 'Lower Jaw Bone', 'bone', 'L', 1.45));

const manifest = {
  version: 1,
  subject: 'Human permanent dentition - 32 FDI teeth, pulp, gums, jaw bone',
  units: 'mm',
  axes: { x: 'patient left (+)', y: 'up (+)', z: 'anterior (+)', occlusalPlane: 'y = 0' },
  pivotRule: 'Every tooth node origin is the cervical centre: the point on the long axis at the cemento-enamel junction (CEJ). The root goes to local -Y, the crown to local +Y.',
  localFrame: {
    viewer: '+Y = coronal (root -> crown), +Z = facial (lip/cheek side), +X = mesial when mesialSign = +1, distal when -1',
    blender: '+Z = coronal, -Y = facial, +X = mesial when mesialSign = +1, distal when -1 (glTF export with +Y up converts this to the viewer frame)',
    crownRegion: 'local y in [0, dims.crownHeight]; root region local y in [-dims.rootLength, 0]',
  },
  archFormula: {
    form: 'x = a*sin(u)^(2/p); z = zFront - b*(1 - cos(u)^(2/p)); u in [0, pi/2]; straight tail after the widest point',
    passesThrough: `crown centre at ${CROWN_CENTRE_FRAC} of crown height`,
    placement: 'tooth i sits at arc length sum(md of teeth before it) + md/2 from the midline; right side is the mirror (x -> -x)',
    upper: ARCH.U, lower: ARCH.L,
  },
  jawHinge: { appliesTo: 'arch_lower', point: [0, 32, -62], axis: [1, 0, 0], maxOpenDeg: 26 },
  hierarchy: {
    subject: {
      arch_upper: ['gum_upper', 'bone_upper', ...parts.filter((p) => p.kind === 'tooth' && p.arch === 'upper').map((p) => p.nodeId)],
      // jaw_hinge is an empty at jawHinge.point; rotating it about X opens the lower jaw.
      // arch_lower is its child and keeps an identity WORLD transform when the jaw is closed.
      jaw_hinge: { arch_lower: ['gum_lower', 'bone_lower', ...parts.filter((p) => p.kind === 'tooth' && p.arch === 'lower').map((p) => p.nodeId)] },
      templates: ['tpl_implant_fixture', 'tpl_implant_abutment', 'tpl_healing_cap', 'tpl_bracket', 'tpl_post'],
    },
  },
  toothTypes: TYPES,
  templates: [
    { nodeId: 'tpl_implant_fixture', displayName: 'Implant fixture', note: 'Threaded titanium screw. Origin at the platform centre (top), body along -Y (viewer) / -Z (Blender). Length 11.5, platform diameter 4.1.' },
    { nodeId: 'tpl_implant_abutment', displayName: 'Implant abutment', note: 'Tapered titanium post. Origin at its base centre, rises along +Y (viewer). Height 5.5, base diameter 4.1, top diameter 2.8, small collar.' },
    { nodeId: 'tpl_healing_cap', displayName: 'Healing cap', note: 'Short dome cap. Origin at base centre, height 3, diameter 4.6.' },
    { nodeId: 'tpl_bracket', displayName: 'Orthodontic bracket', note: 'Twin bracket with base pad, four tie wings and a horizontal archwire slot. Origin at the centre of the pad back face; pad lies in the local XY plane (viewer), bracket projects to +Z by 1.9. Pad 3.2 wide (X) by 2.8 tall (Y). Slot runs along X.' },
    { nodeId: 'tpl_post', displayName: 'Root canal post', note: 'Tapered fibre post. Origin at the top centre, runs along -Y (viewer). Length 9, top diameter 1.5, tip diameter 0.9.' },
  ],
  parts,
};

writeFileSync(OUT, JSON.stringify(manifest, null, 1));
console.log(`scene_manifest.json written: ${parts.length} parts`);
if (process.argv.includes('--report')) {
  const g = (f) => report.find((r) => r.fdi === f);
  console.log('upper intercanine (crown centres):', r3(2 * g(23).x), ' inter-M1:', r3(2 * g(26).x), ' inter-M2:', r3(2 * g(27).x));
  console.log('upper depth front -> M2:', r3(g(21).z - g(27).z), ' -> M3:', r3(g(21).z - g(28).z));
  console.log('lower intercanine:', r3(2 * g(33).x), ' inter-M1:', r3(2 * g(36).x), ' inter-M2:', r3(2 * g(37).x));
  console.log('lower depth front -> M2:', r3(g(31).z - g(37).z), ' -> M3:', r3(g(31).z - g(38).z));
  console.log('front z upper/lower crown centre:', g(21).z, g(31).z, ' M1 z upper/lower:', g(26).z, g(36).z);
  console.log('cervical y upper 11/13/16:', g(11).y, g(13).y, g(16).y, ' lower 41/43/46:', g(41).y, g(43).y, g(46).y);
}
