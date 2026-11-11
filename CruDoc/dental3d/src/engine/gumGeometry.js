import * as THREE from 'three';

// Pure geometry: builds the gum and the bone of one arch from tooth data.
// Cross-section plane per station: n = outward (facial +), c = coronal height
// (c = 0 at the neck, + towards the crown). Upper arch: crown is -Y, lower: +Y.
const STEP = 0.6;          // mm between stations
const EXT = 5;             // mm extension past the last molars
const FN = 8;              // wall rows (base -> margin)
const KT = 7;              // interior points across the top
const BN = 3;              // interior points across the bottom
const R = (FN + 1) * 2 + KT + BN;   // ring size
const C_BASE = -15;
const M_GAP = -1.5;
const sm = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
const lerp = (a, b, t) => a + (b - a) * t;

const col = (hex) => new THREE.Color(hex);
const GUM_PALE = col('#F3A9AB'), GUM_MID = col('#E58E93'), GUM_DEEP = col('#C05867'), GUM_RED = col('#D02F3E');
const BONE_TOP = col('#EFE8D3'), BONE_LOW = col('#CDBE9B');
const _c = new THREE.Color();

// ---- shared sampling of the arch ---------------------------------------
export function sampleArch(teeth, upper) {
  const pts = teeth.map((t) => new THREE.Vector3(t.C.x, 0, t.C.z));
  const d0 = pts[0].clone().sub(pts[1]).setY(0).normalize();
  const d1 = pts[pts.length - 1].clone().sub(pts[pts.length - 2]).setY(0).normalize();
  const ctrl = [pts[0].clone().addScaledVector(d0, EXT), ...pts, pts[pts.length - 1].clone().addScaledVector(d1, EXT)];
  const curve = new THREE.CatmullRomCurve3(ctrl, false, 'centripetal');
  curve.arcLengthDivisions = 500;
  const L = curve.getLength();
  const N = Math.max(8, Math.round(L / STEP));
  const stepLen = L / N;
  const cen = new THREE.Vector3();
  pts.forEach((p) => cen.add(p));
  cen.divideScalar(pts.length);

  const px = new Float32Array(N + 1), pz = new Float32Array(N + 1);
  const nx = new Float32Array(N + 1), nz = new Float32Array(N + 1);
  const tx = new Float32Array(N + 1), tz = new Float32Array(N + 1);
  let dotSum = 0;
  for (let k = 0; k <= N; k++) {
    const u = k / N;
    const P = curve.getPointAt(u); const T = curve.getTangentAt(u);
    const l = Math.hypot(T.x, T.z) || 1;
    px[k] = P.x; pz[k] = P.z; tx[k] = T.x / l; tz[k] = T.z / l;
    nx[k] = tz[k]; nz[k] = -tx[k];
    dotSum += nx[k] * (P.x - cen.x) + nz[k] * (P.z - cen.z);
  }
  if (dotSum < 0) for (let k = 0; k <= N; k++) { nx[k] = -nx[k]; nz[k] = -nz[k]; }

  // key station of each tooth (closest station, kept monotonic)
  const key = [];
  let from = 0;
  for (const t of teeth) {
    let best = from, bd = Infinity;
    for (let k = from; k <= N; k++) {
      const d = (px[k] - t.C.x) ** 2 + (pz[k] - t.C.z) ** 2;
      if (d < bd) { bd = d; best = k; }
    }
    key.push(best); from = best;
  }

  const S = {
    N, upper, stepLen, px, pz, nx, nz, tx, tz, key, teeth,
    w: new Float32Array(N + 1), yc: new Float32Array(N + 1), miss: new Float32Array(N + 1),
    infl: new Float32Array(N + 1), bl: new Float32Array(N + 1), cm: new Float32Array(N + 1),
    pap: new Float32Array(N + 1), emin: new Float32Array(N + 1),
  };
  const T = teeth;
  const m = T.map((t) => (t.present ? 1.0 - t.rec : M_GAP));
  const ant = T.map((t) => (t.cls === 'incisor' || t.cls === 'canine' ? 1 : 0));
  const eAt = (j, k) => {
    const t = T[j]; if (!t.present) return 0;
    const hw = t.md / 2; const d = Math.abs(k - key[j]) * stepLen;
    return d < hw ? 0.5 * Math.cos((Math.PI / 2) * (d / hw)) ** 2 : 0;
  };
  for (let k = 0; k <= N; k++) {
    let i = -1;
    while (i + 1 < T.length && key[i + 1] <= k) i++;
    const a = Math.max(0, i), b = Math.min(T.length - 1, i + 1);
    let al = 0;
    if (i >= 0 && i + 1 < T.length && key[b] > key[a]) al = (k - key[a]) / (key[b] - key[a]);
    const s = sm(0, 1, al);
    S.w[k] = lerp(T[a].cervBl, T[b].cervBl, s) / 2;
    S.yc[k] = lerp(T[a].C.y, T[b].C.y, s);
    S.miss[k] = lerp(T[a].present ? 0 : 1, T[b].present ? 0 : 1, sm(0.3, 0.7, al));
    S.infl[k] = lerp(T[a].infl, T[b].infl, s);
    S.bl[k] = lerp(T[a].bl, T[b].bl, s);
    let cm = lerp(m[a], m[b], sm(0.25, 0.75, al));
    if (a !== b && T[a].present && T[b].present) {
      const ac = T[a].md / (T[a].md + T[b].md);
      const d = al < ac ? (ac - al) / ac : (al - ac) / (1 - ac);
      const f = Math.pow(Math.max(0, 1 - d / 0.85), 1.6);
      const peak = lerp(2.3, 3.0, (ant[a] + ant[b]) / 2) - 0.5 * (T[a].rec + T[b].rec) / 2;
      cm = lerp(cm, peak, f);
      S.pap[k] = f;
    }
    S.cm[k] = cm;
    S.emin[k] = a === b ? eAt(a, k) : Math.max(eAt(a, k), eAt(b, k));
  }
  return S;
}

