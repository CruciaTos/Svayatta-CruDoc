// Level of detail for the 3D view's STILL picture.
// The view always holds a light copy of the scan (level 0), which is what moves.
// When the picture is still it shows the coarsest level whose voxels are no
// bigger than about one screen pixel: sharper levels are fetched only when the
// zoom or the window size calls for them. The last level is the slice views'
// own volume, borrowed (the GPU texture is shared, no second copy).
import { Enums } from '@cornerstonejs/core';
import { core, vp } from './core.js';
import { state, subscribe } from './state.js';
import { setFine3d } from './engine.js';
import { refresh3D, snapshot3dCanvas, fadeOutOverlay, is3dHidden, isMoving, stillMs, needsCalibration, isSurfaceMode } from './view3d.js';
import { loadLevel } from './session.js';

const SHARP_PX = 1.3; // a voxel may be this many screen pixels before a finer level is wanted
const WASTE_PX = 0.6; // go coarser only when the level on screen is this much finer than the screen
const TOO_SLOW_MS = 700; // a still frame slower than this: stop using that level on this computer

let levels = []; // coarse to fine
let current = 0;
let cap = Infinity; // finest level this computer may use
let busy = false;
let timer = null;
let wired = false;
const kept = new Map(); // level index -> { data, geo } fetched before

export const getCurrentLod = () => current;

function publish() {
  if (window.__cbct) window.__cbct.lod = current;
}

export function initLod(meta) {
  const vols = meta.volumes || {};
  const lods = vols.lods && vols.lods.length ? vols.lods : [vols.preview, vols.full].filter(Boolean);
  levels = lods.slice(0, -1).map((e) => ({ file: e.file, dims: e.dims, spacing: e.spacing, origin: e.origin }));
  levels.push({ shared: true });
  current = 0;
  cap = Infinity;
  kept.clear();
  publish();
  if (wired) return;
  wired = true;
  const soon = () => {
    clearTimeout(timer);
    timer = setTimeout(evaluateLod, 300);
  };
  core.hosts.threeD.addEventListener(Enums.Events.CAMERA_MODIFIED, soon);
  subscribe((s, changed) => {
    // view3d: a new look may be ray-cast again and want its sharper copy.
    if (changed.has('layout') || changed.has('focus') || changed.has('panelOpen') || changed.has('phase') || changed.has('view3d')) soon();
  });
  window.addEventListener('resize', soon);
}

const spacingOf = (lv) => (lv.shared ? core.geo.spacing : lv.spacing);

// `now`: called by session.js the moment the full volume is in (the phase is not 'full' yet).
export async function evaluateLod(now = false) {
  // Meshes are built from the slice views' volume (surface.js), not from these
  // levels. The full volume just came in: rebuild them from it, without waiting.
  if (isSurfaceMode()) {
    if (now === true) refresh3D();
    return;
  }
  if (busy || levels.length < 2 || (state.phase !== 'full' && now !== true) || is3dHidden() || !core.geo) return;
  const v = vp('threeD');
  const canvas = v && v.getCanvas();
  const cam = v && v.getCamera();
  if (!canvas || !canvas.height || !cam || !cam.parallelScale) return;
  if (isMoving()) {
    clearTimeout(timer);
    timer = setTimeout(evaluateLod, 300);
    return;
  }
  const pxPerMm = canvas.height / (2 * cam.parallelScale); // parallel projection
  const voxelPx = (i) => Math.min(...spacingOf(levels[i])) * pxPerMm;
  // This computer cannot draw the level on screen fast enough: never above the one below it.
  if (current > 1 && stillMs() > TOO_SLOW_MS) cap = Math.min(cap, current - 1);
  const top = Math.min(levels.length - 1, cap);
  let want = top;
  for (let i = 0; i <= top; i++) {
    if (voxelPx(i) <= SHARP_PX) {
      want = i;
      break;
    }
  }
  if (want < current && current <= top && voxelPx(current) > WASTE_PX) want = current;
  if (want === current) {
    // Same level, but the view changed size: measure again what this computer can move smoothly.
    if (needsCalibration()) await refresh3D();
    return;
  }

  busy = true;
  try {
    let level = null;
    if (want > 0) {
      const lv = levels[want];
      if (lv.shared) level = 'slices';
      else {
        level = kept.get(want) || (await loadLevel(lv));
        kept.set(want, level);
      }
    }
    if (isMoving()) return; // try again once the picture is still (the finally block reschedules)
    const overlay = snapshot3dCanvas();
    await setFine3d(level);
    current = want;
    publish();
    await refresh3D({ cover: false });
    fadeOutOverlay(overlay, 350);
  } catch (err) {
    console.warn('CBCT viewer: 3D detail level', err);
  } finally {
    busy = false;
    clearTimeout(timer);
    timer = setTimeout(evaluateLod, 400);
  }
}
