// Implant planning for dental scans: trace the nerve canal (click points along
// it in the slice views) and place implants at the crosshair. The distance from
// each implant to the canal is shown live: green >= 2 mm, amber 1-2 mm, red < 1 mm.
// Drawn in the slice views (SVG) and in the 3D view (meshes); saved in state.json.
import { Enums } from '@cornerstonejs/core';
import vtkActor from '@kitware/vtk.js/Rendering/Core/Actor.js';
import vtkMapper from '@kitware/vtk.js/Rendering/Core/Mapper.js';
import vtkPolyData from '@kitware/vtk.js/Common/DataModel/PolyData.js';
import vtkDataArray from '@kitware/vtk.js/Common/Core/DataArray.js';
import { core, vp, MPR, centre } from './core.js';
import { state, set, subscribe } from './state.js';
import { h, svgEl, section, row, slider, segmented, chipRow } from './chrome.js';
import { scanKind } from './presets3d.js';
import { is3dHidden } from './view3d.js';
import { smoothPath, implantAxis, clearance, safety, tubeMesh, cylinderMesh, planeDistance, NERVE_RADIUS } from './plan.js';
import { traceCanal, siteMeasure, suggestSize } from './assist.js';
import { planSummary } from './summary.js';
import { foundBoxes } from './findings.js';

export const NERVE = '#F2C14E';
export const SAFETY = { safe: '#4FB47E', close: '#E8A33D', danger: '#E8674F', unknown: '#9AA4B2' };
const SAFETY_TEXT = { safe: 'safe', close: 'close: keep 2 mm', danger: 'too close', unknown: '' };
const SIDES = [['right', 'Right'], ['left', 'Left']];

export const emptyPlan = () => ({ nerves: { right: [], left: [] }, side: 'right', implants: [], selected: -1, follow: true });

let ui = null;
const groups = {};
let actors3d = [];
let drawQueued = false;

const plan = () => state.plan;
const nerveList = () => [plan().nerves.right, plan().nerves.left];
const isDental = () => !!core.meta && scanKind(core.meta) === 'dental';
const crosshairPoint = () => [...((core.crosshair && core.crosshair.toolCenter) || centre())];
const fmt = (p) => `${p[0].toFixed(1)},${p[1].toFixed(1)}`;
// The scan's density levels in stored units (what the voxels hold).
const levels = () => {
  const L = core.meta.landmarks;
  const o = core.valueOffset;
  return { air: L.air - o, soft: L.soft - o, bone: L.bone - o, teeth: L.teeth - o };
};
const undoStack = { right: [], left: [] }; // lengths before each click, so Undo removes a whole followed piece
// Notes from the last Suggest size, shown only while that implant is unchanged.
let suggested = { key: '', notes: [] };
const suggestNotesFor = (im) => (im && JSON.stringify(im) === suggested.key ? suggested.notes : []);

// ───────────────────────── Changing the plan ─────────────────────────

function setNerve(side, pts) {
  set({ plan: { nerves: { ...plan().nerves, [side]: pts } } });
}

// A click while tracing: with Auto-follow the canal is followed from the last point.
function addNervePoint(p) {
  const side = plan().side;
  const pts = plan().nerves[side];
  let mids = [];
  if (plan().follow && pts.length && core.voxels) {
    try {
      mids = traceCanal(core.voxels, core.geo, pts[pts.length - 1], p, levels());
    } catch (err) {
      console.warn('CBCT viewer: canal follow', err);
    }
  }
  undoStack[side].push(pts.length);
  setNerve(side, [...pts, ...mids, p]);
}

function undoNerve() {
  const side = plan().side;
  const pts = plan().nerves[side];
  const back = undoStack[side].length ? undoStack[side].pop() : pts.length - 1;
  setNerve(side, pts.slice(0, Math.max(0, Math.min(back, pts.length - 1))));
}

function clearNerve() {
  undoStack[plan().side] = [];
  setNerve(plan().side, []);
}

function setImplant(i, patch) {
  const list = plan().implants.map((im, k) => (k === i ? { ...im, ...patch } : im));
  set({ plan: { implants: list } });
}

function addImplant() {
  const top = crosshairPoint();
  const im = { top, diameter: 4, length: 10, jaw: top[2] < centre()[2] ? 'lower' : 'upper', tiltAP: 0, tiltLR: 0 };
  set({ plan: { implants: [...plan().implants, im], selected: plan().implants.length } });
}

