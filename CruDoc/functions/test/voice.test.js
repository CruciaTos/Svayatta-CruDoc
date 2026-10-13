/**
 * The AI receptionist's booking API (src/voice/*).
 *
 * Run with:  npm run build && node test/voice.test.js
 *
 * Part 1 is the pure arithmetic: clinic-local dates, working hours, slots,
 * call cost. Part 2 drives the real `voiceApi` handler (API key, router,
 * routes) against an in-memory Firestore (test/fake-firestore.js), because
 * the emulator needs Java 21. What it can't show is two bookings racing at
 * the same instant; the slot lock is exercised as two bookings in a row.
 */
process.env.VOICE_BOT_API_KEY = 'test-voice-key';
process.env.PATIENT_KEK_PEPPER = 'test-pepper';
process.env.SARVAM_WEBHOOK_SECRET = 'test-webhook-secret';

const assert = require('assert');
const {FakeDb, installFakeFirestore, Timestamp} = require('./fake-firestore');

const db = new FakeDb();
installFakeFirestore(db);

const schedule = require('../lib/voice/schedule');
const {outcomeOf} = require('../lib/voice/callEnded');
const {indianNumberDigits, callDocId} = require('../lib/voice/context');
const {routeName, voiceApi} = require('../lib/voice');
const {
  deriveKek, wrapKey, encryptField, decryptField, phoneIndexOf,
} = require('../lib/crypto/patientCipher');

let passed = 0;
const tests = [];
function test(name, fn) {
  tests.push({name, fn});
}

// ====================================================== part 1: pure logic

const OPEN_ALL_WEEK = {
  hours: Object.fromEntries(['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat']
    .map((d) => [d, [['10:00', '13:00'], ['17:00', '21:00']]])),
  slotMinutes: 30,
};

test('clinic-local date and time are IST, not UTC', () => {
  // 20:00 UTC on 9 Oct is 01:30 IST on 10 Oct.
  const t = new Date('2026-10-09T20:00:00Z');
  assert.strictEqual(schedule.localDateOf(t), '2026-10-10');
  assert.strictEqual(schedule.localTimeOf(t), '01:30');
  assert.strictEqual(schedule.monthKeyOf(new Date('2026-10-31T19:00:00Z')), '202611');
});

test('dates: words, validation, weekday, spoken form', () => {
  const now = new Date('2026-10-09T08:00:00Z'); // Fri 9 Oct, 13:30 IST
  assert.strictEqual(schedule.resolveDate('tomorrow', now), '2026-10-10');
  assert.strictEqual(schedule.resolveDate('today', now), '2026-10-09');
  assert.strictEqual(schedule.resolveDate('2026-02-30', now), null);
  assert.strictEqual(schedule.resolveDate('10/10/2026', now), null);
  assert.strictEqual(schedule.weekdayName('2026-10-10'), 'Saturday');
  assert.strictEqual(schedule.spokenDate('2026-10-10'), 'Saturday 10 October');
  assert.strictEqual(schedule.spokenTime('17:30'), '5:30 pm');
  assert.strictEqual(schedule.spokenTime('00:15'), '12:15 am');
  assert.strictEqual(schedule.spokenTime('12:00'), '12:00 pm');
  assert.strictEqual(schedule.addDays('2026-12-31', 1), '2027-01-01');
  assert.strictEqual(schedule.daysBetween('2026-10-09', '2026-11-08'), 30);
});

test('hours fall back to Mon-Sat 9-6, and a bad day is closed, not open', () => {
  const d = schedule.scheduleFrom(undefined);
  assert.ok(d.defaulted);
  assert.deepStrictEqual(d.hours.sun, []);
  const s = schedule.scheduleFrom({hours: {mon: [['18:00', '10:00'], 'junk'], tue: [{open: '9:00', close: '1:00 PM'}]}});
  assert.deepStrictEqual(s.hours.mon, []);
  assert.deepStrictEqual(s.hours.tue, [['09:00', '13:00']]);
  assert.deepStrictEqual(s.hours.wed, []);
});

