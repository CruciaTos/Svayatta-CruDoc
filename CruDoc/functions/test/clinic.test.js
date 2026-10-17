/**
 * Tests for the clinic team authorization helpers (src/clinic.ts).
 *
 * Run with:  npm run build && node test/clinic.test.js
 *
 * These cover the code that decides who may grant what. `checkEscalation`
 * is the guard that stops a manager holding `team` from minting a role with
 * clinical or revenue access and inviting a second phone of their own into
 * it; `loadCaller` is what every privileged action trusts to say who the
 * caller is. Both ran untested until now, which is why the assertions here
 * are deliberately exhaustive about the *deny* paths.
 *
 * Several tests pin current behaviour rather than ideal behaviour (the
 * Admin role holding clinical.edit, for one). They are marked CHARACTERISES
 * so that when the admin/clinical separation lands, the diff is visible and
 * deliberate instead of silent.
 */
const assert = require('assert');

const {
  PERMS,
  CLINICAL_PERMS,
  ADMIN_PERMS,
  ROLE_TEMPLATES,
  MODULES,
  DEFAULT_SEATS,
  INVITE_DAYS,
  MAX_ROLES,
  DENTAL_FEATURES,
  normalizePerms,
  normalizePhone,
  normalizeModules,
  normalizeDental,
  loadCaller,
  requirePerm,
  checkEscalation,
  assertStaffCannotWriteClinical,
} = require('../lib/clinic');

let passed = 0;

function test(name, fn) {
  try {
    const r = fn();
    if (r && typeof r.then === 'function') {
      throw new Error('use testAsync for a promise-returning test');
    }
    passed += 1;
    console.log(`  ok  ${name}`);
  } catch (err) {
    console.error(`FAIL  ${name}`);
    console.error(`      ${err.message}`);
    process.exitCode = 1;
  }
}

const asyncTests = [];
function testAsync(name, fn) {
  asyncTests.push(async () => {
    try {
      await fn();
      passed += 1;
      console.log(`  ok  ${name}`);
    } catch (err) {
      console.error(`FAIL  ${name}`);
      console.error(`      ${err.message}`);
      process.exitCode = 1;
    }
  });
}

/** Asserts fn() throws an HttpsError carrying `code`. */
function throwsCode(code, fn, note = '') {
  try {
    fn();
  } catch (err) {
    assert.strictEqual(err.code, code,
      `expected code "${code}", got "${err.code}" (${err.message}) ${note}`);
    return err;
  }
  assert.fail(`expected a throw with code "${code}" but nothing was thrown ${note}`);
}

async function rejectsCode(code, promise, note = '') {
  try {
    await promise;
  } catch (err) {
    assert.strictEqual(err.code, code,
      `expected code "${code}", got "${err.code}" (${err.message}) ${note}`);
    return err;
  }
  assert.fail(`expected a rejection with code "${code}" but it resolved ${note}`);
}

/** A Caller fixture. */
function caller({uid = 'u1', clinicId = 'c1', isOwner = false, isAdmin = false, perms = []} = {}) {
  return {uid, clinicId, isOwner, isAdmin, perms};
}

// ==================================================================
console.log('\nnormalizePerms');
// ==================================================================

test('drops unknown keys', () => {
  assert.deepStrictEqual(normalizePerms(['billing', 'nonsense', 'drop-table']), ['billing']);
});

test('returns [] for a non-array', () => {
  for (const bad of [null, undefined, 'billing', 42, {billing: true}]) {
    assert.deepStrictEqual(normalizePerms(bad), [], `input: ${JSON.stringify(bad)}`);
  }
});

test('de-duplicates and sorts', () => {
  assert.deepStrictEqual(normalizePerms(['billing', 'billing', 'ai']), ['ai', 'billing']);
});

test('clinical.edit implies clinical.view and patients.view', () => {
  assert.deepStrictEqual(normalizePerms(['clinical.edit']),
    ['clinical.edit', 'clinical.view', 'patients.view']);
});

test('clinical.view implies patients.view', () => {
  assert.deepStrictEqual(normalizePerms(['clinical.view']), ['clinical.view', 'patients.view']);
});

test('patients.edit implies patients.view', () => {
  assert.deepStrictEqual(normalizePerms(['patients.edit']), ['patients.edit', 'patients.view']);
});

