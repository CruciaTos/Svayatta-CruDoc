import * as THREE from 'three';
import { SHADES } from '../data/treatments.js';
import { effectiveTooth } from '../treatments/effective.js';

export function createTimeline({ store, actions, registry, stage, gums, explode, visuals, applyShape }) {
  const el = h('div', { class: 'timeline-bar', role: 'region', 'aria-label': 'Treatment timeline' });
  const chipsWrap = h('div', { class: 'timeline-chips' });
  const baBtn = h('button', {
    type: 'button',
    class: 'pill-btn tb-ba-btn',
    title: 'Hold to compare before and after',
  }, 'Before / After');

  el.append(chipsWrap, h('div', { class: 'tb-sep' }), baBtn);

  const timeline = {
    el,
    isAnimating: false,
    sync,
    animateToVisit,
    snapToVisit,
  };

  let prevVisitBeforeHold = null;
  function startHold(e) {
    e.preventDefault();
    const s = store.get();
    const maxV = (s.visits || []).length;
    if (maxV === 0) return;
    prevVisitBeforeHold = s.currentVisit ?? 0;
    const target = (s.currentVisit ?? 0) === 0 ? maxV : 0;
    try { e.currentTarget.setPointerCapture(e.pointerId); } catch {}
    snapToVisit(target);
  }

  function endHold(e) {
    if (prevVisitBeforeHold !== null) {
      e.preventDefault();
      snapToVisit(prevVisitBeforeHold);
      prevVisitBeforeHold = null;
    }
  }

  baBtn.addEventListener('pointerdown', startHold);
  baBtn.addEventListener('pointerup', endHold);
  baBtn.addEventListener('pointercancel', endHold);
  baBtn.addEventListener('pointerleave', endHold);

  let activeTicker = null;

  function snapToVisit(targetVisit) {
    if (activeTicker) {
      stage.removeTicker(activeTicker);
      activeTicker = null;
    }
    timeline.isAnimating = false;
    actions.applyStateSnapshot({ currentVisit: targetVisit });
  }

  // 500 ms smooth transition between visits
  function animateToVisit(targetVisit) {
    const s = store.get();
    if (s.currentVisit === targetVisit && !activeTicker) return;

    // Snapshot start values
    const startData = new Map();
    for (const [fdi, obj] of registry.teeth) {
      const mat = obj.userData.meshes[0]?.userData?.natural;
      startData.set(fdi, {
        p: obj.userData.rest.p.clone(),
        q: obj.userData.rest.q.clone(),
        shade: mat?.userData?.u?.uShade?.value?.clone() || null,
      });
    }

    timeline.isAnimating = true;
    // Set target state in store so effectiveTooth calculates target
    actions.applyStateSnapshot({ currentVisit: targetVisit });
    const nextState = store.get();
    const profile = nextState.profile || { baseShade: 'A2' };

    // Calculate target transforms and shades
    const targetData = new Map();
    for (const [fdi, obj] of registry.teeth) {
      const part = obj.userData.part;
      const t = effectiveTooth(nextState, fdi);
      if (!t) continue;

      const shift = t.shift || { md: 0, bl: 0, v: 0 };
      const rotate = t.rotate || { tip: 0, torque: 0, spin: 0 };
      const td = part.frame.tangentDistal;
      const fac = part.frame.facial;
      const cor = part.frame.coronal;

      const px = part.position[0] * profile.archWidth - td[0] * shift.md + fac[0] * shift.bl + cor[0] * shift.v;
      const py = part.position[1] - td[1] * shift.md + fac[1] * shift.bl + cor[1] * shift.v;
      const pz = part.position[2] * profile.archDepth - td[2] * shift.md + fac[2] * shift.bl + cor[2] * shift.v;

      const q = new THREE.Quaternion(...part.quaternion);
      const tipRad = -part.mesialSign * THREE.MathUtils.degToRad(rotate.tip || 0);
      const torqueRad = THREE.MathUtils.degToRad(rotate.torque || 0);
      const spinRad = THREE.MathUtils.degToRad(rotate.spin || 0);

      q.multiply(new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 0, 1), tipRad))
       .multiply(new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(1, 0, 0), torqueRad))
       .multiply(new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), spinRad));

      const shadeKey = t.shade ?? profile.baseShade ?? 'A2';
      const hex = SHADES[shadeKey] || (/^#[0-9a-f]{6}$/i.test(shadeKey) ? shadeKey : SHADES.A2);
      const shadeCol = new THREE.Color(hex);

      targetData.set(fdi, {
        p: new THREE.Vector3(px, py, pz),
        q,
        shade: shadeCol,
        scale: t.scale || { w: 1, h: 1 },
      });
    }

    if (activeTicker) {
      stage.removeTicker(activeTicker);
      activeTicker = null;
    }

    const startTime = performance.now();
    const duration = 500;

    const tick = () => {
      const elapsed = performance.now() - startTime;
      const rawProgress = Math.min(1, elapsed / duration);
      // Smoothstep easing
      const k = rawProgress * rawProgress * (3 - 2 * rawProgress);

      for (const [fdi, obj] of registry.teeth) {
        const start = startData.get(fdi);
        const target = targetData.get(fdi);
        if (!start || !target) continue;

        obj.userData.rest.p.lerpVectors(start.p, target.p, k);
        obj.userData.rest.q.slerpQuaternions(start.q, target.q, k);
        obj.position.copy(obj.userData.rest.p);
        obj.quaternion.copy(obj.userData.rest.q);

        const mat = obj.userData.meshes[0]?.userData?.natural;
        if (mat?.userData?.u?.uShade && start.shade && target.shade) {
          mat.userData.u.uShade.value.lerpColors(start.shade, target.shade, k);
        }
      }

      explode.apply();
      stage.invalidate();

      if (rawProgress >= 1) {
        stage.removeTicker(tick);
        activeTicker = null;
        timeline.isAnimating = false;

        for (const [fdi, obj] of registry.teeth) {
          const target = targetData.get(fdi);
          if (target) {
            obj.userData.rest.p.copy(target.p);
            obj.userData.rest.q.copy(target.q);
            obj.position.copy(target.p);
            obj.quaternion.copy(target.q);
            obj.scale.set(target.scale.w ?? 1, target.scale.h ?? 1, target.scale.w ?? 1);
          }
        }
        if (applyShape) applyShape(registry, store, explode, gums);
        else gums.rebuildAll();
        visuals?.rebuild();
        explode.apply();
        stage.invalidate();
        return false;
      }
      return true;
    };

    activeTicker = tick;
    stage.addTicker(tick);
  }

  function sync(s) {
    const visits = Array.isArray(s.visits) ? s.visits : [];
    if (visits.length === 0) {
      el.hidden = true;
      return;
    }
    el.hidden = false;
    chipsWrap.replaceChildren();

    const cur = s.currentVisit ?? 0;
    const total = visits.length;

    // Today chip (index 0)
    const todayBtn = h('button', {
      type: 'button',
      class: 'chip tl-chip' + (cur === 0 ? ' on' : ''),
      'data-visit': 0,
      onclick: () => animateToVisit(0),
    }, 'Today');
    chipsWrap.append(todayBtn);

    // Each visit chip (index 1..total)
    visits.forEach((v, idx) => {
      const vIdx = idx + 1;
      const isFinal = (vIdx === total);
      const rawLabel = typeof v === 'string' ? v : (v?.label || `Visit ${vIdx}`);
      const label = isFinal ? (rawLabel.toLowerCase().includes('final') ? rawLabel : `Final (${rawLabel})`) : rawLabel;
      const chip = h('button', {
        type: 'button',
        class: 'chip tl-chip' + (cur === vIdx ? ' on' : '') + (isFinal ? ' tl-final' : ''),
        'data-visit': vIdx,
        onclick: () => animateToVisit(vIdx),
      }, label);
      chipsWrap.append(chip);
    });
  }

  return timeline;
}

function h(tag, attrs, ...children) {
  const el = document.createElement(tag);
  if (attrs) {
    for (const [k, v] of Object.entries(attrs)) {
      if (k === 'class') el.className = v;
      else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2), v);
      else if (k === 'hidden') { if (v) el.setAttribute('hidden', ''); else el.removeAttribute('hidden'); }
      else el.setAttribute(k, v);
    }
  }
  for (const c of children) {
    if (c == null) continue;
    if (typeof c === 'string' || typeof c === 'number') el.append(document.createTextNode(c));
    else el.append(c);
  }
  return el;
}
