import { worldToIndex, axes, sub, add, mul, norm, cross, dot } from './core.js';
import { runSync, runAsync } from './steps.js';

export function sampleLinear(voxels, geo, p) {
  const [u, v, w] = worldToIndex(p, geo);
  const [nx, ny, nz] = geo.dims;

  if (u < 0 || u > nx - 1 || v < 0 || v > ny - 1 || w < 0 || w > nz - 1) {
    return null;
  }

  const i0 = Math.floor(u);
  const j0 = Math.floor(v);
  const k0 = Math.floor(w);

  const i1 = Math.min(nx - 1, i0 + 1);
  const j1 = Math.min(ny - 1, j0 + 1);
  const k1 = Math.min(nz - 1, k0 + 1);

  const fx = u - i0;
  const fy = v - j0;
  const fz = w - k0;

  const sliceSize = nx * ny;
  const k0Base = k0 * sliceSize;
  const k1Base = k1 * sliceSize;

  const c000 = voxels[i0 + j0 * nx + k0Base];
  const c100 = voxels[i1 + j0 * nx + k0Base];
  const c010 = voxels[i0 + j1 * nx + k0Base];
  const c110 = voxels[i1 + j1 * nx + k0Base];

  const c001 = voxels[i0 + j0 * nx + k1Base];
  const c101 = voxels[i1 + j0 * nx + k1Base];
  const c011 = voxels[i0 + j1 * nx + k1Base];
  const c111 = voxels[i1 + j1 * nx + k1Base];

  const c00 = c000 * (1 - fx) + c100 * fx;
  const c10 = c010 * (1 - fx) + c110 * fx;
  const c01 = c001 * (1 - fx) + c101 * fx;
  const c11 = c011 * (1 - fx) + c111 * fx;

  const c0 = c00 * (1 - fy) + c10 * fy;
  const c1 = c01 * (1 - fy) + c11 * fy;

  return c0 * (1 - fz) + c1 * fz;
}

export function archPath(points, stepMm, geo) {
  if (!points || points.length === 0) {
    return { points: [], normals: [], length: 0 };
  }

  const zAxis = axes(geo).z;

  if (points.length === 1) {
    return {
      points: [[...points[0]]],
      normals: [norm(cross([1, 0, 0], zAxis))],
      length: 0,
    };
  }

  // Calculate cumulative distances along input points
  const cumDists = [0];
  let totalLength = 0;
  for (let i = 0; i < points.length - 1; i++) {
    const d = Math.hypot(
      points[i + 1][0] - points[i][0],
      points[i + 1][1] - points[i][1],
      points[i + 1][2] - points[i][2]
    );
    totalLength += d;
    cumDists.push(totalLength);
  }

  // Resample at equal arc length stepMm
  const resampled = [];
  let segIdx = 0;
  for (let s = 0; s <= totalLength + 1e-6; s += stepMm) {
    const curS = Math.min(s, totalLength);
    while (segIdx < cumDists.length - 2 && cumDists[segIdx + 1] < curS) {
      segIdx++;
    }
    const segLen = cumDists[segIdx + 1] - cumDists[segIdx];
    const t = segLen > 1e-9 ? (curS - cumDists[segIdx]) / segLen : 0;
    const p0 = points[segIdx];
    const p1 = points[segIdx + 1];
    resampled.push([
      p0[0] + (p1[0] - p0[0]) * t,
      p0[1] + (p1[1] - p0[1]) * t,
      p0[2] + (p1[2] - p0[2]) * t,
    ]);
  }

  const n = resampled.length;
  const normals = [];

  for (let i = 0; i < n; i++) {
    let tangent;
    if (i === 0) {
      tangent = sub(resampled[1], resampled[0]);
    } else if (i === n - 1) {
      tangent = sub(resampled[n - 1], resampled[n - 2]);
    } else {
      tangent = sub(resampled[i + 1], resampled[i - 1]);
    }

    const tNorm = norm(tangent);
    let N = norm(cross(tNorm, zAxis));

    // Curvature vector C = P_{i+1} - 2P_i + P_{i-1} points toward center of curvature.
    // If dot(N, C) > 0, N points toward center of curvature, so invert to point outward.
    let curv;
    if (i > 0 && i < n - 1) {
      curv = sub(add(resampled[i + 1], resampled[i - 1]), mul(resampled[i], 2));
    } else if (i === 0 && n > 2) {
      curv = sub(add(resampled[2], resampled[0]), mul(resampled[1], 2));
    } else if (i === n - 1 && n > 2) {
      curv = sub(add(resampled[n - 1], resampled[n - 3]), mul(resampled[n - 2], 2));
    }

    if (curv && Math.hypot(curv[0], curv[1], curv[2]) > 1e-5) {
      if (dot(N, curv) > 0) {
        N = mul(N, -1);
      }
    }

    normals.push(N);
  }

  return {
    points: resampled,
    normals,
    length: totalLength,
  };
}

