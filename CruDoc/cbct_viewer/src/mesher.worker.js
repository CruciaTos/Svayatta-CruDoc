// Builds the 3D view's surface meshes off the main thread (see mesher.js).
import { buildMeshes } from './mesher.js';

self.onmessage = (e) => {
  const { id } = e.data;
  try {
    const t0 = performance.now();
    const meshes = buildMeshes(e.data);
    const ms = Math.round(performance.now() - t0);
    const transfer = [];
    for (const m of meshes) transfer.push(m.points.buffer, m.normals.buffer, m.polys.buffer);
    self.postMessage({ id, meshes, ms }, transfer);
  } catch (err) {
    self.postMessage({ id, error: String((err && err.message) || err) });
  }
};
