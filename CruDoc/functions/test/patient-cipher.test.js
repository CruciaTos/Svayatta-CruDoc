/**
 * Server-side patient field encryption (src/crypto/patientCipher.ts) against
 * values made by the Flutter app's code, and the phone normaliser that sat
 * behind the reminder bug.
 *
 * Run with:  npm run build && node test/patient-cipher.test.js
 *
 * The Dart values below were printed by
 * test/core/services/field_cipher_compat_test.dart, which in turn decrypts
 * values this module made. Change the scheme on one side and a test fails on
 * the other.
 */
const assert = require('assert');
const crypto = require('crypto');
const {
  deriveKek, unwrapKey, wrapKey, encryptField, decryptField, phoneIndexOf,
  isEncrypted,
} = require('../lib/crypto/patientCipher');
const {normalisePhone} = require('../lib/whatsapp/format');

const CLINIC = 'clinic_compat_test';
const PEPPER = 'test-pepper-not-the-real-one';
const DEK = Buffer.from(Array.from({length: 32}, (_, i) => (i * 7 + 3) & 0xff));

// Made by the Dart `encrypt` package via FieldCipher, with DEK above.
const DART = {
  wrapped: '752e927x8r1onruC.E6YDfDUTm5X7yRW9EPhdBHuObaJjJOqmYX55k9GWWB2cT4qDSKgF4aZlxVr2F1UY',
  name: 'enc:v1:3Vbbq+TMa0Ua6wXo.0YHLon9zIF+IxjFA9wZArSrRjh0/zKOOJoh63lrOLw==',
  phone: 'enc:v1:uGeNWbBfTbcD8Iye.AVoklz3uUXsrTuqYuHKaXiCi6Lkx3z6iMdU=',
};

let passed = 0;
function test(name, fn) {
  try {
    fn();
    passed++;
  } catch (err) {
    console.error(`FAIL  ${name}`);
    console.error(err);
    process.exitCode = 1;
  }
}

// ------------------------------------------------------------ Dart interop

test('a key wrapped by the app unwraps on the server', () => {
  const kek = deriveKek(CLINIC, PEPPER);
  assert.deepStrictEqual(unwrapKey(DART.wrapped, kek), DEK);
});

test('fields encrypted by the app decrypt on the server', () => {
  assert.strictEqual(decryptField(DART.name, DEK), 'Sunita Deshmukh');
  assert.strictEqual(decryptField(DART.phone, DEK), '9822011111');
});

test('the wrong pepper does not unwrap the key', () => {
  assert.throws(() => unwrapKey(DART.wrapped, deriveKek(CLINIC, 'wrong')));
});

// ------------------------------------------------------------ round trips

test('server round trip, including Devanagari', () => {
  for (const plain of ['Ramesh Patil', 'रमेश पाटील', '+91 98765 43210']) {
    const sealed = encryptField(plain, DEK);
    assert.ok(isEncrypted(sealed));
    assert.strictEqual(decryptField(sealed, DEK), plain);
  }
  const kek = deriveKek('other', PEPPER);
  assert.deepStrictEqual(unwrapKey(wrapKey(DEK, kek), kek), DEK);
});

test('plaintext passes through; undecryptable ciphertext is null, never returned', () => {
  assert.strictEqual(decryptField('Ramesh', DEK), 'Ramesh');
  assert.strictEqual(decryptField(DART.name, null), null);
  assert.strictEqual(decryptField(DART.name, crypto.randomBytes(32)), null);
  assert.strictEqual(decryptField(undefined, DEK), null);
  assert.strictEqual(encryptField('', DEK), '');
  assert.strictEqual(encryptField(DART.name, DEK), DART.name, 'not double-encrypted');
});

// ------------------------------------------------------------ phone index

test('the phone index ignores formatting and differs per clinic', () => {
  const a = phoneIndexOf('+91 98765 43210', DEK);
  assert.match(a, /^[0-9a-f]{64}$/);
  assert.strictEqual(phoneIndexOf('09876543210', DEK), a);
  assert.strictEqual(phoneIndexOf('9876543210', DEK), a);
  assert.notStrictEqual(phoneIndexOf('9876543210', crypto.randomBytes(32)), a);
  assert.strictEqual(phoneIndexOf('022 2345 6789', DEK), null, 'landline');
  assert.strictEqual(phoneIndexOf(DART.phone, DEK), null, 'ciphertext');
});

// ------------------------------------------------- the reminder bug (P0)

test('ciphertext never normalises to a phone number', () => {
  // 100k encrypted phones used to give ~26% "valid" foreign numbers.
  let accepted = 0;
  for (let i = 0; i < 20000; i++) {
    const phone = `9${String(i).padStart(9, '0')}`;
    if (normalisePhone(encryptField(phone, DEK)) !== null) accepted++;
  }
  assert.strictEqual(accepted, 0);
});

test('only Indian mobiles are accepted', () => {
  assert.strictEqual(normalisePhone('+91 98765 43210'), '919876543210');
  assert.strictEqual(normalisePhone('(+91) 98765-43210'), '919876543210');
  assert.strictEqual(normalisePhone('+1 415 555 0100'), null);
  assert.strictEqual(normalisePhone('14155550100123'), null);
  assert.strictEqual(normalisePhone('+44 7700 900123'), null);
  assert.strictEqual(normalisePhone('9876543210x'), null);
});

console.log(`${passed} passed`);
