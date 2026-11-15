// Reads the mesh files an intraoral scanner or a lab writes: STL (binary and
// ASCII), PLY (ASCII, binary little- and big-endian) and OBJ. Pure functions,
// no browser and no vtk.js: parse.worker.js calls them off the main thread and
// parse.test.js drives them directly. Everything comes back as flat typed
// arrays in the file's own units (millimetres for every scanner we have seen),
// ready to hand to vtkPolyData.

/** A problem worth showing the doctor in plain words. */
export class MeshError extends Error {}

// ───────────────────────── Which format ─────────────────────────

const ascii = (bytes, from, text) => {
  for (let i = 0; i < text.length; i++) if (bytes[from + i] !== text.charCodeAt(i)) return false;
  return true;
};

/** 'stl' | 'ply' | 'obj', from the file's own bytes, with the name as a hint. */
export function detectFormat(buffer, name = '') {
  const bytes = new Uint8Array(buffer);
  if (bytes.length >= 3 && ascii(bytes, 0, 'ply')) return 'ply';
  // A binary STL is exactly header + count + 50 bytes per facet. Checking the
  // length first matters: plenty of binary files start with the word "solid".
  if (bytes.length >= 84) {
    const count = new DataView(buffer).getUint32(80, true);
    if (bytes.length === 84 + count * 50) return 'stl';
  }
  const ext = name.toLowerCase().split('.').pop();
  if (ext === 'stl' || ext === 'ply' || ext === 'obj') return ext;
  if (ascii(bytes, 0, 'solid')) return 'stl';
  return 'obj';
}

// ───────────────────────── STL ─────────────────────────

export function parseStl(buffer) {
  const bytes = new Uint8Array(buffer);
  if (bytes.length >= 84) {
    const count = new DataView(buffer).getUint32(80, true);
    if (bytes.length === 84 + count * 50) return parseStlBinary(buffer, count);
  }
  return parseStlAscii(new TextDecoder().decode(bytes));
}

function parseStlBinary(buffer, count) {
  if (count === 0) throw new MeshError('This STL file holds no surface.');
  const dv = new DataView(buffer);
  const positions = new Float32Array(count * 9);
  let o = 84;
  let w = 0;
  for (let i = 0; i < count; i++) {
    o += 12; // the stored facet normal: recomputed from the corners, which are always right
    for (let k = 0; k < 9; k++, o += 4) positions[w++] = dv.getFloat32(o, true);
    o += 2; // attribute byte count
  }
  return { format: 'stl', positions, indices: null, colors: null };
}

function parseStlAscii(text) {
  const re = /vertex\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)/g;
  const out = [];
  for (let m = re.exec(text); m; m = re.exec(text)) out.push(+m[1], +m[2], +m[3]);
  if (out.length === 0) throw new MeshError('This STL file holds no surface.');
  if (out.length % 9 !== 0) throw new MeshError('This STL file is incomplete.');
  return { format: 'stl', positions: new Float32Array(out), indices: null, colors: null };
}

// ───────────────────────── PLY ─────────────────────────

const PLY_SIZE = {
  char: 1, int8: 1, uchar: 1, uint8: 1,
  short: 2, int16: 2, ushort: 2, uint16: 2,
  int: 4, int32: 4, uint: 4, uint32: 4,
  float: 4, float32: 4, double: 8, float64: 8,
};

function plyRead(dv, off, type, le) {
  switch (type) {
    case 'char': case 'int8': return dv.getInt8(off);
    case 'uchar': case 'uint8': return dv.getUint8(off);
    case 'short': case 'int16': return dv.getInt16(off, le);
    case 'ushort': case 'uint16': return dv.getUint16(off, le);
    case 'int': case 'int32': return dv.getInt32(off, le);
    case 'uint': case 'uint32': return dv.getUint32(off, le);
    case 'float': case 'float32': return dv.getFloat32(off, le);
    case 'double': case 'float64': return dv.getFloat64(off, le);
    default: throw new MeshError(`This PLY file uses a kind of number CruDoc cannot read (${type}).`);
  }
}

