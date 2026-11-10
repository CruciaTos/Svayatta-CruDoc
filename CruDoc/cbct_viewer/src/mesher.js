// Surface meshes from a voxel grid: smoothing and marching cubes on typed arrays.
// No DOM and no vtk objects (only vtk's case table), so it runs in a worker and
// in node tests. vtk's own ImageMarchingCubes is not used: it ignores the scan's
// direction and builds plain JS arrays voxel by voxel, which is far slower.
import caseTable from '@kitware/vtk.js/Filters/General/ImageMarchingCubes/caseTable.js';

// Corners of a cell, numbered as vtk's table expects:
// 0 (0,0,0) 1 (1,0,0) 2 (0,1,0) 3 (1,1,0) 4 (0,0,1) 5 (1,0,1) 6 (0,1,1) 7 (1,1,1).
// Bit b of the case number is corner CASE_CORNER[b].
const CASE_CORNER = [0, 1, 3, 2, 4, 5, 7, 6];
const CASES = new Int8Array(256 * 16);
for (let c = 0; c < 256; c++) {
  const row = caseTable.getCase(c);
  for (let n = 0; n < 16; n++) CASES[c * 16 + n] = row[n];
}

// Smooths the grid in place: `passes` rounds of a [1 2 1] / 4 filter along each axis.
export function blur(f, dims, passes) {
  const [nx, ny, nz] = dims;
  const strides = [1, nx, nx * ny];
  const counts = [nx, ny, nz];
  const line = new Float32Array(Math.max(nx, ny, nz));
  for (let p = 0; p < passes; p++) {
    for (let axis = 0; axis < 3; axis++) {
      const n = counts[axis];
      if (n < 3) continue;
      const st = strides[axis];
      const others = axis === 0 ? [[ny, nx], [nz, nx * ny]] : axis === 1 ? [[nx, 1], [nz, nx * ny]] : [[nx, 1], [ny, nx]];
      const [[na, sa], [nb, sb]] = others;
      for (let b = 0; b < nb; b++) {
        for (let a = 0; a < na; a++) {
          const start = a * sa + b * sb;
          for (let i = 0; i < n; i++) line[i] = f[start + i * st];
          f[start] = (3 * line[0] + line[1]) / 4;
          for (let i = 1; i < n - 1; i++) f[start + i * st] = (line[i - 1] + 2 * line[i] + line[i + 1]) / 4;
          f[start + (n - 1) * st] = (line[n - 2] + 3 * line[n - 1]) / 4;
        }
      }
    }
  }
  return f;
}

