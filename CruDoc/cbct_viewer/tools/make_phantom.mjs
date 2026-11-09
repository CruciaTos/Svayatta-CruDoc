// Synthetic jaw-like phantom pack (no patient data): writes meta.json + full.i16,
// preview.i16, lod1.i16 (if >256), and poster PNGs in pack format v3.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import zlib from 'node:zlib';

const viewerRoot = fileURLToPath(new URL('..', import.meta.url));

let outArg = null;
let N = 96;
for (let i = 2; i < process.argv.length; i++) {
  if (process.argv[i] === '--size' && process.argv[i + 1]) {
    N = parseInt(process.argv[++i], 10);
  } else if (!outArg) {
    outArg = process.argv[i];
  }
}

const out = outArg
  ? (path.isAbsolute(outArg) ? outArg : path.resolve(viewerRoot, outArg))
  : path.join(viewerRoot, 'dev', N === 400 ? 'phantom_big' : 'phantom');

fs.mkdirSync(out, { recursive: true });

const SP = N === 400 ? 0.1 : 0.4;
const data = new Int16Array(N * N * N);
let seed = 7;
const rnd = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296; };
const gauss = () => Math.sqrt(-2 * Math.log(rnd() + 1e-9)) * Math.cos(2 * Math.PI * rnd());
const c = N / 2;
const fovR2 = Math.pow(0.48 * N * SP, 2);

// Fast noise table
const NOISE_SIZE = 1024;
const noiseTable = new Int16Array(NOISE_SIZE);
for (let i = 0; i < NOISE_SIZE; i++) noiseTable[i] = Math.round(gauss() * 40);
let noiseIdx = 0;

for (let z = 0; z < N; z++) {
  const Z = (z - c) * SP;
  const inZMandible = Z > -8 && Z < 1;
  const inZCanal = Math.abs(Z + 4) < 1;
  const inZTeeth = Z > 0 && Z < 7;
  for (let y = 0; y < N; y++) {
    const Y = (y - c) * SP;
    const Y2 = Y * Y;
    const Yplus2 = Y + 2;
    const rMandible2 = Yplus2 * Yplus2;
    const inYMandible = Y < 4;
    const Yplus10 = Y + 10.5;
    const Yplus10_2 = Yplus10 * Yplus10;
    const rowOffset = (z * N + y) * N;

    for (let x = 0; x < N; x++) {
      const X = (x - c) * SP;
      if (X * X + Y2 > fovR2) {
        data[rowOffset + x] = -1000;
        continue;
      }

      let v = -600; // air
      if (Math.abs(X) < 15 && Math.abs(Y) < 12 && Math.abs(Z) < 12) {
        v = 180; // soft tissue box
      }

      // Mandible
      const r = Math.sqrt(X * X + rMandible2);
      const inU = inYMandible && r > 6.5 && r < 11.5 && inZMandible;
      if (inU) {
        v = (r < 7.7 || r > 10.3 || Z < -6.8 || Z > -0.2) ? 2600 : (900 + 600 * rnd());
        if (inZCanal && Math.abs(r - 9) < 1) {
          v = 250;
        }
      }

      // Teeth
      if (inZTeeth) {
        for (const tx of [-3.5, 3.5]) {
          const dx = X - tx;
          const d2 = dx * dx + Yplus10_2;
          if (d2 < 4.84) {
            const d = Math.sqrt(d2);
            v = d < 0.8 ? 300 : (Z > 5 ? 3000 : 2300);
          }
        }
      }

      // Metal crown + orientation bead
      const dCrown2 = Math.pow(X - 3.5, 2) + Yplus10_2 + Math.pow(Z - 7.5, 2);
      if (dCrown2 < 1.44) v = 6000;
      const dBead2 = Math.pow(X - 8, 2) + Math.pow(Y + 8, 2) + Math.pow(Z - 8, 2);
      if (dBead2 < 0.5625) v = 3200;

      v += noiseTable[noiseIdx++ & (NOISE_SIZE - 1)];
      data[rowOffset + x] = Math.max(-32768, Math.min(32767, Math.round(v)));
    }
  }
}

fs.writeFileSync(path.join(out, 'full.i16'), Buffer.from(data.buffer));

const at = (x, y, z) => data[(z * N + y) * N + x];

function boxDownsample(factor) {
  const M = Math.ceil(N / factor);
  const outArr = new Int16Array(M * M * M);
  for (let z = 0; z < M; z++) {
    for (let y = 0; y < M; y++) {
      for (let x = 0; x < M; x++) {
        let s = 0, count = 0;
        for (let k = 0; k < factor; k++) {
          for (let j = 0; j < factor; j++) {
            for (let i = 0; i < factor; i++) {
              const xx = x * factor + i, yy = y * factor + j, zz = z * factor + k;
              if (xx < N && yy < N && zz < N) {
                s += at(xx, yy, zz);
                count++;
              }
            }
          }
        }
        outArr[(z * M + y) * M + x] = Math.round(s / count);
      }
    }
  }
  return { data: outArr, dims: [M, M, M], factor };
}

// ---- preview (LOD 0: <= 128 per axis) ----
const fp = Math.max(2, Math.ceil(N / 128));
const prev = boxDownsample(fp);
fs.writeFileSync(path.join(out, 'preview.i16'), Buffer.from(prev.data.buffer));

