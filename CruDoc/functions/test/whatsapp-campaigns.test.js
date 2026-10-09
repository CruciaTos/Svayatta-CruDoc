/**
 * Unit tests for WhatsApp campaign planning and the campaign template.
 *
 * Run with:  npm run build && node test/whatsapp-campaigns.test.js
 *
 * planCampaign is a pure function, so the rules that decide who is messaged are
 * tested here without Firestore or Meta.
 */
const assert = require('assert');
const {
  planCampaign, CAMPAIGN_TEMPLATE_KEY,
} = require('../lib/whatsapp/campaigns');
const {
  CLINIC_CAMPAIGN, buildCreationPayload, templateFor,
} = require('../lib/whatsapp/templates');

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

const base = {
  campaignId: 'camp-1',
  message: 'Free dental check-up camp this Sunday, 10 AM to 2 PM.',
  clinicName: 'Smile Dental Clinic',
  clinicPhone: '9812345678',
  optedOut: new Set(),
};

// --------------------------------------------------------------- planning

test('plans one message per valid recipient with mapped params', () => {
  const plan = planCampaign({
    ...base,
    recipients: [
      {patientId: 'p1', phone: '+91 98765 43210', firstName: 'Rahul'},
      {patientId: 'p2', phone: '9876543211', firstName: 'Priya'},
    ],
  });

  assert.strictEqual(plan.messages.length, 2);
  const first = plan.messages[0];
  assert.strictEqual(first.phone, '919876543210');
  assert.strictEqual(first.patientId, 'p1');
  assert.strictEqual(first.dedupeKey, 'camp_camp-1_p1');
  assert.deepStrictEqual(first.params, {
    patientFirstName: 'Rahul',
    clinicName: 'Smile Dental Clinic',
    message: 'Free dental check-up camp this Sunday, 10 AM to 2 PM.',
    clinicPhone: '9812345678',
  });
});

test('skips an invalid or missing mobile number', () => {
  const plan = planCampaign({
    ...base,
    recipients: [
      {patientId: 'p1', phone: '1234567890', firstName: 'Rahul'}, // not a mobile
      {patientId: 'p2', phone: '', firstName: 'Priya'},
    ],
  });
  assert.strictEqual(plan.messages.length, 0);
  assert.strictEqual(plan.skipped.invalid_or_missing_phone, 2);
});

test('skips a recipient with no first name', () => {
  const plan = planCampaign({
    ...base,
    recipients: [{patientId: 'p1', phone: '9876543210', firstName: '  '}],
  });
  assert.strictEqual(plan.messages.length, 0);
  assert.strictEqual(plan.skipped.no_patient_name, 1);
});

test('drops opted-out patients by normalised phone', () => {
  const plan = planCampaign({
    ...base,
    optedOut: new Set(['919876543210']),
    recipients: [
      {patientId: 'p1', phone: '+91 98765 43210', firstName: 'Rahul'},
      {patientId: 'p2', phone: '9876543211', firstName: 'Priya'},
    ],
  });
  assert.strictEqual(plan.messages.length, 1);
  assert.strictEqual(plan.messages[0].patientId, 'p2');
  assert.strictEqual(plan.skipped.opted_out, 1);
});

test('sends a phone at most once within a campaign', () => {
  const plan = planCampaign({
    ...base,
    recipients: [
      {patientId: 'p1', phone: '9876543210', firstName: 'Rahul'},
      {patientId: 'p2', phone: '09876543210', firstName: 'Rahul (dup)'},
    ],
  });
  assert.strictEqual(plan.messages.length, 1);
  assert.strictEqual(plan.skipped.duplicate, 1);
});

test('falls back to the phone in the dedupe key when there is no patient id', () => {
  const plan = planCampaign({
    ...base,
    recipients: [{phone: '9876543210', firstName: 'Rahul'}],
  });
  assert.strictEqual(plan.messages[0].dedupeKey, 'camp_camp-1_919876543210');
  assert.strictEqual(plan.messages[0].patientId, null);
});

// --------------------------------------------------------------- template

test('the campaign template key matches the registry', () => {
  assert.strictEqual(CAMPAIGN_TEMPLATE_KEY, CLINIC_CAMPAIGN.key);
  assert.strictEqual(templateFor(CAMPAIGN_TEMPLATE_KEY).name, 'clinic_campaign_v1');
});

test('the campaign template is MARKETING and tells patients how to stop', () => {
  assert.strictEqual(CLINIC_CAMPAIGN.category, 'MARKETING');
  assert.match(CLINIC_CAMPAIGN.body, /Reply STOP/i);
});

test('a MARKETING template carries a stop-promotions button for Meta', () => {
  const payload = buildCreationPayload(CLINIC_CAMPAIGN);
  assert.strictEqual(payload.category, 'MARKETING');
  const buttons = payload.components.find((c) => c.type === 'BUTTONS');
  assert.ok(buttons, 'expected a BUTTONS component');
  assert.match(buttons.buttons[0].text, /stop/i);
});

console.log(`${passed} passed`);
