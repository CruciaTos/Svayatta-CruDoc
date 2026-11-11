import { h } from './dom.js';
import { CONDITIONS, TREATMENTS, MATERIALS, STATUS_COLORS, SURFACES } from '../data/treatments.js';
import { archOfFdi, effectiveTooth } from '../treatments/effective.js';

export function createTreatmentPanel({ store, actions, registry }) {
  const el = h('div', { id: 'treatment-panel', class: 'treatment-panel' });
  let isAdding = false;

  function sync(s) {
    const id = s.selectedId;
    const part = id ? registry.parts.get(id) : null;
    if (!part || part.kind !== 'tooth' || !part.fdi) {
      el.replaceChildren();
      el.hidden = true;
      isAdding = false;
      return;
    }
    el.hidden = false;
    el.replaceChildren();

    const fdi = part.fdi;
    const arch = archOfFdi(fdi);
    const toothEff = effectiveTooth(s, fdi) || s.teeth[fdi] || {};

    // 1. Conditions on this tooth
    const activeConditions = [];

    // Explicit conditions from tooth state
    if (Array.isArray(toothEff.conditions)) {
      for (const c of toothEff.conditions) {
        if (!c) continue;
        const info = CONDITIONS.find((x) => x.id === c.type) || { label: c.type, patientText: '' };
        let title = info.label;
        if (c.type === 'caries') {
          const surfs = (Array.isArray(c.surfaces) && c.surfaces.length) ? c.surfaces : ['O'];
          const surfLabels = surfs.map((srf) => {
            if (srf === 'O') return 'biting surface';
            if (srf === 'M') return 'front side';
            if (srf === 'D') return 'back side';
            if (srf === 'B') return 'cheek side';
            if (srf === 'L') return 'tongue side';
            return srf;
          });
          title = `Decay on ${surfLabels.join(', ')} (${surfs.join('')})`;
        }
        activeConditions.push({
          title,
          desc: info.patientText || '',
        });
      }
    }

    // Numeric conditions
    if (toothEff.recession > 0) {
      activeConditions.push({
        title: `${toothEff.recession} mm gum recession`,
        desc: 'The gum has pulled back, exposing part of the root.',
      });
    }
    if (toothEff.calculus > 0) {
      activeConditions.push({
        title: 'Tartar near the gum line',
        desc: 'Hardened deposits have built up and irritate the gum.',
      });
    }
    if (toothEff.inflammation > 0) {
      activeConditions.push({
        title: 'Swollen gum',
        desc: 'The gum around this tooth is red and inflamed.',
      });
    }
    if (toothEff.boneLoss > 0) {
      activeConditions.push({
        title: `${toothEff.boneLoss} mm bone loss`,
        desc: 'Bone supporting the tooth has receded under the gum.',
      });
    }
    if (toothEff.wear > 0) {
      activeConditions.push({
        title: `${toothEff.wear} mm worn biting edge`,
        desc: 'The biting edge has worn down from grinding or chewing.',
      });
    }
    if (toothEff.chip > 0) {
      activeConditions.push({
        title: 'Chipped tooth edge',
        desc: 'A piece of the enamel has chipped off.',
      });
    }

    if (activeConditions.length > 0) {
      el.append(h('div', { class: 'treat-section-title' }, 'Conditions'));
      for (const cond of activeConditions) {
        const card = h('div', { class: 'treat-card' },
          h('div', { class: 'treat-card-title' }, cond.title),
          cond.desc ? h('div', { class: 'treat-card-desc' }, cond.desc) : null
        );
        el.append(card);
      }
    }

    // 2. Treatments on this tooth
    const allTreatments = Array.isArray(s.treatments) ? s.treatments : [];
    const toothTreatments = allTreatments.filter((tr) => {
      if (!tr) return false;
      if (Array.isArray(tr.teeth) && tr.teeth.map(Number).includes(fdi)) return true;
      if (Array.isArray(tr.arches) && tr.arches.includes(arch)) return true;
      return false;
    });

    if (toothTreatments.length > 0) {
      el.append(h('div', { class: 'treat-section-title' }, 'Treatments'));
      for (const tr of toothTreatments) {
        const info = TREATMENTS.find((x) => x.id === tr.type) || { label: tr.type };
        const mat = tr.material ? (MATERIALS[tr.material]?.label || tr.material) : '';
        const surfs = tr.surfaces?.length ? ` (${tr.surfaces.join('')})` : '';
        const visitTxt = tr.visit ? `Visit ${tr.visit}` : 'Visit 1';

        const statusColor = STATUS_COLORS[tr.status || 'planned'] || '#CBD5E1';
        const statusBtn = h('button', {
          type: 'button',
          class: 'chip',
          title: 'Cycle status',
          onclick: () => {
            const nextStatus = tr.status === 'planned' ? 'inProgress' : tr.status === 'inProgress' ? 'completed' : 'planned';
            const updated = allTreatments.map((x) => (x.id === tr.id ? { ...x, status: nextStatus } : x));
            actions.applyStateSnapshot({ treatments: updated });
          },
        }, h('span', { class: 'dot', style: `background:${statusColor}` }), tr.status || 'planned');

        const rmBtn = tr.origin === 'viewer' ? h('button', {
          type: 'button',
          class: 'treat-rm-btn',
          title: 'Remove treatment',
          onclick: () => {
            const remaining = allTreatments.filter((x) => x.id !== tr.id);
            actions.applyStateSnapshot({ treatments: remaining });
          },
        }, 'Remove') : null;

        const card = h('div', { class: 'treat-card' },
          h('div', { class: 'treat-card-hdr' },
            h('span', { class: 'treat-card-title' }, `${info.label}${surfs}`),
            statusBtn
          ),
          h('div', { class: 'treat-meta-row' },
            h('span', { class: 'treat-meta' }, [mat, visitTxt].filter(Boolean).join(' · ')),
            rmBtn
          )
        );
        el.append(card);
      }
    }

    // 3. Add treatment button & form
    const interactiveActions = part.interactiveActions || ['filling', 'crown', 'rct', 'extraction', 'implant'];
    if (!isAdding) {
      const addBtn = h('button', {
        type: 'button',
        class: 'pill-btn wide treat-add-btn',
        onclick: () => { isAdding = true; sync(store.get()); },
      }, '+ Add treatment');
      el.append(addBtn);
    } else {
      let selectedType = interactiveActions[0] || 'filling';
      const selectedSurfs = new Set(['O']);
      let selectedMaterial = '';
      let selectedVisit = 1;

      const typeSelect = h('select', {
        'aria-label': 'Treatment type',
        onchange: () => {
          selectedType = typeSelect.value;
          renderFormDetails();
        },
      }, interactiveActions.map((act) => {
        const tInfo = TREATMENTS.find((x) => x.id === act);
        return h('option', { value: act }, tInfo?.label || act);
      }));

      const formDetails = h('div', { class: 'treat-form-details' });

      function renderFormDetails() {
        formDetails.replaceChildren();
        const tInfo = TREATMENTS.find((x) => x.id === selectedType);

        // Surfaces for fillings
        if (tInfo?.needsSurfaces || selectedType === 'filling') {
          const chips = SURFACES.map((srf) => {
            const sc = h('button', {
              type: 'button',
              class: 'surf-chip' + (selectedSurfs.has(srf) ? ' on' : ''),
              onclick: () => {
                if (selectedSurfs.has(srf)) selectedSurfs.delete(srf);
                else selectedSurfs.add(srf);
                sc.classList.toggle('on', selectedSurfs.has(srf));
              },
            }, srf);
            return sc;
          });
          formDetails.append(
            h('div', { class: 'match-lbl' }, 'Surfaces'),
            h('div', { class: 'surf-chips' }, chips)
          );
        }

        // Materials
        if (tInfo?.materials && tInfo.materials.length) {
          selectedMaterial = tInfo.materials[0];
          const matSelect = h('select', {
            'aria-label': 'Material',
            onchange: () => { selectedMaterial = matSelect.value; },
          }, tInfo.materials.map((m) => {
            const mInfo = MATERIALS[m];
            return h('option', { value: m }, mInfo?.label || m);
          }));
          formDetails.append(
            h('div', { class: 'match-lbl' }, 'Material'),
            matSelect
          );
        } else {
          selectedMaterial = '';
        }

        // Visit
        const visits = s.visits || [];
        const visitCount = Math.max(1, visits.length);
        const visitOptions = Array.from({ length: visitCount }, (_, i) => i + 1).map((vNum) => {
          const vObj = visits[vNum - 1];
          const vLabel = typeof vObj === 'string' ? vObj : (vObj?.label || `Visit ${vNum}`);
          return h('option', { value: vNum }, vLabel);
        });
        const visitSelect = h('select', {
          'aria-label': 'Visit',
          onchange: () => { selectedVisit = +visitSelect.value; },
        }, visitOptions);
        formDetails.append(
          h('div', { class: 'match-lbl' }, 'Visit'),
          visitSelect
        );
      }

      renderFormDetails();

      const saveBtn = h('button', {
        type: 'button',
        class: 'pill-btn on',
        onclick: () => {
          const newTr = {
            id: `viewer_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
            type: selectedType,
            teeth: [fdi],
            status: 'planned',
            visit: selectedVisit,
            origin: 'viewer',
          };
          if (selectedType === 'filling' || TREATMENTS.find((x) => x.id === selectedType)?.needsSurfaces) {
            newTr.surfaces = Array.from(selectedSurfs);
          }
          if (selectedMaterial) {
            newTr.material = selectedMaterial;
          }
          isAdding = false;
          actions.applyStateSnapshot({ treatments: [...allTreatments, newTr] });
        },
      }, 'Save');

      const cancelBtn = h('button', {
        type: 'button',
        class: 'pill-btn',
        onclick: () => { isAdding = false; sync(store.get()); },
      }, 'Cancel');

      const form = h('div', { class: 'treat-form' },
        h('div', { class: 'match-lbl' }, 'Treatment type'),
        typeSelect,
        formDetails,
        h('div', { class: 'seg match-seg' }, saveBtn, cancelBtn)
      );
      el.append(form);
    }
  }

  return { el, sync };
}
