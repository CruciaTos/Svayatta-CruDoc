// CruDoc muscle chart: three.js viewer for the physiotherapy specialty.
// Runs standalone in a browser, or inside the Flutter app through a WebView
// (?embed=1 hides the side panel; the host drives it through window.MuscleChart).
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { MeshoptDecoder } from 'three/addons/libs/meshopt_decoder.module.js';
import { frameBody } from './framing.js';

const params = new URLSearchParams(location.search);
const EMBED = params.has('embed');
const LITE = params.has('lite');
if (EMBED) document.body.classList.add('embed');

const STATUS = {
  affected: { color: 0xef4444, label: 'Affected' },
  improving: { color: 0xf59e0b, label: 'Improving' },
  resolved: { color: 0x22c55e, label: 'Resolved' },
};

// ---------------------------------------------------------------- host bridge
function send(msg) {
  try {
    if (window.flutter_inappwebview?.callHandler) window.flutter_inappwebview.callHandler('muscleChart', msg);
    else if (window.chrome?.webview?.postMessage) window.chrome.webview.postMessage(msg);
    else if (window.parent !== window) window.parent.postMessage({ source: 'muscleChart', ...msg }, '*');
  } catch (e) { console.warn('bridge', e); }
}

// ---------------------------------------------------------------- renderer
const canvas = document.getElementById('gl');
const stage = document.getElementById('stage');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: !LITE, alpha: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, LITE ? 1 : 1.75));
renderer.outputColorSpace = THREE.SRGBColorSpace;

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(32, 1, 0.01, 100);
scene.add(camera);
scene.add(new THREE.HemisphereLight(0xffffff, 0x8a8f99, 1.6));
const key = new THREE.DirectionalLight(0xffffff, 1.7);
key.position.set(0.6, 0.8, 1);
camera.add(key);
const rim = new THREE.DirectionalLight(0xdfe8ff, 0.5);
rim.position.set(-1, 0.3, -1);
camera.add(rim);

const controls = new OrbitControls(camera, canvas);
controls.enableDamping = true;
controls.dampingFactor = 0.12;
controls.screenSpacePanning = true;
controls.rotateSpeed = 0.8;
controls.zoomSpeed = 1.1;

// ---------------------------------------------------------------- materials
const mat = {
  muscle: new THREE.MeshStandardMaterial({ color: 0xb4544c, roughness: 0.55, metalness: 0 }),
  bone: new THREE.MeshStandardMaterial({ color: 0xe9e4d8, roughness: 0.7 }),
  boneGhost: ghost(0x7c8798, 0.03, 0.38),
  muscleGhost: ghost(0x5f6b7c, 0.02, 0.5),
};
const solidCache = new Map();
function solid(status, selected, hover) {
  const k = `${status}|${selected}|${hover}`;
  if (!solidCache.has(k)) {
    const base = status ? STATUS[status].color : selected ? 0x4f8ef7 : 0xb4544c;
    const m = new THREE.MeshStandardMaterial({ color: base, roughness: 0.5 });
    if (status) { m.emissive.setHex(base); m.emissiveIntensity = 0.28; }
    if (selected) { m.emissive.setHex(base); m.emissiveIntensity = status ? 0.55 : 0.3; }
    else if (hover) { m.emissive.setHex(0x93c5fd); m.emissiveIntensity = 0.35; }
    solidCache.set(k, m);
  }
  return solidCache.get(k);
}
// Frosted "x-ray" look: see-through in the middle, soft grey at the silhouette.
function ghost(edge, base, strength) {
  return new THREE.ShaderMaterial({
    uniforms: { uEdge: { value: new THREE.Color(edge) }, uBase: { value: base }, uStrength: { value: strength } },
    vertexShader: `
      varying vec3 vN; varying vec3 vV;
      void main() {
        vec4 mv = modelViewMatrix * vec4(position, 1.0);
        vN = normalize(normalMatrix * normal); vV = normalize(-mv.xyz);
        gl_Position = projectionMatrix * mv;
      }`,
    fragmentShader: `
      uniform vec3 uEdge; uniform float uBase; uniform float uStrength;
      varying vec3 vN; varying vec3 vV;
      void main() {
        float f = pow(1.0 - abs(dot(normalize(vN), normalize(vV))), 2.2);
        vec3 c = mix(vec3(1.0), uEdge, f);
        gl_FragColor = vec4(c, uBase + f * uStrength);
        #include <colorspace_fragment>
      }`,
    transparent: true, depthWrite: false, side: THREE.FrontSide,
  });
}

