// Panoramic view of the dental arch, shown in the Coronal slot (a button in the slot's
// top-right corner switches it; every other control stays where it is).
//
// After the full scan has arrived the arch is found (arch.js), the picture built
// (panoramic.js) in slices of a few milliseconds, so the viewer never freezes. The
// slot then shows the panoramic picture and, beside it, the cross-section at the
// marker. Click or drag on the picture to move the marker (and the crosshair to that
// spot); the arrow keys step it about 1 mm along the arch.
import { eventTarget } from '@cornerstonejs/core';
import { Enums as ToolsEnums } from '@cornerstonejs/tools';
import { core, axes, dot, add, mul, sub, norm, cross, COLORS } from './core.js';
import { state, subscribe, set } from './state.js';
import { h, svgEl } from './chrome.js';
import { icon } from './icons.js';
import { scanKind } from './presets3d.js';
import { findArchAsync } from './arch.js';
import { archPath, panoramicAsync, crossSection } from './panoramic.js';
import { smoothPath, implantAxis, clearance, safety, planeDistance, NERVE_RADIUS } from './plan.js';
import { NERVE, SAFETY, setImplant } from './planning.js';

const SLABS = [5, 10, 20, 30]; // how deep into the jaw the panoramic picture can look (mm)
let thickness = 10; // chosen slab for this session (the picture may still show the previous one while it rebuilds)
let slabJob = 0;
const HIT_PX = 6; // grab tolerance around an implant, screen pixels (mouse)
const HIT_TOUCH_PX = 14;
const CROSS_WIDTH_MM = 30;
const STEP_KEY_MM = 1;
const MAX_PIXELS = 600000; // panoramic picture size cap (a coarser step on very tall scans)
const SLICE_MS = 10; // work per slice

let frame = null;
let btn = null;
let slabBtn = null;
let layer = null;
let on = false;
let jobId = 0;
// status: idle | busy | none | ready
const job = { status: 'idle', note: '', voxels: null, arch: null, pano: null, step: 0.25, thickness: 10, rightOnLeft: true };
const sel = { col: 0, rowMm: 0 }; // marker: arch column and height (mm along the scan's z axis)
let cs = null; // the cross-section on screen
let queued = false;

const els = {};
const isDental = () => !!core.meta && scanKind(core.meta) === 'dental';

// ───────────────────────── Building the picture ─────────────────────────

async function build() {
  if (!core.voxels || !core.geo || !core.meta || job.voxels === core.voxels) return;
  const voxels = core.voxels;
  const geo = core.geo;
  const id = ++jobId;
  const stale = () => id !== jobId || core.voxels !== voxels;
  slabJob++;
  Object.assign(job, { status: 'busy', note: '', voxels, arch: null, pano: null });
  cs = null;
  refresh();
  try {
    const teeth = core.meta.landmarks && core.meta.landmarks.teeth;
    if (teeth == null) return done(id, 'none', 'This scan has no tooth level, so no dental arch can be found.');
    const found = await findArchAsync(voxels, geo, teeth - core.valueOffset, SLICE_MS);
    if (stale()) return;
    if (!found) return done(id, 'none', 'No dental arch was found in this scan.');
    let length = 0;
    for (let i = 1; i < found.points.length; i++) length += Math.hypot(...sub(found.points[i], found.points[i - 1]));
    const extentZ = geo.dims[2] * geo.spacing[2];
    const step = Math.max(0.25, Math.sqrt((length * extentZ) / MAX_PIXELS));
    const arch = archPath(found.points, step, geo);
    if (arch.points.length < 2) return done(id, 'none', 'No dental arch was found in this scan.');
    const slab = thickness;
    const pano = await panoramicAsync(voxels, geo, arch, { stepMm: step, thicknessMm: slab }, SLICE_MS, stale);
    if (stale() || !pano) return;
    job.arch = arch;
    job.pano = pano;
    job.step = step;
    job.thickness = slab;
    // Patient's right is the low-x end (DICOM LPS: +x is Left); a panoramic shows right on the left.
    job.rightOnLeft = arch.points[0][0] <= arch.points[arch.points.length - 1][0];
    // Start in the middle of the arch, at the height the arch was found at.
    const mid = Math.floor(arch.points.length / 2);
    const z = axes(geo).z;
    sel.col = mid;
    sel.rowMm = dot(arch.points[mid], z);
    job.home = { col: sel.col, rowMm: sel.rowMm };
    done(id, 'ready', '');
  } catch (err) {
    console.warn('CBCT viewer: panoramic', err);
    if (id === jobId) done(id, 'none', 'The panoramic picture could not be built.');
  }
}

