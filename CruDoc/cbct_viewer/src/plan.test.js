import test from 'node:test';
import assert from 'node:assert/strict';
import { smoothPath, segmentDistance, implantAxis, clearance, safety, tubeMesh, cylinderMesh, NERVE_RADIUS } from './plan.js';

const near = (a, b, tol = 1e-6) => assert.ok(Math.abs(a - b) <= tol, `${a} vs ${b}`);

test('smoothPath passes through the clicked points', () => {
  const pts = [[0, 0, 0], [10, 0, 0], [20, 5, 0]];
  const path = smoothPath(pts, 0.5);
  for (const p of pts) assert.ok(path.some((q) => Math.hypot(q[0] - p[0], q[1] - p[1], q[2] - p[2]) < 1e-9));
  assert.ok(path.length > 40);
  assert.deepEqual(smoothPath([[1, 2, 3]]), [[1, 2, 3]]);
});

test('segmentDistance', () => {
  near(segmentDistance([0, 0, 0], [10, 0, 0], [5, 3, 0], [5, 3, 10]), 3); // crossing at right angles
  near(segmentDistance([0, 0, 0], [10, 0, 0], [0, 2, 0], [10, 2, 0]), 2); // parallel
  near(segmentDistance([0, 0, 0], [1, 0, 0], [4, 0, 0], [5, 0, 0]), 3); // in line
  near(segmentDistance([0, 0, 0], [0, 0, 0], [3, 4, 0], [3, 4, 0]), 5); // two points
});

test('implant axis: lower jaw points down, upper up, tilt leans the apex', () => {
  const im = { top: [0, 0, 0], diameter: 4, length: 10, jaw: 'lower', tiltAP: 0, tiltLR: 0 };
  near(implantAxis(im).apex[2], -10);
  near(implantAxis({ ...im, jaw: 'upper' }).apex[2], 10);
  const tilted = implantAxis({ ...im, tiltAP: 20 });
  assert.ok(tilted.apex[1] > 3 && tilted.apex[2] < -9);
  near(Math.hypot(...tilted.apex), 10);
});

test('clearance to the nerve and the safety colour', () => {
  // Nerve running along x, 14 mm below the implant top; implant 10 mm long, 4 mm wide.
  const nerve = [[-20, 0, -14], [0, 0, -14], [20, 0, -14]];
  const im = { top: [0, 0, 0], diameter: 4, length: 10, jaw: 'lower' };
  near(clearance(im, [nerve]), 14 - 10 - 2 - NERVE_RADIUS, 1e-3);
  assert.equal(safety(clearance(im, [nerve])), 'danger'); // 0.8 mm
  assert.equal(safety(clearance({ ...im, length: 8 }, [nerve])), 'safe'); // 2.8 mm
  assert.equal(clearance(im, [[], [[1, 1, 1]]]), null);
  assert.equal(safety(null), 'unknown');
  assert.equal(safety(2.5), 'safe');
  assert.equal(safety(1.5), 'close');
  assert.equal(safety(0.2), 'danger');
});

test('meshes have matching sizes and valid indices', () => {
  const tube = tubeMesh(smoothPath([[0, 0, 0], [10, 0, 0], [10, 10, 5]], 1), 1.2, 10);
  const cyl = cylinderMesh([0, 0, 0], [0, 0, -10], 2, 16);
  for (const m of [tube, cyl]) {
    const nv = m.points.length / 3;
    assert.equal(m.normals.length, m.points.length);
    assert.equal(m.polys.length % 4, 0);
    for (let i = 0; i < m.polys.length; i += 4) {
      assert.equal(m.polys[i], 3);
      for (let k = 1; k < 4; k++) assert.ok(m.polys[i + k] < nv);
    }
  }
  // A straight tube along x: every point is 1.2 mm from the x axis.
  const straight = tubeMesh(smoothPath([[0, 0, 0], [10, 0, 0]], 1), 1.2, 10);
  for (let p = 0; p < straight.points.length; p += 3) near(Math.hypot(straight.points[p + 1], straight.points[p + 2]), 1.2, 1e-5);
});
