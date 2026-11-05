/**
 * Tests for paying for a plan by UPI through YouPI (src/plan-payments.ts).
 *
 * Run with:  npm run build && node test/plan-payments.test.js
 *
 * The real planPayments and youpiWebhook handlers run against the in-memory
 * Firestore fake and a fake YouPI gateway (global fetch). The point of the
 * module is that nothing but a verified payment unlocks a plan, so most of
 * these are the ways it must not.
 */
process.env.YOUPI_BASE_URL = 'https://pay.test';
process.env.YOUPI_MERCHANT_ID = 'merchant-1';
process.env.YOUPI_WEBHOOK_SECRET = 'whsec-test';
process.env.PATIENT_KEK_PEPPER = 'test-pepper-not-the-real-one';

const assert = require('assert');
const crypto = require('crypto');
const {NestedFakeDb, installNestedFake} = require('./fake-firestore-nested');

const db = new NestedFakeDb();
installNestedFake(db);

// ---- fake YouPI ------------------------------------------------------------
// payments: paymentId -> what GET /api/v1/payments/{id} answers.
const gateway = {payments: new Map(), calls: [], createStatus: 201, down: false, echo: null};
let nextPayment = 1;
global.fetch = async (url, init = {}) => {
  const method = init.method || 'GET';
  gateway.calls.push({url, method, headers: init.headers || {}, body: init.body ? JSON.parse(init.body) : null});
  if (gateway.down) throw new Error('connect ECONNREFUSED');
  const json = (status, body) => ({ok: status >= 200 && status < 300, status, json: async () => body});
  const path = url.replace('https://pay.test', '');
  if (method === 'POST' && path === '/api/v1/payments') {
    if (gateway.createStatus !== 201) return json(gateway.createStatus, {error: 'NOPE'});
    const req = JSON.parse(init.body);
    const paymentId = `pay-${nextPayment++}`;
    const amountPaise = String(Math.round(Number(req.amount) * 100));
    gateway.payments.set(paymentId, {paymentId, orderId: req.orderId, amountPaise, status: 'ACTIVE'});
    return json(201, {
      paymentId, orderId: req.orderId, amount: req.amount, amountPaise, currency: 'INR',
      status: 'INITIATED', queuePosition: 0, checkoutUrl: `/checkout/${paymentId}`,
      ...(gateway.echo || {}),
    });
  }
  let m = path.match(/^\/api\/v1\/payments\/(.+)$/);
  if (method === 'GET' && m) {
    const p = gateway.payments.get(decodeURIComponent(m[1]));
    return p ? json(200, {...p, verificationLevel: 1}) : json(404, {error: 'NOT_FOUND'});
  }
  m = path.match(/^\/api\/v1\/checkout\/(.+)\/cancel$/);
  if (method === 'POST' && m) {
    const p = gateway.payments.get(decodeURIComponent(m[1]));
    if (p) p.status = 'CANCELLED';
    return json(200, {success: true, status: 'CANCELLED'});
  }
  return json(404, {});
};

const {
  planPayments, youpiWebhook, priceModules, rupees, normaliseUtr, checkoutUrlFrom,
  verifyGatewaySignature, PLAN_PAYMENTS, STARTS_PER_HOUR, mockPaymentsEnabled,
} = require('../lib/plan-payments');
const subscription = require('../lib/subscription');

