// Smoke test of the scan viewer page (mesh.html) in installed Edge or
// Chromium, against the synthetic arch from tools/make_mesh.mjs.
// Pictures land in tests/out/mesh-*.png.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from '@playwright/test';
import { createServer } from './serve.mjs';

const viewerRoot = fileURLToPath(new URL('..', import.meta.url));
const ROOT = path.resolve(viewerRoot, '../assets/cbct_viewer');
const MESHES = path.resolve(viewerRoot, 'dev/mesh');
const outDir = path.resolve(viewerRoot, 'tests/out');
fs.mkdirSync(outDir, { recursive: true });

if (!fs.existsSync(path.join(MESHES, 'arch.stl'))) {
  console.error('No test meshes: run "npm run phantom-mesh" first.');
  process.exit(1);
}
const expected = JSON.parse(fs.readFileSync(path.join(MESHES, 'arch.json'), 'utf8'));

const results = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${name}${detail ? `   ${detail}` : ''}`);
};

const staticServer = createServer({ root: ROOT, phantom: MESHES });

// How much of the view the surface covers: a page that loaded but drew
// nothing would otherwise pass every other check.
const litShare = (page) =>
  page.evaluate(() => {
    window.__mesh.scene.render();
    const src = document.querySelector('.stage canvas');
    const c = document.createElement('canvas');
    c.width = 400;
    c.height = 300;
    const ctx = c.getContext('2d');
    ctx.drawImage(src, 0, 0, c.width, c.height);
    const d = ctx.getImageData(0, 0, c.width, c.height).data;
    let lit = 0;
    for (let i = 0; i < d.length; i += 4) if (d[i] > 90 && d[i + 1] > 70) lit++;
    return lit / (d.length / 4);
  });

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
  console.log(`Scan viewer smoke test running with: ${browserName}\n`);
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 913 } });

  for (const file of ['arch.stl', 'arch.ply', 'arch.obj']) {
    const page = await ctx.newPage();
    const logs = [];
    const errors = [];
    const notFound = [];
    page.on('response', (r) => r.status() === 404 && notFound.push(r.url()));
    page.on('console', (m) => (m.type() === 'error' ? errors : logs).push(`${m.type()}: ${m.text()}`));
    page.on('pageerror', (e) => errors.push(`pageerror: ${(e.stack || e.message).split('\n').slice(0, 4).join(' | ')}`));
    await page.addInitScript(() => {
      window.__csp = [];
      document.addEventListener('securitypolicyviolation', (e) => window.__csp.push(`${e.violatedDirective} ${e.blockedURI}`));
    });

    const t0 = Date.now();
    await page.goto(
      `${base}mesh.html?debug=1&file=/phantom/${file}&name=${file}&title=Test%20patient&badge=On%20this%20device`,
    );
    let shown = false;
    for (let i = 0; i < 120 && !shown; i++) {
      shown = logs.some((l) => l.includes('"type":"shown"'));
      if (!shown) await page.waitForTimeout(250);
      if (errors.length) break;
    }
    check(`${file}: on screen`, shown, `${Date.now() - t0} ms`);
    if (!shown) {
      console.log(errors.join('\n') || logs.slice(-5).join('\n'));
      await page.close();
      continue;
    }

    const info = await page.evaluate(() => ({ triangles: window.__mesh.triangles, points: window.__mesh.points }));
    check(
      `${file}: ${expected.triangles.toLocaleString('en-US')} triangles, ${expected.points.toLocaleString('en-US')} points`,
      info.triangles === expected.triangles && info.points === expected.points,
      JSON.stringify(info),
    );

    const share = await litShare(page);
    check(`${file}: the surface is drawn`, share > 0.05, `${(share * 100).toFixed(1)}% of the view`);

    const status = await page.locator('.status').textContent();
    check(`${file}: status line reads right`, /triangles/.test(status) && /mm/.test(status), status.trim());

    // Colours are offered only when the file carries them.
    const colourVisible = await page.locator('.seg').nth(1).isVisible();
    check(`${file}: colour choice ${file.endsWith('.ply') ? 'offered' : 'hidden'}`, colourVisible === file.endsWith('.ply'));
    if (colourVisible) {
      await page.locator('.seg').nth(1).getByText('Scan colour').click();
      await page.waitForTimeout(200);
      const coloured = await page.evaluate(() => {
        window.__mesh.scene.render();
        const src = document.querySelector('.stage canvas');
        const c = document.createElement('canvas');
        c.width = 200;
        c.height = 150;
        const ctx2 = c.getContext('2d');
        ctx2.drawImage(src, 0, 0, c.width, c.height);
        const d = ctx2.getImageData(0, 0, c.width, c.height).data;
        // The scan is pink: red clearly ahead of green on the lit surface.
        let pink = 0;
        for (let i = 0; i < d.length; i += 4) if (d[i] > 90 && d[i] - d[i + 1] > 25) pink++;
        return pink / (d.length / 4);
      });
      check(`${file}: scan colours show`, coloured > 0.02, `${(coloured * 100).toFixed(1)}% pink`);
      await page.locator('.seg').nth(1).getByText('Ivory').click();
    }

    // Looks and reset: the camera moves and the surface stays on screen.
    for (const look of ['Top', 'Side', 'Front']) {
      await page.locator('.seg').first().getByText(look).click();
      await page.waitForTimeout(150);
      const s = await litShare(page);
      check(`${file}: ${look.toLowerCase()} view`, s > 0.03, `${(s * 100).toFixed(1)}%`);
    }
    await page.keyboard.press('r');
    await page.waitForTimeout(150);
    check(`${file}: R resets without breaking the view`, (await litShare(page)) > 0.03);

    await page.screenshot({ path: path.join(outDir, `mesh-${file.replace('.', '-')}.png`) });
    const csp = await page.evaluate(() => window.__csp);
    check(`${file}: no console errors, no 404s, no blocked requests`, !errors.length && !notFound.length && !csp.length, [...errors, ...notFound, ...csp].slice(0, 2).join(' | '));
    await page.close();
  }

  // A file that is not there must say so rather than sit on a spinner.
  {
    const page = await ctx.newPage();
    await page.goto(`${base}mesh.html?file=/phantom/missing.stl&name=missing.stl`);
    await page.waitForSelector('.msg:not([hidden])', { timeout: 10000 }).catch(() => {});
    const msg = (await page.locator('.msg').textContent().catch(() => '')) || '';
    check('a missing file says so', /could not be read/i.test(msg), msg.trim());
    await page.close();
  }

  // The CBCT page still boots: the two entries share one bundle.
  {
    const page = await ctx.newPage();
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    await page.goto(`${base}index.html`);
    await page.waitForTimeout(1500);
    check('the CBCT page is untouched', !errors.length, errors.slice(0, 1).join(''));
    await page.close();
  }

  await browser.close();
  await staticServer.close();

  const failed = results.filter((r) => !r.ok);
  console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
  console.log(`Pictures: ${outDir}`);
  process.exit(failed.length ? 1 : 0);
})();
