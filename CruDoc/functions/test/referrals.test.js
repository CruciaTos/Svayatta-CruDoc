/**
 * Tests for referrals between doctors (src/referrals.ts).
 *
 * Run with:  npm run build && node test/referrals.test.js
 *
 * These call the real referralNetwork handler against the in-memory
 * Firestore and Auth fakes, plus small Storage and Messaging fakes, so the
 * permission checks, the encryption, the audit entries and the pushes are the
 * production code paths. The deny paths are spelled out on purpose: a
 * referral carries one clinic's patient to another doctor, and every way it
 * could reach the wrong person is a test here.
 */
process.env.PATIENT_KEK_PEPPER = 'test-pepper-not-the-real-one';

const assert = require('assert');
const admin = require('firebase-admin');
const {NestedFakeDb, installNestedFake, FakeAuth, installFakeAuth} =
  require('./fake-firestore-nested');

const db = new NestedFakeDb();
installNestedFake(db);
const auth = new FakeAuth();
installFakeAuth(auth);

// Storage: uploaded files by path; what was deleted and signed.
const files = new Map();
const deleted = [];
const bucket = {
  file: (path) => ({
    exists: async () => [files.has(path)],
    getMetadata: async () => [files.get(path)],
    getSignedUrl: async (o) => [`https://signed.test/${path}?expires=${o.expires}`],
    delete: async () => {
      deleted.push(path);
      files.delete(path);
    },
  }),
};
Object.defineProperty(admin, 'storage',
  {value: () => ({bucket: () => bucket}), configurable: true, writable: true});

// Messaging: every multicast sent; the token "dead" is reported unregistered.
const pushes = [];
Object.defineProperty(admin, 'messaging', {
  value: () => ({
    sendEachForMulticast: async (m) => {
      pushes.push(m);
      return {responses: m.tokens.map((t) => t === 'dead' ?
        {success: false, error: {code: 'messaging/registration-token-not-registered'}} :
        {success: true})};
    },
  }),
  configurable: true,
  writable: true,
});

const {
  referralNetwork, nextStatus, normalizeHandle, searchTokens, shareKey, cleanFileName,
  drName, SHARES, MATCH_PER_HOUR, SENDS_PER_DAY,
} = require('../lib/referrals');
const {decryptField} = require('../lib/crypto/patientCipher');
const {PERMS} = require('../lib/clinic');

let passed = 0;
const queue = [];
function test(name, fn) {
  queue.push(async () => {
    db.store.clear();
    auth.reset();
    files.clear();
    deleted.length = 0;
    pushes.length = 0;
    try {
      await fn();
      passed += 1;
      console.log(`  ok  ${name}`);
    } catch (err) {
      console.error(`FAIL  ${name}`);
      console.error(`      ${err.stack}`);
      process.exitCode = 1;
    }
  });
}
function section(title) {
  queue.push(async () => console.log(`\n${title}`));
}

async function rejects(code, promise, note = '') {
  try {
    await promise;
  } catch (err) {
    assert.strictEqual(err.code, code, `expected ${code}, got ${err.code} (${err.message}) ${note}`);
    return err;
  }
  assert.fail(`expected ${code}, but it succeeded ${note}`);
}

function throwsCode(code, fn) {
  try {
    fn();
  } catch (err) {
    assert.strictEqual(err.code, code, `expected ${code}, got ${err.code} (${err.message})`);
    return;
  }
  assert.fail(`expected ${code}, but it succeeded`);
}

const call = (uid, data) => referralNetwork.run({auth: {uid, token: {}}, data});

// Dr A: a solo surgeon (their own clinic id is their uid).
const A = 'dr-a';
// Smit: an anaesthetist with a phone login, and a phone to push to.
const SMIT = 'dr-smit';
const SMIT_PHONE = '+919876543210';
// A clinic where Dr A is not the owner, to test member senders.
const CLINIC = 'clinic-owner';

const DOCTOR_PERMS = ['patients.view', 'patients.edit', 'clinical.view', 'clinical.edit',
  'schedule', 'billing', 'messaging', 'ai'];

