import test from 'node:test';
import assert from 'node:assert/strict';
import { sampleLinear, archPath, panoramic, crossSection } from './panoramic.js';
import { findArch } from './arch.js';

const geo = {
  dims: [64, 64, 32],
  spacing: [1, 1, 1],
  origin: [0, 0, 0],
  direction: [1, 0, 0, 0, 1, 0, 0, 0, 1],
};

test('sampleLinear: interpolates linearly and returns null outside', () => {
  const [nx, ny, nz] = geo.dims;
  const voxels = new Int16Array(nx * ny * nz);
  for (let k = 0; k < nz; k++) {
    for (let j = 0; j < ny; j++) {
      for (let i = 0; i < nx; i++) {
        voxels[i + j * nx + k * nx * ny] = i;
      }
    }
  }

  const val = sampleLinear(voxels, geo, [10.5, 5, 5]);
  assert.ok(Math.abs(val - 10.5) < 1e-6, `expected 10.5, got ${val}`);

  assert.equal(sampleLinear(voxels, geo, [-1, 5, 5]), null);
  assert.equal(sampleLinear(voxels, geo, [70, 5, 5]), null);
  assert.equal(sampleLinear(voxels, geo, [10, -2, 5]), null);
});

test('archPath: straight line of length 40', () => {
  const line = [
    [10, 20, 15],
    [50, 20, 15],
  ];
  const path = archPath(line, 1, geo);
  assert.ok(Math.abs(path.length - 40) <= 0.01, `length ${path.length} expected 40 +- 0.01`);
  for (const n of path.normals) {
    const l = Math.hypot(n[0], n[1], n[2]);
    assert.ok(Math.abs(l - 1) < 1e-6, `normal length ${l} expected 1`);
    assert.ok(Math.abs(n[2]) < 1e-6, `normal at right angles to z: got n[2]=${n[2]}`);
  }
});

test('panoramic of volume filled with 7', () => {
  const [nx, ny, nz] = geo.dims;
  const voxels = new Int16Array(nx * ny * nz);
  voxels.fill(7);

  const line = [
    [10, 20, 15],
    [50, 20, 15],
  ];
  const arch = archPath(line, 1, geo);
  const pano = panoramic(voxels, geo, arch, { stepMm: 1, thicknessMm: 4 });

  assert.equal(pano.width, arch.points.length);
  for (let i = 0; i < pano.data.length; i++) {
    assert.ok(Math.abs(pano.data[i] - 7) <= 1e-6, `pixel ${i} is ${pano.data[i]}`);
  }
});

test('panoramic of the B1 synthetic arch volume using findArch', () => {
  const [nx, ny, nz] = geo.dims;
  const voxels = new Int16Array(nx * ny * nz);
  for (let z = 12; z <= 18; z++) {
    for (let x = 0; x < nx; x++) {
      const targetY = 0.02 * (x - 32) ** 2 + 12;
      for (let y = 0; y < ny; y++) {
        if (Math.abs(y - targetY) <= 1.5) {
          voxels[x + y * nx + z * nx * ny] = 2000;
        }
      }
    }
  }

  const archRes = findArch(voxels, geo, 1000);
  assert.ok(archRes);
  const arch = archPath(archRes.points, 1, geo);
  const pano = panoramic(voxels, geo, arch, { stepMm: 1, thicknessMm: 6 });

  // Rows for z 12..18 vs z 0..8
  // In pano, row r has targetZ = pano.zTopMm - r * pano.mmPerPixel
  let sumTeeth = 0, countTeeth = 0;
  let sumLow = 0, countLow = 0;

  for (let r = 0; r < pano.height; r++) {
    const z = pano.zTopMm - r * pano.mmPerPixel;
    const rowBase = r * pano.width;
    for (let c = 0; c < pano.width; c++) {
      const v = pano.data[rowBase + c];
      if (z >= 12 && z <= 18) {
        sumTeeth += v;
        countTeeth++;
      } else if (z >= 0 && z <= 8) {
        sumLow += v;
        countLow++;
      }
    }
  }

  const meanTeeth = countTeeth > 0 ? sumTeeth / countTeeth : 0;
  const meanLow = countLow > 0 ? sumLow / countLow : 0;

  assert.ok(meanTeeth > 5 * (meanLow + 1e-3), `meanTeeth ${meanTeeth} should be > 5x meanLow ${meanLow}`);
});

test('crossSection with bright line along z at arch point', () => {
  const [nx, ny, nz] = geo.dims;
  const voxels = new Int16Array(nx * ny * nz);

  const line = [
    [10, 30, 15],
    [50, 30, 15],
  ];
  const arch = archPath(line, 1, geo);
  const sMm = 20; // 20 mm along the arch: point is at x = 30, y = 30
  const archPt = [30, 30, 15];

  // Bright line along z at (30, 30)
  for (let z = 0; z < nz; z++) {
    voxels[30 + 30 * nx + z * nx * ny] = 1000;
  }

  const cs = crossSection(voxels, geo, arch, sMm, { stepMm: 1, widthMm: 20 });
  const centerCol = Math.round((cs.width - 1) / 2);

  // Find column with highest sum
  let maxColSum = -Infinity;
  let brightestCol = -1;

  for (let c = 0; c < cs.width; c++) {
    let colSum = 0;
    for (let r = 0; r < cs.height; r++) {
      colSum += cs.data[r * cs.width + c];
    }
    if (colSum > maxColSum) {
      maxColSum = colSum;
      brightestCol = c;
    }
  }

  assert.ok(
    Math.abs(brightestCol - centerCol) <= 2,
    `brightest col ${brightestCol} within 2 px of center col ${centerCol}`
  );
});

