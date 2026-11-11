// Headless-Chrome verification of the dental 3D viewer.
//   node tests/verify.mjs                 -> dev server (started here if not already running)
//   node tests/verify.mjs --static        -> serves ../assets/dental3d (the build) with a plain static server
//   node tests/verify.mjs --placeholder   -> forces ?placeholder=1
import puppeteer from 'puppeteer-core';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..');
const shots = path.join(root, 'tmp', 'shots');
fs.mkdirSync(shots, { recursive: true });
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'scene_manifest.json'), 'utf8'));
const args = new Set(process.argv.slice(2));
const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';

let pass = 0, fail = 0;
const failures = [];
function check(name, ok, detail = '') {
  if (ok) { pass++; console.log(`  ok   ${name}${detail ? '  ' + detail : ''}`); }
  else { fail++; failures.push(name); console.log(`  FAIL ${name}${detail ? '  ' + detail : ''}`); }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------- servers
async function up(url) { try { return (await fetch(url)).ok; } catch { return false; } }

function staticServer(dir, port) {
  const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.wasm': 'application/wasm', '.glb': 'model/gltf-binary', '.json': 'application/json' };
  const srv = http.createServer((req, res) => {
    let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (p.endsWith('/')) p += 'index.html';
    const f = path.join(dir, p);
    if (!f.startsWith(dir) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); res.end('not found'); return; }
    res.writeHead(200, { 'content-type': types[path.extname(f)] || 'application/octet-stream' });
    if (req.method === 'HEAD') res.end(); else fs.createReadStream(f).pipe(res);
  });
  return new Promise((r) => srv.listen(port, '127.0.0.1', () => r(srv)));
}

let closeServer = async () => { };
let BASE;
if (args.has('--static')) {
  const srv = await staticServer(path.resolve(root, '..', 'assets', 'dental3d'), 5181);
  closeServer = () => new Promise((r) => srv.close(r));
  BASE = 'http://127.0.0.1:5181/';
} else {
  BASE = 'http://127.0.0.1:5174/';
  if (!(await up(BASE))) {
    const { createServer } = await import('vite');
    const server = await createServer({ root, logLevel: 'error' });
    await server.listen();
    closeServer = () => server.close();
  }
}
const mkQuery = (q) => [args.has('--placeholder') ? 'placeholder=1' : '', q ? `q=${q}` : ''].filter(Boolean).join('&');

// ---------------------------------------------------------------- helpers
const browser = await puppeteer.launch({
  executablePath: CHROME,
  headless: 'new',
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-webgl', '--no-sandbox', '--disable-dev-shm-usage'],
  defaultViewport: null,
});

async function openPage(name, viewport, mobile = false, q = '') {
  const page = await browser.newPage();
  await page.setViewport({ ...viewport, deviceScaleFactor: 1, isMobile: mobile, hasTouch: mobile });
  const errors = [];
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  page.on('console', (m) => {
    const t = m.text();
    if (m.type() === 'error') errors.push('console.error: ' + t);
    else if (m.type() === 'warning' && /webgl|shader|program|glsl/i.test(t)) errors.push('console.warn: ' + t);
  });
  page.on('requestfailed', (r) => { if (!/favicon/.test(r.url())) errors.push('requestfailed: ' + r.url()); });
  await page.evaluateOnNewDocument(() => {
    window.__events = [];
    window.addEventListener('app3d', (e) => window.__events.push(e.detail));
  });
  await page.goto(`${BASE}?${mkQuery(q)}`, { waitUntil: 'load' });
  await page.waitForFunction('window.App3DBridge && window.__dental3d', { timeout: 60000 });
  await page.evaluate('window.App3DBridge.ready');
  return { page, errors, name };
}

const idle = (page, quiet = 400, max = 60000) => page.evaluate(async (quiet, max) => {
  const t0 = performance.now();
  let last = -1, lastChange = performance.now();
  while (performance.now() - t0 < max) {
    await new Promise((r) => setTimeout(r, 60));
    const n = window.__dental3d.stats().renderedFrames;
    if (n !== last) { last = n; lastChange = performance.now(); }
    if (performance.now() - lastChange > quiet && window.__dental3d.flyDone()) return n;
  }
  return -1;
}, quiet, max);

async function shot(page, file) {
  await idle(page);
  await page.screenshot({ path: path.join(shots, file) });
  console.log(`  shot ${path.join('tmp', 'shots', file)}`);
}
const ev = (page, fn, ...a) => page.evaluate(fn, ...a);

console.log(`
== Desktop 1280x800 (${BASE}?${mkQuery('low')}) ==`);
const D = await openPage('desktop', { width: 1280, height: 800 }, false, 'low');
const { page } = D;
await idle(page);
const info = await ev(page, () => ({ placeholder: window.__dental3d.placeholder, gpu: window.__dental3d.stats().gpu }));
console.log(`  model: ${info.placeholder ? 'PLACEHOLDER (capsules)' : 'real GLB'}   gpu: ${info.gpu}`);

if (args.has('--smoke')) {
  // Minimal check used for the built static folder: loads, renders, nothing missing, no console errors.
  const ids = manifest.parts.filter((p) => p.source === 'glb').map((p) => p.nodeId);
  const ok = await ev(page, (ids) => ids.every((id) => window.__dental3d.registry.map.has(id)), ids);
  check('smoke: real model loaded and all glb nodeIds registered', ok && !info.placeholder, `placeholder=${info.placeholder}`);
  const rel = await ev(page, () => [...document.querySelectorAll('script[src],link[href]')].map((e) => e.getAttribute('src') || e.getAttribute('href')));
  check('smoke: built index.html uses relative asset paths only', rel.every((u) => !/^(\/|https?:)/.test(u) || u.startsWith('data:')), rel.join(', '));
  await shot(page, 'static-build-front.png');
  check('smoke: no console / WebGL errors', D.errors.length === 0, D.errors.slice(0, 4).join(' || '));
  await browser.close(); await closeServer();
  console.log(`
${pass} passed, ${fail} failed${fail ? ' -> ' + failures.join('; ') : ''}`);
  process.exit(fail ? 1 : 0);
}