function done(id, status, note) {
  if (id !== jobId) return;
  job.status = status;
  job.note = note;
  if (status === 'ready') showCross();
  refresh();
  if (status === 'ready' && job.thickness !== thickness) rebuildSlab(); // the slab was changed while the first picture was building
}

// A new slab thickness: only the picture is rebuilt (same arch, same step); the marker, the
// cross-section and the old picture stay on screen until the new one is ready.
async function rebuildSlab() {
  if (job.status !== 'ready') return;
  const { voxels, arch, step } = job;
  const id = jobId;
  const sid = ++slabJob;
  const slab = thickness;
  const stale = () => id !== jobId || sid !== slabJob || core.voxels !== voxels;
  refresh();
  try {
    const pano = await panoramicAsync(voxels, core.geo, arch, { stepMm: step, thicknessMm: slab }, SLICE_MS, stale);
    if (stale() || !pano) return;
    job.pano = pano;
    job.thickness = slab;
  } catch (err) {
    console.warn('CBCT viewer: panoramic slab', err);
  }
  if (sid === slabJob) {
    refresh();
    schedule();
  }
}

function setSlab(mm) {
  if (!SLABS.includes(mm) || mm === thickness) return;
  thickness = mm;
  if (job.status === 'ready') rebuildSlab();
  else refresh();
}

function reset() {
  jobId++;
  slabJob++;
  Object.assign(job, { status: 'idle', note: '', voxels: null, arch: null, pano: null });
  cs = null;
  on = false;
  refresh();
}

// ───────────────────────── Marker and cross-section ─────────────────────────

const pointAt = (col) => job.arch.points[Math.max(0, Math.min(job.arch.points.length - 1, col))];

// Rebuild the cross-section at the marker (cheap: about 20 000 samples).
function showCross() {
  if (job.status !== 'ready') return;
  cs = crossSection(job.voxels, core.geo, job.arch, sel.col * job.step, { stepMm: job.step, widthMm: CROSS_WIDTH_MM });
}

// Move the marker. `rowMm` (height) stays as it was when only the column changes.
function select(col, rowMm, { moveCrosshair = true } = {}) {
  if (job.status !== 'ready') return;
  sel.col = Math.max(0, Math.min(job.arch.points.length - 1, Math.round(col)));
  if (rowMm != null) sel.rowMm = rowMm;
  showCross();
  if (moveCrosshair && core.crosshair) {
    ownMove = performance.now();
    const p = pointAt(sel.col);
    const z = axes(core.geo).z;
    core.crosshair.setToolCenter(add(p, mul(z, sel.rowMm - dot(p, z))));
  }
  schedule();
}

// The crosshair's own camera events arrive a little later (and may carry its old position): follow() ignores them.
let ownMove = -1e9;
const OWN_MS = 500;

const stepBy = (mm) => select(sel.col + mm / job.step, null);

// Where a world point sits relative to the arch: the nearest arch column (ignoring height),
// how far to the side of the arch (+ along the outward normal) and along it past the ends.
function locate(q) {
  const { points, normals } = job.arch;
  const n = points.length;
  const z = axes(core.geo).z;
  let col = 0;
  let best = Infinity;
  for (let i = 0; i < n; i++) {
    const d = sub(q, points[i]);
    const dz = dot(d, z);
    const dd = dot(d, d) - dz * dz;
    if (dd < best) {
      best = dd;
      col = i;
    }
  }
  const d = sub(q, points[col]);
  const tangent = norm(sub(points[Math.min(n - 1, col + 1)], points[Math.max(0, col - 1)]));
  const along = dot(d, tangent);
  return {
    col,
    lateral: dot(d, normals[col]),
    // Past the end of the arch: the point has no place on the picture.
    off: (col === 0 && along < -3) || (col === n - 1 && along > 3),
    zMm: dot(q, z),
  };
}

