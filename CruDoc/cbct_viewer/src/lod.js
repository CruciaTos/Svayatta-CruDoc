// Level-of-detail (LOD) for the 3D viewport.
// Coarse when zoomed out, finer only when zoomed in, and back to coarse when zoomed out.
import { Enums } from '@cornerstonejs/core';
import { core, vp } from './core.js';
import { showVolume, logVolumeMemory } from './engine.js';
import { refresh3D, snapshot3dCanvas, fadeOutOverlay, is3dHidden } from './view3d.js';
import { loadLevel } from './session.js';

let lods = [];
let currentLod = 0;
let defaultParallelScale = null;
let isSwapping = false;
let zoomDebounceTimer = null;
let coarserHoldTimer = null;
let candidateCoarserLod = null;
const cachedLevels = new Map(); // index -> { data, geo }

export function getCurrentLod() {
  return currentLod;
}

export function initLod(coarseData, coarseGeo, meta) {
  lods = (meta.volumes && meta.volumes.lods) || [];
  if (!lods.length) {
    if (meta.volumes && meta.volumes.preview) {
      lods.push({
        file: meta.volumes.preview.file,
        factor: meta.volumes.preview.factor || 2,
        dims: coarseGeo.dims,
        spacing: coarseGeo.spacing,
        origin: coarseGeo.origin,
      });
    }
    if (meta.volumes && meta.volumes.full) {
      lods.push({
        file: meta.volumes.full.file,
        factor: 1,
        dims: meta.geometry.dims,
        spacing: meta.geometry.spacing,
        origin: meta.geometry.origin,
      });
    }
  }

  currentLod = 0;
  window.__cbct = window.__cbct || {};
  window.__cbct.lod = currentLod;

  cachedLevels.clear();
  cachedLevels.set(0, { data: coarseData, geo: coarseGeo });

  // Record initial whole-scan parallel scale once camera is set
  requestAnimationFrame(() => {
    const v3 = vp('threeD');
    if (v3) defaultParallelScale = v3.getCamera()?.parallelScale;
  });

  const host = core.hosts.threeD;
  if (host) {
    host.removeEventListener(Enums.Events.CAMERA_MODIFIED, onCameraModified);
    host.addEventListener(Enums.Events.CAMERA_MODIFIED, onCameraModified);
  }
}

let lastParallelScale = null;

function onCameraModified() {
  if (is3dHidden() || lods.length <= 1) return;
  const v3 = vp('threeD');
  if (!v3) return;
  const cam = v3.getCamera();
  if (!cam) return;

  if (lastParallelScale === null) {
    lastParallelScale = cam.parallelScale;
    if (defaultParallelScale === null) defaultParallelScale = cam.parallelScale;
    return;
  }

  if (Math.abs(cam.parallelScale - lastParallelScale) < 1e-4) return;
  lastParallelScale = cam.parallelScale;

  // Zooming occurred: evaluate only after zooming has stopped for 300 ms
  clearTimeout(zoomDebounceTimer);
  zoomDebounceTimer = setTimeout(() => {
    evaluateLod();
  }, 300);
}

function getVoxelPx(entry, pxPerMm) {
  const minSpacing = Math.min(...entry.spacing);
  return minSpacing * pxPerMm;
}

export async function evaluateLod() {
  if (isSwapping || is3dHidden() || lods.length <= 1) return;
  const v3 = vp('threeD');
  if (!v3) return;
  const canvas = v3.getCanvas();
  if (!canvas || !canvas.height) return;
  const cam = v3.getCamera();
  if (!cam || !cam.parallelScale) return;

  const canvasHeightPx = canvas.height;
  const pxPerMm = canvasHeightPx / (2 * cam.parallelScale);

  // At whole-scan view (zoomed out), always choose coarsest level (0) immediately
  const isWholeScan = defaultParallelScale && cam.parallelScale >= defaultParallelScale * 0.95;

  let targetLod = 0;
  if (!isWholeScan) {
    // Choose the coarsest L with voxelPx(L) >= 0.75; if none, the finest
    let chosen = null;
    for (let i = 0; i < lods.length; i++) {
      const vPx = getVoxelPx(lods[i], pxPerMm);
      if (vPx >= 0.75) {
        chosen = i;
        break;
      }
    }
    targetLod = chosen !== null ? chosen : lods.length - 1;

    // Hysteresis:
    // Go finer when current level's voxelPx >= 1.4
    const currVoxelPx = getVoxelPx(lods[currentLod], pxPerMm);
    if (targetLod <= currentLod && currVoxelPx >= 1.4 && currentLod < lods.length - 1) {
      targetLod = currentLod + 1;
    }
  }

  if (targetLod === currentLod) {
    candidateCoarserLod = null;
    clearTimeout(coarserHoldTimer);
    coarserHoldTimer = null;
    return;
  }

  // Go finer immediately (or return to whole scan immediately)
  if (targetLod > currentLod || isWholeScan) {
    candidateCoarserLod = null;
    clearTimeout(coarserHoldTimer);
    coarserHoldTimer = null;
    await swapToLod(targetLod);
    return;
  }

  // Go coarser only when held for 600 ms
  if (targetLod < currentLod) {
    if (candidateCoarserLod === targetLod && coarserHoldTimer) {
      // Timer already running
      return;
    }
    candidateCoarserLod = targetLod;
    clearTimeout(coarserHoldTimer);
    coarserHoldTimer = setTimeout(async () => {
      coarserHoldTimer = null;
      if (candidateCoarserLod === targetLod && !isSwapping) {
        await swapToLod(targetLod);
      }
    }, 600);
  }
}

export async function swapToLod(targetLod) {
  if (targetLod === currentLod || isSwapping) return;
  const targetEntry = lods[targetLod];
  if (!targetEntry) return;

  isSwapping = true;
  try {
    let levelData = cachedLevels.get(targetLod);
    if (!levelData) {
      levelData = await loadLevel(targetEntry);
      cachedLevels.set(targetLod, levelData);
      // Keep at most 2 levels in memory: level 0 + active level
      for (const k of cachedLevels.keys()) {
        if (k !== 0 && k !== targetLod) cachedLevels.delete(k);
      }
    }

    const overlay = snapshot3dCanvas();
    const cam = vp('threeD').getCamera();
    await showVolume(levelData.data, levelData.geo, core.valueOffset, ['threeD']);
    vp('threeD').setCamera({
      viewUp: cam.viewUp,
      viewPlaneNormal: cam.viewPlaneNormal,
      position: cam.position,
      focalPoint: cam.focalPoint,
      parallelScale: cam.parallelScale,
    });
    refresh3D();
    currentLod = targetLod;
    window.__cbct = window.__cbct || {};
    window.__cbct.lod = currentLod;
    logVolumeMemory(`LOD swapped to ${currentLod}`);
    await fadeOutOverlay(overlay, 350);
  } catch (err) {
    console.warn('CBCT viewer: LOD swap error', err);
  } finally {
    isSwapping = false;
    // If scale changed during swap, re-evaluate
    const v3 = vp('threeD');
    const cam = v3?.getCamera();
    if (cam && Math.abs(cam.parallelScale - lastParallelScale) > 1e-4) {
      setTimeout(evaluateLod, 50);
    }
  }
}