/** The header lines and the byte the data starts at. */
export function parsePlyHeader(buffer) {
  const bytes = new Uint8Array(buffer);
  const limit = Math.min(bytes.length, 1 << 16);
  let end = -1;
  for (let i = 0; i + 10 <= limit; i++) {
    if (bytes[i] === 101 && ascii(bytes, i, 'end_header')) {
      end = i;
      break;
    }
  }
  if (end < 0) throw new MeshError('This PLY file has no readable header.');
  let nl = end;
  while (nl < bytes.length && bytes[nl] !== 10) nl++;
  const text = new TextDecoder().decode(bytes.subarray(0, end));
  const lines = text.split('\n').map((s) => s.trim()).filter(Boolean);

  let format = '';
  const elements = [];
  for (const line of lines) {
    const w = line.split(/\s+/);
    if (w[0] === 'format') format = w[1];
    else if (w[0] === 'element') elements.push({ name: w[1], count: Number(w[2]) || 0, props: [] });
    else if (w[0] === 'property' && elements.length) {
      const el = elements[elements.length - 1];
      if (w[1] === 'list') el.props.push({ name: w[4], list: true, countType: w[2], valueType: w[3] });
      else el.props.push({ name: w[2], list: false, type: w[1] });
    }
  }
  if (!format) throw new MeshError('This PLY file does not say how it is written.');
  if (!['ascii', 'binary_little_endian', 'binary_big_endian'].includes(format)) {
    throw new MeshError(`This PLY file is written in a way CruDoc cannot read (${format}).`);
  }
  return { format, elements, dataStart: nl + 1 };
}

// Where x, y, z and the colours sit in a vertex record.
function vertexPlan(el) {
  const at = {};
  for (const p of el.props) at[p.name] = p;
  const xyz = ['x', 'y', 'z'].map((k) => at[k]);
  if (xyz.some((p) => !p)) throw new MeshError('This PLY file has no point positions.');
  const names = at.red ? ['red', 'green', 'blue'] : ['r', 'g', 'b'];
  const rgb = names.map((k) => at[k]);
  return { xyz, rgb: rgb.every(Boolean) ? rgb : null };
}

export function parsePly(buffer) {
  const { format, elements, dataStart } = parsePlyHeader(buffer);
  const vertexEl = elements.find((e) => e.name === 'vertex');
  const faceEl = elements.find((e) => e.name === 'face');
  if (!vertexEl || !vertexEl.count) throw new MeshError('This PLY file holds no points.');
  const plan = vertexPlan(vertexEl);
  return format === 'ascii'
    ? plyAscii(buffer, dataStart, elements, vertexEl, faceEl, plan)
    : plyBinary(buffer, dataStart, elements, vertexEl, faceEl, plan, format === 'binary_little_endian');
}

const floatType = (type) => type === 'float' || type === 'float32' || type === 'double' || type === 'float64';
// Colours are 0-255 bytes in nearly every file; a float file means 0-1.
const colourScale = (prop) => (floatType(prop.type) ? 255 : 1);
const toByte = (v) => Math.max(0, Math.min(255, Math.round(v)));

function plyBinary(buffer, dataStart, elements, vertexEl, faceEl, plan, le) {
  const dv = new DataView(buffer);
  let off = dataStart;

  // Fixed-size records only: a per-vertex list property would make the stride vary.
  let stride = 0;
  const offsets = new Map();
  for (const p of vertexEl.props) {
    if (p.list) throw new MeshError('This PLY file stores its points in a way CruDoc cannot read.');
    const size = PLY_SIZE[p.type];
    if (!size) throw new MeshError(`This PLY file uses a kind of number CruDoc cannot read (${p.type}).`);
    offsets.set(p, stride);
    stride += size;
  }
  const n = vertexEl.count;
  if (off + n * stride > buffer.byteLength) throw new MeshError('This PLY file is incomplete.');

  const positions = new Float32Array(n * 3);
  const colors = plan.rgb ? new Uint8Array(n * 3) : null;
  const scale = plan.rgb ? colourScale(plan.rgb[0]) : 1;
  for (let i = 0; i < n; i++) {
    const rec = off + i * stride;
    for (let k = 0; k < 3; k++) {
      const p = plan.xyz[k];
      positions[i * 3 + k] = plyRead(dv, rec + offsets.get(p), p.type, le);
    }
    if (colors) {
      for (let k = 0; k < 3; k++) {
        const p = plan.rgb[k];
        colors[i * 3 + k] = toByte(plyRead(dv, rec + offsets.get(p), p.type, le) * scale);
      }
    }
  }
  off += n * stride;

  // Elements written between the points and the faces (edges, materials) are stepped over.
  for (const el of elements) {
    if (el === vertexEl) continue;
    if (el === faceEl) break;
    off = skipElement(dv, off, el, le, buffer.byteLength);
  }

  const indices = faceEl && faceEl.count ? plyFacesBinary(dv, off, faceEl, le, buffer.byteLength, n) : null;
  return { format: 'ply', positions, indices, colors };
}

