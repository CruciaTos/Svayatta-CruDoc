// Writes a synthetic "intraoral scan" for testing the scan viewer: an arch-
// shaped tube with tooth-sized bumps, in the three formats a clinic sends us.
//
//   node tools/make_mesh.mjs dev/mesh
//
// Lands as arch.stl (binary), arch.ply (binary little-endian, with colours)
// and arch.obj. Sizes are millimetres, like a real scan.
import fs from 'node:fs';
import path from 'node:path';

const out = path.resolve(process.cwd(), process.argv[2] || 'dev/mesh');
fs.mkdirSync(out, { recursive: true });

const NU = 240; // steps along the arch
const NV = 24; // steps around the tube
const A = 25; // arch half-width, mm
const B = 20; // arch depth, mm

// One ring of points per step along the arch curve.
function build() {
  const points = [];
  const colours = [];
  for (let i = 0; i < NU; i++) {
    const u = i / (NU - 1);
    const t = -1.2 + u * 2.4;
    const cx = A * Math.sin(t);
    const cy = -B * Math.cos(t);
    // The curve's own direction, and a sideways axis at right angles to it.
    const dx = A * Math.cos(t);
    const dy = B * Math.sin(t);
    const dl = Math.hypot(dx, dy);
    const sx = -dy / dl;
    const sy = dx / dl;
    const bump = 1.2 * Math.sin(u * Math.PI * 2 * 14);
    const r = 4 + bump;
    for (let j = 0; j < NV; j++) {
      const a = (j / NV) * Math.PI * 2;
      const radial = Math.cos(a) * r;
      points.push(cx + sx * radial, cy + sy * radial, Math.sin(a) * r);
      // Pink at the gum end, ivory at the biting end, like a colour scan.
      const up = (Math.sin(a) + 1) / 2;
      colours.push(Math.round(205 + 50 * up), Math.round(140 + 85 * up), Math.round(135 + 66 * up));
    }
  }
  const faces = [];
  for (let i = 0; i < NU - 1; i++) {
    for (let j = 0; j < NV; j++) {
      const j2 = (j + 1) % NV;
      const a = i * NV + j;
      const b = i * NV + j2;
      const c = (i + 1) * NV + j2;
      const d = (i + 1) * NV + j;
      faces.push([a, b, c], [a, c, d]);
    }
  }
  return { points, colours, faces };
}

const { points, colours, faces } = build();

// ---- STL, binary: every triangle writes its own three corners ----
{
  const buf = Buffer.alloc(84 + faces.length * 50);
  buf.write('CruDoc synthetic arch scan', 0, 'ascii');
  buf.writeUInt32LE(faces.length, 80);
  let o = 84;
  for (const f of faces) {
    o += 12; // normal left at zero: the viewer recomputes it from the corners
    for (const v of f) {
      for (let k = 0; k < 3; k++) {
        buf.writeFloatLE(points[v * 3 + k], o);
        o += 4;
      }
    }
    o += 2;
  }
  fs.writeFileSync(path.join(out, 'arch.stl'), buf);
}

// ---- PLY, binary little-endian, with per-point colour ----
{
  const n = points.length / 3;
  const header = [
    'ply',
    'format binary_little_endian 1.0',
    'comment CruDoc synthetic arch scan',
    `element vertex ${n}`,
    'property float x',
    'property float y',
    'property float z',
    'property uchar red',
    'property uchar green',
    'property uchar blue',
    `element face ${faces.length}`,
    'property list uchar int vertex_indices',
    'end_header',
    '',
  ].join('\n');
  const body = Buffer.alloc(n * 15 + faces.length * 13);
  let o = 0;
  for (let i = 0; i < n; i++) {
    for (let k = 0; k < 3; k++) {
      body.writeFloatLE(points[i * 3 + k], o);
      o += 4;
    }
    for (let k = 0; k < 3; k++) body.writeUInt8(colours[i * 3 + k], o++);
  }
  for (const f of faces) {
    body.writeUInt8(3, o++);
    for (const v of f) {
      body.writeInt32LE(v, o);
      o += 4;
    }
  }
  fs.writeFileSync(path.join(out, 'arch.ply'), Buffer.concat([Buffer.from(header, 'ascii'), body]));
}

// ---- OBJ ----
{
  const lines = ['# CruDoc synthetic arch scan'];
  for (let i = 0; i < points.length; i += 3) lines.push(`v ${points[i].toFixed(4)} ${points[i + 1].toFixed(4)} ${points[i + 2].toFixed(4)}`);
  for (const f of faces) lines.push(`f ${f[0] + 1} ${f[1] + 1} ${f[2] + 1}`);
  fs.writeFileSync(path.join(out, 'arch.obj'), `${lines.join('\n')}\n`);
}

const meta = { points: points.length / 3, triangles: faces.length };
fs.writeFileSync(path.join(out, 'arch.json'), JSON.stringify(meta, null, 2));
console.log(`Wrote arch.stl, arch.ply and arch.obj to ${out}`);
console.log(`${meta.triangles.toLocaleString('en-US')} triangles, ${meta.points.toLocaleString('en-US')} points`);
