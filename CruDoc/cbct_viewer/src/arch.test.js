import test from 'node:test';
import assert from 'node:assert/strict';
import { findArch, findArchAsync } from './arch.js';

test('findArch detects synthetic parabolic arch', () => {
  const dims = [64, 64, 32];
  const geo = {
    dims,
    spacing: [1, 1, 1],
    origin: [0, 0, 0],
    direction: [1, 0, 0, 0, 1, 0, 0, 0, 1],
  };

  const voxels = new Int16Array(dims[0] * dims[1] * dims[2]);
  for (let z = 12; z <= 18; z++) {
    for (let x = 0; x < dims[0]; x++) {
      const targetY = 0.02 * (x - 32) ** 2 + 12;
      for (let y = 0; y < dims[1]; y++) {
        if (Math.abs(y - targetY) <= 1.5) {
          voxels[x + y * dims[0] + z * dims[0] * dims[1]] = 2000;
        }
      }
    }
  }

  const res = findArch(voxels, geo, 1000);
  assert.ok(res, 'findArch should return a result');
  assert.equal(res.points.length, 64);
  assert.ok(res.zIndex >= 12 && res.zIndex <= 18);

  const [a, b, c] = res.coefficients;
  assert.ok(Math.abs(a - 0.02) <= 0.004, `fitted a ${a} within 0.004 of 0.02`);

  // Lowest point of parabola y = a*x^2 + b*x + c is at x = -b / (2*a)
  const xLow = -b / (2 * a);
  const yLow = a * xLow * xLow + b * xLow + c;

  assert.ok(Math.abs(xLow - 32) <= 1.5, `xLow ${xLow} within 1.5 voxels of 32`);
  assert.ok(Math.abs(yLow - 12) <= 1.5, `yLow ${yLow} within 1.5 voxels of 12`);
});

test('findArch returns null on an all-zero volume', () => {
  const geo = {
    dims: [64, 64, 32],
    spacing: [1, 1, 1],
    origin: [0, 0, 0],
    direction: [1, 0, 0, 0, 1, 0, 0, 0, 1],
  };
  const voxels = new Int16Array(64 * 64 * 32);
  const res = findArch(voxels, geo, 1000);
  assert.equal(res, null);
});


test('findArch stays accurate on a wide scan (700 voxels), sync and in slices', async () => {
  const dims = [700, 420, 12];
  const geo = { dims, spacing: [0.1, 0.1, 0.1], origin: [0, 0, 0], direction: [1, 0, 0, 0, 1, 0, 0, 0, 1] };
  const voxels = new Int16Array(dims[0] * dims[1] * dims[2]);
  const A = 0.0012;
  const X0 = 410;
  const Y0 = 60;
  for (let z = 3; z <= 8; z++) {
    for (let x = 60; x < 640; x++) {
      const ty = A * (x - X0) ** 2 + Y0;
      for (let y = Math.max(0, Math.round(ty) - 2); y <= Math.min(dims[1] - 1, Math.round(ty) + 2); y++) {
        voxels[x + y * dims[0] + z * dims[0] * dims[1]] = 2000;
      }
    }
  }
  const res = findArch(voxels, geo, 1000);
  assert.ok(res);
  const [a, b, c] = res.coefficients;
  assert.ok(Math.abs(a - A) < 0.00005, `a ${a}`);
  const xLow = -b / (2 * a);
  assert.ok(Math.abs(xLow - X0) < 3, `vertex x ${xLow}`);
  assert.ok(Math.abs(a * xLow * xLow + b * xLow + c - Y0) < 2, 'vertex y');
  const slow = await findArchAsync(voxels, geo, 1000, 1);
  assert.deepEqual(slow.coefficients, res.coefficients);
});