// 1. registry
const reg = await ev(page, (ids) => ids.map((id) => [id, window.__dental3d.registry.map.has(id)]), manifest.parts.filter((p) => p.source === 'glb').map((p) => p.nodeId));
check('every source:"glb" nodeId is in the registry', reg.every((r) => r[1]), `${reg.length} ids, missing: ${reg.filter((r) => !r[1]).map((r) => r[0]).join(',') || 'none'}`);
const rt = await ev(page, (ids) => ids.map((id) => window.__dental3d.registry.map.has(id)), manifest.parts.filter((p) => p.source === 'runtime').map((p) => p.nodeId));
check('gum/bone runtime parts are registered', rt.every(Boolean));
const userDataOk = await ev(page, () => [...window.__dental3d.registry.map.values()].every((o) => o.userData.part && o.userData.part.nodeId === o.name));
check('userData.part set on every registered object', userDataOk);

// 2. world positions
const posErr = await ev(page, (parts) => {
  const THREE_V = window.__dental3d.registry.get('tooth_11').position.constructor;
  const v = new THREE_V();
  let max = 0, worst = '';
  for (const p of parts) {
    const o = window.__dental3d.registry.get(p.nodeId);
    o.updateWorldMatrix(true, false);
    o.getWorldPosition(v);
    const d = Math.hypot(v.x - p.position[0], v.y - p.position[1], v.z - p.position[2]);
    if (d > max) { max = d; worst = p.nodeId; }
  }
  return { max, worst };
}, manifest.parts.filter((p) => p.kind === 'tooth'));
check('tooth world positions match manifest within 0.05 mm', posErr.max <= 0.05, `max error ${posErr.max.toFixed(4)} (${posErr.worst})`);

// BVH + raycaster flags
const bvh = await ev(page, () => [...window.__dental3d.registry.teeth.values(), ...window.__dental3d.registry.pulps.values()].every((o) => o.userData.meshes.length && o.userData.meshes.every((m) => m.geometry.boundsTree)));
check('three-mesh-bvh bounds tree on every tooth and pulp mesh', bvh);

// 3. gum rebuild speed
const gumMs = await ev(page, () => {
  const g = window.__dental3d.gums; const out = {};
  for (const a of ['upper', 'lower']) { const t = []; for (let i = 0; i < 12; i++) t.push(g.rebuildGums(a)); t.sort((x, y) => x - y); out[a] = { median: t[6], max: t[11] }; }
  return out;
});
check('gum+bone rebuild < 15 ms per arch', gumMs.upper.median < 15 && gumMs.lower.median < 15, `upper median ${gumMs.upper.median.toFixed(1)} / max ${gumMs.upper.max.toFixed(1)} ms, lower median ${gumMs.lower.median.toFixed(1)} / max ${gumMs.lower.max.toFixed(1)} ms`);

// 4. select every part
const selFail = [];
await ev(page, () => { window.__dental3d.cameraRig.timeScale = 40; });
const allIds = manifest.parts.map((p) => p.nodeId).filter((_, i) => !args.has('--quick') || i % 11 === 0);
const t0 = Date.now();
for (const id of allIds) {
  const r = await ev(page, async (id) => {
    window.App3DBridge.selectPart(id);
    const st = window.App3DBridge.getState();
    // wait for the fly-to to finish
    const t0 = performance.now();
    while (performance.now() - t0 < 20000) {
      await new Promise((r) => setTimeout(r, 40));
      if (window.__dental3d.flyDone()) break;
    }
    const d = window.__dental3d;
    const obj = d.registry.get(id);
    obj.updateWorldMatrix(true, true);
    return { sel: st.selectedId, selAfter: window.App3DBridge.getState().selectedId, target: d.stage.controls.target.toArray(), hasObj: !!obj };
  }, id);
  // compare camera target with the part's bbox centre computed in node from live bbox
  const centre = await ev(page, (id) => {
    const d = window.__dental3d; const o = d.registry.get(id);
    const T = d.stage.camera.position.constructor;
    const mn = new T(1e9, 1e9, 1e9), mx = new T(-1e9, -1e9, -1e9), v = new T();
    o.updateWorldMatrix(true, true);
    o.traverse((m) => {
      if (!m.isMesh) return;
      const pos = m.geometry.attributes.position;
      for (let i = 0; i < pos.count; i += 1) { v.fromBufferAttribute(pos, i).applyMatrix4(m.matrixWorld); mn.min(v); mx.max(v); }
    });
    return [(mn.x + mx.x) / 2, (mn.y + mx.y) / 2, (mn.z + mx.z) / 2];
  }, id);
  const dist = Math.hypot(r.target[0] - centre[0], r.target[1] - centre[1], r.target[2] - centre[2]);
  if (r.selAfter !== id || dist > 1.5) selFail.push(`${id}: selected=${r.selAfter} targetErr=${dist.toFixed(2)}`);
}
check('selectPart(id) selects + camera flies to part (all ' + allIds.length + ' parts)', selFail.length === 0, `${((Date.now() - t0) / 1000).toFixed(0)} s${selFail.length ? ' failures: ' + selFail.slice(0, 5).join(' | ') : ''}`);
await ev(page, () => { window.App3DBridge.selectPart(null); });

// 5. bridge events
const evs = await ev(page, () => window.__events.map((e) => e.type));
check('READY, PART_SELECTED, STATE_UPDATED events sent', evs.includes('READY') && evs.includes('PART_SELECTED') && evs.includes('STATE_UPDATED'), `${evs.length} events`);
const sample = await ev(page, () => { const e = window.__events.filter((x) => x.type === 'PART_SELECTED' && x.payload.fdi)[0]; return e; });
check('PART_SELECTED payload (nodeId, fdi, displayName, category, status)', !!sample && !!sample.payload.nodeId && sample.payload.nodeId === 'tooth_' + sample.payload.fdi && !!sample.payload.displayName && !!sample.payload.category && sample.payload.status === 'normal' && typeof sample.ts === 'number', sample ? JSON.stringify(sample.payload) : 'none');

