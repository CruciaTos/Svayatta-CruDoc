import test from 'node:test';
import assert from 'node:assert/strict';
import { orientationLetters } from './orientation.js';

test('axial: A on top, R on the left', () => {
  assert.deepEqual(orientationLetters([0, -1, 0], [0, 0, -1]), { top: 'A', bottom: 'P', right: 'L', left: 'R' });
});

test('coronal: S on top, R on the left', () => {
  assert.deepEqual(orientationLetters([0, 0, 1], [0, -1, 0]), { top: 'S', bottom: 'I', right: 'L', left: 'R' });
});

test('sagittal: S on top, A on the left', () => {
  assert.deepEqual(orientationLetters([0, 0, 1], [1, 0, 0]), { top: 'S', bottom: 'I', right: 'P', left: 'A' });
});

test('an axial view tilted 30 degrees about the vertical gives two letters', () => {
  const a = (30 * Math.PI) / 180;
  const up = [Math.sin(a), -Math.cos(a), 0];
  const o = orientationLetters(up, [0, 0, -1]);
  assert.equal(o.top, 'AL');
  assert.equal(o.bottom, 'PR');
  assert.equal(o.right.length, 2);
  assert.equal(o.left.length, 2);
});
