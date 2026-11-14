import * as admin from "firebase-admin";
import {getDb} from "../whatsapp/db";
import {enqueueWhatsApp} from "../whatsapp/outbox";
import {getConfig} from "../whatsapp/config";
import {getTenantConfig} from "../whatsapp/tenants";
import {
  GmailError, isPlausibleEmail, refreshAccessToken, sendGmail,
} from "./gmail";
import {
  Channel, EmailTemplate, ReminderKind, ReminderSettings, readSettings,
} from "./settings";
import {openToken} from "./vault";

/**
 * The channel layer for automatic reminders and recalls.
 *
 * deliver() picks the first channel, in the clinic's order, that can reach
 * this patient right now:
 *   WhatsApp  the clinic has a phone to quote, the patient has a phone, and
 *             either the clinic's own number is connected or the shared CruDoc
 *             number is configured (the same fallback the outbox has always
 *             had). Appointment reminders keep their original direct send from
 *             the shared number and its whatsapp_notification_logs entry
 *             (`direct`); recalls go through the outbox.
 *   Email     Gmail is connected and the patient has an address. Sent here, as
 *             the clinic, over the Gmail REST API.
 * A failed email send falls through to the next channel. If nothing can reach
 * the patient the attempt is recorded as "skipped: no_channel".
 *
 * Every attempt is one document in clinics/{clinicId}/reminder_log whose id is
 * deterministic (kind + visit/recall + day), created in a transaction, so a
 * rerun, an overlapping sweep or the morning catch-up can never send the same
 * reminder twice. No names, phones or addresses go in the log: only the
 * patient id, which the app resolves locally for display.
 */

export type LogStatus = "queued" | "sent" | "failed" | "skipped";

export const REMINDER_LOG = "reminder_log";
export const GMAIL_PRIVATE_DOC = ["private", "gmail"] as const;
export const GMAIL_STATUS_DOC = ["messaging_status", "gmail"] as const;

/** A failed attempt is tried once more by the next sweep, then left alone. */
const MAX_ATTEMPTS = 2;

export interface GmailSender {
  address: string;
  refreshToken: string;
  /** Minted on first use in a run, never stored. */
  accessToken?: string;
  /** Set once the token is known dead, so the run stops trying. */
  dead?: boolean;
}

export interface ClinicContext {
  clinicId: string;
  settings: ReminderSettings;
  whatsappReady: boolean;
  gmail: GmailSender | null;
}

export interface PatientContact {
  patientId: string | null;
  phone: string | null;
  email: string | null;
  optedOut: boolean;
}

export interface Rendered {
  /** Visit id or recall record id. */
  refId: string;
  /** Clinic-local date the message is about (YYYY-MM-DD). */
  dayKey: string;
  whatsapp: {
    templateKey: string;
    params: Record<string, string>;
    /**
     * The pre-existing direct send (claims and updates the
     * whatsapp_notification_logs entry). "already" when that log shows the
     * reminder was handled before.
     */
    direct?: () => Promise<"sent" | "already">;
  } | null;
  email: EmailTemplate;
}

export interface DeliverResult {
  status: LogStatus | "already_handled";
  channel: Channel | null;
  reason?: string;
}

function logRef(clinicId: string, id: string) {
  return getDb().collection("clinics").doc(clinicId)
    .collection(REMINDER_LOG).doc(id);
}

function logId(kind: ReminderKind, refId: string, dayKey: string): string {
  return `${kind}_${refId}_${dayKey}`.replace(/[^A-Za-z0-9_.-]/g, "_")
    .slice(0, 400);
}

/**
 * Builds what deliver() needs about one clinic. Done once per clinic per run:
 * it reads the tenant status and the Gmail record, and decrypts the token.
 */
export async function buildClinicContext(
  clinicId: string,
  userData: admin.firestore.DocumentData | undefined,
  clinicPhone: string | null,
): Promise<ClinicContext> {
  const db = getDb();
  const settings = readSettings(userData);

  let whatsappReady = false;
  try {
    const tenant = await getTenantConfig(clinicId);
    let shared = false;
    try {
      getConfig();
      shared = true;
    } catch (_) {
      // No shared number configured.
    }
    whatsappReady =
      !!clinicPhone && ((!!tenant && tenant.status === "connected") || shared);
  } catch (err) {
    console.error(`[reminders] tenant read failed for ${clinicId}`, err);
  }

  let gmail: GmailSender | null = null;
  try {
    const clinic = db.collection("clinics").doc(clinicId);
    const [privateSnap, statusSnap] = await Promise.all([
      clinic.collection(GMAIL_PRIVATE_DOC[0]).doc(GMAIL_PRIVATE_DOC[1]).get(),
      clinic.collection(GMAIL_STATUS_DOC[0]).doc(GMAIL_STATUS_DOC[1]).get(),
    ]);
    const state = statusSnap.data()?.state;
    if (privateSnap.exists && state === "connected") {
      const refreshToken = openToken(
        clinicId, privateSnap.data()?.refreshTokenSealed,
      );
      const address = String(privateSnap.data()?.address || "");
      if (refreshToken && address) gmail = {address, refreshToken};
    }
  } catch (err) {
    console.error(`[reminders] gmail read failed for ${clinicId}`, err);
  }

  return {clinicId, settings, whatsappReady, gmail};
}

/**
 * Takes the log slot for this reminder. False when it is already handled: sent,
 * queued, skipped, or failed twice.
 */