// ---- harness ---------------------------------------------------------------
let passed = 0;
const queue = [];
function test(name, fn) {
  queue.push(async () => {
    db.store.clear();
    gateway.payments.clear();
    gateway.calls.length = 0;
    gateway.createStatus = 201;
    gateway.down = false;
    gateway.echo = null;
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
async function rejects(code, promise) {
  try {
    await promise;
  } catch (err) {
    assert.strictEqual(err.code, code, `expected ${code}, got ${err.code} (${err.message})`);
    return err;
  }
  assert.fail(`expected ${code}, but it succeeded`);
}

const DR = 'dr-pay';
const call = (data, uid = DR) => planPayments.run({auth: {uid, token: {name: 'Dr Pay'}}, data});

/** Delivers [event] to youpiWebhook, signed with [secret] unless [signature] is given. */
async function deliver(event, {secret = 'whsec-test', signature} = {}) {
  const raw = Buffer.from(JSON.stringify(event));
  const sig = signature ?? `sha256=${crypto.createHmac('sha256', secret).update(raw).digest('hex')}`;
  const headers = {'x-gateway-signature': sig, 'x-gateway-delivery-id': 'd-1'};
  const req = {method: 'POST', rawBody: raw, body: event, get: (h) => headers[h.toLowerCase()]};
  let status = 200;
  let body = null;
  const res = {
    status(c) {
      status = c;
      return res;
    },
    json(b) {
      body = b;
      return res;
    },
    send(b) {
      body = b;
      return res;
    },
  };
  await youpiWebhook(req, res);
  return {status, body};
}

/** Starts a checkout for revenue + AI scribe (₹3,498) and returns it. */
async function started() {
  db.seed(`users/${DR}`, {name: 'Dr Pay', email: 'pay@clinic.test', status: 'expired'});
  return call({action: 'start', modules: ['revenue', 'ai_assistant']});
}

/** The bank paid [order]: the gateway now says SUCCESS. */
function paid(order) {
  gateway.payments.get(order.paymentId).status = 'SUCCESS';
}

const success = (r, extra = {}) => ({
  event: 'SUCCESS', paymentId: r.paymentId, orderId: r.orderId,
  amount: rupees(r.amountPaise), amountPaise: r.amountPaise, currency: 'INR', method: 'UPI',
  utr: '412345678901', completedAt: new Date().toISOString(), ...extra,
});

const order = (id) => db.peek(`${PLAN_PAYMENTS}/${id}`);
const user = () => db.peek(`users/${DR}`);

/** start(), plus the paymentId the app never sees but the gateway sends back. */
async function startedWithPayment() {
  const r = await started();
  return {...r, paymentId: order(r.orderId).paymentId};
}

// ---- tests -----------------------------------------------------------------
section('pricing');

test('only paid modules are sold, at the server price, whatever the app sends', () => {
  const p = priceModules(['AI_ASSISTANT', 'revenue', 'revenue', 'dashboard', 'queue', 'made_up', 42]);
  assert.deepStrictEqual(p.modules, ['revenue', 'ai_assistant']);
  assert.strictEqual(p.amountPaise, (999 + 2499) * 100);
  assert.deepStrictEqual(priceModules('revenue').modules, []);
});

test('amounts, UTRs and checkout links are normalised', () => {
  assert.strictEqual(rupees(349800), '3498.00');
  assert.strictEqual(rupees(5), '0.05');
  assert.strictEqual(normaliseUtr(' 4123 4567-8901 '), '412345678901');
  assert.strictEqual(normaliseUtr('12'), '');
  assert.strictEqual(normaliseUtr(undefined), '');
  assert.strictEqual(checkoutUrlFrom('/checkout/p1', 'https://pay.test'), 'https://pay.test/checkout/p1');
  assert.strictEqual(checkoutUrlFrom('javascript:alert(1)', 'https://pay.test'), null);
});

test('the free activation callable is gone', () => {
  assert.strictEqual(subscription.activateDoctorFeatures, undefined);
});

section('start');

test('creates an order and a gateway session priced on the server', async () => {
  const r = await started();
  assert.strictEqual(r.amountPaise, 349800);
  assert.strictEqual(r.checkoutUrl, `https://pay.test/checkout/${order(r.orderId).paymentId}`);
  const sent = gateway.calls[0];
  assert.strictEqual(sent.body.amount, '3498.00');
  assert.strictEqual(sent.body.orderId, r.orderId);
  assert.strictEqual(sent.headers['Idempotency-Key'], r.orderId);
  assert.strictEqual(sent.headers['X-Merchant-Id'], 'merchant-1');
  const o = order(r.orderId);
  assert.strictEqual(o.status, 'pending');
  assert.strictEqual(o.doctorId, DR);
  assert.ok(gateway.payments.has(o.paymentId));
  // Nothing is unlocked by starting.
  assert.strictEqual(user().status, 'expired');
});

test('refuses signed-out callers, an empty basket and unknown actions', async () => {
  await rejects('unauthenticated', planPayments.run({data: {action: 'start', modules: ['revenue']}}));
  await rejects('invalid-argument', call({action: 'start', modules: ['dashboard']}));
  await rejects('invalid-argument', call({action: 'pay', modules: ['revenue']}));
  assert.strictEqual(gateway.calls.length, 0);
});

test('says so plainly when the gateway is not set up, and never fakes it', async () => {
  const saved = process.env.YOUPI_BASE_URL;
  process.env.YOUPI_BASE_URL = '';
  try {
    await rejects('failed-precondition', call({action: 'start', modules: ['revenue']}));
    process.env.YOUPI_BASE_URL = 'http://pay.test';
    await rejects('failed-precondition', call({action: 'start', modules: ['revenue']}));
  } finally {
    process.env.YOUPI_BASE_URL = saved;
  }
});

test('gateway down, busy elsewhere, or echoing the wrong amount: the order fails', async () => {
  gateway.down = true;
  await rejects('unavailable', call({action: 'start', modules: ['revenue']}));
  gateway.down = false;
  gateway.createStatus = 409;
  await rejects('failed-precondition', call({action: 'start', modules: ['revenue']}));
  gateway.createStatus = 201;
  gateway.echo = {amountPaise: '100'};
  await rejects('internal', call({action: 'start', modules: ['revenue']}));
  const statuses = db.all(PLAN_PAYMENTS).map((d) => d.status).sort();
  assert.deepStrictEqual(statuses, ['failed', 'failed', 'failed']);
});

test(`is rate limited to ${STARTS_PER_HOUR} checkouts an hour`, async () => {
  for (let i = 0; i < STARTS_PER_HOUR; i++) await call({action: 'start', modules: ['revenue']});
  await rejects('resource-exhausted', call({action: 'start', modules: ['revenue']}));
});

section('cancel');

test('frees the gateway slot; only the doctor who started it may cancel', async () => {
  const r = await started();
  await rejects('not-found', call({action: 'cancel', orderId: r.orderId}, 'someone-else'));
  const out = await call({action: 'cancel', orderId: r.orderId});
  assert.strictEqual(out.status, 'cancelled');
  assert.strictEqual(order(r.orderId).status, 'cancelled');
  const paymentId = order(r.orderId).paymentId;
  assert.ok(gateway.calls.some((c) => c.url.endsWith(`/api/v1/checkout/${paymentId}/cancel`)));
});

section('webhook');

test('a verified, confirmed payment unlocks the plan and writes the receipt', async () => {
  const r = await startedWithPayment();
  paid(r);
  const res = await deliver(success(r));
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.outcome, 'paid');

  const o = order(r.orderId);
  assert.strictEqual(o.status, 'paid');
  assert.strictEqual(o.utr, '412345678901');
  const u = user();
  assert.strictEqual(u.status, 'active');
  assert.ok(u.enabledModules.includes('revenue') && u.enabledModules.includes('ai_assistant'));
  assert.ok(u.enabledModules.includes('dashboard'), 'base modules kept');
  assert.ok(!u.enabledModules.includes('home_visits'));
  assert.strictEqual(u.lastPaymentAmount, 3498);
  const receipt = db.peek(`payment_transactions/${o.transactionId}`);
  assert.strictEqual(receipt.status, 'success');
  assert.strictEqual(receipt.transactionReference, '412345678901');
  assert.strictEqual(receipt.gatewayPaymentId, r.paymentId);
  assert.strictEqual(receipt.doctorName, 'Dr Pay');
});

test('the receipt says which features are new and which were renewed', async () => {
  const {Timestamp} = require('firebase-admin/firestore');
  const inDays = (d) => Timestamp.fromMillis(Date.now() + d * 86400000);

  // Coming off a trial: everything paid for is new, even modules tried free.
  let r = await startedWithPayment();
  db.seed(`users/${DR}`, {name: 'Dr Pay', status: 'trial', expiresDate: inDays(5),
    enabledModules: ['dashboard', 'revenue', 'ai_assistant']});
  paid(r);
  await deliver(success(r));
  let receipt = db.peek(`payment_transactions/${order(r.orderId).transactionId}`);
  assert.deepStrictEqual(receipt.addedModules.sort(), ['ai_assistant', 'revenue']);
  assert.deepStrictEqual(receipt.renewedModules, []);
  assert.strictEqual(receipt.previousStatus, 'trial');

  // On a running paid plan with revenue: revenue is renewed, the scribe is new.
  db.store.clear();
  r = await startedWithPayment();
  db.seed(`users/${DR}`, {name: 'Dr Pay', status: 'active', expiresDate: inDays(3),
    enabledModules: ['dashboard', 'revenue']});
  paid(r);
  await deliver(success(r));
  receipt = db.peek(`payment_transactions/${order(r.orderId).transactionId}`);
  assert.deepStrictEqual(receipt.addedModules, ['ai_assistant']);
  assert.deepStrictEqual(receipt.renewedModules, ['revenue']);
  assert.strictEqual(receipt.previousStatus, 'active');

  // A paid plan that has run out owns nothing any more.
  db.store.clear();
  r = await startedWithPayment();
  db.seed(`users/${DR}`, {name: 'Dr Pay', status: 'active', expiresDate: inDays(-1),
    enabledModules: ['dashboard', 'revenue', 'ai_assistant']});
  paid(r);
  await deliver(success(r));
  receipt = db.peek(`payment_transactions/${order(r.orderId).transactionId}`);
  assert.deepStrictEqual(receipt.addedModules.sort(), ['ai_assistant', 'revenue']);
  assert.deepStrictEqual(receipt.renewedModules, []);
});

test('a replayed SUCCESS changes nothing', async () => {
  const r = await startedWithPayment();
  paid(r);
  await deliver(success(r));
  const first = order(r.orderId).transactionId;
  const again = await deliver(success(r));
  assert.strictEqual(again.body.outcome, 'already_paid');
  assert.strictEqual(order(r.orderId).transactionId, first);
  assert.strictEqual(db.all('payment_transactions').length, 1);
});

test('a bad or missing signature is refused before anything is read', async () => {
  const r = await startedWithPayment();
  paid(r);
  assert.strictEqual((await deliver(success(r), {secret: 'guessed'})).status, 401);
  assert.strictEqual((await deliver(success(r), {signature: ''})).status, 401);
  assert.strictEqual(order(r.orderId).status, 'pending');
  assert.strictEqual(user().status, 'expired');
});

test('a signed SUCCESS the gateway does not stand behind goes to review, not paid', async () => {
  const r = await startedWithPayment();
  // The gateway still says ACTIVE: the webhook alone is not enough.
  const res = await deliver(success(r));
  assert.strictEqual(res.body.outcome, 'review');
  assert.strictEqual(order(r.orderId).status, 'review');
  assert.strictEqual(order(r.orderId).review.reason, 'gateway_disagrees');
  assert.strictEqual(user().status, 'expired');
});

test('the wrong amount, or no UTR, goes to review', async () => {
  const a = await startedWithPayment();
  paid(a);
  await deliver(success(a, {amountPaise: 100}));
  assert.strictEqual(order(a.orderId).review.reason, 'amount_mismatch');

  const b = await call({action: 'start', modules: ['revenue']});
  const bPay = order(b.orderId).paymentId;
  gateway.payments.get(bPay).status = 'SUCCESS';
  await deliver(success({...b, paymentId: bPay}, {utr: ''}));
  assert.strictEqual(order(b.orderId).review.reason, 'no_utr');
  assert.strictEqual(user().status, 'expired');
});

test('one UTR pays for one order only', async () => {
  const a = await startedWithPayment();
  paid(a);
  await deliver(success(a));
  const b = await call({action: 'start', modules: ['revenue', 'ai_assistant']});
  const bPay = order(b.orderId).paymentId;
  gateway.payments.get(bPay).status = 'SUCCESS';
  const res = await deliver(success({...b, paymentId: bPay}));
  assert.strictEqual(res.body.outcome, 'review');
  assert.strictEqual(order(b.orderId).review.reason, 'utr_reused');
});

test('a payment that arrives after the doctor cancelled is still honoured', async () => {
  const r = await startedWithPayment();
  await call({action: 'cancel', orderId: r.orderId});
  gateway.payments.get(r.paymentId).status = 'SUCCESS';
  const res = await deliver(success(r));
  assert.strictEqual(res.body.outcome, 'paid');
  assert.strictEqual(user().status, 'active');
});

test('FAILED and EXPIRED close a pending order but never a paid one', async () => {
  const r = await startedWithPayment();
  await deliver({event: 'EXPIRED', paymentId: r.paymentId, orderId: r.orderId});
  assert.strictEqual(order(r.orderId).status, 'expired');

  const s = await call({action: 'start', modules: ['revenue']});
  const sPay = order(s.orderId).paymentId;
  gateway.payments.get(sPay).status = 'SUCCESS';
  await deliver(success({...s, paymentId: sPay}, {utr: '499999999999'}));
  await deliver({event: 'FAILED', paymentId: sPay, orderId: s.orderId});
  assert.strictEqual(order(s.orderId).status, 'paid');
});

test('unknown orders and mismatched payment ids are ignored', async () => {
  const r = await startedWithPayment();
  paid(r);
  assert.strictEqual((await deliver(success(r, {orderId: 'NotAnOrderOfOurs1'}))).body.outcome, 'unknown_order');
  assert.strictEqual((await deliver(success(r, {orderId: '../users/x'}))).body.outcome, 'ignored');
  assert.strictEqual((await deliver(success(r, {paymentId: 'pay-other'}))).body.outcome, 'payment_mismatch');
  assert.strictEqual(order(r.orderId).status, 'pending');
});

test('gateway unreachable while confirming: 503 so YouPI retries, then it settles', async () => {
  const r = await startedWithPayment();
  paid(r);
  gateway.down = true;
  assert.strictEqual((await deliver(success(r))).status, 503);
  assert.strictEqual(order(r.orderId).status, 'pending');
  gateway.down = false;
  assert.strictEqual((await deliver(success(r))).body.outcome, 'paid');
});

test('signature check: no secret configured means refuse, not accept', () => {
  const raw = Buffer.from('{}');
  const sig = `sha256=${crypto.createHmac('sha256', '').update(raw).digest('hex')}`;
  assert.deepStrictEqual(verifyGatewaySignature(raw, sig, ''), {ok: false, reason: 'secret_unset'});
});

section('test payments');

/** Runs [fn] with test payments switched on for [project]. */
async function withMock(fn, project = 'svayatta-crudoc-dev') {
  const saved = {mock: process.env.PLAN_PAYMENTS_MOCK, project: process.env.GCLOUD_PROJECT};
  process.env.PLAN_PAYMENTS_MOCK = 'true';
  process.env.GCLOUD_PROJECT = project;
  try {
    await fn();
  } finally {
    if (saved.mock === undefined) delete process.env.PLAN_PAYMENTS_MOCK;
    else process.env.PLAN_PAYMENTS_MOCK = saved.mock;
    if (saved.project === undefined) delete process.env.GCLOUD_PROJECT;
    else process.env.GCLOUD_PROJECT = saved.project;
  }
}

test('off by default, and off on any project not on the list', async () => {
  assert.strictEqual(mockPaymentsEnabled(), false);
  await withMock(async () => {
    assert.strictEqual(mockPaymentsEnabled(), false);
    const r = await started();
    assert.ok(r.checkoutUrl, 'went to the real gateway');
    await rejects('failed-precondition', call({action: 'mockPay', orderId: r.orderId}));
    assert.strictEqual(user().status, 'expired');
  }, 'svayatta-crudoc-prod');
});

test('a test checkout skips the gateway, then mockPay unlocks the plan with a marked receipt', async () => {
  const {Timestamp} = require('firebase-admin/firestore');
  await withMock(async () => {
    db.seed(`users/${DR}`, {
      name: 'Dr Pay', email: 'pay@clinic.test', status: 'active',
      expiresDate: Timestamp.fromMillis(Date.now() + 10 * 86400000),
      enabledModules: ['dashboard', 'revenue'],
    });
    const r = await call({action: 'start', modules: ['revenue', 'home_visits']});
    assert.strictEqual(r.mock, true);
    assert.strictEqual(r.checkoutUrl, null);
    assert.strictEqual(r.amountPaise, (999 + 1499) * 100);
    assert.strictEqual(gateway.calls.length, 0);
    assert.strictEqual(order(r.orderId).status, 'pending');

    await rejects('not-found', call({action: 'mockPay', orderId: r.orderId}, 'someone-else'));
    const out = await call({action: 'mockPay', orderId: r.orderId});
    assert.strictEqual(out.status, 'paid');

    const o = order(r.orderId);
    assert.strictEqual(o.status, 'paid');
    assert.ok(user().enabledModules.includes('home_visits'));
    assert.strictEqual(user().status, 'active');
    const receipt = db.peek(`payment_transactions/${o.transactionId}`);
    assert.strictEqual(receipt.status, 'success');
    assert.strictEqual(receipt.gateway, 'mock');
    assert.strictEqual(receipt.mock, true);
    assert.strictEqual(receipt.amount, 2498);
    assert.deepStrictEqual(receipt.addedModules, ['home_visits']);
    assert.deepStrictEqual(receipt.renewedModules, ['revenue']);

    // Paying again changes nothing.
    const again = await call({action: 'mockPay', orderId: r.orderId});
    assert.strictEqual(again.transactionId, o.transactionId);
    assert.strictEqual(db.all('payment_transactions').length, 1);
  });
});

test('mockPay never pays a real gateway order or a cancelled one', async () => {
  const real = await started();
  await withMock(async () => {
    await rejects('not-found', call({action: 'mockPay', orderId: real.orderId}));
    const r = await call({action: 'start', modules: ['revenue']});
    await call({action: 'cancel', orderId: r.orderId});
    await rejects('failed-precondition', call({action: 'mockPay', orderId: r.orderId}));
    assert.strictEqual(user().status, 'expired');
  });
});

(async () => {
  for (const t of queue) await t();
  console.log(`\n${passed} passed`);
})();
