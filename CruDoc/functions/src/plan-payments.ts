import {onCall, onRequest, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import {FieldValue} from "firebase-admin/firestore";
import {spend} from "./referrals";
import {writePaidPlan} from "./subscription";

/**
 * Paying for a CruDoc plan by UPI, through CruDoc's own YouPI PG gateway
 * (https://github.com/youpi-pg/YouPI-PG).
 *
 *   app ──planPayments{start}──▶ here ──POST /api/v1/payments──▶ YouPI
 *   app opens the returned checkoutUrl; the doctor pays by UPI to CruDoc's VPA
 *   YouPI ──signed webhook──▶ youpiWebhook ──GET /api/v1/payments/{id}──▶ YouPI
 *                                 └─▶ writePaidPlan, plan_payments/{orderId}.status = paid
 *
 * The app only ever watches plan_payments/{orderId}; it never says what was
 * paid. The price is worked out here, and a plan is unlocked only by a
 * webhook whose signature checks out *and* whose payment the gateway then
 * confirms when asked directly. YouPI's own README warns that its bank-SMS
 * matching can be wrong, so anything that doesn't add up is parked as
 * `review` for a person to look at instead of being unlocked or refused.
 *
 * Setup is in functions/.env.example (YOUPI_*).
 */

export const youpiWebhookSecret = defineSecret("YOUPI_WEBHOOK_SECRET");

const REGION = "asia-south1";

/** One document per checkout attempt; the id is the order id sent to YouPI. */
export const PLAN_PAYMENTS = "plan_payments";

/** UTR -> order. One bank transfer pays for one order, ever. */
export const PLAN_PAYMENT_UTRS = "plan_payment_utrs";

/**
 * What one month of each paid module costs, in rupees. The only modules sold.
 * Keep in sync with monthlyPriceInr in crudoc_shared/subscription/feature_catalog.dart,
 * which is what the app shows; this is what is charged.
 */
export const MODULE_PRICES_INR: Readonly<Record<string, number>> = {
  revenue: 999,
  home_visits: 1499,
  omnichannel_messaging: 1999,
  ai_assistant: 2499,
  ai_agentic_calling: 3999,
  multi_device_access: 799,
};

/**
 * Checkouts one doctor may start per hour. YouPI lets only one customer pay
 * at a time on a VPA and queues the rest, so this also stops one account
 * from holding the queue against everyone else.
 */
export const STARTS_PER_HOUR = 6;

const GATEWAY_TIMEOUT_MS = 15_000;

export type PlanPaymentStatus =
  "starting" | "pending" | "paid" | "failed" | "expired" | "cancelled" | "review";

/** Thrown when the gateway can't be asked; the webhook answers 503 so YouPI retries. */
class GatewayUnavailable extends Error {}

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

interface GatewayConfig {
  baseUrl: string;
  merchantId: string;
}

function env(name: string): string {
  return (process.env[name] || "").trim();
}

/**
 * The gateway's base URL and merchant id, or a refusal the app can show.
 * Never a pretend success: an unconfigured deployment must not unlock plans.
 */
export function gatewayConfig(): GatewayConfig {
  const baseUrl = env("YOUPI_BASE_URL").replace(/\/+$/, "");
  if (!baseUrl) {
    throw new HttpsError("failed-precondition", "Online payment isn't set up yet. Contact CruDoc support.");
  }
  // HTTPS only, except a gateway on this machine for the emulator.
  if (!/^https:\/\//.test(baseUrl) && !/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(baseUrl)) {
    throw new HttpsError("failed-precondition", "The payment gateway address must use HTTPS.");
  }
  return {baseUrl, merchantId: env("YOUPI_MERCHANT_ID")};
}

function webhookSecret(): string {
  try {
    const v = youpiWebhookSecret.value();
    if (v && v.trim()) return v.trim();
  } catch (_) {
    // Not bound (emulator, tests): fall back to the environment.
  }
  return env("YOUPI_WEBHOOK_SECRET");
}

function headers(cfg: GatewayConfig, extra: Record<string, string> = {}): Record<string, string> {
  return {
    "Content-Type": "application/json",
    ...(cfg.merchantId ? {"X-Merchant-Id": cfg.merchantId} : {}),
    ...extra,
  };
}

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------

/** The paid modules asked for, in catalogue order, and what they cost in paise. */
export function priceModules(raw: unknown): {modules: string[]; amountPaise: number} {
  const asked = new Set(
    Array.isArray(raw) ? raw.map((m) => String(m).toLowerCase().trim()) : [],
  );
  const modules = Object.keys(MODULE_PRICES_INR).filter((m) => asked.has(m));
  const amountPaise = modules.reduce((sum, m) => sum + MODULE_PRICES_INR[m] * 100, 0);
  return {modules, amountPaise};
}

/** 199900 -> "1999.00", the form YouPI takes amounts in. */
export function rupees(paise: number): string {
  return `${Math.floor(paise / 100)}.${String(paise % 100).padStart(2, "0")}`;
}

/** A UTR as one canonical string, or "" when there isn't a believable one. */
export function normaliseUtr(raw: unknown): string {
  const utr = String(raw ?? "").replace(/[\s-]/g, "").toUpperCase();
  return /^[A-Z0-9]{10,35}$/.test(utr) ? utr : "";
}

/** Amounts arrive as a string from the REST API and a number in webhooks. */
function paiseOf(raw: unknown): number {
  const n = typeof raw === "number" ? raw : Number(String(raw ?? "").trim());
  return Number.isSafeInteger(n) ? n : NaN;
}

/**
 * Checks YouPI's `X-Gateway-Signature: sha256=<hex>`: HMAC-SHA256 of the raw
 * request bytes with the merchant's webhook secret. The parsed body can't be
 * used; re-serialising it gives different bytes.
 */
export function verifyGatewaySignature(
  rawBody: Buffer | undefined,
  header: string | undefined,
  secret: string = webhookSecret(),
): {ok: boolean; reason?: string} {
  if (!secret) return {ok: false, reason: "secret_unset"};
  if (!rawBody) return {ok: false, reason: "no_raw_body"};
  if (!header || !header.startsWith("sha256=")) return {ok: false, reason: "signature_missing"};
  const given = Buffer.from(header.slice(7).toLowerCase(), "utf8");
  const expected = Buffer.from(
    crypto.createHmac("sha256", secret).update(rawBody).digest("hex"), "utf8");
  if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected)) {
    return {ok: false, reason: "signature_mismatch"};
  }
  return {ok: true};
}

