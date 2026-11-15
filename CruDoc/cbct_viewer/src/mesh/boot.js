// The scan viewer page: one surface mesh, full screen, with the top bar and
// status line the CBCT viewer uses. Flutter opens it with the file to read on
// the query string and listens on the same 'cbct' handler.
import '../styles/tokens.css';
import '../styles/mesh.css';
import { version } from '../../package.json';
import { icon } from '../icons.js';
import { createScene } from './view.js';
import ParseWorker from './parse.worker.js?worker&inline';

function h(tag, props = {}, ...kids) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (v === undefined || v === null) continue;
    if (k === 'class') node.className = v;
    else if (k === 'text') node.textContent = v;
    else if (k.startsWith('on')) node.addEventListener(k.slice(2), v);
    else node.setAttribute(k, v);
  }
  kids.flat().forEach((c) => c != null && c !== false && node.append(c));
  return node;
}

const count = (n) => n.toLocaleString('en-US');
const bytes = (n) => (n < 1024 ? `${n} B` : n < 1024 * 1024 ? `${(n / 1024).toFixed(1)} KB` : `${(n / (1024 * 1024)).toFixed(1)} MB`);
const sizeOf = (b) => `${Math.round(b[1] - b[0])} × ${Math.round(b[3] - b[2])} × ${Math.round(b[5] - b[4])} mm`;

// ───────────────────────── The page ─────────────────────────

function mount(root, { title, name, badge }) {
  const back = h('button', { class: 'ico', type: 'button', title: 'Back', 'aria-label': 'Back' }, icon('back', 16));
  const titleEl = h('div', { class: 'title', text: title || name || '3D scan' });
  const chip = h('div', { class: 'chip', text: name || '' });
  const reset = h('button', { class: 'ico', type: 'button', title: 'Reset the view (R)', 'aria-label': 'Reset the view' }, icon('reset', 16));

  // One row of choices, the picked one filled in.
  const segment = (items, onPick, initial) => {
    const buttons = items.map(([, label]) => h('button', { class: 'seg-btn', type: 'button', text: label }));
    buttons.forEach((b, i) => {
      b.classList.toggle('on', items[i][0] === initial);
      b.addEventListener('click', () => {
        buttons.forEach((x) => x.classList.toggle('on', x === b));
        onPick(items[i][0]);
      });
    });
    return { el: h('div', { class: 'seg' }, buttons), buttons };
  };

  const stage = h('div', { class: 'stage' });
  const hint = h('div', { class: 'hint', text: 'Drag to rotate · scroll to zoom · middle-drag to move' });
  const message = h('div', { class: 'msg', hidden: 'hidden' });
  const note = h('div', { class: 'note' });
  const bar = h('i');
  const progress = h('div', { class: 'progress' }, note, h('div', { class: 'track' }, bar));
  const status = h('div', { class: 'status' });
  const badgeEl = badge ? h('div', { class: badge === 'Anonymized' ? 'badge good' : 'badge' }, icon(badge === 'Anonymized' ? 'shield' : 'eye', 13), h('span', { text: badge })) : null;

  const looks = segment([['front', 'Front'], ['top', 'Top'], ['side', 'Side']], (id) => page.onLook(id), 'front');
  const colours = segment([['ivory', 'Ivory'], ['scan', 'Scan colour']], (id) => page.onColour(id), 'ivory');
  colours.el.hidden = true;

  const top = h('header', { class: 'topbar' }, back, titleEl, chip, h('span', { class: 'grow' }), looks.el, colours.el, reset, badgeEl);
  root.append(h('div', { class: 'app' }, top, h('main', { class: 'main' }, stage, hint, message, progress), h('footer', { class: 'statusbar' }, status)));

  const page = {
    stage,
    onLook: () => {},
    onColour: () => {},
    onBack: () => {},
    onReset: () => {},
    setChip: (text) => (chip.textContent = text),
    setStatus: (text) => (status.textContent = text),
    showColours: () => (colours.el.hidden = false),
    busy(text, fraction) {
      progress.hidden = false;
      note.textContent = text;
      bar.style.width = fraction == null ? '' : `${Math.round(fraction * 100)}%`;
      bar.classList.toggle('waiting', fraction == null);
    },
    done() {
      progress.hidden = true;
      hint.classList.add('show');
      setTimeout(() => hint.classList.remove('show'), 4000);
    },
    fail(text) {
      progress.hidden = true;
      message.hidden = false;
      message.textContent = text;
    },
  };
  back.addEventListener('click', () => page.onBack());
  reset.addEventListener('click', () => page.onReset());
  return page;
}