// The crosshair moved (in another view): the marker goes to the nearest spot on the arch,
// unless the crosshair is further from the arch than the cross-section is wide.
function follow() {
  if (!on || job.status !== 'ready' || !core.crosshair || !core.crosshair.toolCenter) return;
  if (performance.now() - ownMove < OWN_MS) return;
  const at = locate(core.crosshair.toolCenter);
  if (at.off || Math.abs(at.lateral) > CROSS_WIDTH_MM / 2) return;
  if (at.col === sel.col && Math.abs(at.zMm - sel.rowMm) < 0.05) return;
  select(at.col, at.zMm, { moveCrosshair: false });
}

// Reset of this slot: back to the middle of the arch (the crosshair goes there too).
const home = () => job.status === 'ready' && select(job.home.col, job.home.rowMm);

// ───────────────────────── Drawing ─────────────────────────

function schedule() {
  if (queued) return;
  queued = true;
  requestAnimationFrame(() => {
    queued = false;
    draw();
  });
}

// Real value -> grey with the same window / level as the slices.
function paint(canvas, data, w, hh) {
  if (canvas.width !== w || canvas.height !== hh) {
    canvas.width = w;
    canvas.height = hh;
  }
  const { low, high, invert } = state.contrast;
  const lo = low - core.valueOffset;
  const k = 255 / (high - low || 1);
  const img = new ImageData(w, hh);
  const px = img.data;
  for (let i = 0, j = 0; i < data.length; i++, j += 4) {
    let g = (data[i] - lo) * k;
    g = g < 0 ? 0 : g > 255 ? 255 : g;
    if (invert) g = 255 - g;
    px[j] = px[j + 1] = px[j + 2] = g;
    px[j + 3] = 255;
  }
  canvas.getContext('2d').putImageData(img, 0, 0);
}

function draw() {
  if (!on) return;
  if (job.status !== 'ready') return;
  const p = job.pano;
  if (!els.panoPainted || els.panoPainted !== p || els.contrastKey !== contrastKey()) {
    paint(els.panoCanvas, p.data, p.width, p.height);
    els.panoPainted = p;
  }
  if (cs && (els.csPainted !== cs || els.contrastKey !== contrastKey())) {
    paint(els.csCanvas, cs.data, cs.width, cs.height);
    els.csPainted = cs;
  }
  els.contrastKey = contrastKey();
  els.panoSvg.setAttribute('viewBox', `0 0 ${p.width} ${p.height}`);
  const row = (job.pano.zTopMm - sel.rowMm) / job.step;
  const x = sel.col + 0.5;
  const y = Math.max(0, Math.min(p.height, row + 0.5));
  setLine(els.panoV, x, 0, x, p.height);
  setLine(els.panoH, 0, y, p.width, y);
  if (cs) {
    els.csSvg.setAttribute('viewBox', `0 0 ${cs.width} ${cs.height}`);
    const cx = (cs.width - 1) / 2 + 0.5;
    setLine(els.csV, cx, 0, cx, cs.height);
    setLine(els.csH, 0, y, cs.width, y);
  }
  drawPlan();
  const total = job.arch.length;
  els.info.textContent = `Along the arch ${(sel.col * job.step).toFixed(1)} of ${total.toFixed(0)} mm · arrow keys step ${STEP_KEY_MM} mm`;
}

// World point -> panoramic picture pixel (null past the ends of the arch).
function toPano(q) {
  const at = locate(q);
  return at.off ? null : { x: at.col + 0.5, y: (job.pano.zTopMm - at.zMm) / job.step + 0.5, lateral: at.lateral };
}