test('free slots: split hours, busy time, lead time and days off', () => {
  const s = schedule.scheduleFrom({...OPEN_ALL_WEEK, daysOff: ['2026-10-11']});
  const now = new Date('2026-10-10T05:00:00Z').getTime(); // 10:30 IST on the 10th
  const busy = [{
    start: new Date('2026-10-10T12:00:00Z').getTime(), // 17:30 IST
    end: new Date('2026-10-10T12:30:00Z').getTime(),
  }];
  const slots = schedule.freeSlots(s, '2026-10-10', busy, now);
  // 10:30 has started and 11:00 is inside the 30-minute lead.
  assert.deepStrictEqual(slots.slice(0, 3), ['11:30', '12:00', '12:30']);
  assert.ok(!slots.includes('17:30'), 'busy slot offered');
  assert.ok(slots.includes('17:00') && slots.includes('20:30'));
  assert.ok(!slots.includes('13:00') && !slots.includes('21:00'), 'slot ending after close');
  assert.deepStrictEqual(schedule.freeSlots(s, '2026-10-11', [], now), [], 'day off');
});

test('spread picks across the day, keeping first and last', () => {
  const items = Array.from({length: 13}, (_, i) => i);
  assert.deepStrictEqual(schedule.spread(items, 6), [0, 2, 5, 7, 10, 12]);
  assert.deepStrictEqual(schedule.spread([1, 2], 6), [1, 2]);
});

test('hours text groups days', () => {
  assert.strictEqual(
    schedule.hoursText(schedule.scheduleFrom(undefined)),
    'Mon to Sat 9:00 am to 6:00 pm. Sun closed.',
  );
});

test('call cost: per started minute plus per started 30 s', () => {
  assert.deepStrictEqual(schedule.callCost(45), {agentMinutes: 1, pulses: 2, costPaise: 340});
  assert.deepStrictEqual(schedule.callCost(70), {agentMinutes: 2, pulses: 3, costPaise: 660});
  assert.deepStrictEqual(schedule.callCost(240), {agentMinutes: 4, pulses: 8, costPaise: 1360});
  assert.deepStrictEqual(schedule.callCost(0), {agentMinutes: 0, pulses: 0, costPaise: 0});
});

test('numbers, ids, routes and outcomes', () => {
  assert.strictEqual(indianNumberDigits('080 6426 1740'), '918064261740');
  assert.strictEqual(indianNumberDigits('+918064261740'), '918064261740');
  assert.strictEqual(indianNumberDigits('12345'), null);
  assert.strictEqual(callDocId('20260828/8448d531-12:47:17-0f1a'), '20260828_8448d531-12:47:17-0f1a');
  assert.strictEqual(routeName('/my-appointments/'), 'my_appointments');
  assert.strictEqual(routeName('/voiceApi/session'), 'session');
  assert.strictEqual(outcomeOf('patient', [{type: 'callback'}, {type: 'booked'}]), 'booked');
  assert.strictEqual(outcomeOf('patient', []), 'info');
  assert.strictEqual(outcomeOf('over_quota', undefined), 'over_quota');
});

// ============================================ part 2: routes on a fake db

const CLINIC = 'clinicSharma';
const LINE = '918064261740';
const DOCTOR_PHONE = '919822011111';
const RAMESH = '919890155555';
const DEK = Buffer.alloc(32, 7);

function seed() {
  db.store.clear();
  db.write(`doctor_keys/${CLINIC}`, {wrappedKey: wrapKey(DEK, deriveKek(CLINIC, 'test-pepper'))});
  db.write(`clinics/${CLINIC}`, {name: 'Sharma Dental Clinic'});
  db.write(`users/${CLINIC}`, {
    displayName: 'Sharma',
    enabledModules: ['ai_agentic_calling'],
    aiReceptionist: OPEN_ALL_WEEK,
  });
  db.write(`voice_lines/${LINE}`, {
    doctorId: CLINIC, doctorIds: [CLINIC], publishedNumber: DOCTOR_PHONE, status: 'pending_test',
  });
  db.write('patients/p_ramesh', {
    doctorId: CLINIC,
    firstName: encryptField('Ramesh', DEK),
    lastName: encryptField('Patil', DEK),
    phone: encryptField('9890155555', DEK),
    phoneIndex: phoneIndexOf(RAMESH, DEK),
  });
}

/** Two days from now, clinic-local: always in the future, inside the 60-day window. */
const DAY = schedule.addDays(schedule.localDateOf(new Date()), 2);

function at(date, time) {
  const [h, m] = time.split(':').map(Number);
  const [y, mo, d] = date.split('-').map(Number);
  return Timestamp.fromDate(new Date(Date.UTC(y, mo - 1, d, h, m) - 330 * 60000));
}