// ---------------------------------------------------------------- state
const state = {
  mode: 'anatomy',          // anatomy | focus | isolate
  skeleton: true,
  superficial: true,
  hidden: new Set(),
  selected: null,
  hover: null,
  findings: new Map(),      // id -> { status, condition, pain }
};
let catalog, byId = new Map(), muscles = [], bones = [], musclesById = new Map();
let rightSign = -1;         // world-x sign of the patient's right side
let bodyBox = new THREE.Box3();

// ---------------------------------------------------------------- load
const loader = new GLTFLoader().setMeshoptDecoder(MeshoptDecoder);
const loadBar = document.querySelector('#loading i');
Promise.all([
  fetch('catalog.json').then(r => r.json()),
  new Promise((res, rej) => loader.load('body.glb', res, e => {
    if (e.total) loadBar.style.width = `${(e.loaded / e.total) * 100}%`;
  }, rej)),
]).then(([cat, gltf]) => init(cat, gltf)).catch(err => {
  document.querySelector('#loading span').textContent = 'Could not load the model: ' + err;
  send({ type: 'error', message: String(err) });
});

function init(cat, gltf) {
  catalog = cat;
  for (const m of cat.muscles) byId.set(m.id, { ...m, kind: 'muscle' });
  for (const b of cat.bones) byId.set(b.id, { ...b, kind: 'bone' });
  const root = gltf.scene;
  scene.add(root);
  root.updateMatrixWorld(true);
  let rx = 0, rn = 0;
  root.traverse(o => {
    if (!o.isMesh) return;
    const info = byId.get(o.name) || byId.get(o.parent?.name);
    const id = byId.has(o.name) ? o.name : o.parent?.name;
    if (!info) return;
    o.userData.id = id;
    o.geometry.computeBoundingBox();
    o.userData.box = o.geometry.boundingBox.clone().applyMatrix4(o.matrixWorld);
    o.userData.center = o.userData.box.getCenter(new THREE.Vector3());
    bodyBox.union(o.userData.box);
    if (info.kind === 'muscle') {
      muscles.push(o); musclesById.set(id, o);
      if (info.side === 'R') { rx += o.userData.center.x; rn++; }
    } else { bones.push(o); o.material = mat.bone; }
  });
  rightSign = rn && rx / rn > bodyBox.getCenter(new THREE.Vector3()).x ? 1 : -1;
  // keep ghosts drawn after solids, bones' ghosts behind muscles' ghosts
  bones.forEach(b => (b.renderOrder = 1));
  muscles.forEach(m => (m.renderOrder = 2));

  applyMaterials();
  resize();
  setView('front', false);
  document.getElementById('loading').remove();
  buildUi();
  needsRender = true;
  send({ type: 'ready', muscles: muscles.length, bones: bones.length });
}

// ---------------------------------------------------------------- appearance
function applyMaterials() {
  const { mode } = state;
  for (const m of muscles) {
    const id = m.userData.id, info = byId.get(id);
    const f = state.findings.get(id);
    const status = f?.status || '';
    const sel = state.selected === id, hov = state.hover === id;
    const flagged = !!status || sel;
    let visible = !state.hidden.has(id) && (state.superficial || !info.superficial || flagged);
    let material;
    if (mode === 'anatomy') material = solid(status, sel, hov);
    else if (flagged) material = solid(status, sel, hov);
    else if (mode === 'focus') material = hov ? solid('', false, true) : mat.muscleGhost;
    else { visible = visible && hov; material = solid('', false, true); }
    m.visible = visible;
    m.material = material;
  }
  for (const b of bones) {
    b.visible = state.skeleton;
    b.material = mode === 'anatomy' ? mat.bone : mat.boneGhost;
  }
  needsRender = true;
}

// ---------------------------------------------------------------- camera
const DIRS = {
  front: new THREE.Vector3(0, 0.08, 1),
  back: new THREE.Vector3(0, 0.08, -1),
};
function sideDir(side) { return new THREE.Vector3(side === 'right' ? rightSign : -rightSign, 0.08, 0); }
function dirFor(name) { return name === 'left' || name === 'right' ? sideDir(name) : DIRS[name].clone(); }