/** The checkout page to open, as an absolute http(s) URL on the gateway, or null. */
export function checkoutUrlFrom(raw: unknown, baseUrl: string): string | null {
  if (typeof raw !== "string" || !raw) return null;
  try {
    const url = new URL(raw, `${baseUrl}/`);
    return url.protocol === "https:" || url.protocol === "http:" ? url.toString() : null;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// The callable: start and cancel a checkout
// ---------------------------------------------------------------------------

function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to pay for a plan.");
  return uid;
}

async function start(request: CallableRequest) {
  const uid = requireUid(request);
  const {modules, amountPaise} = priceModules(request.data?.modules);
  if (!modules.length) {
    throw new HttpsError("invalid-argument", "Choose at least one paid feature.");
  }
  const cfg = gatewayConfig();
  await spend(uid, "planPaymentStarts", 1, STARTS_PER_HOUR, 3600_000,
    "That's a lot of payment attempts. Try again in an hour, or contact CruDoc support.");

  const db = admin.firestore();
  const ref = db.collection(PLAN_PAYMENTS).doc();
  const orderId = ref.id;
  await ref.set({
    doctorId: uid,
    modules,
    amountPaise,
    currency: "INR",
    gateway: "youpi",
    status: "starting" as PlanPaymentStatus,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  const fail = async (reason: string, error: HttpsError): Promise<never> => {
    await ref.update({status: "failed", failure: reason, updatedAt: FieldValue.serverTimestamp()});
    throw error;
  };

  const token = (request.auth?.token ?? {}) as Record<string, unknown>;
  let res: Response;
  try {
    res = await fetch(`${cfg.baseUrl}/api/v1/payments`, {
      method: "POST",
      headers: headers(cfg, {"Idempotency-Key": orderId}),
      body: JSON.stringify({
        orderId,
        amount: rupees(amountPaise),
        currency: "INR",
        customer: {
          name: String(token.name ?? ""),
          email: String(token.email ?? ""),
          phoneNumber: String(token.phone_number ?? ""),
        },
        description: `CruDoc plan, 30 days: ${modules.join(", ")}`,
        metadata: {doctorId: uid, kind: "crudoc_plan"},
      }),
      signal: AbortSignal.timeout(GATEWAY_TIMEOUT_MS),
    });
  } catch (err) {
    console.error("[planPayments] gateway unreachable:", (err as Error).message);
    return fail("gateway_unreachable",
      new HttpsError("unavailable", "We couldn't open the payment page. Try again in a minute."));
  }

  const body = await res.json().catch(() => ({})) as Record<string, unknown>;
  if (res.status === 409) {
    return fail("duplicate_session", new HttpsError("failed-precondition",
      "A payment is already open for you on another device. Finish or cancel it there first."));
  }
  if (res.status === 403) {
    return fail("gateway_refused", new HttpsError("permission-denied",
      "The payment service declined this payment. Contact CruDoc support."));
  }
  const checkoutUrl = checkoutUrlFrom(body.checkoutUrl, cfg.baseUrl);
  if (!res.ok || typeof body.paymentId !== "string" || !body.paymentId || !checkoutUrl) {
    console.error(`[planPayments] create failed: HTTP ${res.status}`, body.error ?? "");
    return fail(`gateway_http_${res.status}`,
      new HttpsError("unavailable", "We couldn't open the payment page. Try again in a minute."));
  }
  // The page must ask for what we priced, for this order.
  if (body.orderId !== orderId || paiseOf(body.amountPaise) !== amountPaise) {
    console.error(`[planPayments] gateway echoed ${body.orderId}/${body.amountPaise} for ${orderId}/${amountPaise}`);
    return fail("gateway_mismatch",
      new HttpsError("internal", "The payment page came back with the wrong amount. Nothing was charged."));
  }

  const queuePosition = typeof body.queuePosition === "number" ? body.queuePosition : null;
  await ref.update({
    status: "pending" as PlanPaymentStatus,
    paymentId: body.paymentId,
    checkoutUrl,
    gatewayStatus: String(body.status ?? ""),
    queuePosition,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {orderId, checkoutUrl, amountPaise, modules, queuePosition};
}

async function cancel(request: CallableRequest) {
  const uid = requireUid(request);
  const orderId = String(request.data?.orderId ?? "").trim();
  if (!orderId) throw new HttpsError("invalid-argument", "orderId is required.");

  const db = admin.firestore();
  const ref = db.collection(PLAN_PAYMENTS).doc(orderId);
  const snap = await ref.get();
  const order = snap.data();
  if (!order || order.doctorId !== uid) throw new HttpsError("not-found", "Payment not found.");
  if (order.status !== "starting" && order.status !== "pending") {
    return {orderId, status: order.status};
  }

  // Free the gateway's slot for the next person. If this fails the session
  // still expires on its own; and if the doctor pays anyway, the webhook
  // honours it (see settle), so cancelling never loses a real payment.
  if (typeof order.paymentId === "string" && order.paymentId) {
    try {
      const cfg = gatewayConfig();
      await fetch(`${cfg.baseUrl}/api/v1/checkout/${encodeURIComponent(order.paymentId)}/cancel`, {
        method: "POST",
        headers: headers(cfg),
        signal: AbortSignal.timeout(GATEWAY_TIMEOUT_MS),
      });
    } catch (err) {
      console.warn(`[planPayments] cancel of ${orderId} not sent:`, (err as Error).message);
    }
  }
  await db.runTransaction(async (tx) => {
    const now = (await tx.get(ref)).data();
    if (now?.status === "starting" || now?.status === "pending") {
      tx.update(ref, {status: "cancelled", updatedAt: FieldValue.serverTimestamp()});
    }
  });
  return {orderId, status: "cancelled"};
}

/**
 * `planPayments({action, ...})`:
 *   start   {modules}   -> {orderId, checkoutUrl, amountPaise, modules, queuePosition}
 *   cancel  {orderId}   -> {orderId, status}
 * The outcome arrives on plan_payments/{orderId}, which the app watches.
 */
export const planPayments = onCall({region: REGION, maxInstances: 10}, async (request) => {
  switch (String(request.data?.action ?? "")) {
  case "start": return start(request);
  case "cancel": return cancel(request);
  default: throw new HttpsError("invalid-argument", "Unknown action.");
  }
});

// ---------------------------------------------------------------------------
// The webhook: settle a checkout
// ---------------------------------------------------------------------------

/** What YouPI says about a payment when asked directly. */
async function confirmWithGateway(paymentId: string): Promise<Record<string, unknown>> {
  let cfg: GatewayConfig;
  try {
    cfg = gatewayConfig();
  } catch (_) {
    throw new GatewayUnavailable("YOUPI_BASE_URL is unset");
  }
  let res: Response;
  try {
    res = await fetch(`${cfg.baseUrl}/api/v1/payments/${encodeURIComponent(paymentId)}`, {
      headers: headers(cfg),
      signal: AbortSignal.timeout(GATEWAY_TIMEOUT_MS),
    });
  } catch (err) {
    throw new GatewayUnavailable((err as Error).message);
  }
  if (res.status === 404) return {};
  if (!res.ok) throw new GatewayUnavailable(`HTTP ${res.status}`);
  return await res.json() as Record<string, unknown>;
}

async function markReview(
  ref: admin.firestore.DocumentReference, reason: string, details: Record<string, unknown>,
): Promise<string> {
  console.error(`[youpiWebhook] ${ref.id} needs review: ${reason}`, details);
  await admin.firestore().runTransaction(async (tx) => {
    const order = (await tx.get(ref)).data();
    if (order && order.status !== "paid") {
      tx.update(ref, {
        status: "review", review: {reason, ...details},
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  });
  return "review";
}

/**
 * A SUCCESS event. Unlocks the plan only when the signed event, the gateway
 * asked directly, and the order all agree, and the UTR has paid for nothing
 * else. A real payment is honoured even after the doctor cancelled or the
 * session expired: the money arrived, so the plan is theirs.
 */
async function settle(
  ref: admin.firestore.DocumentReference,
  order: admin.firestore.DocumentData,
  event: Record<string, unknown>,
): Promise<string> {
  const paymentId = String(order.paymentId || event.paymentId || "");
  const utr = normaliseUtr(event.utr);
  if (paiseOf(event.amountPaise) !== order.amountPaise) {
    return markReview(ref, "amount_mismatch",
      {expectedPaise: order.amountPaise, eventPaise: String(event.amountPaise ?? ""), utr});
  }
  if (!utr) return markReview(ref, "no_utr", {paymentId});

  // Ask the gateway itself, so a webhook alone, replayed or forged with a
  // leaked secret, never unlocks a plan.
  const confirmed = await confirmWithGateway(paymentId);
  if (confirmed.status !== "SUCCESS" || confirmed.orderId !== ref.id ||
      paiseOf(confirmed.amountPaise) !== order.amountPaise) {
    return markReview(ref, "gateway_disagrees", {
      paymentId, utr,
      gatewayStatus: String(confirmed.status ?? "missing"),
      gatewayOrderId: String(confirmed.orderId ?? ""),
      gatewayPaise: String(confirmed.amountPaise ?? ""),
    });
  }

  const db = admin.firestore();
  const utrRef = db.collection(PLAN_PAYMENT_UTRS).doc(utr);
  return db.runTransaction(async (tx) => {
    const [orderSnap, utrSnap, userSnap] = await Promise.all([
      tx.get(ref), tx.get(utrRef), tx.get(db.collection("users").doc(order.doctorId)),
    ]);
    const now = orderSnap.data() || {};
    if (now.status === "paid") return "already_paid";
    if (now.status === "review") return "review";
    if (utrSnap.exists && utrSnap.data()?.orderId !== ref.id) {
      tx.update(ref, {
        status: "review",
        review: {reason: "utr_reused", utr, otherOrderId: String(utrSnap.data()?.orderId ?? "")},
        updatedAt: FieldValue.serverTimestamp(),
      });
      return "review";
    }

    const verificationLevel =
      typeof confirmed.verificationLevel === "number" ? confirmed.verificationLevel : null;
    const {transactionId, validUntil} = writePaidPlan(tx, order.doctorId, userSnap.data() || {}, {
      modules: order.modules,
      amountInr: order.amountPaise / 100,
      paymentMethod: "UPI",
      transactionReference: utr,
      receipt: {gateway: "youpi", gatewayPaymentId: paymentId, orderId: ref.id, utr, verificationLevel},
    });
    tx.set(utrRef, {orderId: ref.id, doctorId: order.doctorId, at: FieldValue.serverTimestamp()});
    tx.update(ref, {
      status: "paid",
      paymentId,
      utr,
      verificationLevel,
      transactionId,
      validUntil,
      paidAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return "paid";
  });
}

/** Handles one verified webhook event; returns what was done, for the log. */
export async function handleGatewayEvent(event: Record<string, unknown>): Promise<string> {
  const orderId = typeof event.orderId === "string" ? event.orderId.trim() : "";
  // Order ids are Firestore auto ids; anything that couldn't be one (a path,
  // say) isn't ours.
  if (!/^[A-Za-z0-9]{1,64}$/.test(orderId)) return "ignored";

  const ref = admin.firestore().collection(PLAN_PAYMENTS).doc(orderId);
  const order = (await ref.get()).data();
  if (!order) return "unknown_order";
  if (order.paymentId && event.paymentId && order.paymentId !== event.paymentId) {
    console.error(`[youpiWebhook] ${orderId}: event for payment ${event.paymentId}, order has ${order.paymentId}`);
    return "payment_mismatch";
  }

  const kind = String(event.event ?? "").toUpperCase();
  if (kind === "SUCCESS") return settle(ref, order, event);
  if (kind === "FAILED" || kind === "EXPIRED" || kind === "CANCELLED") {
    const status = kind.toLowerCase();
    await admin.firestore().runTransaction(async (tx) => {
      const now = (await tx.get(ref)).data();
      if (now?.status === "starting" || now?.status === "pending") {
        tx.update(ref, {status, updatedAt: FieldValue.serverTimestamp()});
      }
    });
    return status;
  }
  return "ignored";
}

/**
 * YouPI's merchant webhook. Configure it in the YouPI merchant admin as
 *   https://asia-south1-<project>.cloudfunctions.net/youpiWebhook
 * with the same secret as YOUPI_WEBHOOK_SECRET.
 */
export const youpiWebhook = onRequest(
  {region: REGION, maxInstances: 10, secrets: [youpiWebhookSecret]},
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method not allowed");
      return;
    }
    const check = verifyGatewaySignature(
      (req as unknown as {rawBody?: Buffer}).rawBody,
      req.get("x-gateway-signature") ?? undefined,
    );
    if (!check.ok) {
      console.error(`[youpiWebhook] rejected: ${check.reason}`);
      res.status(check.reason === "secret_unset" ? 500 : 401).send("Unauthorized");
      return;
    }

    const delivery = req.get("x-gateway-delivery-id") ?? "";
    try {
      const body = req.body && typeof req.body === "object" ? req.body as Record<string, unknown> : {};
      const outcome = await handleGatewayEvent(body);
      console.log(`[youpiWebhook] delivery ${delivery} order ${String(body.orderId ?? "")}: ${outcome}`);
      res.status(200).json({ok: true, outcome});
    } catch (err) {
      // 5xx so YouPI delivers it again; settling is idempotent.
      const retry = err instanceof GatewayUnavailable;
      console.error(`[youpiWebhook] delivery ${delivery} failed${retry ? " (gateway unreachable)" : ""}:`,
        (err as Error).message);
      res.status(retry ? 503 : 500).json({ok: false});
    }
  },
);
