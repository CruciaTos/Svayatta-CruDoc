import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { DRACOLoader } from 'three/examples/jsm/loaders/DRACOLoader.js';
import { buildPlaceholder } from './placeholder.js';

const MODEL_URL = 'models/subject.glb';

// Reads a URL to an ArrayBuffer with download progress; null when it is not there
// (404, or a dev server answering with index.html).
async function fetchGlb(onProgress) {
  let res;
  try { res = await fetch(MODEL_URL); } catch { return null; }
  if (!res.ok || (res.headers.get('content-type') || '').includes('text/html')) return null;
  const total = +res.headers.get('content-length') || 0;
  if (!res.body || !total) return res.arrayBuffer();
  const reader = res.body.getReader();
  const parts = [];
  let got = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    parts.push(value); got += value.length;
    onProgress?.(got / total);
  }
  const out = new Uint8Array(got);
  let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; }
  return out.buffer;
}

// Loads the Draco-compressed GLB (relative URLs only; works offline from the
// loopback server). Uses capsule stand-ins with ?placeholder=1 or when the GLB
// is missing. A GLB that exists but fails to parse is a real error and throws.
export async function loadModel(manifest, onProgress) {
  const forced = new URLSearchParams(location.search).get('placeholder') === '1';
  const buf = forced ? null : await fetchGlb(onProgress);
  if (!buf) return { root: buildPlaceholder(manifest), placeholder: true };
  const draco = new DRACOLoader().setDecoderPath('./draco/');
  const loader = new GLTFLoader().setDRACOLoader(draco);
  try {
    const gltf = await loader.parseAsync(buf, './models/');
    const root = gltf.scene.getObjectByName('subject') || gltf.scene;
    return { root, placeholder: false };
  } finally {
    draco.dispose();
  }
}