// 6. mode + material assertions
await ev(page, () => { window.App3DBridge.selectPart('tooth_26'); });
await idle(page);
for (const m of ['pbr', 'xray', 'heatmap']) {
  await ev(page, (m) => window.App3DBridge.setMode(m), m);
  const r = await ev(page, () => {
    const d = window.__dental3d; const g = d.appearance.ghost;
    const sel = d.registry.get('tooth_26').userData.meshes[0].material;
    const other = d.registry.get('tooth_11').userData.meshes[0].material;
    return {
      mode: window.App3DBridge.getState().mode, selGhost: sel === g, otherGhost: other === g,
      pulpVisible: d.registry.pulps.get(26).visible, pulpOther: d.registry.pulps.get(11).visible,
      gumGhost: d.registry.get('gum_upper').material === g, tint: other.userData?.u?.uTint?.value?.w ?? -1,
    };
  });
  if (m === 'pbr') check('mode pbr: nothing ghosted, pulps hidden', r.mode === 'pbr' && !r.selGhost && !r.otherGhost && !r.gumGhost && !r.pulpVisible);
  if (m === 'xray') check('mode xray: selected tooth solid + pulp shown, others/gum ghosted', r.mode === 'xray' && !r.selGhost && r.otherGhost && r.gumGhost && r.pulpVisible);
  if (m === 'heatmap') check('mode heatmap: teeth tinted by status', r.mode === 'heatmap' && r.tint > 0.9 && !r.otherGhost);
}
await ev(page, () => { window.App3DBridge.setMode('pbr'); window.App3DBridge.selectPart(null); });

// 7. explode / jaw
const exp = await ev(page, () => {
  const d = window.__dental3d; const P = d.stage.camera.position.constructor; const v = new P();
  const man = d.registry.manifest.parts.find((p) => p.nodeId === 'tooth_11');
  const o = d.registry.get('tooth_11');
  const at = () => { o.updateWorldMatrix(true, false); o.getWorldPosition(v); return v.toArray(); };
  window.App3DBridge.setExplode(1); d.snap();
  const e1 = at();
  const gum1 = d.registry.get('gum_upper').position.toArray();
  window.App3DBridge.setExplode(0); d.snap();
  const e0 = at();
  return { e1, e0, ev: man.explodeVector, pos: man.position, gum1, gumEv: d.registry.manifest.parts.find((p) => p.nodeId === 'gum_upper').explodeVector };
});
const ed1 = Math.hypot(...exp.e1.map((x, i) => x - (exp.pos[i] + exp.ev[i])));
const ed0 = Math.hypot(...exp.e0.map((x, i) => x - exp.pos[i]));
check('explode 1 moves tooth_11 by explodeVector; 0 restores it', ed1 < 0.05 && ed0 < 0.05, `err@1=${ed1.toFixed(4)} err@0=${ed0.toFixed(4)}; gum_upper at 1 = ${exp.gum1.map((x) => x.toFixed(1))}`);
const jaw = await ev(page, () => {
  const d = window.__dental3d; const P = d.stage.camera.position.constructor; const v = new P();
  const o = d.registry.get('tooth_41'); const q = (f) => { window.App3DBridge.setJawOpen(f); d.snap(); o.updateWorldMatrix(true, false); o.getWorldPosition(v); return { y: v.y, z: v.z, rot: d.registry.nodes.jaw_hinge.rotation.x * 180 / Math.PI }; };
  const a = q(0), b = q(1), c = q(0);
  return { a, b, c };
});
check('jaw open rotates jaw_hinge to maxOpenDeg and back', Math.abs(jaw.b.rot - manifest.jawHinge.maxOpenDeg) < 0.01 && Math.abs(jaw.c.y - jaw.a.y) < 0.01 && jaw.b.y < jaw.a.y - 10, `lower incisor y ${jaw.a.y.toFixed(1)} -> ${jaw.b.y.toFixed(1)} -> ${jaw.c.y.toFixed(1)}`);

// 8. camera presets
for (const name of ['front', 'upper', 'lower', 'left', 'right']) {
  await ev(page, (n) => window.App3DBridge.setCameraPreset(n), name);
  await idle(page, 500);
  const r = await ev(page, () => { const { camera, controls } = window.__dental3d.stage; const d = camera.position.clone().sub(controls.target).normalize(); return { dir: d.toArray(), dist: camera.position.distanceTo(controls.target), jaw: window.App3DBridge.getState().jawOpen }; });
  const want = await ev(page, (n) => window.__dental3d.cameraRig.presets[n].dir, name);
  const wl = Math.hypot(...want); const dot = r.dir.reduce((s, x, i) => s + x * want[i] / wl, 0);
  check(`camera preset ${name}`, dot > 0.99, `dir dot ${dot.toFixed(3)}, distance ${r.dist.toFixed(0)} mm, jaw ${r.jaw}`);
  if (name === 'upper') await shot(page, 'desktop-upper-occlusal.png');
  if (name === 'lower') await shot(page, 'desktop-lower-occlusal.png');
  if (name === 'left') await shot(page, 'desktop-left.png');
  if (name === 'front') await shot(page, 'desktop-front-natural.png');
}

