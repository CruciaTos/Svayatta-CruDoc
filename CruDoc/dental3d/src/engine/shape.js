import * as THREE from 'three';
import { updateToothMaterial } from './toothMaterial.js';
import { effectiveTooth } from '../treatments/effective.js';

const _qZ = new THREE.Quaternion();
const _qX = new THREE.Quaternion();
const _qY = new THREE.Quaternion();
const _zAxis = new THREE.Vector3(0, 0, 1);
const _xAxis = new THREE.Vector3(1, 0, 0);
const _yAxis = new THREE.Vector3(0, 1, 0);

export function applyShape(registry, store, explode, gums, changedFdis = null) {
  const state = store.get();
  const profile = state.profile || { baseShade: 'A2', archWidth: 1, archDepth: 1 };
  const L = state.layers || { upper: true, lower: true, gums: true, bone: true };
  const changedArches = new Set();

  for (const [fdi, obj] of registry.teeth) {
    const part = obj.userData.part;
    const t = effectiveTooth(state, fdi);
    if (!t) continue;

    const shift = t.shift || { md: 0, bl: 0, v: 0 };
    const rotate = t.rotate || { tip: 0, torque: 0, spin: 0 };
    const scale = t.scale || { w: 1, h: 1 };

    const td = part.frame.tangentDistal;
    const fac = part.frame.facial;
    const cor = part.frame.coronal;

    const px = part.position[0] * profile.archWidth - td[0] * shift.md + fac[0] * shift.bl + cor[0] * shift.v;
    const py = part.position[1] - td[1] * shift.md + fac[1] * shift.bl + cor[1] * shift.v;
    const pz = part.position[2] * profile.archDepth - td[2] * shift.md + fac[2] * shift.bl + cor[2] * shift.v;

    const q = new THREE.Quaternion(...part.quaternion);
    const tipRad = -part.mesialSign * THREE.MathUtils.degToRad(rotate.tip || 0);
    const torqueRad = THREE.MathUtils.degToRad(rotate.torque || 0);
    const spinRad = THREE.MathUtils.degToRad(rotate.spin || 0);

    _qZ.setFromAxisAngle(_zAxis, tipRad);
    _qX.setFromAxisAngle(_xAxis, torqueRad);
    _qY.setFromAxisAngle(_yAxis, spinRad);
    q.multiply(_qZ).multiply(_qX).multiply(_qY);

    obj.scale.set(scale.w ?? 1, scale.h ?? 1, scale.w ?? 1);
    const archVisible = part.arch === 'upper' ? L.upper : L.lower;
    obj.visible = (t.present !== false) && archVisible;

    obj.userData.rest.p.set(px, py, pz);
    obj.userData.rest.q.copy(q);
    obj.position.set(px, py, pz);
    obj.quaternion.copy(q);

    const mat = obj.userData.meshes[0]?.userData?.natural;
    if (mat) {
      updateToothMaterial(mat, t, profile);
    }

    if (!changedFdis || changedFdis.has(+fdi)) {
      changedArches.add(part.arch);
    }
  }

  explode.apply();
  if (changedFdis && changedFdis.size) {
    for (const arch of changedArches) gums.rebuildGums(arch);
  } else {
    gums.rebuildAll();
  }
}

