import * as THREE from 'three';
import { sampleArch, buildGeometry } from './gumGeometry.js';
import { createGumMaterial, createBoneMaterial } from './materials.js';
import { effectiveTooth } from '../treatments/effective.js';

const _ax = new THREE.Vector3();

export const ARCH_ORDER = {
  upper: [18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28],
  lower: [48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38],
};

// Owns the four runtime meshes (gum/bone x upper/lower). They are children of
// their arch node, registered under their manifest nodeIds, and are rebuilt from
// the CURRENT rest transform + per-tooth state of the store.
export function createGums(registry, store, onChange) {
  const meshes = {};
  for (const kind of ['gum', 'bone']) {
    for (const arch of ['upper', 'lower']) {
      const id = `${kind}_${arch}`;
      const part = registry.parts.get(id);
      const mesh = new THREE.Mesh(new THREE.BufferGeometry(), kind === 'gum' ? createGumMaterial() : createBoneMaterial());
      mesh.name = id;
      mesh.userData.kind = kind;
      mesh.userData.arch = arch;
      registry.nodes[`arch_${arch}`].add(mesh);
      registry.register(mesh, part);
      meshes[id] = mesh;
    }
  }
  const timings = { upper: 0, lower: 0 };

  function toothData(arch) {
    const st = store.get();
    return ARCH_ORDER[arch].map((fdi) => {
      const obj = registry.teeth.get(fdi);
      const part = obj.userData.part;
      const s = effectiveTooth(st, fdi);
      _ax.set(0, 1, 0).applyQuaternion(obj.userData.rest.q);
      return {
        fdi, C: obj.userData.rest.p, cervBl: part.dims.cervBl, md: part.dims.md, cls: part.toothClass,
        present: s.present, rec: s.recession, infl: s.inflammation, bl: s.boneLoss,
        ax: _ax.x, ay: _ax.y, az: _ax.z, rl: (part.dims.rootLength || 12) * (obj.scale?.y || 1),
      };
    });
  }

  function rebuildGums(arch) {
    const t0 = performance.now();
    const S = sampleArch(toothData(arch), arch === 'upper');
    for (const kind of ['gum', 'bone']) {
      const mesh = meshes[`${kind}_${arch}`];
      const old = mesh.geometry;
      mesh.geometry = buildGeometry(S, kind);
      old.dispose();
    }
    timings[arch] = performance.now() - t0;
    onChange?.(arch);
    return timings[arch];
  }

  return {
    meshes, timings, rebuildGums,
    rebuildAll() { rebuildGums('upper'); rebuildGums('lower'); },
    archOfFdi: (fdi) => (ARCH_ORDER.upper.includes(+fdi) ? 'upper' : 'lower'),
  };
}
