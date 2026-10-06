import * as crypto from "crypto";
import * as admin from "firebase-admin";
import {getDb} from "./db";
import {getWebhookAppSecret, getWebhookVerifyToken} from "./config";
import {applyStatusEvent, lastClinicFor, LogStatus} from "./logs";
import {classifyReply, optIn, optOut} from "./optouts";
import {sendSessionText} from "./send";

/**
 * Meta's callbacks: delivery receipts, and anything a patient writes back.
 *
 * Replying is only legal inside the 24 hours a patient's own message opens,
 * which is exactly the situation here, so the confirmations and the auto-reply
 * are plain text rather than templates. They are also free.
 */

const AUTOREPLY_COLLECTION = "whatsapp_autoreplies";

/** One auto-reply per phone per day, so a chatty patient is not spammed. */
const AUTOREPLY_COOLDOWN_MS = 24 * 60 * 60 * 1000;

/** Answers Meta's subscription handshake. */
export function verifySubscription(query: Record<string, unknown>): string | null {
  const mode = query["hub.mode"];
  const token = query["hub.verify_token"];
  const challenge = query["hub.challenge"];
  const expected = getWebhookVerifyToken();

  if (mode !== "subscribe" || typeof token !== "string" || !expected) {
    return null;
  }

  const a = Buffer.from(token);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;

  return typeof challenge === "string" ? challenge : "";
}

/**
 * Checks Meta signed the request.
 *
 * Refuses when the secret is unset. The previous implementation wrapped this
 * whole check in `if (appSecret)`, and the repository shipped with the secret
 * unset — so every unsigned POST was accepted and anyone who found the URL
 * could forge delivery receipts.
 *
 * Uses the raw body only. Re-serialising the parsed body produces different
 * bytes, so comparing against that can never match.
 */
export function verifySignature(
  rawBody: Buffer | undefined,
  header: string | undefined,
): {ok: boolean; reason?: string} {
  const secret = getWebhookAppSecret();
  if (!secret) return {ok: false, reason: "app_secret_unset"};
  if (!rawBody) return {ok: false, reason: "no_raw_body"};
  if (!header || !header.startsWith("sha256=")) {
    return {ok: false, reason: "signature_missing"};
  }

  const given = Buffer.from(header.slice(7), "utf8");
  const expected = Buffer.from(
    crypto.createHmac("sha256", secret).update(rawBody).digest("hex"),
    "utf8",
  );

  if (given.length !== expected.length) {
    return {ok: false, reason: "signature_mismatch"};
  }
  if (!crypto.timingSafeEqual(given, expected)) {
    return {ok: false, reason: "signature_mismatch"};
  }

  return {ok: true};
}

function metaStatusToLogStatus(raw: string): LogStatus | null {
  switch (raw) {
  case "sent": return "sent";
  case "delivered": return "delivered";
  case "read": return "read";
  case "failed": return "failed";
  default: return null;
  }
}

function timestampFrom(seconds: unknown): Date {
  const n = Number(seconds);
  return Number.isFinite(n) && n > 0 ? new Date(n * 1000) : new Date();
}

async function handleStatuses(
  statuses: Array<Record<string, any>>,
): Promise<void> {
  for (const s of statuses) {
    const status = metaStatusToLogStatus(String(s.status || ""));
    const messageId = String(s.id || "");
    if (!status || !messageId) continue;

    const error = Array.isArray(s.errors) ? s.errors[0] : undefined;

    try {
      await applyStatusEvent({
        messageId,
        status,
        at: timestampFrom(s.timestamp),
        errorCode: error?.code,
        errorTitle: error?.title || error?.message,
      });
    } catch (err) {
      console.error(`[WhatsApp Webhook] status ${messageId} failed`, err);
    }
  }
}

/** True when this phone has not had an auto-reply in the last day. */
async function mayAutoReply(phone: string): Promise<boolean> {
  const ref = getDb().collection(AUTOREPLY_COLLECTION).doc(phone);

  return getDb().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const last = (snap.data()?.lastRepliedAt as admin.firestore.Timestamp)
      ?.toMillis?.() ?? 0;

    if (Date.now() - last < AUTOREPLY_COOLDOWN_MS) return false;

    tx.set(ref, {
      phone,
      lastRepliedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    return true;
  });
}

async function replySafely(to: string, text: string): Promise<void> {
  try {
    await sendSessionText({to, text});
  } catch (err) {
    // A reply failing must not fail the webhook: Meta disables a callback that
    // keeps returning errors.
    console.error(`[WhatsApp Webhook] reply to ${to} failed`, err);
  }
}

async function handleInbound(
  messages: Array<Record<string, any>>,
): Promise<void> {
  for (const m of messages) {
    const from = String(m.from || "").replace(/\D/g, "");
    if (!from) continue;

    const text = m.type === "text" ?
      String(m.text?.body || "") :
      String(m.button?.text || m.interactive?.button_reply?.title || "");

    const intent = classifyReply(text);

    if (intent === "stop") {
      await optOut(from, "reply");
      await replySafely(
        from,
        "You won't get reminders from CruDoc any more. " +
        "Reply START to turn them back on.",
      );
      console.log(`[WhatsApp] ${from} opted out`);
      continue;
    }

    if (intent === "start") {
      await optIn(from);
      await replySafely(
        from,
        "Appointment reminders are back on. Reply STOP at any time to stop them.",
      );
      console.log(`[WhatsApp] ${from} opted back in`);
      continue;
    }

    // Anything else: tell them this number is not watched, and point them at
    // the clinic that last messaged them.
    if (!(await mayAutoReply(from))) continue;

    const clinic = await lastClinicFor(from);
    const where = clinic?.clinicName ?
      `${clinic.clinicName}` :
      "your clinic";

    await replySafely(
      from,
      "This number only sends appointment reminders and is not monitored. " +
      `Please call ${where} directly.`,
    );
  }
}

/**
 * Processes one callback.
 *
 * Never throws: Meta disables a webhook that keeps failing, and a routing
 * problem on one event must not cost every later one.
 */
export async function processWebhook(body: any): Promise<void> {
  const entries: Array<Record<string, any>> = Array.isArray(body?.entry) ?
    body.entry :
    [];

  for (const entry of entries) {
    const changes: Array<Record<string, any>> = Array.isArray(entry?.changes) ?
      entry.changes :
      [];

    for (const change of changes) {
      const value = change?.value || {};

      try {
        if (Array.isArray(value.statuses) && value.statuses.length) {
          await handleStatuses(value.statuses);
        }
        if (Array.isArray(value.messages) && value.messages.length) {
          await handleInbound(value.messages);
        }
      } catch (err) {
        console.error("[WhatsApp Webhook] change failed", err);
      }
    }
  }
}
