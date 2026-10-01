/**
 * Unit tests for the pure time/slot logic behind the voice-receptionist
 * appointment endpoints.
 *
 * Run with:  npm run build && node test/appointments.test.js
 *
 * The timezone case here is a regression test for a real defect: the
 * original createAppointment built its Timestamp with
 * `new Date("2026-10-03T10:30:00")`. A date-time string with no offset is
 * interpreted in the *runtime's* zone, which is UTC on Cloud Functions,
 * while the Flutter app renders the stored Timestamp in device-local time.
 * Every AI-booked appointment therefore showed up 5.5 hours late for an
 * IST clinic. These assertions pin the corrected behaviour.
 */
const assert = require('assert');
const {__internal} = require('../lib/appointments');

const {normaliseTime, instantFromClinicLocal, computeOpenSlots} = __internal;

const IST = 330; // +05:30 in minutes
let passed = 0;

function test(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`  ok  ${name}`);
  } catch (err) {
    console.error(`FAIL  ${name}`);
    console.error(`      ${err.message}`);
    process.exitCode = 1;
  }
}

// ------------------------------------------------------------------
console.log('normaliseTime');
// ------------------------------------------------------------------

test('passes through 24-hour time', () => {
  assert.strictEqual(normaliseTime('14:30'), '14:30');
});

test('zero-pads a single-digit hour', () => {
  assert.strictEqual(normaliseTime('9:05'), '09:05');
});

test('converts PM to 24-hour', () => {
  assert.strictEqual(normaliseTime('2:30 PM'), '14:30');
  assert.strictEqual(normaliseTime('2:30PM'), '14:30');
});

test('handles the midnight and noon edge cases', () => {
  assert.strictEqual(normaliseTime('12:00 AM'), '00:00');
  assert.strictEqual(normaliseTime('12:00 PM'), '12:00');
  assert.strictEqual(normaliseTime('12:30 AM'), '00:30');
});

// ------------------------------------------------------------------
console.log('instantFromClinicLocal');
// ------------------------------------------------------------------

test('resolves an IST wall-clock time to the right absolute instant', () => {
  const instant = instantFromClinicLocal('2026-10-03', '10:30', IST);
  assert.strictEqual(instant.toISOString(), '2026-10-03T05:00:00.000Z');
});

test('REGRESSION: does not treat clinic-local time as UTC', () => {
  // The old behaviour. If this ever matches again, appointments are
  // being stored 5.5h late for an IST clinic.
  const buggy = new Date('2026-10-03T10:30:00Z');
  const fixed = instantFromClinicLocal('2026-10-03', '10:30', IST);
  assert.notStrictEqual(fixed.toISOString(), buggy.toISOString());
  assert.strictEqual(fixed.getTime(), buggy.getTime() - IST * 60000);
});

test('a zero offset means the wall clock already is UTC', () => {
  const instant = instantFromClinicLocal('2026-10-03', '10:30', 0);
  assert.strictEqual(instant.toISOString(), '2026-10-03T10:30:00.000Z');
});

test('accepts 12-hour input', () => {
  const instant = instantFromClinicLocal('2026-10-03', '2:30 PM', IST);
  assert.strictEqual(instant.toISOString(), '2026-10-03T09:00:00.000Z');
});

test('crossing midnight backwards still lands on the right day', () => {
  // 00:30 IST on the 3rd is 19:00 UTC on the 2nd.
  const instant = instantFromClinicLocal('2026-10-03', '00:30', IST);
  assert.strictEqual(instant.toISOString(), '2026-10-02T19:00:00.000Z');
});

test('rejects a malformed date', () => {
  assert.throws(() => instantFromClinicLocal('03-10-2026', '10:30', IST), /Invalid date/);
});

test('rejects a malformed time', () => {
  assert.throws(() => instantFromClinicLocal('2026-10-03', 'half nine', IST), /Invalid time/);
});

// ------------------------------------------------------------------
console.log('computeOpenSlots');
// ------------------------------------------------------------------