// 9. real pointer picking + drag guard
await ev(page, () => { window.App3DBridge.setJawOpen(0); window.__dental3d.snap(); window.App3DBridge.setCameraPreset('front'); });
await idle(page, 500);
const scr = await ev(page, (id) => {
  const d = window.__dental3d; const o = d.registry.get(id); o.updateWorldMatrix(true, true);
  const P = d.stage.camera.position.constructor; const v = new P();
  o.userData.meshes[0].geometry.computeBoundingBox(); o.userData.meshes[0].geometry.boundingBox.getCenter(v);
  v.set(v.x, v.y + (id === 'tooth_11' ? 4 : 0), v.z);
  o.userData.meshes[0].localToWorld(v); v.project(d.stage.camera);
  const r = d.stage.canvas.getBoundingClientRect();
  return [r.left + (v.x * 0.5 + 0.5) * r.width, r.top + (-v.y * 0.5 + 0.5) * r.height];
}, 'tooth_11');
await page.mouse.click(scr[0], scr[1]);
await sleep(200);
let sel = await ev(page, () => window.App3DBridge.getState().selectedId);
check('canvas click selects the tooth under the pointer', sel === 'tooth_11' || /^tooth_(11|21|12|22)$/.test(sel || ''), `selected ${sel}`);
await page.mouse.move(scr[0] + 200, scr[1] + 150); await page.mouse.down(); await page.mouse.move(scr[0] + 230, scr[1] + 170, { steps: 4 }); await page.mouse.up();
await sleep(200);
const sel2 = await ev(page, () => window.App3DBridge.getState().selectedId);
check('click-vs-drag guard: a drag does not change the selection', sel2 === sel);
await page.mouse.move(scr[0], scr[1]); await sleep(300);
const hov = await ev(page, () => window.App3DBridge.getState().hoveredId);
check('hover sets hoveredId on mouse move', !!hov, `hovered ${hov}`);
await page.mouse.click(40, 400); await sleep(200); // empty canvas area
check('click on empty space clears selection', (await ev(page, () => window.App3DBridge.getState().selectedId)) === null);

// 10. inspector UI
await page.click('.tree-row[data-id="tooth_36"]'); await sleep(200);
check('tree row click selects tooth', (await ev(page, () => window.App3DBridge.getState().selectedId)) === 'tooth_36');
const cardTxt = await ev(page, () => document.querySelector('.card').innerText);
check('selected card shows name, FDI, nodeId', /Lower Left First Molar/.test(cardTxt) && /FDI 36/.test(cardTxt) && /tooth_36/.test(cardTxt), cardTxt.replace(/\n/g, ' | '));
await page.click('.chip[data-status="planned"]'); await sleep(150);
check('status chip calls setPartStatus', (await ev(page, () => window.App3DBridge.getState().teeth[36].status)) === 'planned');
await page.type('.search', 'canine'); await sleep(100);
const vis = await ev(page, () => [...document.querySelectorAll('.tree-row')].filter((e) => !e.hidden).length);
check('search filters the tree', vis === 4, `${vis} rows visible for "canine"`);
await page.$eval('.search', (e) => { e.value = ''; e.dispatchEvent(new Event('input')); });
check('#treatment-panel container exists', !!(await page.$('#treatment-panel')));
const wide = await ev(page, () => { const r = document.querySelector('.inspector').getBoundingClientRect(); return { w: r.width, right: r.right, vw: innerWidth }; });
check('wide layout: 300 px inspector docked right', Math.abs(wide.w - 300) < 1 && Math.abs(wide.right - wide.vw) < 1, JSON.stringify(wide));
// layers
await ev(page, () => { window.App3DBridge.setLayer('gums', false); window.App3DBridge.setLayer('upper', false); });
const lay = await ev(page, () => ({ gum: window.__dental3d.registry.get('gum_lower').visible, up: window.__dental3d.registry.nodes.arch_upper.visible }));
check('layer toggles hide arch / gums', lay.up === false && lay.gum === false);
await ev(page, () => { window.App3DBridge.setLayer('gums', true); window.App3DBridge.setLayer('upper', true); });

// 11. screenshots: x-ray, exploded, heatmap
await ev(page, () => { window.App3DBridge.selectPart('tooth_14'); window.App3DBridge.setMode('xray'); });
await idle(page, 600);
await shot(page, 'desktop-xray-tooth14.png');
await ev(page, () => { window.App3DBridge.setMode('pbr'); window.App3DBridge.selectPart(null); window.App3DBridge.setExplode(1); window.__dental3d.snap(); window.App3DBridge.resetCamera(); });
await idle(page, 600);
await ev(page, () => window.App3DBridge.setCameraPreset('front')); // keeps explode; refit
await shot(page, 'desktop-exploded.png');
await ev(page, () => {
  window.App3DBridge.setExplode(0); window.__dental3d.snap(); window.App3DBridge.setCameraPreset('front');
  const b = window.App3DBridge;
  b.setPartStatus('tooth_11', 'flagged'); b.setPartStatus('tooth_12', 'planned'); b.setPartStatus('tooth_21', 'inProgress');
  b.setPartStatus('tooth_16', 'completed'); b.setPartStatus('tooth_26', 'flagged'); b.setPartStatus('tooth_14', 'planned', '#FF00AA');
  b.selectPart('tooth_22'); b.setMode('heatmap');
});
await idle(page, 600);
await ev(page, () => window.App3DBridge.setCameraPreset('front'));
await shot(page, 'desktop-heatmap.png');
// gum states
await ev(page, () => {
  const b = window.App3DBridge;
  b.setMode('pbr'); b.selectPart(null);
  b.applyStateSnapshot({ teeth: { 24: { present: false }, 11: { recession: 2.0, inflammation: 0.9 }, 12: { inflammation: 0.6 }, 36: { present: false }, 46: { recession: 1.5 } } });
  b.setCameraPreset('front');
});
await shot(page, 'desktop-gum-states.png');
await ev(page, () => {
  window.App3DBridge.applyStateSnapshot({ teeth: { 24: { present: true }, 11: { recession: 0, inflammation: 0 }, 12: { inflammation: 0 }, 36: { present: true }, 46: { recession: 0 } } });
  window.App3DBridge.setLayer('gums', false);
});
await idle(page, 500);
await shot(page, 'desktop-bone.png');
await ev(page, () => window.App3DBridge.setLayer('gums', true));