function seedPeople() {
  db.seed(`users/${A}`, {name: 'Asha Rao', specialty: 'General Surgery'});
  auth.seedUser({uid: A, phoneNumber: '+919000000001'});

  db.seed(`users/${SMIT}`, {name: 'Smit Patil', specialty: 'Anaesthesiology',
    clinicName: 'City Hospital'});
  db.seed(`users/${SMIT}/device_tokens/t1`, {token: 'tok-smit'});
  db.seed(`users/${SMIT}/device_tokens/t2`, {token: 'dead'});
  auth.seedUser({uid: SMIT, phoneNumber: SMIT_PHONE});

  // Verified email: matched. Unverified: anyone could have typed it in.
  db.seed('users/dr-mail', {name: 'Meera Shah', specialty: 'Cardiology'});
  auth.seedUser({uid: 'dr-mail', email: 'meera@hospital.test', emailVerified: true});
  db.seed('users/dr-unverified', {name: 'Not Proven'});
  auth.seedUser({uid: 'dr-unverified', email: 'claimed@hospital.test', emailVerified: false});

  // Never receive referrals: clinic staff, a manager-owner, a Super Admin.
  db.seed('users/recep', {name: 'Front Desk', memberKind: 'staff', clinicId: CLINIC});
  auth.seedUser({uid: 'recep', phoneNumber: '+919000000002'});
  db.seed('users/manager', {name: 'Manager', memberKind: 'owner'});
  db.seed('clinics/manager', {ownerIsDoctor: false});
  auth.seedUser({uid: 'manager', phoneNumber: '+919000000003'});
  db.seed('users/super', {name: 'Super', role: 'superAdmin'});
  auth.seedUser({uid: 'super', phoneNumber: '+919000000004'});

  // Turned off "let others find me by my number".
  db.seed('users/dr-hidden', {name: 'Hidden', discoverable: false});
  auth.seedUser({uid: 'dr-hidden', phoneNumber: '+919000000005'});

  // A clinic with a doctor member, a receptionist and a nurse.
  db.seed(`clinics/${CLINIC}`, {name: 'Clinic', ownerUid: CLINIC});
  const m = (uid, extra) => db.seed(`clinics/${CLINIC}/members/${uid}`,
    {name: uid, active: true, isOwner: false, ...extra});
  m('member-doc', {kind: 'doctor', roleId: 'doctor', perms: DOCTOR_PERMS});
  m('recep', {kind: 'staff', roleId: 'receptionist',
    perms: ['patients.view', 'patients.edit', 'schedule', 'billing', 'messaging']});
  m('nurse', {kind: 'staff', roleId: 'assistant', perms: ['patients.view', 'clinical.view']});
  db.seed('users/member-doc', {name: 'Member Doc', memberKind: 'doctor', clinicId: CLINIC});
  db.seed('users/nurse', {name: 'Nurse', memberKind: 'staff', clinicId: CLINIC});
}

const SHARE = 'share_0000000001';

function sendData(extra = {}) {
  return {
    action: 'send',
    clinicId: A,
    shareId: SHARE,
    recipientUid: SMIT,
    consent: true,
    patientId: 'p-1',
    localReferralId: 'ref-1',
    patient: {name: 'Ravi Kumar', phone: '9811111111', gender: 'male', age: 54},
    reason: 'Anaesthesia for laparoscopic cholecystectomy',
    findings: 'ASA II, controlled hypertension',
    question: 'Fit for GA?',
    urgency: 'soon',
    teeth: [],
    attachments: [],
    ...extra,
  };
}

const plain = (shareId, value) => decryptField(value,
  shareKey(shareId, process.env.PATIENT_KEK_PEPPER));

// ─────────────────────────────── pure helpers ───────────────────────────────

section('status rules');

test('the recipient moves a referral forward; the sender only withdraws', () => {
  assert.strictEqual(nextStatus('sent', 'accept', 'recipient'), 'acknowledged');
  assert.strictEqual(nextStatus('acknowledged', 'seen', 'recipient'), 'seen');
  assert.strictEqual(nextStatus('seen', 'complete', 'recipient'), 'completed');
  assert.strictEqual(nextStatus('completed', 'reply', 'recipient'), 'completed');
  assert.strictEqual(nextStatus('sent', 'decline', 'recipient'), 'declined');
  assert.strictEqual(nextStatus('seen', 'withdraw', 'sender'), 'withdrawn');
});

