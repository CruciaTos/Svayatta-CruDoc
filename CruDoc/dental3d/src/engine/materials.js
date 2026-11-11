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

export function createGumMaterial() {
  return new THREE.MeshPhysicalMaterial({
    color: '#FFFFFF', vertexColors: true, roughness: 0.45, metalness: 0,
    clearcoat: 0.3, clearcoatRoughness: 0.35, sheen: 0.5, sheenRoughness: 0.5, sheenColor: new THREE.Color('#FFB3B8'),
    side: THREE.DoubleSide,
  });
}

export function createBoneMaterial() {
  return new THREE.MeshStandardMaterial({ color: '#E9E0C9', roughness: 0.8, metalness: 0, vertexColors: true, side: THREE.DoubleSide });
}