let tween = null;
// The whole-body view (Front, Back, ...) currently shown, until the user or a
// region/muscle/zoom control moves the camera. It is re-framed whenever the
// stage is resized, so the body fills the stage at its final size even if the
// first frame was taken before the layout settled.
let autoView = null;
function frameBox(box, dir, animate = true, pad = 1.15) {
  const center = box.getCenter(new THREE.Vector3());
  const radius = box.getBoundingSphere(new THREE.Sphere()).radius;
  const fov = THREE.MathUtils.degToRad(camera.fov);
  const fit = Math.min(fov, 2 * Math.atan(Math.tan(fov / 2) * camera.aspect));
  const dist = (radius * pad) / Math.sin(fit / 2);
  const toPos = center.clone().add(dir.clone().normalize().multiplyScalar(dist));
  autoView = null;
  moveCamera(toPos, center, animate);
}
function moveCamera(toPos, toTarget, animate = true) {
  if (!animate) {
    tween = null;
    camera.position.copy(toPos); controls.target.copy(toTarget); controls.update(); needsRender = true; return;
  }
  tween = { t0: performance.now(), dur: 520, fromPos: camera.position.clone(), fromTarget: controls.target.clone(), toPos, toTarget };
}

// Pixels at the top and bottom of the stage covered by the overlay bars. The
// bars wrap onto more rows when the stage is narrow, so measure them.
function overlayInsets() {
  const s = stage.getBoundingClientRect();
  const top = document.querySelector('.bar.top').getBoundingClientRect();
  const bottom = document.querySelector('.bar.bottom').getBoundingClientRect();
  return {
    top: Math.max(0, top.bottom - s.top) + 6,
    bottom: Math.max(0, s.bottom - bottom.top) + 6,
  };
}
// Whole-body views (Front / Back / sides / reset): fill the clear area.
function setView(name, animate = true) {
  autoView = name;
  const { top, bottom } = overlayInsets();
  const { pos, target } = frameBody({
    box: bodyBox,
    dir: dirFor(name),
    fovDeg: camera.fov,
    aspect: camera.aspect,
    stageW: stage.clientWidth,
    stageH: stage.clientHeight,
    top,
    bottom,
    side: 12,
  });
  moveCamera(pos, target, animate);
}

const REGIONS = {
  neck: { re: /sternocleidomastoid|scalenus|levator scapulae|splenius/, sides: 'RL', dir: () => new THREE.Vector3(rightSign * 0.5, 0.15, 1) },
  shoulder: { re: /deltoid|supraspinatus|infraspinatus|teres (major|minor)|subscapularis/, pad: 1.7, sides: 'R', dir: () => new THREE.Vector3(rightSign * 1, 0.25, 0.6) },
  lowback: { re: /quadratus lumborum|lumborum|thoracolumbar/, sides: 'RLM', dir: () => DIRS.back.clone() },
  hip: { re: /gluteus|piriformis|gemellus|obturator internus|quadratus femoris/, sides: 'R', dir: () => new THREE.Vector3(rightSign * 0.6, 0.1, -1) },
  knee: { re: /popliteus/, pad: 3.2, sides: 'R', dir: () => new THREE.Vector3(rightSign * 0.5, 0.05, -1) },
  ankle: { re: /abductor hallucis|flexor digitorum brevis|extensor digitorum brevis|extensor hallucis brevis|quadratus plantae/, sides: 'R', dir: () => new THREE.Vector3(rightSign * 1, 0.25, 0.4) },
};
function frameRegion(key) {
  const r = REGIONS[key], box = new THREE.Box3();
  for (const m of muscles) {
    const info = byId.get(m.userData.id);
    if (r.sides.includes(info.side) && r.re.test(info.name.toLowerCase())) box.union(m.userData.box);
  }
  if (!box.isEmpty()) frameBox(box, r.dir(), true, r.pad || 1.25);
}
function frameMuscle(id) {
  const m = musclesById.get(id); if (!m) return;
  const dir = camera.position.clone().sub(controls.target).normalize();
  frameBox(m.userData.box, dir, true, 1.6);
}