test('schedule implies nothing', () => {
  assert.deepStrictEqual(normalizePerms(['schedule']), ['schedule']);
});

test('ignores non-string members', () => {
  assert.deepStrictEqual(normalizePerms(['billing', 7, null, {}, ['ai']]), ['billing']);
});

test('every key in PERMS survives a round trip', () => {
  // Guards against a typo in PERMS that would silently drop a permission.
  for (const p of PERMS) {
    assert.ok(normalizePerms([p]).includes(p), `${p} was dropped by normalizePerms`);
  }
});

// ==================================================================
console.log('\nnormalizePhone');
// ==================================================================

test('prefixes a bare 10-digit Indian number', () => {
  assert.strictEqual(normalizePhone('9876543210'), '+919876543210');
});

test('strips spaces and dashes before deciding', () => {
  assert.strictEqual(normalizePhone('98765 43210'), '+919876543210');
  assert.strictEqual(normalizePhone('98765-43210'), '+919876543210');
  assert.strictEqual(normalizePhone(' 98765 - 43210 '), '+919876543210');
});

test('passes through an E.164 number', () => {
  assert.strictEqual(normalizePhone('+919876543210'), '+919876543210');
  assert.strictEqual(normalizePhone('+14155552671'), '+14155552671');
});

test('rejects wrong lengths, letters and junk', () => {
  for (const bad of ['12345', '987654321', '98765432101', 'abcdefghij',
    '+9', '+1234567890123456', '', '++919876543210', '+91 98765 4321a']) {
    throwsCode('invalid-argument', () => normalizePhone(bad), `input: "${bad}"`);
  }
});

test('rejects a non-string', () => {
  for (const bad of [null, undefined, 9876543210, {}]) {
    throwsCode('invalid-argument', () => normalizePhone(bad), `input: ${JSON.stringify(bad)}`);
  }
});

// ==================================================================
console.log('\nnormalizeModules / normalizeDental');
// ==================================================================

test('modules: null and undefined mean "no personal limit"', () => {
  assert.strictEqual(normalizeModules(null), null);
  assert.strictEqual(normalizeModules(undefined), null);
});

test('modules: a non-array is treated as no limit', () => {
  assert.strictEqual(normalizeModules('patients'), null);
  assert.strictEqual(normalizeModules(42), null);
});

test('modules: unknown keys dropped, deduped, sorted', () => {
  assert.deepStrictEqual(
    normalizeModules(['revenue', 'bogus', 'patients', 'patients']),
    ['patients', 'revenue'],
  );
});

test('modules: every key in MODULES survives', () => {
  for (const m of MODULES) {
    assert.deepStrictEqual(normalizeModules([m]), [m], `${m} was dropped`);
  }
});

test('CHARACTERISES modules: [] stays [] (an empty allow-list, not "no limit")', () => {
  // Meaningful: `invite` stores modules only when normalizeModules() is
  // non-null, so [] is persisted and means "no modules at all", whereas
  // null means "no personal limit". normalizeDental differs (below).
  assert.deepStrictEqual(normalizeModules([]), []);
});

test('CHARACTERISES dental: [] collapses to null, unlike modules', () => {
  assert.strictEqual(normalizeDental([]), null);
  assert.strictEqual(normalizeDental(['bogus']), null);
});

test('dental: known keys kept, deduped, sorted', () => {
  assert.deepStrictEqual(normalizeDental(['endo', 'chairside', 'endo']), ['chairside', 'endo']);
});

test('dental: every key in DENTAL_FEATURES survives', () => {
  for (const f of DENTAL_FEATURES) {
    assert.deepStrictEqual(normalizeDental([f]), [f], `${f} was dropped`);
  }
});

// ==================================================================
console.log('\nrequirePerm');
// ==================================================================

test('refuses an admin who does not hold the permission (no admin shortcut)', () => {
  // loadCaller already puts everything an admin is entitled to into perms,
  // so a shortcut here would hand back the clinical access just withheld.
  throwsCode('permission-denied',
    () => requirePerm(caller({isAdmin: true, perms: []}), 'clinical.edit'));
});

test('lets an admin through for a permission that is in their perms', () => {
  requirePerm(caller({isAdmin: true, perms: ['revenue', 'team']}), 'revenue');
});

test('lets a member through for a permission they hold', () => {
  requirePerm(caller({perms: ['team', 'billing']}), 'team');
});

