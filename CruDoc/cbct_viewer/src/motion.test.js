import test from 'node:test';
import assert from 'node:assert/strict';
import { slerp, basisOf, cameraQuat } from './motion.js';

const EPS = 1e-6;

function near(a, b, eps = EPS) {
  for (let i = 0; i < a.length; i++) {
    if (Math.abs(a[i] - b[i]) > eps) return false;
  }
  return true;
}

// Two quaternions represent the same rotation if they are equal or negatives.
function sameBasis(q1, q2, eps = EPS) {
  const b1 = basisOf(q1);
  const b2 = basisOf(q2);
  return near(b1.viewUp, b2.viewUp, eps) && near(b1.viewPlaneNormal, b2.viewPlaneNormal, eps);
}

function norm(v) {
  const len = Math.hypot(...v);
  return v.map((x) => x / len);
}
function dot(a, b) { return a[0]*b[0] + a[1]*b[1] + a[2]*b[2]; }

const cams = [
  { viewUp: [0, 0, 1],  viewPlaneNormal: [0, -1, 0] },
  { viewUp: [0, -1, 0], viewPlaneNormal: [0,  0, 1] },
  { viewUp: [0, 0, 1],  viewPlaneNormal: [1,  0, 0] },
];

// 1. cameraQuat -> basisOf round-trips
for (const cam of cams) {
  test(`basisOf(cameraQuat(cam)) round-trips viewUp=${JSON.stringify(cam.viewUp)} vpn=${JSON.stringify(cam.viewPlaneNormal)}`, () => {
    const q = cameraQuat(cam);
    const { viewUp, viewPlaneNormal } = basisOf(q);
    assert.ok(near(viewUp, norm(cam.viewUp), EPS),
      `viewUp mismatch: got ${JSON.stringify(viewUp)}`);
    assert.ok(near(viewPlaneNormal, norm(cam.viewPlaneNormal), EPS),
      `viewPlaneNormal mismatch: got ${JSON.stringify(viewPlaneNormal)}`);
  });
}

// 2. slerp(a, b, 0) == a and slerp(a, b, 1) == b (or its negative, same rotation)
test('slerp(a, b, 0) gives same rotation as a', () => {
  const a = cameraQuat(cams[0]);
  const b = cameraQuat(cams[1]);
  const result = slerp(a, b, 0);
  assert.ok(sameBasis(result, a, EPS), `slerp at t=0 did not reproduce a`);
});

test('slerp(a, b, 1) gives same rotation as b', () => {
  const a = cameraQuat(cams[0]);
  const b = cameraQuat(cams[1]);
  const result = slerp(a, b, 1);
  assert.ok(sameBasis(result, b, EPS), `slerp at t=1 did not reproduce b`);
});

// 3. At t=0.5 basisOf returns two unit vectors that are orthogonal
for (let i = 0; i < cams.length; i++) {
  for (let j = i + 1; j < cams.length; j++) {
    test(`slerp(cam${i}, cam${j}, 0.5) gives valid camera (orthogonal up and normal)`, () => {
      const a = cameraQuat(cams[i]);
      const b = cameraQuat(cams[j]);
      const mid = slerp(a, b, 0.5);
      const { viewUp, viewPlaneNormal } = basisOf(mid);

      // Both should be unit vectors
      assert.ok(Math.abs(Math.hypot(...viewUp) - 1) < EPS, `viewUp not unit: ${Math.hypot(...viewUp)}`);
      assert.ok(Math.abs(Math.hypot(...viewPlaneNormal) - 1) < EPS, `viewPlaneNormal not unit: ${Math.hypot(...viewPlaneNormal)}`);

      // They should be orthogonal
      const d = Math.abs(dot(viewUp, viewPlaneNormal));
      assert.ok(d < EPS, `viewUp · viewPlaneNormal = ${d}, expected ~0`);
    });
  }
}

