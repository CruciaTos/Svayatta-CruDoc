// Panoramic view check: the arch is found after the full scan arrives, the viewer keeps
// drawing while it is built, the Coronal slot switches to the panoramic picture, a click
// moves the marker and the crosshair, arrow keys step along the arch, and Copy summary works.
// Pictures land in tests/out/pano-*.png.
//
//   node tests/panoramic.mjs [--scan dev/phantom_big]
//
// A scan without a dental arch only has to show the plain message (and never crash).
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
const context = await browser.newContext({ viewport: { width: 1440, height: 913 } });
await context.grantPermissions(['clipboard-read', 'clipboard-write']).catch(() => {});
const page = await context.newPage();
const logs = [];
page.on('console', (m) => logs.push(`${m.type()}: ${m.text()}`));
page.on('pageerror', (e) => logs.push(`PAGEERROR: ${e.message}`));
let failures = 0;
const check = (name, ok, extra = '') => {
  if (!ok) failures++;
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${extra ? `  (${extra})` : ''}`);
};
// Frame gaps: how long the page went without drawing.
await page.addInitScript(() => {
  window.__gaps = [];
  let last = performance.now();
  const tick = (t) => {
    window.__gaps.push([t, t - last]);
    last = t;
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
});

await page.goto(`${base}index.html?debug=1&base=/phantom/&title=Pano`);
for (let i = 0; i < 80 && !logs.some((l) => l.includes('"type":"full"')); i++) await page.waitForTimeout(250);
const fullAt = await page.evaluate(() => performance.now());
const state = () => page.evaluate(() => window.__cbct.panoState());
let st = await state();
for (let i = 0; i < 120 && (st.status === 'idle' || st.status === 'busy'); i++) {
  await page.waitForTimeout(250);
  st = await state();
}
const doneAt = await page.evaluate(() => performance.now());
const worst = await page.evaluate(([a, b]) => Math.max(0, ...window.__gaps.filter(([t]) => t >= a && t <= b).map(([, d]) => d)), [fullAt, doneAt]);
console.log(`  panoramic ${st.status} after ${Math.round(doneAt - fullAt)} ms, arch ${st.length.toFixed(1)} mm, picture ${st.columns} x ${st.rows}, worst frame gap ${Math.round(worst)} ms`);
check('panoramic finished (picture or plain message)', st.status === 'ready' || st.status === 'none', st.status);
check('the viewer kept drawing while it was built (no gap over 100 ms)', worst < 100, `${Math.round(worst)} ms`);

const slot = page.locator('.vp[data-id=coronal]');
const btn = slot.locator('.vpbtns button[aria-label="Panoramic view"]');
check('panoramic button in the Coronal slot', (await btn.count()) === 1);
await btn.click();
await page.waitForTimeout(300);
check('slot switched to panoramic', await page.evaluate(() => document.querySelector('.vp[data-id=coronal]').classList.contains('pano-on')));
check('pill says Panoramic', (await slot.locator('.pill .name').textContent()) === 'Panoramic');

if (st.status === 'none') {
  const msg = await slot.locator('.pano-msg').textContent();
  check('plain message when there is no arch', /arch|tooth/i.test(msg), msg);
  await slot.screenshot({ path: path.join(out, 'pano-none.png') });
} else {
  const sizes = await page.evaluate(() => {
    const c = document.querySelectorAll('.pano canvas');
    return [...c].map((x) => [x.width, x.height]);
  });
  check('both pictures drawn', sizes.length === 2 && sizes.every(([w, h]) => w > 10 && h > 10), JSON.stringify(sizes));
  const lit = await page.evaluate(() => {
    const c = document.querySelector('.pano canvas');
    const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
    let min = 255, max = 0;
    for (let i = 0; i < d.length; i += 4 * 17) { min = Math.min(min, d[i]); max = Math.max(max, d[i]); }
    return [min, max];
  });
  check('panoramic picture has contrast', lit[1] - lit[0] > 60, JSON.stringify(lit));
  await slot.screenshot({ path: path.join(out, 'pano-view.png') });

  // Window / level follows the slices: the preset buttons change the picture.
  const grey = () => page.evaluate(() => {
    const c = document.querySelector('.pano canvas');
    const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
    let s = 0;
    for (let i = 0; i < d.length; i += 4 * 13) s += d[i];
    return s;
  });
  const before = await grey();
  await page.evaluate(() => [...document.querySelectorAll('.panel .chip')].find((b) => b.textContent.startsWith('Soft tissue')).click());
  await page.waitForTimeout(300);
  check('window / level changes the picture', (await grey()) !== before);
  await page.evaluate(() => [...document.querySelectorAll('.panel .chip')].find((b) => b.textContent.startsWith('Bone')).click());

  // Click on the picture: marker moves, crosshair goes to that point on the arch.
  const cell = await page.locator('.pano .pcell.pick').boundingBox();
  const s0 = (await state()).sMm;
  await page.mouse.click(cell.x + cell.width * 0.25, cell.y + cell.height * 0.5);
  await page.waitForTimeout(300);
  const a = await state();
  check('click moves the marker along the arch', Math.abs(a.sMm - s0) > 3, `${s0.toFixed(1)} -> ${a.sMm.toFixed(1)} mm`);
  const ch = await page.evaluate(() => [...window.__cbct.core.crosshair.toolCenter]);
  const dxy = Math.hypot(ch[0] - a.point[0], ch[1] - a.point[1]);
  check('crosshair moved to the clicked point', dxy < 0.6, `${dxy.toFixed(2)} mm in the plane, z ${ch[2].toFixed(1)} vs row ${a.rowMm.toFixed(1)}`);
  check('cross-section shown', !!a.cross && a.cross[0] > 20, JSON.stringify(a.cross));
  const markerX = await page.evaluate(() => document.querySelector('.pano .pcell.pick svg line:last-child').getAttribute('x1'));
  check('marker drawn on the panoramic', Math.abs(Number(markerX) - (a.col + 0.5)) < 0.01, `x ${markerX}, col ${a.col}`);

  // Arrow keys: about 1 mm each.
  await page.mouse.move(cell.x + cell.width * 0.5, cell.y + cell.height * 0.5);
  for (let i = 0; i < 3; i++) await page.keyboard.press('ArrowRight');
  await page.waitForTimeout(250);
  const b = await state();
  check('ArrowRight x3 steps about 3 mm', Math.abs(b.sMm - a.sMm - 3) < 0.6, `${(b.sMm - a.sMm).toFixed(2)} mm`);
  await page.keyboard.press('ArrowLeft');
  await page.waitForTimeout(150);
  const c = await state();
  check('ArrowLeft steps back about 1 mm', Math.abs(b.sMm - c.sMm - 1) < 0.3, `${(b.sMm - c.sMm).toFixed(2)} mm`);
  // Past the ends it stops.
  for (let i = 0; i < 4; i++) await page.keyboard.press('PageDown');
  await page.evaluate(() => window.__cbct.panoSelect(-50));
  check('marker stops at the start of the arch', (await state()).col === 0);
  await page.evaluate(() => window.__cbct.panoSelect(1e6));
  const end = await state();
  check('marker stops at the end of the arch', end.col === end.columns - 1);
  await page.evaluate((n) => window.__cbct.panoSelect(n / 2), end.columns);
  await page.waitForTimeout(300);
  await slot.screenshot({ path: path.join(out, 'pano-cross.png') });
}

if (st.status === 'ready') {
  // The marker follows the crosshair when it moves elsewhere (another view, a click in the slices).
  await page.evaluate(() => window.__cbct.panoSelect(40));
  const p40 = (await state()).point;
  await page.evaluate(() => window.__cbct.panoSelect(8));
  await page.waitForTimeout(700); // the marker ignores the crosshair's own move for a moment
  await page.evaluate((p) => window.__cbct.core.crosshair.setToolCenter(p), p40);
  await page.waitForTimeout(400);
  check('marker follows the crosshair', (await state()).col === 40, `col ${(await state()).col}`);
  // A crosshair further from the arch than the cross-section is wide: the marker stays.
  await page.evaluate((p) => window.__cbct.core.crosshair.setToolCenter([p[0], p[1] + (p[1] > 0 ? -17 : 17), p[2]]), p40);
  await page.waitForTimeout(400);
  check('marker stays when the crosshair is far from the arch', (await state()).col === 40, `col ${(await state()).col}`);

  // Nerve canal and an implant on both pictures.
  const pts = [];
  for (const c of [5, 30, 55]) {
    await page.evaluate((n) => window.__cbct.panoSelect(n), c);
    pts.push((await state()).point);
  }
  await page.evaluate((p) => window.__cbct.set({ plan: { nerves: { right: p, left: [] } } }), pts);
  await page.waitForTimeout(300);
  const count = (sel) => page.evaluate((s) => document.querySelectorAll(s).length, sel);
  check('nerve canal drawn on the panoramic', (await count('.pano .pcell.pick g.plan polyline')) >= 1);
  check('nerve canal cut shown on the cross-section', (await count('.pano .pcell:not(.pick) g.plan circle')) >= 1);
  await page.evaluate((p) => window.__cbct.set({ plan: { implants: [{ top: p, diameter: 4, length: 10, jaw: 'lower', tiltAP: 0, tiltLR: 0 }], selected: 0 } }), pts[1]);
  await page.waitForTimeout(300);
  check('implant drawn on the panoramic', (await count('.pano .pcell.pick g.plan polygon, .pano .pcell.pick g.plan circle')) >= 1);
  check('implant drawn on the cross-section', (await count('.pano .pcell:not(.pick) g.plan polygon')) >= 1);
  await slot.screenshot({ path: path.join(out, 'pano-plan.png') });

  // Drag an implant on the panoramic. A second implant is selected first, so the drag must select the grabbed one.
  await page.evaluate(([p0, p1]) => window.__cbct.set({ plan: { implants: [{ top: p0, diameter: 4, length: 10, jaw: 'lower', tiltAP: 6, tiltLR: -4 }, { top: p1, diameter: 4, length: 10, jaw: 'lower', tiltAP: 0, tiltLR: 0 }], selected: 1 } }), [pts[1], pts[2]]);
  await page.waitForTimeout(300);
  const implants = () => page.evaluate(() => window.__cbct.state.plan.implants.map((im) => ({ top: [...im.top], length: im.length, diameter: im.diameter, tiltAP: im.tiltAP, tiltLR: im.tiltLR })));
  const sc = (await state());
  const ptr = await page.evaluate(() => {
    const cellR = document.querySelector('.pano .pcell.pick').getBoundingClientRect();
    const w = window.__cbct.panoState();
    const r = document.querySelector('.pano .pcell.pick g.plan polygon').getBoundingClientRect();
    return { s: Math.min(cellR.width / w.columns, cellR.height / w.rows), x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  const before = await implants();
  const loc0 = await page.evaluate((q) => window.__cbct.panoLocate(q), before[0].top);
  const COLS = 10;
  const ROWS = 8;
  await page.mouse.move(ptr.x, ptr.y);
  check('cursor is grab over an implant', await page.evaluate(() => document.querySelector('.pano .pcell.pick').classList.contains('grab')));
  await page.mouse.down();
  await page.mouse.move(ptr.x + (COLS * ptr.s) / 2, ptr.y + (ROWS * ptr.s) / 2, { steps: 4 });
  await page.mouse.move(ptr.x + COLS * ptr.s, ptr.y + ROWS * ptr.s, { steps: 4 });
  await page.waitForTimeout(200);
  check('cursor is grabbing during the drag', await page.evaluate(() => document.querySelector('.pano .pcell.pick').classList.contains('grabbing')));
  await page.mouse.up();
  await page.waitForTimeout(200);
  const after = await implants();
  const loc1 = await page.evaluate((q) => window.__cbct.panoLocate(q), after[0].top);
  const lenNow = (im) => Math.hypot(...im.top.map((v, i) => v - before[0].top[i]));
  check('dragging an implant selected it', (await page.evaluate(() => window.__cbct.state.plan.selected)) === 0);
  check('drag moved the implant along the arch by the dragged columns', Math.abs(loc1.col - loc0.col - COLS) <= 1, `${loc0.col} -> ${loc1.col}`);
  check('drag moved the implant down by the dragged rows', Math.abs(after[0].top[2] - before[0].top[2] + ROWS * sc.step) < 0.3, `${(after[0].top[2] - before[0].top[2]).toFixed(2)} mm, expected ${(-ROWS * sc.step).toFixed(2)}`);
  check('drag kept the side offset', Math.abs(loc1.lateral - loc0.lateral) < 0.3, `${loc0.lateral.toFixed(2)} -> ${loc1.lateral.toFixed(2)} mm`);
  check('drag kept length, diameter and tilts', after[0].length === 10 && after[0].diameter === 4 && after[0].tiltAP === 6 && after[0].tiltLR === -4);
  check('drag did not touch the other implant', JSON.stringify(after[1]) === JSON.stringify(before[1]));
  check('drag did not move the marker', (await state()).col === sc.col);
  check('implant really moved', lenNow(after[0]) > 2, `${lenNow(after[0]).toFixed(2)} mm`);

  // Escape during a drag puts it back.
  const mid = await page.evaluate(() => {
    const r = document.querySelector('.pano .pcell.pick g.plan polygon').getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  await page.mouse.move(mid.x, mid.y);
  await page.mouse.down();
  await page.mouse.move(mid.x - 6 * ptr.s, mid.y - 5 * ptr.s, { steps: 4 });
  await page.waitForTimeout(150);
  const moving = await implants();
  check('implant follows the drag before Escape', moving[0].top.some((v, i) => Math.abs(v - after[0].top[i]) > 0.5));
  await page.keyboard.press('Escape');
  await page.mouse.move(mid.x - 8 * ptr.s, mid.y, { steps: 2 });
  await page.mouse.up();
  await page.waitForTimeout(150);
  check('Escape restored the implant', JSON.stringify((await implants())[0].top) === JSON.stringify(after[0].top));

  // A click on empty picture still moves the marker.
  const cellBox = await page.locator('.pano .pcell.pick').boundingBox();
  const colBefore = (await state()).col;
  await page.mouse.click(cellBox.x + cellBox.width * 0.9, cellBox.y + cellBox.height * 0.1);
  await page.waitForTimeout(200);
  check('click on empty picture still moves the marker', (await state()).col !== colBefore);
  check('and leaves the implants alone', JSON.stringify(await implants()) === JSON.stringify(after));

  // Slab thickness: rebuilds the picture only, keeps the marker, plan uses the new slab.
  const slabBtn = slot.locator('.vpbtns button[aria-label="Slab thickness"]');
  check('slab button shows the default 10 mm', (await slabBtn.textContent()) === '10 mm');
  const stBefore = await state();
  const sumOf = () => page.evaluate(() => {
    const c = document.querySelector('.pano canvas');
    const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
    let s = 0;
    for (let i = 0; i < d.length; i += 4 * 7) s += d[i];
    return s;
  });
  const sum10 = await sumOf();
  await slabBtn.click();
  for (let i = 0; i < 60 && (await state()).thickness !== 20; i++) await page.waitForTimeout(100);
  const st20 = await state();
  check('slab button cycles to 20 mm and the picture is rebuilt with it', st20.thickness === 20 && (await slabBtn.textContent()) === '20 mm', `${st20.thickness}`);
  check('slab change keeps the marker, the arch and the picture size', st20.col === stBefore.col && st20.rowMm === stBefore.rowMm && st20.columns === stBefore.columns && st20.rows === stBefore.rows && st20.length === stBefore.length);
  await page.waitForTimeout(200);
  check('picture changed with the slab', (await sumOf()) !== sum10);
  // Two quick clicks: the first build is cancelled, the last choice wins.
  await slabBtn.click();
  await slabBtn.click();
  for (let i = 0; i < 80 && (await state()).thickness !== 5; i++) await page.waitForTimeout(100);
  const st5 = await state();
  check('quick clicks: the last slab (5 mm) wins', st5.thickness === 5 && st5.wantedThickness === 5, `${st5.thickness} / ${st5.wantedThickness}`);
  check('marker still where it was', st5.col === stBefore.col && st5.rowMm === stBefore.rowMm);
  // The plan overlay follows the slab: an implant 8 mm to the side of the arch is cut by a 20 mm slab, not by a 5 mm one.
  const sidePt = await page.evaluate(() => {
    const w = window.__cbct.panoState();
    return [0, 1, 2].map((k) => w.point[k] + w.normal[k] * 8);
  });
  await page.evaluate((p) => window.__cbct.set({ plan: { nerves: { right: [], left: [] }, implants: [{ top: p, diameter: 4, length: 10, jaw: 'lower', tiltAP: 0, tiltLR: 0 }], selected: 0 } }), sidePt);
  const fillNow = async () => {
    await page.waitForTimeout(200);
    return page.evaluate(() => {
      const el = document.querySelector('.pano .pcell.pick g.plan polygon');
      return el ? Number(el.getAttribute('fill-opacity')) : null;
    });
  };
  const thin = await fillNow(); // slab is 5 mm
  await page.evaluate(() => window.__cbct.panoSetSlab(20));
  for (let i = 0; i < 80 && (await state()).thickness !== 20; i++) await page.waitForTimeout(100);
  const thick = await fillNow();
  check('implant beside the arch is faint in a 5 mm slab and filled in a 20 mm slab', thin === 0.08 && thick === 0.3, `${thin} -> ${thick}`);
  await page.evaluate(() => window.__cbct.panoSetSlab(10));
  for (let i = 0; i < 80 && (await state()).thickness !== 10; i++) await page.waitForTimeout(100);
  check('slab back to 10 mm', (await state()).thickness === 10 && (await slabBtn.textContent()) === '10 mm');

  await page.evaluate(() => window.__cbct.set({ plan: { nerves: { right: [], left: [] }, implants: [], selected: -1 } }));
  await page.waitForTimeout(200);
  check('plan removed from the pictures', (await count('.pano g.plan *')) === 0);

  // Reset on the slot: back to the middle of the arch (and the hidden coronal view is left alone).
  await page.evaluate(() => window.__cbct.panoSelect(3));
  const camBefore = await page.evaluate(() => JSON.stringify(window.__cbct.core.engine.getViewport('coronal').getCamera().parallelScale));
  await slot.locator('.vpbtns button[aria-label="Reset this view"]').click();
  await page.waitForTimeout(300);
  const home = await state();
  check('Reset on the slot returns to the middle of the arch', home.col === home.home, `col ${home.col}, home ${home.home}`);
  check('Reset left the hidden coronal view alone', (await page.evaluate(() => JSON.stringify(window.__cbct.core.engine.getViewport('coronal').getCamera().parallelScale))) === camBefore);
}

// Back to the Coronal slice view.
await btn.click();
await page.waitForTimeout(200);
check('button switches back to Coronal', (await slot.locator('.pill .name').textContent()) === 'Coronal' && !(await page.evaluate(() => document.querySelector('.vp[data-id=coronal]').classList.contains('pano-on'))));

// Copy summary: add an implant, press the button, the clipboard (or the fallback box) has the text.
await page.evaluate(() => [...document.querySelectorAll('.panel button')].find((x) => x.textContent === 'Add at crosshair').click());
await page.waitForTimeout(300);
await page.evaluate(() => [...document.querySelectorAll('.panel button')].find((x) => x.textContent === 'Copy summary').click());
await page.waitForTimeout(500);
const label = await page.evaluate(() => [...document.querySelectorAll('.panel .chips button')].find((x) => /^(Copied|Copy summary|Select and copy)/.test(x.textContent)).textContent);
const clip = await page.evaluate(() => navigator.clipboard.readText().catch(() => null));
const boxText = await page.evaluate(() => document.querySelector('.sumbox').value);
const text = (clip && clip.startsWith('Implant plan') ? clip : boxText).split('\r').join('');
check('Copy summary gives the plan text', /^Implant plan\nNerve canal:/.test(text) && /Implant 1: /.test(text), text.split('\n').slice(0, 3).join(' / '));
check('button says Copied', label === 'Copied' || label.startsWith('Select'), label);
await page.waitForTimeout(1900);
check('button label comes back', (await page.evaluate(() => [...document.querySelectorAll('.panel .chips button')].some((x) => x.textContent === 'Copy summary'))));
// Clipboard refused: the text appears in a selected read-only box.
await page.evaluate(() => {
  Object.defineProperty(navigator, 'clipboard', { value: { writeText: () => Promise.reject(new Error('denied')) }, configurable: true });
  document.execCommand = () => false;
  [...document.querySelectorAll('.panel button')].find((x) => x.textContent === 'Copy summary').click();
});
await page.waitForTimeout(400);
const fallback = await page.evaluate(() => {
  const t = document.querySelector('.sumbox');
  return { shown: t.style.display !== 'none', selected: t.selectionEnd - t.selectionStart, ro: t.readOnly };
});
check('clipboard refused: text shown selected in a read-only box', fallback.shown && fallback.selected > 20 && fallback.ro, JSON.stringify(fallback));
await page.locator('.panel').screenshot({ path: path.join(out, 'pano-panel.png') });

const bad = logs.filter((l) => /PAGEERROR|^error:|warning: CBCT/.test(l) && !l.includes('state.json') && !l.includes('404'));
console.log(bad.length ? `console problems:\n${bad.join('\n')}` : 'no console problems');
console.log(failures ? `PANORAMIC: ${failures} FAILED` : 'PANORAMIC: ALL PASS');
await browser.close();
await server.close();
process.exit(failures ? 1 : 0);