test('nobody acts for the other side', () => {
  throwsCode('permission-denied', () => nextStatus('sent', 'accept', 'sender'));
  throwsCode('permission-denied', () => nextStatus('sent', 'complete', 'sender'));
  throwsCode('permission-denied', () => nextStatus('sent', 'withdraw', 'recipient'));
});

test('a closed referral stays closed', () => {
  for (const s of ['completed', 'declined', 'withdrawn']) {
    throwsCode('failed-precondition', () => nextStatus(s, 'accept', 'recipient'));
    throwsCode('failed-precondition', () => nextStatus(s, 'withdraw', 'sender'));
  }
  throwsCode('failed-precondition', () => nextStatus('withdrawn', 'reply', 'recipient'));
  throwsCode('failed-precondition', () => nextStatus('seen', 'decline', 'recipient'));
  throwsCode('invalid-argument', () => nextStatus('sent', 'delete', 'sender'));
});

section('handles, search and names');

test('handles are normalised and checked', () => {
  assert.strictEqual(normalizeHandle('@Dr.Smit_Patil'), 'dr.smit_patil');
  for (const bad of ['ab', '.smit', 'smit.', 'sm..it', 'smit patil', 'a'.repeat(31), '', 'smit/x']) {
    throwsCode('invalid-argument', () => normalizeHandle(bad));
  }
});

test('search tokens cover prefixes of name, handle, specialty and city', () => {
  const t = searchTokens({displayName: 'Dr. Smit Patil', handle: 'smit.p',
    specialty: 'Anaesthesiology', city: 'Pune'});
  for (const w of ['sm', 'smit', 'pa', 'patil', 'an', 'anaesth', 'pu', 'pune', 'smit.p']) {
    assert.ok(t.includes(w), `missing ${w}`);
  }
  assert.ok(!t.includes('dr'), 'the title is not a search word');
  assert.ok(!t.includes('s'), 'single letters would match everyone');
});

test('file names cannot climb out of the share folder', () => {
  assert.strictEqual(cleanFileName('xray 1.png'), 'xray 1.png');
  for (const bad of ['../x.pdf', 'a/b.pdf', 'a\\b.pdf', '', 'x\u0000.pdf', 'a'.repeat(121)]) {
    throwsCode('invalid-argument', () => cleanFileName(bad));
  }
});

test('names get one "Dr." in front', () => {
  assert.strictEqual(drName('Smit Patil'), 'Dr. Smit Patil');
  assert.strictEqual(drName('Dr. Smit'), 'Dr. Smit');
  assert.strictEqual(drName('dr Smit'), 'dr Smit');
});

// ─────────────────────────────── matchContacts ───────────────────────────────

section('matchContacts');

test('finds doctors by phone and verified email, and nobody else', async () => {
  seedPeople();
  const res = await call(A, {action: 'matchContacts', clinicId: A, contacts: [
    {id: 'c-smit', phone: '098765 43210'},
    {id: 'c-mail', email: 'Meera@Hospital.test'},
    {id: 'c-unverified', email: 'claimed@hospital.test'},
    {id: 'c-recep', phone: '9000000002'},
    {id: 'c-manager', phone: '9000000003'},
    {id: 'c-super', phone: '9000000004'},
    {id: 'c-hidden', phone: '9000000005'},
    {id: 'c-self', phone: '9000000001'},
    {id: 'c-nobody', phone: '9123456789'},
  ]});
  const byId = Object.fromEntries(res.matches.map((m) => [m.id, m]));
  assert.deepStrictEqual(Object.keys(byId).sort(), ['c-mail', 'c-smit']);
  assert.strictEqual(byId['c-smit'].uid, SMIT);
  assert.strictEqual(byId['c-smit'].name, 'Smit Patil');
  assert.strictEqual(byId['c-smit'].specialty, 'Anaesthesiology');
  assert.strictEqual(byId['c-mail'].uid, 'dr-mail');
});