test('refuses a member for a permission they lack', () => {
  const err = throwsCode('permission-denied',
    () => requirePerm(caller({perms: ['billing']}), 'team'));
  assert.match(err.message, /team/, 'the message should name the missing permission');
});

test('refuses a member holding no permissions at all', () => {
  throwsCode('permission-denied', () => requirePerm(caller({perms: []}), 'patients.view'));
});

// ==================================================================
console.log('\ncheckEscalation  (the privilege-escalation guard)');
// ==================================================================

test('the owner may grant anything, including the admin role', () => {
  checkEscalation(caller({isOwner: true}), 'admin', PERMS);
});

test('an admin may grant anything, including team', () => {
  checkEscalation(caller({isAdmin: true}), 'admin', ['team']);
});

test('a non-admin may NOT hand out the admin role', () => {
  throwsCode('permission-denied',
    () => checkEscalation(caller({perms: ['team']}), 'admin', ['billing']));
});

test('a non-admin may NOT hand out the team permission', () => {
  throwsCode('permission-denied',
    () => checkEscalation(caller({perms: ['team']}), undefined, ['team']));
});

test('a non-admin may NOT grant a permission they do not hold', () => {
  // The attack this exists for: a manager with `team` but no clinical or
  // revenue access building a role that has them.
  throwsCode('permission-denied',
    () => checkEscalation(caller({perms: ['team', 'schedule']}), undefined,
      ['schedule', 'clinical.edit']));
  throwsCode('permission-denied',
    () => checkEscalation(caller({perms: ['team']}), undefined, ['revenue']));
});

test('a non-admin MAY grant a subset of what they hold', () => {
  checkEscalation(caller({perms: ['team', 'schedule', 'billing']}), undefined,
    ['schedule', 'billing']);
  checkEscalation(caller({perms: ['team', 'schedule']}), undefined, []);
});

test('an exact match of the caller\'s own permissions is allowed', () => {
  checkEscalation(caller({perms: ['schedule', 'billing']}), undefined, ['schedule', 'billing']);
});

test('a roleId other than "admin" is not itself an escalation', () => {
  checkEscalation(caller({perms: ['schedule']}), 'receptionist', ['schedule']);
});

test('CHARACTERISES a non-array `perms` skips the subset check entirely', () => {
  // Latent hazard, not currently reachable: callers pass either
  // normalizePerms() output or a role document's `perms`. If a role doc ever
  // held a non-array `perms`, escalation would be silently skipped because
  // `list` falls back to []. Worth a guard when this area is next touched.
  checkEscalation(caller({perms: []}), undefined, 'clinical.edit');
  checkEscalation(caller({perms: []}), undefined, {team: true});
  checkEscalation(caller({perms: []}), undefined, undefined);
  checkEscalation(caller({perms: []}), undefined, null);
});

test('coerces array members to strings before comparing', () => {
  // ['team'] smuggled as a String object or similar must still be caught.
  throwsCode('permission-denied',
    () => checkEscalation(caller({perms: []}), undefined, [new String('team')]));
});

// ==================================================================
console.log('\nassertStaffCannotWriteClinical  (the staff/clinical invariant)');
// ==================================================================

test('refuses a staff role holding clinical.edit', () => {
  const err = throwsCode('invalid-argument',
    () => assertStaffCannotWriteClinical('staff', ['patients.view', 'clinical.edit']));
  assert.match(err.message, /clinical\.edit/,
    'the message should name the offending permission');
});

test('allows a staff role to READ clinical records', () => {
  // The Assistant / Nurse case: chairside work needs the chart.
  assertStaffCannotWriteClinical('staff', ['patients.view', 'clinical.view', 'inventory']);
});

test('allows a doctor role to write clinical records', () => {
  assertStaffCannotWriteClinical('doctor', ['clinical.edit', 'clinical.view']);
});

test('allows a staff role with no clinical permissions', () => {
  assertStaffCannotWriteClinical('staff', ['patients.view', 'schedule', 'billing']);
  assertStaffCannotWriteClinical('staff', []);
});

test('exempts the built-in admin role', () => {
  // Exempt only while the admin role still carries every permission.
  assertStaffCannotWriteClinical('staff', [...PERMS], 'admin');
});

