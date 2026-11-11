import * as THREE from 'three';
import { isVisibleDeep } from './registry.js';

const DRAG_PX = 5;

// Click selects (only if the pointer moved < 5 px); hover raycasts at most once
// per animation frame, never while a button is down and never for touch.
export function createPicking(stage, registry, handlers) {
  const { canvas, camera } = stage;
  const raycaster = new THREE.Raycaster();
  raycaster.firstHitOnly = true;
  const ndc = new THREE.Vector2();
  let down = null;
  let hoverQueued = false;
  let lastEv = null;
  let enabled = true;

  function targets() {
    const out = [];
    for (const obj of registry.map.values()) {
      const kind = obj.userData.part.kind;
      if (kind === 'pulp') continue;
      if (!isVisibleDeep(obj)) continue;
      for (const m of obj.userData.meshes) out.push(m);
    }
    return out;
  }

  function pickAt(clientX, clientY) {
    const r = canvas.getBoundingClientRect();
    ndc.set(((clientX - r.left) / r.width) * 2 - 1, -((clientY - r.top) / r.height) * 2 + 1);
    raycaster.setFromCamera(ndc, camera);
    const hits = raycaster.intersectObjects(targets(), false);
    return hits.length ? hits[0].object.userData.ownerId : null;
  }

  canvas.addEventListener('pointerdown', (e) => {
    if (down) { down.multi = true; return; } // second finger: pinch/pan, never a tap
    if (e.button !== 0 && e.pointerType === 'mouse') return;
    down = { x: e.clientX, y: e.clientY, id: e.pointerId, moved: false, multi: false };
  });
  canvas.addEventListener('pointermove', (e) => {
    if (down) {
      if (Math.hypot(e.clientX - down.x, e.clientY - down.y) >= DRAG_PX) down.moved = true;
      return;
    }
    if (e.pointerType !== 'mouse' || !enabled) return;
    lastEv = e;
    if (!hoverQueued) {
      hoverQueued = true;
      requestAnimationFrame(() => {
        hoverQueued = false;
        if (down || !lastEv) return;
        handlers.hover(pickAt(lastEv.clientX, lastEv.clientY));
      });
    }
  });
  const end = (e) => {
    const d = down; down = null;
    if (!d || e.type === 'pointercancel') return;
    if (!d.moved && Math.hypot(e.clientX - d.x, e.clientY - d.y) < DRAG_PX && !d.multi) {
      handlers.select(pickAt(e.clientX, e.clientY));
    }
  };
  canvas.addEventListener('pointerup', end);
  canvas.addEventListener('pointercancel', end);
  canvas.addEventListener('pointerleave', () => { lastEv = null; if (!down) handlers.hover(null); });

  return { pickAt, setEnabled: (v) => { enabled = v; } };
}
