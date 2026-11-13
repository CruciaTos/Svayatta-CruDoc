// Treatment player: every treatment type plays all its steps, steps back exactly, restores the patient on close,
// and stops rendering when idle (headless Chrome, dev server).   node tests/player.mjs
import puppeteer from 'puppeteer-core';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const BASE = 'http://127.0.0.1:5174/';
let pass = 0, fail = 0;
const check = (name, ok, detail = '') => { if (ok) { pass++; console.log(`  ok   ${name}`); } else { fail++; console.log(`  FAIL ${name}  ${detail}`); } };
let closeServer = async () => { };
try { if (!(await fetch(BASE)).ok) throw 0; } catch {
  const { createServer } = await import('vite');
  const server = await createServer({ root, logLevel: 'error', server: { hmr: false, watch: null } });
  await server.listen();
  closeServer = () => server.close();
}
const browser = await puppeteer.launch({
  executablePath: CHROME, headless: 'new', defaultViewport: null, protocolTimeout: 600000,
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-webgl', '--no-sandbox', '--disable-dev-shm-usage'],
});
const page = await browser.newPage();
await page.setViewport({ width: 1280, height: 800, deviceScaleFactor: 1 });
const errors = [];
page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
await page.goto(`${BASE}?q=low`, { waitUntil: 'load' });
await page.waitForFunction('window.App3DBridge && window.__dental3d', { timeout: 120000 });
await page.evaluate('window.App3DBridge.ready');
const ev = (pg, fn, ...a) => pg.evaluate(fn, ...a);

// D3: every treatment type plays all its steps in order; going back restores the earlier look exactly;
// closing restores the patient's state; the render loop stops once a step has finished.
await ev(page, () => {
  const d = window.__dental3d;
  d.cameraRig.timeScale = 40;
  const r3 = (v) => Math.round(v * 1000) / 1000;
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const sig = () => {
    const s = d.store.get();
    const teeth = {};
    for (const [f, o] of d.registry.teeth) {
      const m = o.userData.meshes[0]?.userData?.natural;
      const u = m?.userData?.u;
      teeth[f] = JSON.stringify([
        o.visible, o.position.toArray().map(r3), o.quaternion.toArray().map(r3),
        o.children.map((c) => [c.userData.isTreatmentVisual ? 1 : 0, c.visible, c.position.toArray().map(r3)]),
        o.userData.meshes.map((x) => x.visible),
        u ? [u.uTint.value.toArray().map(r3), r3(u.uPrep.value), r3(u.uCalculus.value), u.uShade.value.toArray().map(r3),
          u.uSurfCaries.value.map(r3), u.uSurfFill.value.map((v) => v.toArray().map(r3)), u.uSurfMetal.value.map(r3)] : null,
        m ? [r3(m.roughness), r3(m.opacity), m.transparent] : null,
      ]);
    }
    const pulps = [...d.registry.pulps].map(([f, o]) => `${f}:${o.userData.matOverride ? 1 : 0}`).join(',');
    return { top: JSON.stringify({ mode: s.mode, layers: s.layers, preview: s.preview }), teeth, pulps };
  };
  const diff = (a, b2) => {
    if (a.top !== b2.top) return 'top ' + a.top + ' vs ' + b2.top;
    if (a.pulps !== b2.pulps) return 'pulps';
    for (const f of Object.keys(a.teeth)) if (a.teeth[f] !== b2.teeth[f]) return `tooth ${f}`;
    return null;
  };
  const settle = async () => {
    const t0 = performance.now();
    let lastFrames = window.__frames ?? d.stats().renderedFrames;
    let stableStart = performance.now();
    while (performance.now() - t0 < 15000) {
      await sleep(100);
      const cur = window.__frames ?? d.stats().renderedFrames;
      if (cur !== lastFrames) {
        lastFrames = cur;
        stableStart = performance.now();
      } else if (performance.now() - stableStart >= 1500 && d.flyDone()) {
        return true;
      }
    }
    return false;
  };
  window.__d3 = { sig, diff, settle };
});
const D3_CASES = [
  ['filling', { teeth: { 36: { conditions: [{ type: 'caries', surfaces: ['O'] }] } } }, { teeth: [36], surfaces: ['O'], material: 'composite' }],
  ['sealant', {}, { teeth: [16], material: 'composite' }],
  ['bonding', {}, { teeth: [21], material: 'composite' }],
  ['rct', {}, { teeth: [11], material: 'guttaPercha' }],
  ['crown', {}, { teeth: [11], material: 'zirconia' }],
  ['veneer', {}, { teeth: [12], material: 'emax' }],
  ['extraction', {}, { teeth: [48] }],
  ['implant', { teeth: { 46: { present: false } } }, { teeth: [46], material: 'zirconia' }],
  ['bridge', { teeth: { 36: { present: false } } }, { teeth: [35, 36, 37], material: 'zirconia' }],
  ['scaling', {}, { arches: ['upper', 'lower'] }],
  ['whitening', {}, { arches: ['upper', 'lower'] }],
  ['braces', {}, { arches: ['upper', 'lower'] }],
];
const d3 = [];
for (const [type, extra, tr] of D3_CASES) {
  d3.push(await ev(page, async (type, extra, tr) => {
    const b = window.App3DBridge;
    const d = window.__dental3d;
    const { sig, diff, settle } = window.__d3;
    b.loadPreset('healthy');
    b.selectPart(null);
    const id = 't_d3_' + type;
    b.applyStateSnapshot({ ...extra, treatments: [{ id, type, visit: 1, status: 'planned', ...tr }] });
    await settle();
    const base = sig();
    const startPos = d.stage.camera.position.clone();
    b.playExplainer(id);
    const started = d.player.isPlaying;
    await settle();
    const n = document.querySelectorAll('.explainer-dot').length;
    const fwd = [sig()];
    let settledAll = true;
    for (let k = 1; k < n; k++) { d.player.next(); settledAll = (await settle()) && settledAll; fwd.push(sig()); }
    const backDiffs = [];
    for (let k = n - 2; k >= 0; k--) { d.player.prev(); await settle(); const dd = diff(fwd[k], sig()); if (dd) backDiffs.push(`step ${k + 1}: ${dd}`); }
    b.closeExplainer();
    await settle();
    return { type, started, steps: n, settledAll, backDiffs, closeDiff: diff(base, sig()), camBack: d.stage.camera.position.distanceTo(startPos) < 0.01, playing: d.player.isPlaying };
  }, type, extra, tr));
}
await ev(page, () => window.App3DBridge.loadPreset('healthy'));
const d3Bad = d3.filter((r) => !r.started || r.steps < 2 || !r.settledAll || r.backDiffs.length || r.closeDiff || !r.camBack || r.playing);
check('D3: every treatment plays all its steps, steps back exactly, restores the patient on close, and stops rendering when idle',
  d3.length === 12 && d3Bad.length === 0 && errors.length === 0,
  JSON.stringify({ bad: d3Bad, errors: errors.slice(0, 3) }));


await browser.close();
await closeServer();
console.log(`
${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
