import test from 'node:test';
import assert from 'node:assert/strict';
import { isosurface, buildMeshes } from './mesher.js';

// A ball of radius 6 voxels in a 20^3 grid: value = 6 - distance (high inside).
function ball(n = 20, r = 6) {
  const f = new Float32Array(n * n * n);
  const c = (n - 1) / 2;
  let q = 0;
  for (let k = 0; k < n; k++) for (let j = 0; j < n; j++) for (let i = 0; i < n; i++) f[q++] = r - Math.hypot(i - c, j - c, k - c);
  return { f, dims: [n, n, n], c };
}

test('isosurface of a ball is closed, on the sphere, normals outward', () => {
  const { f, dims, c } = ball();
  const geo = { spacing: [0.5, 0.5, 0.5], origin: [10, 20, 30], direction: [1, 0, 0, 0, 1, 0, 0, 0, 1] };
  const m = isosurface(f, dims, 0, geo);
  const nt = m.polys.length / 4;
  assert.ok(nt > 500, `${nt} triangles`);
  // Closed: every edge is shared by exactly two triangles.
  const edges = new Map();
  for (let t = 0; t < nt; t++) {
    const v = [m.polys[t * 4 + 1], m.polys[t * 4 + 2], m.polys[t * 4 + 3]];
    for (let e = 0; e < 3; e++) {
      const a = Math.min(v[e], v[(e + 1) % 3]);
      const b = Math.max(v[e], v[(e + 1) % 3]);
      edges.set(`${a}-${b}`, (edges.get(`${a}-${b}`) || 0) + 1);
    }
  }
  assert.ok([...edges.values()].every((n) => n === 2));
  const centre = [10 + c * 0.5, 20 + c * 0.5, 30 + c * 0.5];
  for (let v = 0; v < m.points.length / 3; v++) {
    const d = [0, 1, 2].map((a) => m.points[v * 3 + a] - centre[a]);
    const len = Math.hypot(...d);
    assert.ok(Math.abs(len - 3) < 0.15, `radius ${len}`);
    const dotN = d.reduce((s, x, a) => s + (x / len) * m.normals[v * 3 + a], 0);
    assert.ok(dotN > 0.95, `normal ${dotN}`);
  }
});

test('direction turns the mesh', () => {
  const { f, dims } = ball();
  const geo = { spacing: [1, 1, 1], origin: [0, 0, 0], direction: [0, 1, 0, -1, 0, 0, 0, 0, 1] };
  const [m] = buildMeshes({ grid: f, dims, geo, isos: [0], passes: 1 });
  // Axis i runs along +y, axis j along -x: x values are all <= 0.
  for (let v = 0; v < m.points.length / 3; v++) assert.ok(m.points[v * 3] <= 0.001);
});
