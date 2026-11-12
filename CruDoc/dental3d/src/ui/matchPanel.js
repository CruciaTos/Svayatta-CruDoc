import { h, icon } from './dom.js';
import { SHADES } from '../data/treatments.js';
import { defaultToothState } from '../state/schema.js';

export function createMatchPanel({ store, actions, registry }) {
  let curFdi = null;
  let isOpen = false;

  const toggleBtn = h('button', {
    type: 'button',
    class: 'match-toggle-btn',
    onclick: () => {
      isOpen = !isOpen;
      body.classList.toggle('open', isOpen);
      toggleBtn.classList.toggle('open', isOpen);
    },
  }, h('span', { class: 'match-toggle-text' }, 'Match this tooth'), icon('chevron', 16));

  // Present / Missing switch
  const btnPresent = h('button', {
    type: 'button',
    class: 'pill-btn on',
    onclick: () => { if (curFdi) actions.applyStateSnapshot({ teeth: { [curFdi]: { present: true } } }); },
  }, 'Present');
  const btnMissing = h('button', {
    type: 'button',
    class: 'pill-btn',
    onclick: () => { if (curFdi) actions.applyStateSnapshot({ teeth: { [curFdi]: { present: false } } }); },
  }, 'Missing');
  const presentSwitch = h('div', { class: 'match-switch-row' },
    h('span', { class: 'match-lbl' }, 'Tooth presence'),
    h('div', { class: 'seg match-seg' }, btnPresent, btnMissing)
  );

  // Helper for sliders
  const sliders = {};
  function makeSlider(key, label, min, max, step, getVal, updateVal) {
    const valText = h('span', { class: 'sl-val mono' });
    const input = h('input', {
      type: 'range',
      min, max, step,
      'aria-label': label,
      class: 'match-range',
    });
    input.addEventListener('input', () => {
      const v = parseFloat(input.value);
      valText.textContent = v.toFixed(step < 0.1 ? 2 : step < 1 ? 1 : 0);
      if (curFdi) {
        updateVal(v);
      }
    });
    const row = h('div', { class: 'match-sl' },
      h('div', { class: 'match-sl-hdr' }, h('span', { class: 'match-lbl' }, label), valText),
      input
    );
    sliders[key] = {
      set(val) {
        if (document.activeElement !== input) {
          input.value = val;
          valText.textContent = Number(val || 0).toFixed(step < 0.1 ? 2 : step < 1 ? 1 : 0);
        }
      },
    };
    return row;
  }

  // Sliders for position, rotation, scale
  const slMoveSideways = makeSlider('shift.md', 'Move sideways', -4, 4, 0.1, (t) => t.shift?.md ?? 0, (v) => {
    actions.applyStateSnapshot({ teeth: { [curFdi]: { shift: { md: v } } } });
  });
  const slMoveInOut = makeSlider('shift.bl', 'Move in/out', -4, 4, 0.1, (t) => t.shift?.bl ?? 0, (v) => {
    actions.applyStateSnapshot({ teeth: { [curFdi]: { shift: { bl: v } } } });
  });
  const slMoveUpDown = makeSlider('shift.v', 'Move up/down', -4, 4, 0.1, (t) => t.shift?.v ?? 0, (v) => {
    actions.applyStateSnapshot({ teeth: { [curFdi]: { shift: { v: v } } } });
  });
  const slTiltSideways = makeSlider('rotate.tip', 'Tilt sideways', -30, 30, 1, (t) => t.rotate?.tip ?? 0, (v) => {
    actions.applyStateSnapshot({ teeth: { [curFdi]: { rotate: { tip: v } } } });
  });
  const slTiltInOut = makeSlider('rotate.torque', 'Tilt in/out', -30, 30, 1, (t) => t.rotate?.torque ?? 0, (v) => {
    actions.applyStateSnapshot({ teeth: { [curFdi]: { rotate: { torque: v } } } });
  });
  const slTurn = makeSlider('rotate.spin', 'Turn', -45, 45, 1, (t) => t.rotate?.spin ?? 0, (v) => {
    actions.applyStateSnapshot({ teeth: { [curFdi]: { rotate: { spin: v } } } });
  });
  const slWidth = makeSlider('scale.w', 'Width', 0.8, 1.2, 0.02, (t) => t.scale?.w ?? 1, (v) => {
    actions.applyStateSnapshot({ teeth: { [curFdi]: { scale: { w: v } } } });
  });
  const slLength = makeSlider('scale.h', 'Length', 0.8, 1.2, 0.02, (t) => t.scale?.h ?? 1, (v) => {
    actions.applyStateSnapshot({ teeth: { [curFdi]: { scale: { h: v } } } });
  });

  // Shade chips
  const shadeChips = [];
  const shadeRow = h('div', { class: 'match-shade-grid' });
  for (const [key, hex] of Object.entries(SHADES)) {
    const dot = h('span', { class: 'shade-dot', style: `background:${hex}` });
    const chip = h('button', {
      type: 'button',
      class: 'shade-chip',
      'data-shade': key,
      title: key,
      onclick: () => {
        if (!curFdi) return;
        const currentShade = store.get().teeth[curFdi]?.shade;
        actions.applyStateSnapshot({ teeth: { [curFdi]: { shade: currentShade === key ? null : key } } });
      },
    }, dot, h('span', { class: 'shade-lbl' }, key));
    shadeChips.push({ chip, key });
    shadeRow.append(chip);
  }

  // Condition sliders
  const slStain = makeSlider('stain', 'Stain', 0, 1, 0.05, (t) => t.stain ?? 0, (v) => {
    actions.applyStateSnapshot({ teeth: { [curFdi]: { stain: v } } });
  });
  const slWear = makeSlider('wear', 'Worn', 0, 3, 0.1, (t) => t.wear ?? 0, (v) => {
    actions.applyStateSnapshot({ teeth: { [curFdi]: { wear: v } } });
  });
  const slChip = makeSlider('chip', 'Chipped', 0, 1, 0.05, (t) => t.chip ?? 0, (v) => {
    actions.applyStateSnapshot({ teeth: { [curFdi]: { chip: v } } });
  });
  const slRecession = makeSlider('recession', 'Gum recession', 0, 6, 0.2, (t) => t.recession ?? 0, (v) => {
    actions.applyStateSnapshot({ teeth: { [curFdi]: { recession: v } } });
  });
  const slInflammation = makeSlider('inflammation', 'Gum swelling', 0, 1, 0.05, (t) => t.inflammation ?? 0, (v) => {
    actions.applyStateSnapshot({ teeth: { [curFdi]: { inflammation: v } } });
  });
  const slCalculus = makeSlider('calculus', 'Tartar', 0, 1, 0.05, (t) => t.calculus ?? 0, (v) => {
    actions.applyStateSnapshot({ teeth: { [curFdi]: { calculus: v } } });
  });
  const slBoneLoss = makeSlider('boneLoss', 'Bone loss', 0, 6, 0.2, (t) => t.boneLoss ?? 0, (v) => {
    actions.applyStateSnapshot({ teeth: { [curFdi]: { boneLoss: v } } });
  });

  // Reset tooth button
  const resetBtn = h('button', {
    type: 'button',
    class: 'pill-btn wide match-reset-btn',
    onclick: () => {
      if (!curFdi) return;
      actions.applyStateSnapshot({ teeth: { [curFdi]: defaultToothState() } });
    },
  }, 'Reset tooth');

  const body = h('div', { class: 'match-panel-body' },
    presentSwitch,
    h('div', { class: 'match-section-title' }, 'Position & Alignment'),
    slMoveSideways, slMoveInOut, slMoveUpDown,
    slTiltSideways, slTiltInOut, slTurn,
    slWidth, slLength,
    h('div', { class: 'match-section-title' }, 'Shade'),
    shadeRow,
    h('div', { class: 'match-section-title' }, 'Wear & Gum Health'),
    slStain, slWear, slChip,
    slRecession, slInflammation, slCalculus, slBoneLoss,
    resetBtn
  );

  const el = h('div', { class: 'match-panel' }, toggleBtn, body);
  el.hidden = true;

  function sync(s) {
    const id = s.selectedId;
    const part = id ? registry.parts.get(id) : null;
    if (!part || part.kind !== 'tooth' || !part.fdi) {
      el.hidden = true;
      curFdi = null;
      return;
    }
    const fdiChanged = curFdi !== part.fdi;
    curFdi = part.fdi;
    el.hidden = false;
    if (fdiChanged) {
      isOpen = false;
      body.classList.remove('open');
      toggleBtn.classList.remove('open');
    }

    const t = s.teeth[curFdi] || defaultToothState();
    btnPresent.classList.toggle('on', t.present !== false);
    btnMissing.classList.toggle('on', t.present === false);

    sliders['shift.md'].set(t.shift?.md ?? 0);
    sliders['shift.bl'].set(t.shift?.bl ?? 0);
    sliders['shift.v'].set(t.shift?.v ?? 0);
    sliders['rotate.tip'].set(t.rotate?.tip ?? 0);
    sliders['rotate.torque'].set(t.rotate?.torque ?? 0);
    sliders['rotate.spin'].set(t.rotate?.spin ?? 0);
    sliders['scale.w'].set(t.scale?.w ?? 1);
    sliders['scale.h'].set(t.scale?.h ?? 1);

    for (const item of shadeChips) {
      item.chip.classList.toggle('on', t.shade === item.key);
    }

    sliders['stain'].set(t.stain ?? 0);
    sliders['wear'].set(t.wear ?? 0);
    sliders['chip'].set(t.chip ?? 0);
    sliders['recession'].set(t.recession ?? 0);
    sliders['inflammation'].set(t.inflammation ?? 0);
    sliders['calculus'].set(t.calculus ?? 0);
    sliders['boneLoss'].set(t.boneLoss ?? 0);
  }

  return { el, sync };
}