async function call(route, body, {key = 'test-voice-key', query = {}} = {}) {
  let status = 0;
  let payload;
  const req = {
    method: 'POST',
    path: `/${route}`,
    url: `/${route}`,
    body: {line_id: LINE, interaction_id: 'int/001', ...body},
    query,
    headers: {'x-api-key': key, 'content-type': 'application/json'},
    get(h) {
      return this.headers[h.toLowerCase()];
    },
    header(h) {
      return this.get(h);
    },
  };
  const res = {
    statusCode: 200,
    headersSent: false,
    setHeader() {},
    getHeader() {},
    set() {
      return res;
    },
    status(c) {
      status = c;
      res.statusCode = c;
      return res;
    },
    json(b) {
      payload = b;
      res.headersSent = true;
      return res;
    },
    send(b) {
      payload = b;
      return res;
    },
    end() {},
    on() {},
  };
  await voiceApi(req, res);
  return {status, body: payload};
}

test('wrong API key is refused', async () => {
  seed();
  const r = await call('session', {caller: RAMESH}, {key: 'nope'});
  assert.strictEqual(r.status, 401);
});

test('the key sent twice (Auth plus a header) still works; a wrong one does not', async () => {
  seed();
  assert.strictEqual((await call('session', {caller: RAMESH}, {key: 'test-voice-key, test-voice-key'})).status, 200);
  assert.strictEqual((await call('session', {caller: RAMESH}, {key: 'nope, also-nope'})).status, 401);
});

test('the key may come in the body when the header is empty', async () => {
  seed();
  const ok = await call('session', {caller: RAMESH, api_key: 'test-voice-key'}, {key: ''});
  assert.strictEqual(ok.status, 200);
  assert.strictEqual(ok.body.api_key, undefined, 'key echoed back');
  assert.strictEqual((await call('session', {caller: RAMESH, api_key: 'wrong'}, {key: ''})).status, 401);
});

test('unknown line: polite refusal, not an error', async () => {
  seed();
  const r = await call('session', {line_id: '919999999999', caller: RAMESH});
  assert.strictEqual(r.status, 200);
  assert.strictEqual(r.body.ok, false);
  assert.strictEqual(r.body.code, 'unknown_line');
  assert.ok(r.body.say);
});

test("doctor's test call verifies the line", async () => {
  seed();
  const r = await call('session', {caller: '+91 98220 11111'});
  assert.strictEqual(r.body.mode, 'verify');
  assert.strictEqual(db.peek(`voice_lines/${LINE}`).status, 'active');
});

test('known caller is greeted by first name; plain caller is not', async () => {
  seed();
  db.write(`voice_lines/${LINE}`, {status: 'active'}, true);
  const r = await call('session', {caller: '+919890155555'});
  assert.strictEqual(r.body.mode, 'patient');
  assert.strictEqual(r.body.caller_first_name, 'Ramesh');
  assert.strictEqual(r.body.clinic_name, 'Sharma Dental Clinic');
  assert.strictEqual(r.body.ask_phone, false);
  assert.ok(r.body.say.includes('Ramesh ji'));
  const call1 = db.peek('voice_calls/int_001');
  assert.strictEqual(call1.doctorId, CLINIC);
  assert.strictEqual(decryptField(call1.callerPhone, DEK), '9890155555'.replace(/^/, '91'));

  const s = await call('session', {caller: '9000000001', interaction_id: 'int/002'});
  assert.strictEqual(s.body.caller_known, false);
  assert.strictEqual(s.body.caller_first_name, '');
});

test('names Super Admin stored encrypted are read, never spoken as ciphertext', async () => {
  seed();
  const crypto = require('crypto');
  const seal = (value) => {
    const key = crypto.createHash('sha256').update(`crudoc-doctor-profile::${CLINIC}`).digest();
    const iv = crypto.randomBytes(12);
    const c = crypto.createCipheriv('aes-256-gcm', key, iv);
    const body = Buffer.concat([c.update(value, 'utf8'), c.final(), c.getAuthTag()]);
    return `enc:v1:${iv.toString('base64')}.${body.toString('base64')}`;
  };
  db.store.delete(`clinics/${CLINIC}`);
  db.write(`users/${CLINIC}`, {displayName: null, name: seal('Anjali Rao'), clinicName: seal('Rao Clinic')}, true);
  db.write(`voice_lines/${LINE}`, {status: 'active'}, true);
  const r = await call('session', {caller: RAMESH});
  assert.strictEqual(r.body.clinic_name, 'Rao Clinic');
  assert.strictEqual(r.body.doctors[0].name, 'Dr. Anjali Rao');
  assert.ok(!JSON.stringify(r.body).includes('enc:v1:'));
});

