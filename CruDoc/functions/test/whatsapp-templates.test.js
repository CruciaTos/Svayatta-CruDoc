/**
 * Unit tests for the WhatsApp reminder: template shape, IST formatting, and
 * the STOP/START reply parser.
 *
 * Run with:  npm run build && node test/whatsapp-templates.test.js
 *
 * These pin three defects from the previous implementation:
 *
 *  1. Times were formatted with `toLocaleDateString("en-US", ...)` and no
 *     `timeZone`. Cloud Functions run on UTC, so an 11:00 AM IST appointment
 *     was announced to the patient as 5:30 AM. A test written in IST would
 *     pass while production was wrong, so these assert against fixed UTC
 *     instants.
 *
 *  2. Parameters were positional from the call site onwards. The clinic name
 *     and the doctor name could be swapped without anything failing: the
 *     patient simply received a plausible message with the wrong words in it.
 *
 *  3. A missing parameter was sent as an empty string, so the patient got
 *     "your appointment at  with ".
 */
const assert = require('assert');
const {
  APPOINTMENT_REMINDER, TEMPLATES, TEMPLATE_KEYS, templateFor,
  toPositionalParams, buildMessageComponents, buildCreationPayload,
  sanitiseParam,
} = require('../lib/whatsapp/templates');
const {
  formatDate, formatTime, istDayRange, firstNameOf, fullNameOf, normalisePhone,
} = require('../lib/whatsapp/format');
const {classifyReply} = require('../lib/whatsapp/optouts');

let passed = 0;

function test(name, fn) {
  try {
    fn();
    passed++;
  } catch (err) {
    console.error(`FAIL  ${name}`);
    console.error('      ' + err.message);
    process.exitCode = 1;
  }
}

// ----------------------------------------------------------- template shape

test('the body numbers its variables 1..n in order', () => {
  for (const key of TEMPLATE_KEYS) {
    const spec = TEMPLATES[key];
    const found = [...spec.body.matchAll(/\{\{(\d+)\}\}/g)].map((m) => Number(m[1]));
    const expected = spec.paramOrder.map((_, i) => i + 1);
    assert.deepStrictEqual(found, expected, `${key}: numbering does not match paramOrder`);
  }
});

test('no body starts or ends with a variable, which Meta rejects', () => {
  for (const key of TEMPLATE_KEYS) {
    const body = TEMPLATES[key].body.trim();
    assert.ok(!body.startsWith('{{'), `${key}: starts with a variable`);
    assert.ok(!body.endsWith('}}'), `${key}: ends with a variable`);
  }
});

test('no two variables sit next to each other', () => {
  for (const key of TEMPLATE_KEYS) {
    assert.ok(
      !/\{\{\d+\}\}\s*\{\{\d+\}\}/.test(TEMPLATES[key].body),
      `${key}: has adjacent variables`,
    );
  }
});

test('every parameter has an example for Meta review', () => {
  for (const key of TEMPLATE_KEYS) {
    const spec = TEMPLATES[key];
    for (const name of spec.paramOrder) {
      assert.ok(spec.example[name], `${key}: no example for ${name}`);
    }
  }
});

test('the reminder tells the patient how to stop', () => {
  assert.match(APPOINTMENT_REMINDER.body, /Reply STOP/i);
});

test('the reminder carries no medical information', () => {
  // A reminder naming a procedure would disclose health data to anyone who
  // glances at the phone, and reads as non-utility to Meta.
  const forbidden = /diagnos|treatment|procedure|medicine|surgery|root canal|therapy/i;
  assert.ok(!forbidden.test(APPOINTMENT_REMINDER.body));
  assert.ok(!APPOINTMENT_REMINDER.paramOrder.some((p) => forbidden.test(p)));
});

test('the parameter order matches the registered template', () => {
  // Patient, clinic, doctor, date, time, clinic phone. Swapping clinic and
  // doctor here would send a message that still reads correctly but is wrong.
  assert.deepStrictEqual(APPOINTMENT_REMINDER.paramOrder, [
    'patientFirstName', 'clinicName', 'doctorName', 'date', 'time', 'clinicPhone',
  ]);
  assert.strictEqual(APPOINTMENT_REMINDER.name, 'appointment_reminder_v1');
  assert.strictEqual(APPOINTMENT_REMINDER.language, 'en');
  assert.strictEqual(APPOINTMENT_REMINDER.category, 'UTILITY');
});

// ------------------------------------------------------- parameter mapping

test('named parameters map to the declared positional order', () => {
  const ordered = toPositionalParams(APPOINTMENT_REMINDER, {
    doctorName: 'Dr. Mehta',
    clinicPhone: '9812345678',
    patientFirstName: 'Rahul',
    time: '11:00 AM',
    clinicName: 'Smile Dental Clinic',
    date: 'Tue, 6 Oct',
  });

  assert.deepStrictEqual(ordered, [
    'Rahul', 'Smile Dental Clinic', 'Dr. Mehta', 'Tue, 6 Oct', '11:00 AM', '9812345678',
  ]);
});

test('a missing parameter is refused rather than sent blank', () => {
  assert.throws(
    () => toPositionalParams(APPOINTMENT_REMINDER, {
      patientFirstName: 'Rahul',
      clinicName: 'Smile Dental Clinic',
      doctorName: 'Dr. Mehta',
      date: 'Tue, 6 Oct',
      time: '11:00 AM',
      // clinicPhone absent
    }),
    /missing: clinicPhone/,
  );
});

test('an unknown template key throws', () => {
  assert.throws(() => templateFor('nope'), /Unknown WhatsApp template/);
});

