// Responsive layout checks across desktop, laptop, and tablet viewports.
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

const SIZES = [
  { name: 'desktop', width: 1440, height: 913 },
  { name: 'laptop', width: 1280, height: 720 },
  { name: 'ipad-pro landscape', width: 1366, height: 1024 },
  { name: 'ipad-air landscape', width: 1180, height: 820 },
  { name: 'ipad portrait', width: 820, height: 1180 },
  { name: 'small tablet', width: 768, height: 1024 },
];

const staticServer = createServer({ root: ROOT, phantom: PHANTOM });

(async () => {
  const { base } = await staticServer.start();

  let browser;
  let browserName = 'msedge';
  try {
    browser = await chromium.launch({ channel: 'msedge', headless: true });
  } catch {
    browserName = 'chromium';
    browser = await chromium.launch({ headless: true });
  }
  console.log(`Responsive test running with: ${browserName}\n`);

  const allResults = [];

  for (const { name, width, height } of SIZES) {
    console.log(`=== ${name} (${width} x ${height}) ===`);
    const ctx = await browser.newContext({ viewport: { width, height } });
    const page = await ctx.newPage();
    const logs = [];
    page.on('console', (m) => logs.push(m.type() + ': ' + m.text()));

    await page.goto(base + 'index.html?debug=1&base=/phantom/&title=Test%20Phantom');

    // Wait for "type":"full"
    for (let i = 0; i < 240; i++) {
      if (logs.some((l) => l.includes('"type":"full"'))) break;
      await page.waitForTimeout(250);
    }
    await page.waitForTimeout(1000);

    const shotPath = path.join(outDir, `responsive-${width}x${height}.png`);
    await page.screenshot({ path: shotPath });

    // 1. No horizontal scroll
    const noHScroll = await page.evaluate(() => {
      const sw = document.documentElement.scrollWidth;
      const iw = window.innerWidth;
      return { ok: sw <= iw, sw, iw };
    });
    allResults.push({
      size: `${width}x${height}`,
      check: 'no horizontal scroll',
      ok: noHScroll.ok,
      detail: `scrollWidth=${noHScroll.sw}, innerWidth=${noHScroll.iw}`,
    });

    // 2. Viewports size >= 120 and no overlap
    const vpCheck = await page.evaluate(() => {
      const vps = [...document.querySelectorAll('.vp')].map((el) => {
        const r = el.getBoundingClientRect();
        return { id: el.dataset.id, w: r.width, h: r.height, top: r.top, bottom: r.bottom, left: r.left, right: r.right };
      });
      const tooSmall = vps.filter((v) => v.w < 120 || v.h < 120);
      const overlaps = [];
      for (let i = 0; i < vps.length; i++) {
        for (let j = i + 1; j < vps.length; j++) {
          const a = vps[i], b = vps[j];
          const noOverlap = a.right <= b.left || a.left >= b.right || a.bottom <= b.top || a.top >= b.bottom;
          if (!noOverlap) overlaps.push(`${a.id} overlaps ${b.id}`);
        }
      }
      return { ok: vps.length === 4 && tooSmall.length === 0 && overlaps.length === 0, count: vps.length, tooSmall, overlaps };
    });
    allResults.push({
      size: `${width}x${height}`,
      check: 'viewports >= 120px and no overlap',
      ok: vpCheck.ok,
      detail: vpCheck.ok ? '4 viewports ok' : JSON.stringify(vpCheck),
    });

    // 3. Bar visible buttons >= 28x28
    const btnCheck = await page.evaluate(() => {
      const bar = document.querySelector('.bar');
      if (!bar) return { ok: false, error: 'no .bar' };
      const barR = bar.getBoundingClientRect();
      const btns = [...bar.querySelectorAll('button, .tbtn')];
      const visible = btns.filter((b) => {
        const r = b.getBoundingClientRect();
        return r.right <= barR.right + 1 && r.left >= barR.left - 1;
      });
      const bad = visible.filter((b) => {
        const r = b.getBoundingClientRect();
        return r.width < 28 || r.height < 28;
      });
      return { ok: bad.length === 0, visibleCount: visible.length, total: btns.length, badCount: bad.length };
    });
    allResults.push({
      size: `${width}x${height}`,
      check: 'visible buttons in .bar >= 28x28',
      ok: btnCheck.ok,
      detail: btnCheck.ok ? `${btnCheck.visibleCount} visible buttons ok` : JSON.stringify(btnCheck),
    });

    // 4. Panel drawer behavior below/above 1100 px
    const panelCheck = await page.evaluate(async (w) => {
      const panel = document.querySelector('.panel');
      const main = document.querySelector('.main');
      if (!panel || !main) return { ok: false, error: 'no panel or main' };
      const pos = getComputedStyle(panel).position;
      if (w < 1100) {
        if (pos !== 'absolute') return { ok: false, detail: `expected absolute position below 1100, got ${pos}` };
        return { ok: true, drawer: true };
      } else {
        if (pos !== 'static' && pos !== 'relative') return { ok: false, detail: `expected static/relative above 1100, got ${pos}` };
        return { ok: true, drawer: false };
      }
    }, width);

    // Test toggle if drawer
    let drawerToggleOk = true;
    if (width < 1100) {
      const initialPanel = await page.evaluate(() => document.querySelector('.main')?.dataset.panel);
      await page.keyboard.press(']');
      await page.waitForTimeout(200);
      const toggledPanel = await page.evaluate(() => document.querySelector('.main')?.dataset.panel);
      await page.keyboard.press(']');
      await page.waitForTimeout(200);
      const revertedPanel = await page.evaluate(() => document.querySelector('.main')?.dataset.panel);
      drawerToggleOk = initialPanel !== toggledPanel && revertedPanel === initialPanel;
    }
    allResults.push({
      size: `${width}x${height}`,
      check: width < 1100 ? 'panel is drawer and ] toggles it' : 'panel is static/relative',
      ok: panelCheck.ok && drawerToggleOk,
      detail: panelCheck.detail || (width < 1100 ? `toggle ok (drawer)` : 'static/relative ok'),
    });

    // 5. Text clipping check
    const textClipCheck = await page.evaluate(() => {
      const targets = [...document.querySelectorAll('.pill, .vpinfo, .scale')];
      const clipped = [];
      for (const el of targets) {
        if (el.scrollWidth > el.clientWidth + 1) {
          clipped.push({ class: el.className, sw: el.scrollWidth, cw: el.clientWidth, text: el.textContent.trim().slice(0, 30) });
        }
      }
      return { ok: clipped.length === 0, clipped };
    });
    allResults.push({
      size: `${width}x${height}`,
      check: 'no text clipping in .pill, .vpinfo, .scale',
      ok: textClipCheck.ok,
      detail: textClipCheck.ok ? 'no clipping' : JSON.stringify(textClipCheck.clipped),
    });

    // 6. Toolbar scroll width vs client width
    const toolbarDims = await page.evaluate(() => {
      const bar = document.querySelector('.bar');
      return bar ? { sw: bar.scrollWidth, cw: bar.clientWidth } : null;
    });
    console.log(`Toolbar: scrollWidth=${toolbarDims?.sw ?? 'N/A'}, clientWidth=${toolbarDims?.cw ?? 'N/A'}`);

    for (const r of allResults.slice(-5)) {
      console.log(`  ${r.ok ? 'PASS' : 'FAIL'}: ${r.check} (${r.detail})`);
    }
    console.log();

    await page.close();
    await ctx.close();
  }

  await browser.close();
  await staticServer.close();

  console.log('=== SUMMARY TABLE ===');
  console.log('| Size | Check | Result | Detail |');
  console.log('|---|---|---|---|');
  for (const r of allResults) {
    console.log(`| ${r.size} | ${r.check} | ${r.ok ? 'PASS' : 'FAIL'} | ${r.detail} |`);
  }

  const anyFailed = allResults.some((r) => !r.ok);
  process.exit(anyFailed ? 1 : 0);
})().catch(async (err) => {
  console.error('RESPONSIVE ERROR', err);
  await staticServer.close().catch(() => {});
  process.exit(2);
});