test('hidden caller id (the doctor\'s number on an active line) asks for the phone', async () => {
  seed();
  db.write(`voice_lines/${LINE}`, {status: 'active'}, true);
  const r = await call('session', {caller: DOCTOR_PHONE});
  assert.strictEqual(r.body.mode, 'patient');
  assert.strictEqual(r.body.ask_phone, true);
  const b = await call('book', {caller: DOCTOR_PHONE, patient_name: 'Asha', date: DAY, time: '11:00'});
  assert.strictEqual(b.body.code, 'phone_required');
});

test('module off or line paused: paused mode', async () => {
  seed();
  db.write(`users/${CLINIC}`, {enabledModules: []}, true);
  assert.strictEqual((await call('session', {caller: RAMESH})).body.mode, 'paused');
  seed();
  db.write(`voice_lines/${LINE}`, {status: 'paused'}, true);
  assert.strictEqual((await call('session', {caller: RAMESH})).body.mode, 'paused');
});

test('over quota', async () => {
  seed();
  db.write(`voice_lines/${LINE}`, {status: 'active'}, true);
  const month = schedule.monthKeyOf(new Date());
  db.write(`voice_usage/${CLINIC}_${month}`, {calls: 20, includedCalls: 20, extraCalls: 0});
  assert.strictEqual((await call('session', {caller: RAMESH})).body.mode, 'over_quota');
  db.write(`voice_usage/${CLINIC}_${month}`, {extraCalls: 5}, true);
  assert.strictEqual((await call('session', {caller: RAMESH})).body.mode, 'patient');
});

test('slots skip an appointment made in the app', async () => {
  seed();
  db.write('appointments/app1', {
    doctorId: CLINIC, patientId: 'x', status: 'scheduled', isDeleted: false,
    scheduledStart: at(DAY, '17:30'), durationMinutes: 30,
  });
  const r = await call('slots', {caller: RAMESH, date: DAY});
  assert.strictEqual(r.body.ok, true);
  assert.ok(r.body.slots.length > 0 && r.body.slots.length <= 6);
  const all = schedule.freeSlots(schedule.scheduleFrom(OPEN_ALL_WEEK), DAY,
    [{start: at(DAY, '17:30').toMillis(), end: at(DAY, '18:00').toMillis()}], Date.now());
  assert.ok(!all.includes('17:30'));
  for (const s of r.body.slots) assert.ok(all.includes(s), `${s} is not free`);
});

test('closed day offers the next open day', async () => {
  seed();
  db.write(`users/${CLINIC}`, {aiReceptionist: {...OPEN_ALL_WEEK, daysOff: [DAY]}}, true);
  const r = await call('slots', {caller: RAMESH, date: DAY});
  assert.deepStrictEqual(r.body.slots, []);
  assert.strictEqual(r.body.next_free_date, schedule.addDays(DAY, 1));
  assert.ok(r.body.say_if_empty.includes('next free day'));
});

test('book: existing patient reused, encrypted, AI-tagged, slot locked, idempotent', async () => {
  seed();
  const r = await call('book', {caller: RAMESH, patient_name: 'Ramesh', date: DAY, time: '11:00', reason: 'tooth pain'});
  assert.strictEqual(r.body.ok, true, JSON.stringify(r.body));
  const appt = db.peek(`appointments/${r.body.appointment_id}`);
  assert.strictEqual(appt.patientId, 'p_ramesh');
  assert.strictEqual(appt.source, 'ai_receptionist');
  assert.strictEqual(appt.attendingDoctorUid, CLINIC);
  assert.strictEqual(appt.scheduledStart.toMillis(), at(DAY, '11:00').toMillis());
  assert.strictEqual(appt.treatmentType, 'tooth pain');
  assert.strictEqual(db.all('patients').length, 1, 'no duplicate patient');
  assert.ok(db.peek(`slot_locks/${CLINIC}_${at(DAY, '11:00').toMillis()}`));

  const again = await call('book', {caller: RAMESH, patient_name: 'Ramesh', date: DAY, time: '11:00'});
  assert.strictEqual(again.body.ok, true);
  assert.strictEqual(again.body.appointment_id, r.body.appointment_id);
  assert.strictEqual(db.all('appointments').length, 1, 'retry booked twice');
});

