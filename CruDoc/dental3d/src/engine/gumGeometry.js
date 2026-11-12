import * as THREE from 'three';

// Pure geometry: builds the gum and the bone of one arch from tooth data.
// Cross-section plane per station: n = outward (facial +), c = coronal height
// (c = 0 at the neck, + towards the crown). Upper arch: crown is -Y, lower: +Y.
const STEP = 0.5;          // mm between stations
const EXT = 8;             // mm extension past the last molars
const FN = 14;             // wall rows (margin -> base)
const KT = 7;              // interior points across the top
const BN = 3;              // interior points across the bottom
const R = (FN + 1) * 2 + KT + BN;   // ring size
const M_GAP = -1.5;
const END_TAPER = 3.0;     // mm over which the distal ends round off
const ATT_M = 5;           // wall row (counted from the margin) where the palate leaves the lingual wall
const FADE_MM = 3.2;       // far edge dissolves over this many mm
const sm = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
const lerp = (a, b, t) => a + (b - a) * t;
const bump = (x, c, wd) => { const t = (x - c) / wd; return t * t >= 1 ? 0 : (1 - t * t) * (1 - t * t); };
const rgb = (hex) => { const c = new THREE.Color(hex); return [c.r, c.g, c.b]; };
const C_MARGIN = rgb('#F5B1AE'), C_ATT = rgb('#EE9C9C'), C_MUC = rgb('#E2808B'), C_DEEP = rgb('#C65C6D');
const C_PALE = rgb('#F6BBB8'), C_GROOVE = rgb('#E69A9D'), C_RED = rgb('#D02F3E'), C_PAL = rgb('#EDA3A5');
const BONE_TOP = rgb('#F1EBDA'), BONE_LOW = rgb('#D6C9A8');
// wall row -> fraction of the depth (dense at the margin and at the rounded base)
const SROW = new Float32Array(FN + 1);
for (let m = 0; m <= FN; m++) SROW[m] = 0.5 - 0.5 * Math.cos(Math.PI * m / FN);

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
    rl: new Float32Array(N + 1), hn: new Float32Array(N + 1), tau: new Float32Array(N + 1),
  };
  // lean of each tooth's root: horizontal part of the long axis (along the outward normal) per mm of depth
  const lean = teeth.map((t, j) => {
    const k = key[j];
    const h = (t.ax * S.nx[k] + t.az * S.nz[k]) / Math.max(0.4, Math.abs(t.ay));
    return Math.max(-0.8, Math.min(0.8, h));
  });
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
    S.rl[k] = lerp(T[a].rl, T[b].rl, s);
    S.hn[k] = lerp(lean[a], lean[b], s);
    const ue = Math.min(1, Math.min(k, N - k) * stepLen / END_TAPER);
    S.tau[k] = Math.sqrt(Math.max(0, 1 - (1 - ue) * (1 - ue)));
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
// Each station writes R ring points: facial wall (base -> margin), the rolled
// top, lingual wall (margin -> base), then the base. out.n = offset along the
// outward normal, out.c = height above the neck, out.col = RGBA.
const _o = { n: new Float32Array(R), c: new Float32Array(R), col: new Float32Array(R * 4) };

