import { indexToWorld } from './core.js';
import { runSync, runAsync } from './steps.js';

// Finds the dental arch: a parabola y = a*x^2 + b*x + c (voxel indices) through
// the tooth band of the scan, returned as 64 world points along it.
// `voxels` hold stored values (real - valueOffset): pass the threshold in the same units.
// The work is a generator that yields now and then, so the page can run it in slices
// (findArchAsync) or all at once (findArch).
function* archSteps(voxels, geo, teethValue) {
  const [nx, ny, nz] = geo.dims;
  const sliceSize = nx * ny;

  // 1. For every z slice count the voxels with value >= teethValue.
  const counts = new Int32Array(nz);
  let maxCount = 0;
  let maxK = -1;
  for (let k = 0; k < nz; k++) {
    let c = 0;
    const base = k * sliceSize;
    for (let n = base, end = base + sliceSize; n < end; n++) {
      if (voxels[n] >= teethValue) c++;
    }
    counts[k] = c;
    if (c > maxCount) {
      maxCount = c;
      maxK = k;
    }
    yield;
  }

  if (maxCount === 0 || maxK === -1) return null;

  // Take the 20 % of slices around the slice with the highest count (the tooth band).
  const halfBand = Math.max(1, Math.round(nz * 0.1));
  const kMin = Math.max(0, maxK - halfBand);
  const kMax = Math.min(nz - 1, maxK + halfBand);
  const zIndex = Math.round((kMin + kMax) / 2);

  // 2. In that band, set a mask bit for every (x, y) column that has a voxel >= teethValue.
  // (Slice by slice: memory is read in order.)
  const mask = new Uint8Array(sliceSize);
  for (let k = kMin; k <= kMax; k++) {
    const base = k * sliceSize;
    for (let n = 0; n < sliceSize; n++) {
      if (voxels[base + n] >= teethValue) mask[n] = 1;
    }
    yield;
  }

  // 3. Statistics of the mask points. Fewer than 30: no teeth found.
  let count = 0;
  let sumX = 0;
  let sumY = 0;
  let minX = Infinity;
  let maxX = -Infinity;
  for (let y = 0; y < ny; y++) {
    for (let x = 0; x < nx; x++) {
      if (!mask[x + y * nx]) continue;
      count++;
      sumX += x;
      sumY += y;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
    }
  }
  if (count < 30 || minX >= maxX) return null;
  yield;

  // 4. Fit y = a*x*x + b*x + c by least squares. The sums are built on centred and scaled
  // coordinates u = (x - meanX) / s, v = (y - meanY) / s (s = half the width of the arch).
  // Raw sums of x^4 over a 400-voxel scan are around 1e15 per point and lose digits.
  const meanX = sumX / count;
  const meanY = sumY / count;
  const s = (maxX - minX) / 2 || 1;
  let S4 = 0, S3 = 0, S2 = 0, S1 = 0;
  let T2 = 0, T1 = 0, T0 = 0;
  for (let y = 0; y < ny; y++) {
    const v = (y - meanY) / s;
    for (let x = 0; x < nx; x++) {
      if (!mask[x + y * nx]) continue;
      const u = (x - meanX) / s;
      const u2 = u * u;
      S1 += u;
      S2 += u2;
      S3 += u2 * u;
      S4 += u2 * u2;
      T0 += v;
      T1 += v * u;
      T2 += v * u2;
    }
  }
  const S0 = count;

  const detM = S4 * (S2 * S0 - S1 * S1) - S3 * (S3 * S0 - S1 * S2) + S2 * (S3 * S1 - S2 * S2);
  if (Math.abs(detM) < 1e-9) return null;
  // v = A*u^2 + B*u + C (Cramer's rule)
  const A = (T2 * (S2 * S0 - S1 * S1) - S3 * (T1 * S0 - S1 * T0) + S2 * (T1 * S1 - S2 * T0)) / detM;
  const B = (S4 * (T1 * S0 - S1 * T0) - T2 * (S3 * S0 - S1 * S2) + S2 * (S3 * T0 - T1 * S2)) / detM;
  const C = (S4 * (S2 * T0 - T1 * S1) - S3 * (S3 * T0 - T1 * S2) + T2 * (S3 * S1 - S2 * S2)) / detM;

  // Back to voxel units: y = meanY + s*(A*u^2 + B*u + C) with u = (x - meanX) / s.
  const a = A / s;
  const b = B - (2 * A * meanX) / s;
  const c = meanY + s * C + (A * meanX * meanX) / s - B * meanX;

  // 5. Return { points, zIndex, coefficients: [a, b, c] }: 64 points along the curve
  // from the smallest to the largest masked x, in world coordinates.
  const points = [];
  const numPoints = 64;
  for (let n = 0; n < numPoints; n++) {
    const x = minX + (maxX - minX) * (n / (numPoints - 1));
    const u = (x - meanX) / s;
    const y = meanY + s * ((A * u + B) * u + C);
    points.push(indexToWorld([x, y, zIndex], geo));
  }

  return { points, zIndex, coefficients: [a, b, c] };
}

export const findArch = (voxels, geo, teethValue) => runSync(archSteps(voxels, geo, teethValue));
export const findArchAsync = (voxels, geo, teethValue, budgetMs) => runAsync(archSteps(voxels, geo, teethValue), budgetMs);