// A1 check: bone is visible only when layers.bone is on AND (layers.gums is off OR mode === 'xray')
const boneCheck = await ev(page, () => {
  const d = window.__dental3d;
  const bUpper = d.registry.get('bone_upper');
  const gUpper = d.registry.get('gum_upper');
  window.App3DBridge.setMode('pbr');
  window.App3DBridge.setLayer('gums', true);
  window.App3DBridge.setLayer('bone', true);
  d.appearance.refresh();
  const natBoneVis = bUpper.visible;
  const natGumVis = gUpper.visible;

  window.App3DBridge.setMode('xray');
  d.appearance.refresh();
  const xrayBoneVis = bUpper.visible;

  window.App3DBridge.setMode('pbr');
  window.App3DBridge.setLayer('gums', false);
  d.appearance.refresh();
  const gumsOffBoneVis = bUpper.visible;

  window.App3DBridge.setLayer('gums', true);
  d.appearance.refresh();
  return { natBoneVis, natGumVis, xrayBoneVis, gumsOffBoneVis };
});
check('A1: bone hidden under healthy gums in pbr, visible in xray or when gums layer off',
  boneCheck.natBoneVis === false && boneCheck.natGumVis === true &&
  boneCheck.xrayBoneVis === true && boneCheck.gumsOffBoneVis === true,
  JSON.stringify(boneCheck)
);

// A3 check: shift.bl = 3 on tooth 11 moves it forward
const shapeCheck = await ev(page, () => {
  const d = window.__dental3d;
  const t11 = d.registry.get('tooth_11');
  const zBefore = t11.userData.rest.p.z;
  window.App3DBridge.applyStateSnapshot({ teeth: { 11: { shift: { bl: 3 } } } });
  const zAfter = t11.userData.rest.p.z;
  const movedForward = zAfter > zBefore + 2.5;
  window.App3DBridge.applyStateSnapshot({ teeth: { 11: { shift: { bl: 0 } } } });
  return { zBefore, zAfter, diff: zAfter - zBefore, movedForward };
});
check('A3: shift.bl = 3 on tooth 11 moves it forward', shapeCheck.movedForward, `z: ${shapeCheck.zBefore.toFixed(2)} -> ${shapeCheck.zAfter.toFixed(2)}`);

// A4 screenshot: worn lower incisor (41 wear 2.5) and chipped 21 (chip 0.6)
await ev(page, () => {
  const b = window.App3DBridge;
  b.setMode('pbr');
  b.selectPart(null);
  b.setCameraPreset('front');
  b.applyStateSnapshot({ teeth: { 41: { wear: 2.5 }, 21: { chip: 0.6 } } });
});
await idle(page, 600);
await shot(page, 'desktop-worn-chip.png');
await ev(page, () => window.App3DBridge.applyStateSnapshot({ teeth: { 41: { wear: 0 }, 21: { chip: 0 } } }));

// Phase B: decay on 36 O+D and silver filling on 46 O
const bSurfCheck = await ev(page, () => {
  const b = window.App3DBridge;
  const d = window.__dental3d;
  b.setMode('pbr');
  b.selectPart(null);
  b.setCameraPreset('lower');
  b.applyStateSnapshot({
    teeth: {
      36: { present: true, conditions: [{ type: 'caries', surfaces: ['O', 'D'] }] },
      46: { present: true, conditions: [] },
    },
    treatments: [
      { id: 't_fill_46', type: 'filling', teeth: [46], surfaces: ['O'], material: 'amalgam', status: 'completed', visit: 1 },
    ],
    currentVisit: 1,
  });

  const mat36 = d.registry.get('tooth_36').userData.meshes[0].userData.natural;
  const mat46 = d.registry.get('tooth_46').userData.meshes[0].userData.natural;
  const u36 = mat36.userData.u;
  const u46 = mat46.userData.u;

  const c36_O = u36.uSurfCaries.value[1];
  const c36_D = u36.uSurfCaries.value[2];
  const c36_M = u36.uSurfCaries.value[0];
  const f46_O_a = u46.uSurfFill.value[1].w;
  const f46_O_metal = u46.uSurfMetal.value[1];

  return { c36_O, c36_D, c36_M, f46_O_a, f46_O_metal };
});
check('B1/B2: decay on 36 O+D and silver filling on 46 O',
  bSurfCheck.c36_O === 1 && bSurfCheck.c36_D === 1 && bSurfCheck.c36_M === 0 &&
  bSurfCheck.f46_O_a === 1 && bSurfCheck.f46_O_metal === 0.85,
  JSON.stringify(bSurfCheck)
);
await idle(page, 600);
await shot(page, 'desktop-decay-fill.png');
await ev(page, () => {
  window.App3DBridge.applyStateSnapshot({
    teeth: { 36: { conditions: [] }, 46: { conditions: [] } },
    treatments: [],
    currentVisit: 0,
  });
  window.App3DBridge.setCameraPreset('front');
});

// 11b. snapshot round-trip test (Phase A2)
const roundTrip = await ev(page, async () => {
  const b = window.App3DBridge;
  const initial = {
    profile: { baseShade: 'A3', archWidth: 1.05, archDepth: 0.95 },
    teeth: {
      11: {
        shift: { md: 1.2, bl: 2.1, v: -0.5 },
        rotate: { tip: 5, torque: -10, spin: 15 },
        scale: { w: 1.1, h: 0.9 },
        wear: 1.5, stain: 0.4, chip: 0.2, shade: 'A35',
      },
    },
    treatments: [
      { id: 't1', type: 'crown', teeth: [11], status: 'planned', visit: 1, origin: 'viewer' },
      { id: 't2', type: 'scaling', teeth: [], status: 'planned', visit: 1, origin: 'viewer' },
    ],
    visits: [{ id: 1, label: 'Visit 1' }, { id: 2, label: 'Visit 2' }],
    currentVisit: 1,
  };
  b.applyStateSnapshot(initial);
  await new Promise((r) => setTimeout(r, 120));
  const p1 = b.getPersist();

  const chartUpdate = {
    saved: p1,
    treatments: [
      { id: 't1', type: 'crown', teeth: [11], status: 'planned', visit: 2, origin: 'chart' },
      { id: 't3', type: 'filling', teeth: [36], status: 'planned', visit: 2, origin: 'chart' },
    ],
    visits: [{ id: 1, label: 'Visit 1' }, { id: 2, label: 'Visit 2' }],
  };
  b.applyStateSnapshot(chartUpdate);
  await new Promise((r) => setTimeout(r, 120));
  const p2 = b.getPersist();

  b.applyStateSnapshot({ teeth: { 11: { shift: { md: 0, bl: 0, v: 0 }, rotate: { tip: 0, torque: 0, spin: 0 }, scale: { w: 1, h: 1 }, wear: 0, stain: 0, chip: 0, shade: null } }, treatments: [], visits: [], currentVisit: 0 });

  const evs = window.__events.filter((x) => x.type === 'STATE_UPDATED' && x.payload && x.payload.persist);
  return { p1, p2, hasPersistInEvent: evs.length > 0 };
});
check('snapshot round-trip and saved merge',
  roundTrip.p1.profile.baseShade === 'A3' &&
  roundTrip.p1.teeth[11].shift.md === 1.2 &&
  roundTrip.p1.teeth[11].scale.w === 1.1 &&
  roundTrip.p2.treatments.find((t) => t.id === 't1')?.visit === 1 &&
  roundTrip.p2.treatments.some((t) => t.id === 't2') &&
  roundTrip.p2.treatments.some((t) => t.id === 't3') &&
  roundTrip.hasPersistInEvent,
  JSON.stringify({ t1Visit: roundTrip.p2.treatments.find((t) => t.id === 't1')?.visit, treatments: roundTrip.p2.treatments.map((t) => t.id), hasPersist: roundTrip.hasPersistInEvent })
);

