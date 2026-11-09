// The numbers and letters around the slice views: orientation letters, slice /
// window / zoom lines, scale bar, slice scrollbar, and the status-bar readout.
import { Enums } from '@cornerstonejs/core';
import { core, vp, MPR, VIEW_AXIS, axes, dot, sub, centre, worldToIndex, worldToCornerMm, valueAt } from './core.js';
import { state, set, subscribe } from './state.js';
import { orientationLetters } from './orientation.js';
import { scrollView } from './engine.js';

const COS_HALF_DEGREE = 0.999962;
const SCALE_MM = [1, 2, 5, 10, 20, 50];

let ui = null;
const pending = new Set();
let scheduled = false;

export function updateView(id) {
  const v = vp(id);
  if (!v || !core.geo || !ui) return;
  const frame = ui.frames[id];
  const cam = v.getCamera();
  const g = core.geo;
  const a = axes();
  const k = VIEW_AXIS[id];
  const straight = Math.abs(dot(cam.viewPlaneNormal, [a.x, a.y, a.z][k])) > COS_HALF_DEGREE;
  const idx = worldToIndex(cam.focalPoint)[k];
  const N = g.dims[k];

  frame.setOrientation(orientationLetters(cam.viewUp, cam.viewPlaneNormal));
  frame.setLabel({ oblique: !straight });

  let line1;
  if (straight) {
    const n = Math.min(N, Math.max(1, Math.round(idx + 1e-6) + 1));
    // Position = (n - 0.5) x spacing, measured from the volume's first voxel corner.
    line1 = `Slice ${n} / ${N} · ${((n - 0.5) * g.spacing[k]).toFixed(2)} mm`;
  } else {
    line1 = `Oblique · ${Math.abs(dot(sub(cam.focalPoint, centre()), cam.viewPlaneNormal)).toFixed(2)} mm from centre`;
  }
  const fit = core.fit[id];
  const zoom = fit ? fit.parallelScale / cam.parallelScale : 1;
  const { low, high } = state.contrast;
  frame.setInfo(line1, `W ${Math.round(high - low)}  L ${Math.round((low + high) / 2)} · ${zoom.toFixed(2)}×`);

  // A bar of 1, 2, 5, 10, 20 or 50 mm that is 60 to 140 px wide.
  const pxPerMm = (core.hosts[id].clientHeight || 1) / (2 * cam.parallelScale);
  const mm = SCALE_MM.find((l) => l * pxPerMm >= 60) || SCALE_MM[SCALE_MM.length - 1];
  frame.setScale({ px: mm * pxPerMm, label: `${mm} mm` });

  frame.setScroll(N > 1 ? idx / (N - 1) : 0, true);
}

export function scheduleUpdate(ids = MPR) {
  ids.forEach((id) => pending.add(id));
  if (scheduled) return;
  scheduled = true;
  requestAnimationFrame(() => {
    scheduled = false;
    const todo = [...pending];
    pending.clear();
    for (const id of todo) {
      try {
        updateView(id);
      } catch (err) {
        console.warn('CBCT viewer: overlay', id, err);
      }
    }
  });
}

export function initOverlays(userInterface) {
  ui = userInterface;
  for (const id of MPR) {
    const host = core.hosts[id];
    host.addEventListener(Enums.Events.CAMERA_MODIFIED, () => scheduleUpdate([id]));

    ui.frames[id].onScroll((t) => {
      if (!core.geo) return;
      const k = VIEW_AXIS[id];
      const cam = vp(id).getCamera();
      const target = Math.round(t * (core.geo.dims[k] - 1));
      const delta = target - Math.round(worldToIndex(cam.focalPoint)[k]);
      if (delta) scrollView(id, delta);
    });

    // Mouse position in mm and the voxel value under it.
    let moving = false;
    host.addEventListener('pointermove', (e) => {
      if (moving || !core.volumeId) return;
      moving = true;
      requestAnimationFrame(() => {
        moving = false;
        try {
          const r = host.getBoundingClientRect();
          const w = vp(id).canvasToWorld([e.clientX - r.left, e.clientY - r.top]);
          const mm = worldToCornerMm(w);
          set({ status: { viewport: id, x: mm[0], y: mm[1], z: mm[2], value: valueAt(w) } });
        } catch {
          /* the view is not ready */
        }
      });
    });
  }
  subscribe((s, changed) => {
    if (changed.has('contrast') || changed.has('layout') || changed.has('focus')) scheduleUpdate();
  });
}