async function claim(
  clinicId: string,
  id: string,
  base: Record<string, unknown>,
): Promise<boolean> {
  const ref = logRef(clinicId, id);
  return getDb().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = admin.firestore.FieldValue.serverTimestamp();
    if (!snap.exists) {
      tx.create(ref, {
        ...base, status: "pending", attempts: 1, createdAt: now, updatedAt: now,
      });
      return true;
    }
    const data = snap.data() || {};
    if (data.status === "failed" && (data.attempts || 1) < MAX_ATTEMPTS) {
      tx.update(ref, {
        status: "pending", attempts: (data.attempts || 1) + 1, updatedAt: now,
      });
      return true;
    }
    return false;
  });
}

async function finish(
  clinicId: string,
  id: string,
  fields: {
    status: LogStatus;
    channel: Channel | null;
    reason?: string;
    errorCode?: string;
    outboxId?: string;
  },
): Promise<void> {
  await logRef(clinicId, id).update({
    status: fields.status,
    channel: fields.channel,
    reason: fields.reason ?? null,
    errorCode: fields.errorCode ?? null,
    outboxId: fields.outboxId ?? null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function markGmailReauth(clinicId: string): Promise<void> {
  try {
    await getDb().collection("clinics").doc(clinicId)
      .collection(GMAIL_STATUS_DOC[0]).doc(GMAIL_STATUS_DOC[1])
      .set({
        state: "reauth_required",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
  } catch (err) {
    console.error(`[reminders] could not flag gmail reauth for ${clinicId}`, err);
  }
}

/** Sends one email as the clinic, minting the access token on first use. */
async function sendEmail(
  ctx: ClinicContext,
  to: string,
  email: EmailTemplate,
): Promise<void> {
  const g = ctx.gmail;
  if (!g || g.dead) {
    throw new GmailError("Gmail is not connected.", "gmail_unavailable", true, true);
  }
  try {
    if (!g.accessToken) g.accessToken = await refreshAccessToken(g.refreshToken);
    await sendGmail({
      accessToken: g.accessToken,
      fromAddress: g.address,
      to,
      subject: email.subject,
      body: email.body,
    });
  } catch (err) {
    if (err instanceof GmailError && err.reauth) {
      g.dead = true;
      await markGmailReauth(ctx.clinicId);
    }
    throw err;
  }
}

export async function deliver(
  ctx: ClinicContext,
  patient: PatientContact,
  kind: ReminderKind,
  rendered: Rendered,
): Promise<DeliverResult> {
  const id = logId(kind, rendered.refId, rendered.dayKey);
  const claimed = await claim(ctx.clinicId, id, {
    kind,
    refId: rendered.refId,
    dayKey: rendered.dayKey,
    patientId: patient.patientId,
  });
  if (!claimed) return {status: "already_handled", channel: null};

  if (patient.optedOut) {
    await finish(ctx.clinicId, id, {
      status: "skipped", channel: null, reason: "opted_out",
    });
    return {status: "skipped", channel: null, reason: "opted_out"};
  }

  let lastError: {channel: Channel; code: string; message: string} | null = null;

  for (const channel of ctx.settings.channelOrder) {
    if (channel === "whatsapp") {
      if (!ctx.whatsappReady || !patient.phone || !rendered.whatsapp) continue;
      try {
        if (rendered.whatsapp.direct) {
          const sent = await rendered.whatsapp.direct();
          if (sent === "already") {
            await finish(ctx.clinicId, id, {
              status: "skipped", channel: "whatsapp", reason: "already_sent",
            });
            return {status: "skipped", channel: "whatsapp", reason: "already_sent"};
          }
          await finish(ctx.clinicId, id, {status: "sent", channel: "whatsapp"});
          return {status: "sent", channel: "whatsapp"};
        }
        const result = await enqueueWhatsApp({
          doctorId: ctx.clinicId,
          toPhone: patient.phone,
          templateKey: rendered.whatsapp.templateKey,
          params: rendered.whatsapp.params,
          kind,
          patientId: patient.patientId ?? undefined,
          dedupeKey: `${id}_wa`,
        });
        await finish(ctx.clinicId, id, {
          status: "queued", channel: "whatsapp", outboxId: result.id,
        });
        return {status: "queued", channel: "whatsapp"};
      } catch (err) {
        lastError = {
          channel,
          code: String((err as {code?: unknown}).code ?? "whatsapp_failed"),
          message: (err as Error).message,
        };
      }
    } else {
      if (!ctx.gmail || ctx.gmail.dead || !isPlausibleEmail(patient.email)) {
        continue;
      }
      try {
        await sendEmail(ctx, patient.email as string, rendered.email);
        await finish(ctx.clinicId, id, {status: "sent", channel: "email"});
        return {status: "sent", channel: "email"};
      } catch (err) {
        const code = err instanceof GmailError ? err.code : "send_failed";
        lastError = {channel, code, message: (err as Error).message};
        console.error(
          `[reminders] email failed for ${ctx.clinicId} ${id}: ${code}`,
        );
      }
    }
  }

  if (lastError) {
    await finish(ctx.clinicId, id, {
      status: "failed",
      channel: lastError.channel,
      errorCode: lastError.code,
      reason: lastError.message.slice(0, 200),
    });
    return {status: "failed", channel: lastError.channel, reason: lastError.code};
  }

  await finish(ctx.clinicId, id, {
    status: "skipped", channel: null, reason: "no_channel",
  });
  return {status: "skipped", channel: null, reason: "no_channel"};
}

/** Records a skip decided before delivery (no name, nothing to say). */
export async function logSkip(
  clinicId: string,
  kind: ReminderKind,
  refId: string,
  dayKey: string,
  patientId: string | null,
  reason: string,
): Promise<void> {
  const id = logId(kind, refId, dayKey);
  const ok = await claim(clinicId, id, {kind, refId, dayKey, patientId});
  if (ok) await finish(clinicId, id, {status: "skipped", channel: null, reason});
}
