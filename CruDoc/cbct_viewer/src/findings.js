// Things found automatically when a scan opens (no AI: density measurements).
// Today: boxes around metal and very dense objects (implants, crowns, fillings,
// root fillings), shown in the slice views and in 3D, listed in the panel;
// clicking one moves the crosshair there.
import { Enums } from '@cornerstonejs/core';
import vtkActor from '@kitware/vtk.js/Rendering/Core/Actor.js';
import vtkMapper from '@kitware/vtk.js/Rendering/Core/Mapper.js';
import vtkPolyData from '@kitware/vtk.js/Common/DataModel/PolyData.js';
import { core, vp, MPR } from './core.js';
import { state, set, subscribe } from './state.js';
import { h, svgEl, section, chipRow } from './chrome.js';
import { is3dHidden } from './view3d.js';
import { planeDistance } from './plan.js';
import { findDense } from './assist.js';

const BOX = '#5AA2F0';

let ui = null;
let boxes = [];
let scannedFor = null; // the voxel array the boxes belong to
let show = true;
const groups = {};
let actors3d = [];
let meshCount = 0;
let queued = false;
let panel = null;

const fmt = (p) => `${p[0].toFixed(1)},${p[1].toFixed(1)}`;
const cornersOf = (b) => {
  const out = [];
  for (const x of [b.min[0], b.max[0]]) for (const y of [b.min[1], b.max[1]]) for (const z of [b.min[2], b.max[2]]) out.push([x, y, z]);
  return out;
};

function scan() {
  if (!core.voxels || !core.geo || !core.meta || core.voxels === scannedFor) return;
  scannedFor = core.voxels;
  const metal = core.meta.landmarks && core.meta.landmarks.metal;
  boxes = metal == null ? [] : findDense(core.voxels, core.geo, metal - core.valueOffset);
  panel.render();
  redraw(true);
}

function drawView(id) {
  if (!groups[id]) {
    groups[id] = svgEl('g', { class: 'found' });
    ui.frames[id].svg.append(groups[id]);
  }
  const g = groups[id];
  g.replaceChildren();
  const v = vp(id);
  if (!show || !v || !boxes.length) return;
  const cam = v.getCamera();
  boxes.forEach((b, i) => {
    const corners = cornersOf(b);
    const d = corners.map((c) => planeDistance(c, cam.focalPoint, cam.viewPlaneNormal));
    if (Math.min(...d) > 0 || Math.max(...d) < 0) return; // this slice misses the box
    const px = corners.map((c) => v.worldToCanvas(c));
    const x0 = Math.min(...px.map((p) => p[0]));
    const x1 = Math.max(...px.map((p) => p[0]));
    const y0 = Math.min(...px.map((p) => p[1]));
    const y1 = Math.max(...px.map((p) => p[1]));
    g.append(svgEl('rect', { x: x0 - 2, y: y0 - 2, width: x1 - x0 + 4, height: y1 - y0 + 4, fill: 'none', stroke: BOX, 'stroke-width': 1.25, 'stroke-dasharray': '4 3', rx: 2 }));
    const t = svgEl('text', { x: x1 + 5, y: y0 + 9, 'font-size': 10, 'font-weight': 600, fill: BOX, 'font-family': 'Geist, system-ui, sans-serif' });
    t.textContent = `M${i + 1}`;
    g.append(t);
  });
}

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
  if (!show || !boxes.length) {
    if (!is3dHidden()) v.render();
    return;
  }
  // All boxes as one set of lines (12 edges each).
  const pts = [];
  const lines = [];
  const EDGES = [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]];
  for (const b of boxes) {
    const base = pts.length / 3;
    for (const c of cornersOf(b)) pts.push(...c);
    for (const [a, c] of EDGES) lines.push(2, base + a, base + c);
  }
  const pd = vtkPolyData.newInstance();
  pd.getPoints().setData(new Float32Array(pts), 3);
  pd.getLines().setData(new Uint32Array(lines));
  const mapper = vtkMapper.newInstance({ scalarVisibility: false });
  mapper.setInputData(pd);
  const actor = vtkActor.newInstance();
  actor.setMapper(mapper);
  const p = actor.getProperty();
  p.setColor(0x5a / 255, 0xa2 / 255, 0xf0 / 255);
  p.setLineWidth(1.5);
  p.setLighting(false);
  actors3d = [{ uid: `cbctFound${++meshCount}`, actor }];
  v.addActor(actors3d[0]);
  if (!is3dHidden()) v.render();
}

function redraw(with3d = false) {
  if (with3d) redraw.need3d = true;
  if (queued) return;
  queued = true;
  requestAnimationFrame(() => {
    queued = false;
    try {
      for (const id of MPR) drawView(id);
      const v = vp('threeD');
      if (redraw.need3d || (v && actors3d.some((e) => !v.getActor(e.uid)))) {
        redraw.need3d = false;
        draw3d();
      }
    } catch (err) {
      console.warn('CBCT viewer: findings overlay', err);
    }
  });
}

function buildPanel() {
  const note = h('p', { class: 'pnote' });
  const showBtn = h('button', { class: 'chip', type: 'button', text: 'Show boxes', onclick: () => {
    show = !show;
    panel.render();
    redraw(true);
  } });
  const list = chipRow([], (key) => {
    const b = boxes[Number(key)];
    if (b && core.crosshair) core.crosshair.setToolCenter([...b.centre]);
  });
  const el = section('Found automatically', note, h('div', { class: 'chips' }, showBtn), list.el);
  const render = () => {
    el.style.display = core.meta ? '' : 'none';
    showBtn.classList.toggle('on', show);
    const metal = core.meta && core.meta.landmarks && core.meta.landmarks.metal;
    note.textContent = metal == null
      ? 'This scan has no metal level, so dense objects are not marked.'
      : boxes.length
        ? `${boxes.length} metal or very dense object${boxes.length > 1 ? 's' : ''} (implants, crowns, fillings). Click one to go there.`
        : 'No metal or very dense objects found.';
    list.setItems(boxes.map((b, i) => [String(i), `M${i + 1} · ${b.sizeMm.map((x) => x.toFixed(1)).join(' × ')} mm`]));
  };
  return { el, render };
}

export function initFindings(userInterface) {
  ui = userInterface;
  panel = buildPanel();
  const pin = document.querySelector('.panel .pin');
  if (pin) pin.append(panel.el);
  panel.render();
  for (const id of MPR) core.hosts[id].addEventListener(Enums.Events.CAMERA_MODIFIED, () => redraw());
  window.addEventListener('resize', () => redraw());
  subscribe((s, changed) => {
    // Once the full scan is in, look for dense objects when the page is idle.
    if (changed.has('phase') && s.phase === 'full') setTimeout(scan, 200);
    if (changed.has('phase') && s.phase === 'empty') {
      boxes = [];
      scannedFor = null;
    }
    if (changed.has('phase')) panel.render();
    if (changed.has('layout') || changed.has('focus') || changed.has('panelOpen')) redraw();
  });
}

// For the test scripts (with ?debug).
export const foundBoxes = () => boxes;
