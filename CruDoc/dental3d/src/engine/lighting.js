import * as THREE from 'three';
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js';

// Three-point studio rig that follows the camera (so the model is always lit
// from a flattering angle), a hemisphere base, a small image-based environment
// for the clear-coat reflections, and a soft contact shadow blob.
export function setupLighting(stage) {
  const { scene, camera, controls, renderer } = stage;

  const pmrem = new THREE.PMREMGenerator(renderer);
  const env = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
  scene.environment = env;
  scene.environmentIntensity = 0.45;
  pmrem.dispose();

  scene.add(new THREE.HemisphereLight('#FFFFFF', '#C9CFD8', 0.75));

  const rig = new THREE.Group();
  scene.add(rig);
  const aim = new THREE.Object3D();
  rig.add(aim);

  const key = new THREE.DirectionalLight('#FFF0DC', 2.3); // warm, ~45 deg up-right
  key.position.set(70, 75, 100);
  const fill = new THREE.DirectionalLight('#DDE8FF', 0.7); // soft, from the left
  fill.position.set(-100, 5, 80);
  const rim = new THREE.DirectionalLight('#BFD8FF', 1.5); // cool, from behind
  rim.position.set(-20, 55, -130);
  for (const l of [key, fill, rim]) { l.target = aim; rig.add(l); }

  // Contact shadow blob under the model.
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const g = c.getContext('2d');
  const grad = g.createRadialGradient(64, 64, 4, 64, 64, 62);
  grad.addColorStop(0, 'rgba(15,23,42,0.2)');
  grad.addColorStop(0.55, 'rgba(15,23,42,0.08)');
  grad.addColorStop(1, 'rgba(15,23,42,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, 128, 128);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  const shadow = new THREE.Mesh(
    new THREE.PlaneGeometry(150, 150),
    new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false, toneMapped: false }),
  );
  shadow.rotation.x = -Math.PI / 2;
  shadow.position.set(0, -52, -6);
  shadow.renderOrder = -1;
  shadow.name = 'contact_shadow';
  scene.add(shadow);

  const sync = () => {
    rig.position.copy(controls.target);
    rig.quaternion.copy(camera.quaternion);
    rig.updateMatrixWorld(true);
  };
  stage.beforeRender.add(sync);
  sync();
  return { rig, shadow };
}