test('does not exempt a role merely named like the admin one', () => {
  throwsCode('invalid-argument',
    () => assertStaffCannotWriteClinical('staff', ['clinical.edit'], 'Admin'));
  throwsCode('invalid-argument',
    () => assertStaffCannotWriteClinical('staff', ['clinical.edit'], 'admin2'));
  throwsCode('invalid-argument',
    () => assertStaffCannotWriteClinical('staff', ['clinical.edit'], ''));
});

test('every built-in template satisfies the invariant', () => {
  for (const r of ROLE_TEMPLATES) {
    assertStaffCannotWriteClinical(r.kind, r.perms, r.id);
  }
});

test('the invariant would reject the admin template without its exemption', () => {
  // Makes the size of the remaining gap explicit: the only thing keeping
  // the Admin role legal is the roleId exemption.
  const adminTemplate = ROLE_TEMPLATES.find((r) => r.id === 'admin');
  throwsCode('invalid-argument',
    () => assertStaffCannotWriteClinical(adminTemplate.kind, adminTemplate.perms));
});

// ==================================================================
console.log('\nloadCaller');
// ==================================================================

/**
 * The smallest Firestore stand-in that understands the one nested path
 * loadCaller reads: clinics/{clinicId}/members/{uid}.
 *
 * Deliberately local to this file: the shared test/fake-firestore.js models
 * only flat `collection/doc` paths, and teaching it subcollections risks the
 * voice tests that depend on its current behaviour.
 */
function fakeDbWithMembers(members) {
  const docRef = (path) => ({
    get: async () => ({
      exists: Object.prototype.hasOwnProperty.call(members, path),
      data: () => members[path],
    }),
    collection: (sub) => ({doc: (id) => docRef(`${path}/${sub}/${id}`)}),
  });
  return {collection: (name) => ({doc: (id) => docRef(`${name}/${id}`)})};
}

/** Installs the fake for the duration of fn, then restores. */
async function withMembers(members, fn) {
  const admin = require('firebase-admin');
  // `firestore` may be defined as a getter on the namespace, so capture the
  // resolved function rather than assuming a value descriptor.
  const previous = admin.firestore;
  const db = fakeDbWithMembers(members);
  const fake = () => db;
  for (const k of ['Timestamp', 'FieldValue', 'FieldPath', 'GeoPoint']) {
    if (previous && previous[k] !== undefined) fake[k] = previous[k];
  }
  Object.defineProperty(admin, 'firestore', {value: fake, configurable: true, writable: true});
  try {
    return await fn();
  } finally {
    Object.defineProperty(admin, 'firestore',
      {value: previous, configurable: true, writable: true});
  }
}

testAsync('refuses an unauthenticated call', async () => {
  await rejectsCode('unauthenticated', loadCaller({}, 'c1'));
  await rejectsCode('unauthenticated', loadCaller({auth: {}}, 'c1'));
});

testAsync('refuses a missing clinicId', async () => {
  await rejectsCode('invalid-argument', loadCaller({auth: {uid: 'u1'}}, ''));
});

testAsync('treats uid === clinicId as the owner with every permission', async () => {
  // A solo doctor: no clinic document at all. The owner path must not depend
  // on a member document, or on a clinic document, existing.
  await withMembers({}, async () => {
    const c = await loadCaller({auth: {uid: 'c1'}}, 'c1');
    assert.strictEqual(c.isOwner, true);
    assert.strictEqual(c.isAdmin, true);
    assert.deepStrictEqual([...c.perms].sort(), [...PERMS].sort());
  });
});

testAsync('a clinic predating ownerIsDoctor keeps its owner fully privileged', async () => {
  await withMembers({'clinics/c1': {name: 'C1'}}, async () => {
    const c = await loadCaller({auth: {uid: 'c1'}}, 'c1');
    assert.deepStrictEqual([...c.perms].sort(), [...PERMS].sort());
  });
});

testAsync('a manager-owner runs the clinic but holds no clinical permission', async () => {
  await withMembers({'clinics/c1': {name: 'C1', ownerIsDoctor: false}}, async () => {
    const c = await loadCaller({auth: {uid: 'c1'}}, 'c1');
    assert.strictEqual(c.isOwner, true);
    assert.deepStrictEqual([...c.perms].sort(), [...ADMIN_PERMS].sort());
    for (const p of CLINICAL_PERMS) {
      throwsCode('permission-denied', () => requirePerm(c, p));
    }
    requirePerm(c, 'team');
    requirePerm(c, 'settings');
  });
});