function skipElement(dv, off, el, le, limit) {
  if (el.props.every((p) => !p.list)) {
    const stride = el.props.reduce((s, p) => s + (PLY_SIZE[p.type] || 0), 0);
    return off + el.count * stride;
  }
  for (let i = 0; i < el.count; i++) {
    for (const p of el.props) {
      if (!p.list) {
        off += PLY_SIZE[p.type] || 0;
        continue;
      }
      if (off >= limit) throw new MeshError('This PLY file is incomplete.');
      off += PLY_SIZE[p.countType] + plyRead(dv, off, p.countType, le) * PLY_SIZE[p.valueType];
    }
  }
  return off;
}

function plyFacesBinary(dv, off, faceEl, le, limit, pointCount) {
  const list = faceEl.props.find((p) => p.list);
  if (!list) throw new MeshError('This PLY file does not list its triangles.');
  const at = faceEl.props.indexOf(list);
  const before = faceEl.props.slice(0, at).reduce((s, p) => s + (PLY_SIZE[p.type] || 0), 0);
  const after = faceEl.props.slice(at + 1);
  const out = [];
  const size = PLY_SIZE[list.valueType];
  for (let f = 0; f < faceEl.count; f++) {
    off += before;
    if (off + PLY_SIZE[list.countType] > limit) throw new MeshError('This PLY file is incomplete.');
    const count = plyRead(dv, off, list.countType, le);
    off += PLY_SIZE[list.countType];
    if (off + count * size > limit) throw new MeshError('This PLY file is incomplete.');
    const face = [];
    for (let i = 0; i < count; i++) face.push(plyRead(dv, off + i * size, list.valueType, le));
    off += count * size;
    fan(face, out, pointCount);
    for (const p of after) {
      off += p.list ? PLY_SIZE[p.countType] + plyRead(dv, off, p.countType, le) * PLY_SIZE[p.valueType] : PLY_SIZE[p.type] || 0;
    }
  }
  return out.length ? new Uint32Array(out) : null;
}

function plyAscii(buffer, dataStart, elements, vertexEl, faceEl, plan) {
  const body = new TextDecoder().decode(new Uint8Array(buffer, dataStart));
  const tok = tokens(body);
  const n = vertexEl.count;
  const positions = new Float32Array(n * 3);
  const colors = plan.rgb ? new Uint8Array(n * 3) : null;
  const scale = plan.rgb ? colourScale(plan.rgb[0]) : 1;
  const slot = new Map(vertexEl.props.map((p, i) => [p, i]));

  for (let i = 0; i < n; i++) {
    const rec = [];
    for (let k = 0; k < vertexEl.props.length; k++) rec.push(tok.next());
    if (rec.some((v) => v === undefined)) throw new MeshError('This PLY file is incomplete.');
    for (let k = 0; k < 3; k++) positions[i * 3 + k] = rec[slot.get(plan.xyz[k])];
    if (colors) for (let k = 0; k < 3; k++) colors[i * 3 + k] = toByte(rec[slot.get(plan.rgb[k])] * scale);
  }
  for (const el of elements) {
    if (el === vertexEl) continue;
    if (el === faceEl) break;
    for (let i = 0; i < el.count; i++) {
      for (const p of el.props) {
        const v = tok.next();
        if (p.list) for (let k = 0; k < v; k++) tok.next();
      }
    }
  }
  const out = [];
  if (faceEl) {
    for (let f = 0; f < faceEl.count; f++) {
      for (const p of faceEl.props) {
        const count = tok.next();
        if (count === undefined) throw new MeshError('This PLY file is incomplete.');
        if (!p.list) continue;
        const face = [];
        for (let i = 0; i < count; i++) face.push(tok.next());
        fan(face, out, n);
      }
    }
  }
  return { format: 'ply', positions, indices: out.length ? new Uint32Array(out) : null, colors };
}

