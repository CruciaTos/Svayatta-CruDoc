// node --test "src/mesh/*.test.js"
import test from 'node:test';
import assert from 'node:assert/strict';
import { parseMesh, parseStl, parsePly, parseObj, parsePlyHeader, detectFormat, smoothNormals, weld, boundsOf, MeshError } from './parse.js';

// A unit square made of two triangles, in the z = 0 plane.
const QUAD = [
  [[0, 0, 0], [1, 0, 0], [1, 1, 0]],
  [[0, 0, 0], [1, 1, 0], [0, 1, 0]],
];

function binaryStl(triangles, header = 'CruDoc test') {
  const buf = new ArrayBuffer(84 + triangles.length * 50);
  const dv = new DataView(buf);
  const bytes = new Uint8Array(buf);
  for (let i = 0; i < header.length; i++) bytes[i] = header.charCodeAt(i);
  dv.setUint32(80, triangles.length, true);
  let o = 84;
  for (const tri of triangles) {
    o += 12; // the stored normal is left at zero: the reader recomputes it
    for (const corner of tri) for (const v of corner) {
      dv.setFloat32(o, v, true);
      o += 4;
    }
    o += 2;
  }
  return buf;
}

function asciiStl(triangles) {
  const lines = ['solid test'];
  for (const tri of triangles) {
    lines.push('  facet normal 0 0 0', '    outer loop');
    for (const c of tri) lines.push(`      vertex ${c[0]} ${c[1]} ${c[2]}`);
    lines.push('    endloop', '  endfacet');
  }
  lines.push('endsolid test');
  return new TextEncoder().encode(lines.join('\n')).buffer;
}

const bytesOf = (...parts) => {
  const total = parts.reduce((s, p) => s + p.length, 0);
  const out = new Uint8Array(total);
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out.buffer;
};
const text = (s) => new TextEncoder().encode(s);

test('binary STL: triangles, welding and bounds', () => {
  const m = parseMesh(binaryStl(QUAD), 'arch.stl');
  assert.equal(m.format, 'stl');
  assert.equal(m.triangles, 2);
  assert.equal(m.welded, true);
  assert.equal(m.points, 4); // six loose corners, four distinct spots
  assert.deepEqual(m.bounds, [0, 1, 0, 1, 0, 0]);
  assert.equal(m.normals.length, m.positions.length);
  assert.equal(m.colors, null);
});

test('binary STL whose header starts with the word solid is still read as binary', () => {
  const buf = binaryStl(QUAD, 'solid exported by a scanner');
  assert.equal(detectFormat(buf, ''), 'stl');
  assert.equal(parseStl(buf).positions.length, 18);
});

test('ASCII STL, including negative exponents', () => {
  const m = parseMesh(asciiStl([[[1e-5, 0, 0], [1, -2.5e-3, 0], [0, 1, 0]]]), 'bite.stl');
  assert.equal(m.triangles, 1);
  assert.equal(m.points, 3);
  assert.ok(Math.abs(m.positions[0] - 1e-5) < 1e-9);
  assert.ok(Math.abs(m.positions[4] + 2.5e-3) < 1e-9);
});

test('empty and broken STL files say so in plain words', () => {
  assert.throws(() => parseStl(binaryStl([])), MeshError);
  assert.throws(() => parseMesh(text('solid x\nendsolid x').buffer, 'x.stl'), MeshError);
});

test('ASCII PLY: colours, a quad face and a property the reader does not need', () => {
  const ply = [
    'ply',
    'format ascii 1.0',
    'comment made by a test',
    'element vertex 4',
    'property float x',
    'property float y',
    'property float z',
    'property float quality',
    'property uchar red',
    'property uchar green',
    'property uchar blue',
    'element face 1',
    'property list uchar int vertex_indices',
    'end_header',
    '0 0 0 0.5 255 0 0',
    '1 0 0 0.5 0 255 0',
    '1 1 0 0.5 0 0 255',
    '0 1 0 0.5 255 255 255',
    '4 0 1 2 3',
  ].join('\n');
  const m = parseMesh(text(ply).buffer, 'scan.ply');
  assert.equal(m.format, 'ply');
  assert.equal(m.points, 4);
  assert.equal(m.triangles, 2); // the quad is split
  assert.equal(m.welded, false); // the file already shares its corners
  assert.deepEqual([...m.indices], [0, 1, 2, 0, 2, 3]);
  assert.deepEqual([...m.colors.slice(0, 6)], [255, 0, 0, 0, 255, 0]);
});

test('ASCII PLY: float colours are stretched to bytes', () => {
  const ply = [
    'ply', 'format ascii 1.0',
    'element vertex 3',
    'property float x', 'property float y', 'property float z',
    'property float r', 'property float g', 'property float b',
    'element face 1', 'property list uchar int vertex_indices',
    'end_header',
    '0 0 0 1 0 0', '1 0 0 0 1 0', '0 1 0 0 0 0.5',
    '3 0 1 2',
  ].join('\n');
  const m = parsePly(text(ply).buffer);
  assert.deepEqual([...m.colors], [255, 0, 0, 0, 255, 0, 0, 0, 128]);
});