testAsync('a manager-owner stays restricted even if admins are granted clinical access', async () => {
  // adminClinicalAccess governs delegated admins; it is the owner's to give,
  // so it must not quietly restore the owner's own clinical access.
  await withMembers({'clinics/c1': {name: 'C1', ownerIsDoctor: false, adminClinicalAccess: true}},
    async () => {
      const c = await loadCaller({auth: {uid: 'c1'}}, 'c1');
      assert.ok(!c.perms.includes('clinical.view'));
    });
});

testAsync('refuses someone with no member document', async () => {
  await withMembers({}, () =>
    rejectsCode('permission-denied', loadCaller({auth: {uid: 'u1'}}, 'c1')));
});

testAsync('refuses an inactive member', async () => {
  await withMembers({
    'clinics/c1/members/u1': {active: false, roleId: 'doctor', perms: ['patients.view']},
  }, () => rejectsCode('permission-denied', loadCaller({auth: {uid: 'u1'}}, 'c1')));
});

testAsync('refuses a member whose active flag is missing or merely truthy', async () => {
  // The check is `active !== true`, so these must all be refused.
  for (const active of [undefined, 'true', 1, {}]) {
    await withMembers({
      'clinics/c1/members/u1': {active, roleId: 'doctor', perms: []},
    }, () => rejectsCode('permission-denied', loadCaller({auth: {uid: 'u1'}}, 'c1'),
      `active: ${JSON.stringify(active)}`));
  }
});

testAsync('an admin gets every administrative permission but NO clinical one', async () => {
  await withMembers({
    'clinics/c1': {name: 'C1', adminClinicalAccess: false},
    'clinics/c1/members/u1': {active: true, roleId: 'admin', perms: []},
  }, async () => {
    const c = await loadCaller({auth: {uid: 'u1'}}, 'c1');
    assert.strictEqual(c.isAdmin, true);
    assert.strictEqual(c.isOwner, false);
    assert.deepStrictEqual([...c.perms].sort(), [...ADMIN_PERMS].sort());
    for (const p of CLINICAL_PERMS) {
      assert.ok(!c.perms.includes(p), `an admin must not hold ${p}`);
      throwsCode('permission-denied', () => requirePerm(c, p));
    }
    // Still fully in charge of running the clinic.
    for (const p of ['team', 'settings', 'billing', 'revenue', 'inventory']) {
      requirePerm(c, p);
    }
  });
});

testAsync('an admin regains clinical access once the owner grants it', async () => {
  await withMembers({
    'clinics/c1': {name: 'C1', adminClinicalAccess: true},
    'clinics/c1/members/u1': {active: true, roleId: 'admin', perms: []},
  }, async () => {
    const c = await loadCaller({auth: {uid: 'u1'}}, 'c1');
    assert.deepStrictEqual([...c.perms].sort(), [...PERMS].sort());
    requirePerm(c, 'clinical.edit');
  });
});

testAsync('an absent adminClinicalAccess is read permissively (un-backfilled clinic)', async () => {
  // A clinic created before the setting existed must not be locked out of
  // its own records because the backfill has not run yet.
  await withMembers({
    'clinics/c1': {name: 'C1'},
    'clinics/c1/members/u1': {active: true, roleId: 'admin', perms: []},
  }, async () => {
    const c = await loadCaller({auth: {uid: 'u1'}}, 'c1');
    assert.deepStrictEqual([...c.perms].sort(), [...PERMS].sort(),
      'absent must behave as true until the migration has run');
  });
});

testAsync('the owner keeps clinical access whatever the clinic setting says', async () => {
  // The owner is the doctor; the setting is about delegated admins.
  await withMembers({
    'clinics/c1': {name: 'C1', adminClinicalAccess: false},
  }, async () => {
    const c = await loadCaller({auth: {uid: 'c1'}}, 'c1');
    assert.strictEqual(c.isOwner, true);
    assert.deepStrictEqual([...c.perms].sort(), [...PERMS].sort());
    requirePerm(c, 'clinical.edit');
  });
});

