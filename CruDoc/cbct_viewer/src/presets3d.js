// The 3D looks, one family per kind of scan. Everything here is plain data in
// REAL units (meta.values / meta.landmarks, or Hounsfield units for CT), so it
// can be unit-tested without a GPU; view3d.js turns a look into vtk settings.
//
// meta.kind: 'dental' (CBCT of jaws; also the fallback when the packer wrote no
// kind), 'ct' (medical CT in Hounsfield units), 'mr' (no fixed units).

const hex = (h) => [parseInt(h.slice(1, 3), 16) / 255, parseInt(h.slice(3, 5), 16) / 255, parseInt(h.slice(5, 7), 16) / 255];
const IVORY_LOW = hex('#C8B48C');
const IVORY = hex('#ECE1C9');
const ENAMEL = hex('#F3EEE4');
const GLASS_BONE = hex('#A99F8C');
const SKIN = hex('#D9A58A');
const MUSCLE = hex('#B4614A');
const LUNG = hex('#A9C7DE');
const GREY_LOW = hex('#8E8A84');
const GREY_HIGH = hex('#EDEAE4');

const FAMILIES = {
  dental: [
    ['bone', 'Bone'],
    ['teeth', 'Teeth'],
    ['roots', 'Teeth in bone'],
    ['skinBone', 'Skin + bone'],
    ['xray', 'X-ray'],
    ['mip', 'MIP'],
  ],
  ct: [
    ['bone', 'Bone'],
    ['skin', 'Skin'],
    ['muscle', 'Muscle + bone'],
    ['lungs', 'Lungs'],
    ['xray', 'X-ray'],
    ['mip', 'MIP'],
  ],
  mr: [
    ['tissue', 'Tissue'],
    ['mip', 'MIP'],
  ],
};

export function scanKind(meta) {
  const k = meta && meta.kind;
  return k === 'ct' || k === 'mr' ? k : 'dental';
}

export const presetsFor = (meta) => FAMILIES[scanKind(meta)];

export function presetLabel(meta, id) {
  const hit = presetsFor(meta).find(([k]) => k === id);
  return hit ? hit[1] : '';
}

// A saved or default preset that this kind of scan does not have falls back to its first.
export function validPreset(meta, id) {
  const list = presetsFor(meta);
  return list.some(([k]) => k === id) ? id : list[0][0];
}

const LO = -Infinity; // "the lowest stored value"
const HI = Infinity; // "the highest stored value"