// ───────────────────────── Reading the file ─────────────────────────

async function fetchMeshFile(url, onProgress) {
  const res = await fetch(url);
  if (!res.ok) throw new Error('This 3D file could not be read from the clinic computer.');
  const total = Number(res.headers.get('content-length')) || 0;
  if (!res.body || !total) return { buffer: await res.arrayBuffer(), total };
  const chunks = [];
  const reader = res.body.getReader();
  let got = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    got += value.length;
    onProgress(got / total);
  }
  const out = new Uint8Array(got);
  let at = 0;
  for (const c of chunks) {
    out.set(c, at);
    at += c.length;
  }
  return { buffer: out.buffer, total: got };
}

function parseInWorker(buffer, name) {
  return new Promise((resolve, reject) => {
    const worker = new ParseWorker();
    worker.onmessage = (e) => {
      worker.terminate();
      if (e.data.error) reject(new Error(e.data.error));
      else resolve(e.data);
    };
    worker.onerror = () => {
      worker.terminate();
      reject(new Error('CruDoc could not read this 3D file.'));
    };
    worker.postMessage({ id: 1, buffer, name }, [buffer]);
  });
}

// ───────────────────────── Boot ─────────────────────────

export async function start(params) {
  const post = bridge();
  const name = params.get('name') || '';
  const page = mount(document.getElementById('app'), {
    title: params.get('title') || '',
    name,
    badge: params.get('badge') || '',
  });
  if (params.get('reduced') === '1' || matchMedia('(prefers-reduced-motion: reduce)').matches) {
    document.documentElement.classList.add('reduced');
  }
  post({ type: 'boot', version });

  const scene = createScene(page.stage);
  const leave = () => post({ type: 'close' });
  page.onBack = leave;
  page.onLook = (id) => scene.look(id);
  page.onColour = (id) => scene.setColourMode(id);
  page.onReset = () => scene.look('front');
  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') leave();
    else if (e.key === 'r' || e.key === 'R') scene.look('front');
  });

  const url = params.get('file');
  if (!url) {
    page.fail('No 3D file was given to open.');
    return;
  }
  try {
    page.busy('Opening the scan', 0);
    const { buffer, total } = await fetchMeshFile(url, (f) => page.busy('Opening the scan', f));
    page.busy('Preparing the surface', null);
    const mesh = await parseInWorker(buffer, name);
    scene.showMesh(mesh);
    const kind = mesh.format.toUpperCase();
    page.setChip([name, `${count(mesh.triangles)} triangles`].filter(Boolean).join(' · '));
    page.setStatus([kind, bytes(total), `${count(mesh.triangles)} triangles`, `${count(mesh.points)} points`, sizeOf(mesh.bounds)].join('  ·  '));
    if (mesh.colors) page.showColours();
    page.done();
    post({ type: 'shown', triangles: mesh.triangles, points: mesh.points, format: mesh.format, parseMs: mesh.parseMs });
    if (params.has('debug')) window.__mesh = { scene, mesh: { ...mesh, positions: null, indices: null, normals: null, colors: null }, triangles: mesh.triangles, points: mesh.points };
  } catch (err) {
    const text = err && err.message ? err.message : 'CruDoc could not open this 3D file.';
    page.fail(text);
    post({ type: 'error', message: text });
  }
}

// The same handler name the CBCT viewer uses, so the Flutter side is one piece of wiring.
function bridge() {
  const outbox = [];
  let ready = !!(window.flutter_inappwebview && typeof window.flutter_inappwebview.callHandler === 'function');
  const send = (msg) => {
    try {
      window.flutter_inappwebview.callHandler('cbct', msg);
    } catch {
      /* outside the app: the console line below is the whole record */
    }
  };
  window.addEventListener('flutterInAppWebViewPlatformReady', () => {
    ready = true;
    while (outbox.length) send(outbox.shift());
  }, { once: true });
  return (msg) => {
    console.log('[mesh->flutter]', JSON.stringify(msg));
    if (ready) send(msg);
    else outbox.push(msg);
  };
}