test('book: a family member on the same phone is a new, encrypted patient', async () => {
  seed();
  const r = await call('book', {caller: RAMESH, patient_name: 'Sunita Patil', date: DAY, time: '11:30'});
  assert.strictEqual(r.body.ok, true);
  const created = db.all('patients').find((p) => p.id !== 'p_ramesh');
  assert.ok(created, 'patient not created');
  assert.ok(created.firstName.startsWith('enc:v1:'), 'name stored readable');
  assert.strictEqual(decryptField(created.firstName, DEK), 'Sunita');
  assert.strictEqual(decryptField(created.lastName, DEK), 'Patil');
  assert.strictEqual(decryptField(created.phone, DEK), '9890155555');
  assert.strictEqual(created.phoneIndex, phoneIndexOf(RAMESH, DEK));
  assert.strictEqual(created.doctorId, CLINIC);
});

test('book: second caller for the same slot is refused with alternatives', async () => {
  seed();
  const a = await call('book', {caller: RAMESH, patient_name: 'Ramesh', date: DAY, time: '12:00', interaction_id: 'int/A'});
  assert.strictEqual(a.body.ok, true);
  const b = await call('book', {caller: '9000000002', patient_name: 'Meera', date: DAY, time: '12:00', interaction_id: 'int/B'});
  assert.strictEqual(b.body.ok, false);
  assert.strictEqual(b.body.code, 'slot_taken');
  assert.ok(b.body.alternatives.length > 0 && !b.body.alternatives.includes('12:00'));
  assert.ok(b.body.say.includes('12:00 pm'));
});

test('book: an overlapping app appointment blocks the slot', async () => {
  seed();
  db.write('appointments/app2', {
    doctorId: CLINIC, patientId: 'x', status: 'scheduled', isDeleted: false,
    scheduledStart: at(DAY, '18:15'), durationMinutes: 30,
  });
  const r = await call('book', {caller: RAMESH, patient_name: 'Ramesh', date: DAY, time: '18:00'});
  assert.strictEqual(r.body.code, 'slot_taken');
});

test('book: outside hours, closed day, past, bad input', async () => {
  seed();
  const out = await call('book', {caller: RAMESH, patient_name: 'Ramesh', date: DAY, time: '14:00'});
  assert.strictEqual(out.body.code, 'outside_hours');
  const late = await call('book', {caller: RAMESH, patient_name: 'Ramesh', date: DAY, time: '20:45'});
  assert.strictEqual(late.body.code, 'outside_hours', 'runs past closing');
  const past = await call('book', {caller: RAMESH, patient_name: 'Ramesh', date: '2020-01-01', time: '11:00'});
  assert.strictEqual(past.body.code, 'in_past');
  const noName = await call('book', {caller: RAMESH, date: DAY, time: '11:00'});
  assert.strictEqual(noName.body.code, 'name_required');
  const badTime = await call('book', {caller: RAMESH, patient_name: 'R', date: DAY, time: 'evening'});
  assert.strictEqual(badTime.body.code, 'invalid_time');
  db.write(`users/${CLINIC}`, {aiReceptionist: {...OPEN_ALL_WEEK, daysOff: [DAY]}}, true);
  const off = await call('book', {caller: RAMESH, patient_name: 'Ramesh', date: DAY, time: '11:00'});
  assert.strictEqual(off.body.code, 'day_off');
});

