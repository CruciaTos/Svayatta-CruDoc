import * as THREE from 'three';

export const PRESET_NAMES = ['front', 'upper', 'lower', 'left', 'right'];
const DEFAULT_PRESET = 'front';

// Direction = from the target towards the camera. halfW/halfH = half extents (mm)
// of what the view should contain. jaw: jaw-open value to animate to (null = keep).
const PRESETS = {
  front: { dir: [0, 0.07, 1], target: [0, 1, -2], halfW: 40, halfH: 38, jaw: 0 },
  upper: { dir: [0, -0.62, 0.78], target: [0, 4, 2], halfW: 36, halfH: 36, jaw: 1 },
  lower: { dir: [0, 0.78, 0.63], target: [0, -27, -14], halfW: 36, halfH: 34, jaw: 1, hideUpper: true },
  left: { dir: [1, 0.08, 0.1], target: [0, 0, -4], halfW: 46, halfH: 38, jaw: null },
  right: { dir: [-1, 0.08, 0.1], target: [0, 0, -4], halfW: 46, halfH: 38, jaw: null },
};

const ease = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

export function createCameraRig(stage, registry, store) {
  const { camera, controls } = stage;
  let flight = null;
  let timeScale = 1; // tests speed flights up
  const box = new THREE.Box3();
  const sphere = new THREE.Sphere();
  const tmpQ = new THREE.Quaternion();

  function halfAngles() {
    const v = THREE.MathUtils.degToRad(camera.fov / 2);
    const h = Math.atan(Math.tan(v) * camera.aspect);
    return { v, h };
  }

  function fitDistanceBox(halfW, halfH, fill = 0.86) {
    const { v, h } = halfAngles();
    return Math.max(halfH / Math.tan(v), halfW / Math.tan(h)) / fill;
  }

  function startFlight(toTarget, toDir, toDist, ms = 650) {
    const fromTarget = controls.target.clone();
    const off = camera.position.clone().sub(fromTarget);
    const fromDist = off.length();
    const fromDir = off.normalize();
    flight = {
      t: 0, ms: Math.max(1, ms / timeScale), fromTarget, toTarget: toTarget.clone(), fromDir, toDir: toDir.clone().normalize(),
      fromDist, toDist,
      qd: new THREE.Quaternion().setFromUnitVectors(fromDir, toDir.clone().normalize()),
    };
    stage.invalidate();
  }

  stage.addTicker((dt) => {
    if (!flight) return false;
    flight.t += dt * 1000;
    const k = Math.min(1, flight.t / flight.ms);
    const e = ease(k);
    controls.target.lerpVectors(flight.fromTarget, flight.toTarget, e);
    tmpQ.identity().slerp(flight.qd, e);
    const dir = flight.fromDir.clone().applyQuaternion(tmpQ);
    const dist = THREE.MathUtils.lerp(flight.fromDist, flight.toDist, e);
    camera.position.copy(controls.target).addScaledVector(dir, dist);
    camera.lookAt(controls.target);
    controls.update();
    if (k >= 1) flight = null;
    return !!flight;
  });
  controls.addEventListener('start', () => { flight = null; });

  // The upper arch sits directly above the lower one, so the 'lower' preset hides
  // it (and gives it back as soon as another preset / reset is used).
  let autoHidUpper = false;
  store.subscribe((s, changed) => { if (changed.has('layers') && s.layers.upper) autoHidUpper = false; });
  function applyPresetLayers(p) {
    const up = store.get().layers.upper;
    if (p.hideUpper && up) { autoHidUpper = true; store.set({ layers: { upper: false } }); }
    else if (!p.hideUpper && autoHidUpper) { autoHidUpper = false; store.set({ layers: { upper: true } }); }
  }

  const api = {
    set timeScale(v) { timeScale = v; },
    presets: PRESETS,
    get flying() { return !!flight; },
    cancelFlight() { flight = null; },
    // factor < 1 moves closer, > 1 further away (zoom buttons and +/- keys)
    zoomBy(factor) {
      flight = null;
      const off = camera.position.clone().sub(controls.target);
      const d = THREE.MathUtils.clamp(off.length() * factor, controls.minDistance, controls.maxDistance);
      camera.position.copy(controls.target).add(off.setLength(d));
      controls.update();
      stage.invalidate();
    },
    flyTo(nodeId, ms = 650) {
      const obj = registry.get(nodeId);
      if (!obj) return false;
      obj.updateWorldMatrix(true, true);
      box.makeEmpty().setFromObject(obj, true);
      if (box.isEmpty()) return false;
      const centre = box.getCenter(new THREE.Vector3());
      box.getBoundingSphere(sphere);
      const part = obj.userData.part;
      const dir = new THREE.Vector3().fromArray(part.cameraFocusOffset || [0, 0, 1]);
      if (dir.lengthSq() < 1e-6) dir.set(0, 0, 1);
      // lower-jaw parts move with the hinge
      if (part.arch === 'lower' || nodeId.endsWith('_lower') || (part.fdi >= 31 && part.fdi <= 48)) {
        registry.nodes.arch_lower.getWorldQuaternion(tmpQ);
        dir.applyQuaternion(tmpQ);
      }
      const { v, h } = halfAngles();
      const half = Math.min(v, h);
      const dist = Math.max(controls.minDistance + 4, sphere.radius / (0.4 * Math.tan(half)));
      startFlight(centre, dir, Math.min(dist, controls.maxDistance), ms);
      return true;
    },
    preset(name, ms = 650, withJaw = true) {
      const p = PRESETS[name] || PRESETS[DEFAULT_PRESET];
      applyPresetLayers(p);
      const ex = store.get().explode;
      const dist = fitDistanceBox(p.halfW + 8 * ex, p.halfH + 36 * ex);
      startFlight(new THREE.Vector3().fromArray(p.target), new THREE.Vector3().fromArray(p.dir), Math.min(dist, controls.maxDistance), ms);
      if (withJaw && p.jaw !== null) store.set({ jawOpen: p.jaw });
    },
    reset(ms = 650) { api.preset(DEFAULT_PRESET, ms, false); },
    // jump instantly (boot, tests)
    presetNow(name) {
      api.preset(name, 1, false);
      flight.t = 1; // finishes on the next frame
    },
  };
  return api;
}
