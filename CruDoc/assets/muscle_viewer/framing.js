import * as THREE from './vendor/three.module.js';

/**
 * Camera placement that makes the whole body fill the part of the stage that
 * the overlay bars (mode switch on top, view buttons below) do not cover.
 *
 * Fits the body's real height and width to the matching field of view. The
 * old approach fitted its bounding *sphere* to the narrower side of the stage,
 * which sized a tall body to the stage width and left it small.
 *
 * `top` / `bottom` / `side` are the pixels at each edge to keep clear. Returns
 * where the camera goes and what it looks at (lowered or raised so the body
 * sits centred in the clear area rather than in the whole stage).
 */
export function frameBody({
  box,
  dir,
  fovDeg,
  aspect,
  stageW,
  stageH,
  top = 0,
  bottom = 0,
  side = 0,
  pad = 1.04,
}) {
  const size = box.getSize(new THREE.Vector3());
  const center = box.getCenter(new THREE.Vector3());
  const d = dir.clone().normalize();

  // Seen from the side the body's width is its depth, and vice versa.
  const fromSide = Math.abs(d.x) > Math.abs(d.z);
  const width = fromSide ? size.z : size.x;
  const depth = fromSide ? size.x : size.z;

  const availH = Math.max(stageH - top - bottom, stageH * 0.4);
  const availW = Math.max(stageW - 2 * side, stageW * 0.5);

  const tanV = Math.tan(THREE.MathUtils.degToRad(fovDeg) / 2);
  const tanH = tanV * aspect;
  const distV = (size.y / 2 * pad) / (tanV * (availH / stageH));
  const distH = (width / 2 * pad) / (tanH * (availW / stageW));
  // The camera looks at the body's centre; its front surface is half the
  // depth closer, so back off by that much to keep the silhouette inside.
  const dist = Math.max(distV, distH) + depth / 2;

  // Centre the body in the clear area: if more is covered at the bottom than
  // the top, the body must sit higher on screen, so look slightly below it.
  const worldPerPx = (2 * dist * tanV) / stageH;
  const target = center.clone().add(new THREE.Vector3(0, -((bottom - top) / 2) * worldPerPx, 0));
  const pos = target.clone().add(d.multiplyScalar(dist));
  return { pos, target };
}