function fillGum(S, k, out) {
  const w = S.w[k], cm = S.cm[k], miss = S.miss[k], pap = S.pap[k], infl = S.infl[k];
  const E = Math.min(1, S.emin[k] * 2), rl = S.rl[k], hn = S.hn[k];
  const tau = 0.04 + 0.96 * S.tau[k];
  const cbot = -(rl + 3.8), span = cm - cbot, halfRoot = 0.5 * rl;
  // outward half-width of the tissue at height c (root + soft tissue + eminence, rounded in at the base)
  const wall = (c, facial) => {
    const d = cm - c;
    const u = c < 0 ? -c : 0;
    const rw = w * (1.15 - 0.55 * Math.min(1, u / rl));
    const base = 1.5 + 1.2 * sm(0, halfRoot, u);
    let th = lerp(0.45 + 0.35 * bump(d, 0.6, 0.55) - 0.22 * bump(d, 1.7, 0.5), base, sm(1.2, 3.4, d));
    th = lerp(th, base + 0.3, miss);
    th -= 0.35 * pap * (1 - sm(0, 3, d));
    const env = sm(1.0, 3.0, d) * (1 - sm(halfRoot, rl, u));
    const em = (facial ? 0.7 : 0.2) * E * env;
    const x = (u - (rl - 0.2)) / 4;
    const rho = x > 0 ? Math.sqrt(Math.max(0, 1 - x * x)) : 1;
    return Math.max(0.03, (rw + th + em) * rho * tau);
  };
  const paint = (idx, c, top, facial) => {
    const d = Math.max(0, cm - c);
    const u = c < 0 ? -c : 0;
    let r = C_ATT[0], g = C_ATT[1], b = C_ATT[2], t;
    t = (1 - sm(0, 1.3, d)) * 0.6; r += (C_MARGIN[0] - r) * t; g += (C_MARGIN[1] - g) * t; b += (C_MARGIN[2] - b) * t;
    t = sm(4.5, 10, d); r += (C_MUC[0] - r) * t; g += (C_MUC[1] - g) * t; b += (C_MUC[2] - b) * t;
    t = sm(10, 17, d) * 0.55; r += (C_DEEP[0] - r) * t; g += (C_DEEP[1] - g) * t; b += (C_DEEP[2] - b) * t;
    if (facial) { t = E * sm(1, 3, d) * (1 - sm(halfRoot, rl, u)) * 0.35; r += (C_PALE[0] - r) * t; g += (C_PALE[1] - g) * t; b += (C_PALE[2] - b) * t; }
    t = bump(d, 1.7, 0.45) * 0.35; r += (C_GROOVE[0] - r) * t; g += (C_GROOVE[1] - g) * t; b += (C_GROOVE[2] - b) * t;
    t = top ? infl * 0.3 : Math.min(1, infl * 0.75) * (1 - sm(2, 8, d)) * 0.9 + Math.min(1, infl) * 0.15;
    r += (C_RED[0] - r) * t; g += (C_RED[1] - g) * t; b += (C_RED[2] - b) * t;
    out.col[idx * 4] = r; out.col[idx * 4 + 1] = g; out.col[idx * 4 + 2] = b;
    out.col[idx * 4 + 3] = sm(0, FADE_MM, c - cbot);
  };
  let i = 0;
  for (let j = 0; j <= FN; j++, i++) {
    const c = cm - SROW[FN - j] * span;
    out.n[i] = hn * c + wall(c, true); out.c[i] = c; paint(i, c, false, true);
  }
  const hF = wall(cm, true), hL = wall(cm, false), cc = hn * cm;
  for (let q = 1; q <= KT; q++, i++) {
    const th = Math.PI * q / (KT + 1);
    out.n[i] = cc + 0.5 * (hF - hL) + 0.5 * (hF + hL) * Math.cos(th);
    out.c[i] = cm + Math.sin(th) * (-0.8 + miss * 2.1);
    paint(i, cm, true, false);
  }
  for (let m = 0; m <= FN; m++, i++) {
    const c = cm - SROW[m] * span;
    out.n[i] = hn * c - wall(c, false); out.c[i] = c; paint(i, c, false, false);
  }
  const nbF = out.n[0], nbL = out.n[i - 1];
  for (let q = 1; q <= BN; q++, i++) {
    out.c[i] = cbot; out.n[i] = lerp(nbL, nbF, q / (BN + 1)); paint(i, cbot, false, false);
  }
}

