// Performance test: 3D viewport frame rates, level-of-detail transitions,
// and high-DPI scaling against the 400^3 big phantom.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';
import { chromium } from '@playwright/test';
import { createServer } from './serve.mjs';

const viewerRoot = fileURLToPath(new URL('..', import.meta.url));
const ROOT = path.resolve(viewerRoot, '../assets/cbct_viewer');
const PHANTOM_BIG = path.resolve(viewerRoot, 'dev/phantom_big');

// Ensure phantom_big exists
if (!fs.existsSync(path.join(PHANTOM_BIG, 'meta.json'))) {
  console.log('Generating dev/phantom_big (400^3)...');
  execSync('node tools/make_phantom.mjs dev/phantom_big --size 400', { cwd: viewerRoot, stdio: 'inherit' });
}

const staticServer = createServer({ root: ROOT, phantom: PHANTOM_BIG });

async function runSession(browser, dsf = 1.0) {
  const { base } = await staticServer.start();
  const ctx = await browser.newContext({
    viewport: { width: 1440, height: 913 },
    deviceScaleFactor: dsf,
  });
  const page = await ctx.newPage();

  await page.addInitScript(() => {
    window.__frames = [];
    window.__measuring = false;
    let lastT = 0;
    function loop(t) {
      if (window.__measuring && lastT > 0) {
        window.__frames.push(t - lastT);
      }
      lastT = t;
      requestAnimationFrame(loop);
    }
    requestAnimationFrame(loop);
    window.__startPerf = () => {
      window.__frames = [];
      window.__measuring = true;
    };
    window.__stopPerf = () => {
      window.__measuring = false;
      return window.__frames;
    };
  });

  const url = base + 'index.html?debug=1&base=/phantom/&first=1&badge=Anonymized&title=Big%20Phantom';
  await page.goto(url);

  // Wait for viewer to be full phase
  const logs = [];
  page.on('console', (m) => {
    logs.push(m.text());
    if (m.text().includes('[lod debug]')) console.log('  ' + m.text());
  });
  for (let i = 0; i < 40; i++) {
    if (logs.some((l) => l.includes('"type":"full"'))) break;
    await page.waitForTimeout(250);
  }
  await page.waitForTimeout(1000); // stabilize

  const vpLoc = page.locator('.vp[data-id=threeD]');
  const box = await vpLoc.boundingBox();
  const cx = box.x + box.width / 2;
  const cy = box.y + box.height / 2;

  function stats(deltas, lod) {
    const total = deltas.length;
    const over50 = deltas.filter((d) => d > 50).length;
    const pct50 = total > 0 ? (over50 / total) * 100 : 0;
    const sorted = [...deltas].sort((a, b) => a - b);
    const p90 = sorted[Math.floor(sorted.length * 0.9)] || 0;
    const max = deltas.length ? Math.max(...deltas) : 0;
    return { total, over50, pct50, p90, max, lod };
  }

  async function runRound(roundNum) {
    console.log(`\n=== Round ${roundNum} (deviceScaleFactor: ${dsf}) ===`);

    // 1. Drag-rotate 3D view (80 mouse moves)
    await page.mouse.move(cx, cy);
    await page.mouse.down();
    await page.evaluate(() => window.__startPerf());

    for (let i = 0; i < 80; i++) {
      const angle = (i / 80) * Math.PI * 2;
      await page.mouse.move(cx + Math.cos(angle) * 60, cy + Math.sin(angle) * 60);
      await page.waitForTimeout(16);
    }
    const rotDeltas = await page.evaluate(() => window.__stopPerf());
    await page.mouse.up();
    await page.waitForTimeout(350); // allow sharpen
    const lod1 = await page.evaluate(() => window.__cbct?.lod);
    const s1 = stats(rotDeltas, lod1);
    console.log(`1. Zoomed-out rotation: ${s1.over50}/${s1.total} (${s1.pct50.toFixed(1)}%) > 50ms | p90=${s1.p90.toFixed(1)}ms | max=${s1.max.toFixed(1)}ms | lod=${s1.lod}`);

    // 2. Wheel-zoom in 10 notches, wait 1 s, rotate again
    await page.mouse.move(cx, cy);
    for (let i = 0; i < 10; i++) {
      await page.mouse.wheel(0, -120);
      await page.waitForTimeout(60);
    }
    await page.waitForTimeout(1000);
    const lod2 = await page.evaluate(() => window.__cbct?.lod);

    await page.mouse.down();
    await page.evaluate(() => window.__startPerf());
    for (let i = 0; i < 80; i++) {
      const angle = (i / 80) * Math.PI * 2;
      await page.mouse.move(cx + Math.sin(angle) * 50, cy + Math.cos(angle) * 50);
      await page.waitForTimeout(16);
    }
    const zoomRotDeltas = await page.evaluate(() => window.__stopPerf());
    await page.mouse.up();
    await page.waitForTimeout(350);
    const s2 = stats(zoomRotDeltas, lod2);
    console.log(`2. Zoomed-in rotation:  ${s2.over50}/${s2.total} (${s2.pct50.toFixed(1)}%) > 50ms | p90=${s2.p90.toFixed(1)}ms | max=${s2.max.toFixed(1)}ms | lod=${s2.lod}`);

    // 3. Wheel-zoom out 10 notches, wait 1.5 s
    await page.mouse.move(cx, cy);
    for (let i = 0; i < 12; i++) {
      await page.mouse.wheel(0, 120);
      await page.waitForTimeout(60);
    }
    await page.waitForTimeout(1500);
    const lod3 = await page.evaluate(() => window.__cbct?.lod);
    console.log(`3. Zoomed-out return: lod=${lod3}`);

    return { s1, s2, lod3 };
  }

  const r1 = await runRound(1);
  const r2 = await runRound(2);

  await page.close();
  await ctx.close();
  await staticServer.close();

  return { r1, r2 };
}