test('a phone match wins over an email match on the same contact', async () => {
  seedPeople();
  const res = await call(A, {action: 'matchContacts', clinicId: A, contacts: [
    {id: 'c', phone: SMIT_PHONE, email: 'meera@hospital.test'},
  ]});
  assert.strictEqual(res.matches.length, 1);
  assert.strictEqual(res.matches[0].uid, SMIT);
});

test('needs clinical access in the clinic it is asked for', async () => {
  seedPeople();
  await rejects('permission-denied', call('recep', {action: 'matchContacts', clinicId: CLINIC,
    contacts: [{id: 'c', phone: SMIT_PHONE}]}));
  await rejects('permission-denied', call(A, {action: 'matchContacts', clinicId: CLINIC,
    contacts: [{id: 'c', phone: SMIT_PHONE}]}), '(not a member)');
});

test('is rate limited per hour', async () => {
  seedPeople();
  db.seed(`rate_limits/${A}`, {matchReferralContacts: {windowStart: Date.now(), count: MATCH_PER_HOUR}});
  await rejects('resource-exhausted', call(A, {action: 'matchContacts', clinicId: A,
    contacts: [{id: 'c', phone: SMIT_PHONE}]}));
});

// ─────────────────────────────── directory ───────────────────────────────

section('saveDirectoryProfile');

test('lists a doctor with a unique handle and search tokens', async () => {
  seedPeople();
  await call(SMIT, {action: 'saveDirectoryProfile', listed: true, handle: '@Smit.P',
    displayName: 'Smit Patil', specialty: 'Anaesthesiology', city: 'Pune'});
  const card = db.peek(`doctor_directory/${SMIT}`);
  assert.strictEqual(card.listed, true);
  assert.strictEqual(card.handle, 'smit.p');
  assert.ok(card.searchTokens.includes('anaes'));
  assert.strictEqual(db.peek('doctor_handles/smit.p').uid, SMIT);

  await rejects('already-exists', call('dr-mail', {action: 'saveDirectoryProfile', listed: true,
    handle: 'smit.p', displayName: 'Meera'}));
});

test('changing a handle frees the old one; unlisting clears the search words', async () => {
  seedPeople();
  await call(SMIT, {action: 'saveDirectoryProfile', listed: true, handle: 'smit.p',
    displayName: 'Smit Patil'});
  await call(SMIT, {action: 'saveDirectoryProfile', listed: false, handle: 'smit.patil',
    displayName: 'Smit Patil'});
  assert.strictEqual(db.peek('doctor_handles/smit.p'), undefined);
  assert.strictEqual(db.peek('doctor_handles/smit.patil').uid, SMIT);
  assert.deepStrictEqual(db.peek(`doctor_directory/${SMIT}`).searchTokens, []);
});

test('staff cannot list themselves, and a listing needs a name and handle', async () => {
  seedPeople();
  await rejects('permission-denied', call('recep', {action: 'saveDirectoryProfile', listed: true,
    handle: 'frontdesk', displayName: 'Front Desk'}));
  await rejects('invalid-argument', call(SMIT, {action: 'saveDirectoryProfile', listed: true,
    displayName: 'Smit'}));
});

// ─────────────────────────────── send ───────────────────────────────

section('send');

test('sends an encrypted copy that only names the two doctors in clear', async () => {
  seedPeople();
  await call(A, sendData());
  const s = db.peek(`${SHARES}/${SHARE}`);
  assert.strictEqual(s.senderUid, A);
  assert.strictEqual(s.senderClinicId, A);
  assert.strictEqual(s.recipientUid, SMIT);
  assert.strictEqual(s.senderName, 'Asha Rao');
  assert.strictEqual(s.recipientName, 'Smit Patil');
  assert.strictEqual(s.status, 'sent');
  assert.strictEqual(s.urgency, 'soon');
  assert.strictEqual(s.patient.age, 54);

  // Free text is ciphertext at rest and reads back with the share key.
  for (const v of [s.patient.name, s.patient.phone, s.reason, s.findings, s.question]) {
    assert.ok(v.startsWith('enc:v1:'), `not encrypted: ${v}`);
  }
  assert.strictEqual(plain(SHARE, s.patient.name), 'Ravi Kumar');
  assert.strictEqual(plain(SHARE, s.reason), 'Anaesthesia for laparoscopic cholecystectomy');
  assert.strictEqual(plain(SHARE, s.history[0].note), 'Sent through CruDoc');
  assert.ok(!JSON.stringify(s).includes('Ravi'), 'patient name leaked in clear');

  const log = db.all('access_logs').find((l) => l.action === 'referral.share');
  assert.ok(log, 'no audit entry');
  assert.strictEqual(log.actorUid, A);
  assert.strictEqual(log.patientId, 'p-1');
  assert.strictEqual(log.recipientUid, SMIT);
});

