/**
 * Tests for CruDoc IDs (src/crudoc-id.ts): the pure helpers.
 *
 * Run with:  npm run build && node test/crudoc-id.test.js
 */
const assert = require('assert');
const {newCrudocId, normalizeCrudocId, formatCrudocId, CRUDOC_ID_LENGTH} =
  require('../lib/crudoc-id');

// New IDs: 8 characters from the Crockford alphabet, different each time.
const seen = new Set();
for (let i = 0; i < 2000; i++) {
  const id = newCrudocId();
  assert.strictEqual(id.length, CRUDOC_ID_LENGTH);
  assert.match(id, /^[0-9A-HJKMNP-TV-Z]{8}$/);
  seen.add(id);
}
assert.ok(seen.size > 1990, 'IDs repeat far too often');

// Forgiving input.
assert.strictEqual(normalizeCrudocId('k7q9-2xmb'), 'K7Q92XMB');
assert.strictEqual(normalizeCrudocId(' K7Q9 2XMB '), 'K7Q92XMB');
assert.strictEqual(normalizeCrudocId('CD-K7Q9-2XMB'), 'K7Q92XMB');
assert.strictEqual(normalizeCrudocId('KOQ9-2XMB'), 'K0Q92XMB'); // O reads as 0
assert.strictEqual(normalizeCrudocId('KIQ9-2XML'), 'K1Q92XM1'); // I and L read as 1

// Not IDs.
assert.strictEqual(normalizeCrudocId('K7Q9-2XM'), null);
assert.strictEqual(normalizeCrudocId('K7Q9-2XMBB'), null);
assert.strictEqual(normalizeCrudocId('K7Q9-2XMU'), null); // U is never used
assert.strictEqual(normalizeCrudocId('K7Q9_2XMB'), null);
assert.strictEqual(normalizeCrudocId(''), null);
assert.strictEqual(normalizeCrudocId(undefined), null);

assert.strictEqual(formatCrudocId('K7Q92XMB'), 'K7Q9-2XMB');
console.log('crudoc-id: all tests passed');
