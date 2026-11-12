import * as THREE from 'three';

// Dev stand-in for subject.glb: capsule-ish teeth (crown + root) and pulps built
// from the manifest, with the same node hierarchy and transforms as the real file.
export function buildPlaceholder(manifest) {
  const subject = new THREE.Group(); subject.name = 'subject';
  const archUpper = new THREE.Group(); archUpper.name = 'arch_upper';
  const hinge = new THREE.Group(); hinge.name = 'jaw_hinge';
  hinge.position.fromArray(manifest.jawHinge.point);
  const archLower = new THREE.Group(); archLower.name = 'arch_lower';
  archLower.position.fromArray(manifest.jawHinge.point).multiplyScalar(-1);
  const templates = new THREE.Group(); templates.name = 'templates';
  subject.add(archUpper, hinge, templates);
  hinge.add(archLower);
  for (const n of manifest.hierarchy.subject.templates) {
    const m = new THREE.Mesh(new THREE.BoxGeometry(2, 2, 2), new THREE.MeshStandardMaterial({ color: '#999' }));
    m.name = n; templates.add(m);
  }

  const withMask = (geo) => {
    const n = geo.attributes.position.count;
    geo.setAttribute('color', new THREE.BufferAttribute(new Float32Array(n * 3).fill(1), 3));
    return geo;
  };
  for (const p of manifest.parts) {
    if (p.kind !== 'tooth') continue;
    const { crownHeight: ch, rootLength: rl, cervMd, cervBl, md, bl } = p.dims;
    const crown = new THREE.CapsuleGeometry(0.5, Math.max(0.1, ch - 1), 6, 14);
    crown.translate(0, ch / 2, 0); // y in [0, ch] approx
    crown.scale(md * 0.95, 1, bl * 0.95);
    const root = new THREE.ConeGeometry(0.5, rl, 14, 1, true);
    root.scale(cervMd * 0.9, 1, cervBl * 0.9);
    root.rotateX(Math.PI); // apex down
    root.translate(0, -rl / 2, 0);
    const parts = [crown, root].map((g) => g.toNonIndexed());
    const merged = mergeSimple(parts);
    const mesh = new THREE.Mesh(withMask(merged), new THREE.MeshStandardMaterial({ color: '#EADFC8' }));
    mesh.name = p.nodeId;
    mesh.position.fromArray(p.position);
    mesh.quaternion.fromArray(p.quaternion);
    const pg = new THREE.CapsuleGeometry(0.5, 1, 4, 8);
    pg.scale(cervMd * 0.25, (ch + rl) * 0.45, cervBl * 0.25);
    pg.translate(0, (ch - rl) * 0.2, 0);
    const pulp = new THREE.Mesh(pg, new THREE.MeshStandardMaterial({ color: '#D9534F' }));
    pulp.name = 'pulp_' + p.fdi;
    mesh.add(pulp);
    (p.arch === 'upper' ? archUpper : archLower).add(mesh);
  }
  return subject;
}

function mergeSimple(geos) {
  const total = geos.reduce((s, g) => s + g.attributes.position.count, 0);
  const pos = new Float32Array(total * 3);
  const nor = new Float32Array(total * 3);
  let o = 0;
  for (const g of geos) {
    pos.set(g.attributes.position.array, o);
    nor.set(g.attributes.normal.array, o);
    o += g.attributes.position.array.length;
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  out.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  return out;
}