// ---------------------------------------------------------------- picking
const ray = new THREE.Raycaster();
const ndc = new THREE.Vector2();
function pick(ev) {
  const r = canvas.getBoundingClientRect();
  ndc.set(((ev.clientX - r.left) / r.width) * 2 - 1, -((ev.clientY - r.top) / r.height) * 2 + 1);
  ray.setFromCamera(ndc, camera);
  let targets;
  if (state.mode === 'isolate') {
    targets = muscles.filter(m => !state.hidden.has(m.userData.id) && (state.superficial || !byId.get(m.userData.id).superficial));
  } else targets = muscles.filter(m => m.visible);
  const solidsFirst = state.mode === 'anatomy' ? targets : targets;
  const hit = ray.intersectObjects(solidsFirst, false)[0];
  return hit ? hit.object.userData.id : null;
}

let downAt = null, lastHoverT = 0;
canvas.addEventListener('pointerdown', e => { downAt = { x: e.clientX, y: e.clientY }; hideTip(); });
canvas.addEventListener('pointerup', e => {
  if (!downAt) return;
  const moved = Math.hypot(e.clientX - downAt.x, e.clientY - downAt.y) > 4;
  downAt = null;
  if (moved || e.button !== 0) return;
  select(pick(e));
});
canvas.addEventListener('dblclick', e => { const id = pick(e); if (id) { select(id); frameMuscle(id); } });
canvas.addEventListener('pointermove', e => {
  if (downAt) return;
  const now = performance.now();
  if (now - lastHoverT < 50) return;
  lastHoverT = now;
  const id = pick(e);
  if (id !== state.hover) { state.hover = id; applyMaterials(); }
  if (id) showTip(e, label(id)); else hideTip();
});
canvas.addEventListener('pointerleave', () => { if (state.hover) { state.hover = null; applyMaterials(); } hideTip(); });
window.addEventListener('keydown', e => {
  if (e.key === 'Escape') select(null);
  if ((e.key === 'h' || e.key === 'H') && state.selected && document.activeElement.tagName !== 'INPUT') hideMuscle(state.selected);
});

const tip = document.getElementById('tip');
function showTip(e, text) {
  const r = stage.getBoundingClientRect();
  tip.textContent = text; tip.style.display = 'block';
  tip.style.left = `${e.clientX - r.left + 14}px`; tip.style.top = `${e.clientY - r.top + 14}px`;
}
function hideTip() { tip.style.display = 'none'; }
function label(id) {
  const i = byId.get(id); if (!i) return id;
  const side = i.side === 'R' ? 'Right' : i.side === 'L' ? 'Left' : '';
  return `${side ? side + ' ' : ''}${i.name.replace(/ muscles?$/i, '').replace(/^./, c => c.toLowerCase()).replace(/^./, c => c.toUpperCase())}`;
}

// ---------------------------------------------------------------- actions
function select(id) {
  state.selected = id;
  applyMaterials();
  renderCard();
  const i = id && byId.get(id);
  send({ type: 'select', id, name: i?.name ?? null, side: i?.side ?? null, region: i?.region ?? null, finding: id ? state.findings.get(id) ?? null : null });
}
function setFinding(id, patch) {
  const cur = state.findings.get(id) || { status: '', condition: '', pain: 0 };
  const next = { ...cur, ...patch };
  if (!next.status && !next.condition && !next.pain) state.findings.delete(id); else state.findings.set(id, next);
  applyMaterials(); renderFindings(); renderCard();
  send({ type: 'finding', id, name: byId.get(id)?.name, side: byId.get(id)?.side, finding: state.findings.get(id) ?? null, all: window.MuscleChart.getFindings() });
}
function hideMuscle(id) { state.hidden.add(id); if (state.selected === id) select(null); applyMaterials(); }
function setMode(m) {
  state.mode = m;
  document.querySelectorAll('#modes button').forEach(b => b.classList.toggle('on', b.dataset.mode === m));
  applyMaterials();
}

