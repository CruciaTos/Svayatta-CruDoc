import test from 'node:test';
import assert from 'node:assert/strict';
import { planSummary } from './summary.js';

test('an empty plan gives only Implant plan and the nerve line not traced for both', () => {
  const text = planSummary({}, null, null);
  const expected = [
    'Implant plan',
    'Nerve canal: right not traced, left not traced',
  ].join('\n');
  assert.equal(text, expected);

  // Also test with empty nerves and implants arrays
  const text2 = planSummary({ nerves: { right: [], left: [] }, implants: [] }, [], []);
  assert.equal(text2, expected);
});

test('one implant with a known nerve gives the distance line with the right safety word', () => {
  // Nerve running along x, 14 mm below the implant top; implant 10 mm long, 4 mm wide.
  const nerve = [[-20, 0, -14], [0, 0, -14], [20, 0, -14]];
  const im = { top: [0, 0, 0], diameter: 4, length: 10, jaw: 'lower', tiltAP: 0, tiltLR: 0 };
  const plan = {
    nerves: { right: nerve, left: [] },
    implants: [im],
  };

  // clearance is ~0.8 mm -> 'danger' -> 'too close'
  const textDanger = planSummary(plan, null, null);
  assert.ok(textDanger.includes('Implant 1: 4.0 x 10.0 mm, lower jaw, tilt A-P 0°, L-R 0°'));
  assert.ok(textDanger.includes('Distance to the nerve canal 0.8 mm (too close)'));

  // Length 8 mm -> clearance ~2.8 mm -> 'safe'
  const planSafe = {
    nerves: { right: nerve, left: [] },
    implants: [{ ...im, length: 8 }],
  };
  const textSafe = planSummary(planSafe, null, null);
  assert.ok(textSafe.includes('Distance to the nerve canal 2.8 mm (safe)'));

  // No nerve traced -> Distance to the nerve canal: not checked (no canal traced)
  const planNoNerve = {
    nerves: { right: [], left: [] },
    implants: [im],
  };
  const textNoNerve = planSummary(planNoNerve, null, null);
  assert.ok(textNoNerve.includes('Distance to the nerve canal: not checked (no canal traced)'));
});

test('measures format bone width and height to canal / sinus', () => {
  const nerve = [[-20, 0, -14], [0, 0, -14], [20, 0, -14]];
  const imLower = { top: [0, 0, 0], diameter: 4, length: 10, jaw: 'lower', tiltAP: 5, tiltLR: 0 };
  const measureLower = {
    widthCrest: 6.8,
    widthMid: 7.1,
    heightToNerve: 12.0,
    heightToAir: null,
  };
  const planLower = {
    nerves: { right: nerve, left: [] },
    implants: [imLower],
  };
  const textLower = planSummary(planLower, [measureLower], null);
  assert.ok(
    textLower.includes('Bone width 6.8 mm near the crest, 7.1 mm at mid; height to the canal roof 12.0 mm')
  );

  const imUpper = { top: [0, 0, 0], diameter: 4, length: 10, jaw: 'upper', tiltAP: 0, tiltLR: 0 };
  const measureUpper = {
    widthCrest: 5.5,
    widthMid: 6.2,
    heightToNerve: null,
    heightToAir: 9.3,
  };
  const textUpper = planSummary({ nerves: {}, implants: [imUpper] }, [measureUpper], null);
  assert.ok(
    textUpper.includes('Bone width 5.5 mm near the crest, 6.2 mm at mid; height to the sinus floor 9.3 mm')
  );
});

test('two found boxes give the Found automatically line with both sizes', () => {
  const found = [
    { sizeMm: [4.1, 4.0, 9.8] },
    { sizeMm: [2.4, 2.4, 2.4] },
  ];
  const text = planSummary({}, null, found);
  assert.ok(
    text.includes('Found automatically: 2 metal or very dense objects (4.1 x 4.0 x 9.8 mm, 2.4 x 2.4 x 2.4 mm)')
  );

  // Single object singular
  const textSingle = planSummary({}, null, [{ sizeMm: [3.0, 3.0, 5.0] }]);
  assert.ok(textSingle.includes('Found automatically: 1 metal or very dense object (3.0 x 3.0 x 5.0 mm)'));
});
