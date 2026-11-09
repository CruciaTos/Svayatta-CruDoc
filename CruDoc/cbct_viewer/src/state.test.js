import test from 'node:test';
import assert from 'node:assert/strict';
import { state, set, subscribe, presetWindow, matchPreset } from './state.js';

test('1. set() performs a one-level merge for object values', () => {
  const origContrast = { ...state.contrast };
  set({ contrast: { low: 5 } });
  assert.equal(state.contrast.low, 5);
  assert.equal(state.contrast.high, origContrast.high);
  assert.equal(state.contrast.preset, origContrast.preset);
  assert.equal(state.contrast.invert, origContrast.invert);
  set({ contrast: origContrast });
});

test('2. set() replaces a plain string value', () => {
  const origLayout = state.layout;
  set({ layout: 'single' });
  assert.equal(state.layout, 'single');
  set({ layout: origLayout });
});

test('3. subscribe() notifies once per set() with state and changed keys, and unregisters', () => {
  const origLayout = state.layout;
  let count = 0;
  let lastState = null;
  let lastChanged = null;

  const unsubscribe = subscribe((s, changed) => {
    count++;
    lastState = s;
    lastChanged = changed;
  });

  set({ layout: 'single' });
  assert.equal(count, 1);
  assert.equal(lastState, state);
  assert.ok(lastChanged.has('layout'));

  unsubscribe();
  set({ layout: origLayout });
  assert.equal(count, 1);
});

test('4. presetWindow() returns window range or null', () => {
  const meta = {
    values: { min: -1000, max: 6000 },
    presets: {
      bone: { low: -600, high: 3000 },
      teeth: { low: 1100, high: 5900 },
    },
  };

  assert.deepEqual(presetWindow(meta, 'bone'), { low: -600, high: 3000 });
  assert.equal(presetWindow(meta, 'nope'), null);
  assert.equal(presetWindow(null, 'bone'), null);
});

test('5. matchPreset() matches within 0.5% tolerance', () => {
  const meta = {
    values: { min: -1000, max: 6000 },
    presets: {
      bone: { low: -600, high: 3000 },
      teeth: { low: 1100, high: 5900 },
    },
  };

  assert.equal(matchPreset(meta, -600, 3000), 'bone');
  assert.equal(matchPreset(meta, -590, 3010), 'bone');
  assert.equal(matchPreset(meta, 0, 2000), null);
  assert.equal(matchPreset(null, 0, 1), null);
});

