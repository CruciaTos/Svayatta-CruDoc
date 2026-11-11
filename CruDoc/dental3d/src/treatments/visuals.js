import * as THREE from 'three';
import { MATERIALS, SHADES } from '../data/treatments.js';
import { effectiveTooth, ARCH_ORDER } from './effective.js';

const steelMat = new THREE.MeshStandardMaterial({
  color: '#B0B4BA',
  metalness: 0.92,
  roughness: 0.22,
});

const titaniumMat = new THREE.MeshPhysicalMaterial({
  color: new THREE.Color(MATERIALS.titanium?.color || '#9EA3A8'),
  roughness: 0.35,
  metalness: 0.9,
});

const _matCache = new Map();
function getMaterial(matKey, fallbackColor = '#EFE8D6') {
  const cacheKey = `${matKey}_${fallbackColor}`;
  if (_matCache.has(cacheKey)) return _matCache.get(cacheKey);

  const info = MATERIALS[matKey] || MATERIALS.emax;
  const col = info.color || fallbackColor;
  const mat = new THREE.MeshPhysicalMaterial({
    color: new THREE.Color(col),
    roughness: info.roughness ?? 0.18,
    metalness: info.metalness ?? 0,
    transmission: info.transmission ?? 0,
    clearcoat: info.metalness ? 0 : 0.6,
    clearcoatRoughness: 0.12,
  });
  _matCache.set(cacheKey, mat);
  return mat;
}