// ---- profiles -----------------------------------------------------------
const gumA = (d) => 1.1 * sm(0, 3, d) + 1.0 * sm(3, 16, d)
  + 0.45 * Math.pow(Math.sin(Math.PI * Math.min(1, Math.max(0, d / 16))), 1.5);

function boneN(c, w, crest) { // bone half-width below the crest
  const t = Math.min(1, Math.max(0, (c + 21) / (crest + 21)));
  return lerp(w + 1.8, w + 1.0, t);
}

function fillGum(S, k, out) {
  const w = S.w[k], cm = S.cm[k], miss = S.miss[k], pap = S.pap[k], emin = S.emin[k], infl = S.infl[k];
  const cLing = S.upper ? -9 : -11;
  const crest = -2 - S.bl[k];
  const nm = w + 0.3 - 0.5 * pap;
  const wall = (c, eminence) => {
    const d = cm - c;
    let n = nm + gumA(d) + eminence * Math.pow(Math.sin(Math.PI * Math.min(1, Math.max(0, d / 15))), 1.2);
    const wt = 1 - sm(crest, crest + 1.5, c);       // stay outside the bone
    n += wt * Math.max(0, boneN(c, w, crest) + 0.4 - n);
    return n;
  };
  const paint = (idx, c, top) => {
    const d = Math.max(0, cm - c);
    _c.copy(GUM_PALE).lerp(GUM_MID, sm(0, 3, d)).lerp(GUM_DEEP, sm(3, 14, d) * 0.8);
    if (!top) _c.lerp(GUM_RED, Math.min(1, infl * 0.75) * (1 - sm(2, 8, d)) * 0.9 + Math.min(1, infl) * 0.15);
    else _c.lerp(GUM_RED, infl * 0.3);
    out.col[idx * 3] = _c.r; out.col[idx * 3 + 1] = _c.g; out.col[idx * 3 + 2] = _c.b;
  };
  let i = 0;
  for (let j = 0; j <= FN; j++, i++) { const c = lerp(C_BASE, cm, j / FN); out.n[i] = wall(c, emin); out.c[i] = c; paint(i, c, false); }
  for (let q = 1; q <= KT; q++, i++) {
    const th = Math.PI * q / (KT + 1);
    out.n[i] = nm * Math.cos(th);
    out.c[i] = cm + Math.sin(th) * (-0.8 + miss * 2.1);
    paint(i, cm, true);
  }
  for (let j = FN; j >= 0; j--, i++) { const c = lerp(cLing, cm, j / FN); out.n[i] = -wall(c, 0); out.c[i] = c; paint(i, c, false); }
  const nbF = out.n[0], nbL = out.n[i - 1];
  for (let q = 1; q <= BN; q++, i++) {
    const s = q / (BN + 1);
    out.c[i] = lerp(cLing, C_BASE, s); out.n[i] = lerp(nbL, nbF, s); paint(i, C_BASE + 4, false);
  }
}

