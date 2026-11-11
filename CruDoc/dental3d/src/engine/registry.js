import * as THREE from 'three';
import { computeBoundsTree, disposeBoundsTree, acceleratedRaycast } from 'three-mesh-bvh';

THREE.BufferGeometry.prototype.computeBoundsTree = computeBoundsTree;
THREE.BufferGeometry.prototype.disposeBoundsTree = disposeBoundsTree;
THREE.Mesh.prototype.raycast = acceleratedRaycast;

// Index of every manifest part: nodeId -> Object3D (with `userData.part`,
// `userData.rest` = transform before explode, `userData.meshes` = own meshes).
export function createRegistry(root, manifest) {
  const partById = new Map(manifest.parts.map((p) => [p.nodeId, p]));
  const map = new Map();
  const teeth = new Map(); // fdi -> Object3D
  const pulps = new Map(); // fdi -> Object3D

  const ownMeshes = (obj) => {
    const out = [];
    const walk = (o) => {
      if (o.isMesh) out.push(o);
      for (const c of o.children) if (!partById.has(c.name)) walk(c);
    };
    walk(obj);
    return out;
  };

  const registry = {
    root, manifest, map, teeth, pulps,
    nodes: {},
    parts: partById,
    get: (id) => map.get(id),
    ownMeshes,
    register(obj, part) {
      obj.userData.part = part;
      obj.userData.meshes = ownMeshes(obj);
      for (const m of obj.userData.meshes) m.userData.ownerId = part.nodeId;
      obj.userData.rest = { p: obj.position.clone(), q: obj.quaternion.clone() };
      obj.userData.explode = new THREE.Vector3().fromArray(part.explodeVector || [0, 0, 0]);
      map.set(part.nodeId, obj);
      if (part.kind === 'tooth') teeth.set(part.fdi, obj);
      if (part.kind === 'pulp') pulps.set(part.fdi, obj);
    },
  };

  root.updateMatrixWorld(true);
  root.traverse((o) => {
    if (!o.name) return;
    const part = partById.get(o.name);
    if (part && part.source === 'glb') registry.register(o, part);
    else if (['arch_upper', 'arch_lower', 'jaw_hinge', 'templates', 'subject'].includes(o.name)) registry.nodes[o.name] = o;
  });
  registry.nodes.subject = root;
  if (registry.nodes.templates) registry.nodes.templates.visible = false;

  for (const o of [...teeth.values(), ...pulps.values()]) {
    for (const m of o.userData.meshes) {
      if (!m.geometry.boundsTree) m.geometry.computeBoundsTree();
    }
  }
  return registry;
}

export function isVisibleDeep(o) {
  for (let n = o; n; n = n.parent) if (!n.visible) return false;
  return true;
}
