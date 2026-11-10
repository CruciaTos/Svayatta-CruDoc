// Implant plan check: trace a nerve in the sagittal view, add an implant above
// it, lengthen it toward the nerve, reload and check the plan was saved.
// Pictures land in tests/out/plan-*.png.
//
//   node tests/plan.mjs [--scan dev/phantom_big]
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
const page = await (await browser.newContext({ viewport: { width: 1440, height: 913 } })).newPage();
const logs = [];
page.on('console', (m) => logs.push(`${m.type()}: ${m.text()}`));
page.on('pageerror', (e) => logs.push(`PAGEERROR: ${e.message}`));
let failures = 0;
const check = (name, ok, extra = '') => {
  if (!ok) failures++;
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${extra ? `  (${extra})` : ''}`);
};
const open = async () => {
  logs.length = 0;
  await page.goto(`${base}index.html?debug=1&base=/phantom/&title=Plan`);
  for (let i = 0; i < 80 && !logs.some((l) => l.includes('"type":"full"')); i++) await page.waitForTimeout(250);
  await page.waitForTimeout(800);
};
const note = () => page.evaluate(() => [...document.querySelectorAll('.panel .pnote')].map((p) => p.textContent).join(' | '));
const clickButton = (text) => page.evaluate((t) => [...document.querySelectorAll('.panel button')].find((b) => b.textContent === t).click(), text);

await open();
check('plan section shown', await page.evaluate(() => [...document.querySelectorAll('.panel h3')].some((x) => x.textContent === 'Implant plan')));

const sag = await page.locator('.vp[data-id=sagittal]').boundingBox();
// Manual tracing first (Auto-follow off): every click is one point.
await clickButton('Auto-follow');
await page.keyboard.press('n');
check('N starts tracing', (await page.evaluate(() => window.__cbct.state.tool)) === 'nerve');
for (const fx of [0.3, 0.42, 0.55, 0.7]) {
  await page.mouse.click(sag.x + sag.width * fx, sag.y + sag.height * 0.72);
  await page.waitForTimeout(120);
}
const pts = await page.evaluate(() => window.__cbct.state.plan.nerves.right.length);
check('four nerve points', pts === 4, `${pts}`);
await page.keyboard.press('Backspace');
check('Backspace removes one', (await page.evaluate(() => window.__cbct.state.plan.nerves.right.length)) === 3);
await page.mouse.click(sag.x + sag.width * 0.7, sag.y + sag.height * 0.72);

await page.keyboard.press('c');
// The crosshair 8 mm above the middle (the crosshair tool moves by dragging, so set it directly).
await page.evaluate(() => {
  const ch = window.__cbct.core.crosshair;
  const c = ch.toolCenter;
  ch.setToolCenter([c[0], c[1], c[2] + 8]);
});
await page.waitForTimeout(300);
await clickButton('Add at crosshair');
await page.waitForTimeout(400);
const first = await note();
check('implant added with a distance', /To the nerve canal: -?\d/.test(first), first);
await page.screenshot({ path: path.join(out, 'plan-full.png') });

// Lower jaw (apex down, toward the nerve), then lengthen to 16 mm: the distance must shrink.
await clickButton('Lower jaw');
await page.waitForTimeout(200);
const first2 = await note();
await page.evaluate(() => {
  const row = [...document.querySelectorAll('.panel .prow')].find((r) => r.querySelector('label') && r.querySelector('label').textContent === 'Length');
  const input = row.querySelector('input.range');
  input.value = '16';
  input.dispatchEvent(new Event('input', { bubbles: true }));
});
await page.waitForTimeout(400);
const longer = await note();
const mm = (s) => Number((s.match(/To the nerve canal: (-?[\d.]+)/) || [])[1]);
check('longer implant is closer to the nerve', mm(longer) < mm(first2), `${mm(first2)} -> ${mm(longer)}`);
// Bone measurements and Suggest size.
const site = await note();
check('bone measurements shown', /Bone width|No bone found/.test(site), site.slice(0, 160));
await clickButton('Suggest size');
await page.waitForTimeout(300);
const sized = await page.evaluate(() => window.__cbct.state.plan.implants[0]);
check('Suggest size picks a standard size', [3, 3.3, 3.5, 4, 4.5, 5, 5.5, 6].includes(sized.diameter) && [6, 7, 8, 8.5, 10, 11.5, 13, 14, 16].includes(sized.length), `${sized.diameter} x ${sized.length}`);
console.log('  after suggest:', (await note()).slice(0, 300));
await page.locator('.vp[data-id=threeD]').screenshot({ path: path.join(out, 'plan-3d.png') });

// A second implant 2 mm above the top of a bone block: real bone numbers.
const spot = await page.evaluate(() => {
  const { core } = window.__cbct;
  const g = core.geo;
  const [nx, ny, nz] = g.dims;
  const L = core.meta.landmarks;
  const j = Math.floor(ny / 2);
  for (let i = 0; i < nx; i += 4) {
    for (let k = nz - 1; k >= 0; k--) {
      const v = core.voxels[i + nx * (j + ny * k)] + core.valueOffset;
      if (v >= L.bone && v < L.teeth) {
        const a = [g.direction[6], g.direction[7], g.direction[8]];
        const p = [0, 1, 2].map((q) => g.origin[q] + g.direction[q] * i * g.spacing[0] + g.direction[3 + q] * j * g.spacing[1] + a[q] * k * g.spacing[2]);
        return [p[0], p[1], p[2] + 2];
      }
    }
  }
  return null;
});
if (spot) {
  await page.evaluate((p) => window.__cbct.core.crosshair.setToolCenter(p), spot);
  await page.waitForTimeout(200);
  await clickButton('Add at crosshair');
  await clickButton('Lower jaw');
  await page.waitForTimeout(300);
  const boneNote = await note();
  check('bone numbers at a bone site', /Bone width: \d/.test(boneNote) && /above the crest/.test(boneNote), boneNote.slice(0, 260));
  await clickButton('Suggest size');
  await page.waitForTimeout(300);
  console.log('  site 2 after suggest:', (await note()).slice(0, 300), JSON.stringify(await page.evaluate(() => window.__cbct.state.plan.implants[1])).slice(0, 200));
  await page.locator('.vp[data-id=coronal]').screenshot({ path: path.join(out, 'plan-site2.png') });
  await clickButton('Delete');
} else check('a bone block in the test scan', false);

// Automatic boxes around dense objects.
const found = await page.evaluate(() => window.__cbct.foundBoxes().map((b) => b.sizeMm.map((x) => +x.toFixed(1))));
check('dense objects boxed automatically', found.length > 0, JSON.stringify(found.slice(0, 4)));
check('found section shown', await page.evaluate(() => [...document.querySelectorAll('.panel h3')].some((x) => x.textContent === 'Found automatically')));
if (found.length) {
  await page.evaluate(() => [...document.querySelectorAll('.panel .chip')].find((b) => b.textContent.startsWith('M1 ')).click());
  await page.waitForTimeout(500);
  await page.locator('.vp[data-id=coronal]').screenshot({ path: path.join(out, 'plan-found.png') });
}

// Auto-follow on: two clicks give the start, the end and points between.
await clickButton('Auto-follow');
await page.evaluate(() => [...document.querySelectorAll('.panel button')].find((b) => b.textContent === 'Left').click());
await page.keyboard.press('n');
await page.mouse.click(sag.x + sag.width * 0.3, sag.y + sag.height * 0.5);
await page.mouse.click(sag.x + sag.width * 0.7, sag.y + sag.height * 0.5);
await page.waitForTimeout(300);
const left = await page.evaluate(() => window.__cbct.state.plan.nerves.left.length);
check('Auto-follow adds points between two clicks', left >= 2, `${left} points`);
await page.keyboard.press('Backspace');
check('Backspace undoes the whole followed piece', (await page.evaluate(() => window.__cbct.state.plan.nerves.left.length)) === 1);
await page.keyboard.press('c');
await page.locator('.vp[data-id=sagittal]').screenshot({ path: path.join(out, 'plan-sagittal.png') });

// Saved with the scan: the autosave (after 2 s) writes the plan into state.json.
const put = await page.waitForRequest((r) => r.method() === 'PUT' && r.url().includes('state.json'), { timeout: 6000 }).catch(() => null);
const body = put ? JSON.parse(put.postData() || '{}') : {};
const saved = body.plan ? { n: body.plan.nerves.right.length, i: body.plan.implants.length, len: body.plan.implants[0] && body.plan.implants[0].length } : null;
check('plan saved in state.json', !!saved && saved.n === 4 && saved.i === 1 && saved.len === sized.length, JSON.stringify(saved));

const bad = logs.filter((l) => /PAGEERROR|^error:|warning: CBCT/.test(l) && !l.includes('state.json') && !l.includes('404'));
console.log(bad.length ? `console problems:\n${bad.join('\n')}` : 'no console problems');
console.log(failures ? `PLAN: ${failures} FAILED` : 'PLAN: ALL PASS');
await browser.close();
await server.close();
process.exit(failures ? 1 : 0);