// The implant plan on both pictures (same colours as the slice views). On the panoramic the
// nerve canal is projected onto the arch: solid inside the slab the picture looks through,
// faint outside. On the cross-section only where the canal and the implants cut the plane.
function drawPlan() {
  const gp = els.panoPlan;
  const gc = els.csPlan;
  gp.replaceChildren();
  gc.replaceChildren();
  if (!isDental()) return;
  const plan = state.plan;
  const stepMm = job.step;
  const halfSlab = job.thickness / 2;
  const nerves = [plan.nerves.right, plan.nerves.left];
  const width = Math.max(1.5, (2 * NERVE_RADIUS) / stepMm);
  const polyline = (pts, opacity) => svgEl('polyline', { points: pts.map((p) => `${p[0].toFixed(2)},${p[1].toFixed(2)}`).join(' '), fill: 'none', stroke: NERVE, 'stroke-width': width, 'stroke-opacity': opacity, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' });

  const onPano = toPano;
  for (const pts of nerves) {
    if (pts.length < 2) continue;
    // Consecutive pieces with the same look (solid / faint) become one line.
    let run = [];
    let solid = null;
    const flush = () => {
      if (run.length > 1) gp.append(polyline(run, solid ? 0.9 : 0.3));
      run = [];
    };
    for (const q of smoothPath(pts, 0.5)) {
      const at = onPano(q);
      if (!at) {
        flush();
        solid = null;
        continue;
      }
      const s = Math.abs(at.lateral) <= halfSlab;
      if (s !== solid) {
        const last = run[run.length - 1];
        flush();
        solid = s;
        if (last) run.push(last); // pieces share their joint
      }
      run.push([at.x, at.y]);
    }
    flush();
  }

  const normal = cs ? norm(cross(cs.u, cs.v)) : null;
  const planeAt = pointAt(sel.col);
  const onCs = (q) => {
    const r = sub(q, cs.origin);
    return [dot(r, cs.u) / stepMm + 0.5, dot(r, cs.v) / stepMm + 0.5];
  };
  if (cs) {
    for (const pts of nerves) {
      if (pts.length < 2) continue;
      const path = smoothPath(pts, 0.5);
      for (let i = 1; i < path.length; i++) {
        const da = planeDistance(path[i - 1], planeAt, normal);
        const db = planeDistance(path[i], planeAt, normal);
        if (da * db > 0) continue;
        const t = da === db ? 0 : da / (da - db);
        const [x, y] = onCs(add(path[i - 1], mul(sub(path[i], path[i - 1]), t)));
        gc.append(svgEl('circle', { cx: x, cy: y, r: Math.max(1.2, NERVE_RADIUS / stepMm), fill: NERVE, 'fill-opacity': 0.9 }));
      }
    }
  }

  plan.implants.forEach((im, i) => {
    const { top, apex } = implantAxis(im);
    const r = im.diameter / 2;
    const col = SAFETY[safety(clearance(im, nerves))];
    const style = (cut) => ({ fill: col, 'fill-opacity': cut ? 0.3 : 0.08, stroke: col, 'stroke-opacity': cut ? 1 : 0.45, 'stroke-width': i === plan.selected ? 2.25 : 1.25, 'vector-effect': 'non-scaling-stroke' });
    const body = (g, a, b, rp, cut) => {
      const dx = b[0] - a[0];
      const dy = b[1] - a[1];
      const len = Math.hypot(dx, dy);
      if (len < 0.5) g.append(svgEl('circle', { cx: a[0], cy: a[1], r: rp, ...style(cut) }));
      else {
        const ux = (-dy / len) * rp;
        const uy = (dx / len) * rp;
        const pts = [[a[0] + ux, a[1] + uy], [b[0] + ux, b[1] + uy], [b[0] - ux, b[1] - uy], [a[0] - ux, a[1] - uy]];
        g.append(svgEl('polygon', { points: pts.map((p) => `${p[0].toFixed(2)},${p[1].toFixed(2)}`).join(' '), ...style(cut) }));
      }
      const t = svgEl('text', { x: a[0], y: a[1] - rp - 1.5, 'text-anchor': 'middle', 'font-size': 7, 'font-weight': 600, fill: col, 'font-family': 'Geist, system-ui, sans-serif' });
      t.textContent = String(i + 1);
      g.append(t);
    };
    const a = onPano(top);
    const b = onPano(apex);
    if (a && b) body(gp, [a.x, a.y], [b.x, b.y], r / stepMm, Math.min(Math.abs(a.lateral), Math.abs(b.lateral)) <= halfSlab + r || a.lateral > 0 !== b.lateral > 0);
    if (cs) {
      const dt = planeDistance(top, planeAt, normal);
      const da = planeDistance(apex, planeAt, normal);
      body(gc, onCs(top), onCs(apex), r / stepMm, dt > 0 !== da > 0 || Math.min(Math.abs(dt), Math.abs(da)) <= r);
    }
  });
}

const contrastKey = () => `${state.contrast.low}|${state.contrast.high}|${state.contrast.invert}`;
function setLine(el, x1, y1, x2, y2) {
  el.setAttribute('x1', x1);
  el.setAttribute('y1', y1);
  el.setAttribute('x2', x2);
  el.setAttribute('y2', y2);
}

// What the slot shows: the picture, a message, or nothing.
function refresh() {
  if (!layer) return;
  const show = isDental();
  btn.style.display = show ? '' : 'none';
  btn.classList.toggle('on', on && show);
  slabBtn.style.display = on && show && job.status === 'ready' ? '' : 'none';
  slabBtn.textContent = `${thickness} mm`;
  slabBtn.classList.toggle('busy', job.status === 'ready' && job.thickness !== thickness);
  slabBtn.title = `Slab thickness: the panoramic looks ${thickness} mm into the jaw (click to change)`;
  frame.root.classList.toggle('pano-on', on && show);
  els.name.textContent = on && show ? 'Panoramic' : 'Coronal';
  const ready = job.status === 'ready';
  els.cells.style.display = ready ? '' : 'none';
  els.info.style.display = ready ? '' : 'none';
  els.letterL.style.display = els.letterR.style.display = ready ? '' : 'none';
  els.msg.style.display = ready ? 'none' : '';
  els.msg.textContent = job.status === 'none' ? job.note : job.status === 'idle' ? 'The panoramic picture is built once the whole scan has loaded.' : 'Building the panoramic picture…';
  if (ready) {
    els.letterL.textContent = job.rightOnLeft ? 'R' : 'L';
    els.letterR.textContent = job.rightOnLeft ? 'L' : 'R';
    // The two pictures share the slot in proportion to their widths in millimetres.
    els.panoCell.style.flexGrow = String(job.arch.length);
    els.csCell.style.flexGrow = String(CROSS_WIDTH_MM);
    els.csCell.style.display = '';
    schedule();
  }
}

// ───────────────────────── Wiring ─────────────────────────

function toggle() {
  on = !on;
  if (on && job.status === 'idle' && state.phase === 'full') build();
  refresh();
  if (on) follow(); // start where the crosshair is
}

// Pointer position on the panoramic picture: picture pixels and the screen size of one pixel.
function toPicture(e) {
  const r = els.panoCell.getBoundingClientRect();
  const { width: w, height: hh } = job.pano;
  const s = Math.min(r.width / w, r.height / hh);
  return { x: (e.clientX - r.left - (r.width - w * s) / 2) / s, y: (e.clientY - r.top - (r.height - hh * s) / 2) / s, s };
}

// Click or drag on the panoramic picture: move the marker to that spot.
function pick(e) {
  if (job.status !== 'ready') return;
  const { x, y } = toPicture(e);
  const { width: w, height: hh } = job.pano;
  select(Math.max(0, Math.min(w - 1, x - 0.5)), job.pano.zTopMm - Math.max(0, Math.min(hh - 1, y - 0.5)) * job.step);
}

// ───────────────────────── Dragging an implant ─────────────────────────

// The implant under a picture point (the last one wins, as it is drawn on top), or -1.
function implantAt(x, y, tol) {
  const list = state.plan.implants;
  for (let i = list.length - 1; i >= 0; i--) {
    const { top, apex } = implantAxis(list[i]);
    const a = toPano(top);
    const b = toPano(apex);
    if (!a || !b) continue;
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const len2 = dx * dx + dy * dy;
    const t = len2 ? Math.max(0, Math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / len2)) : 0;
    if (Math.hypot(x - (a.x + t * dx), y - (a.y + t * dy)) <= list[i].diameter / 2 / job.step + tol) return i;
  }
  return -1;
}

// A point on the arch at a (fractional) column, and its outward normal.
function archAt(c) {
  const { points, normals } = job.arch;
  const f = Math.max(0, Math.min(points.length - 1, c));
  const i = Math.min(points.length - 2, Math.floor(f));
  const t = f - i;
  const lerp = (u, v) => add(mul(u, 1 - t), mul(v, t));
  return { p: lerp(points[i], points[i + 1]), n: norm(lerp(normals[i], normals[i + 1])) };
}

// Where the implant's top goes when the pointer has moved dx columns and dy picture rows: along
// the arch (its side offset kept, following the normal) and straight up or down. The apex moves
// with it, so axis and length stay as they were.
function draggedTop(start, dx, dy) {
  const z = axes(core.geo).z;
  const c1 = Math.max(0, Math.min(job.arch.points.length - 1, start.col + dx));
  const a0 = archAt(start.col);
  const a1 = archAt(c1);
  let delta = add(sub(a1.p, a0.p), mul(sub(a1.n, a0.n), start.lateral));
  delta = sub(delta, mul(z, dot(delta, z))); // the horizontal part only
  delta = add(delta, mul(z, -dy * job.step));
  return add(start.top, delta);
}

let drag = null; // { i, x, y, col, lateral, top, pending, raf }

function startDrag(e, i) {
  const { x, y } = toPicture(e);
  const im = state.plan.implants[i];
  const at = locate(im.top);
  drag = { i, x, y, col: at.col, lateral: at.lateral, top: [...im.top], pending: null, raf: 0 };
  set({ plan: { selected: i } });
  els.panoCell.classList.add('grabbing');
}

function applyDrag() {
  if (!drag) return;
  drag.raf = 0;
  const e = drag.pending;
  if (!e) return;
  drag.pending = null;
  const { x, y } = toPicture(e);
  const dy = Math.max(0, Math.min(job.pano.height - 1, y)) - drag.y;
  setImplant(drag.i, { top: draggedTop(drag, x - drag.x, dy) });
}

function moveDrag(e) {
  drag.pending = { clientX: e.clientX, clientY: e.clientY };
  if (!drag.raf) drag.raf = requestAnimationFrame(applyDrag);
}

function endDrag(cancel) {
  if (!drag) return;
  if (drag.raf) cancelAnimationFrame(drag.raf);
  if (cancel) setImplant(drag.i, { top: drag.top });
  else if (drag.pending) applyDrag();
  drag = null;
  els.panoCell.classList.remove('grabbing');
}

export function initPano(ui) {
  frame = ui.frames.coronal;
  els.name = frame.root.querySelector('.pill .name');
  els.panoCanvas = h('canvas');
  els.panoV = svgEl('line', { stroke: COLORS.coronal, 'stroke-width': 1.5, 'vector-effect': 'non-scaling-stroke' });
  els.panoH = svgEl('line', { stroke: COLORS.coronal, 'stroke-width': 1, 'stroke-opacity': 0.7, 'stroke-dasharray': '4 3', 'vector-effect': 'non-scaling-stroke' });
  els.panoSvg = svgEl('svg', {});
  els.panoPlan = svgEl('g', { class: 'plan' });
  els.panoSvg.append(els.panoPlan, els.panoH, els.panoV);
  els.panoCell = h('div', { class: 'pcell pick' }, els.panoCanvas, els.panoSvg);
  els.csCanvas = h('canvas');
  els.csV = svgEl('line', { stroke: COLORS.coronal, 'stroke-width': 1.5, 'vector-effect': 'non-scaling-stroke' });
  els.csH = svgEl('line', { stroke: COLORS.coronal, 'stroke-width': 1, 'stroke-opacity': 0.7, 'stroke-dasharray': '4 3', 'vector-effect': 'non-scaling-stroke' });
  els.csSvg = svgEl('svg', {});
  els.csPlan = svgEl('g', { class: 'plan' });
  els.csSvg.append(els.csPlan, els.csH, els.csV);
  els.csCell = h('div', { class: 'pcell' }, els.csCanvas, els.csSvg);
  els.cells = h('div', { class: 'pano-cells' }, els.panoCell, els.csCell);
  els.msg = h('div', { class: 'pano-msg' });
  els.info = h('div', { class: 'vpinfo' });
  els.letterL = h('span', { class: 'lt left' });
  els.letterR = h('span', { class: 'lt right' });
  layer = h('div', { class: 'pano' }, els.cells, els.msg, els.info, els.letterL, els.letterR);
  frame.root.append(layer);

  btn = h('button', { class: 'vpbtn', type: 'button', title: 'Panoramic view of the dental arch', 'aria-label': 'Panoramic view', onclick: toggle }, icon('panoramic', 14));
  frame.root.querySelector('.vpbtns').prepend(btn);
  slabBtn = h('button', { class: 'vpbtn txt', type: 'button', 'aria-label': 'Slab thickness', onclick: () => setSlab(SLABS[(SLABS.indexOf(thickness) + 1) % SLABS.length]) });
  frame.root.querySelector('.vpbtns').prepend(slabBtn);

  let dragging = false;
  const tolFor = (e, pt) => (e.pointerType === 'touch' ? HIT_TOUCH_PX : HIT_PX) / pt.s;
  els.panoCell.addEventListener('pointerdown', (e) => {
    if (e.button !== 0 || job.status !== 'ready') return;
    const pt = toPicture(e);
    const i = implantAt(pt.x, pt.y, tolFor(e, pt));
    els.panoCell.setPointerCapture(e.pointerId);
    if (i >= 0) {
      startDrag(e, i);
      return;
    }
    dragging = true;
    pick(e);
  });
  els.panoCell.addEventListener('pointermove', (e) => {
    if (drag) moveDrag(e);
    else if (dragging) pick(e);
    else if (job.status === 'ready') {
      const pt = toPicture(e);
      els.panoCell.classList.toggle('grab', implantAt(pt.x, pt.y, tolFor(e, pt)) >= 0);
    }
  });
  const stop = () => {
    dragging = false;
    endDrag(false);
  };
  els.panoCell.addEventListener('pointerup', stop);
  els.panoCell.addEventListener('pointercancel', stop);
  // Escape during a drag puts the implant back where it was.
  window.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || !drag) return;
    e.preventDefault();
    e.stopPropagation();
    endDrag(true);
  }, true);

  // Reset on this slot goes back to the middle of the arch (the slice view under it has nothing to show).
  frame.root.querySelector('.vpbtns').addEventListener('click', (e) => {
    if (!on || !isDental() || !e.target.closest('button[aria-label="Reset this view"]')) return;
    e.stopPropagation();
    home();
  }, true);

  // The crosshair moves in another view (or by a click in the slices): the marker follows.
  eventTarget.addEventListener(ToolsEnums.Events.CROSSHAIR_TOOL_CENTER_CHANGED, follow);

  // Arrow keys step along the arch while the panoramic picture is on screen (and hovered).
  window.addEventListener('keydown', (e) => {
    if (!on || job.status !== 'ready' || e.ctrlKey || e.metaKey || e.altKey || e.target instanceof HTMLInputElement) return;
    if ((state.hovered || state.active) !== 'coronal') return;
    const dir = { ArrowRight: 1, ArrowUp: 1, ArrowLeft: -1, ArrowDown: -1 }[e.key];
    if (!dir) return;
    e.preventDefault();
    e.stopPropagation();
    stepBy(dir * STEP_KEY_MM);
  }, true);

  subscribe((s, changed) => {
    if (changed.has('phase')) {
      if (s.phase === 'empty') reset();
      else if (s.phase === 'full') setTimeout(build, 600); // after the other automatic scans
    }
    if (changed.has('meta') || changed.has('phase')) refresh();
    if ((changed.has('contrast') || changed.has('plan')) && on) schedule();
  });
  refresh();
}

// For the test scripts (with ?debug).
export const panoState = () => ({
  status: job.status,
  note: job.note,
  on,
  length: job.arch ? job.arch.length : 0,
  columns: job.pano ? job.pano.width : 0,
  rows: job.pano ? job.pano.height : 0,
  step: job.step,
  thickness: job.thickness,
  wantedThickness: thickness,
  col: sel.col,
  home: job.home ? job.home.col : null,
  sMm: sel.col * job.step,
  rowMm: sel.rowMm,
  cross: cs ? [cs.width, cs.height] : null,
  point: job.arch ? pointAt(sel.col) : null,
  normal: job.arch ? job.arch.normals[sel.col] : null,
});
export const panoSetSlab = setSlab;
export const panoSelect = (col, rowMm) => select(col, rowMm);
export const panoLocate = (q) => (job.status === 'ready' ? locate(q) : null);
