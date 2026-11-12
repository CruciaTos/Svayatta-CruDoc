import { h, icon } from '../ui/dom.js';
import { TREATMENTS } from '../data/treatments.js';
import { createAnimationRunner } from './animations.js';

export function createPlayer({ store, actions, registry, stage, cameraRig, gums, explode, visuals, appearance }) {
  const el = h('div', { class: 'explainer-card', role: 'region', 'aria-label': 'Treatment explainer' });
  el.hidden = true;

  const runner = createAnimationRunner({ stage, registry, store, gums, cameraRig, appearance, visuals });

  let curTreatment = null;
  let curDef = null;
  let curSteps = [];
  let curStepIdx = 0;
  let baselineMode = null;
  let baselineLayers = null;
  let baselineCamPos = null;
  let baselineControlsTarget = null;
  let playing = false;

  // UI elements
  const badge = h('span', { class: 'explainer-badge mono' });
  const title = h('h4', { class: 'explainer-title' });
  const closeBtn = h('button', {
    type: 'button',
    class: 'explainer-close',
    'aria-label': 'Close explainer',
    onclick: () => close(),
  }, icon('close', 16));

  const hdr = h('div', { class: 'explainer-hdr' },
    h('div', { class: 'explainer-hdr-left' }, badge, title),
    closeBtn
  );

  const text = h('p', { class: 'explainer-text' });

  const dots = h('div', { class: 'explainer-dots' });
  const prevBtn = h('button', {
    type: 'button',
    class: 'pill-btn explainer-btn',
    onclick: () => prev(),
  }, 'Back');

  const nextBtn = h('button', {
    type: 'button',
    class: 'pill-btn on explainer-btn',
    onclick: () => next(),
  }, 'Next');

  const nav = h('div', { class: 'explainer-nav' },
    dots,
    h('div', { class: 'explainer-btns' }, prevBtn, nextBtn)
  );

  el.append(hdr, text, nav);

  function syncUI() {
    if (!curTreatment || !curSteps.length) return;
    const step = curSteps[curStepIdx];
    const total = curSteps.length;

    badge.textContent = `Step ${curStepIdx + 1} of ${total}`;
    title.textContent = step.title;
    text.textContent = step.text;

    if (dots.children.length !== total) {
      dots.replaceChildren();
      for (let i = 0; i < total; i++) {
        dots.append(h('span', { class: 'explainer-dot' }));
      }
    }
    for (let i = 0; i < total; i++) {
      dots.children[i]?.classList.toggle('on', i === curStepIdx);
    }

    prevBtn.disabled = curStepIdx === 0;
    nextBtn.textContent = curStepIdx === total - 1 ? 'Done' : 'Next';
  }

  // Visuals that show the finished work: from the first of these onward the treatment counts as done.
  const RESULT = {
    seat_crown: {}, seat_veneer: {}, seat_bridge: {}, place_fixture: {}, osseointegrate: {}, place_abutment: {},
    heal_socket: {}, gum_heal: {},
    place_braces: { progress: 0, brackets: true },
    align_teeth: { progress: 0, brackets: true },
    remove_braces: { progress: 1, brackets: false },
  };
  // Where the last result step up to `idx` leaves the treatment (align_teeth ends at full progress).
  function previewFor(idx) {
    let spec = null;
    for (let i = 0; i <= idx; i++) {
      const r = RESULT[curSteps[i].visual];
      if (r) spec = i < idx && curSteps[i].visual === 'align_teeth' ? { ...r, progress: 1 } : { ...r };
    }
    return { id: curTreatment.id, on: !!spec, ...(spec || {}) };
  }
  const targetOf = () => curTreatment.teeth?.[0] || (curTreatment.arches?.includes('lower') ? 31 : 11);

  // Back to the patient's state, then earlier steps jump to their end and this one animates.
  function runStep(idx) {
    if (idx < 0 || idx >= curSteps.length) return;
    curStepIdx = idx;
    syncUI();
    runner.reset();
    store.set({ preview: previewFor(idx) });
    const base = { treatment: curTreatment, targetFdi: targetOf() };
    for (let i = 0; i < idx; i++) runner.runVisual({ ...base, visual: curSteps[i].visual, instant: true });
    runner.runVisual({ ...base, visual: curSteps[idx].visual });
    stage.invalidate();
  }

  function onKey(e) {
    if (!playing) return;
    if (e.key === 'Escape') close();
    else if (e.key === 'ArrowRight') next();
    else if (e.key === 'ArrowLeft') prev();
    else return;
    e.preventDefault();
  }

  function play(treatmentId) {
    const s = store.get();
    const tr = (s.treatments || []).find((t) => t.id === treatmentId);
    if (!tr) return false;
    const tDef = TREATMENTS.find((t) => t.id === tr.type);
    if (!tDef || !tDef.steps || !tDef.steps.length) return false;

    if (playing) {
      runner.reset();
    } else {
      baselineMode = s.mode;
      baselineLayers = { ...s.layers };
      baselineCamPos = stage.camera.position.clone();
      baselineControlsTarget = stage.controls.target.clone();
      window.addEventListener('keydown', onKey);
    }
    runner.setBaselineMode(baselineMode);

    curTreatment = tr;
    curDef = tDef;
    curSteps = tDef.steps;
    curStepIdx = 0;
    playing = true;
    if (tr.type === 'boneGraft') store.set({ layers: { bone: true } });

    // Phones: the bottom sheet would sit on top of the card, so fold it away.
    document.getElementById('app')?.classList.remove('sheet-open');
    document.querySelector('.sheet-handle')?.setAttribute('aria-expanded', 'false');

    const fdi = targetOf();
    const nodeId = tr.teeth?.length ? `tooth_${fdi}` : null;
    if (nodeId && cameraRig) cameraRig.flyTo(nodeId, 500);
    else cameraRig?.preset('front', 500);

    el.hidden = false;
    runStep(0);
    return true;
  }

  function next() {
    if (!playing) return;
    if (curStepIdx < curSteps.length - 1) runStep(curStepIdx + 1);
    else close();
  }

  function prev() {
    if (!playing || curStepIdx <= 0) return;
    runStep(curStepIdx - 1);
  }

  function close() {
    if (!playing) return;
    playing = false;
    window.removeEventListener('keydown', onKey);
    runner.reset();
    store.set({ preview: null, mode: baselineMode, layers: baselineLayers });
    if (baselineCamPos && baselineControlsTarget) {
      cameraRig?.cancelFlight?.();
      stage.controls.target.copy(baselineControlsTarget);
      stage.camera.position.copy(baselineCamPos);
      stage.camera.lookAt(baselineControlsTarget);
      stage.controls.update();
    }
    appearance.refresh();
    visuals.rebuild();
    stage.invalidate();

    curTreatment = null;
    curDef = null;
    curSteps = [];
    curStepIdx = 0;
    el.hidden = true;
  }

  // The treatment was removed while its steps were showing.
  store.subscribe((s, changed) => {
    if (playing && changed.has('treatments') && !(s.treatments || []).some((t) => t.id === curTreatment?.id)) close();
  });

  return {
    el,
    play,
    next,
    prev,
    close,
    get isPlaying() { return playing; },
    get currentStep() { return curStepIdx; },
    get currentTreatment() { return curTreatment; },
  };
}