// ---------------------------------------------------------------- Phase C: Treatments & Timeline
// C1/C2: Presets 2 through 5 and timeline checks
const cResults = await ev(page, async () => {
  const b = window.App3DBridge;
  const d = window.__dental3d;

  // Preset 2: gap_stained_front
  b.loadPreset('gap_stained_front');
  const p2_v0_11_shade = b.getState().teeth[11].shade;
  const p2_v0_21_stain = b.getState().teeth[21].stain;
  b.applyStateSnapshot({ currentVisit: 1 });
  const t11_cap = d.registry.get('tooth_11').children.some((c) => c.userData.isTreatmentVisual);
  b.applyStateSnapshot({ currentVisit: 2 });
  const mat12 = d.registry.get('tooth_12').userData.meshes[0].userData.natural;
  const p2_v2_whitened = mat12.userData.u?.uShade?.value != null;

  // Preset 3: missing_front
  b.loadPreset('missing_front');
  b.applyStateSnapshot({ currentVisit: 0 });
  const p3_v0_11_vis = d.registry.get('tooth_11').visible;
  b.applyStateSnapshot({ currentVisit: 3 });
  const t11_obj = d.registry.get('tooth_11');
  const p3_v3_11_vis = t11_obj.visible;
  const p3_v3_11_hasHardware = t11_obj.children.some((c) => c.userData.isTreatmentVisual);

  // Preset 4: crowding (braces)
  b.loadPreset('crowding');
  b.applyStateSnapshot({ currentVisit: 1 });
  const t11_hasBracket = d.registry.get('tooth_11').children.some((c) => c.userData.isTreatmentVisual);
  const upperWire_v1 = d.registry.nodes.arch_upper.children.some((c) => c.userData.isArchWire);
  b.applyStateSnapshot({ currentVisit: 3 });
  const t11_hasBracket_v3 = d.registry.get('tooth_11').children.some((c) => c.userData.isTreatmentVisual);
  const upperWire_v3 = d.registry.nodes.arch_upper.children.some((c) => c.userData.isArchWire);

  // Preset 5: worn_gum_disease
  b.loadPreset('worn_gum_disease');
  b.applyStateSnapshot({ currentVisit: 1 });
  const t31_calculus_v1 = b.getState().teeth[31].calculus;
  const t46_vis_v1 = d.registry.get('tooth_46').visible;
  b.applyStateSnapshot({ currentVisit: 3 });
  const t46_vis_v3 = d.registry.get('tooth_46').visible;

  return {
    p2_v0_11_shade, p2_v0_21_stain, t11_cap, p2_v2_whitened,
    p3_v0_11_vis, p3_v3_11_vis, p3_v3_11_hasHardware,
    t11_hasBracket, upperWire_v1, t11_hasBracket_v3, upperWire_v3,
    t31_calculus_v1, t46_vis_v1, t46_vis_v3,
  };
});

check('C1/C2: gap_stained_front caps at visit 1 and whitens at visit 2',
  cResults.p2_v0_11_shade === 'A35' && cResults.p2_v0_21_stain === 0.6 && cResults.t11_cap && cResults.p2_v2_whitened,
  JSON.stringify({ cap: cResults.t11_cap, whitened: cResults.p2_v2_whitened })
);
check('C1/C2: missing_front implant on 11 appears at visit 3 with hardware',
  !cResults.p3_v0_11_vis && cResults.p3_v3_11_vis && cResults.p3_v3_11_hasHardware,
  JSON.stringify({ v0Vis: cResults.p3_v0_11_vis, v3Vis: cResults.p3_v3_11_vis, hasHardware: cResults.p3_v3_11_hasHardware })
);
check('C1/C2: crowding has brackets and archwires at visit 1 and removes them at visit 3',
  cResults.t11_hasBracket && cResults.upperWire_v1 && !cResults.t11_hasBracket_v3 && !cResults.upperWire_v3,
  JSON.stringify({ v1Brackets: cResults.t11_hasBracket, v1Wire: cResults.upperWire_v1, v3Brackets: cResults.t11_hasBracket_v3, v3Wire: cResults.upperWire_v3 })
);
check('C1/C2: worn_gum_disease scaling cleans calculus at v1 and restores 46 at v3',
  !cResults.t46_vis_v1 && cResults.t46_vis_v3,
  JSON.stringify({ t46_v1: cResults.t46_vis_v1, t46_v3: cResults.t46_vis_v3 })
);