test('pushes to the recipient without the patient, and drops dead tokens', async () => {
  seedPeople();
  await call(A, sendData({urgency: 'urgent'}));
  assert.strictEqual(pushes.length, 1);
  const p = pushes[0];
  assert.deepStrictEqual(p.tokens.sort(), ['dead', 'tok-smit']);
  assert.strictEqual(p.notification.title, 'Urgent: New referral from Dr. Asha Rao');
  assert.ok(!JSON.stringify(p).includes('Ravi'), 'patient on the lock screen');
  assert.deepStrictEqual(p.data, {type: 'referral', shareId: SHARE});
  assert.strictEqual(db.peek(`users/${SMIT}/device_tokens/t2`), undefined);
  assert.ok(db.peek(`users/${SMIT}/device_tokens/t1`));
});

test('a retry of the same send changes nothing and pushes once', async () => {
  seedPeople();
  await call(A, sendData());
  await call(A, sendData({reason: 'something else'}));
  assert.strictEqual(plain(SHARE, db.peek(`${SHARES}/${SHARE}`).reason),
    'Anaesthesia for laparoscopic cholecystectomy');
  assert.strictEqual(pushes.length, 1);
  await rejects('already-exists', call('dr-mail', sendData({clinicId: 'dr-mail'})),
    '(someone else reusing the id)');
});

test('refuses without the patient\'s consent', async () => {
  seedPeople();
  await rejects('failed-precondition', call(A, sendData({consent: false})));
  await rejects('failed-precondition', call(A, sendData({consent: 'yes'})));
  assert.strictEqual(db.peek(`${SHARES}/${SHARE}`), undefined);
});

test('only to a doctor who can receive referrals', async () => {
  seedPeople();
  await rejects('invalid-argument', call(A, sendData({recipientUid: A})), '(self)');
  for (const uid of ['recep', 'manager', 'super', 'dr-hidden', 'nobody']) {
    await rejects('not-found', call(A, sendData({recipientUid: uid})), `(${uid})`);
  }
});

test('a hidden doctor who listed themselves can still be referred to', async () => {
  seedPeople();
  db.seed('doctor_directory/dr-hidden', {listed: true, displayName: 'Hidden Listed'});
  await call(A, sendData({recipientUid: 'dr-hidden'}));
  assert.strictEqual(db.peek(`${SHARES}/${SHARE}`).recipientName, 'Hidden Listed');
});

test('only doctors with clinical access send, from their own clinic', async () => {
  seedPeople();
  await rejects('permission-denied', call('recep', sendData({clinicId: CLINIC})), '(receptionist)');
  await rejects('permission-denied', call('nurse', sendData({clinicId: CLINIC})), '(nurse)');
  await rejects('permission-denied', call(A, sendData({clinicId: CLINIC})), '(not a member)');
  await call('member-doc', sendData({clinicId: CLINIC}));
  assert.strictEqual(db.peek(`${SHARES}/${SHARE}`).senderClinicId, CLINIC);
});

test('a manager-owner, who never opens records, cannot send', async () => {
  seedPeople();
  await rejects('permission-denied', call('manager', sendData({clinicId: 'manager'})));
});

test('validates the referral itself', async () => {
  seedPeople();
  await rejects('invalid-argument', call(A, sendData({reason: ''})));
  await rejects('invalid-argument', call(A, sendData({patient: {name: ''}})));
  await rejects('invalid-argument', call(A, sendData({shareId: 'short'})));
  await rejects('invalid-argument', call(A, sendData({shareId: '../../etc/passwd'})));
  await rejects('invalid-argument', call(A, sendData({findings: 'x'.repeat(4001)})));
});

