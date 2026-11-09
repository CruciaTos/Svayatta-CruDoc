// Shared engine-side singleton plus the geometry helpers every module needs.
// Written by engine.js; read by overlays, 3D, session.

export const IDS = ['axial', 'threeD', 'coronal', 'sagittal'];
export const MPR = ['axial', 'coronal', 'sagittal'];
export const ENGINE_ID = 'cbctEngine';
export const COLORS = { axial: '#e9ae45', coronal: '#2fc1ae', sagittal: '#a193ff', threeD: '#8c94a3' };

export const core = {
  engine: null,
  hosts: {}, // id -> element
  meta: null,
  geo: null, // geometry of the volume on screen { dims, spacing, origin, direction }
  voxels: null, // Int16Array of the volume on screen
  valueOffset: 0, // stored = real - valueOffset
  volumeId: null,
  crosshair: null, // Crosshairs tool instance
  fit: {}, // id -> { parallelScale, pxPerMm } at the fitted camera
};

export const vp = (id) => core.engine && core.engine.getViewport(id);

// ---------- vectors ----------
export const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
export const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
export const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
export const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
export const mul = (a, s) => [a[0] * s, a[1] * s, a[2] * s];
export const norm = (a) => {
  const l = Math.hypot(a[0], a[1], a[2]) || 1;
  return [a[0] / l, a[1] / l, a[2] / l];
};

// ---------- geometry ----------
export const axes = (g = core.geo) => ({
  x: [g.direction[0], g.direction[1], g.direction[2]],
  y: [g.direction[3], g.direction[4], g.direction[5]],
  z: [g.direction[6], g.direction[7], g.direction[8]],
});

// World point -> continuous voxel index [i, j, k] (voxel centres at integers).
export function worldToIndex(p, g = core.geo) {
  const a = axes(g);
  const r = sub(p, g.origin);
  return [dot(r, a.x) / g.spacing[0], dot(r, a.y) / g.spacing[1], dot(r, a.z) / g.spacing[2]];
}

export function indexToWorld(ijk, g = core.geo) {
  const a = axes(g);
  return add(g.origin, add(add(mul(a.x, ijk[0] * g.spacing[0]), mul(a.y, ijk[1] * g.spacing[1])), mul(a.z, ijk[2] * g.spacing[2])));
}

// Millimetres from the volume's first voxel corner (0..FOV), as the slice positions are shown.
export function worldToCornerMm(p, g = core.geo) {
  const ijk = worldToIndex(p, g);
  return [(ijk[0] + 0.5) * g.spacing[0], (ijk[1] + 0.5) * g.spacing[1], (ijk[2] + 0.5) * g.spacing[2]];
}

// The middle voxel of each axis (a real slice, never between two slices).
export function centre(g = core.geo) {
  return indexToWorld([Math.floor(g.dims[0] / 2), Math.floor(g.dims[1] / 2), Math.floor(g.dims[2] / 2)], g);
}

// Real voxel value at a world point (nearest voxel), or null outside.
export function valueAt(p) {
  if (!core.voxels || !core.geo) return null;
  const [i, j, k] = worldToIndex(p).map(Math.round);
  const [nx, ny, nz] = core.geo.dims;
  if (i < 0 || j < 0 || k < 0 || i >= nx || j >= ny || k >= nz) return null;
  return core.voxels[(k * ny + j) * nx + i] + core.valueOffset;
}

// The volume axis a straight view looks along, and the plane extents (mm) shown in it.
export const VIEW_AXIS = { axial: 2, coronal: 1, sagittal: 0 };
export function planeExtents(id, g = core.geo) {
  const [nx, ny, nz] = g.dims;
  const [sx, sy, sz] = g.spacing;
  if (id === 'axial') return [nx * sx, ny * sy];
  if (id === 'coronal') return [nx * sx, nz * sz];
  return [ny * sy, nz * sz];
}

// The eight corners of the volume's bounding box (outer voxel faces).
export function boxCorners(g = core.geo) {
  const out = [];
  for (const k of [-0.5, g.dims[2] - 0.5]) for (const j of [-0.5, g.dims[1] - 0.5]) for (const i of [-0.5, g.dims[0] - 0.5]) out.push(indexToWorld([i, j, k], g));
  return out;
}