// ---------------------------------------------------------------- side panel
function buildUi() {
  document.querySelectorAll('#modes button').forEach(b => b.onclick = () => setMode(b.dataset.mode));
  document.querySelectorAll('[data-view]').forEach(b => b.onclick = () => setView(b.dataset.view));
  document.querySelectorAll('[data-region]').forEach(b => b.onclick = () => frameRegion(b.dataset.region));
  const tSk = document.getElementById('tSkeleton'), tSu = document.getElementById('tSuperficial');
  tSk.onclick = () => { state.skeleton = !state.skeleton; tSk.classList.toggle('on', state.skeleton); applyMaterials(); };
  tSu.onclick = () => { state.superficial = !state.superficial; tSu.classList.toggle('on', state.superficial); applyMaterials(); };
  document.getElementById('bShowAll').onclick = () => { state.hidden.clear(); applyMaterials(); };
  document.getElementById('zIn').onclick = () => dolly(0.8);
  document.getElementById('zOut').onclick = () => dolly(1.25);
  document.getElementById('zReset').onclick = () => setView('front');

  const search = document.getElementById('search'), results = document.getElementById('results');
  const named = [...musclesById.keys()].map(id => byId.get(id));
  search.oninput = () => {
    const q = search.value.trim().toLowerCase();
    results.innerHTML = '';
    if (q.length < 2) return;
    named.filter(i => i.name.toLowerCase().includes(q)).slice(0, 40).forEach(i => {
      const b = document.createElement('button');
      b.innerHTML = `${i.name}<small>${i.side === 'R' ? 'Right' : i.side === 'L' ? 'Left' : ''} · ${i.region}</small>`;
      b.onclick = () => { select(i.id); frameMuscle(i.id); };
      results.append(b);
    });
  };
  document.getElementById('cClose').onclick = () => select(null);
  document.getElementById('cFocus').onclick = () => state.selected && frameMuscle(state.selected);
  document.getElementById('cHide').onclick = () => state.selected && hideMuscle(state.selected);
  document.querySelectorAll('#cStatus button').forEach(b => b.onclick = () => setFinding(state.selected, { status: b.dataset.status }));
  document.getElementById('cCondition').onchange = e => setFinding(state.selected, { condition: e.target.value, status: state.findings.get(state.selected)?.status || 'affected' });
  document.getElementById('cPain').oninput = e => {
    document.getElementById('cPainV').textContent = e.target.value;
    setFinding(state.selected, { pain: +e.target.value, status: state.findings.get(state.selected)?.status || 'affected' });
  };
}
function dolly(k) {
  autoView = null;
  const off = camera.position.clone().sub(controls.target).multiplyScalar(k);
  tween = { t0: performance.now(), dur: 250, fromPos: camera.position.clone(), fromTarget: controls.target.clone(), toPos: controls.target.clone().add(off), toTarget: controls.target.clone() };
}
function renderCard() {
  const card = document.getElementById('card'), id = state.selected;
  card.hidden = !id; if (!id) return;
  const i = byId.get(id), f = state.findings.get(id) || {};
  document.getElementById('cName').textContent = i.name;
  document.getElementById('cSub').textContent = [i.side === 'R' ? 'Right' : i.side === 'L' ? 'Left' : 'Midline', i.region, i.group].filter(Boolean).join(' · ');
  document.getElementById('cActions').innerHTML = (i.actions || []).map(a => `<span>${a}</span>`).join('');
  document.querySelectorAll('#cStatus button').forEach(b => b.classList.toggle('on', (f.status || '') === b.dataset.status));
  document.getElementById('cCondition').value = f.condition || '';
  document.getElementById('cPain').value = f.pain || 0;
  document.getElementById('cPainV').textContent = f.pain || 0;
}
function renderFindings() {
  const list = document.getElementById('fList');
  if (!state.findings.size) { list.innerHTML = '<p class="muted">Click a muscle and set a status to record a finding.</p>'; return; }
  list.innerHTML = '';
  for (const [id, f] of state.findings) {
    const b = document.createElement('button');
    const c = STATUS[f.status]?.color ?? 0x94a3b8;
    b.innerHTML = `<i class="d" style="background:#${c.toString(16).padStart(6, '0')}"></i><span>${label(id)}<small>${[f.condition, f.pain ? `pain ${f.pain}/10` : ''].filter(Boolean).join(' · ') || STATUS[f.status]?.label || ''}</small></span>`;
    b.onclick = () => { select(id); frameMuscle(id); };
    list.append(b);
  }
}

