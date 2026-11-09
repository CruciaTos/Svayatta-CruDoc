import test from 'node:test';
import assert from 'node:assert/strict';
import { fitCamera } from './fit.js';

const close = (a, b) => assert.ok(Math.abs(a - b) < 1e-3, `${a} !~ ${b}`);

test('wide viewport: height decides', () => {
  const f = fitCamera(400, 300, 40, 40);
  close(f.parallelScale, 20);
  close(f.pxPerMm, 7.5);
});

test('tall viewport: width decides', () => {
  const f = fitCamera(300, 400, 40, 40);
  close(f.parallelScale, 26.6667);
  close(f.pxPerMm, 7.5);
});

test('wide plane in a square viewport', () => {
  const f = fitCamera(500, 500, 40, 20);
  close(f.parallelScale, 20);
  close(f.pxPerMm, 12.5);
  close(f.rectW, 500);
  close(f.rectH, 250);
});