test('newlines and tabs are stripped from parameters', () => {
  assert.strictEqual(sanitiseParam('Smile\nDental\tClinic'), 'Smile Dental Clinic');
  assert.strictEqual(sanitiseParam(null), '');
});

test('the send payload is a single body component', () => {
  const c = buildMessageComponents(APPOINTMENT_REMINDER, APPOINTMENT_REMINDER.example);
  assert.strictEqual(c.length, 1);
  assert.strictEqual(c[0].type, 'body');
  assert.strictEqual(c[0].parameters.length, 6);
  assert.strictEqual(c[0].parameters[0].text, 'Rahul');
});

test('the creation payload matches what was registered with Meta', () => {
  const payload = buildCreationPayload(APPOINTMENT_REMINDER);
  assert.strictEqual(payload.name, 'appointment_reminder_v1');
  assert.strictEqual(payload.category, 'UTILITY');
  const body = payload.components.find((c) => c.type === 'BODY');
  assert.strictEqual(body.text, APPOINTMENT_REMINDER.body);
  assert.strictEqual(body.example.body_text[0].length, 6);
});

// ------------------------------------------------------- IST formatting

test('an IST morning appointment is not rendered in UTC', () => {
  // 05:30 UTC is 11:00 IST. The old code printed 5:30 AM to the patient.
  const instant = new Date('2026-10-06T05:30:00Z');
  assert.strictEqual(formatTime(instant), '11:00 AM');
  assert.strictEqual(formatDate(instant), 'Tue, 6 Oct');
});

test('an evening appointment stays on the right IST date', () => {
  // 20:00 IST on 6 Oct is 14:30 UTC the same day.
  const instant = new Date('2026-10-06T14:30:00Z');
  assert.strictEqual(formatTime(instant), '8:00 PM');
  assert.strictEqual(formatDate(instant), 'Tue, 6 Oct');
});

test('an appointment after 18:30 UTC belongs to the next IST day', () => {
  // 19:00 UTC on 5 Oct is 00:30 IST on 6 Oct. A UTC-based day boundary would
  // put this on the wrong day and remind the patient a day early.
  const instant = new Date('2026-10-05T19:00:00Z');
  assert.strictEqual(formatDate(instant), 'Tue, 6 Oct');
  assert.strictEqual(formatTime(instant), '12:30 AM');
});

test('tomorrow spans one IST day, offset from UTC by 5.5 hours', () => {
  // 18:00 IST on 5 Oct == 12:30 UTC. Tomorrow is all of 6 Oct IST.
  const now = new Date('2026-10-05T12:30:00Z');
  const {start, end} = istDayRange(now, 1);
  assert.strictEqual(start.toISOString(), '2026-10-05T18:30:00.000Z');
  assert.strictEqual(end.toISOString(), '2026-10-06T18:30:00.000Z');
  assert.strictEqual(end - start, 24 * 60 * 60 * 1000);
});

test('the day range holds just before the IST midnight boundary', () => {
  // 23:50 IST on 5 Oct == 18:20 UTC. Tomorrow must still be 6 Oct.
  const now = new Date('2026-10-05T18:20:00Z');
  const {start} = istDayRange(now, 1);
  assert.strictEqual(start.toISOString(), '2026-10-05T18:30:00.000Z');
});

// -------------------------------------------------------------- recipients

test('names come from either record shape', () => {
  assert.strictEqual(firstNameOf({firstName: 'Rahul', lastName: 'Sharma'}), 'Rahul');
  assert.strictEqual(firstNameOf({fullName: 'Rahul Sharma'}), 'Rahul');
  assert.strictEqual(fullNameOf({firstName: 'Rahul', lastName: 'Sharma'}), 'Rahul Sharma');
  assert.strictEqual(fullNameOf({fullName: 'Rahul Sharma'}), 'Rahul Sharma');
  assert.strictEqual(firstNameOf({}), '');
});

test('phone numbers normalise to digits with a country code', () => {
  assert.strictEqual(normalisePhone('+91 98765 43210'), '919876543210');
  assert.strictEqual(normalisePhone('09876543210'), '919876543210');
  assert.strictEqual(normalisePhone('9876543210'), '919876543210');
});

test('numbers that cannot receive WhatsApp are refused', () => {
  assert.strictEqual(normalisePhone('1234567890'), null, 'Indian mobiles start 6-9');
  assert.strictEqual(normalisePhone('+91 22 2345 6789'), null, 'landline');
  assert.strictEqual(normalisePhone('12345'), null);
  assert.strictEqual(normalisePhone(''), null);
  assert.strictEqual(normalisePhone(null), null);
});

// ------------------------------------------------------------ STOP / START

test('stop words opt the patient out', () => {
  for (const t of ['STOP', 'stop', ' Stop. ', 'UNSUBSCRIBE', 'cancel', 'band', 'बंद']) {
    assert.strictEqual(classifyReply(t), 'stop', `"${t}" should stop`);
  }
});

test('start words opt the patient back in', () => {
  for (const t of ['START', 'start', 'subscribe', 'resume']) {
    assert.strictEqual(classifyReply(t), 'start', `"${t}" should start`);
  }
});

test('a sentence that merely mentions stopping is left for a human', () => {
  assert.strictEqual(
    classifyReply('I could not stop by yesterday, can I come on Thursday instead'),
    'other',
  );
  assert.strictEqual(classifyReply('thanks, see you then'), 'other');
  assert.strictEqual(classifyReply(''), 'other');
  assert.strictEqual(classifyReply(null), 'other');
});

test('a short polite stop still counts', () => {
  assert.strictEqual(classifyReply('please stop'), 'stop');
});

console.log(`${passed} passed`);