const dayOpen = instantFromClinicLocal('2026-10-03', '09:00', IST);
const dayClose = instantFromClinicLocal('2026-10-03', '18:00', IST);
// A "now" well before the day starts, so nothing is filtered as past.
const beforeTheDay = instantFromClinicLocal('2026-10-03', '06:00', IST).getTime();

function istInterval(startTime, endTime) {
  return {
    start: instantFromClinicLocal('2026-10-03', startTime, IST).getTime(),
    end: instantFromClinicLocal('2026-10-03', endTime, IST).getTime(),
  };
}

test('an empty day yields one slot per grid step', () => {
  const slots = computeOpenSlots(dayOpen, dayClose, 30, [], beforeTheDay);
  assert.strictEqual(slots.length, 18); // 09:00-18:00 in 30-min steps
  assert.strictEqual(slots[0].start, '2026-10-03T03:30:00.000Z'); // 09:00 IST
  assert.strictEqual(slots[17].end, '2026-10-03T12:30:00.000Z'); // 18:00 IST
});

test('a booked slot is removed', () => {
  const busy = [istInterval('10:00', '10:30')];
  const slots = computeOpenSlots(dayOpen, dayClose, 30, busy, beforeTheDay);
  assert.strictEqual(slots.length, 17);
  const starts = slots.map((s) => s.start);
  assert.ok(!starts.includes('2026-10-03T04:30:00.000Z')); // 10:00 IST is gone
});

test('an appointment starting before opening still blocks the first slot', () => {
  const busy = [istInterval('08:45', '09:15')];
  const slots = computeOpenSlots(dayOpen, dayClose, 30, busy, beforeTheDay);
  assert.strictEqual(slots.length, 17);
  assert.strictEqual(slots[0].start, '2026-10-03T04:00:00.000Z'); // 09:30 IST
});

test('a long appointment blocks every slot it spans', () => {
  const busy = [istInterval('10:00', '12:00')];
  const slots = computeOpenSlots(dayOpen, dayClose, 30, busy, beforeTheDay);
  assert.strictEqual(slots.length, 14); // 18 - 4
});

test('slots that have already started are not offered', () => {
  const now = instantFromClinicLocal('2026-10-03', '11:00', IST).getTime();
  const slots = computeOpenSlots(dayOpen, dayClose, 30, [], now);
  // 09:00, 09:30, 10:00, 10:30 and 11:00 have all begun.
  assert.strictEqual(slots.length, 13);
  assert.strictEqual(slots[0].start, '2026-10-03T06:00:00.000Z'); // 11:30 IST
});

test('a slot that would overrun closing is not offered', () => {
  const close = instantFromClinicLocal('2026-10-03', '09:50', IST);
  const slots = computeOpenSlots(dayOpen, close, 30, [], beforeTheDay);
  assert.strictEqual(slots.length, 1); // only 09:00-09:30 fits
});

test('a back-to-back appointment does not block the next slot', () => {
  // 10:00-10:30 busy must leave 10:30 free -- the boundary is exclusive.
  const busy = [istInterval('10:00', '10:30')];
  const slots = computeOpenSlots(dayOpen, dayClose, 30, busy, beforeTheDay);
  const starts = slots.map((s) => s.start);
  assert.ok(starts.includes('2026-10-03T05:00:00.000Z')); // 10:30 IST present
});

test('a non-30-minute grid is respected', () => {
  const slots = computeOpenSlots(dayOpen, dayClose, 20, [], beforeTheDay);
  assert.strictEqual(slots.length, 27); // 540 minutes / 20
});

test('a fully booked day yields nothing', () => {
  const busy = [istInterval('09:00', '18:00')];
  const slots = computeOpenSlots(dayOpen, dayClose, 30, busy, beforeTheDay);
  assert.deepStrictEqual(slots, []);
});

console.log(`\n${passed} passed${process.exitCode ? ' (with failures)' : ''}`);
