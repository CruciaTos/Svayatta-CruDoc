import * as THREE from 'three';
import { SHADES } from '../data/treatments.js';

const CEMENTUM = '#E6DCC4';
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
    uSurfMetal: { value: [0, 0, 0, 0, 0] },
    uPrep: { value: 0 },
    uStain: { value: 0 },
    uCalculus: { value: 0 },
    uWear: { value: 0 },
    uChip: { value: 0 },
  };

  const mat = new THREE.MeshPhysicalMaterial({
    color: '#FFFFFF',
    roughness: 0.16,
    metalness: 0,
    clearcoat: 0.85,
    clearcoatRoughness: 0.08,
    sheen: 0.3,
    sheenRoughness: 0.6,
    sheenColor: new THREE.Color('#FFE6D8'),
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
uniform vec4 uSurfFill[5]; uniform float uSurfCaries[5]; uniform float uSurfMetal[5];
uniform float uPrep; uniform float uStain; uniform float uCalculus; uniform float uWear; uniform float uChip;
float gRootW;
float gFillMetal;

void calcSurfaceWeights(in vec3 pos, in float signM, in float md, in float bl, in float h, out float w[5]) {
  w[0] = 0.0; w[1] = 0.0; w[2] = 0.0; w[3] = 0.0; w[4] = 0.0;
  if (pos.y > 0.0) {
    float xn = (pos.x * signM) / max(md * 0.5, 0.001);
    float zn = pos.z / max(bl * 0.5, 0.001);
    float yn = pos.y / max(h, 0.001);
    w[1] = smoothstep(0.72, 0.82, yn) * (1.0 - smoothstep(0.55, 0.8, length(vec2(xn, zn))));
    w[0] = smoothstep(0.45, 0.6, xn) * smoothstep(0.25, 0.4, yn);
    w[2] = smoothstep(0.45, 0.6, -xn) * smoothstep(0.25, 0.4, yn);
    float bBase = smoothstep(0.2, 0.35, yn) * (1.0 - smoothstep(0.7, 0.85, yn));
    w[3] = smoothstep(0.45, 0.6, zn) * bBase;
    w[4] = smoothstep(0.45, 0.6, -zn) * bBase;
  }
}`)
      .replace('#include <color_fragment>', `
      float yN = vLocalPos.y / max(uCrownH, 0.001);
      gRootW = 1.0 - smoothstep(-1.0, 0.25, vLocalPos.y);
      // studio whitening: the default enamel reads pearl white; darker patient shades keep their difference
      float shLum = dot(uShade, vec3(0.2126, 0.7152, 0.0722));
      float shWhite = smoothstep(0.55, 0.72, shLum);
      vec3 studioShade = mix(uShade, min(mix(vec3(shLum), uShade, 0.4) * 1.12, vec3(0.97)), shWhite);
      vec3 base = mix(studioShade, uCementum, gRootW);
      float incisal = smoothstep(0.88, 1.0, yN) * uAnterior;
      base = mix(base, uIncisal, incisal * 0.45);
      base = mix(base, vec3(0.45, 0.30, 0.14), clamp(uStain, 0.0, 1.0) * 0.6);
      float calc = clamp(uCalculus, 0.0, 1.0) * (1.0 - smoothstep(0.0, 0.3, yN)) * step(-0.5, vLocalPos.y);
      base = mix(base, vec3(0.55, 0.47, 0.30), calc * 0.7);

      float sWeights[5];
      calcSurfaceWeights(vLocalPos, uMesialSign, uMd, uBl, uCrownH, sWeights);
      float cNoise = fract(sin(dot(floor(vLocalPos * 16.0), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
      for (int i = 0; i < 5; i++) {
        if (uSurfCaries[i] > 0.0) {
          float edgeF = smoothstep(0.08, 0.4, sWeights[i]) * (1.0 - smoothstep(0.65, 0.95, sWeights[i]));
          float cw = clamp(sWeights[i] * uSurfCaries[i] + (cNoise - 0.5) * 0.15 * edgeF, 0.0, 1.0);
          base = mix(base, vec3(0.16, 0.09, 0.05), cw);
        }
        if (uSurfFill[i].a > 0.0) {
          base = mix(base, uSurfFill[i].rgb, sWeights[i] * uSurfFill[i].a);
        }
      }

      gFillMetal = 0.0;
      for (int i = 0; i < 5; i++) {
        if (uSurfMetal[i] > 0.0) {
          gFillMetal = max(gFillMetal, sWeights[i] * uSurfMetal[i]);
        }
      }

      base = mix(base, uTint.rgb, uTint.a);
      #ifdef USE_COLOR
        base *= mix(0.86, 1.0, vColor.r);
      #endif
      diffuseColor.rgb = base;`)
      .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
      // soft warm lift in the shade (subsurface feel) and a rim for the selection wash
      totalEmissiveRadiance += diffuseColor.rgb * vec3(1.0, 0.82, 0.74) * 0.04;
      float tintRim = pow(1.0 - clamp(dot(normal, normalize(vViewPosition)), 0.0, 1.0), 2.4);
      totalEmissiveRadiance += uTint.rgb * uTint.a * (1.0 - step(0.99, uTint.a)) * tintRim * 1.1;`)
      .replace('#include <roughnessmap_fragment>', `#include <roughnessmap_fragment>
      roughnessFactor = mix(roughnessFactor, 0.62, gRootW);
      if (gFillMetal > 0.0) {
        roughnessFactor = mix(roughnessFactor, 0.45, gFillMetal);
      }`)
      .replace('#include <metalnessmap_fragment>', `#include <metalnessmap_fragment>
      if (gFillMetal > 0.0) {
        metalnessFactor = mix(metalnessFactor, 0.85, gFillMetal);
      }`);
  };
  mat.customProgramCacheKey = () => 'tooth-enamel-v4';
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

  if (t.surfCaries) {
    for (let i = 0; i < 5; i++) {
      u.uSurfCaries.value[i] = t.surfCaries[i] ?? 0;
    }
  }
  if (t.surfFill) {
    for (let i = 0; i < 5; i++) {
      const f = t.surfFill[i];
      if (f && f.a > 0) {
        u.uSurfFill.value[i].set(f.r, f.g, f.b, f.a);
        u.uSurfMetal.value[i] = f.metal || 0;
      } else {
        u.uSurfFill.value[i].set(0, 0, 0, 0);
        u.uSurfMetal.value[i] = 0;
      }
    }
  }
}

export function setTint(mat, hex, amount) {
  const t = mat.userData.u.uTint.value;
  if (!hex || amount <= 0) { t.w = 0; return; }
  const c = _c.set(hex);
  t.set(c.r, c.g, c.b, amount);
}
const _c = new THREE.Color();
export { NEUTRAL_LIGHT };
