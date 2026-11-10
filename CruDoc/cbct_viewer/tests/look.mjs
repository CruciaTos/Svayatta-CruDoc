// Looks and motion check for the 3D view: opens a scan, saves a picture of the
// 3D view for every look, traces a first drag frame by frame, and prints what
// the quality governor decided. Pictures land in tests/out/look-*.png.
//
//   node tests/look.mjs [--scan dev/phantom_big] [--dsf 1] [--kind ct]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from '@playwright/test';
import { createServer } from './serve.mjs';

const arg = (name, fallback) => {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : fallback;
};
const viewerRoot = fileURLToPath(new URL('..', import.meta.url));
const scan = path.resolve(viewerRoot, arg('scan', 'dev/phantom_big'));
const dsf = Number(arg('dsf', '1'));
const out = path.resolve(viewerRoot, 'tests/out');
fs.mkdirSync(out, { recursive: true });

const server = createServer({ phantom: scan });
const { base } = await server.start();
let browser;
try {
  browser = await chromium.launch({ channel: 'msedge', headless: true });
} catch {
  browser = await chromium.launch({ headless: true });
}
const ctx = await browser.newContext({ viewport: { width: 1440, height: 913 }, deviceScaleFactor: dsf });
const page = await ctx.newPage();
const logs = [];
const t0 = Date.now();
page.on('console', (m) => logs.push(`${Date.now() - t0} ${m.type()}: ${m.text()}`));
page.on('pageerror', (e) => logs.push(`${Date.now() - t0} PAGEERROR: ${e.message}`));
await page.addInitScript(() => {
  window.__long = [];
  let last = 0;
  const loop = (t) => {
    if (last && t - last > 50 && window.__trace) window.__long.push({ at: Math.round(t), ms: Math.round(t - last), ...(window.__cbct && window.__cbct.debug3d ? window.__cbct.debug3d() : {}) });
    last = t;
    requestAnimationFrame(loop);
  };
  requestAnimationFrame(loop);
});
await page.goto(`${base}index.html?debug=1&base=/phantom/&title=Look`);
for (let i = 0; i < 80 && !logs.some((l) => l.includes('"type":"full"')); i++) await page.waitForTimeout(250);
const opened = logs.some((l) => l.includes('"type":"full"'));
console.log(opened ? 'opened' : 'DID NOT OPEN');
if (!opened) console.log(logs.join('\n'));

const vpLoc = page.locator('.vp[data-id=threeD]');
const box = await vpLoc.boundingBox();
const cx = box.x + box.width / 2;
const cy = box.y + box.height / 2;
const dbg = () => page.evaluate(() => ({ lod: window.__cbct.lod, still: Math.round(window.__cbct.stillMs()), ...window.__cbct.debug3d() }));
const shot = async (name) => {
  await page.waitForTimeout(900);
  await vpLoc.screenshot({ path: path.join(out, `look-${name}.png`) });
};

// The first drag, one second after the scan is in: the moment most likely to stutter.
await page.waitForTimeout(1000);
console.log('before first drag', JSON.stringify(await dbg()));
await page.evaluate(() => (window.__trace = true));
await page.mouse.move(cx, cy);
await page.mouse.down();
for (let i = 0; i < 80; i++) {
  const a = (i / 80) * Math.PI * 2;
  await page.mouse.move(cx + Math.cos(a) * 60, cy + Math.sin(a) * 60);
  await page.waitForTimeout(16);
}
await page.mouse.up();
const long1 = await page.evaluate(() => {
  window.__trace = false;
  return window.__long.splice(0);
});
console.log(`first drag: ${long1.length} frames over 50 ms`, JSON.stringify(long1.slice(0, 12)));
await page.waitForTimeout(2500);
console.log('after first drag', JSON.stringify(await dbg()));

const kinds = await page.evaluate(() => [...document.querySelectorAll('.panel .chips')].pop() && [...[...document.querySelectorAll('.panel .chips')].pop().querySelectorAll('.chip')].map((b) => b.textContent));
console.log('3D looks:', kinds.join(', '));
for (let i = 0; i < kinds.length; i++) {
  await page.evaluate((n) => [...[...document.querySelectorAll('.panel .chips')].pop().querySelectorAll('.chip')][n].click(), i);
  await shot(`${i}-${kinds[i].replace(/[^a-z]+/gi, '_')}`);
}
await page.evaluate(() => [...[...document.querySelectorAll('.panel .chips')].pop().querySelectorAll('.chip')][0].click());

// Sliders: Threshold and Smooth rebuild the meshes once the slider rests.
const slide = (label, value) => page.evaluate(([l, v]) => {
  const row = [...document.querySelectorAll('.panel .prow')].find((r) => r.querySelector('label') && r.querySelector('label').textContent === l);
  const input = row && row.querySelector('input.range');
  if (!input) return false;
  input.value = String(v);
  input.dispatchEvent(new Event('input', { bubbles: true }));
  return true;
}, [label, value]);
const meshInfo = () => page.evaluate(() => { const d = window.__cbct.debug3d(); return `mesh=${d.mesh} tris=${d.tris} built in ${d.meshMs} ms grid=${d.grid}`; });
console.log('bone', await meshInfo());
for (const [label, value, name] of [['Smooth', 0, 'smooth-0'], ['Smooth', 100, 'smooth-100'], ['Smooth', 40, null], ['Threshold', 400, 'threshold-up'], ['Threshold', 0, null]]) {
  if (!(await slide(label, value))) console.log(`no ${label} slider`);
  await page.waitForTimeout(1200);
  if (name) {
    await shot(name);
    console.log(name, await meshInfo());
  }
}
// Cut at crosshair clips the meshes too (second cut mode, then back to Off).
const cutPick = (n) => page.evaluate((i) => [...document.querySelectorAll('.panel .seg')].pop().querySelectorAll('button')[i].click(), n);
await cutPick(1);
await shot('cut');
await cutPick(0);

// Zoom in and take the sharp picture, then a moving one.
await page.mouse.move(cx, cy);
for (let i = 0; i < 6; i++) {
  await page.mouse.wheel(0, -120);
  await page.waitForTimeout(60);
}
await page.waitForTimeout(2500);
await shot('zoom-still');
console.log('zoomed in', JSON.stringify(await dbg()));
await page.mouse.down();
await page.mouse.move(cx + 30, cy + 10, { steps: 6 });
await page.waitForTimeout(120);
await vpLoc.screenshot({ path: path.join(out, 'look-zoom-moving.png') });
await page.mouse.up();

// A gizmo letter turns the view.
const letter = page.locator('.gizmo circle').first();
await letter.click({ force: true });
await shot('gizmo-turn');
console.log('end', JSON.stringify(await dbg()));
const bad = logs.filter((l) => /PAGEERROR| error:|warning: CBCT/.test(l) && !l.includes('state.json') && !l.includes('404'));
console.log(bad.length ? `console problems:\n${bad.join('\n')}` : 'no console problems');

await browser.close();
await server.close();
