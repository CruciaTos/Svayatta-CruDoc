import * as THREE from 'three';

const ACCENT = '#3B82F6';
const RADIUS_PX = 1.75; // outline thickness in CSS pixels
const SCALE = 2; // mask resolution: 2 target pixels per CSS pixel (smooth on phones, fixed cost)

// Screen-space outline of the selected tooth's VISIBLE silhouette. Two cheap mask passes into a
// CSS-pixel-sized target (everything else drawn black for depth, then the tooth alone in white,
// depth-tested), then one full-screen pass that draws dilate(mask) minus mask. Runs only while a
// tooth is selected. Glass gums, bone, pulps and the shadow plane are left out of the mask pass,
// so they never hide the tooth.
export function createOutline(stage, registry, store) {
  const { renderer, scene, camera } = stage;
  const rt = new THREE.WebGLRenderTarget(1, 1, { depthBuffer: true, samples: 4, minFilter: THREE.LinearFilter, magFilter: THREE.LinearFilter });
  const black = new THREE.MeshBasicMaterial({ color: 0x000000 });
  const white = new THREE.MeshBasicMaterial({ color: 0xffffff });
  const quadCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const mat = new THREE.ShaderMaterial({
    transparent: true, depthTest: false, depthWrite: false,
    uniforms: { tMask: { value: rt.texture }, uTexel: { value: new THREE.Vector2(1, 1) }, uColor: { value: new THREE.Color(ACCENT) }, uR: { value: RADIUS_PX * SCALE + 0.5 } },
    vertexShader: 'varying vec2 vUv; void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }',
    fragmentShader: `uniform sampler2D tMask; uniform vec2 uTexel; uniform vec3 uColor; uniform float uR; varying vec2 vUv;
      void main() {
        float c = texture2D(tMask, vUv).r;
        // average mask coverage over a disk (two rings): a smooth distance-like field
        float acc = 0.0;
        for (int i = 0; i < 16; i++) {
          float a = float(i) * 0.39269908;
          vec2 d = vec2(cos(a), sin(a)) * uTexel;
          acc += texture2D(tMask, vUv + d * uR).r;
          if (i < 8) acc += texture2D(tMask, vUv + d * 2.0 * uR * 0.5).r * 2.0;
        }
        float cov = acc / 32.0;
        float al = smoothstep(0.02, 0.22, cov) * (1.0 - smoothstep(0.0, 1.0, c));
        if (al < 0.004) discard;
        gl_FragColor = vec4(uColor, al);
        #include <colorspace_fragment>
      }`,
  });
  const quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), mat);
  quad.frustumCulled = false;
  const quadScene = new THREE.Scene();
  quadScene.add(quad);

  stage.onResize.add((w, h) => {
    const rw = Math.round(w * SCALE), rh = Math.round(h * SCALE);
    rt.setSize(rw, rh); mat.uniforms.uTexel.value.set(1 / rw, 1 / rh);
  });

  
  function toothMeshes(obj) {
    const out = [];
    const walk = (o) => {
      if (o.isMesh) out.push(o);
      for (const c of o.children) if (!(c.userData.part && c !== obj)) walk(c);
    };
    walk(obj);
    return out;
  }

  function draw() {
    const id = store.get().selectedId;
    const obj = id && registry.teeth && registry.get(id);
    if (!obj || obj.userData.part?.kind !== 'tooth' || !obj.visible) return;
    const xray = store.get().mode === 'xray';
    const ghostMat = stage.ghostMaterial;
    const sel = toothMeshes(obj);
    const selSet = new Set(sel);
    const vis = [];
    scene.traverse((o) => { if (o.isMesh && o.visible) vis.push(o); });
    const hidden = [];
    const hide = (o) => { o.visible = false; hidden.push(o); };
    const prevTarget = renderer.getRenderTarget();
    const prevAuto = renderer.autoClear;
    const prevClear = renderer.getClearColor(new THREE.Color());
    const prevAlpha = renderer.getClearAlpha();
    const prevBg = scene.background;
    try {
      scene.background = null;
      renderer.autoClear = false;
      renderer.setClearColor(0x000000, 0);
      renderer.setRenderTarget(rt);
      renderer.clear(true, true, true);
      // A: everything that can occlude, as black depth (not glass gums / bone / pulps / the selected tooth)
      for (const o of vis) {
        const kind = o.userData.kind || o.userData.part?.kind;
        // gums and bone (glass or solid) occlude, so only the crown above the gum line is outlined;
        // in x-ray they are ghosted, so they stay out
        const ghosted = xray && (kind === 'gum' || kind === 'bone');
        const ownerKind = o.userData.ownerId && registry.parts.get(o.userData.ownerId)?.kind;
        if (selSet.has(o) || ghosted || ownerKind === 'pulp' || o.name === 'contact_shadow' || !o.material || (o.material.isShaderMaterial && o.material === ghostMat)) hide(o);
      }
      scene.overrideMaterial = black;
      renderer.render(scene, camera);
      for (const o of hidden) o.visible = true;
      hidden.length = 0;
      // B: the tooth alone in white, depth-tested against A
      for (const o of vis) if (!selSet.has(o)) hide(o);
      scene.overrideMaterial = white;
      renderer.render(scene, camera);
    } finally {
      scene.overrideMaterial = null;
      for (const o of vis) o.visible = true;
      // restore anything hidden for other reasons (vis only held visible meshes, so this is exact)
      scene.background = prevBg;
      renderer.setRenderTarget(prevTarget);
      renderer.setClearColor(prevClear, prevAlpha);
    }
    renderer.setRenderTarget(null);
    renderer.render(quadScene, quadCam);
    renderer.autoClear = prevAuto;
  }

  stage.afterRender.add(draw);
  return { draw };
}