function deleteImplant(i) {
  const list = plan().implants.filter((_, k) => k !== i);
  set({ plan: { implants: list, selected: Math.min(i, list.length - 1) } });
}

// ───────────────────────── Slice views ─────────────────────────

function drawView(id) {
  const frame = ui.frames[id];
  if (!groups[id]) {
    groups[id] = svgEl('g', { class: 'plan' });
    frame.svg.append(groups[id]);
  }
  const g = groups[id];
  g.replaceChildren();
  const v = vp(id);
  if (!v || !core.geo || !isDental()) return;
  const cam = v.getCamera();
  const n = cam.viewPlaneNormal;
  const o = cam.focalPoint;
  const pxPerMm = (core.hosts[id].clientHeight || 1) / (2 * cam.parallelScale);
  const onSlice = Math.min(...core.geo.spacing) * 0.75;
  const px = (p) => v.worldToCanvas(p);
  const width = Math.max(2, 2 * NERVE_RADIUS * pxPerMm);
  const line = (pts, opacity) => svgEl('polyline', { points: pts.map(fmt).join(' '), fill: 'none', stroke: NERVE, 'stroke-width': width, 'stroke-opacity': opacity, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' });

  for (const [side] of SIDES) {
    const pts = plan().nerves[side];
    if (!pts.length) continue;
    const path = smoothPath(pts, 0.5);
    const screen = path.map(px);
    if (screen.length > 1) g.append(line(screen, 0.25));
    // Where the canal passes through this slice: drawn solid.
    let run = [];
    const flush = () => {
      if (run.length > 1) g.append(line(run, 0.9));
      else if (run.length === 1) g.append(svgEl('circle', { cx: run[0][0], cy: run[0][1], r: width / 2, fill: NERVE, 'fill-opacity': 0.9 }));
      run = [];
    };
    path.forEach((p, i) => (Math.abs(planeDistance(p, o, n)) <= NERVE_RADIUS ? run.push(screen[i]) : flush()));
    flush();
    // The clicked points that lie on this slice.
    for (const p of pts) {
      if (Math.abs(planeDistance(p, o, n)) > onSlice) continue;
      const q = px(p);
      g.append(svgEl('circle', { cx: q[0], cy: q[1], r: 3.5, fill: NERVE, stroke: '#0B0E14', 'stroke-width': 1.5 }));
    }
  }

  const nerves = nerveList();
  plan().implants.forEach((im, i) => {
    const { top, apex } = implantAxis(im);
    const r = im.diameter / 2;
    const dt = planeDistance(top, o, n);
    const da = planeDistance(apex, o, n);
    const cut = dt > 0 !== da > 0 || Math.min(Math.abs(dt), Math.abs(da)) <= r;
    const col = SAFETY[safety(clearance(im, nerves))];
    const a = px(top);
    const b = px(apex);
    const rp = r * pxPerMm;
    const dx = b[0] - a[0];
    const dy = b[1] - a[1];
    const L = Math.hypot(dx, dy);
    const style = { fill: col, 'fill-opacity': cut ? 0.3 : 0.08, stroke: col, 'stroke-opacity': cut ? 1 : 0.45, 'stroke-width': i === plan().selected ? 2.25 : 1.25 };
    if (L < 2) {
      g.append(svgEl('circle', { cx: a[0], cy: a[1], r: rp, ...style }));
    } else {
      const ux = (-dy / L) * rp;
      const uy = (dx / L) * rp;
      const corners = [[a[0] + ux, a[1] + uy], [b[0] + ux, b[1] + uy], [b[0] - ux, b[1] - uy], [a[0] - ux, a[1] - uy]];
      g.append(svgEl('polygon', { points: corners.map(fmt).join(' '), ...style }));
    }
    const label = svgEl('text', { x: a[0], y: a[1] - Math.max(rp, 6) - 4, 'text-anchor': 'middle', 'font-size': 11, 'font-weight': 600, fill: col, 'font-family': 'Geist, system-ui, sans-serif' });
    label.textContent = String(i + 1);
    g.append(label);
  });
}

// ───────────────────────── 3D view ─────────────────────────

function meshActor(m, color, opacity = 1) {
  const pd = vtkPolyData.newInstance();
  pd.getPoints().setData(m.points, 3);
  pd.getPolys().setData(m.polys);
  pd.getPointData().setNormals(vtkDataArray.newInstance({ numberOfComponents: 3, values: m.normals, name: 'Normals' }));
  const mapper = vtkMapper.newInstance({ scalarVisibility: false });
  mapper.setInputData(pd);
  const actor = vtkActor.newInstance();
  actor.setMapper(mapper);
  const p = actor.getProperty();
  const hex = (c) => [1, 3, 5].map((k) => parseInt(c.slice(k, k + 2), 16) / 255);
  p.setColor(...hex(color));
  p.setOpacity(opacity);
  p.setAmbient(0.25);
  p.setDiffuse(0.8);
  p.setSpecular(0.35);
  p.setSpecularPower(30);
  return actor;
}

let meshCount = 0;
function draw3d() {
  const v = vp('threeD');
  if (!v) return;
  const old = actors3d.map((e) => e.uid).filter((uid) => v.getActor(uid));
  if (old.length) v.removeActors(old);
  for (const { actor } of actors3d) {
    const m = actor.getMapper();
    actor.delete();
    if (m) m.delete();
  }
  actors3d = [];
  if (!isDental()) return;
  const nerves = nerveList();
  for (const pts of nerves) {
    if (pts.length < 2) continue;
    actors3d.push({ uid: `cbctPlan${++meshCount}`, actor: meshActor(tubeMesh(smoothPath(pts, 0.5), NERVE_RADIUS), NERVE) });
  }
  for (const im of plan().implants) {
    const { top, apex } = implantAxis(im);
    actors3d.push({ uid: `cbctPlan${++meshCount}`, actor: meshActor(cylinderMesh(top, apex, im.diameter / 2), SAFETY[safety(clearance(im, nerves))]) });
  }
  for (const e of actors3d) v.addActor(e);
  if (!is3dHidden()) v.render();
}

// A new volume on the 3D view drops every actor: put the plan back.
function keep3d() {
  const v = vp('threeD');
  if (v && actors3d.some((e) => !v.getActor(e.uid))) draw3d();
}

function redraw(with3d = false) {
  if (with3d) redraw.need3d = true;
  if (drawQueued) return;
  drawQueued = true;
  requestAnimationFrame(() => {
    drawQueued = false;
    try {
      for (const id of MPR) drawView(id);
      if (redraw.need3d) {
        redraw.need3d = false;
        draw3d();
      } else keep3d();
    } catch (err) {
      console.warn('CBCT viewer: plan overlay', err);
    }
  });
}

// ───────────────────────── Panel ─────────────────────────

function buildPanel() {
  const sideSeg = segmented(SIDES, (side) => set({ plan: { side } }));
  const traceBtn = h('button', { class: 'chip', type: 'button', text: 'Trace', title: 'Click along the canal in the slice views (N)', onclick: () => set({ tool: state.tool === 'nerve' ? 'crosshair' : 'nerve' }) });
  const followBtn = h('button', { class: 'chip', type: 'button', text: 'Auto-follow', title: 'Follow the canal between your clicks', onclick: () => set({ plan: { follow: !plan().follow } }) });
  const undoBtn = h('button', { class: 'chip', type: 'button', text: 'Undo', onclick: undoNerve });
  const clearBtn = h('button', { class: 'chip', type: 'button', text: 'Clear', onclick: clearNerve });
  const nerveNote = h('p', { class: 'pnote' });

  const addBtn = h('button', { class: 'chip', type: 'button', text: 'Add at crosshair', title: 'The implant top goes at the crosshair, the apex into the jaw', onclick: addImplant });
  const implantChips = chipRow([], (key) => {
    set({ plan: { selected: Number(key) } });
  });
  const jawSeg = segmented([['lower', 'Lower jaw'], ['upper', 'Upper jaw']], (jaw) => setImplant(plan().selected, { jaw }));
  const sel = () => plan().implants[plan().selected];
  const num = (key, digits, unit) => {
    const val = h('span', { class: 'val' });
    return { val, show: (im) => (val.textContent = `${im[key].toFixed(digits)}${unit}`) };
  };
  const dia = num('diameter', 1, ' mm');
  const len = num('length', 1, ' mm');
  const ap = num('tiltAP', 0, '°');
  const lr = num('tiltLR', 0, '°');
  const diaSlider = slider(3, 6, 0.1, (x) => setImplant(plan().selected, { diameter: x }));
  const lenSlider = slider(6, 16, 0.5, (x) => setImplant(plan().selected, { length: x }));
  const apSlider = slider(-30, 30, 1, (x) => setImplant(plan().selected, { tiltAP: x }));
  const lrSlider = slider(-30, 30, 1, (x) => setImplant(plan().selected, { tiltLR: x }));
  const moveBtn = h('button', { class: 'chip', type: 'button', text: 'Move to crosshair', onclick: () => setImplant(plan().selected, { top: crosshairPoint() }) });
  const measureOf = (im) => (core.voxels && core.geo ? siteMeasure(core.voxels, core.geo, im, levels(), nerveList()) : null);
  const seatBtn = h('button', { class: 'chip', type: 'button', text: 'Seat at crest', title: 'Move the implant top to where its axis enters the bone', onclick: () => {
    const m = measureOf(sel());
    if (m && m.crest) setImplant(plan().selected, { top: m.crest });
  } });
  const suggestBtn = h('button', { class: 'chip', type: 'button', text: 'Suggest size', title: 'A standard size that keeps 1.5 mm of bone around it and 2 mm from the nerve (1 mm from a sinus)', onclick: () => {
    const im = sel();
    const m = measureOf(im);
    if (!m) return;
    const s = suggestSize(m, im.jaw);
    const patch = { diameter: s.diameter, length: s.length, ...(m.crest ? { top: m.crest } : {}) };
    suggested = { key: JSON.stringify({ ...im, ...patch }), notes: s.notes };
    setImplant(plan().selected, patch);
  } });
  const siteNote = h('p', { class: 'pnote' });
  const delBtn = h('button', { class: 'chip', type: 'button', text: 'Delete', onclick: () => deleteImplant(plan().selected) });
  const implantNote = h('p', { class: 'pnote' });
  const detail = h(
    'div',
    { class: 'plan-implant' },
    jawSeg.el,
    row('Diameter', diaSlider.el, dia.val),
    row('Length', lenSlider.el, len.val),
    row('Tilt A–P', apSlider.el, ap.val),
    row('Tilt L–R', lrSlider.el, lr.val),
    implantNote,
    siteNote,
    h('div', { class: 'chips' }, suggestBtn, seatBtn, moveBtn, delBtn),
  );

  // Copy summary: the plan as plain text for the patient record. A WebView may refuse the
  // clipboard: then the text is shown in a box, already selected, to copy by hand.
  const copyBtn = h('button', { class: 'chip', type: 'button', text: 'Copy summary', title: 'Copy the plan as text for the patient record', onclick: () => copySummary() });
  const sumBox = h('textarea', { class: 'sumbox', readonly: '', rows: '7', 'aria-label': 'Plan summary' });
  sumBox.style.display = 'none';
  sumBox.addEventListener('keydown', (e) => e.stopPropagation());
  let copiedTimer = 0;
  const copySummary = async () => {
    const measures = plan().implants.map((im) => {
      const m = measureOf(im);
      return m && m.crest ? m : null;
    });
    const text = planSummary(plan(), measures, foundBoxes());
    let ok = false;
    try {
      await navigator.clipboard.writeText(text);
      ok = true;
    } catch {
      sumBox.value = text;
      sumBox.style.display = '';
      sumBox.focus();
      sumBox.select();
      try {
        ok = document.execCommand('copy');
      } catch {
        ok = false;
      }
    }
    clearTimeout(copiedTimer);
    if (ok) {
      sumBox.style.display = 'none';
      copyBtn.textContent = 'Copied';
    } else copyBtn.textContent = 'Select and copy below';
    copiedTimer = setTimeout(() => (copyBtn.textContent = 'Copy summary'), 1600);
  };

  const el = section(
    'Implant plan',
    h('div', { class: 'prow' }, h('label', { text: 'Nerve canal' }), sideSeg.el),
    h('div', { class: 'chips' }, traceBtn, followBtn, undoBtn, clearBtn),
    nerveNote,
    h('div', { class: 'prow' }, h('label', { text: 'Implants' }), addBtn),
    implantChips.el,
    detail,
    h('div', { class: 'chips' }, copyBtn),
    sumBox,
  );

  const render = () => {
    el.style.display = isDental() ? '' : 'none';
    const p = plan();
    sideSeg.mark(p.side);
    traceBtn.classList.toggle('on', state.tool === 'nerve');
    followBtn.classList.toggle('on', !!p.follow);
    const count = (s) => p.nerves[s].length;
    nerveNote.textContent = state.tool === 'nerve'
      ? `Click along the ${p.side} canal in any slice view${p.follow ? ' (start and end are enough: it follows the canal between clicks)' : ''}. Backspace undoes the last click.`
      : `Right: ${count('right')} points · Left: ${count('left')} points`;
    implantChips.setItems(p.implants.map((_, i) => [String(i), `Implant ${i + 1}`]));
    implantChips.mark(String(p.selected));
    const im = sel();
    detail.style.display = im ? '' : 'none';
    if (!im) return;
    jawSeg.mark(im.jaw);
    diaSlider.set(im.diameter);
    lenSlider.set(im.length);
    apSlider.set(im.tiltAP);
    lrSlider.set(im.tiltLR);
    for (const x of [dia, len, ap, lr]) x.show(im);
    const mm = clearance(im, nerveList());
    const level = safety(mm);
    implantNote.replaceChildren();
    if (mm == null) implantNote.textContent = 'Trace the nerve canal to check the distance.';
    else implantNote.append('To the nerve canal: ', h('b', { text: `${mm.toFixed(1)} mm`, style: `color:${SAFETY[level]}` }), ` · ${SAFETY_TEXT[level]}`);
    siteNote.replaceChildren(...siteLines(measureOf(im), im).flatMap((t, i) => (i ? [h('br'), t] : [t])));
  };
  // The measured bone at the implant, in words.
  const siteLines = (m, im) => {
    if (!m) return [];
    if (!m.crest) return ['No bone found along this implant.', ...suggestNotesFor(im)];
    const f = (x) => (x == null ? '–' : `${x.toFixed(1)} mm`);
    const off = m.crestOffset;
    const lines = [
      `Bone width: ${f(m.widthCrest)} near the crest, ${f(m.widthMid)} at mid-implant`,
      im.jaw === 'upper' ? `Height to the sinus / nose floor: ${f(m.heightToAir)}` : `Height to the canal roof: ${f(m.heightToNerve)}`,
      Math.abs(off) < 0.3 ? 'Top is at the crest' : `Top is ${Math.abs(off).toFixed(1)} mm ${off > 0 ? 'above' : 'below'} the crest`,
    ];
    return [...lines, ...suggestNotesFor(im)];
  };
  return { el, render };
}

// ───────────────────────── Wiring ─────────────────────────

export function initPlanning(userInterface) {
  ui = userInterface;
  const panel = buildPanel();
  const pin = document.querySelector('.panel .pin');
  if (pin) pin.append(panel.el);
  panel.render();

  for (const id of MPR) {
    const host = core.hosts[id];
    host.addEventListener(Enums.Events.CAMERA_MODIFIED, () => redraw());
    // A click (no drag) while tracing adds a point on the slice under the mouse.
    let down = null;
    host.addEventListener('pointerdown', (e) => {
      down = e.button === 0 && state.tool === 'nerve' ? { x: e.clientX, y: e.clientY } : null;
    }, true);
    host.addEventListener('pointerup', (e) => {
      if (!down || state.tool !== 'nerve' || !core.volumeId) return;
      const moved = Math.hypot(e.clientX - down.x, e.clientY - down.y) > 4;
      down = null;
      if (moved) return;
      const r = host.getBoundingClientRect();
      const p = vp(id).canvasToWorld([e.clientX - r.left, e.clientY - r.top]);
      addNervePoint([...p]);
    }, true);
  }
  window.addEventListener('resize', () => redraw());
  window.addEventListener('keydown', (e) => {
    if (state.tool !== 'nerve' || e.target instanceof HTMLInputElement) return;
    if (e.key === 'Backspace' || e.key === 'Delete') {
      e.preventDefault();
      undoNerve();
    }
  });
  subscribe((s, changed) => {
    if (changed.has('plan') || changed.has('tool') || changed.has('phase')) panel.render();
    if (changed.has('plan') || changed.has('phase')) redraw(true);
    else if (changed.has('layout') || changed.has('focus') || changed.has('panelOpen')) redraw();
  });
}
