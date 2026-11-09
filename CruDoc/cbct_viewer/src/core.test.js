import test from 'node:test';
import assert from 'node:assert/strict';
import {
  core,
  worldToIndex,
  indexToWorld,
  worldToCornerMm,
  centre,
  planeExtents,
  boxCorners,
  valueAt,
} from './core.js';

const close = (a, b) => assert.ok(a.every((v, i) => Math.abs(v - b[i]) < 1e-9), `${a} !~ ${b}`);

test.beforeEach(() => {
  core.geo = {
    dims: [10, 20, 30],
    spacing: [0.5, 0.5, 1],
    origin: [0, 0, 0],
    direction: [1, 0, 0, 0, 1, 0, 0, 0, 1],
  };
  core.voxels = null;
  core.valueOffset = 0;
});

test('1. worldToIndex and indexToWorld convert between world and index coordinates', () => {
  close(worldToIndex([1, 2, 3]), [2, 4, 3]);
  close(indexToWorld([2, 4, 3]), [1, 2, 3]);
});

test('2. worldToCornerMm calculates distance in mm from first voxel outer corner', () => {
  close(worldToCornerMm([0, 0, 0]), [0.25, 0.25, 0.5]);
});

test('3. centre returns the middle voxel coordinate in world space', () => {
  close(centre(), [2.5, 5, 15]);
});

test('4. planeExtents returns mm dimensions for axial, coronal, and sagittal planes', () => {
  close(planeExtents('axial'), [5, 10]);
  close(planeExtents('coronal'), [5, 30]);
  close(planeExtents('sagittal'), [10, 30]);
});

test('5. boxCorners returns 8 outer bounding box corner points', () => {
  const corners = boxCorners();
  assert.equal(corners.length, 8);
  close(corners[0], [-0.25, -0.25, -0.5]);
  close(corners[7], [4.75, 9.75, 29.5]);
});

test('6. valueAt returns voxel value plus offset, or null when outside volume', () => {
  core.voxels = Int16Array.from({ length: 10 * 20 * 30 }, (_, i) => i % 1000);
  core.valueOffset = 100;
  const expected = ((1 * 20 + 2) * 10 + 3) % 1000 + 100;
  assert.equal(valueAt(indexToWorld([3, 2, 1])), expected);
  assert.equal(valueAt([-5, 0, 0]), null);
});

test('7. rotated volume correctly maps between world and index coordinates', () => {
  core.geo.direction = [0, 1, 0, 1, 0, 0, 0, 0, 1];
  close(worldToIndex([2, 1, 3]), [2, 4, 3]);
  close(indexToWorld([2, 4, 3]), [2, 1, 3]);
});

