// Phone / tablet / desktop layout and touch checks for the 3D viewer (headless Chrome, dev server).
//   node tests/responsive.mjs
// Viewports: phone 375x812, phone landscape 812x375, tablet 768x1024, desktop 1280x800.
import puppeteer from 'puppeteer-core';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..');
const shots = path.join(root, 'tmp', 'shots', 'responsive');
fs.mkdirSync(shots, { recursive: true });
const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const BASE = 'http://127.0.0.1:5174/';

let pass = 0, fail = 0;
const failures = [];
function check(name, ok, detail = '') {
  if (ok) { pass++; console.log(`  ok   ${name}`); }
  else { fail++; failures.push(name); console.log(`  FAIL ${name}  ${detail}`); }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let closeServer = async () => { };
try { if (!(await fetch(BASE)).ok) throw 0; } catch {
  const { createServer } = await import('vite');
  const server = await createServer({ root, logLevel: 'error', server: { hmr: false, watch: null } });
  await server.listen();
  closeServer = () => server.close();
}
const browser = await puppeteer.launch({
  executablePath: CHROME, headless: 'new', defaultViewport: null,
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-webgl', '--no-sandbox', '--disable-dev-shm-usage'],
});

const VIEWPORTS = [
  ['phone 375x812', 375, 812, true],
  ['phone landscape 812x375', 812, 375, true],
  ['tablet 768x1024', 768, 1024, true],
  ['desktop 1280x800', 1280, 800, false],
];

const idle = (page, quiet = 300) => page.evaluate(async (quiet) => {
  const t0 = performance.now();
  let last = -1, lc = performance.now();
  while (performance.now() - t0 < 60000) {
    await new Promise((r) => setTimeout(r, 60));
    const n = window.__dental3d.stats().renderedFrames;
    if (n !== last) { last = n; lc = performance.now(); }
    if (performance.now() - lc > quiet && window.__dental3d.flyDone()) return n;
  }
  return -1;
}, quiet);

async function open(w, h, mobile, query = 'q=low') {
  const page = await browser.newPage();
  await page.setViewport({ width: w, height: h, deviceScaleFactor: 1, isMobile: mobile, hasTouch: mobile });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await page.goto(`${BASE}?${query}`, { waitUntil: 'load' });
  await page.waitForFunction('window.App3DBridge && window.__dental3d', { timeout: 120000 });
  await page.evaluate('window.App3DBridge.ready');
  await idle(page);
  return { page, errors };
}

// Rects of the pieces that must not collide, plus every control that must be tappable.
const MEASURE = () => {
  const vis = (el) => { const r = el.getBoundingClientRect(); const s = getComputedStyle(el); return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none'; };
  const rect = (sel) => {
    const el = document.querySelector(sel);
    if (!el || !vis(el)) return null;
    const r = el.getBoundingClientRect();
    return { l: Math.round(r.left), t: Math.round(r.top), r: Math.round(r.right), b: Math.round(r.bottom) };
  };
  const inspector = document.querySelector('.inspector');
  let insp = null;
  if (inspector && vis(inspector)) {
    const r = inspector.getBoundingClientRect();
    insp = { l: Math.round(r.left), t: Math.round(r.top), r: Math.round(r.right), b: Math.round(r.bottom) };
  }
  const targets = [];
  const scopes = ['.toolbar', '.timeline-bar', '.explainer-card', '.sheet-handle', '.sheet-peek', '.treatment-panel', '.tb-sliders.open', '.popover.open'];
  for (const sc of scopes) {
    for (const root of document.querySelectorAll(sc)) {
      if (!vis(root)) continue;
      // Skip elements clipped away by the closed bottom sheet.
      for (const el of root.querySelectorAll('button, [role=button], input[type=range], input[type=checkbox], select')) {
        if (!vis(el)) continue;
        const r = el.getBoundingClientRect();
        if (r.top >= innerHeight || r.bottom <= 0) continue;
        targets.push({ sc, tag: el.tagName.toLowerCase(), cls: el.className?.toString().slice(0, 30) || '', w: Math.round(r.width), h: Math.round(r.height), txt: (el.textContent || el.getAttribute('aria-label') || '').trim().slice(0, 16) });
      }
    }
  }
  return {
    vw: innerWidth, vh: innerHeight,
    scrollW: document.documentElement.scrollWidth, scrollH: document.documentElement.scrollHeight,
    bodyScrollW: document.body.scrollWidth,
    toolbar: rect('.toolbar'), timeline: rect('.timeline-bar'), insp, peek: rect('.sheet-peek'),
    explainer: rect('.explainer-card'), stage: rect('.stage'),
    canvas: (() => { const c = document.querySelector('canvas.stage-canvas'); const s = document.querySelector('.stage').getBoundingClientRect(); return { cw: c.clientWidth, ch: c.clientHeight, sw: Math.round(s.width), sh: Math.round(s.height) }; })(),
    targets,
  };
};

const overlap = (a, b) => a && b && a.l < b.r - 1 && b.l < a.r - 1 && a.t < b.b - 1 && b.t < a.b - 1;
const inside = (a, w, h) => a && a.l >= -1 && a.t >= -1 && a.r <= w + 1 && a.b <= h + 1;

for (const [name, w, h, mobile] of VIEWPORTS) {
  console.log(`\n== ${name} ==`);
  const { page, errors } = await open(w, h, mobile);
  await page.evaluate(() => { window.App3DBridge.loadPreset('worn_gum_disease'); window.App3DBridge.selectPart('tooth_36'); });
  await idle(page);
  const sheetMode = w < 900;

  // 1. idle layout
  let m = await page.evaluate(MEASURE);
  check(`${name}: no horizontal page scroll`, m.scrollW <= m.vw && m.bodyScrollW <= m.vw, `scrollW=${m.scrollW} vw=${m.vw}`);
  check(`${name}: toolbar and timeline sit inside the viewport`, inside(m.toolbar, m.vw, m.vh) && inside(m.timeline, m.vw, m.vh), JSON.stringify({ tb: m.toolbar, tl: m.timeline }));
  check(`${name}: toolbar, timeline and sheet do not overlap`, !overlap(m.toolbar, m.timeline) && !overlap(m.toolbar, m.insp) && !overlap(m.timeline, m.insp), JSON.stringify({ tb: m.toolbar, tl: m.timeline, insp: m.insp }));
  check(`${name}: canvas matches the stage`, Math.abs(m.canvas.cw - m.canvas.sw) <= 1 && Math.abs(m.canvas.ch - m.canvas.sh) <= 1, JSON.stringify(m.canvas));
  const small = m.targets.filter((t) => t.w < 40 - 0.5 || t.h < 40 - 0.5);
  check(`${name}: touch targets >= 40 px (idle)`, !mobile || small.length === 0, JSON.stringify(small.slice(0, 6)));
  await page.screenshot({ path: path.join(shots, `${w}x${h}-idle.png`) });

  // 2. sheet open + treatment panel
  if (sheetMode) {
    await page.evaluate(() => document.querySelector('.sheet-handle').click());
    await sleep(500);
    await idle(page);
    m = await page.evaluate(MEASURE);
    check(`${name}: open sheet leaves room for the toolbar`, !overlap(m.toolbar, m.insp) && !overlap(m.timeline, m.insp) && inside(m.toolbar, m.vw, m.vh), JSON.stringify({ tb: m.toolbar, tl: m.timeline, insp: m.insp }));
    const sm = m.targets.filter((t) => t.w < 40 - 0.5 || t.h < 40 - 0.5);
    check(`${name}: touch targets >= 40 px (sheet open)`, sm.length === 0, JSON.stringify(sm.slice(0, 8)));
    await page.screenshot({ path: path.join(shots, `${w}x${h}-sheet.png`) });
    await page.evaluate(() => document.querySelector('.sheet-handle').click());
    await sleep(400);
  } else {
    m = await page.evaluate(MEASURE);
    const sm = m.targets.filter((t) => t.w < 40 - 0.5 || t.h < 40 - 0.5);
    check(`${name}: touch targets >= 40 px (side panel)`, !mobile || sm.length === 0, JSON.stringify(sm.slice(0, 8)));
  }

  // 3. explainer card
  const started = await page.evaluate(() => {
    const tr = window.__dental3d.store.get().treatments.find((t) => t.type === 'filling') || window.__dental3d.store.get().treatments[0];
    return tr ? window.__dental3d.player.play(tr.id) : false;
  });
  await sleep(300);
  await idle(page);
  m = await page.evaluate(MEASURE);
  check(`${name}: explainer started`, started === true && !!m.explainer);
  check(`${name}: explainer inside viewport and clear of toolbar, timeline, sheet`, inside(m.explainer, m.vw, m.vh) && !overlap(m.explainer, m.toolbar) && !overlap(m.explainer, m.timeline) && !overlap(m.explainer, m.insp), JSON.stringify({ ex: m.explainer, tb: m.toolbar, tl: m.timeline, insp: m.insp }));
  const em = m.targets.filter((t) => t.sc === '.explainer-card' && (t.w < 40 - 0.5 || t.h < 40 - 0.5));
  check(`${name}: explainer buttons >= 40 px`, !mobile || em.length === 0, JSON.stringify(em));
  await page.screenshot({ path: path.join(shots, `${w}x${h}-explainer.png`) });
  await page.evaluate(() => window.__dental3d.player.close());
  await sleep(200);

  check(`${name}: no page errors`, errors.length === 0, errors.slice(0, 3).join(' | '));

  // 4. touch gestures (touch devices only)
  if (mobile && w === 375) {
    const client = await page.createCDPSession();
    const touch = async (type, pts) => client.send('Input.dispatchTouchEvent', { type, touchPoints: pts.map(([x, y], i) => ({ x, y, id: i + 1 })) });
    const cam = () => page.evaluate(() => {
      const { camera, controls } = window.__dental3d.stage;
      return { d: camera.position.distanceTo(controls.target), p: camera.position.toArray(), t: controls.target.toArray() };
    });
    await page.evaluate(() => { window.App3DBridge.selectPart(null); window.App3DBridge.resetCamera(); });
    await idle(page);
    const stageBox = await page.evaluate(() => { const r = document.querySelector('canvas.stage-canvas').getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height }; });
    const cx = stageBox.x + stageBox.w / 2, cy = stageBox.y + stageBox.h * 0.35;
    // one finger rotates
    const c0 = await cam();
    await touch('touchStart', [[cx - 60, cy]]);
    for (let i = 1; i <= 8; i++) { await touch('touchMove', [[cx - 60 + i * 15, cy]]); await sleep(16); }
    await touch('touchEnd', []);
    await sleep(500); await idle(page);
    const c1 = await cam();
    const moved = Math.hypot(c1.p[0] - c0.p[0], c1.p[2] - c0.p[2]);
    check('touch: one finger rotates (target unchanged, camera moved)', moved > 5 && Math.hypot(c1.t[0] - c0.t[0], c1.t[1] - c0.t[1]) < 0.5, JSON.stringify({ moved, c0t: c0.t, c1t: c1.t }));
    // pinch zooms
    const d0 = c1.d;
    await touch('touchStart', [[cx - 20, cy], [cx + 20, cy]]);
    for (let i = 1; i <= 8; i++) { await touch('touchMove', [[cx - 20 - i * 10, cy], [cx + 20 + i * 10, cy]]); await sleep(16); }
    await touch('touchEnd', []);
    await sleep(500); await idle(page);
    const c2 = await cam();
    check('touch: pinch out zooms in', c2.d < d0 - 5, JSON.stringify({ d0, d1: c2.d }));
    // two-finger drag pans
    const t0 = c2.t;
    await touch('touchStart', [[cx - 30, cy], [cx + 30, cy]]);
    for (let i = 1; i <= 8; i++) { await touch('touchMove', [[cx - 30, cy + i * 12], [cx + 30, cy + i * 12]]); await sleep(16); }
    await touch('touchEnd', []);
    await sleep(500); await idle(page);
    const c3 = await cam();
    check('touch: two fingers drag pans the target', Math.hypot(c3.t[0] - t0[0], c3.t[1] - t0[1], c3.t[2] - t0[2]) > 2, JSON.stringify({ t0, t1: c3.t }));
    // tap selects a tooth
    await page.evaluate(() => { window.App3DBridge.resetCamera(); window.App3DBridge.setCameraPreset('front'); });
    await idle(page);
    const pt = await page.evaluate(() => {
      const { camera } = window.__dental3d.stage;
      const o = window.__dental3d.registry.get('tooth_11');
      o.updateWorldMatrix(true, true);
      const v = o.localToWorld(o.position.clone().set(0, 4, 0)).project(camera);
      const r = document.querySelector('canvas.stage-canvas').getBoundingClientRect();
      return [r.left + ((v.x + 1) / 2) * r.width, r.top + ((1 - v.y) / 2) * r.height];
    });
    await touch('touchStart', [pt]);
    await sleep(40);
    await touch('touchEnd', []);
    await sleep(400);
    const sel = await page.evaluate(() => window.__dental3d.store.get().selectedId);
    check('touch: a tap on a tooth selects it', typeof sel === 'string' && sel.startsWith('tooth_'), `selected=${sel} at ${pt.map(Math.round)}`);
    await client.detach();
  }

  // 5. rotation: same page, swapped viewport
  if (mobile && w === 375) {
    await page.setViewport({ width: 812, height: 375, deviceScaleFactor: 1, isMobile: true, hasTouch: true });
    await sleep(500); await idle(page);
    const mr = await page.evaluate(MEASURE);
    check('rotation 375x812 -> 812x375: canvas resized to the new stage', Math.abs(mr.canvas.cw - mr.canvas.sw) <= 1 && mr.canvas.cw > 700 && !overlap(mr.toolbar, mr.timeline), JSON.stringify(mr.canvas));
  }
  await page.close();
}

await browser.close();
await closeServer();
console.log(`\n${pass} passed, ${fail} failed${fail ? ' -> ' + failures.join('; ') : ''}`);
process.exit(fail ? 1 : 0);