function fillBone(S, k, out) {
  const w = S.w[k], rl = S.rl[k], hn = S.hn[k], tau = 0.04 + 0.96 * S.tau[k];
  const crest = Math.min(-2 - S.bl[k], S.cm[k] - 1.3);
  const bbot = -(rl + 3.4), span = crest - bbot;
  const wall = (c) => {
    const u = c < 0 ? -c : 0;
    const rw = w * (1.15 - 0.55 * Math.min(1, u / rl));
    const x = (u - (rl - 0.1)) / 3.5;
    const rho = x > 0 ? Math.sqrt(Math.max(0, 1 - x * x)) : 1;
    return Math.max(0.03, (rw + 0.85) * rho * tau);
  };
  const paint = (idx, c) => {
    const t = sm(bbot, crest, c);
    out.col[idx * 4] = lerp(BONE_LOW[0], BONE_TOP[0], t); out.col[idx * 4 + 1] = lerp(BONE_LOW[1], BONE_TOP[1], t);
    out.col[idx * 4 + 2] = lerp(BONE_LOW[2], BONE_TOP[2], t); out.col[idx * 4 + 3] = sm(0, FADE_MM, c - bbot);
  };
  let i = 0;
  for (let j = 0; j <= FN; j++, i++) { const c = crest - SROW[FN - j] * span; out.n[i] = hn * c + wall(c); out.c[i] = c; paint(i, c); }
  const hc = wall(crest);
  for (let q = 1; q <= KT; q++, i++) {
    const th = Math.PI * q / (KT + 1);
    out.n[i] = hn * crest + hc * Math.cos(th); out.c[i] = crest + 0.9 * Math.sin(th); paint(i, crest);
  }
  for (let m = 0; m <= FN; m++, i++) { const c = crest - SROW[m] * span; out.n[i] = hn * c - wall(c); out.c[i] = c; paint(i, c); }
  const nbF = out.n[0], nbL = out.n[i - 1];
  for (let q = 1; q <= BN; q++, i++) { out.c[i] = bbot; out.n[i] = lerp(nbL, nbF, q / (BN + 1)); paint(i, bbot); }
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

const PAL_M = 16;

export function buildGeometry(S, kind) {
  const { N, upper } = S;
  const dir = upper ? -1 : 1;                 // +c direction in world Y
  const nRing = (N + 1) * R;
  const attachIdx = (FN + 1) + KT + ATT_M;     // lingual wall point the palate grows from
  const keep = upper ? attachIdx : R;          // upper arch: ring pairs from here on are not built (the palate closes it)
  const rows = Math.floor(N / 2);
  const nPal = upper ? (rows + 1) * (PAL_M - 1) : 0;
  const total = nRing + nPal + 2 * (R + 1);
  const pos = new Float32Array(total * 3);
  const colr = new Float32Array(total * 4);
  const out = _o;
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
    colr.set(out.col, k * R * 4);
  }

  const idx = new Uint32Array(N * keep * 6 + rows * PAL_M * 6 + 2 * R * 3);
  let ni = 0;
  for (let k = 0; k < N; k++) {
    for (let i = 0; i < keep; i++) {
      const a = k * R + i, b = k * R + (i + 1) % R, c = (k + 1) * R + i, d = (k + 1) * R + (i + 1) % R;
      idx[ni++] = a; idx[ni++] = c; idx[ni++] = b; idx[ni++] = b; idx[ni++] = c; idx[ni++] = d;
    }
  }
  const mid = Math.floor(N / 2);
  orient(idx, (mid * keep + Math.floor(FN / 2)) * 6, 0, ni, pos, [S.nx[mid], 0, S.nz[mid]]);

  // palate vault between the left and right lingual walls (upper arch), fading out at the back
  if (upper) {
    const vi = (r, m) => {
      if (m === 0) return r * R + attachIdx;
      if (m === PAL_M) return (N - r) * R + attachIdx;
      return nRing + r * (PAL_M - 1) + (m - 1);
    };
    const fadeRows = 3.4 / STEP;
    for (let r = 0; r <= rows; r++) {
      const A = (r * R + attachIdx) * 3, B = ((N - r) * R + attachIdx) * 3;
      const span = Math.hypot(pos[B] - pos[A], pos[B + 2] - pos[A + 2]);
      const rise = Math.min(13, 0.36 * span);
      const al = sm(0, fadeRows, r);
      for (let m = 1; m < PAL_M; m++) {
        const v = m / PAL_M, o = vi(r, m) * 3;
        const h = Math.pow(4 * v * (1 - v), 0.85);
        pos[o] = lerp(pos[A], pos[B], v);
        pos[o + 1] = lerp(pos[A + 1], pos[B + 1], v) - dir * rise * h;
        pos[o + 2] = lerp(pos[A + 2], pos[B + 2], v);
        const t = kind === 'gum' ? C_PAL : BONE_TOP;
        const o4 = vi(r, m) * 4;
        colr[o4] = t[0]; colr[o4 + 1] = t[1]; colr[o4 + 2] = t[2]; colr[o4 + 3] = al;
      }
      for (const e of [r * R + attachIdx, (N - r) * R + attachIdx]) colr[e * 4 + 3] = Math.min(colr[e * 4 + 3], al);
    }
    const from = ni;
    for (let r = 0; r < rows; r++) {
      for (let m = 0; m < PAL_M; m++) {
        const v00 = vi(r, m), v01 = vi(r, m + 1), v10 = vi(r + 1, m), v11 = vi(r + 1, m + 1);
        idx[ni++] = v00; idx[ni++] = v10; idx[ni++] = v01; idx[ni++] = v01; idx[ni++] = v10; idx[ni++] = v11;
      }
    }
    if (ni > from) orient(idx, from, from, ni, pos, [0, dir, 0]);
  }

  // end caps (the ends are already rounded off by the taper, so the caps are tiny)
  for (let cap = 0; cap < 2; cap++) {
    const k = cap === 0 ? 0 : N;
    const base = nRing + nPal + cap * (R + 1);
    let cx = 0, cy = 0, cz = 0;
    for (let i = 0; i < R; i++) {
      const s = (k * R + i) * 3, d = (base + i) * 3;
      pos[d] = pos[s]; pos[d + 1] = pos[s + 1]; pos[d + 2] = pos[s + 2];
      colr.copyWithin((base + i) * 4, (k * R + i) * 4, (k * R + i) * 4 + 4);
      cx += pos[s]; cy += pos[s + 1]; cz += pos[s + 2];
    }
    const cc = (base + R) * 3;
    pos[cc] = cx / R; pos[cc + 1] = cy / R; pos[cc + 2] = cz / R;
    colr.copyWithin((base + R) * 4, base * 4, base * 4 + 4);
    const from = ni;
    for (let i = 0; i < keep; i++) { idx[ni++] = base + R; idx[ni++] = base + i; idx[ni++] = base + (i + 1) % R; }
    const sign = cap === 0 ? -1 : 1;
    if (ni > from) orient(idx, from, from, ni, pos, [sign * S.tx[k], 0, sign * S.tz[k]]);
  }

  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  g.setAttribute('color', new THREE.BufferAttribute(colr, 4));
  g.setIndex(new THREE.BufferAttribute(idx.subarray(0, ni), 1));
  g.computeVertexNormals();
  g.computeBoundingSphere();
  g.computeBoundingBox();
  return g;
}
