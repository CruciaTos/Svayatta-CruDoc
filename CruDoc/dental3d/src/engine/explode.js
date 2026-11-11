import * as THREE from 'three';

// Explode (0..1) and jaw opening (0..1), both smoothed towards the store value.
// Explode offsets are world millimetres (manifest explodeVector x factor).
export function createExplode(registry, store, stage) {
  let cur = 0, curJaw = 0;
  const maxOpen = THREE.MathUtils.degToRad(registry.manifest.jawHinge.maxOpenDeg || 26);
  const hinge = registry.nodes.jaw_hinge;
  const q = new THREE.Quaternion();
  const v = new THREE.Vector3();

  function apply() {
    if (hinge) { hinge.rotation.x = curJaw * maxOpen; hinge.updateMatrixWorld(true); }
    for (const obj of registry.map.values()) {
      const rest = obj.userData.rest;
      if (!rest) continue;
      const ev = obj.userData.explode;
      if (ev.lengthSq() === 0) { continue; }
      const parent = obj.parent;
      if (cur === 0) { obj.position.copy(rest.p); continue; }
      parent.getWorldQuaternion(q).invert();
      v.copy(ev).multiplyScalar(cur).applyQuaternion(q);
      obj.position.copy(rest.p).add(v);
    }
  }

  function tick(dt) {
    const s = store.get();
    const k = 1 - Math.exp(-dt * 9);
    let busy = false;
    if (Math.abs(s.explode - cur) > 1e-3) { cur += (s.explode - cur) * k; busy = true; } else if (cur !== s.explode) { cur = s.explode; busy = true; }
    if (Math.abs(s.jawOpen - curJaw) > 1e-3) { curJaw += (s.jawOpen - curJaw) * k; busy = true; } else if (curJaw !== s.jawOpen) { curJaw = s.jawOpen; busy = true; }
    if (busy) apply();
    return busy;
  }
  stage.addTicker(tick);

  return {
    apply,
    // jump straight to the stored values (used by tests and snapshots)
    snap() { const s = store.get(); cur = s.explode; curJaw = s.jawOpen; apply(); stage.invalidate(); },
    get current() { return { explode: cur, jawOpen: curJaw }; },
  };
}