// ---------------------------------------------------------------- callouts
const labelsEl = document.getElementById('labels');
const calloutEls = new Map();
const v = new THREE.Vector3();
function updateCallouts() {
  const ids = new Set(state.findings.keys());
  for (const [id, el] of calloutEls) if (!ids.has(id)) { el.remove(); calloutEls.delete(id); }
  const w = canvas.clientWidth, h = canvas.clientHeight;
  for (const id of ids) {
    const m = musclesById.get(id); if (!m) continue;
    let el = calloutEls.get(id);
    const f = state.findings.get(id), i = byId.get(id);
    if (!el) {
      el = document.createElement('div'); el.className = 'callout';
      el.onclick = () => { select(id); frameMuscle(id); };
      labelsEl.append(el); calloutEls.set(id, el);
    }
    const c = STATUS[f.status]?.color ?? 0x94a3b8;
    const html = `<span class="s" style="background:#${c.toString(16).padStart(6, '0')}">${i.side === 'M' ? '•' : i.side}</span><span class="n">${label(id).replace(/^(Right|Left) /, '')}</span>${f.condition ? `<span>${f.condition}</span>` : ''}`;
    if (el._html !== html) { el.innerHTML = html; el._html = html; }
    v.copy(m.userData.center).project(camera);
    const behind = v.z > 1;
    el.style.display = behind || !m.visible ? 'none' : 'flex';
    el._x = (v.x * 0.5 + 0.5) * w; el._y = (-v.y * 0.5 + 0.5) * h;
  }
  // nudge labels apart so neighbouring muscles don't stack their callouts
  const shown = [...calloutEls.values()].filter(e => e.style.display !== 'none').sort((a, b) => a._y - b._y);
  const placed = [];
  for (const el of shown) {
    let y = el._y;
    const wEl = el.offsetWidth || 160;
    for (const p of placed) if (Math.abs(p.x - el._x) < (p.w + wEl) / 2 && y - p.y < 34) y = p.y + 34;
    placed.push({ x: el._x, y, w: wEl });
    el.style.left = `${el._x}px`; el.style.top = `${y}px`;
  }
}

// ---------------------------------------------------------------- loop
let needsRender = true;
controls.addEventListener('change', () => (needsRender = true));
// The user took the camera: stop re-framing on resize.
controls.addEventListener('start', () => (autoView = null));
function resize() {
  const w = stage.clientWidth, h = stage.clientHeight;
  renderer.setSize(w, h, false);
  camera.aspect = w / Math.max(h, 1);
  camera.updateProjectionMatrix();
  if (autoView && !bodyBox.isEmpty()) setView(autoView, false);
  needsRender = true;
}
new ResizeObserver(resize).observe(stage);

const perf = document.getElementById('perf');
let frames = 0, lastT = performance.now(), gpu = '';
try {
  const gl = renderer.getContext(), ext = gl.getExtension('WEBGL_debug_renderer_info');
  gpu = ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : '';
} catch { /* ignore */ }
function loop(t) {
  requestAnimationFrame(loop);
  if (tween) {
    const k = Math.min(1, (t - tween.t0) / tween.dur), e = 1 - Math.pow(1 - k, 3);
    camera.position.lerpVectors(tween.fromPos, tween.toPos, e);
    controls.target.lerpVectors(tween.fromTarget, tween.toTarget, e);
    if (k >= 1) tween = null;
    needsRender = true;
  }
  controls.update();
  if (!needsRender) return;
  needsRender = false;
  renderer.render(scene, camera);
  updateCallouts();
  frames++;
  if (t - lastT > 1000) {
    const info = renderer.info.render;
    perf.textContent = `${Math.round((frames * 1000) / (t - lastT))} fps (while moving) · ${(info.triangles / 1e6).toFixed(2)}M tris · ${info.calls} draws${gpu ? '\n' + gpu : ''}`;
    perf.style.whiteSpace = 'pre';
    frames = 0; lastT = t;
  }
}
requestAnimationFrame(loop);

// ---------------------------------------------------------------- public API for the host app
window.MuscleChart = {
  setMode,
  setView: name => (REGIONS[name] ? frameRegion(name) : setView(name)),
  select: id => { select(id); if (id) frameMuscle(id); },
  setFindings(list) {
    state.findings.clear();
    for (const f of list || []) if (musclesById.has(f.id)) state.findings.set(f.id, { status: f.status || 'affected', condition: f.condition || '', pain: f.pain || 0 });
    applyMaterials(); renderFindings(); renderCard();
  },
  getFindings: () => [...state.findings].map(([id, f]) => ({ id, ...f })),
  setSkeleton(on) { state.skeleton = !!on; applyMaterials(); },
  setSuperficial(on) { state.superficial = !!on; applyMaterials(); },
  catalog: () => catalog,
};