function binaryPly({ le = true, withColour = true, faceCount = 2 } = {}) {
  const header = [
    'ply',
    `format ${le ? 'binary_little_endian' : 'binary_big_endian'} 1.0`,
    'element vertex 4',
    'property float x',
    'property float y',
    'property float z',
    ...(withColour ? ['property uchar red', 'property uchar green', 'property uchar blue'] : []),
    'element face ' + faceCount,
    'property list uchar int vertex_indices',
    'end_header',
    '',
  ].join('\n');
  const stride = 12 + (withColour ? 3 : 0);
  const body = new Uint8Array(4 * stride + faceCount * 13);
  const dv = new DataView(body.buffer);
  const pts = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]];
  pts.forEach((p, i) => {
    const at = i * stride;
    p.forEach((v, k) => dv.setFloat32(at + k * 4, v, le));
    if (withColour) for (let k = 0; k < 3; k++) dv.setUint8(at + 12 + k, i * 60 + k);
  });
  let o = 4 * stride;
  const faces = [[0, 1, 2], [0, 2, 3]].slice(0, faceCount);
  for (const f of faces) {
    dv.setUint8(o, 3);
    o += 1;
    for (const i of f) {
      dv.setInt32(o, i, le);
      o += 4;
    }
  }
  return bytesOf(text(header), body);
}

test('binary PLY, little-endian, with colours', () => {
  const m = parseMesh(binaryPly(), 'upper.ply');
  assert.equal(m.triangles, 2);
  assert.equal(m.points, 4);
  assert.deepEqual([...m.indices], [0, 1, 2, 0, 2, 3]);
  assert.deepEqual([...m.colors.slice(3, 6)], [60, 61, 62]);
  assert.deepEqual(m.bounds, [0, 1, 0, 1, 0, 0]);
});

test('binary PLY, big-endian, without colours', () => {
  const m = parseMesh(binaryPly({ le: false, withColour: false }), 'lower.ply');
  assert.equal(m.triangles, 2);
  assert.equal(m.colors, null);
  assert.deepEqual(m.bounds, [0, 1, 0, 1, 0, 0]);
});

test('PLY header: where the data starts, with CRLF line ends', () => {
  const head = 'ply\r\nformat ascii 1.0\r\nelement vertex 1\r\nproperty float x\r\nproperty float y\r\nproperty float z\r\nend_header\r\n';
  const { format, elements, dataStart } = parsePlyHeader(bytesOf(text(head), text('0 0 0\n')));
  assert.equal(format, 'ascii');
  assert.equal(elements[0].count, 1);
  assert.equal(dataStart, head.length);
});

test('a PLY that stops in the middle says so', () => {
  const full = new Uint8Array(binaryPly());
  assert.throws(() => parsePly(full.slice(0, full.length - 20).buffer), MeshError);
});

test('a PLY CruDoc cannot read is named, not guessed at', () => {
  const head = text('ply\nformat binary_wobbly 1.0\nelement vertex 1\nproperty float x\nend_header\n');
  assert.throws(() => parsePlyHeader(head.buffer), /binary_wobbly/);
  assert.throws(() => parsePlyHeader(text('solid nonsense').buffer), /no readable header/);
});

test('OBJ: slashes, negative indices and a quad', () => {
  const obj = [
    '# a lab design',
    'v 0 0 0', 'v 1 0 0', 'v 1 1 0', 'v 0 1 0',
    'vn 0 0 1',
    'f 1//1 2//1 3//1',
    'f -4 -2 -1',
  ].join('\n');
  const m = parseObj(text(obj).buffer);
  assert.deepEqual([...m.indices], [0, 1, 2, 0, 2, 3]);
  assert.equal(parseMesh(text(obj).buffer, 'crown.obj').triangles, 2);
});

test('welding keeps every distinct spot and nothing more', () => {
  const soup = new Float32Array(QUAD.flat(2));
  const w = weld(soup);
  assert.equal(w.positions.length, 12);
  assert.deepEqual([...w.indices], [0, 1, 2, 0, 2, 3]);
});

test('smooth normals on a flat surface all point the same way', () => {
  const m = parseMesh(binaryStl(QUAD), 'flat.stl');
  for (let i = 0; i < m.normals.length; i += 3) {
    assert.ok(Math.abs(m.normals[i]) < 1e-6);
    assert.ok(Math.abs(m.normals[i + 1]) < 1e-6);
    assert.ok(Math.abs(m.normals[i + 2] - 1) < 1e-6);
  }
});

test('smooth normals average across a fold', () => {
  // Two triangles meeting at 90°: the shared edge points halfway between.
  const positions = new Float32Array([0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 1]);
  const n = smoothNormals(positions, new Uint32Array([0, 1, 2, 3, 4, 5]));
  const len = Math.hypot(n[0], n[1], n[2]);
  assert.ok(Math.abs(len - 1) < 1e-6);
  assert.ok(n[2] > 0.5); // bent up out of the plane
});

test('bounds of an empty mesh are zeros, not infinities', () => {
  assert.deepEqual(boundsOf(new Float32Array(0)), [0, 0, 0, 0, 0, 0]);
});

test('the format is taken from the bytes before the name', () => {
  assert.equal(detectFormat(binaryPly(), 'wrongly_named.stl'), 'ply');
  assert.equal(detectFormat(text('v 0 0 0\nf 1 1 1\n').buffer, 'design.obj'), 'obj');
});