// A look: { blend: 'composite' | 'mip' | 'mean', shade, color: [[x, [r,g,b]]...],
// alpha: [[x, a]...], rampStart }. x rises along each list. `rampStart` is the
// value where the picture starts to be solid (click-to-place stops there).
// `solid` (0..1) is the first-open "solidify" factor.
// Most looks also carry `surfaces`: [{ iso, color, opacity }], outer first. The
// 3D view then draws one mesh per entry instead of casting rays (surface.js);
// the ray-cast fields stay for the looks and tools that need the voxels.
export function buildLook(meta, { preset, threshold = 0, opacity = 100 }, solid = 1) {
  const L = meta.landmarks;
  const kind = scanKind(meta);
  const id = validPreset(meta, preset);
  const peak = Math.min(1, 0.85 * (opacity / 100) * solid);
  const op = Math.min(1, (opacity / 100) * solid); // a mesh's own opacity
  const t = threshold;
  const mesh = (iso, color, share = 1) => ({ iso, color, opacity: op * share });
  const withSurfaces = (look, ...surfaces) => ({ ...look, surfaces });

  if (id === 'xray' || id === 'mip') {
    const xray = id === 'xray';
    const win = (meta.presets && meta.presets.bone) || { low: L.air, high: L.teeth };
    const a = xray ? win.low : L.soft;
    const b = Math.max(xray ? win.high : meta.values.max, a + 1);
    return {
      blend: xray ? 'mean' : 'mip',
      shade: false,
      color: [[LO, [0, 0, 0]], [a, [0, 0, 0]], [b, [1, 1, 1]], [HI, [1, 1, 1]]],
      alpha: [[LO, 1], [HI, 1]],
      rampStart: L.bone,
    };
  }

  const ramp = (start, full, low, high, highAt) => ({
    blend: 'composite',
    shade: true,
    color: [[LO, low], [start, low], [highAt, high], [HI, high]],
    alpha: [[LO, 0], [start, 0], [full, peak], [HI, peak]],
    rampStart: start,
  });

  if (kind === 'ct') {
    if (id === 'skin') return withSurfaces(ramp(-400 + t, -150 + t, SKIN, SKIN, 0 + t), mesh(-275 + t, SKIN));
    if (id === 'muscle') {
      return withSurfaces({
        blend: 'composite',
        shade: true,
        color: [[LO, MUSCLE], [150 + t, MUSCLE], [320 + t, IVORY], [HI, IVORY]],
        alpha: [[LO, 0], [-40 + t, 0], [40 + t, 0.18 * solid], [150 + t, 0.18 * solid], [350 + t, peak], [HI, peak]],
        rampStart: -40 + t,
      }, mesh(0 + t, MUSCLE, 0.3), mesh(250 + t, IVORY));
    }
    if (id === 'lungs') {
      return {
        blend: 'composite',
        shade: true,
        color: [[LO, LUNG], [-400 + t, LUNG], [300 + t, IVORY], [HI, IVORY]],
        alpha: [[LO, 0], [-920 + t, 0], [-780 + t, 0.1 * solid], [-520 + t, 0.1 * solid], [-380 + t, 0], [250 + t, 0], [450 + t, 0.5 * peak], [HI, 0.5 * peak]],
        rampStart: -920 + t,
      };
    }
    return withSurfaces(ramp(200 + t, 400 + t, IVORY_LOW, IVORY, 1200 + t), mesh(300 + t, IVORY)); // bone
  }

  if (kind === 'mr') {
    const span = L.teeth - L.soft;
    return withSurfaces(ramp(L.soft + 0.1 * span + t, L.soft + 0.45 * span + t, GREY_LOW, GREY_HIGH, L.teeth + t), mesh(L.soft + 0.275 * span + t, GREY_HIGH));
  }

  // dental
  const d = 0.08 * (L.teeth - L.soft);
  if (id === 'teeth') return withSurfaces(ramp(L.teeth - 2 * d + t, L.teeth + t, ENAMEL, ENAMEL, L.teeth), mesh(L.teeth - d + t, ENAMEL));
  if (id === 'roots') {
    // Bone turns to faint glass so the teeth, roots included, show through it.
    const boneStart = L.bone - d + t;
    const teethStart = L.teeth - 2.5 * d + t;
    const glass = 0.05 * solid;
    return withSurfaces({
      blend: 'composite',
      shade: true,
      color: [[LO, GLASS_BONE], [teethStart, GLASS_BONE], [L.teeth - d + t, ENAMEL], [HI, ENAMEL]],
      alpha: [[LO, 0], [boneStart, 0], [Math.min(boneStart + 2 * d, teethStart - 1), glass], [teethStart, glass], [L.teeth - 0.5 * d + t, peak], [HI, peak]],
      rampStart: teethStart,
    }, mesh(L.bone + t, GLASS_BONE, 0.16), mesh(L.teeth - 1.5 * d + t, ENAMEL));
  }
  const start = L.bone - d + t;
  const full = L.bone + d + t;
  if (id === 'skinBone') {
    return withSurfaces({
      blend: 'composite',
      shade: true,
      color: [[LO, SKIN], [start, SKIN], [L.teeth, IVORY], [HI, IVORY]],
      alpha: [[LO, 0], [L.air, 0], [L.soft, 0.12 * solid], [start, 0.12 * solid], [full, peak], [HI, peak]],
      rampStart: start,
    }, mesh((L.air + L.soft) / 2, SKIN, 0.22), mesh(L.bone + t, IVORY));
  }
  return withSurfaces(ramp(start, full, IVORY_LOW, IVORY, L.teeth), mesh(L.bone + t, IVORY)); // bone
}
