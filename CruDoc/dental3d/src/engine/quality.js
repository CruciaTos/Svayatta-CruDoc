import * as THREE from 'three';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { GTAOPass } from 'three/examples/jsm/postprocessing/GTAOPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js';
import { ShaderPass } from 'three/examples/jsm/postprocessing/ShaderPass.js';
import { SMAAPass } from 'three/examples/jsm/postprocessing/SMAAPass.js';

export const QUALITY_LEVELS = ['low', 'medium', 'high'];
const PRESETS = {
  low: { cap: 3, ao: false, bloom: false },
  medium: { cap: 3, ao: true, bloom: false },
  high: { cap: 3, ao: true, bloom: true },
};

export function defaultQuality() {
  const q = new URLSearchParams(location.search).get('q');
  if (QUALITY_LEVELS.includes(q)) return q;
  const touch = (navigator.maxTouchPoints || 0) > 0 || matchMedia('(pointer: coarse)').matches;
  return touch ? 'low' : 'medium';
}

// Caps are the device pixel ratio ceiling (phones are ~2.6-3, so 3 keeps them native-sharp).
// Low renders straight to the canvas (MSAA only). Medium/high go through an
// EffectComposer: scene -> ambient occlusion (half resolution) -> [bloom] ->
// tone map / sRGB -> SMAA. The bloom threshold sits above 1.0 (HDR), so only the
// emissive selection highlight and the strongest speculars glow.
export function createQuality(stage) {
  const { renderer, scene, camera } = stage;
  let composer = null;
  let gtao = null;
  let bloom = null;
  let current = null;

  function disposeComposer() {
    if (!composer) return;
    composer.passes.forEach((p) => p.dispose?.());
    composer.dispose?.();
    composer = null; gtao = null; bloom = null;
  }

  function build(preset) {
    const { w, h } = stage.size;
    const pr = renderer.getPixelRatio();
    composer = new EffectComposer(renderer);
    composer.setPixelRatio(pr);
    composer.setSize(w, h);
    // The composer path keeps the background transparent (the page colour shows
    // through) so the tone mapper in OutputPass cannot grey out the background.
    const rp = new RenderPass(scene, camera);
    rp.clearColor = new THREE.Color(0x000000);
    rp.clearAlpha = 0;
    composer.addPass(rp);
    if (preset.ao) {
      gtao = new GTAOPass(scene, camera, Math.round((w * pr) / 2), Math.round((h * pr) / 2));
      gtao.output = GTAOPass.OUTPUT.Default;
      gtao.updateGtaoMaterial({ radius: 3.2, distanceExponent: 1.4, thickness: 2, scale: 1.1, samples: 8, distanceFallOff: 1, screenSpaceRadius: false });
      gtao.updatePdMaterial({ lumaPhi: 10, depthPhi: 2, normalPhi: 3, radius: 5, radiusExponent: 1, rings: 2, samples: 12 });
      gtao.blendIntensity = 0.9;
      composer.addPass(gtao);
      // keep the AO buffers at half resolution when the composer resizes
      const origSize = gtao.setSize.bind(gtao);
      gtao.setSize = (cw, ch) => origSize(Math.max(1, Math.round(cw / 2)), Math.max(1, Math.round(ch / 2)));
      gtao.setSize(w * pr, h * pr);
    }
    if (preset.bloom) {
      bloom = new UnrealBloomPass(new THREE.Vector2(w, h), 0.45, 0.55, 1.7);
      composer.addPass(bloom);
    }
    // Soft-edged (alpha) surfaces leave premultiplied colour in the transparent target: undo it
    // for tone mapping / sRGB, then redo it so the page colour shows through without a bright halo.
    const alphaPass = (mul) => new ShaderPass({
      uniforms: { tDiffuse: { value: null } },
      vertexShader: 'varying vec2 vUv; void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
      fragmentShader: `uniform sampler2D tDiffuse; varying vec2 vUv;
        void main() { vec4 c = texture2D(tDiffuse, vUv);
          ${mul ? 'c.rgb *= c.a;' : 'c.rgb = c.a > 0.002 ? c.rgb / c.a : vec3(0.0);'}
          gl_FragColor = c; }`,
    });
    composer.addPass(alphaPass(false));
    composer.addPass(new OutputPass());
    composer.addPass(alphaPass(true));
    composer.addPass(new SMAAPass());
  }

  function render() {
    if (!composer) { renderer.render(scene, camera); return; }
    // (background handled in apply(): scene.background is null while composing)
    // AO would treat ghosted (transparent) parts as solid, so skip it then.
    if (gtao) gtao.enabled = !stage.flags.ghost;
    composer.render();
  }

  function apply(name) {
    if (!PRESETS[name]) name = 'medium';
    if (name === current) return name;
    current = name;
    const preset = PRESETS[name];
    stage.pixelRatioCap = preset.cap;
    disposeComposer();
    stage.resize(); // sets the pixel ratio + size first
    const composed = preset.ao || preset.bloom;
    scene.background = null;
    renderer.setClearColor(0x000000, 0);
    if (composed) build(preset);
    stage.setRenderFn(render);
    return name;
  }

  stage.onResize.add((w, h, pr) => {
    if (!composer) return;
    composer.setPixelRatio(pr);
    composer.setSize(w, h);
  });

  return { apply, get current() { return current; }, hasBloom: () => !!bloom };
}