// A cursor over whitespace-separated numbers, without cutting the text up.
function tokens(text) {
  let i = 0;
  const len = text.length;
  return {
    next() {
      while (i < len && text.charCodeAt(i) <= 32) i++;
      if (i >= len) return undefined;
      const from = i;
      while (i < len && text.charCodeAt(i) > 32) i++;
      return Number(text.slice(from, i));
    },
  };
}

// A polygon becomes triangles around its first corner; a corner that points
// outside the point list is dropped rather than drawn wrong.
function fan(face, out, pointCount) {
  for (let i = 2; i < face.length; i++) {
    const a = face[0];
    const b = face[i - 1];
    const c = face[i];
    if (!(a >= 0 && b >= 0 && c >= 0 && a < pointCount && b < pointCount && c < pointCount)) continue;
    out.push(a, b, c);
  }
}

// ───────────────────────── OBJ ─────────────────────────

export function parseObj(buffer) {
  const text = new TextDecoder().decode(new Uint8Array(buffer));
  const pts = [];
  const faces = [];
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (!line || line.charCodeAt(0) === 35) continue;
    const w = line.split(/\s+/);
    if (w[0] === 'v') pts.push(+w[1], +w[2], +w[3]);
    else if (w[0] === 'f') {
      // "f 1 2 3", "f 1/1 2/2 3/3", "f 1//1 2//2 3//3"; a negative index counts back.
      const face = [];
      for (let i = 1; i < w.length; i++) {
        const v = parseInt(w[i].split('/')[0], 10);
        if (Number.isNaN(v)) continue;
        face.push(v > 0 ? v - 1 : pts.length / 3 + v);
      }
      faces.push(face);
    }
  }
  if (!pts.length) throw new MeshError('This OBJ file holds no points.');
  const out = [];
  for (const face of faces) fan(face, out, pts.length / 3);
  return { format: 'obj', positions: new Float32Array(pts), indices: out.length ? new Uint32Array(out) : null, colors: null };
}

// ───────────────────────── Normals, welding, bounds ─────────────────────────

/** [minX, maxX, minY, maxY, minZ, maxZ] over every point. */
export function boundsOf(positions) {
  if (!positions.length) return [0, 0, 0, 0, 0, 0];
  const b = [Infinity, -Infinity, Infinity, -Infinity, Infinity, -Infinity];
  for (let i = 0; i < positions.length; i += 3) {
    for (let k = 0; k < 3; k++) {
      const v = positions[i + k];
      if (v < b[k * 2]) b[k * 2] = v;
      if (v > b[k * 2 + 1]) b[k * 2 + 1] = v;
    }
  }
  return b;
}

/** Smooth normals: every corner gets the sum of the triangles it belongs to. */
export function smoothNormals(positions, indices) {
  const normals = new Float32Array(positions.length);
  const count = indices ? indices.length : positions.length / 3;
  for (let t = 0; t + 2 < count; t += 3) {
    const a = (indices ? indices[t] : t) * 3;
    const b = (indices ? indices[t + 1] : t + 1) * 3;
    const c = (indices ? indices[t + 2] : t + 2) * 3;
    const ux = positions[b] - positions[a];
    const uy = positions[b + 1] - positions[a + 1];
    const uz = positions[b + 2] - positions[a + 2];
    const vx = positions[c] - positions[a];
    const vy = positions[c + 1] - positions[a + 1];
    const vz = positions[c + 2] - positions[a + 2];
    // Left unnormalized on purpose: a bigger triangle then counts for more.
    const nx = uy * vz - uz * vy;
    const ny = uz * vx - ux * vz;
    const nz = ux * vy - uy * vx;
    normals[a] += nx; normals[a + 1] += ny; normals[a + 2] += nz;
    normals[b] += nx; normals[b + 1] += ny; normals[b + 2] += nz;
    normals[c] += nx; normals[c + 1] += ny; normals[c + 2] += nz;
  }
  for (let i = 0; i < normals.length; i += 3) {
    const len = Math.hypot(normals[i], normals[i + 1], normals[i + 2]);
    if (len > 0) {
      normals[i] /= len;
      normals[i + 1] /= len;
      normals[i + 2] /= len;
    }
  }
  return normals;
}

