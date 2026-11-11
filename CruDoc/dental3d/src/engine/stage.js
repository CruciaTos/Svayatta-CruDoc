import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';

export const BG = '#F4F5F7';

// Renderer, scene, camera, controls and an on-demand render loop. Anything that
// animates registers a ticker; the loop only keeps running while a ticker (or
// the damped controls) reports that it is still moving.
export function createStage(container) {
  const canvas = document.createElement('canvas');
  canvas.className = 'stage-canvas';
  container.appendChild(canvas);

  const renderer = new THREE.WebGLRenderer({
    canvas, antialias: true, alpha: true, premultipliedAlpha: true, powerPreference: 'high-performance',
  });
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.AgXToneMapping ?? THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.0;
  renderer.setClearColor(BG, 1);

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(BG);

  const camera = new THREE.PerspectiveCamera(30, 1, 1, 2000);
  camera.position.set(0, 6, 190);
  scene.add(camera);

  const controls = new OrbitControls(camera, canvas);
  controls.enableDamping = true;
  controls.dampingFactor = 0.09;
  controls.screenSpacePanning = true;
  controls.minDistance = 18;
  controls.maxDistance = 420;
  controls.rotateSpeed = 0.8;
  controls.zoomSpeed = 0.9;
  controls.panSpeed = 0.9;
  controls.target.set(0, 0, -4);
  controls.update();

  const tickers = new Set();
  const frameTimes = []; // interval between rendered frames (ms)
  const cpuTimes = [];   // time spent inside render() (ms)
  let raf = 0;
  let last = 0;
  let renderFn = () => renderer.render(scene, camera);
  let renderedFrames = 0;

  const stage = {
    canvas, renderer, scene, camera, controls, container,
    flags: { ghost: false },
    setRenderFn(fn) { renderFn = fn; invalidate(); },
    addTicker(fn) { tickers.add(fn); return () => tickers.delete(fn); },
    onResize: new Set(),
    beforeRender: new Set(),
    pixelRatioCap: 1.5,
    size: { w: 1, h: 1 },
  };

  function invalidate() {
    if (!raf) raf = requestAnimationFrame(frame);
  }

  function frame(now) {
    raf = 0;
    const dt = last ? Math.min(0.1, (now - last) / 1000) : 1 / 60;
    if (last) { frameTimes.push(now - last); if (frameTimes.length > 240) frameTimes.shift(); }
    last = now;
    let busy = false;
    for (const t of tickers) if (t(dt)) busy = true;
    if (controls.update(dt)) busy = true;
    for (const fn of stage.beforeRender) fn();
    const t0 = performance.now();
    renderFn();
    cpuTimes.push(performance.now() - t0);
    if (cpuTimes.length > 240) cpuTimes.shift();
    renderedFrames++;
    if (busy) invalidate(); else last = 0;
  }

  controls.addEventListener('change', invalidate);

  function resize() {
    const w = Math.max(1, container.clientWidth);
    const h = Math.max(1, container.clientHeight);
    const pr = Math.min(window.devicePixelRatio || 1, stage.pixelRatioCap);
    renderer.setPixelRatio(pr);
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    stage.size = { w, h };
    for (const fn of stage.onResize) fn(w, h, pr);
    invalidate();
  }
  new ResizeObserver(resize).observe(container);
  stage.resize = resize;
  stage.invalidate = invalidate;

  const pct = (arr, p) => {
    if (!arr.length) return 0;
    const s = [...arr].sort((a, b) => a - b);
    return s[Math.min(s.length - 1, Math.floor(p * s.length))];
  };
  const avg = (arr) => (arr.length ? arr.reduce((a, b) => a + b, 0) / arr.length : 0);

  stage.stats = () => {
    const gl = renderer.getContext();
    const ext = gl.getExtension('WEBGL_debug_renderer_info');
    const gpu = ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : 'unknown';
    return {
      renderedFrames,
      sampleSize: frameTimes.length,
      frameIntervalAvgMs: +avg(frameTimes).toFixed(2),
      frameIntervalP95Ms: +pct(frameTimes, 0.95).toFixed(2),
      cpuRenderAvgMs: +avg(cpuTimes).toFixed(2),
      cpuRenderMaxMs: +Math.max(0, ...cpuTimes).toFixed(2),
      recentFrameMs: frameTimes.slice(-30).map((v) => +v.toFixed(1)),
      gpu,
      softwareRendered: /swiftshader|llvmpipe|software|basic render/i.test(gpu),
      calls: renderer.info.render.calls,
      triangles: renderer.info.render.triangles,
      pixelRatio: renderer.getPixelRatio(),
    };
  };
  return stage;
}