test('attachments must be this doctor\'s uploads for this share', async () => {
  seedPeople();
  const mine = `referral_uploads/${A}/${SHARE}/xray.png`;
  await rejects('failed-precondition', call(A, sendData({attachments: [{name: 'xray.png'}]})),
    '(not uploaded)');
  // The same name uploaded by someone else, or for another share, doesn't count.
  files.set(`referral_uploads/${SMIT}/${SHARE}/xray.png`, {size: 10, contentType: 'image/png'});
  files.set(`referral_uploads/${A}/other_share_01/xray.png`, {size: 10, contentType: 'image/png'});
  await rejects('failed-precondition', call(A, sendData({attachments: [{name: 'xray.png'}]})));
  await rejects('invalid-argument', call(A, sendData({attachments: [{name: '../other/xray.png'}]})));

  files.set(mine, {size: 2048, contentType: 'image/png'});
  await call(A, sendData({attachments: [{name: 'xray.png'}]}));
  assert.deepStrictEqual(db.peek(`${SHARES}/${SHARE}`).attachments,
    [{name: 'xray.png', path: mine, size: 2048, contentType: 'image/png'}]);
});

test('refuses a file of the wrong type', async () => {
  seedPeople();
  files.set(`referral_uploads/${A}/${SHARE}/run.exe`, {size: 10, contentType: 'application/x-msdownload'});
  await rejects('invalid-argument', call(A, sendData({attachments: [{name: 'run.exe'}]})));
});

test('is rate limited per day', async () => {
  seedPeople();
  db.seed(`rate_limits/${A}`, {referralSends: {windowStart: Date.now(), count: SENDS_PER_DAY}});
  await rejects('resource-exhausted', call(A, sendData()));
});

// ─────────────────────────────── update ───────────────────────────────

section('update');

test('the recipient accepts, sees, replies and completes; the sender is told each time', async () => {
  seedPeople();
  db.seed(`users/${A}/device_tokens/t`, {token: 'tok-a'});
  await call(A, sendData());
  pushes.length = 0;

  const up = (step, extra = {}) => call(SMIT, {action: 'update', shareId: SHARE, step, ...extra});
  assert.strictEqual((await up('accept')).status, 'acknowledged');
  assert.strictEqual((await up('seen')).status, 'seen');
  assert.strictEqual((await up('complete', {reply: 'GA given, uneventful', note: 'done'})).status, 'completed');

  const s = db.peek(`${SHARES}/${SHARE}`);
  assert.strictEqual(s.status, 'completed');
  assert.strictEqual(plain(SHARE, s.reply), 'GA given, uneventful');
  assert.deepStrictEqual(s.history.map((h) => h.status), ['sent', 'acknowledged', 'seen', 'completed']);
  assert.strictEqual(plain(SHARE, s.history[3].note), 'done');
  assert.ok(s.history.slice(1).every((h) => h.by === SMIT));

  assert.deepStrictEqual(pushes.map((p) => p.notification.title), [
    'Dr. Smit Patil accepted your referral',
    'Dr. Smit Patil has seen your patient',
    'Dr. Smit Patil completed your referral',
  ]);
  assert.ok(pushes.every((p) => p.tokens[0] === 'tok-a'));
  assert.strictEqual(db.all('access_logs').filter((l) => l.action.startsWith('referral.')).length, 4);
});

test('a reply on its own keeps the status and needs text', async () => {
  seedPeople();
  await call(A, sendData());
  await rejects('invalid-argument', call(SMIT, {action: 'update', shareId: SHARE, step: 'reply'}));
  await call(SMIT, {action: 'update', shareId: SHARE, step: 'reply', reply: 'Booked for Monday'});
  const s = db.peek(`${SHARES}/${SHARE}`);
  assert.strictEqual(s.status, 'sent');
  assert.strictEqual(plain(SHARE, s.reply), 'Booked for Monday');
  await rejects('invalid-argument', call(SMIT, {action: 'update', shareId: SHARE, step: 'delete'}));
});

