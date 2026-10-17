/**
 * End-to-end tests for the clinicTeam actions added for admin/clinical
 * separation and patient assignment, and for the functions that keep each
 * clinical record's copy of its patient's assignment current.
 *
 * Run with:  npm run build && node test/clinic-actions.test.js
 *
 * These call the real handlers (clinicTeam.run, trigger.run) against an
 * in-memory Firestore that understands subcollections, so they exercise the
 * same code paths production does — loadCaller, the permission checks, the
 * writes and the audit entries — without an emulator.
 */
const assert = require('assert');
const {NestedFakeDb, installNestedFake, FakeAuth, installFakeAuth} =
  require('./fake-firestore-nested');

const db = new NestedFakeDb();
installNestedFake(db);
const auth = new FakeAuth();
installFakeAuth(auth);

const {clinicTeam, PERMS} = require('../lib/clinic');
const assignment = require('../lib/clinical-assignment');

let passed = 0;
const queue = [];
function test(name, fn) {
  queue.push(async () => {
    db.store.clear();
    db.failNextCommit = false;
    auth.reset();
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
function section(title) {
  queue.push(async () => console.log(`\n${title}`));
}

const C = 'owner-1'; // a clinic's id is its owner's uid
const call = (uid, data, token = {}) => clinicTeam.run({auth: {uid, token}, data});

async function rejects(code, promise, note = '') {
  try {
    await promise;
  } catch (err) {
    assert.strictEqual(err.code, code, `expected ${code}, got ${err.code} (${err.message}) ${note}`);
    return err;
  }
  assert.fail(`expected ${code}, but it succeeded ${note}`);
}

const DOCTOR_PERMS = ['patients.view', 'patients.edit', 'clinical.view', 'clinical.edit',
  'schedule', 'billing', 'messaging', 'ai'];

/** A clinic with an owner, an admin, two doctors, a receptionist and an accountant. */
function seedClinic({scope = 'clinic', adminClinicalAccess = false} = {}) {
  db.seed(`clinics/${C}`, {name: 'Clinic', ownerUid: C, clinicalAccessScope: scope,
    adminClinicalAccess, seats: {doctor: 5, staff: 10}});
  const m = (uid, extra) => db.seed(`clinics/${C}/members/${uid}`, {
    name: uid, phone: '', email: '', active: true, isOwner: false, specialty: '', ...extra});
  m(C, {kind: 'doctor', roleId: 'admin', perms: PERMS, isOwner: true});
  m('mgr', {kind: 'staff', roleId: 'admin', perms: PERMS});
  m('doc1', {kind: 'doctor', roleId: 'doctor', perms: DOCTOR_PERMS});
  m('doc2', {kind: 'doctor', roleId: 'doctor', perms: DOCTOR_PERMS});
  m('recep', {kind: 'staff', roleId: 'receptionist',
    perms: ['patients.view', 'patients.edit', 'schedule', 'billing', 'messaging']});
  m('acct', {kind: 'staff', roleId: 'accountant', perms: ['patients.view', 'billing', 'revenue']});
  m('gone', {kind: 'doctor', roleId: 'doctor', perms: DOCTOR_PERMS, active: false});
  for (const r of [
    {id: 'admin', name: 'Admin', kind: 'staff', perms: PERMS},
    {id: 'doctor', name: 'Doctor', kind: 'doctor', perms: DOCTOR_PERMS},
    {id: 'receptionist', name: 'Receptionist', kind: 'staff',
      perms: ['patients.view', 'patients.edit', 'schedule', 'billing', 'messaging']},
    {id: 'assistant', name: 'Assistant', kind: 'staff',
      perms: ['patients.view', 'clinical.view', 'schedule', 'inventory']},
  ]) db.seed(`clinics/${C}/roles/${r.id}`, {name: r.name, kind: r.kind, perms: r.perms});
  db.seed('patients/p1', {doctorId: C, firstName: 'Alice', assignedDoctorUids: []});
}

const audit = (action) => db.all('access_logs').filter((l) => l.action === action);

// ==================================================================
section('setAdminClinicalAccess');
// ==================================================================

test('the owner can grant and revoke, and each is audited', async () => {
  seedClinic();
  const on = await call(C, {action: 'setAdminClinicalAccess', clinicId: C, enabled: true});
  assert.strictEqual(on.adminClinicalAccess, true);
  assert.strictEqual(db.peek(`clinics/${C}`).adminClinicalAccess, true);
  assert.strictEqual(db.peek(`clinics/${C}`).adminClinicalAccessSetBy, C);
  assert.strictEqual(audit('clinic.adminClinical.grant').length, 1);

  await call(C, {action: 'setAdminClinicalAccess', clinicId: C, enabled: false});
  assert.strictEqual(db.peek(`clinics/${C}`).adminClinicalAccess, false);
  assert.strictEqual(audit('clinic.adminClinical.revoke').length, 1);
});

test('an admin cannot grant it, not even to themselves', async () => {
  seedClinic();
  await rejects('permission-denied',
    call('mgr', {action: 'setAdminClinicalAccess', clinicId: C, enabled: true}));
  assert.strictEqual(db.peek(`clinics/${C}`).adminClinicalAccess, false, 'unchanged');
  assert.strictEqual(audit('clinic.adminClinical.grant').length, 0);
});

test('no other member can change it either', async () => {
  seedClinic();
  for (const uid of ['doc1', 'recep', 'acct']) {
    await rejects('permission-denied',
      call(uid, {action: 'setAdminClinicalAccess', clinicId: C, enabled: true}), uid);
  }
});

test('refuses anything but a real boolean', async () => {
  seedClinic();
  for (const enabled of ['true', 1, null, undefined]) {
    await rejects('invalid-argument',
      call(C, {action: 'setAdminClinicalAccess', clinicId: C, enabled}), JSON.stringify(enabled));
  }
});

test('refuses a clinic that does not exist', async () => {
  // The owner path does not need a member doc, so this reaches the check.
  await rejects('not-found',
    call('nobody', {action: 'setAdminClinicalAccess', clinicId: 'nobody', enabled: true}));
});

// ==================================================================
section('setClinicalAccessScope');
// ==================================================================

test('the owner can switch to assigned, and existing records get their copy first', async () => {
  seedClinic();
  db.seed('patients/p1', {doctorId: C, assignedDoctorUids: ['doc1']});
  db.seed('dental_records/r1', {doctorId: C, patientId: 'p1'});
  db.seed('radiology_docs/x1', {doctorId: C, patientId: 'p1'});
  const res = await call(C, {action: 'setClinicalAccessScope', clinicId: C, scope: 'assigned'});
  assert.strictEqual(res.clinicalAccessScope, 'assigned');
  assert.strictEqual(res.recordsUpdated, 2);
  assert.deepStrictEqual(db.peek('dental_records/r1').assignedDoctorUids, ['doc1']);
  assert.deepStrictEqual(db.peek('radiology_docs/x1').assignedDoctorUids, ['doc1']);
  assert.strictEqual(db.peek(`clinics/${C}`).clinicalAccessScope, 'assigned');
  assert.strictEqual(audit('clinic.clinicalScope.assigned').length, 1);
});

test('switching back to clinic-wide touches no records', async () => {
  seedClinic({scope: 'assigned'});
  db.seed('dental_records/r1', {doctorId: C, patientId: 'p1'});
  const res = await call(C, {action: 'setClinicalAccessScope', clinicId: C, scope: 'clinic'});
  assert.strictEqual(res.recordsUpdated, 0);
  assert.strictEqual(db.peek('dental_records/r1').assignedDoctorUids, undefined);
});

test('only the owner may change it', async () => {
  seedClinic();
  for (const uid of ['mgr', 'doc1', 'recep']) {
    await rejects('permission-denied',
      call(uid, {action: 'setClinicalAccessScope', clinicId: C, scope: 'assigned'}), uid);
  }
  assert.strictEqual(db.peek(`clinics/${C}`).clinicalAccessScope, 'clinic');
});

test('refuses an unknown scope', async () => {
  seedClinic();
  for (const scope of ['', 'everyone', 'ASSIGNED', null]) {
    await rejects('invalid-argument',
      call(C, {action: 'setClinicalAccessScope', clinicId: C, scope}), JSON.stringify(scope));
  }
});

// ==================================================================
section('assignPatient');
// ==================================================================

const assign = (uid, doctorUids, patientId = 'p1') =>
  call(uid, {action: 'assignPatient', clinicId: C, patientId, doctorUids});

test('the front desk can assign doctors, and it is audited', async () => {
  seedClinic();
  const res = await assign('recep', ['doc1', 'doc2']);
  assert.deepStrictEqual(res.assignedDoctorUids, ['doc1', 'doc2']);
  assert.deepStrictEqual(db.peek('patients/p1').assignedDoctorUids, ['doc1', 'doc2']);
  assert.strictEqual(audit('patient.assign').length, 1);
});

test('the owner counts as a doctor who can be assigned', async () => {
  seedClinic();
  await assign('recep', [C]);
  assert.deepStrictEqual(db.peek('patients/p1').assignedDoctorUids, [C]);
});

test('an empty list unassigns the patient', async () => {
  seedClinic();
  db.seed('patients/p1', {doctorId: C, assignedDoctorUids: ['doc1']});
  await assign('recep', []);
  assert.deepStrictEqual(db.peek('patients/p1').assignedDoctorUids, []);
});

test('trims and de-duplicates the list', async () => {
  seedClinic();
  await assign('recep', [' doc1 ', 'doc1', '', 'doc2']);
  assert.deepStrictEqual(db.peek('patients/p1').assignedDoctorUids, ['doc1', 'doc2']);
});

test('needs patients.edit', async () => {
  seedClinic();
  await rejects('permission-denied', assign('acct', ['doc1']));
});

test('only active doctors of this clinic can be assigned', async () => {
  seedClinic();
  await rejects('invalid-argument', assign('recep', ['recep']), 'a receptionist');
  await rejects('invalid-argument', assign('recep', ['gone']), 'an inactive doctor');
  await rejects('invalid-argument', assign('recep', ['stranger']), 'a non-member');
  assert.deepStrictEqual(db.peek('patients/p1').assignedDoctorUids, [], 'unchanged');
});

test("refuses another clinic's patient", async () => {
  seedClinic();
  db.seed('patients/foreign', {doctorId: 'other', assignedDoctorUids: []});
  await rejects('permission-denied', assign('recep', ['doc1'], 'foreign'));
  assert.deepStrictEqual(db.peek('patients/foreign').assignedDoctorUids, []);
});

test('refuses a patient that does not exist', async () => {
  seedClinic();
  await rejects('not-found', assign('recep', ['doc1'], 'ghost'));
});

test('refuses a list that is not a list, or too long', async () => {
  seedClinic();
  await rejects('invalid-argument', assign('recep', 'doc1'));
  await rejects('invalid-argument',
    assign('recep', Array.from({length: 51}, (_, i) => `d${i}`)));
});

test('a scoped doctor cannot assign anyone — not even themselves', async () => {
  // The hole this closes: assignPatient runs with admin rights, so without
  // this check a doctor confined to their own patients could add themselves
  // to anybody's.
  seedClinic({scope: 'assigned'});
  db.seed('patients/theirs', {doctorId: C, assignedDoctorUids: ['doc2']});
  await rejects('permission-denied', assign('doc1', ['doc1', 'doc2'], 'theirs'));
  assert.deepStrictEqual(db.peek('patients/theirs').assignedDoctorUids, ['doc2'], 'unchanged');
});

test('in a scoped clinic the front desk and the owner still can', async () => {
  seedClinic({scope: 'assigned'});
  await assign('recep', ['doc1']);
  await assign(C, ['doc1', 'doc2']);
  assert.deepStrictEqual(db.peek('patients/p1').assignedDoctorUids, ['doc1', 'doc2']);
});

test('in a clinic-wide clinic a doctor may assign (it grants nothing there)', async () => {
  seedClinic({scope: 'clinic'});
  await assign('doc1', ['doc2']);
  assert.deepStrictEqual(db.peek('patients/p1').assignedDoctorUids, ['doc2']);
});

// ==================================================================
section('the staff / clinical-write invariant in the actions');
// ==================================================================

test('saveRole refuses a staff role that writes clinical records', async () => {
  seedClinic();
  await rejects('invalid-argument', call(C, {action: 'saveRole', clinicId: C,
    name: 'Scribe', kind: 'staff', perms: ['patients.view', 'clinical.edit']}));
});

test('saveRole allows a staff role that only reads them', async () => {
  seedClinic();
  const res = await call(C, {action: 'saveRole', clinicId: C,
    name: 'Nurse', kind: 'staff', perms: ['patients.view', 'clinical.view']});
  assert.ok(res.roleId);
});

test('saveRole allows a doctor role to write them', async () => {
  seedClinic();
  const res = await call(C, {action: 'saveRole', clinicId: C,
    name: 'Consultant', kind: 'doctor', perms: ['patients.view', 'clinical.edit']});
  assert.ok(res.roleId);
});

test("invite refuses making someone staff with a role that writes records", async () => {
  seedClinic();
  db.seed(`clinics/${C}/roles/legacy`, {name: 'Legacy', kind: 'staff',
    perms: ['patients.view', 'clinical.edit']});
  await rejects('invalid-argument', call(C, {action: 'invite', clinicId: C, name: 'X',
    phone: '9876500001', kind: 'staff', roleId: 'legacy'}));
  // Inviting with the doctor role as staff is the same mismatch.
  await rejects('invalid-argument', call(C, {action: 'invite', clinicId: C, name: 'Y',
    phone: '9876500002', kind: 'staff', roleId: 'doctor'}));
});

test('invite still works for the ordinary cases', async () => {
  seedClinic();
  const doc = await call(C, {action: 'invite', clinicId: C, name: 'Dr New',
    phone: '9876500003', kind: 'doctor', roleId: 'doctor'});
  assert.ok(doc.inviteId);
  const nurse = await call(C, {action: 'invite', clinicId: C, name: 'Nurse',
    phone: '9876500004', kind: 'staff', roleId: 'assistant'});
  assert.ok(nurse.inviteId);
  // The built-in admin role stays exempt while it carries every permission.
  const adm = await call(C, {action: 'invite', clinicId: C, name: 'Manager',
    phone: '9876500005', kind: 'staff', roleId: 'admin'});
  assert.ok(adm.inviteId);
});

test('updateMember refuses turning a doctor into staff while they keep doctor rights', async () => {
  seedClinic();
  await rejects('invalid-argument',
    call(C, {action: 'updateMember', clinicId: C, uid: 'doc1', kind: 'staff'}));
  assert.strictEqual(db.peek(`clinics/${C}/members/doc1`).kind, 'doctor', 'unchanged');
});

test('updateMember refuses giving a staff member the doctor role', async () => {
  seedClinic();
  await rejects('invalid-argument',
    call(C, {action: 'updateMember', clinicId: C, uid: 'recep', roleId: 'doctor'}));
});

test('updateMember allows the consistent change of both at once', async () => {
  seedClinic();
  await call(C, {action: 'updateMember', clinicId: C, uid: 'recep', roleId: 'doctor', kind: 'doctor'});
  const m = db.peek(`clinics/${C}/members/recep`);
  assert.strictEqual(m.kind, 'doctor');
  assert.strictEqual(m.roleId, 'doctor');
});

test('updateMember leaves a member who predates the rule editable otherwise', async () => {
  seedClinic();
  db.seed(`clinics/${C}/members/old`, {name: 'Old', active: true, kind: 'staff',
    roleId: 'legacy', perms: ['patients.view', 'clinical.edit']});
  await call(C, {action: 'updateMember', clinicId: C, uid: 'old', specialty: 'Ortho'});
  assert.strictEqual(db.peek(`clinics/${C}/members/old`).specialty, 'Ortho');
});

// ==================================================================
section('ensureClinic: a doctor-owner or a manager-owner');
// ==================================================================

const OWNER = 'new-owner';
function seedSignup(claims = {}) {
  db.seed(`users/${OWNER}`, {name: 'Asha', specialty: 'Dentist'});
  auth.seedUser({uid: OWNER, email: 'asha@clinic.test', customClaims: claims});
}
const setUp = (extra) => call(OWNER,
  {action: 'ensureClinic', clinicName: 'Sunrise', ownerName: 'Asha', specialty: 'Dentist', ...extra},
  {email: 'asha@clinic.test'});

test('a doctor-owner is set up exactly as before', async () => {
  seedSignup();
  const res = await setUp({});
  assert.strictEqual(res.ownerIsDoctor, true);
  assert.strictEqual(db.peek(`clinics/${OWNER}`).ownerIsDoctor, true);
  const m = db.peek(`clinics/${OWNER}/members/${OWNER}`);
  assert.strictEqual(m.kind, 'doctor');
  assert.deepStrictEqual([...m.perms].sort(), [...PERMS].sort());
  assert.strictEqual(auth.users.get(OWNER).customClaims.nonClinicalOwner, undefined,
    'a doctor-owner must not be restricted');
  assert.strictEqual(db.peek(`users/${OWNER}`).clinicId, OWNER);
});

test('a manager-owner is listed as staff, without clinical permissions', async () => {
  seedSignup();
  const res = await setUp({ownerIsDoctor: false});
  assert.strictEqual(res.ownerIsDoctor, false);
  assert.strictEqual(db.peek(`clinics/${OWNER}`).ownerIsDoctor, false);
  const m = db.peek(`clinics/${OWNER}/members/${OWNER}`);
  assert.strictEqual(m.kind, 'staff');
  assert.ok(!m.perms.includes('clinical.view') && !m.perms.includes('clinical.edit'));
  assert.ok(m.perms.includes('team') && m.perms.includes('settings'));
});

test('a manager-owner gets the claim the rules read, merged with existing claims', async () => {
  seedSignup({beta: true});
  await setUp({ownerIsDoctor: false});
  assert.deepStrictEqual(auth.users.get(OWNER).customClaims, {beta: true, nonClinicalOwner: true});
});

test('an existing clinic is never switched to a manager-owner', async () => {
  // Decided once at creation; a later call must not strip a doctor's access.
  seedSignup();
  await setUp({});
  await setUp({ownerIsDoctor: false});
  assert.strictEqual(db.peek(`clinics/${OWNER}`).ownerIsDoctor, true);
  assert.strictEqual(auth.users.get(OWNER).customClaims.nonClinicalOwner, undefined);
});

test('a failed setup takes the claim back off', async () => {
  seedSignup({beta: true});
  db.failNextCommit = true;
  await assert.rejects(setUp({ownerIsDoctor: false}));
  assert.deepStrictEqual(auth.users.get(OWNER).customClaims, {beta: true});
  assert.strictEqual(db.peek(`clinics/${OWNER}`), undefined, 'no half-made clinic');
});

test('a manager-owner cannot be assigned as a patient\'s doctor', async () => {
  seedClinic();
  db.seed(`clinics/${C}`, {...db.peek(`clinics/${C}`), ownerIsDoctor: false});
  await rejects('invalid-argument', assign('recep', [C]));
});

// ==================================================================
section('createMember: the admin creates the login');
// ==================================================================

const create = (uid, extra) => call(uid, {action: 'createMember', clinicId: C, ...extra});

test('creates an email account, its member record and its profile', async () => {
  seedClinic();
  const res = await create(C, {name: 'Dr Ravi', email: 'Ravi@Clinic.test', kind: 'doctor',
    roleId: 'doctor', specialty: 'Dentist', modules: ['patients', 'appointments'],
    dentalFeatures: ['endo']});
  assert.strictEqual(res.mode, 'created');
  assert.strictEqual(res.contact, 'email');

  const user = auth.users.get(res.uid);
  assert.strictEqual(user.email, 'ravi@clinic.test', 'stored lower-case');
  assert.strictEqual(user.displayName, 'Dr Ravi');
  assert.strictEqual(user.password, undefined, 'the admin never sets a password');

  const m = db.peek(`clinics/${C}/members/${res.uid}`);
  assert.strictEqual(m.kind, 'doctor');
  assert.strictEqual(m.roleId, 'doctor');
  assert.strictEqual(m.active, true);
  assert.strictEqual(m.specialty, 'Dentist');
  assert.deepStrictEqual(m.modules, ['appointments', 'patients']);
  assert.deepStrictEqual(m.dentalFeatures, ['endo']);
  assert.strictEqual(m.createdBy, C);

  const p = db.peek(`users/${res.uid}`);
  assert.strictEqual(p.clinicId, C);
  assert.strictEqual(p.memberKind, 'doctor', 'so they skip the owner onboarding');
  assert.strictEqual(audit('team.createMember').length, 1);
});

test('creates a phone account, normalising the number', async () => {
  seedClinic();
  const res = await create(C, {name: 'Rahul', phone: '98765 43210', kind: 'staff', roleId: 'receptionist'});
  assert.strictEqual(res.contact, 'phone');
  assert.strictEqual(auth.users.get(res.uid).phoneNumber, '+919876543210');
  assert.strictEqual(db.peek(`clinics/${C}/members/${res.uid}`).specialty, '', 'staff has none');
});

test('leaves an existing account alone and asks for an invite instead', async () => {
  seedClinic();
  auth.seedUser({uid: 'already', email: 'taken@clinic.test'});
  const before = auth.users.size;
  const res = await create(C, {name: 'X', email: 'taken@clinic.test', kind: 'staff', roleId: 'receptionist'});
  assert.strictEqual(res.mode, 'exists');
  assert.strictEqual(auth.users.size, before, 'no account created');
  assert.strictEqual(db.peek(`clinics/${C}/members/already`), undefined, 'not taken over');
});

test('needs the team permission', async () => {
  seedClinic();
  await rejects('permission-denied',
    create('recep', {name: 'X', email: 'x@c.test', kind: 'staff', roleId: 'receptionist'}));
  assert.strictEqual(auth.users.size, 0);
});

test('cannot hand out more than the creator holds', async () => {
  seedClinic();
  db.seed(`clinics/${C}/members/lead`, {name: 'Lead', active: true, kind: 'staff',
    roleId: 'lead', perms: ['team', 'schedule', 'patients.view']});
  await rejects('permission-denied',
    create('lead', {name: 'X', email: 'x@c.test', kind: 'doctor', roleId: 'doctor'}));
  await rejects('permission-denied',
    create('lead', {name: 'Y', email: 'y@c.test', kind: 'staff', roleId: 'admin'}));
  assert.strictEqual(auth.users.size, 0);
});

test('refuses staff with a role that writes medical records', async () => {
  seedClinic();
  await rejects('invalid-argument',
    create(C, {name: 'X', email: 'x@c.test', kind: 'staff', roleId: 'doctor'}));
  assert.strictEqual(auth.users.size, 0);
});

test('respects the seat limit', async () => {
  seedClinic();
  // mgr, recep and acct already fill three staff seats.
  db.seed(`clinics/${C}`, {...db.peek(`clinics/${C}`), seats: {doctor: 5, staff: 3}});
  await rejects('resource-exhausted',
    create(C, {name: 'X', email: 'x@c.test', kind: 'staff', roleId: 'receptionist'}));
  assert.strictEqual(auth.users.size, 0, 'no account created past the limit');
});

test('refuses missing or doubled contact details, and a missing name', async () => {
  seedClinic();
  const base = {kind: 'staff', roleId: 'receptionist'};
  await rejects('invalid-argument', create(C, {...base, name: 'X'}));
  await rejects('invalid-argument', create(C, {...base, name: 'X', email: 'a@b.test', phone: '9876543210'}));
  await rejects('invalid-argument', create(C, {...base, name: '', email: 'a@b.test'}));
  await rejects('invalid-argument', create(C, {...base, name: 'X', email: 'not-an-email'}));
  await rejects('not-found', create(C, {...base, name: 'X', email: 'a@b.test', roleId: 'nope'}));
});

test('removes the new account if its records cannot be written', async () => {
  seedClinic();
  db.failNextCommit = true;
  await rejects('internal',
    create(C, {name: 'X', email: 'x@c.test', kind: 'staff', roleId: 'receptionist'}));
  assert.strictEqual(auth.users.size, 0, 'no account left behind without a clinic');
});

test('a manager-owner can create staff and doctors', async () => {
  seedClinic();
  db.seed(`clinics/${C}`, {...db.peek(`clinics/${C}`), ownerIsDoctor: false});
  const doc = await create(C, {name: 'Dr A', email: 'a@c.test', kind: 'doctor', roleId: 'doctor'});
  assert.strictEqual(doc.mode, 'created', 'creating a doctor role is administration, not clinical access');
});

// ==================================================================
section('the copy of the assignment on clinical records');
// ==================================================================

const snapOf = async (path) => db.doc(path).get();
const changeEvent = async (path, before, params) => ({
  data: {before: before === undefined ? {exists: false, data: () => undefined} : before,
    after: await snapOf(path)},
  params,
});

test('an assignment change reaches every clinical record of that patient', async () => {
  db.seed('patients/p1', {doctorId: C, assignedDoctorUids: []});
  for (const coll of assignment.CLINICAL_COLLECTIONS) {
    db.seed(`${coll}/a`, {doctorId: C, patientId: 'p1', assignedDoctorUids: []});
  }
  db.seed('dental_records/other-patient', {doctorId: C, patientId: 'p2', assignedDoctorUids: []});
  db.seed('dental_records/other-clinic', {doctorId: 'x', patientId: 'p1', assignedDoctorUids: []});

  const before = await snapOf('patients/p1');
  db.seed('patients/p1', {doctorId: C, assignedDoctorUids: ['doc1']});
  await assignment.fanOutPatientAssignment.run(
    await changeEvent('patients/p1', before, {patientId: 'p1'}));

  for (const coll of assignment.CLINICAL_COLLECTIONS) {
    assert.deepStrictEqual(db.peek(`${coll}/a`).assignedDoctorUids, ['doc1'], coll);
  }
  assert.deepStrictEqual(db.peek('dental_records/other-patient').assignedDoctorUids, [],
    "another patient's record must not change");
  assert.deepStrictEqual(db.peek('dental_records/other-clinic').assignedDoctorUids, [],
    "another clinic's record must not change");
});

test('an edit that does not change the assignment writes nothing', async () => {
  db.seed('patients/p1', {doctorId: C, firstName: 'A', assignedDoctorUids: ['doc1']});
  db.seed('dental_records/a', {doctorId: C, patientId: 'p1', assignedDoctorUids: ['doc1']});
  const before = await snapOf('patients/p1');
  db.seed('patients/p1', {doctorId: C, firstName: 'B', assignedDoctorUids: ['doc1']});
  const commits = db.commits;
  await assignment.fanOutPatientAssignment.run(
    await changeEvent('patients/p1', before, {patientId: 'p1'}));
  assert.strictEqual(db.commits, commits, 'no batch should have been committed');
});

test('a new clinical record is given its patient’s assignment', async () => {
  db.seed('patients/p1', {doctorId: C, assignedDoctorUids: ['doc2', 'doc1']});
  db.seed('dental_records/new', {doctorId: C, patientId: 'p1'});
  await assignment.stampDentalRecordAssignment.run(
    await changeEvent('dental_records/new', undefined, {recordId: 'new'}));
  assert.deepStrictEqual(db.peek('dental_records/new').assignedDoctorUids, ['doc1', 'doc2']);
});

test("a record never copies another clinic's patient, or a missing one", async () => {
  db.seed('patients/foreign', {doctorId: 'x', assignedDoctorUids: ['doc1']});
  db.seed('dental_records/borrow', {doctorId: C, patientId: 'foreign'});
  db.seed('dental_records/orphan', {doctorId: C, patientId: 'ghost'});
  assert.strictEqual(await assignment.stampRecord(db.doc('dental_records/borrow'),
    db.peek('dental_records/borrow')), false);
  assert.strictEqual(await assignment.stampRecord(db.doc('dental_records/orphan'),
    db.peek('dental_records/orphan')), false);
  assert.strictEqual(db.peek('dental_records/borrow').assignedDoctorUids, undefined);
});

test('stamping converges: a current copy is not rewritten', async () => {
  // The write the trigger makes fires it again; that second run must stop.
  db.seed('patients/p1', {doctorId: C, assignedDoctorUids: ['doc1']});
  db.seed('dental_records/r', {doctorId: C, patientId: 'p1', assignedDoctorUids: ['doc1']});
  assert.strictEqual(await assignment.stampRecord(db.doc('dental_records/r'),
    db.peek('dental_records/r')), false);
});

test('the clinic-wide backfill is complete, skips orphans, and is idempotent', async () => {
  db.seed('patients/p1', {doctorId: C, assignedDoctorUids: ['doc1']});
  db.seed('patients/p2', {doctorId: C});
  db.seed('dental_records/a', {doctorId: C, patientId: 'p1'});
  db.seed('procedure_log_entries/b', {doctorId: C, patientId: 'p2'});
  db.seed('dental_records/orphan', {doctorId: C, patientId: 'ghost'});
  db.seed('dental_records/elsewhere', {doctorId: 'x', patientId: 'p1'});

  assert.strictEqual(await assignment.copyAssignmentsForClinic(C), 2);
  assert.deepStrictEqual(db.peek('dental_records/a').assignedDoctorUids, ['doc1']);
  assert.deepStrictEqual(db.peek('procedure_log_entries/b').assignedDoctorUids, []);
  assert.strictEqual(db.peek('dental_records/orphan').assignedDoctorUids, undefined);
  assert.strictEqual(db.peek('dental_records/elsewhere').assignedDoctorUids, undefined);
  assert.strictEqual(await assignment.copyAssignmentsForClinic(C), 0, 'second run changes nothing');
});

test('uid lists compare by meaning, not order or spacing', async () => {
  assert.ok(assignment.sameUids(['b', 'a'], [' a', 'b', 'b']));
  assert.ok(assignment.sameUids(undefined, []));
  assert.ok(!assignment.sameUids(['a'], ['a', 'b']));
});

// ==================================================================
(async () => {
  for (const t of queue) await t();
  console.log(`\n${passed} tests passed`);
  if (process.exitCode) console.error('SOME TESTS FAILED');
})();
