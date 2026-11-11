// One-shot smoke test of the full CBCT viewer in installed Edge or Chromium,
// against the synthetic phantom (pack format v2).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from '@playwright/test';
import { createServer } from './serve.mjs';

const viewerRoot = fileURLToPath(new URL('..', import.meta.url));
const ROOT = path.resolve(viewerRoot, '../assets/cbct_viewer');
const PHANTOM = path.resolve(viewerRoot, 'dev/phantom');
const outDir = path.resolve(viewerRoot, 'tests/out');
fs.mkdirSync(outDir, { recursive: true });

const staticServer = createServer({ root: ROOT, phantom: PHANTOM });
const puts = staticServer.puts;

const results = [];
const check = (name, ok, detail = '') => results.push({ name, ok: !!ok, detail });

(async () => {
  const { base } = await staticServer.start();

  let browser;
  let browserName = 'msedge';
  try {
    browser = await chromium.launch({ channel: 'msedge', headless: true });
  } catch (err) {
    browserName = 'chromium';
    browser = await chromium.launch({ headless: true });
  }
  console.log(`Smoke test running with: ${browserName}`);

  const ctx = await browser.newContext({ viewport: { width: 1440, height: 913 }, acceptDownloads: true });
  const page = await ctx.newPage();
  const logs = [], errors = [], notFound = [];
  page.on('response', (r) => { if (r.status() === 404) notFound.push(r.url()); });
  page.on('console', (m) => (m.type() === 'error' ? errors : logs).push(m.type() + ': ' + m.text()));
  page.on('pageerror', (e) => errors.push('pageerror: ' + (e.stack || e.message).split('\n').slice(0, 5).join(' | ')));
  await page.addInitScript(() => {
    window.__csp = [];
    document.addEventListener('securitypolicyviolation', (e) => window.__csp.push(e.violatedDirective + ' ' + e.blockedURI));
  });

  const t0 = Date.now();
  await page.goto(base + 'index.html?debug=1&base=/phantom/&first=1&badge=Anonymized&title=Test%20Phantom&chip=' + encodeURIComponent('CBCT · TEST PHANTOM · 09 Nov 2026 · 38 × 38 × 38 mm'));
  const waitFor = async (needle, ms = 60000) => {
    for (let i = 0; i < ms / 250; i++) {
      if (logs.some((l) => l.includes(needle))) return true;
      if (errors.some((e) => !/Failed to load resource/.test(e))) return false;
      await page.waitForTimeout(250);
    }
    return false;
  };

  const shown = await waitFor('"type":"shown"');
  const preview = await waitFor('"type":"preview"');
  const full = await waitFor('"type":"full"');
  check('messages shown, preview, full', shown && preview && full, `${Date.now() - t0} ms`);
  console.log('messages:', logs.filter((l) => l.includes('[cbct->flutter]')).map((l) => l.replace('log: [cbct->flutter] ', '')).join('  '));
  await page.waitForTimeout(1200); // solidify + fades
  await page.screenshot({ path: path.join(outDir, 'v2-1-open.png') });

  const $ = (sel) => page.locator(sel);
  const text = (sel) => page.locator(sel).first().innerText();
  const val = (sel) => page.locator(sel).first().inputValue();

  // Overlays
  const letters = await page.evaluate(() => ['top', 'bottom', 'left', 'right'].map((p) => document.querySelector('.vp[data-id=axial] .lt.' + p).textContent).join(','));
  check('axial letters A,P,R,L', letters === 'A,P,R,L', letters);
  const covOk = await page.evaluate(() => ['coronal', 'sagittal'].map((id) => ['top', 'bottom', 'left', 'right'].map((p) => document.querySelector(`.vp[data-id=${id}] .lt.${p}`).textContent).join(',')).join(' | '));
  check('coronal S,I,R,L | sagittal S,I,A,P', covOk === 'S,I,R,L | S,I,A,P', covOk);
  const info = await text('.vp[data-id=axial] .vpinfo');
  check('info overlay slice + W/L + zoom', /Slice \d+ \/ 96 · [\d.]+ mm/.test(info) && /W 3600\s+L 1200 · 1\.00×/.test(info), info.replace(/\n/g, ' / '));
  check('scale bar', /^\d+ mm$/.test(await text('.vp[data-id=axial] .scale .lbl')), await text('.vp[data-id=axial] .scale .lbl'));
  const gizmoN = await page.evaluate(() => document.querySelector('.gizmo').children.length);
  check('3D gizmo drawn', gizmoN >= 12, 'children=' + gizmoN);
  const planes = await page.evaluate(() => document.querySelector('.vp[data-id=threeD] .ov').querySelectorAll('polygon').length);
  check('3D plane outlines (3)', planes === 3, 'polygons=' + planes);
  check('posters faded out', await page.evaluate(() => [...document.querySelectorAll('.poster')].every((p) => getComputedStyle(p).display === 'none')));

  // Histogram painted
  const histPixels = await page.evaluate(() => { const c = document.querySelector('.histcv'); const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data; let n = 0; for (let i = 3; i < d.length; i += 4) if (d[i] > 0) n++; return n; });
  check('histogram drawn', histPixels > 500, 'pixels=' + histPixels);

  // Panel: level/width, presets, invert
  check('level/width boxes', (await val('.prow:has(label:text-is("Level")) input.num')) === '1200' && (await val('.prow:has(label:text-is("Width")) input.num')) === '3600');
  await $('.chip:has-text("Teeth")').first().click();
  check('Teeth preset', (await val('.prow:has(label:text-is("Width")) input.num')) === '4800', await val('.prow:has(label:text-is("Width")) input.num'));
  await $('.toggle').click();
  check('invert toggle', await $('.toggle').evaluate((b) => b.classList.contains('on')));
  await page.keyboard.press('r');
  await page.waitForTimeout(300);
  check('R resets window and invert', (await val('.prow:has(label:text-is("Width")) input.num')) === '3600' && !(await $('.toggle').evaluate((b) => b.classList.contains('on'))));

  // Slab
  await $('.seg button:text-is("MIP")').first().click();
  check('MIP sets 5 mm', (await val('.numwrap input')) === '5', await val('.numwrap input'));
  await $('.numwrap input').fill('0');
  await page.keyboard.press('Enter');
  check('0 mm forces Thin', await $('.seg button:text-is("Thin")').evaluate((b) => b.classList.contains('on')));

  // 3D controls
  await $('.chip:has-text("Skin + bone")').click();
  await page.locator('.seg button:text-is("Axial")').click();
  check('3D label', (await text('.vp[data-id=threeD] .pill small')).includes('cut axial'), await text('.vp[data-id=threeD] .pill small'));
  await page.screenshot({ path: path.join(outDir, 'v2-2-skin-cut.png') });
  await $('.chip:has-text("X-ray")').click();
  await page.waitForTimeout(300);
  await page.screenshot({ path: path.join(outDir, 'v2-3-xray.png') });
  await $('.chip:has-text("Bone")').nth(1).click(); // 3D bone (second Bone chip)
  await page.locator('.seg button:text-is("Off")').click();

  // A6: new look "Teeth in bone", Smooth slider, gizmo letter click
  const teethInBoneChip = await page.locator('.chips .chip').evaluateAll((chips) =>
    chips.some((c) => c.textContent.trim() === 'Teeth in bone'));
  check('3D chip row contains "Teeth in bone"', teethInBoneChip);
  await $('.chip:has-text("Teeth in bone")').first().click();
  await page.waitForTimeout(200);
  check('"Teeth in bone" chip sets 3D label', (await text('.vp[data-id=threeD] .pill small')).includes('Teeth in bone'), await text('.vp[data-id=threeD] .pill small'));

  const smoothRow = await page.locator('.prow:has(label:text-is("Smooth"))').count();
  check('Smooth slider row exists', smoothRow > 0);

  const implantPlanSec = await page.locator('.psec h3', { hasText: 'Implant plan' }).count();
  check('panel section "Implant plan" exists', implantPlanSec > 0);
  const foundAutoSec = await page.locator('.psec h3', { hasText: 'Found automatically' }).count();
  check('panel section "Found automatically" exists', foundAutoSec > 0);

  // Click a gizmo circle (force: true because it may be small / covered) and wait
  // up to 1500 ms for viewPlaneNormal to change.
  const vpnBefore = await page.evaluate(() => {
    const cam = window.__cbct.core.engine.getViewport('threeD').getCamera();
    return [...cam.viewPlaneNormal];
  });
  await page.locator('.gizmo circle').first().click({ force: true });
  let vpnChanged = false;
  for (let i = 0; i < 15; i++) {
    await page.waitForTimeout(100);
    const vpnAfter = await page.evaluate(() => {
      const cam = window.__cbct.core.engine.getViewport('threeD').getCamera();
      return [...cam.viewPlaneNormal];
    });
    if (vpnAfter.some((v, j) => Math.abs(v - vpnBefore[j]) > 0.01)) {
      vpnChanged = true;
      break;
    }
  }
  check('gizmo circle click changes viewPlaneNormal within 1.5 s', vpnChanged);

  // Status readout
  const ax = await page.locator('.vp[data-id=axial]').boundingBox();
  await page.mouse.move(ax.x + ax.width * 0.4, ax.y + ax.height * 0.45);
  await page.mouse.move(ax.x + ax.width * 0.5, ax.y + ax.height * 0.5);
  await page.waitForTimeout(300);
  const readout = await text('.readout');
  check('status readout', /Axial\s+x [\d.]+\s+y [\d.]+\s+z [\d.]+ mm\s+·\s+value -?\d+/.test(readout), readout);

  // Tools
  await page.keyboard.press('l');
  check('L selects Length', await $('.tbtn[title^="Length"]').evaluate((b) => b.classList.contains('on')));
  await page.mouse.move(ax.x + 200, ax.y + 200);
  await page.mouse.down(); await page.mouse.move(ax.x + 320, ax.y + 260, { steps: 6 }); await page.mouse.up();
  await page.waitForTimeout(300);
  await page.mouse.move(ax.x + 330, ax.y + 270);
  await page.evaluate(() => window.__cbct.core.engine.renderViewports(['axial']));
  await page.waitForTimeout(500);
  const measured = await page.evaluate(() => /mm/.test(document.querySelector('.vp[data-id=axial] .svg-layer')?.textContent || ''));
  check('length measurement drawn', measured, await page.evaluate(() => { const l = document.querySelector('.vp[data-id=axial] .svg-layer'); return l ? 'svg-layer html ' + l.innerHTML.length + ' text=' + l.textContent.slice(0, 60) : 'no svg-layer'; }));
  await page.keyboard.press('c');

  // Scroll: wheel, arrows, shift+wheel
  const idxOf = async () => /Slice (\d+)/.exec(await text('.vp[data-id=axial] .vpinfo'))[1];
  await page.waitForTimeout(400);
  const before = Number(await idxOf());
  await page.mouse.move(ax.x + ax.width / 2, ax.y + ax.height / 2);
  await page.keyboard.press('ArrowUp'); await page.waitForTimeout(250);
  const afterArrow = Number(await idxOf());
  await page.keyboard.press('PageDown'); await page.waitForTimeout(250);
  const afterPage = Number(await idxOf());
  check('arrows and PageDown scroll', afterArrow === before + 1 && afterPage === afterArrow - 10, `${before} -> ${afterArrow} -> ${afterPage}`);

  // Click-to-place on 3D
  const v3 = await page.locator('.vp[data-id=threeD]').boundingBox();
  const centreBefore = await text('.vp[data-id=coronal] .vpinfo');
  await page.mouse.click(v3.x + v3.width * 0.5, v3.y + v3.height * 0.5);
  await page.waitForTimeout(400);
  console.log('coronal info before/after 3D click:', centreBefore.replace(/\n/g, ' / '), '=>', (await text('.vp[data-id=coronal] .vpinfo')).replace(/\n/g, ' / '));

  // Layouts, help, overlays
  await page.locator('.tbtn[title^="One large"]').click();
  await page.waitForTimeout(300);
  const sizes = await page.evaluate(() => [...document.querySelectorAll('.vp')].map((v) => v.dataset.id + ':' + Math.round(v.getBoundingClientRect().width)).join(' '));
  check('1+3 layout', /axial:\d{3,4}/.test(sizes) && sizes.includes('threeD:'), sizes);
  await page.keyboard.press('?');
  check('help opens', await page.evaluate(() => document.querySelector('.help').classList.contains('open')));
  await page.keyboard.press('Escape'); await page.keyboard.press('Escape');
  await page.keyboard.press('h');
  check('H hides overlays', await page.evaluate(() => document.getElementById('app').classList.contains('no-overlay')));
  await page.keyboard.press('h');
  await page.keyboard.press(']');
  await page.waitForTimeout(300);
  check('] closes the panel', (await page.evaluate(() => document.querySelector('.main').dataset.panel)) === 'closed');
  await page.keyboard.press(']');
  await page.screenshot({ path: path.join(outDir, 'v2-4-final.png') });

  // Snapshot goes to the loopback server
  await page.keyboard.press('s');
  await page.waitForTimeout(800);
  check('snapshot PUT', Object.keys(puts).some((k) => /snap_\d+\.png$/.test(k)), JSON.stringify(puts));

  // Close: posters + state saved
  await page.locator('.back').click();
  await page.waitForTimeout(800);
  check('close saved state + 4 posters', Object.keys(puts).filter((k) => /poster_|state\.json/.test(k)).length >= 5, Object.keys(puts).join(' '));
  check('close message posted', logs.some((l) => l.includes('"type":"close"')));

  const csp = await page.evaluate(() => window.__csp);
  check('no CSP violations', csp.length === 0, JSON.stringify(csp));
  check('no console errors (first-open state.json 404 aside)', errors.filter((e) => !/Failed to load resource/.test(e)).length === 0 && notFound.every((u) => u.endsWith('state.json')), JSON.stringify({ errors: errors.slice(0, 5), notFound }));

  for (const r of results) console.log((r.ok ? 'PASS ' : 'FAIL ') + r.name + (r.detail && !r.ok ? '  -> ' + r.detail : r.ok && r.detail ? '  (' + r.detail + ')' : ''));
  const allPassed = results.every((r) => r.ok);
  console.log(allPassed ? 'ALL PASS' : 'SOME FAILED');

  await browser.close();
  await staticServer.close();
  process.exit(allPassed ? 0 : 1);
})().catch(async (e) => {
  console.error('SCRIPT ERROR', e);
  await staticServer.close().catch(() => {});
  process.exit(2);
});