const WELD_BITS = 17; // three axes packed into one number that stays exact (3 × 17 < 53)
const WELD_STEPS = (1 << WELD_BITS) - 1;

/**
 * An STL is a heap of loose triangles: the same corner is written once per
 * triangle, so nothing can be shaded smoothly. Corners that land on the same
 * spot (about a thousandth of a millimetre apart on a scan-sized mesh) become
 * one point with one normal.
 */
export function weld(positions, colors = null) {
  const b = boundsOf(positions);
  const span = Math.max(b[1] - b[0], b[3] - b[2], b[5] - b[4]) || 1;
  const q = WELD_STEPS / span;
  const seen = new Map();
  const n = positions.length / 3;
  const indices = new Uint32Array(n);
  const outPos = new Float32Array(positions.length);
  const outCol = colors ? new Uint8Array(colors.length) : null;
  let kept = 0;
  for (let i = 0; i < n; i++) {
    const x = Math.round((positions[i * 3] - b[0]) * q);
    const y = Math.round((positions[i * 3 + 1] - b[2]) * q);
    const z = Math.round((positions[i * 3 + 2] - b[4]) * q);
    const key = (x * (WELD_STEPS + 1) + y) * (WELD_STEPS + 1) + z;
    let at = seen.get(key);
    if (at === undefined) {
      at = kept++;
      seen.set(key, at);
      outPos[at * 3] = positions[i * 3];
      outPos[at * 3 + 1] = positions[i * 3 + 1];
      outPos[at * 3 + 2] = positions[i * 3 + 2];
      if (outCol) for (let k = 0; k < 3; k++) outCol[at * 3 + k] = colors[i * 3 + k];
    }
    indices[i] = at;
  }
  return {
    positions: outPos.slice(0, kept * 3),
    colors: outCol ? outCol.slice(0, kept * 3) : null,
    indices,
  };
}

/** Above this many loose corners, welding costs more time than it is worth. */
export const WELD_LIMIT = 1_500_000;

/**
 * Reads one mesh file and returns everything the 3D view needs:
 * `{ format, positions, indices, normals, colors, points, triangles, bounds, welded }`.
 * Positions stay in the file's own units: nothing is moved or scaled.
 */
export function parseMesh(buffer, name = '') {
  const format = detectFormat(buffer, name);
  const mesh = format === 'ply' ? parsePly(buffer) : format === 'obj' ? parseObj(buffer) : parseStl(buffer);
  let { positions, indices, colors } = mesh;
  if (!positions.length) throw new MeshError('This file holds no surface.');
  if (positions.length % 3 !== 0) throw new MeshError('This file is incomplete.');

  let welded = false;
  if (!indices) {
    if (positions.length % 9 !== 0) throw new MeshError('This file is incomplete.');
    if (positions.length / 3 <= WELD_LIMIT) {
      const w = weld(positions, colors);
      positions = w.positions;
      colors = w.colors;
      indices = w.indices;
      welded = true;
    }
  }
  const triangles = indices ? indices.length / 3 : positions.length / 9;
  if (!triangles) throw new MeshError('This file holds no triangles.');
  return {
    format,
    positions,
    indices,
    normals: smoothNormals(positions, indices),
    colors,
    points: positions.length / 3,
    triangles,
    bounds: boundsOf(positions),
    welded,
  };
}
