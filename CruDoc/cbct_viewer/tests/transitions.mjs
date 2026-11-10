// Frame-capture test that proves "no snaps" during viewer opening and 3D sharpen.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from '@playwright/test';
import { createServer } from './serve.mjs';

const viewerRoot = fileURLToPath(new URL('..', import.meta.url));
const ROOT = path.resolve(viewerRoot, '../assets/cbct_viewer');
const PHANTOM = path.resolve(viewerRoot, 'dev/phantom');

// Ensure phantom exists
if (!fs.existsSync(path.join(PHANTOM, 'meta.json'))) {
  const { execSync } = await import('node:child_process');
  execSync('node tools/make_phantom.mjs dev/phantom', { cwd: viewerRoot, stdio: 'inherit' });
}

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
  console.log(`Transitions test running with: ${browserName}`);

  const ctx = await browser.newContext({ viewport: { width: 1440, height: 913 } });
  const page = await ctx.newPage();

  // In-page image diff calculator using OffscreenCanvas and atob
  await page.addInitScript(() => {
    window.__diffFrames = async (base64Array) => {
      const bitmaps = await Promise.all(
        base64Array.map(async (b64) => {
          const bin = atob(b64);
          const u8 = new Uint8Array(bin.length);
          for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
          const blob = new Blob([u8], { type: 'image/png' });
          return createImageBitmap(blob);
        })
      );

      const w = bitmaps[0].width;
      const h = bitmaps[0].height;
      const cv1 = new OffscreenCanvas(w, h);
      const ctx1 = cv1.getContext('2d', { willReadFrequently: true });
      const cv2 = new OffscreenCanvas(w, h);
      const ctx2 = cv2.getContext('2d', { willReadFrequently: true });

      const diffs = [];
      const pixelCount = w * h;

      for (let i = 0; i < bitmaps.length - 1; i++) {
        ctx1.drawImage(bitmaps[i], 0, 0);
        const d1 = ctx1.getImageData(0, 0, w, h).data;
        ctx2.drawImage(bitmaps[i + 1], 0, 0);
        const d2 = ctx2.getImageData(0, 0, w, h).data;

        let sum = 0;
        for (let j = 0; j < d1.length; j += 4) {
          sum += Math.abs(d1[j] - d2[j]) + Math.abs(d1[j + 1] - d2[j + 1]) + Math.abs(d1[j + 2] - d2[j + 2]);
        }
        diffs.push(sum / (pixelCount * 3));
      }
      return diffs;
    };
  });

  const url = base + 'index.html?debug=1&base=/phantom/&first=1&badge=Anonymized&title=Test%20Phantom&chip=' + encodeURIComponent('CBCT · TEST PHANTOM · 09 Nov 2026 · 38 × 38 × 38 mm');

  // Start navigation
  const navPromise = page.goto(url);

  // 1. Capture 3D viewport every 40 ms for 6 s during opening
  const vpLoc = page.locator('.vp[data-id=threeD]');
  await page.waitForSelector('.vp[data-id=threeD]', { state: 'attached' });
  await navPromise;

  const openFrames = [];
  const openStart = Date.now();
  while (Date.now() - openStart < 6000) {
    const t0 = Date.now();
    try {
      const buf = await vpLoc.screenshot({ type: 'png' });
      openFrames.push(buf.toString('base64'));
    } catch {
      /* ignore occasional layout tick */
    }
    const elapsed = Date.now() - t0;
    if (elapsed < 40) await page.waitForTimeout(40 - elapsed);
  }

  // 2. Drag to rotate 3D view for 1 s, release, and capture for 1 s
  const box = await vpLoc.boundingBox();
  const cx = box.x + box.width / 2;
  const cy = box.y + box.height / 2;

  await page.mouse.move(cx, cy);
  await page.mouse.down();
  const dragStart = Date.now();
  let step = 0;
  while (Date.now() - dragStart < 1000) {
    step += 0.25;
    await page.mouse.move(cx + Math.cos(step) * 40, cy + Math.sin(step) * 40);
    await page.waitForTimeout(30);
  }
  await page.mouse.up();

  // Capture sharpen phase for 1 s
  const sharpenFrames = [];
  const sharpenStart = Date.now();
  while (Date.now() - sharpenStart < 1000) {
    const t0 = Date.now();
    try {
      const buf = await vpLoc.screenshot({ type: 'png' });
      sharpenFrames.push(buf.toString('base64'));
    } catch {
      /* ignore */
    }
    const elapsed = Date.now() - t0;
    if (elapsed < 40) await page.waitForTimeout(40 - elapsed);
  }

  // Evaluate pixel differences in the page
  const openDiffs = await page.evaluate((frames) => window.__diffFrames(frames), openFrames);
  const sharpenDiffs = await page.evaluate((frames) => window.__diffFrames(frames), sharpenFrames);
  // DUMP=1: print the opening diffs and save the frames around the biggest jump.
  if (process.env.DUMP) {
    const { writeFileSync, mkdirSync } = await import('node:fs');
    console.log('open diffs:', openDiffs.map((d) => d.toFixed(2)).join(' '));
    const at = openDiffs.indexOf(Math.max(...openDiffs));
    mkdirSync('tests/out', { recursive: true });
    for (const k of [at - 1, at, at + 1, at + 2]) if (openFrames[k]) writeFileSync(`tests/out/open-${k}.png`, Buffer.from(openFrames[k], 'base64'));
    console.log('biggest jump between frames', at, 'and', at + 1);
  }

  function analyze(diffs, name) {
    // Filter out initial static/blank frames until first image appears
    let firstImgIdx = 0;
    for (let i = 0; i < diffs.length; i++) {
      if (diffs[i] > 0.1) {
        firstImgIdx = i + 1; // start analyzing from the frame after the image appears
        break;
      }
    }
    const active = diffs.slice(firstImgIdx);
    if (!active.length) {
      console.log(`Phase ${name}: NO ACTIVITY DETECTED`);
      return false;
    }

    // Active frames where change is occurring (diff > 0.02)
    const changing = active.filter((d) => d > 0.02);
    const sorted = [...(changing.length ? changing : active)].sort((a, b) => a - b);
    const median = sorted[Math.floor(sorted.length / 2)] || 0.01;
    const max = Math.max(...active);
    const ratio = max / median;
    const pass = ratio <= 3.0;

    console.log(`Phase ${name}: max jump = ${max.toFixed(2)}, median = ${median.toFixed(2)}, ratio = ${ratio.toFixed(2)}x (limit: 3.0x) -> ${pass ? 'PASS' : 'FAIL'}`);
    return pass;
  }

  console.log('--- Transitions Test Results ---');
  const openPass = analyze(openDiffs, 'Opening');
  const sharpenPass = analyze(sharpenDiffs, 'Sharpen');
  const allPass = openPass && sharpenPass;
  console.log(allPass ? 'TRANSITIONS: ALL PASS' : 'TRANSITIONS: FAIL');

  await browser.close();
  await staticServer.close();
  process.exit(allPass ? 0 : 1);
})().catch(async (err) => {
  console.error('Transitions test error:', err);
  await staticServer.close().catch(() => {});
  process.exit(2);
});
