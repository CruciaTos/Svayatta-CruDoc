// Opens the built viewer with the phantom at 1440 x 913, waits for full load,
// and saves tests/out/step-<n>.png (default n=0).
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

const step = process.argv[2] || '0';
const outFile = path.join(outDir, `step-${step}.png`);

const staticServer = createServer({ root: ROOT, phantom: PHANTOM });

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
  console.log(`Shot script running with: ${browserName}`);

  const ctx = await browser.newContext({ viewport: { width: 1440, height: 913 }, acceptDownloads: true });
  const page = await ctx.newPage();
  const logs = [];
  page.on('console', (m) => logs.push(m.type() + ': ' + m.text()));

  await page.goto(base + 'index.html?base=/phantom/&first=1&title=Test%20Phantom');

  const waitFor = async (needle, ms = 60000) => {
    for (let i = 0; i < ms / 250; i++) {
      if (logs.some((l) => l.includes(needle))) return true;
      await page.waitForTimeout(250);
    }
    return false;
  };

  const fullLoaded = await waitFor('"type":"full"');
  if (!fullLoaded) {
    console.warn('Timed out waiting for "type":"full", taking screenshot anyway.');
  }
  await page.waitForTimeout(1000);

  await page.screenshot({ path: outFile });
  console.log('Saved screenshot:', outFile);

  await browser.close();
  await staticServer.close();
  process.exit(0);
})().catch(async (err) => {
  console.error('SHOT ERROR', err);
  await staticServer.close().catch(() => {});
  process.exit(2);
});