function fillBone(S, k, out) {
  const w = S.w[k]; const crest = -2 - S.bl[k];
  const paint = (idx, c) => {
    _c.copy(BONE_LOW).lerp(BONE_TOP, sm(-21, crest, c));
    out.col[idx * 3] = _c.r; out.col[idx * 3 + 1] = _c.g; out.col[idx * 3 + 2] = _c.b;
  };
  let i = 0;
  for (let j = 0; j <= FN; j++, i++) { const c = lerp(-21, crest, j / FN); out.n[i] = boneN(c, w, crest); out.c[i] = c; paint(i, c); }
  for (let q = 1; q <= KT; q++, i++) {
    const th = Math.PI * q / (KT + 1);
    out.n[i] = (w + 1.0) * Math.cos(th); out.c[i] = crest + 0.9 * Math.sin(th); paint(i, crest);
  }
  for (let j = FN; j >= 0; j--, i++) { const c = lerp(-21, crest, j / FN); out.n[i] = -boneN(c, w, crest); out.c[i] = c; paint(i, c); }
  const nbF = out.n[0], nbL = out.n[i - 1];
  for (let q = 1; q <= BN; q++, i++) {
    out.c[i] = -21; out.n[i] = lerp(nbL, nbF, q / (BN + 1)); paint(i, -21);
  }
}

// ---- mesh assembly --------------------------------------------------------
// Flip triangles idx[from..to) if the triangle starting at `probe` faces away from `want`.
function orient(idx, probe, from, to, pos, want) {
  const a = idx[probe] * 3, b = idx[probe + 1] * 3, c = idx[probe + 2] * 3;
  const ux = pos[b] - pos[a], uy = pos[b + 1] - pos[a + 1], uz = pos[b + 2] - pos[a + 2];
  const vx = pos[c] - pos[a], vy = pos[c + 1] - pos[a + 1], vz = pos[c + 2] - pos[a + 2];
  const nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
  if (nx * want[0] + ny * want[1] + nz * want[2] < 0) {
    for (let i = from; i < to; i += 3) { const t = idx[i + 1]; idx[i + 1] = idx[i + 2]; idx[i + 2] = t; }
  }
}

const PAL_M = 14;
const PAL_PINK = col('#E9989D');