testAsync('a non-admin member is unaffected by adminClinicalAccess', async () => {
  await withMembers({
    'clinics/c1': {name: 'C1', adminClinicalAccess: false},
    'clinics/c1/members/u1': {
      active: true, roleId: 'doctor', perms: ['clinical.edit'],
    },
  }, async () => {
    const c = await loadCaller({auth: {uid: 'u1'}}, 'c1');
    assert.ok(c.perms.includes('clinical.edit'),
      'a doctor\'s own clinical access is not governed by the admin setting');
  });
});

testAsync('normalizes a member\'s stored permissions, adding implied ones', async () => {
  await withMembers({
    'clinics/c1/members/u1': {
      active: true, roleId: 'doctor', perms: ['clinical.edit', 'bogus'],
    },
  }, async () => {
    const c = await loadCaller({auth: {uid: 'u1'}}, 'c1');
    assert.strictEqual(c.isAdmin, false);
    assert.deepStrictEqual(c.perms, ['clinical.edit', 'clinical.view', 'patients.view']);
  });
});

testAsync('treats a member with absent perms as holding none', async () => {
  await withMembers({
    'clinics/c1/members/u1': {active: true, roleId: 'receptionist'},
  }, async () => {
    const c = await loadCaller({auth: {uid: 'u1'}}, 'c1');
    assert.deepStrictEqual(c.perms, []);
    throwsCode('permission-denied', () => requirePerm(c, 'team'));
  });
});

testAsync('reads the member of the requested clinic, not another one', async () => {
  // Cross-clinic: u1 is an admin of c2 but not a member of c1.
  await withMembers({
    'clinics/c2/members/u1': {active: true, roleId: 'admin', perms: PERMS},
  }, async () => {
    await rejectsCode('permission-denied', loadCaller({auth: {uid: 'u1'}}, 'c1'));
    const c = await loadCaller({auth: {uid: 'u1'}}, 'c2');
    assert.strictEqual(c.isAdmin, true);
  });
});

testAsync('an active member is never flagged as owner', async () => {
  await withMembers({
    'clinics/c1/members/u1': {active: true, roleId: 'doctor', perms: ['patients.view']},
  }, async () => {
    const c = await loadCaller({auth: {uid: 'u1'}}, 'c1');
    assert.strictEqual(c.isOwner, false);
    assert.strictEqual(c.clinicId, 'c1');
    assert.strictEqual(c.uid, 'u1');
  });
});

// ==================================================================
console.log('\nconstants and role templates');
// ==================================================================

test('PERMS has no duplicates', () => {
  assert.strictEqual(new Set(PERMS).size, PERMS.length);
});

test('ADMIN_PERMS is PERMS minus the clinical ones, and nothing else', () => {
  for (const p of CLINICAL_PERMS) {
    assert.ok(PERMS.includes(p), `${p} must be a real permission`);
    assert.ok(!ADMIN_PERMS.includes(p), `${p} must not be an admin permission`);
  }
  assert.strictEqual(ADMIN_PERMS.length, PERMS.length - CLINICAL_PERMS.length);
  // The split must not quietly drop an administrative permission.
  for (const p of PERMS) {
    assert.ok(ADMIN_PERMS.includes(p) || CLINICAL_PERMS.includes(p),
      `${p} belongs to neither set`);
  }
});

test('an admin still runs the clinic: team and settings stay administrative', () => {
  for (const p of ['team', 'settings', 'billing', 'revenue', 'inventory',
    'schedule', 'messaging', 'ai', 'patients.view', 'patients.edit']) {
    assert.ok(ADMIN_PERMS.includes(p), `${p} should remain an admin permission`);
  }
});

test('MODULES and DENTAL_FEATURES have no duplicates', () => {
  assert.strictEqual(new Set(MODULES).size, MODULES.length);
  assert.strictEqual(new Set(DENTAL_FEATURES).size, DENTAL_FEATURES.length);
});

test('every role template references only real permissions', () => {
  for (const r of ROLE_TEMPLATES) {
    for (const p of r.perms) {
      assert.ok(PERMS.includes(p), `role "${r.id}" references unknown permission "${p}"`);
    }
  }
});

test('every role template\'s perms are already normalized', () => {
  // If a template is missing an implied permission, a seeded clinic and a
  // re-saved role would disagree about what that role can do.
  for (const r of ROLE_TEMPLATES) {
    assert.deepStrictEqual(normalizePerms(r.perms), [...r.perms].sort(),
      `role "${r.id}" is not normalized (missing an implied permission?)`);
  }
});