test('nobody else can touch it', async () => {
  seedPeople();
  await call(A, sendData());
  for (const uid of ['dr-mail', 'recep', 'super']) {
    for (const step of ['accept', 'withdraw']) {
      await rejects('permission-denied', call(uid, {action: 'update', shareId: SHARE, step}),
        `(${uid} ${step})`);
    }
  }
  await rejects('permission-denied', call(A, {action: 'update', shareId: SHARE, step: 'accept'}),
    '(the sender accepting their own referral)');
  await rejects('not-found', call(SMIT, {action: 'update', shareId: 'missing_share_1', step: 'accept'}));
  assert.strictEqual(db.peek(`${SHARES}/${SHARE}`).status, 'sent');
});

test('the sender withdraws: the patient is wiped and the files deleted', async () => {
  seedPeople();
  const path = `referral_uploads/${A}/${SHARE}/xray.png`;
  files.set(path, {size: 10, contentType: 'image/png'});
  await call(A, sendData({attachments: [{name: 'xray.png'}]}));
  pushes.length = 0;

  await call(A, {action: 'update', shareId: SHARE, step: 'withdraw'});
  const s = db.peek(`${SHARES}/${SHARE}`);
  assert.strictEqual(s.status, 'withdrawn');
  assert.deepStrictEqual(s.patient, {name: '', phone: '', gender: '', age: null});
  assert.strictEqual(s.findings, '');
  assert.strictEqual(s.question, '');
  assert.deepStrictEqual(s.attachments, []);
  assert.deepStrictEqual(deleted, [path]);
  assert.strictEqual(pushes[0].notification.title, 'Dr. Asha Rao withdrew a referral');

  // And it can't be reopened.
  await rejects('failed-precondition', call(SMIT, {action: 'update', shareId: SHARE, step: 'accept'}));
});

// ─────────────────────────────── attachmentUrl ───────────────────────────────

section('attachmentUrl');

test('a short-lived link for the two doctors only, and an audit entry', async () => {
  seedPeople();
  const path = `referral_uploads/${A}/${SHARE}/xray.png`;
  files.set(path, {size: 10, contentType: 'image/png'});
  await call(A, sendData({attachments: [{name: 'xray.png'}]}));

  const before = Date.now();
  const {url} = await call(SMIT, {action: 'attachmentUrl', shareId: SHARE, name: 'xray.png'});
  assert.ok(url.startsWith(`https://signed.test/${path}`));
  const expires = Number(new URL(url).searchParams.get('expires'));
  assert.ok(expires - before <= 10 * 60_000 + 1000, 'link lives too long');
  assert.ok(db.all('access_logs').some((l) =>
    l.action === 'referral.attachment.view' && l.actorUid === SMIT));

  await call(A, {action: 'attachmentUrl', shareId: SHARE, name: 'xray.png'});
  await rejects('permission-denied', call('dr-mail', {action: 'attachmentUrl', shareId: SHARE,
    name: 'xray.png'}));
  await rejects('not-found', call(SMIT, {action: 'attachmentUrl', shareId: SHARE, name: 'other.png'}));
  await rejects('invalid-argument', call(SMIT, {action: 'attachmentUrl', shareId: SHARE,
    name: '../x.png'}));
});

test('no link once withdrawn', async () => {
  seedPeople();
  files.set(`referral_uploads/${A}/${SHARE}/xray.png`, {size: 10, contentType: 'image/png'});
  await call(A, sendData({attachments: [{name: 'xray.png'}]}));
  await call(A, {action: 'update', shareId: SHARE, step: 'withdraw'});
  await rejects('not-found', call(SMIT, {action: 'attachmentUrl', shareId: SHARE, name: 'xray.png'}));
});

section('general');

test('signed-out callers and unknown actions are refused', async () => {
  await rejects('unauthenticated', referralNetwork.run({data: {action: 'send'}}));
  await rejects('invalid-argument', call(A, {action: 'nope'}));
});

test('the admin PERMS list still includes clinical.view (send relies on it)', () => {
  assert.ok(PERMS.includes('clinical.view'));
});

(async () => {
  for (const t of queue) await t();
  console.log(`\n${passed} passed`);
})();