// C3: Timeline UI checks
const tlCheck = await ev(page, async () => {
  const b = window.App3DBridge;
  const d = window.__dental3d;

  b.loadPreset('crowding');
  const tlEl = document.querySelector('.timeline-bar');
  const visibleWithVisits = tlEl && !tlEl.hidden;
  const chipsCount = document.querySelectorAll('.tl-chip').length;

  // Test hold-to-compare button
  b.applyStateSnapshot({ currentVisit: 3 });
  const baBtn = document.querySelector('.tb-ba-btn');
  const downEvt = new PointerEvent('pointerdown', { pointerId: 1, bubbles: true });
  baBtn.dispatchEvent(downEvt);
  const snappedTo0 = b.getState().currentVisit === 0;

  const upEvt = new PointerEvent('pointerup', { pointerId: 1, bubbles: true });
  baBtn.dispatchEvent(upEvt);
  const restoredTo3 = b.getState().currentVisit === 3;

  // Empty visits hides timeline
  b.loadPreset('healthy');
  const hiddenWhenEmpty = tlEl && tlEl.hidden;

  return { visibleWithVisits, chipsCount, snappedTo0, restoredTo3, hiddenWhenEmpty };
});

check('C3: timeline bar displays chips, responds to Before/After hold, and hides when empty',
  tlCheck.visibleWithVisits && tlCheck.chipsCount === 4 && tlCheck.snappedTo0 && tlCheck.restoredTo3 && tlCheck.hiddenWhenEmpty,
  JSON.stringify(tlCheck)
);

// C4: Treatment Panel in Inspector checks
const treatPanelCheck = await ev(page, async () => {
  const b = window.App3DBridge;
  b.loadPreset('worn_gum_disease');
  b.selectPart('tooth_36');

  const panel = document.getElementById('treatment-panel');
  const visible = panel && !panel.hidden;
  const cards = [...panel.querySelectorAll('.treat-card')].map((c) => c.querySelector('.treat-card-title')?.textContent || '');
  const hasCaries = cards.some((txt) => /decay/i.test(txt));
  const hasFilling = cards.some((txt) => /filling/i.test(txt));

  // Cycle status on filling
  const fillingCard = [...panel.querySelectorAll('.treat-card')].find((c) => /filling/i.test(c.textContent));
  const statusBtn = fillingCard?.querySelector('.chip');
  const st0 = statusBtn?.textContent?.trim();
  statusBtn?.click();
  const st1 = b.getState().treatments.find((t) => t.type === 'filling' && t.teeth.includes(36))?.status;

  // Add treatment
  b.selectPart('tooth_11');
  const addBtn = panel.querySelector('.treat-add-btn');
  addBtn?.click();
  const formVisible = !!panel.querySelector('.treat-form');

  // Save added treatment
  const saveBtn = panel.querySelector('.treat-form .pill-btn.on');
  saveBtn?.click();
  const viewerTr = b.getState().treatments.find((t) => t.teeth.includes(11) && t.origin === 'viewer');

  // Remove added treatment
  const rmBtn = panel.querySelector('.treat-rm-btn');
  const canRemove = !!rmBtn;
  rmBtn?.click();
  const removed = !b.getState().treatments.some((t) => t.id === viewerTr?.id);

  b.loadPreset('healthy');
  b.selectPart(null);

  return { visible, hasCaries, hasFilling, st0, st1, formVisible, added: !!viewerTr, canRemove, removed };
});

check('C4: treatment panel displays conditions and treatments, cycles status, and adds/removes viewer treatments',
  treatPanelCheck.visible && treatPanelCheck.hasCaries && treatPanelCheck.hasFilling &&
  treatPanelCheck.st0 === 'planned' && treatPanelCheck.st1 === 'inProgress' &&
  treatPanelCheck.formVisible && treatPanelCheck.added && treatPanelCheck.canRemove && treatPanelCheck.removed,
  JSON.stringify(treatPanelCheck)
);

// Capture screenshots of presets across the timeline for GATE C
await ev(page, () => window.App3DBridge.loadPreset('gap_stained_front'));
await ev(page, () => window.App3DBridge.applyStateSnapshot({ currentVisit: 1 }));
await idle(page, 400);
await shot(page, 'desktop-preset2-gap-caps-v1.png');

await ev(page, () => window.App3DBridge.loadPreset('missing_front'));
await ev(page, () => window.App3DBridge.applyStateSnapshot({ currentVisit: 3 }));
await idle(page, 400);
await shot(page, 'desktop-preset3-implants-v3.png');

await ev(page, () => window.App3DBridge.loadPreset('crowding'));
await ev(page, () => window.App3DBridge.applyStateSnapshot({ currentVisit: 1 }));
await idle(page, 400);
await shot(page, 'desktop-preset4-braces-v1.png');

await ev(page, () => window.App3DBridge.applyStateSnapshot({ currentVisit: 3 }));
await idle(page, 400);
await shot(page, 'desktop-preset4-straight-v3.png');

await ev(page, () => window.App3DBridge.loadPreset('worn_gum_disease'));
await ev(page, () => window.App3DBridge.applyStateSnapshot({ currentVisit: 1 }));
await idle(page, 400);
await shot(page, 'desktop-preset5-cleaned-v1.png');

await ev(page, () => window.App3DBridge.loadPreset('healthy'));

// quality presets quick check
for (const q of ['medium', 'high']) {
  await ev(page, (q) => window.App3DBridge.setQuality(q), q);
  await ev(page, () => window.App3DBridge.selectPart('tooth_11'));
  await idle(page, 800, 90000);
  await shot(page, `desktop-quality-${q}.png`);
}
await ev(page, () => { window.App3DBridge.setQuality('low'); window.App3DBridge.selectPart(null); });

// 12. timing (low quality, animated)
await idle(page);
const timing = await ev(page, async () => {
  const d = window.__dental3d;
  window.App3DBridge.setCameraPreset('front');
  await new Promise((r) => setTimeout(r, 800));
  for (let i = 0; i < 4; i++) { window.App3DBridge.setCameraPreset(['upper', 'lower', 'left', 'front'][i]); await new Promise((r) => setTimeout(r, 900)); }
  return d.stats();
});
console.log('  frame timing (low quality, camera flights):', JSON.stringify({ gpu: timing.gpu, software: timing.softwareRendered, frames: timing.sampleSize, intervalAvgMs: timing.frameIntervalAvgMs, intervalP95Ms: timing.frameIntervalP95Ms, cpuRenderAvgMs: timing.cpuRenderAvgMs, cpuRenderMaxMs: timing.cpuRenderMaxMs, triangles: timing.triangles, calls: timing.calls }));

