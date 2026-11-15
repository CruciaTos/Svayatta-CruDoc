// Reads a mesh file off the main thread: a full-arch scan is tens of
// megabytes, and welding its corners would otherwise freeze the page for
// seconds. The arrays are handed over, not copied.
import { parseMesh, MeshError } from './parse.js';

self.onmessage = (e) => {
  const { id, buffer, name } = e.data;
  try {
    const t0 = performance.now();
    const mesh = parseMesh(buffer, name);
    const parseMs = Math.round(performance.now() - t0);
    const payload = {
      id,
      format: mesh.format,
      positions: mesh.positions,
      indices: mesh.indices,
      normals: mesh.normals,
      colors: mesh.colors,
      points: mesh.points,
      triangles: mesh.triangles,
      bounds: mesh.bounds,
      welded: mesh.welded,
      parseMs,
    };
    const handOver = [mesh.positions, mesh.normals, mesh.indices, mesh.colors]
      .filter(Boolean)
      .map((a) => a.buffer);
    self.postMessage(payload, handOver);
  } catch (err) {
    self.postMessage({
      id,
      error: err instanceof MeshError ? err.message : 'CruDoc could not read this 3D file.',
    });
  }
};