// ---- lod1 (<= 256 per axis, only when N > 256) ----
let lod1Res = null;
if (N > 256) {
  const f1 = Math.max(2, Math.ceil(N / 256));
  lod1Res = boxDownsample(f1);
  fs.writeFileSync(path.join(out, 'lod1.i16'), Buffer.from(lod1Res.data.buffer));
}

// ---- posters (8-bit grey PNG, Bone window) ----
const crcTable = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
const crc32 = (b) => {
  let c = 0xffffffff;
  for (const x of b) c = crcTable[(c ^ x) & 255] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};
const chunk = (type, body) => {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(body.length);
  const td = Buffer.concat([Buffer.from(type), body]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
};
function png(w, h, px) {
  const raw = Buffer.alloc((w + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w + 1)] = 0;
    for (let x = 0; x < w; x++) raw[y * (w + 1) + 1 + x] = px[y * w + x];
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;
  ihdr[9] = 0;
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

const lo = -600, hi = 3000;
const grey = (v) => Math.max(0, Math.min(255, Math.round(((v - lo) / (hi - lo)) * 255)));
const midIdx = N >> 1;
const posterSize = Math.min(N, 256);
const posterStep = N / posterSize;
const axial = new Uint8Array(posterSize * posterSize);
const coronal = new Uint8Array(posterSize * posterSize);
const sagittal = new Uint8Array(posterSize * posterSize);

for (let r = 0; r < posterSize; r++) {
  const y = Math.floor(r * posterStep);
  const zInv = Math.floor((posterSize - 1 - r) * posterStep);
  for (let col = 0; col < posterSize; col++) {
    const x = Math.floor(col * posterStep);
    axial[r * posterSize + col] = grey(at(x, y, midIdx));
    coronal[r * posterSize + col] = grey(at(x, midIdx, zInv));
    sagittal[r * posterSize + col] = grey(at(midIdx, x, zInv));
  }
}

fs.writeFileSync(path.join(out, 'poster_axial.png'), png(posterSize, posterSize, axial));
fs.writeFileSync(path.join(out, 'poster_coronal.png'), png(posterSize, posterSize, coronal));
fs.writeFileSync(path.join(out, 'poster_sagittal.png'), png(posterSize, posterSize, sagittal));
fs.writeFileSync(path.join(out, 'poster_3d.png'), png(posterSize, posterSize, axial));

// ---- meta.json (format v3) ----
const sh0 = ((fp - 1) / 2) * SP;
const lod0Entry = {
  file: 'preview.i16',
  factor: fp,
  dims: prev.dims,
  spacing: [SP * fp, SP * fp, SP * fp],
  origin: [-c * SP + sh0, -c * SP + sh0, -c * SP + sh0],
};

const lodList = [lod0Entry];

if (lod1Res) {
  const sh1 = ((lod1Res.factor - 1) / 2) * SP;
  lodList.push({
    file: 'lod1.i16',
    factor: lod1Res.factor,
    dims: lod1Res.dims,
    spacing: [SP * lod1Res.factor, SP * lod1Res.factor, SP * lod1Res.factor],
    origin: [-c * SP + sh1, -c * SP + sh1, -c * SP + sh1],
  });
}

lodList.push({
  file: 'full.i16',
  factor: 1,
  dims: [N, N, N],
  spacing: [SP, SP, SP],
  origin: [-c * SP, -c * SP, -c * SP],
});

const meta = {
  packVersion: 3,
  seriesKey: N === 400 ? 'phantom_big' : 'phantom',
  source: { fingerprint: N === 400 ? 'phantom_big' : 'phantom' },
  geometry: {
    dims: [N, N, N],
    spacing: [SP, SP, SP],
    origin: [-c * SP, -c * SP, -c * SP],
    direction: [1, 0, 0, 0, 1, 0, 0, 0, 1],
  },
  volumes: {
    full: {
      file: 'full.i16',
      dims: [N, N, N],
      spacing: [SP, SP, SP],
      origin: [-c * SP, -c * SP, -c * SP],
    },
    mid: lod1Res ? {
      file: 'lod1.i16',
      dims: lod1Res.dims,
      spacing: [SP * lod1Res.factor, SP * lod1Res.factor, SP * lod1Res.factor],
      origin: [-c * SP + ((lod1Res.factor - 1) / 2) * SP, -c * SP + ((lod1Res.factor - 1) / 2) * SP, -c * SP + ((lod1Res.factor - 1) / 2) * SP],
    } : null,
    preview: lod0Entry,
    lods: lodList,
  },
  posters: {
    axial: 'poster_axial.png',
    coronal: 'poster_coronal.png',
    sagittal: 'poster_sagittal.png',
    threeD: 'poster_3d.png',
  },
  values: { min: -1000, max: 6011, padValue: -1000, valueOffset: 0 },
  landmarks: { air: -600, soft: 180, bone: 1100, teeth: 3000, metal: 5900 },
  presets: {
    bone: { low: -600, high: 3000 },
    teeth: { low: 1100, high: 5900 },
    soft: { low: -600, high: 1100 },
    fineBone: { low: 180, high: 3000 },
    full: { low: -1000, high: 6011 },
  },
  device: { manufacturer: 'TEST', model: 'PHANTOM' },
};

fs.writeFileSync(path.join(out, 'meta.json'), JSON.stringify(meta, null, 2));
console.log(`phantom v3 ready (${N}^3) in`, out + ':', fs.readdirSync(out).join(', '));