// The lowest value in the volume (what outside-the-scan points show). Cached: a cross-section
// is rebuilt on every arrow key and the volume can hold 100 million voxels.
const minCache = new WeakMap();
function getVolumeMin(voxels) {
  if (minCache.has(voxels)) return minCache.get(voxels);
  let min = Infinity;
  for (let i = 0; i < voxels.length; i++) {
    if (voxels[i] < min) min = voxels[i];
  }
  min = min === Infinity ? 0 : min;
  minCache.set(voxels, min);
  return min;
}

// One row of the picture at a time, so a caller can run it in slices (panoramicAsync).
function* panoramicSteps(voxels, geo, arch, { stepMm = 0.25, thicknessMm = 10 } = {}) {
  const width = arch.points.length;
  const zAxis = axes(geo).z;
  const extentZ = geo.dims[2] * geo.spacing[2];
  const height = Math.round(extentZ / stepMm);
  const data = new Float32Array(width * height);
  const volumeMin = getVolumeMin(voxels);

  const originZ = dot(geo.origin, zAxis);
  const zTopMm = originZ + (geo.dims[2] - 1) * geo.spacing[2];
  const halfThick = thicknessMm / 2;

  for (let r = 0; r < height; r++) {
    const targetZ = zTopMm - r * stepMm;
    const rowOffset = r * width;

    for (let c = 0; c < width; c++) {
      const P = arch.points[c];
      const N = arch.normals[c];
      const zMm = targetZ - dot(P, zAxis);

      let sum = 0;
      let count = 0;

      for (let t = -halfThick; t <= halfThick + 1e-6; t += stepMm) {
        const pt = [
          P[0] + N[0] * t + zAxis[0] * zMm,
          P[1] + N[1] * t + zAxis[1] * zMm,
          P[2] + N[2] * t + zAxis[2] * zMm,
        ];
        const val = sampleLinear(voxels, geo, pt);
        if (val !== null) {
          sum += val;
          count++;
        }
      }

      data[rowOffset + c] = count > 0 ? sum / count : volumeMin;
    }
    yield;
  }

  return {
    width,
    height,
    data,
    mmPerPixel: stepMm,
    zTopMm,
  };
}

export const panoramic = (voxels, geo, arch, opts) => runSync(panoramicSteps(voxels, geo, arch, opts));
export const panoramicAsync = (voxels, geo, arch, opts, budgetMs, cancelled) => runAsync(panoramicSteps(voxels, geo, arch, opts), budgetMs, cancelled);

export function crossSection(voxels, geo, arch, sMm, { stepMm = 0.25, widthMm = 30 } = {}) {
  const width = Math.round(widthMm / stepMm);
  const zAxis = axes(geo).z;
  const extentZ = geo.dims[2] * geo.spacing[2];
  const height = Math.round(extentZ / stepMm);
  const data = new Float32Array(width * height);
  const volumeMin = getVolumeMin(voxels);

  // Find nearest arch point to arc length sMm
  let bestIdx = 0;
  let bestDiff = Infinity;
  let runningDist = 0;
  for (let i = 0; i < arch.points.length; i++) {
    if (i > 0) {
      runningDist += Math.hypot(
        arch.points[i][0] - arch.points[i - 1][0],
        arch.points[i][1] - arch.points[i - 1][1],
        arch.points[i][2] - arch.points[i - 1][2]
      );
    }
    const diff = Math.abs(runningDist - sMm);
    if (diff < bestDiff) {
      bestDiff = diff;
      bestIdx = i;
    }
  }

  const P = arch.points[bestIdx];
  const N = arch.normals[bestIdx];

  const u = N;
  const v = mul(zAxis, -1);

  const originZ = dot(geo.origin, zAxis);
  const zTopMm = originZ + (geo.dims[2] - 1) * geo.spacing[2];
  const Pz = dot(P, zAxis);
  const centerPx = (width - 1) / 2;

  // Origin at top-left: horizontal center at P, vertical top at zTopMm
  const origin = add(
    sub(P, mul(u, centerPx * stepMm)),
    mul(zAxis, zTopMm - Pz)
  );

  for (let py = 0; py < height; py++) {
    const rowOffset = py * width;
    const vOffset = mul(v, py * stepMm);
    for (let px = 0; px < width; px++) {
      const uOffset = mul(u, px * stepMm);
      const pt = add(origin, add(uOffset, vOffset));
      const val = sampleLinear(voxels, geo, pt);
      data[rowOffset + px] = val !== null ? val : volumeMin;
    }
  }

  return {
    width,
    height,
    data,
    mmPerPixel: stepMm,
    origin,
    u,
    v,
  };
}