// One isosurface of the grid `f` (dims [nx, ny, nz]) at `iso`.
// geo: { spacing, origin, direction } of the grid; direction holds the three
// axis directions one after another (vtk / Cornerstone layout).
// Returns { points, normals, polys } ready for vtkPolyData (polys in vtk cell
// layout: 3, a, b, c, ...). Normals point toward lower values (out of bone).
export function isosurface(f, dims, iso, geo) {
  const [nx, ny, nz] = dims;
  const slice = nx * ny;
  const sp = geo.spacing;
  const o = geo.origin;
  const d = geo.direction;

  let cap = 1 << 16;
  let pts = new Float32Array(cap * 3);
  let nrm = new Float32Array(cap * 3);
  let nv = 0;
  let tcap = 1 << 17;
  let tri = new Uint32Array(tcap * 4);
  let nt = 0;

  // Vertex ids of the edges already cut: x and y edges on the bottom and top
  // layer of the current row of cells, z edges between them.
  let xb = new Int32Array(slice).fill(-1);
  let yb = new Int32Array(slice).fill(-1);
  let xt = new Int32Array(slice).fill(-1);
  let yt = new Int32Array(slice).fill(-1);
  const zm = new Int32Array(slice);

  const g0 = [0, 0, 0];
  const g1 = [0, 0, 0];
  // Gradient at a grid point, in index units, into g.
  const grad = (i, j, k, p, g) => {
    g[0] = i === 0 ? f[p + 1] - f[p] : i === nx - 1 ? f[p] - f[p - 1] : (f[p + 1] - f[p - 1]) / 2;
    g[1] = j === 0 ? f[p + nx] - f[p] : j === ny - 1 ? f[p] - f[p - nx] : (f[p + nx] - f[p - nx]) / 2;
    g[2] = k === 0 ? f[p + slice] - f[p] : k === nz - 1 ? f[p] - f[p - slice] : (f[p + slice] - f[p - slice]) / 2;
  };

  // A new vertex on the edge from grid point a to grid point a + step along `axis`.
  const vertex = (a, axis) => {
    const step = axis === 0 ? 1 : axis === 1 ? nx : slice;
    const b = a + step;
    const fa = f[a];
    const t = (iso - fa) / (f[b] - fa);
    const k = (a / slice) | 0;
    const r = a - k * slice;
    const j = (r / nx) | 0;
    const i = r - j * nx;
    const idx = [i, j, k];
    grad(i, j, k, a, g0);
    idx[axis] += 1;
    grad(idx[0], idx[1], idx[2], b, g1);
    idx[axis] -= 1 - t;
    if (nv === cap) {
      cap *= 2;
      const p2 = new Float32Array(cap * 3);
      p2.set(pts);
      pts = p2;
      const n2 = new Float32Array(cap * 3);
      n2.set(nrm);
      nrm = n2;
    }
    const x = idx[0] * sp[0];
    const y = idx[1] * sp[1];
    const z = idx[2] * sp[2];
    const q = nv * 3;
    pts[q] = o[0] + x * d[0] + y * d[3] + z * d[6];
    pts[q + 1] = o[1] + x * d[1] + y * d[4] + z * d[7];
    pts[q + 2] = o[2] + x * d[2] + y * d[5] + z * d[8];
    // Normal = minus the gradient, in world units.
    const gx = -(g0[0] + t * (g1[0] - g0[0])) / sp[0];
    const gy = -(g0[1] + t * (g1[1] - g0[1])) / sp[1];
    const gz = -(g0[2] + t * (g1[2] - g0[2])) / sp[2];
    let wx = gx * d[0] + gy * d[3] + gz * d[6];
    let wy = gx * d[1] + gy * d[4] + gz * d[7];
    let wz = gx * d[2] + gy * d[5] + gz * d[8];
    const len = Math.hypot(wx, wy, wz) || 1;
    nrm[q] = wx / len;
    nrm[q + 1] = wy / len;
    nrm[q + 2] = wz / len;
    return nv++;
  };

  const ids = new Int32Array(12);
  for (let k = 0; k < nz - 1; k++) {
    xt.fill(-1);
    yt.fill(-1);
    zm.fill(-1);
    for (let j = 0; j < ny - 1; j++) {
      for (let i = 0; i < nx - 1; i++) {
        const p = k * slice + j * nx + i;
        const v0 = f[p];
        const v1 = f[p + 1];
        const v2 = f[p + nx];
        const v3 = f[p + nx + 1];
        const v4 = f[p + slice];
        const v5 = f[p + slice + 1];
        const v6 = f[p + slice + nx];
        const v7 = f[p + slice + nx + 1];
        const c =
          (v0 >= iso ? 1 : 0) | (v1 >= iso ? 2 : 0) | (v3 >= iso ? 4 : 0) | (v2 >= iso ? 8 : 0) |
          (v4 >= iso ? 16 : 0) | (v5 >= iso ? 32 : 0) | (v7 >= iso ? 64 : 0) | (v6 >= iso ? 128 : 0);
        if (c === 0 || c === 255) continue;
        const e = j * nx + i;
        ids.fill(-1);
        for (let n = c * 16; CASES[n] >= 0; n++) {
          const edge = CASES[n];
          if (ids[edge] < 0) {
            let id;
            switch (edge) {
              case 0: id = xb[e] >= 0 ? xb[e] : (xb[e] = vertex(p, 0)); break;
              case 1: id = yb[e + 1] >= 0 ? yb[e + 1] : (yb[e + 1] = vertex(p + 1, 1)); break;
              case 2: id = xb[e + nx] >= 0 ? xb[e + nx] : (xb[e + nx] = vertex(p + nx, 0)); break;
              case 3: id = yb[e] >= 0 ? yb[e] : (yb[e] = vertex(p, 1)); break;
              case 4: id = xt[e] >= 0 ? xt[e] : (xt[e] = vertex(p + slice, 0)); break;
              case 5: id = yt[e + 1] >= 0 ? yt[e + 1] : (yt[e + 1] = vertex(p + slice + 1, 1)); break;
              case 6: id = xt[e + nx] >= 0 ? xt[e + nx] : (xt[e + nx] = vertex(p + slice + nx, 0)); break;
              case 7: id = yt[e] >= 0 ? yt[e] : (yt[e] = vertex(p + slice, 1)); break;
              case 8: id = zm[e] >= 0 ? zm[e] : (zm[e] = vertex(p, 2)); break;
              case 9: id = zm[e + 1] >= 0 ? zm[e + 1] : (zm[e + 1] = vertex(p + 1, 2)); break;
              case 10: id = zm[e + nx] >= 0 ? zm[e + nx] : (zm[e + nx] = vertex(p + nx, 2)); break;
              default: id = zm[e + nx + 1] >= 0 ? zm[e + nx + 1] : (zm[e + nx + 1] = vertex(p + nx + 1, 2));
            }
            ids[edge] = id;
          }
        }
        for (let n = c * 16; CASES[n] >= 0; n += 3) {
          if (nt === tcap) {
            tcap *= 2;
            const t2 = new Uint32Array(tcap * 4);
            t2.set(tri);
            tri = t2;
          }
          const q = nt * 4;
          tri[q] = 3;
          tri[q + 1] = ids[CASES[n]];
          tri[q + 2] = ids[CASES[n + 1]];
          tri[q + 3] = ids[CASES[n + 2]];
          nt++;
        }
      }
    }
    // The top layer becomes the bottom of the next row of cells.
    [xb, xt] = [xt, xb];
    [yb, yt] = [yt, yb];
  }
  return { points: pts.slice(0, nv * 3), normals: nrm.slice(0, nv * 3), polys: tri.slice(0, nt * 4) };
}

// Everything a worker does for one request: smooth once, then one mesh per iso value.
export function buildMeshes({ grid, dims, geo, isos, passes }) {
  if (passes > 0) blur(grid, dims, passes);
  return isos.map((iso) => isosurface(grid, dims, iso, geo));
}
