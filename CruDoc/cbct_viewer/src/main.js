import './styles/tokens.css';
import './styles/viewer.css';
import { version } from '../package.json';
import { mountChrome, installKeys } from './chrome.js';
import { bus, state } from './state.js';
import { core } from './core.js';
import { initEngine, annotation } from './engine.js';
import { init3d, tuning } from './view3d.js';
import { initOverlays } from './overlays.js';
import { installSession, fail } from './session.js';

console.log('CBCT viewer booted');

// ───────────────────────── Flutter bridge (handler 'cbct') ─────────────────────────

const outbox = [];
let bridgeReady = !!(window.flutter_inappwebview && typeof window.flutter_inappwebview.callHandler === 'function');

function send(msg) {
  try {
    window.flutter_inappwebview.callHandler('cbct', msg);
  } catch (err) {
    console.warn('CBCT viewer: could not post', msg.type, err);
  }
}
function flushOutbox() {
  bridgeReady = true;
  while (outbox.length) send(outbox.shift());
}
function post(msg) {
  console.log('[cbct->flutter]', JSON.stringify(msg));
  if (bridgeReady) send(msg);
  else outbox.push(msg);
}
window.addEventListener('flutterInAppWebViewPlatformReady', flushOutbox, { once: true });

// ───────────────────────── Boot: chrome first, engine behind it ─────────────────────────

const ui = mountChrome(document.getElementById('app'));
bus.on('post', post);
installKeys();
post({ type: 'boot', version });

const engineStarted = initEngine(ui.hosts).then(() => {
  init3d(ui);
  initOverlays(ui);
});
engineStarted.catch(fail);
installSession(ui, post, engineStarted);

// Flutter opens the page with the scan in the query string (or calls CbctViewer.open itself).
const params = new URLSearchParams(location.search);
if (params.has('debug')) window.__cbct = { core, state, annotation, tuning };
window.CbctViewer.open({
  base: params.get('base') || '/dev/phantom/',
  title: params.get('title') || 'CBCT',
  chip: params.get('chip') || '',
  badge: params.get('badge') || '',
  deviceClass: params.get('device') || 'pc',
  firstOpen: params.get('first') === '1',
  reducedMotion: params.get('reduced') === '1' || matchMedia('(prefers-reduced-motion: reduce)').matches,
});