(async () => {
  let browser;
  let browserName = 'msedge';
  try {
    browser = await chromium.launch({ channel: 'msedge', headless: true });
  } catch {
    browserName = 'chromium';
    browser = await chromium.launch({ headless: true });
  }
  console.log(`Perf test running with: ${browserName}`);

  // Standard DPR = 1.0
  const standard = await runSession(browser, 1.0);

  // High-DPI DPR = 1.5
  const highDpi = await runSession(browser, 1.5);

  await browser.close();

  console.log('\n--- Performance Targets Evaluation ---');
  const r2 = standard.r2;
  const t1 = r2.s1.pct50 < 2.0;
  console.log(`- Zoomed-out rotation < 2% over 50ms: ${r2.s1.pct50.toFixed(1)}% -> ${t1 ? 'PASS' : 'FAIL'}`);

  const t2 = r2.s2.lod > 0;
  console.log(`- Finer level appeared when zoomed in: lod=${r2.s2.lod} -> ${t2 ? 'PASS' : 'FAIL'}`);

  const t3 = r2.lod3 === 0;
  console.log(`- Zooming out returned to coarse level (lod=0): lod=${r2.lod3} -> ${t3 ? 'PASS' : 'FAIL'}`);

  const hdOk = highDpi.r2.s1.pct50 < 5.0;
  console.log(`- High-DPI (1.5x) coarse rotation: ${highDpi.r2.s1.pct50.toFixed(1)}% > 50ms -> ${hdOk ? 'SMOOTH' : 'EVALUATE'}`);

  const allPass = t1 && t2 && t3;
  console.log(allPass ? 'PERF: ALL PASS' : 'PERF: PARTIAL/CHECK');
  process.exit(allPass ? 0 : 1);
})().catch(async (e) => {
  console.error('Perf test error:', e);
  await staticServer.close().catch(() => {});
  process.exit(2);
});