export function buildGeometry(S, kind) {
  const { N, upper } = S;
  const dir = upper ? -1 : 1;                 // +c direction in world Y
  const nRing = (N + 1) * R;
  const attachJ = kind === 'gum' ? 4 : 5;
  const attachIdx = (FN + 1) + KT + (FN - attachJ);
  const rows = Math.floor(N / 2);
  const nPal = upper ? (rows + 1) * (PAL_M - 1) : 0;
  const total = nRing + nPal + 2 * (R + 1);
  const pos = new Float32Array(total * 3);
  const colr = new Float32Array(total * 3);
  const out = { n: new Float32Array(R), c: new Float32Array(R), col: new Float32Array(R * 3) };
  const fill = kind === 'gum' ? fillGum : fillBone;
  for (let k = 0; k <= N; k++) {
    fill(S, k, out);
    const yc = S.yc[k];
    for (let i = 0; i < R; i++) {
      const o = (k * R + i) * 3;
      pos[o] = S.px[k] + out.n[i] * S.nx[k];
      pos[o + 1] = yc + dir * out.c[i];
      pos[o + 2] = S.pz[k] + out.n[i] * S.nz[k];
    }
    colr.set(out.col, k * R * 3);
  }

  // tube between stations
  const idx = [];
  for (let k = 0; k < N; k++) {
    for (let i = 0; i < R; i++) {
      const a = k * R + i, b = k * R + (i + 1) % R, c = (k + 1) * R + i, d = (k + 1) * R + (i + 1) % R;
      idx.push(a, c, b, b, c, d);
    }
  }
  const mid = Math.floor(N / 2);
  orient(idx, (mid * R + Math.floor(FN / 2)) * 6, 0, idx.length, pos, [S.nx[mid], 0, S.nz[mid]]);

  // palate vault between the left and right lingual walls (upper arch)
  if (upper) {
    const vi = (r, m) => {
      if (m === 0) return r * R + attachIdx;
      if (m === PAL_M) return (N - r) * R + attachIdx;
      return nRing + r * (PAL_M - 1) + (m - 1);
    };
    for (let r = 0; r <= rows; r++) {
      const A = (r * R + attachIdx) * 3, B = ((N - r) * R + attachIdx) * 3;
      const span = Math.hypot(pos[B] - pos[A], pos[B + 2] - pos[A + 2]);
      const rise = Math.min(kind === 'gum' ? 13 : 13.5, 0.36 * span);
      for (let m = 1; m < PAL_M; m++) {
        const v = m / PAL_M, o = vi(r, m) * 3;
        const h = Math.pow(4 * v * (1 - v), 0.9);
        pos[o] = lerp(pos[A], pos[B], v);
        pos[o + 1] = lerp(pos[A + 1], pos[B + 1], v) - dir * rise * h;
        pos[o + 2] = lerp(pos[A + 2], pos[B + 2], v);
        const t = kind === 'gum' ? PAL_PINK : BONE_TOP;
        colr[o] = t.r; colr[o + 1] = t.g; colr[o + 2] = t.b;
      }
    }
    const from = idx.length;
    for (let r = 0; r < rows; r++) {
      for (let m = 0; m < PAL_M; m++) {
        const v00 = vi(r, m), v01 = vi(r, m + 1), v10 = vi(r + 1, m), v11 = vi(r + 1, m + 1);
        idx.push(v00, v10, v01, v01, v10, v11);
      }
    }
    if (idx.length > from) orient(idx, from, from, idx.length, pos, [0, dir, 0]);
  }

  // end caps
  for (let cap = 0; cap < 2; cap++) {
    const k = cap === 0 ? 0 : N;
    const base = nRing + nPal + cap * (R + 1);
    let cx = 0, cy = 0, cz = 0;
    for (let i = 0; i < R; i++) {
      const s = (k * R + i) * 3, d = (base + i) * 3;
      pos[d] = pos[s]; pos[d + 1] = pos[s + 1]; pos[d + 2] = pos[s + 2];
      colr[d] = colr[s]; colr[d + 1] = colr[s + 1]; colr[d + 2] = colr[s + 2];
      cx += pos[s]; cy += pos[s + 1]; cz += pos[s + 2];
    }
    const cc = (base + R) * 3;
    pos[cc] = cx / R; pos[cc + 1] = cy / R; pos[cc + 2] = cz / R;
    colr[cc] = colr[(base) * 3]; colr[cc + 1] = colr[(base) * 3 + 1]; colr[cc + 2] = colr[(base) * 3 + 2];
    const from = idx.length;
    for (let i = 0; i < R; i++) idx.push(base + R, base + i, base + (i + 1) % R);
    const sign = cap === 0 ? -1 : 1;
    orient(idx, from, from, idx.length, pos, [sign * S.tx[k], 0, sign * S.tz[k]]);
  }

  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  g.setAttribute('color', new THREE.BufferAttribute(colr, 3));
  g.setIndex(new THREE.BufferAttribute(new Uint32Array(idx), 1));
  g.computeVertexNormals();
  g.computeBoundingSphere();
  g.computeBoundingBox();
  return g;
}
