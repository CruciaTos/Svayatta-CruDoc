import { h, icon } from './dom.js';
import { STATUS_COLORS } from '../data/treatments.js';
import { createMatchPanel } from './matchPanel.js';
import { createTreatmentPanel } from './treatmentPanel.js';

const STATUS_CHIPS = [['normal', 'Normal'], ['flagged', 'Flagged'], ['planned', 'Planned'], ['inProgress', 'In progress'], ['completed', 'Completed']];
const GROUPS = [
  { arch: 'upper', title: 'Upper arch', quads: [[1, 'Upper right', [11, 12, 13, 14, 15, 16, 17, 18]], [2, 'Upper left', [21, 22, 23, 24, 25, 26, 27, 28]]] },
  { arch: 'lower', title: 'Lower arch', quads: [[4, 'Lower right', [41, 42, 43, 44, 45, 46, 47, 48]], [3, 'Lower left', [31, 32, 33, 34, 35, 36, 37, 38]]] },
];
const dotColor = (st) => STATUS_COLORS[st] || '#CBD5E1';

export function createInspector({ store, actions, registry, player }) {
  const rows = []; // {el, text, id, fdi, dot}
  const mkRow = (id, label, fdi) => {
    const dot = h('span', { class: 'dot' });
    const el = h('button', { type: 'button', class: 'tree-row', 'data-id': id, onclick: () => actions.select(id, { fly: true }) }, dot, h('span', { class: 'lbl' }, label));
    rows.push({ el, text: label.toLowerCase(), id, fdi, dot });
    return el;
  };
  const groupEls = [];
  const tree = h('div', { class: 'tree', role: 'tree' });
  for (const g of GROUPS) {
    const body = h('div', { class: 'grp-body' });
    const details = h('details', { class: 'grp', open: true }, h('summary', null, icon('chevron', 16), g.title), body);
    const subs = [];
    for (const [q, qLabel, fdis] of g.quads) {
      const qBody = h('div', { class: 'grp-body' });
      for (const fdi of fdis) {
        const part = registry.parts.get('tooth_' + fdi);
        qBody.append(mkRow(part.nodeId, `${fdi} · ${part.displayName}`, fdi));
      }
      const qd = h('details', { class: 'grp sub', open: q === 1 || q === 4 }, h('summary', null, icon('chevron', 16), `${qLabel} (Q${q})`), qBody);
      subs.push(qd); body.append(qd);
    }
    for (const kind of ['gum', 'bone']) {
      const id = `${kind}_${g.arch}`;
      body.append(mkRow(id, registry.parts.get(id).displayName, null));
    }
    groupEls.push({ details, subs });
    tree.append(details);
  }

  const search = h('input', { type: 'search', class: 'search', placeholder: 'Search teeth, gums, bone', 'aria-label': 'Search parts', autocomplete: 'off', spellcheck: 'false' });
  search.addEventListener('input', () => {
    const q = search.value.trim().toLowerCase();
    for (const r of rows) r.el.hidden = !!q && !r.text.includes(q);
    for (const g of groupEls) {
      let any = false;
      for (const qd of g.subs) {
        const has = [...qd.querySelectorAll('.tree-row')].some((e) => !e.hidden);
        qd.hidden = !has; if (q && has) qd.open = true; any ||= has;
      }
      const direct = [...g.details.querySelectorAll(':scope > .grp-body > .tree-row')].some((e) => !e.hidden);
      g.details.hidden = !(any || direct);
      if (q) g.details.open = true;
    }
  });
  const searchWrap = h('div', { class: 'search-wrap' }, icon('search', 16), search);

  // selected-part card
  const cardName = h('div', { class: 'card-name' }, 'Nothing selected');
  const cardMeta = h('div', { class: 'card-meta' });
  const cardId = h('code', { class: 'mono card-id' });
  const chips = STATUS_CHIPS.map(([k, label]) => h('button', {
    type: 'button', class: 'chip', 'data-status': k, onclick: () => { const id = store.get().selectedId; if (id) actions.setPartStatus(id, k); },
  }, h('span', { class: 'dot', style: `background:${dotColor(k)}` }), label));
  const chipRow = h('div', { class: 'chips' }, chips);
  const hint = h('div', { class: 'card-hint' }, 'Tap a tooth in the 3D view or pick one from the list.');
  const card = h('section', { class: 'card' }, cardName, cardMeta, cardId, chipRow, hint);
  const matchPanel = createMatchPanel({ store, actions, registry });
  const treatmentPanel = createTreatmentPanel({ store, actions, registry, player });

  const body = h('div', { class: 'insp-body' }, searchWrap, tree, card, matchPanel.el, treatmentPanel.el);
  const handle = h('div', { class: 'sheet-handle', role: 'button', 'aria-label': 'Expand inspector', tabindex: 0 }, h('span', { class: 'grip' }));
  const peek = h('div', { class: 'sheet-peek' }, h('span', { class: 'peek-name' }, 'Tap a tooth'));
  const el = h('aside', { class: 'inspector', 'aria-label': 'Inspector' }, handle, peek, body);

  function sync(s) {
    const id = s.selectedId;
    for (const r of rows) {
      r.el.classList.toggle('sel', r.id === id);
      r.dot.style.background = r.fdi ? dotColor(s.teeth[r.fdi].status) : '#E2E8F0';
    }
    const part = id ? registry.parts.get(id) : null;
    cardName.textContent = part ? part.displayName : 'Nothing selected';
    cardMeta.replaceChildren();
    cardId.textContent = part ? part.nodeId : '';
    hint.hidden = !!part;
    chipRow.hidden = !part || part.kind !== 'tooth';
    if (part) {
      if (part.fdi) cardMeta.append(h('span', { class: 'badge mono' }, `FDI ${part.fdi}`));
      cardMeta.append(h('span', { class: 'badge' }, part.toothClass || part.category));
      if (part.kind !== 'tooth') cardMeta.append(h('span', { class: 'card-note' }, 'Status applies to teeth.'));
    }
    const st = part && part.fdi ? s.teeth[part.fdi].status : null;
    chips.forEach((c) => c.classList.toggle('on', c.dataset.status === st));
    peek.firstChild.textContent = part ? (part.fdi ? `${part.fdi} · ${part.displayName}` : part.displayName) : 'Tap a tooth';
    matchPanel.sync(s);
    treatmentPanel.sync(s);
  }
  let lastSel = null;
  store.subscribe((s, changed) => {
    sync(s);
    if (changed.has('selectedId') && s.selectedId !== lastSel) {
      lastSel = s.selectedId;
      const r = rows.find((x) => x.id === s.selectedId);
      if (r) {
        for (let p = r.el.parentElement; p; p = p.parentElement) if (p.tagName === 'DETAILS') p.open = true;
        // scroll only the tree itself (scrollIntoView would also scroll the page / sheet)
        const tr = tree.getBoundingClientRect(); const rr = r.el.getBoundingClientRect();
        if (rr.top < tr.top + 28) tree.scrollTop += rr.top - tr.top - 28;
        else if (rr.bottom > tr.bottom) tree.scrollTop += rr.bottom - tr.bottom;
      }
    }
  });
  sync(store.get());

  // bottom sheet behaviour (narrow screens)
  const app = () => document.getElementById('app');
  const peekH = 64;
  let drag = null;
  const setOpen = (open) => {
    app().classList.toggle('sheet-open', open);
    el.style.transform = '';
    handle.setAttribute('aria-expanded', String(open));
  };
  const sheetH = () => el.getBoundingClientRect().height;
  const startDrag = (e) => {
    drag = { y: e.clientY, open: app().classList.contains('sheet-open'), moved: 0 };
    e.currentTarget.setPointerCapture(e.pointerId);
  };
  const moveDrag = (e) => {
    if (!drag) return;
    const dy = e.clientY - drag.y;
    drag.moved = Math.max(drag.moved, Math.abs(dy));
    const closedY = sheetH() - peekH;
    const y = Math.min(closedY, Math.max(0, (drag.open ? 0 : closedY) + dy));
    el.style.transition = 'none';
    el.style.transform = `translateY(${y}px)`;
  };
  const endDrag = (e) => {
    if (!drag) return;
    const d = drag; drag = null; el.style.transition = '';
    if (d.moved < 6) { setOpen(!d.open); return; }
    const dy = e.clientY - d.y;
    setOpen(d.open ? dy < 60 : dy < -40);
  };
  for (const t of [handle, peek]) {
    t.addEventListener('pointerdown', startDrag);
    t.addEventListener('pointermove', moveDrag);
    t.addEventListener('pointerup', endDrag);
    t.addEventListener('pointercancel', endDrag);
  }
  handle.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === ' ') setOpen(!app().classList.contains('sheet-open'));
  });
  return { el, setOpen };
}