test('role templates have unique ids and kinds of doctor or staff', () => {
  const ids = ROLE_TEMPLATES.map((r) => r.id);
  assert.strictEqual(new Set(ids).size, ids.length);
  for (const r of ROLE_TEMPLATES) {
    assert.ok(['doctor', 'staff'].includes(r.kind), `role "${r.id}" has kind "${r.kind}"`);
  }
});

test('only the admin template is a system role, and it holds every permission', () => {
  const system = ROLE_TEMPLATES.filter((r) => r.isSystem);
  assert.deepStrictEqual(system.map((r) => r.id), ['admin']);
  assert.deepStrictEqual([...system[0].perms].sort(), [...PERMS].sort());
});

test('CHARACTERISES the Admin template being staff kind yet holding clinical.edit', () => {
  // The crux of separating administrative authority from clinical
  // privilege: today a non-clinical practice manager necessarily holds
  // write access to every patient's clinical record. Expected to change.
  const admin = ROLE_TEMPLATES.find((r) => r.id === 'admin');
  assert.strictEqual(admin.kind, 'staff');
  assert.ok(admin.perms.includes('clinical.edit'));
  assert.ok(admin.perms.includes('clinical.view'));
});

test('no staff template may WRITE clinical records, except admin', () => {
  // The invariant that matters: recording a diagnosis or a clinical note is
  // a clinical act, so `clinical.edit` has no business on a staff role.
  // `admin` is the sole exception today and only because of the bypass
  // above; it is expected to drop off this list, leaving it empty.
  const writers = ROLE_TEMPLATES
    .filter((r) => r.kind === 'staff' && r.perms.includes('clinical.edit'))
    .map((r) => r.id);
  assert.deepStrictEqual(writers, ['admin'],
    'a staff role other than admin gained clinical WRITE access');
});

test('CHARACTERISES staff templates that may READ clinical records', () => {
  // Read access is a different question from write: an assistant or nurse
  // legitimately needs to see the chart they are assisting with, so
  // `clinical.view` on a staff role is intended, not a defect. Pinned so
  // that a new staff role gaining chart visibility is a visible decision.
  const readers = ROLE_TEMPLATES
    .filter((r) => r.kind === 'staff' && r.perms.includes('clinical.view'))
    .map((r) => r.id)
    .sort();
  assert.deepStrictEqual(readers, ['admin', 'assistant'],
    'a staff role gained clinical read access');
});

test('the receptionist template cannot write clinical records or see revenue', () => {
  const recep = ROLE_TEMPLATES.find((r) => r.id === 'receptionist');
  assert.strictEqual(recep.kind, 'staff');
  for (const denied of ['clinical.view', 'clinical.edit', 'revenue', 'team', 'settings']) {
    assert.ok(!recep.perms.includes(denied),
      `the receptionist template must not hold "${denied}"`);
  }
  for (const granted of ['patients.view', 'patients.edit', 'schedule', 'billing', 'messaging']) {
    assert.ok(recep.perms.includes(granted),
      `the receptionist template should hold "${granted}"`);
  }
});

test('the doctor template is doctor kind with clinical access but no admin rights', () => {
  const doc = ROLE_TEMPLATES.find((r) => r.id === 'doctor');
  assert.strictEqual(doc.kind, 'doctor');
  assert.ok(doc.perms.includes('clinical.edit'));
  for (const denied of ['team', 'settings', 'revenue', 'inventory']) {
    assert.ok(!doc.perms.includes(denied), `the doctor template must not hold "${denied}"`);
  }
});

test('seat defaults and limits are sane', () => {
  assert.ok(DEFAULT_SEATS.doctor > 0 && DEFAULT_SEATS.staff > 0);
  assert.ok(INVITE_DAYS > 0 && INVITE_DAYS <= 30);
  assert.ok(MAX_ROLES >= ROLE_TEMPLATES.length);
});

// ==================================================================
// Async tests run last so the sync output stays grouped.
// ==================================================================
(async () => {
  console.log('\n— running async loadCaller tests —');
  for (const t of asyncTests) await t();
  console.log(`\n${passed} assertions passed`);
  if (process.exitCode) console.error('SOME TESTS FAILED');
})();