test('my appointments, cancel and reschedule work only for the caller', async () => {
  seed();
  const booked = await call('book', {caller: RAMESH, patient_name: 'Ramesh', date: DAY, time: '17:00'});
  const id = booked.body.appointment_id;

  const mine = await call('my_appointments', {caller: RAMESH});
  assert.strictEqual(mine.body.appointments.length, 1);
  assert.strictEqual(mine.body.appointments[0].time, '17:00');

  // Someone else can't see, move or cancel it, and learns nothing.
  const other = await call('cancel', {caller: '9000000003', appointment_id: id});
  assert.strictEqual(other.body.code, 'not_found');
  const otherMove = await call('reschedule', {caller: '9000000003', appointment_id: id, date: DAY, time: '19:00'});
  assert.strictEqual(otherMove.body.code, 'not_found');
  assert.strictEqual(db.peek(`appointments/${id}`).status, 'scheduled');

  const moved = await call('reschedule', {caller: RAMESH, appointment_id: id, date: DAY, time: '19:00'});
  assert.strictEqual(moved.body.ok, true, JSON.stringify(moved.body));
  assert.strictEqual(db.peek(`appointments/${id}`).scheduledStart.toMillis(), at(DAY, '19:00').toMillis());
  assert.ok(!db.peek(`slot_locks/${CLINIC}_${at(DAY, '17:00').toMillis()}`), 'old lock kept');
  assert.ok(db.peek(`slot_locks/${CLINIC}_${at(DAY, '19:00').toMillis()}`), 'new lock missing');

  const cancelled = await call('cancel', {caller: RAMESH, appointment_id: id, reason: 'travelling'});
  assert.strictEqual(cancelled.body.ok, true);
  const a = db.peek(`appointments/${id}`);
  assert.strictEqual(a.status, 'cancelled');
  assert.strictEqual(a.isDeleted, true);
  assert.ok(!db.peek(`slot_locks/${CLINIC}_${at(DAY, '19:00').toMillis()}`), 'lock not released');

  // The slot is free again for someone else.
  const rebook = await call('book', {caller: '9000000004', patient_name: 'Meera', date: DAY, time: '19:00', interaction_id: 'int/C'});
  assert.strictEqual(rebook.body.ok, true);
});

test('another clinic\'s appointment id is not found', async () => {
  seed();
  db.write('appointments/foreign', {
    doctorId: 'otherClinic', patientId: 'p_ramesh', status: 'scheduled',
    scheduledStart: at(DAY, '11:00'),
  });
  const r = await call('cancel', {caller: RAMESH, appointment_id: 'foreign'});
  assert.strictEqual(r.body.code, 'not_found');
});

test('callback: saved encrypted, a repeat caller adds to the same card', async () => {
  seed();
  const first = await call('callback', {caller: RAMESH, name: 'Ramesh', note: 'About my bill'});
  assert.strictEqual(first.body.ok, true);
  assert.strictEqual(first.body.merged, false);
  const second = await call('callback', {caller: RAMESH, name: 'Ramesh', note: 'Also the X-ray', interaction_id: 'int/009'});
  assert.strictEqual(second.body.merged, true);
  const cards = db.all('voice_callbacks');
  assert.strictEqual(cards.length, 1);
  assert.strictEqual(decryptField(cards[0].note, DEK), 'About my bill\nAlso the X-ray');
  assert.strictEqual(cards[0].messageCount, 2);
  assert.ok(cards[0].name.startsWith('enc:v1:'));

  db.write(`voice_lines/${LINE}`, {status: 'active'}, true);
  const s = await call('session', {caller: RAMESH, interaction_id: 'int/010'});
  assert.strictEqual(s.body.has_open_message, true);
});

test('call-ended: needs the token, counts once, derives the outcome', async () => {
  seed();
  await call('book', {caller: RAMESH, patient_name: 'Ramesh', date: DAY, time: '12:30', interaction_id: 'int/E'});
  const payload = {
    interaction_id: 'int/E',
    agent_phone_number: '+918064261740',
    user_phone_number: '+919890155555',
    duration: 70,
    start_datetime: new Date().toISOString(),
  };
  const denied = await call('call-ended', payload, {key: '', query: {token: 'wrong'}});
  assert.strictEqual(denied.status, 401);

  const ok = await call('call-ended', payload, {key: '', query: {token: 'test-webhook-secret'}});
  assert.strictEqual(ok.body.counted, true);
  const dup = await call('call-ended', payload, {key: '', query: {token: 'test-webhook-secret'}});
  assert.strictEqual(dup.body.duplicate, true);

  const c = db.peek('voice_calls/int_E');
  assert.strictEqual(c.outcome, 'booked');
  assert.strictEqual(c.costPaise, 660);
  const u = db.peek(`voice_usage/${CLINIC}_${schedule.monthKeyOf(new Date())}`);
  assert.strictEqual(u.calls, 1);
  assert.strictEqual(u.costPaise, 660);
  assert.strictEqual(u.includedCalls, 20);
  assert.strictEqual(u.outcomes.booked, 1);
});

(async () => {
  for (const {name, fn} of tests) {
    try {
      await fn();
      passed++;
    } catch (err) {
      console.error(`FAIL  ${name}`);
      console.error(err);
      process.exitCode = 1;
    }
  }
  console.log(`${passed}/${tests.length} passed`);
})();