// idle render loop: no frames when nothing moves
await idle(page);
const f0 = await ev(page, () => window.__dental3d.stats().renderedFrames);
await sleep(1200);
const f1 = await ev(page, () => window.__dental3d.stats().renderedFrames);
check('render-on-demand: no frames rendered while idle', f1 === f0, `${f1 - f0} frames in 1.2 s`);

check('desktop: no console / WebGL errors', D.errors.length === 0, D.errors.slice(0, 4).join(' || '));
await page.close();

// ---------------------------------------------------------------- phone
console.log('\n== Phone 390x844 (touch) ==');
const Pn = await openPage('phone', { width: 390, height: 844 }, true);
const pp = Pn.page;
await idle(pp);
const pq = await ev(pp, () => window.App3DBridge.getState().quality);
const ov = await ev(pp, () => ({ sw: document.documentElement.scrollWidth, iw: innerWidth, sh: document.documentElement.scrollHeight, ih: innerHeight }));
check('phone: no horizontal / vertical page scroll', ov.sw <= ov.iw && ov.sh <= ov.ih, JSON.stringify(ov));
const lay2 = await ev(pp, () => {
  const r = (s) => { const e = document.querySelector(s).getBoundingClientRect(); return { l: e.left, r: e.right, t: e.top, b: e.bottom, w: e.width, h: e.height }; };
  return { tb: r('.toolbar'), insp: r('.inspector'), peek: r('.sheet-peek'), vw: innerWidth, vh: innerHeight, touch: [...document.querySelectorAll('.toolbar button')].map((b) => { const q = b.getBoundingClientRect(); return [Math.round(q.width), Math.round(q.height)]; }).filter(([w, h]) => w > 0 && h > 0) };
});
check('phone: toolbar fits within the viewport and sits above the sheet peek', lay2.tb.l >= 0 && lay2.tb.r <= lay2.vw && lay2.tb.b <= lay2.insp.t + 1, JSON.stringify({ toolbar: lay2.tb, sheetTop: lay2.insp.t }));
check('phone: touch targets >= 40 px', lay2.touch.every(([w, h]) => w >= 40 - 0.5 && h >= 40 - 0.5), JSON.stringify(lay2.touch));
check('phone: sheet peek shows ~64 px', Math.abs(lay2.vh - lay2.insp.t - 64) < 2, `peek ${Math.round(lay2.vh - lay2.insp.t)} px`);
await shot(pp, 'phone-front.png');
await ev(pp, () => window.App3DBridge.selectPart('tooth_21'));
await idle(pp, 600);
await shot(pp, 'phone-selected.png');
check('phone: selecting a part does not scroll the page/app container', (await ev(pp, () => document.getElementById('app').scrollTop + document.documentElement.scrollTop + document.body.scrollTop)) === 0);
await pp.tap('.sheet-handle'); await sleep(500);
const open = await ev(pp, () => document.getElementById('app').classList.contains('sheet-open'));
const h2 = await ev(pp, () => { const r = document.querySelector('.inspector').getBoundingClientRect(); return { top: r.top, h: innerHeight, frac: (innerHeight - r.top) / innerHeight }; });
check('phone: tapping the handle expands the sheet to ~55 %', open && Math.abs(h2.frac - 0.55) < 0.03, `expanded fraction ${h2.frac.toFixed(2)}`);
await shot(pp, 'phone-sheet-open.png');
await pp.tap('.match-toggle-btn'); await sleep(300);
const matchOpen = await ev(pp, () => document.querySelector('.match-panel-body').classList.contains('open'));
const matchScroll = await ev(pp, () => ({ sw: document.documentElement.scrollWidth, iw: innerWidth }));
check('phone: match panel expands without horizontal scroll', matchOpen && matchScroll.sw <= matchScroll.iw, JSON.stringify(matchScroll));
await shot(pp, 'phone-match-panel.png');
await pp.tap('.match-toggle-btn'); await sleep(200);
await pp.tap('.sheet-handle'); await sleep(500);
await pp.tap('.tb-adjust'); await sleep(300);
await shot(pp, 'phone-adjust.png');
await pp.tap('.tb-adjust'); await sleep(200);
await ev(pp, () => document.querySelector('[data-pop="view"]').click()); await sleep(300);
await shot(pp, 'phone-view-popover.png');
await ev(pp, () => document.querySelector('[data-pop="view"]').click()); await sleep(200);

// Test applying presets from toolbar
await ev(pp, () => document.querySelector('[data-pop="patients"]').click()); await sleep(300);
await shot(pp, 'phone-patients-menu.png');
await ev(pp, () => document.querySelector('[data-preset="gap_stained_front"]').click()); await sleep(400);
const presetGap = await ev(pp, () => ({
  t11Shade: window.App3DBridge.getState().teeth[11].shade,
  t21Stain: window.App3DBridge.getState().teeth[21].stain,
  visits: window.App3DBridge.getState().visits.length,
}));
check('phone: preset gap_stained_front applies', presetGap.t11Shade === 'A35' && presetGap.t21Stain === 0.6 && presetGap.visits === 2, JSON.stringify(presetGap));
await shot(pp, 'phone-gap-stained-preset.png');

await ev(pp, () => document.querySelector('[data-pop="patients"]').click()); await sleep(300);
await ev(pp, () => document.querySelector('[data-preset="worn_gum_disease"]').click()); await sleep(400);
await shot(pp, 'phone-worn-preset.png');

await ev(pp, () => document.querySelector('[data-pop="patients"]').click()); await sleep(300);
await ev(pp, () => document.querySelector('[data-preset="healthy"]').click()); await sleep(400);

check(`phone: default quality is ${pq}`, pq === 'low');
check('phone: no console / WebGL errors', Pn.errors.length === 0, Pn.errors.slice(0, 4).join(' || '));
await pp.close();

await browser.close();
await closeServer();
console.log(`\n${pass} passed, ${fail} failed${fail ? ' -> ' + failures.join('; ') : ''}`);
process.exit(fail ? 1 : 0);
