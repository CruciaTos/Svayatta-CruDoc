import './ui/styles.css';
import manifest from '../scene_manifest.json';
import { createStore } from './state/store.js';
import { createOutline } from './engine/outline.js';
import { createStage } from './engine/stage.js';
import { setupLighting } from './engine/lighting.js';
import { createQuality, defaultQuality } from './engine/quality.js';
import { loadModel } from './engine/loader.js';
import { createRegistry } from './engine/registry.js';
import { createGums } from './engine/gums.js';
import { createAppearance } from './engine/modes.js';
import { createExplode } from './engine/explode.js';
import { applyShape } from './engine/shape.js';
import { createVisuals } from './treatments/visuals.js';
import { createPlayer } from './treatments/player.js';
import { createTimeline } from './ui/timeline.js';
import { createCameraRig } from './engine/camera.js';
import { createPicking } from './engine/picking.js';
import { createActions } from './engine/actions.js';
import { createBridge } from './bridge.js';
import { createToolbar } from './ui/toolbar.js';
import { createInspector } from './ui/inspector.js';
import { h } from './ui/dom.js';

const app = document.getElementById('app');
const urlParams = new URLSearchParams(window.location.search);
const isCompact = urlParams.get('compact') === '1';
if (isCompact) {
  document.documentElement.classList.add('compact');
  app.classList.add('compact');
}
if (new URLSearchParams(window.location.search).get('theme') === 'dark') document.documentElement.classList.add('dark');
const stageEl = h('div', { class: 'stage' });
const bar = h('i');
const msg = h('div', { class: 'msg' }, 'Loading 3D model');
const overlay = h('div', { class: 'overlay', role: 'status' }, h('div', { class: 'spinner' }), h('div', { class: 'bar' }, bar), msg);
stageEl.append(overlay);
app.append(stageEl);

function fail(err) {
  console.error(err);
  overlay.classList.add('error');
  overlay.classList.remove('gone');
  msg.textContent = `The 3D model could not be loaded. ${err && err.message ? err.message : ''}`.trim();
}

async function boot() {
  const store = createStore();
  store.set({ quality: defaultQuality() });
  const stage = createStage(stageEl);
  setupLighting(stage);
  const quality = createQuality(stage);

  const { root, placeholder } = await loadModel(manifest, (f) => { bar.style.width = `${Math.round(f * 100)}%`; });
  stage.scene.add(root);
  const registry = createRegistry(root, manifest);
  const missing = manifest.parts.filter((p) => p.source === 'glb' && !registry.map.has(p.nodeId)).map((p) => p.nodeId);
  if (missing.length) console.warn('Parts missing from the model:', missing.join(', '));

  const gums = createGums(registry, store, () => stage.invalidate());
  gums.rebuildAll();
  const appearance = createAppearance(registry, store, stage, gums);
  createOutline(stage, registry, store);
  const explode = createExplode(registry, store, stage);
  applyShape(registry, store, explode, gums);
  const visuals = createVisuals(registry, store, stage);
  visuals.rebuild();
  const cameraRig = createCameraRig(stage, registry, store);
  const actions = createActions({ store, registry, cameraRig });
  createPicking(stage, registry, { select: (id) => actions.select(id), hover: (id) => actions.hover(id), fly: (id) => actions.flyTo(id),
    // a tap (not a drag) on a tooth tells the host to open that tooth's form
    tap: (id) => {
      const part = id && registry.parts.get(id);
      if (part && part.fdi) window.App3DBridge?.emit('TOOTH_TAPPED', { fdi: part.fdi });
    } });

  const player = createPlayer({ store, actions, registry, stage, cameraRig, gums, explode, visuals, appearance });
  actions.playExplainer = (id) => player.play(id);
  actions.closeExplainer = () => player.close();

  const timeline = createTimeline({ store, actions, registry, stage, gums, explode, visuals, applyShape });
  timeline.sync(store.get());

  store.subscribe((s, changed, changedTeeth) => {
    if (changed.has('teeth') || changed.has('profile') || changed.has('treatments') || changed.has('preview') || (changed.has('currentVisit') && !timeline.isAnimating)) {
      applyShape(registry, store, explode, gums, changed.has('teeth') && !changed.has('profile') && !changed.has('treatments') && !changed.has('currentVisit') && !changed.has('preview') ? changedTeeth : null);
    }
    if (changed.has('treatments') || (changed.has('currentVisit') && !timeline.isAnimating) || changed.has('teeth') || changed.has('profile') || (changed.has('preview') && !s.preview?.quick)) {
      visuals.rebuild();
    }
    if (changed.has('quality')) quality.apply(s.quality);
    if (changed.has('visits') || changed.has('currentVisit')) {
      timeline.sync(s);
    }
    appearance.refresh();
    stage.invalidate();
  });

  const toolbar = createToolbar({ store, actions });
  const inspector = createInspector({ store, actions, registry, player });
  // Bottom stack (first child = lowest): toolbar, timeline, explainer.
  stageEl.append(h('div', { class: 'dock' }, toolbar.el, timeline.el, player.el));
  app.append(inspector.el);

  const { bridge, markReady } = createBridge({ store, actions, registry });
  window.__dental3d = {
    stats: () => stage.stats(),
    store, registry, stage, gums, explode, cameraRig, actions, quality, appearance,
    placeholder,
    visuals,
    timeline,
    player,
    snap: () => { explode.snap(); },
    flyDone: () => !cameraRig.flying,
  };

  quality.apply(store.get().quality);
  appearance.refresh();
  cameraRig.presetNow('front');
  stage.invalidate();
  await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
  overlay.classList.add('gone');
  markReady();
  void bridge;
}

boot().catch(fail);