export function createVisuals(registry, store, stage) {
  if (registry.nodes.templates) {
    registry.nodes.templates.visible = false;
  }

  const tplFixture = registry.get('tpl_implant_fixture') || registry.nodes.templates?.getObjectByName('tpl_implant_fixture');
  const tplAbutment = registry.get('tpl_implant_abutment') || registry.nodes.templates?.getObjectByName('tpl_implant_abutment');
  const tplBracket = registry.get('tpl_bracket') || registry.nodes.templates?.getObjectByName('tpl_bracket');

  function clearVisuals() {
    for (const [, toothObj] of registry.teeth) {
      const toRemove = toothObj.children.filter((c) => c.userData.isTreatmentVisual);
      for (const c of toRemove) {
        toothObj.remove(c);
        if (c.geometry && !c.userData.sharedGeom) c.geometry.dispose();
        if (c.material && !c.userData.sharedMat) c.material.dispose();
      }
      toothObj.position.copy(toothObj.userData.rest.p);
      for (const m of toothObj.userData.meshes) {
        if (m.userData.natural) {
          m.userData.natural.clippingPlanes = null;
        }
      }
    }
    for (const arch of ['upper', 'lower']) {
      const archNode = registry.nodes['arch_' + arch];
      if (archNode) {
        const wires = archNode.children.filter((c) => c.userData.isArchWire);
        for (const w of wires) {
          archNode.remove(w);
          if (w.geometry) w.geometry.dispose();
        }
      }
    }
  }

  function rebuild() {
    clearVisuals();
    const state = store.get();
    const profile = state.profile || { baseShade: 'A2' };

    // Update world matrices for accurate positioning
    registry.root.updateMatrixWorld(true);

    const bracketPointsByArch = { upper: [], lower: [] };

    for (const [fdi, toothObj] of registry.teeth) {
      const t = effectiveTooth(state, fdi);
      if (!t) continue;
      const part = toothObj.userData.part;
      const baseMesh = toothObj.userData.meshes[0];
      if (!baseMesh) continue;

      const crownShadeKey = t.shade ?? profile.baseShade ?? 'A1';
      const crownHex = SHADES[crownShadeKey] || (/^#[0-9a-f]{6}$/i.test(crownShadeKey) ? crownShadeKey : SHADES.A1);

      // 1. RCT pulp color
      const pulp = registry.pulps.get(fdi);
      if (pulp) {
        pulp.userData.rctDone = t.rctDone;
      }

      // 2. Implant
      if (t.implant) {
        // hide tooth's own mesh below y = 0
        if (baseMesh.userData.natural) {
          baseMesh.userData.natural.clippingPlanes = [new THREE.Plane(new THREE.Vector3(0, 1, 0), 0)];
        }
        if (tplFixture) {
          const fix = tplFixture.clone();
          fix.userData.isTreatmentVisual = true;
          fix.position.set(0, -1.5, 0);
          fix.traverse((m) => {
            if (m.isMesh) {
              m.material = titaniumMat;
              m.userData.sharedGeom = true;
              m.userData.sharedMat = true;
            }
          });
          toothObj.add(fix);
        }
        if (tplAbutment) {
          const abut = tplAbutment.clone();
          abut.userData.isTreatmentVisual = true;
          abut.position.set(0, -1.5, 0);
          abut.traverse((m) => {
            if (m.isMesh) {
              m.material = titaniumMat;
              m.userData.sharedGeom = true;
              m.userData.sharedMat = true;
            }
          });
          toothObj.add(abut);
        }
        // Implant also gets crown on top (clipping below y = -0.6)
        const crownMat = getMaterial(t.implantMaterial || 'zirconia', crownHex).clone();
        crownMat.clippingPlanes = [new THREE.Plane(new THREE.Vector3(0, 1, 0), 0.6)];
        crownMat.clipShadows = true;
        const cap = new THREE.Mesh(baseMesh.geometry, crownMat);
        cap.scale.set(1.03, 1.03, 1.03);
        cap.userData.isTreatmentVisual = true;
        cap.userData.sharedGeom = true;
        toothObj.add(cap);
      }
      // 3. Pontic (bridge false tooth)
      else if (t.pontic) {
        if (baseMesh.userData.natural) {
          baseMesh.userData.natural.clippingPlanes = [new THREE.Plane(new THREE.Vector3(0, 1, 0), 0)];
        }
        // raised so it does not touch the gum line
        baseMesh.position.y = 0.8;

        const crownMat = getMaterial(t.crownMaterial || 'zirconia', crownHex).clone();
        crownMat.clippingPlanes = [new THREE.Plane(new THREE.Vector3(0, 1, 0), 0.6)];
        crownMat.clipShadows = true;
        const cap = new THREE.Mesh(baseMesh.geometry, crownMat);
        cap.position.y = 0.8;
        cap.scale.set(1.03, 1.03, 1.03);
        cap.userData.isTreatmentVisual = true;
        cap.userData.sharedGeom = true;
        toothObj.add(cap);
      }
      // 4. Crown
      else if (t.crowned) {
        const crownMat = getMaterial(t.crownMaterial || 'emax', crownHex).clone();
        crownMat.clippingPlanes = [new THREE.Plane(new THREE.Vector3(0, 1, 0), 0.6)];
        crownMat.clipShadows = true;
        const cap = new THREE.Mesh(baseMesh.geometry, crownMat);
        cap.scale.set(1.03, 1.03, 1.03);
        cap.userData.isTreatmentVisual = true;
        cap.userData.sharedGeom = true;
        toothObj.add(cap);
      }
      // 5. Veneer
      else if (t.veneer) {
        const veneerMat = getMaterial(t.veneerMaterial || 'emax', crownHex).clone();
        veneerMat.clippingPlanes = [
          new THREE.Plane(new THREE.Vector3(0, 0, 1), 0.15 * part.dims.bl),
          new THREE.Plane(new THREE.Vector3(0, 1, 0), 0.8),
        ];
        veneerMat.clipShadows = true;
        const ven = new THREE.Mesh(baseMesh.geometry, veneerMat);
        ven.scale.set(1.02, 1.02, 1.02);
        ven.userData.isTreatmentVisual = true;
        ven.userData.sharedGeom = true;
        toothObj.add(ven);
      }

      // 6. Braces
      if (t.brackets && tplBracket) {
        const bracket = tplBracket.clone();
        bracket.userData.isTreatmentVisual = true;
        const localSlot = new THREE.Vector3(0, 0.45 * part.dims.crownHeight, 0.5 * part.dims.bl * 0.95);
        bracket.position.copy(localSlot);
        bracket.traverse((m) => {
          if (m.isMesh) {
            m.material = steelMat;
            m.userData.sharedGeom = true;
            m.userData.sharedMat = true;
          }
        });
        toothObj.add(bracket);

        // Collect point for archwire
        bracket.updateMatrixWorld(true);
        const worldPt = new THREE.Vector3(0, 0, 1.2).applyMatrix4(bracket.matrixWorld);
        const archNode = registry.nodes['arch_' + part.arch];
        if (archNode) {
          archNode.updateMatrixWorld(true);
          const archPt = worldPt.clone();
          archNode.worldToLocal(archPt);
          bracketPointsByArch[part.arch].push({ fdi, pt: archPt });
        }
      }
    }

    // 7. Archwire tube meshes
    for (const arch of ['upper', 'lower']) {
      const archItems = bracketPointsByArch[arch];
      if (archItems.length >= 2) {
        const order = ARCH_ORDER[arch];
        archItems.sort((a, b) => order.indexOf(a.fdi) - order.indexOf(b.fdi));
        const pts = archItems.map((x) => x.pt);

        const curve = new THREE.CatmullRomCurve3(pts, false, 'centripetal', 0.5);
        const tubeGeo = new THREE.TubeGeometry(curve, 64, 0.25, 8, false);
        const wireMesh = new THREE.Mesh(tubeGeo, steelMat);
        wireMesh.userData.isArchWire = true;
        registry.nodes['arch_' + arch].add(wireMesh);
      }
    }

    stage.invalidate();
  }

  return { rebuild, clearVisuals };
}
