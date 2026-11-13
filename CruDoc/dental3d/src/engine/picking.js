import * as THREE from 'three';
import { isVisibleDeep } from './registry.js';

const DRAG_PX = 5;
const DRAG_PX_TOUCH = 10; // fingers wobble more than a mouse
const DOUBLE_TAP_MS = 350;
const IN_APP = new URLSearchParams(location.search).get('app') === '1';

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
  let lastTap = null;

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
    down = { x: e.clientX, y: e.clientY, id: e.pointerId, moved: false, multi: false, lim: e.pointerType === 'mouse' ? DRAG_PX : DRAG_PX_TOUCH };
  });
  canvas.addEventListener('pointermove', (e) => {
    if (down) {
      if (Math.hypot(e.clientX - down.x, e.clientY - down.y) >= down.lim) down.moved = true;
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
    if (!d.moved && Math.hypot(e.clientX - d.x, e.clientY - d.y) < d.lim && !d.multi) {
      const id = pickAt(e.clientX, e.clientY);
      handlers.select(id);
      // single tap selects and centres the tooth: the camera flies to it and
      // the orbit pivot moves onto it, so dragging orbits around that tooth.
      // Double tap opens the tooth form in the app.
      const now = performance.now();
      if (id && lastTap && lastTap.id === id && now - lastTap.t < DOUBLE_TAP_MS) {
        if (IN_APP) handlers.tap?.(id);
        lastTap = null;
      }
      else {
        if (id) handlers.fly?.(id);
        lastTap = id ? { id, t: now } : null;
      }
    }
  };
  canvas.addEventListener('pointerup', end);
  canvas.addEventListener('pointercancel', end);
  canvas.addEventListener('pointerleave', () => { lastEv = null; if (!down) handlers.hover(null); });

  return { pickAt, setEnabled: (v) => { enabled = v; } };
}
