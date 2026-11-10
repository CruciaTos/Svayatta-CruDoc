import test from 'node:test';
import assert from 'node:assert/strict';
import { traceCanal, siteMeasure, suggestSize, findDense } from './assist.js';

const lv = { air: -600, soft: 180, bone: 1100 };
// 80 x 60 x 60 voxels of 0.5 mm, identity direction, origin 0.
const geo = { dims: [80, 60, 60], spacing: [0.5, 0.5, 0.5], origin: [0, 0, 0], direction: [1, 0, 0, 0, 1, 0, 0, 0, 1] };
const N = 80 * 60 * 60;
const idx = (i, j, k) => i + 80 * (j + 60 * k);
const world = (i, j, k) => [i * 0.5, j * 0.5, k * 0.5];

// A jaw: a bone block (j 10..50, k 5..45) in soft tissue, with a dark canal
// curving through it: centre j = 30 + 8 sin(i / 25), k = 20, radius 2.5 voxels.
function jaw() {
  const v = new Int16Array(N).fill(180);
  const canal = (i) => [30 + 8 * Math.sin(i / 25), 20];
  for (let k = 0; k < 60; k++) for (let j = 0; j < 60; j++) for (let i = 0; i < 80; i++) {
    if (j >= 10 && j <= 50 && k >= 5 && k <= 45) {
      const [cj, ck] = canal(i);
      v[idx(i, j, k)] = Math.hypot(j - cj, k - ck) <= 2.5 ? 180 : 1400;
    }
  }
  return { v, canal };
}

test('traceCanal follows a curved canal inside the bone', () => {
  const { v, canal } = jaw();
  const a = world(5, canal(5)[0], 20);
  const b = world(75, canal(75)[0], 20);
  const pts = traceCanal(v, geo, a, b, lv, { stepMm: 0.5 });
  assert.ok(pts.length >= 8, `${pts.length} points`);
  for (const p of pts) {
    const i = p[0] / 0.5;
    const [cj, ck] = canal(i);
    const off = Math.hypot(p[1] / 0.5 - cj, p[2] / 0.5 - ck) * 0.5;
    assert.ok(off < 1.0, `point ${p.map((x) => x.toFixed(1))} is ${off.toFixed(2)} mm from the canal`);
  }
});

test('siteMeasure and suggestSize on a block of bone', () => {
  // Bone k 5..45 (top surface at k = 45, z = 22.5 mm); air below k < 5 except the block.
  const v = new Int16Array(N).fill(180);
  for (let k = 5; k <= 45; k++) for (let j = 22; j <= 38; j++) for (let i = 0; i < 80; i++) v[idx(i, j, k)] = 1400;
  for (let k = 0; k < 5; k++) for (let j = 0; j < 60; j++) for (let i = 0; i < 80; i++) v[idx(i, j, k)] = -1000;
  // Implant top 1 mm above the bone, pointing down; bone is 8.5 mm wide (j 22..38 = 17 voxels).
  const im = { top: [20, 15, 23.5], diameter: 4, length: 10, jaw: 'lower', tiltAP: 0, tiltLR: 0 };
  const nerve = [[0, 15, 8], [40, 15, 8]]; // canal centre at z = 8 mm, under the site
  const m = siteMeasure(v, geo, im, lv, [nerve]);
  assert.ok(Math.abs(m.crestOffset - 1) < 0.5, `crest offset ${m.crestOffset}`);
  assert.ok(Math.abs(m.widthCrest - 8.5) < 1, `width ${m.widthCrest}`);
  assert.ok(Math.abs(m.heightToNerve - (22.5 - 8 - 1.2)) < 0.6, `to nerve ${m.heightToNerve}`);
  const upper = siteMeasure(v, geo, { ...im, top: [20, 15, 1], jaw: 'upper' }, lv);
  assert.ok(upper.crest == null || upper.heightToAir == null || upper.heightToAir > 0);
  // Width reads ~8 mm (voxel centres, on the safe side): 8 - 3 = 5.0 mm diameter.
  // Height to the canal roof ~13.5 mm, minus the 2 mm margin: longest standard 11.5 mm.
  const s = suggestSize(m, 'lower');
  assert.equal(s.diameter, 5.0);
  assert.equal(s.length, 11.5);
  assert.deepEqual(s.notes, []);
  assert.ok(suggestSize({ widthCrest: 5, widthMid: 6, heightToNerve: null }, 'lower').notes.length === 2);
});

test('findDense boxes two metal objects', () => {
  const v = new Int16Array(N).fill(180);
  for (let k = 10; k < 20; k++) for (let j = 10; j < 14; j++) for (let i = 10; i < 14; i++) v[idx(i, j, k)] = 6000;
  for (let k = 40; k < 44; k++) for (let j = 40; j < 50; j++) for (let i = 50; i < 70; i++) v[idx(i, j, k)] = 6000;
  const boxes = findDense(v, geo, 5000, { minMm3: 0.5 });
  assert.equal(boxes.length, 2);
  const big = boxes[0];
  assert.ok(Math.abs(big.sizeMm[0] - 10) < 0.6 && Math.abs(big.sizeMm[1] - 5) < 0.6 && Math.abs(big.sizeMm[2] - 2) < 0.6, JSON.stringify(big.sizeMm));
  assert.equal(findDense(new Int16Array(N), geo, 5000).length, 0);
});
