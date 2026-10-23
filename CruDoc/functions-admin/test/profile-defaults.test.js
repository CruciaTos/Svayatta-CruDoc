/**
 * Tests for the profile defaults (src/profile-defaults.ts).
 *
 * Run with:  npm run build && node test/profile-defaults.test.js
 */
const assert = require('assert');
const {Timestamp, FieldValue} = require('firebase-admin/firestore');
const {profileDefaults} = require('../lib/profile-defaults');

const created = Timestamp.fromDate(new Date('2026-10-08T16:33:00Z'));
const docTime = Timestamp.fromDate(new Date('2026-10-08T16:30:00Z'));

// An older build's profile: no role, no isDeleted, no accountCreated.
assert.deepStrictEqual(
  profileDefaults({uid: 'u1', email: 'x', createdAt: created}, docTime),
  {role: 'doctor', isDeleted: false, accountCreated: created},
);

// No createdAt either: the document's own creation time.
assert.deepStrictEqual(profileDefaults({specialty: 'Dentist'}, docTime), {
  role: 'doctor',
  isDeleted: false,
  accountCreated: docTime,
});

// Nothing to go on: the server's time.
const patch = profileDefaults({});
assert.strictEqual(patch.role, 'doctor');
assert.ok(patch.accountCreated instanceof FieldValue);

// A complete doctor profile: nothing to write (so the trigger stops).
assert.deepStrictEqual(
  profileDefaults(
    {role: 'doctor', isDeleted: false, accountCreated: created},
    docTime,
  ),
  {},
);

// Deleted doctors keep isDeleted: true.
assert.deepStrictEqual(
  profileDefaults({role: 'doctor', isDeleted: true, accountCreated: created}),
  {},
);

// Never touched: Super Admins, other roles, clinic staff.
assert.deepStrictEqual(profileDefaults({role: 'superAdmin'}), {});
assert.deepStrictEqual(profileDefaults({role: 'receptionist'}), {});
assert.deepStrictEqual(profileDefaults({memberKind: 'staff'}), {});

// A clinic owner without a role is a doctor's account.
assert.strictEqual(profileDefaults({memberKind: 'owner'}).role, 'doctor');

console.log('profile-defaults tests passed');
