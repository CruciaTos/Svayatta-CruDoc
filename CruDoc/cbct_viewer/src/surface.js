// Surface meshes for the 3D view: the normal looks draw surfaces (like a game,
// each pixel is touched about once) instead of casting rays through the volume.
// One mesh per tissue, each its own actor, so a tissue can be shown or hidden.
// The meshes are built in a worker (mesher.js) from the volume the slice views
// hold, sampled down to at most GRID voxels per axis.
import vtkActor from '@kitware/vtk.js/Rendering/Core/Actor.js';
import vtkMapper from '@kitware/vtk.js/Rendering/Core/Mapper.js';
import vtkPolyData from '@kitware/vtk.js/Common/DataModel/PolyData.js';
import vtkDataArray from '@kitware/vtk.js/Common/Core/DataArray.js';
import MesherWorker from './mesher.worker.js?worker&inline';
import { core } from './core.js';
import { state } from './state.js';

const GRID = { pc: 256, tablet: 192 }; // voxels per axis of the grid a mesh is built from

let worker = null;
let lastId = 0;
const waiting = new Map();
const sourceIds = new WeakMap();
let sourceCount = 0;
let meshCount = 0;
let shown = null; // { key, entries: [{ uid, actor }] } on the 3D view

// For the test scripts (with ?debug).
export const meshStats = { ms: 0, triangles: 0, grid: null };

function getWorker() {
  if (worker) return worker;
  worker = new MesherWorker();
  worker.onmessage = (e) => {
    const w = waiting.get(e.data.id);
    if (!w) return;
    waiting.delete(e.data.id);
    if (e.data.error) w.reject(new Error(e.data.error));
    else w.resolve(e.data);
  };
  worker.onerror = (e) => {
    for (const w of waiting.values()) w.reject(new Error(e.message || 'mesh worker failed'));
    waiting.clear();
    worker = null;
  };
  return worker;
}

const gridLimit = () => GRID[state.deviceClass] || GRID.pc;

function sourceId() {
  const v = core.voxels;
  if (!v) return 0;
  if (!sourceIds.has(v)) sourceIds.set(v, ++sourceCount);
  return sourceIds.get(v);
}

// Which meshes a look wants: rebuilt only when this changes.
export const surfaceKey = (specs, passes) => `${sourceId()}|${gridLimit()}|${passes}|${specs.map((s) => Math.round(s.iso)).join(',')}`;
export const shownKey = () => (shown ? shown.key : '');

// The slice views' volume, sampled down to the grid (a Float32Array the worker may own).
function sample() {
  const src = core.voxels;
  const g = core.geo;
  const s = Math.max(1, Math.ceil(Math.max(...g.dims) / gridLimit()));
  const [nx, ny] = g.dims;
  const dims = g.dims.map((n) => Math.floor((n - 1) / s) + 1);
  const grid = new Float32Array(dims[0] * dims[1] * dims[2]);
  let q = 0;
  for (let k = 0; k < dims[2]; k++) {
    for (let j = 0; j < dims[1]; j++) {
      const row = (k * s * ny + j * s) * nx;
      for (let i = 0; i < dims[0]; i++) grid[q++] = src[row + i * s];
    }
  }
  return { grid, dims, geo: { spacing: g.spacing.map((x) => x * s), origin: [...g.origin], direction: [...g.direction] } };
}

function makeActor(m) {
  const pd = vtkPolyData.newInstance();
  pd.getPoints().setData(m.points, 3);
  pd.getPolys().setData(m.polys);
  pd.getPointData().setNormals(vtkDataArray.newInstance({ numberOfComponents: 3, values: m.normals, name: 'Normals' }));
  const mapper = vtkMapper.newInstance({ scalarVisibility: false });
  mapper.setInputData(pd);
  const actor = vtkActor.newInstance();
  actor.setMapper(mapper);
  actor.setVisibility(false);
  return { uid: `cbctMesh${++meshCount}`, actor };
}

// Builds the meshes for `specs` ([{ iso (real units), color, opacity }]) with
// `passes` rounds of smoothing. Resolves to { key, entries } (hidden actors),
// or null when a newer build was asked for meanwhile.
export async function buildSurfaces(specs, passes) {
  if (!core.voxels || !core.geo) return null;
  const key = surfaceKey(specs, passes);
  const { grid, dims, geo } = sample();
  const id = ++lastId;
  const isos = specs.map((s) => s.iso - core.valueOffset);
  const res = await new Promise((resolve, reject) => {
    waiting.set(id, { resolve, reject });
    getWorker().postMessage({ id, grid, dims, geo, isos, passes }, [grid.buffer]);
  });
  if (id !== lastId) return null;
  meshStats.ms = res.ms;
  meshStats.grid = dims;
  meshStats.triangles = res.meshes.reduce((n, m) => n + m.polys.length / 4, 0);
  return { key, entries: res.meshes.map(makeActor) };
}

function dispose(entries) {
  for (const { actor } of entries) {
    const m = actor.getMapper();
    actor.delete();
    if (m) m.delete();
  }
}

// Puts freshly built meshes on the view in place of the old ones.
export function placeSurfaces(viewport, built) {
  if (shown) {
    viewport.removeActors(shown.entries.map((e) => e.uid).filter((uid) => viewport.getActor(uid)));
    dispose(shown.entries);
  }
  shown = built;
  for (const e of built.entries) viewport.addActor(e);
}

// Meshes built for a look that is no longer wanted.
export const discardSurfaces = (built) => built && dispose(built.entries);

// The scan closes: free the meshes and forget any build still running.
export function dropSurfaces(viewport) {
  lastId++;
  if (!shown) return;
  if (viewport) viewport.removeActors(shown.entries.map((e) => e.uid).filter((uid) => viewport.getActor(uid)));
  dispose(shown.entries);
  shown = null;
}

// A new volume on the 3D view removes every actor: put the meshes back.
export function keepPlaced(viewport) {
  if (!shown) return;
  for (const e of shown.entries) if (!viewport.getActor(e.uid)) viewport.addActor(e);
}

export const surfaceActors = () => (shown ? shown.entries.map((e) => e.actor) : []);

// Colour, opacity and lighting; `visible` false hides every mesh.
export function styleSurfaces(specs, visible) {
  if (!shown) return;
  shown.entries.forEach(({ actor }, i) => {
    const s = specs[i];
    const on = !!(visible && s && s.opacity > 0.003);
    actor.setVisibility(on);
    if (!s) return;
    const p = actor.getProperty();
    p.setColor(...s.color);
    p.setOpacity(Math.min(1, s.opacity));
    p.setAmbient(0.16);
    p.setDiffuse(0.84);
    p.setSpecular(0.22);
    p.setSpecularPower(22);
    p.setInterpolationToPhong();
  });
}
