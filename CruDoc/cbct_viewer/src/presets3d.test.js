import test from 'node:test';
import assert from 'node:assert/strict';
import { buildLook, presetsFor, validPreset, scanKind, presetLabel } from './presets3d.js';

const base = {
  values: { min: -1000, max: 3000 },
  landmarks: { air: -900, soft: 50, bone: 500, teeth: 1800, metal: null },
  presets: { bone: { low: -900, high: 1800 } },
};
const metas = {
  dental: base,
  ct: { ...base, kind: 'ct' },
  mr: { ...base, kind: 'mr' },
};

function isSorted(arr) {
  for (let i = 1; i < arr.length; i++) {
    if (arr[i][0] < arr[i - 1][0]) return false;
  }
  return true;
}

for (const [kindName, meta] of Object.entries(metas)) {
  const presets = presetsFor(meta);
  for (const [id] of presets) {
    test(`buildLook ${kindName}/${id}: blend valid`, () => {
      const look = buildLook(meta, { preset: id, threshold: 0, opacity: 100 });
      assert.ok(['composite', 'mip', 'mean'].includes(look.blend),
        `blend="${look.blend}" not in allowed set`);
    });

    test(`buildLook ${kindName}/${id}: color x values non-decreasing`, () => {
      const look = buildLook(meta, { preset: id, threshold: 0, opacity: 100 });
      assert.ok(isSorted(look.color), `color x not sorted: ${JSON.stringify(look.color)}`);
    });

    test(`buildLook ${kindName}/${id}: alpha x values non-decreasing`, () => {
      const look = buildLook(meta, { preset: id, threshold: 0, opacity: 100 });
      assert.ok(isSorted(look.alpha), `alpha x not sorted: ${JSON.stringify(look.alpha)}`);
    });

    test(`buildLook ${kindName}/${id}: alpha values in [0,1]`, () => {
      const look = buildLook(meta, { preset: id, threshold: 0, opacity: 100 });
      for (const [, a] of look.alpha) {
        assert.ok(a >= 0 && a <= 1, `alpha value ${a} out of [0,1]`);
      }
    });

    test(`buildLook ${kindName}/${id}: colour channel values in [0,1]`, () => {
      const look = buildLook(meta, { preset: id, threshold: 0, opacity: 100 });
      for (const [, [r, g, b]] of look.color) {
        // Infinity sentinels are allowed for the x coordinate but not colour channels
        if (!Number.isFinite(r) || !Number.isFinite(g) || !Number.isFinite(b)) {
          // colour channels must be finite numbers
          assert.ok(false, `non-finite colour channel [${r},${g},${b}] in preset ${id}`);
        }
        assert.ok(r >= 0 && r <= 1, `r=${r} out of [0,1]`);
        assert.ok(g >= 0 && g <= 1, `g=${g} out of [0,1]`);
        assert.ok(b >= 0 && b <= 1, `b=${b} out of [0,1]`);
      }
    });

    test(`buildLook ${kindName}/${id}: rampStart is finite`, () => {
      const look = buildLook(meta, { preset: id, threshold: 0, opacity: 100 });
      assert.ok(Number.isFinite(look.rampStart),
        `rampStart=${look.rampStart} is not finite`);
    });
  }
}

test('validPreset: mr does not have bone, falls back to tissue', () => {
  assert.equal(validPreset(metas.mr, 'bone'), 'tissue');
});

test('validPreset: dental has roots, returns roots', () => {
  assert.equal(validPreset(metas.dental, 'roots'), 'roots');
});

test('scanKind: empty object -> dental', () => {
  assert.equal(scanKind({}), 'dental');
});

test('presetLabel: dental roots -> "Teeth in bone"', () => {
  assert.equal(presetLabel(metas.dental, 'roots'), 'Teeth in bone');
});

