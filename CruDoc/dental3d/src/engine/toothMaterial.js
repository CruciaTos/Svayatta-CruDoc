import * as THREE from 'three';
import { SHADES } from '../data/treatments.js';

const CEMENTUM = '#D9C8A2';
const INCISAL_GREY = '#B4C0CC';
const NEUTRAL_LIGHT = '#D5D8DE';

// One enamel material per tooth. Everything visual that pass 2 needs to vary
// per tooth lives in `material.userData.u` (uniform value holders).
export function createToothMaterial(toothPart, { vertexColors = true } = {}) {
  const isAnterior = toothPart.toothClass === 'incisor' || toothPart.toothClass === 'canine';
  const dims = toothPart.dims;
  const u = {
    uShade: { value: new THREE.Color(SHADES.A2) },
    uCementum: { value: new THREE.Color(CEMENTUM) },
    uIncisal: { value: new THREE.Color(INCISAL_GREY) },
    uCrownH: { value: dims.crownHeight },
    uAnterior: { value: isAnterior ? 1 : 0 },
    uTint: { value: new THREE.Vector4(1, 1, 1, 0) }, // rgb (linear) + amount
    // --- reserved for pass 2 (neutral defaults) ---
    uMd: { value: dims.md },
    uBl: { value: dims.bl },
    uMesialSign: { value: toothPart.mesialSign },
    uSurfFill: { value: Array.from({ length: 5 }, () => new THREE.Vector4(0, 0, 0, 0)) },
    uSurfCaries: { value: [0, 0, 0, 0, 0] },
    uPrep: { value: 0 },
    uStain: { value: 0 },
    uCalculus: { value: 0 },
    uWear: { value: 0 },
    uChip: { value: 0 },
  };

  const mat = new THREE.MeshPhysicalMaterial({
    color: '#FFFFFF',
    roughness: 0.2,
    metalness: 0,
    clearcoat: 0.6,
    clearcoatRoughness: 0.12,
    vertexColors,
    envMapIntensity: 1,
  });
  mat.userData.u = u;

  mat.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, u);
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', `#include <common>
varying vec3 vLocalPos;
uniform float uCrownH;
uniform float uWear;
uniform float uChip;
uniform float uMd;
uniform float uMesialSign;`)
      .replace('#include <begin_vertex>', `#include <begin_vertex>
      if (uWear > 0.0) {
        transformed.y = min(transformed.y, uCrownH - uWear);
      }
      if (uChip > 0.0) {
        vec3 chipCentre = vec3(uMesialSign * uMd * 0.5, uCrownH, 0.0);
        float chipRadius = uChip * 0.5 * uMd;
        vec3 chipDir = transformed - chipCentre;
        float chipDist = length(chipDir);
        if (chipDist < chipRadius) {
          transformed = chipCentre + (chipDist > 0.0001 ? (chipDir / chipDist) : vec3(0.0, -1.0, 0.0)) * chipRadius;
        }
      }
      vLocalPos = transformed;`);
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', `#include <common>
varying vec3 vLocalPos;
uniform vec3 uShade; uniform vec3 uCementum; uniform vec3 uIncisal;
uniform float uCrownH; uniform float uAnterior; uniform vec4 uTint;
uniform float uMd; uniform float uBl; uniform float uMesialSign;
uniform vec4 uSurfFill[5]; uniform float uSurfCaries[5];
uniform float uPrep; uniform float uStain; uniform float uCalculus; uniform float uWear; uniform float uChip;
float gRootW;`)
      .replace('#include <color_fragment>', `
      float yN = vLocalPos.y / max(uCrownH, 0.001);
      gRootW = 1.0 - smoothstep(-1.0, 0.25, vLocalPos.y);
      vec3 base = mix(uShade, uCementum, gRootW);
      float incisal = smoothstep(0.88, 1.0, yN) * uAnterior;
      base = mix(base, uIncisal, incisal * 0.45);
      base = mix(base, vec3(0.45, 0.30, 0.14), clamp(uStain, 0.0, 1.0) * 0.6);
      float calc = clamp(uCalculus, 0.0, 1.0) * (1.0 - smoothstep(0.0, 0.3, yN)) * step(-0.5, vLocalPos.y);
      base = mix(base, vec3(0.55, 0.47, 0.30), calc * 0.7);
      base = mix(base, uTint.rgb, uTint.a);
      #ifdef USE_COLOR
        base *= mix(0.78, 1.0, vColor.r);
      #endif
      diffuseColor.rgb = base;`)
      .replace('#include <roughnessmap_fragment>', `#include <roughnessmap_fragment>
      roughnessFactor = mix(roughnessFactor, 0.62, gRootW);`);
  };
  mat.customProgramCacheKey = () => 'tooth-enamel-v2';
  return mat;
}

export function updateToothMaterial(mat, t, profile) {
  if (!mat?.userData?.u) return;
  const u = mat.userData.u;
  const shadeKey = t.shade ?? profile?.baseShade ?? 'A2';
  const hex = SHADES[shadeKey] || (/^#[0-9a-f]{6}$/i.test(shadeKey) ? shadeKey : SHADES.A2);
  u.uShade.value.set(hex);
  u.uStain.value = Math.min(1, Math.max(0, Number(t.stain) || 0));
  u.uCalculus.value = Math.min(1, Math.max(0, Number(t.calculus) || 0));
  u.uWear.value = Math.min(4, Math.max(0, Number(t.wear) || 0));
  u.uChip.value = Math.min(1, Math.max(0, Number(t.chip) || 0));
}

export function setTint(mat, hex, amount) {
  const t = mat.userData.u.uTint.value;
  if (!hex || amount <= 0) { t.w = 0; return; }
  const c = _c.set(hex);
  t.set(c.r, c.g, c.b, amount);
}
const _c = new THREE.Color();
export { NEUTRAL_LIGHT };
