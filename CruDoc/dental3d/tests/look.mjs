// Look pass: captures gum / tooth screenshots into tmp/shots/look/ (dev server started here if needed).
//   node tests/look.mjs [name,name,...]   (default: all)
import puppeteer from 'puppeteer-core';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..');
const out = path.join(root, 'tmp', 'shots', 'look');
fs.mkdirSync(out, { recursive: true });
const only = process.argv[2] ? new Set(process.argv[2].split(',')) : null;
const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const BASE = 'http://127.0.0.1:5174/';
let closeServer = async () => {};
try { if (!(await fetch(BASE)).ok) throw 0; } catch {
  const { createServer } = await import('vite');
  const server = await createServer({ root, logLevel: 'error' });
  await server.listen();
  closeServer = () => server.close();
}
const browser = await puppeteer.launch({
  executablePath: CHROME, headless: 'new', defaultViewport: null,
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-webgl', '--no-sandbox', '--disable-dev-shm-usage'],
});

async function open(viewport, mobile = false) {
  const page = await browser.newPage();
  await page.setViewport({ ...viewport, deviceScaleFactor: 1, isMobile: mobile, hasTouch: mobile });
  const errors = [];
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  page.on('console', (m) => { if (m.type() === 'error' || (m.type() === 'warning' && /webgl|shader|program|glsl/i.test(m.text()))) errors.push(m.text()); });
  await page.goto(`${BASE}?q=${process.env.Q || 'medium'}`, { waitUntil: 'load' });
  await page.waitForFunction('window.App3DBridge && window.__dental3d', { timeout: 120000 });
  await page.evaluate('window.App3DBridge.ready');
  return { page, errors };
}
const idle = (page) => page.evaluate(async () => {
  const t0 = performance.now(); let last = -1, lc = performance.now();
  while (performance.now() - t0 < 90000) {
    await new Promise((r) => setTimeout(r, 80));
    const n = window.__dental3d.stats().renderedFrames;
    if (n !== last) { last = n; lc = performance.now(); }
    if (performance.now() - lc > 500 && window.__dental3d.flyDone()) return n;
  }
  return -1;
});
const shot = async (page, name) => { await idle(page); await page.screenshot({ path: path.join(out, name) }); console.log('shot', name); };
const want = (n) => !only || only.has(n);

const { page, errors } = await open({ width: 1280, height: 800 });
await page.evaluate(() => { document.querySelector('.inspector')?.remove(); document.querySelectorAll('.timeline-bar').forEach((e) => e.remove()); });
const ev = (fn, ...a) => page.evaluate(fn, ...a);
// hide the side panel so the stage is wide; refit
await ev(() => { window.__dental3d.stage.resize(); });

const view = async (preset, style) => {
  await ev((p, s) => { const b = window.App3DBridge; b.setMode('pbr'); b.selectPart(null); b.setLayer('gums', true); b.setGumStyle(s); b.setCameraPreset(p); }, preset, style);
  await idle(page);
};
if (want('front-solid')) { await view('front', 'solid'); await shot(page, 'front-solid.png'); }
if (want('threequarter-solid') || want('threequarter-glass')) {
  for (const s of ['solid', 'glass']) {
    if (!want('threequarter-' + s)) continue;
    await view('front', s);
    await ev(() => {
      const { camera, controls } = window.__dental3d.stage;
      const t = controls.target.clone(); const d = camera.position.distanceTo(t);
      const ang = 0.62; camera.position.set(t.x + Math.sin(ang) * d, t.y + d * 0.12, t.z + Math.cos(ang) * d); controls.update();
    });
    await shot(page, `threequarter-${s}.png`);
  }
}
if (want('front-glass')) { await view('front', 'glass'); await shot(page, 'front-glass.png'); }
if (want('gum-closeup')) {
  await view('front', 'solid');
  await ev(() => {
    const d = window.__dental3d; const p = d.registry.get('tooth_11').userData.rest.p; const { camera, controls } = d.stage;
    controls.target.set(p.x + 2, p.y - 1, p.z); camera.position.set(p.x + 2, p.y + 2, p.z + 35); controls.update(); d.stage.invalidate();
  });
  await shot(page, 'gum-closeup.png');
}
if (want('lower-front')) {
  await view('front', 'solid');
  await ev(() => {
    const d = window.__dental3d; const p = d.registry.get('tooth_41').userData.rest.p; const { camera, controls } = d.stage;
    controls.target.set(p.x, p.y, p.z); camera.position.set(p.x + 20, p.y - 6, p.z + 90); controls.update(); d.stage.invalidate();
  });
  await shot(page, 'lower-front.png');
}
if (want('missing-tooth')) {
  await view('front', 'solid');
  await ev(() => {
    window.App3DBridge.applyStateSnapshot({ teeth: { 11: { present: false } } });
    const d = window.__dental3d; const p = d.registry.get('tooth_11').userData.rest.p; const { camera, controls } = d.stage;
    controls.target.set(p.x, p.y, p.z); camera.position.set(p.x + 6, p.y - 2, p.z + 70); controls.update(); d.stage.invalidate();
  });
  await shot(page, 'missing-tooth.png');
  await ev(() => window.App3DBridge.applyStateSnapshot({ teeth: { 11: { present: true } } }));
}
if (want('upper-occlusal')) {
  await view('upper', 'solid');
  await shot(page, 'upper-occlusal.png');
}
if (want('side-glass')) {
  await view('left', 'glass');
  await shot(page, 'side-glass.png');
}
console.log('desktop errors:', errors.length ? errors.slice(0, 5).join(' || ') : 'none');
await page.close();

if (want('phone-glass')) {
  const P = await open({ width: 390, height: 844 }, true);
  await P.page.evaluate(() => { window.App3DBridge.setGumStyle('glass'); window.App3DBridge.setCameraPreset('front'); });
  await shot(P.page, 'phone-glass.png');
  console.log('phone errors:', P.errors.length ? P.errors.slice(0, 5).join(' || ') : 'none');
  await P.page.close();
}
await browser.close();
await closeServer();
