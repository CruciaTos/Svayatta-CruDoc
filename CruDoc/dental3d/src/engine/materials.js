import * as THREE from 'three';

// Shared Fresnel ghost used for x-ray (and for hidden-but-present layers in the
// status view): pale blue, rim lit, depthWrite off.
export function createGhostMaterial() {
  return new THREE.ShaderMaterial({
    transparent: true,
    depthWrite: false,
    side: THREE.FrontSide,
    uniforms: {
      uOpacity: { value: 0.14 },
      uCore: { value: new THREE.Color('#BCD4F2') },
      uRim: { value: new THREE.Color('#5AA0F5') },
    },
    vertexShader: `
      varying vec3 vN; varying vec3 vV;
      void main() {
        vec4 mv = modelViewMatrix * vec4(position, 1.0);
        vN = normalize(normalMatrix * normal);
        vV = normalize(-mv.xyz);
        gl_Position = projectionMatrix * mv;
      }`,
    fragmentShader: `
      uniform float uOpacity; uniform vec3 uCore; uniform vec3 uRim;
      varying vec3 vN; varying vec3 vV;
      void main() {
        float f = pow(1.0 - clamp(abs(dot(normalize(vN), normalize(vV))), 0.0, 1.0), 2.2);
        vec3 col = mix(uCore, uRim, f);
        gl_FragColor = vec4(col, clamp(uOpacity * (0.55 + 3.2 * f), 0.0, 0.9));
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }`,
  });
}

export function createPulpMaterial() {
  return new THREE.MeshStandardMaterial({ color: '#D9534F', roughness: 0.5, metalness: 0, emissive: '#5A1010', emissiveIntensity: 0.35 });
}

// Solid gum: soft wet tissue. Vertex alpha dissolves the far edge (transparent, depth-written, so no sorting artefacts).
export function createGumMaterial() {
  const m = new THREE.MeshPhysicalMaterial({
    color: '#FFFFFF', vertexColors: true, roughness: 0.38, metalness: 0,
    clearcoat: 0.35, clearcoatRoughness: 0.25, sheen: 0.4, sheenRoughness: 0.5, sheenColor: new THREE.Color('#FFC4C4'),
    transparent: true, depthWrite: true, side: THREE.FrontSide,
  });
  // the dissolving far edge faces away from the camera: kill its grazing-angle reflections so it fades to nothing, not to white
  m.onBeforeCompile = (shader) => {
    shader.fragmentShader = shader.fragmentShader.replace('#include <lights_physical_fragment>', `#include <lights_physical_fragment>
      #ifdef USE_COLOR_ALPHA
        float fadeK = smoothstep(0.7, 1.0, vColor.a);
        material.clearcoat *= fadeK; material.specularF90 *= fadeK; material.sheenColor *= fadeK; material.specularColor *= fadeK;
      #endif`);
  };
  m.customProgramCacheKey = () => 'gum-fade-v1';
  return m;
}

export function createBoneMaterial() {
  return new THREE.MeshStandardMaterial({ color: '#E9E0C9', roughness: 0.8, metalness: 0, vertexColors: true, transparent: true, side: THREE.FrontSide });
}

// Glass shell for gum / bone: pale, Fresnel-lit, rim brighter, far edge dissolved by vertex alpha.
export function createGlassMaterial(kind) {
  const gum = kind === 'gum';
  return new THREE.ShaderMaterial({
    transparent: true,
    depthWrite: false,
    side: THREE.FrontSide,
    uniforms: {
      uOpacity: { value: gum ? 0.26 : 0.18 },
      uCore: { value: new THREE.Color(gum ? '#EFD3D6' : '#E4E9F0') },
      uRim: { value: new THREE.Color(gum ? '#FFFDFC' : '#FFFFFF') },
      uSel: { value: 0 },
    },
    vertexShader: `
      attribute vec4 color;
      varying vec3 vN; varying vec3 vV; varying float vFade;
      void main() {
        vec4 mv = modelViewMatrix * vec4(position, 1.0);
        vN = normalize(normalMatrix * normal);
        vV = normalize(-mv.xyz);
        vFade = color.a;
        gl_Position = projectionMatrix * mv;
      }`,
    fragmentShader: `
      uniform float uOpacity; uniform vec3 uCore; uniform vec3 uRim; uniform float uSel;
      varying vec3 vN; varying vec3 vV; varying float vFade;
      void main() {
        vec3 N = normalize(vN); vec3 V = normalize(vV);
        float ndv = clamp(abs(dot(N, V)), 0.0, 1.0);
        float f = pow(1.0 - ndv, 2.0);
        vec3 H = normalize(normalize(vec3(0.35, 0.6, 0.7)) + V);
        float spec = pow(max(dot(N * sign(dot(N, V)), H), 0.0), 36.0);
        vec3 col = mix(uCore, uRim, f) + vec3(spec * 0.3);
        col = mix(col, vec3(0.23, 0.51, 0.96), uSel * 0.45);
        float a = clamp(uOpacity * (0.75 + 1.5 * f) + spec * 0.16 + uSel * 0.22, 0.0, 0.55) * vFade;
        gl_FragColor = vec4(col, a);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }`,
  });
}
