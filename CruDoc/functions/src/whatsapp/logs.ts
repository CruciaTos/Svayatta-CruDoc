import * as admin from "firebase-admin";
import {getDb} from "./db";

/**
 * The delivery log.
 *
 * One document per reminder, keyed by the appointment id, which makes the
 * whole sweep idempotent: re-running it finds the existing document and does
 * not send again.
 *
 * Written only by Cloud Functions. The Flutter client used to write these too,
 * with millisecond integers where the server wrote Timestamps and 0/1 where it
 * wrote booleans, so the same field had different types depending on who
 * touched the document last and no ordering or range query on it was safe.
 */

export const LOGS_COLLECTION = "whatsapp_notification_logs";

export type LogStatus =
  | "pending"
  | "sent"
  | "delivered"
  | "read"
  | "failed"
  | "skipped";

/**
 * How far a status may move. Meta does not guarantee the order delivery
 * receipts arrive in, and a late "sent" arriving after "read" must not drag
 * the log backwards and tell the doctor less than they already knew.
 */
const RANK: Record<LogStatus, number> = {
  skipped: -1,
  pending: 0,
  sent: 1,
  delivered: 2,
  read: 3,
  failed: 1,
};

export interface ReminderLogSeed {
  appointmentId: string;
  doctorId: string;
  patientId?: string | null;
  recipientPhone: string;
  recipientName: string;
  clinicName: string;
  scheduledStart: Date;
}

/**
 * Claims an appointment for sending.
 *
 * Returns false when another run already handled it. The check and the write
 * happen in one transaction: the previous implementation read first and wrote
 * after, so two overlapping runs could both decide to send.
 */
export async function claimReminder(seed: ReminderLogSeed): Promise<boolean> {
  const db = getDb();
  const ref = db.collection(LOGS_COLLECTION).doc(seed.appointmentId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);

    if (snap.exists) {
      const data = snap.data() || {};
      const status = data.status as LogStatus | undefined;

      // Already away, or deliberately not sent.
      if (status && ["sent", "delivered", "read", "skipped"].includes(status)) {
        return false;
      }

      // A run that died mid-send leaves "pending". Allow a retake after the
      // lease, so one crashed invocation does not silence the reminder.
      if (status === "pending") {
        const started = (data.attemptedAt as admin.firestore.Timestamp)
          ?.toMillis?.() ?? 0;
        if (Date.now() - started < 5 * 60 * 1000) return false;
      }

      // "failed" falls through: one retry on the next run is intended.
      const attempts = (data.attemptCount as number) || 0;
      if (status === "failed" && attempts >= 2) return false;
    }

    tx.set(ref, {
      appointmentId: seed.appointmentId,
      doctorId: seed.doctorId,
      patientId: seed.patientId ?? null,
      recipientPhone: seed.recipientPhone,
      recipientName: seed.recipientName,
      clinicName: seed.clinicName,
      scheduledStart: admin.firestore.Timestamp.fromDate(seed.scheduledStart),
      kind: "day_before_reminder",
      status: "pending",
      attemptCount: admin.firestore.FieldValue.increment(1),
      attemptedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return true;
  });
}

export async function markSent(
  appointmentId: string,
  messageId: string,
): Promise<void> {
  await getDb().collection(LOGS_COLLECTION).doc(appointmentId).set({
    status: "sent",
    whatsappMessageId: messageId,
    failureReason: null,
    sentAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  // Delivery receipts name the message, not the appointment, so the id has to
  // be resolvable back to this document.
  await getDb().collection(MESSAGE_INDEX_COLLECTION).doc(messageId).set({
    appointmentId,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

export async function markFailed(
  appointmentId: string,
  reason: string,
  code?: number,
): Promise<void> {
  await getDb().collection(LOGS_COLLECTION).doc(appointmentId).set({
    status: "failed",
    failureReason: reason.slice(0, 500),
    failureCode: code ?? null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

/**
 * Records a reminder that was deliberately not sent.
 *
 * Skips are logged as carefully as sends. "Why did my patient not get a
 * reminder" is the question this system has to be able to answer.
 */
export async function logSkipped(params: {
  appointmentId: string;
  doctorId: string;
  patientId?: string | null;
  recipientPhone?: string | null;
  recipientName?: string | null;
  reason: string;
}): Promise<void> {
  await getDb().collection(LOGS_COLLECTION).doc(params.appointmentId).set({
    appointmentId: params.appointmentId,
    doctorId: params.doctorId,
    patientId: params.patientId ?? null,
    recipientPhone: params.recipientPhone ?? null,
    recipientName: params.recipientName ?? null,
    kind: "day_before_reminder",
    status: "skipped",
    failureReason: params.reason,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

export const MESSAGE_INDEX_COLLECTION = "whatsapp_message_index";

/**
 * Applies a delivery receipt.
 *
 * Only moves the status forward, and keeps every raw event in a subcollection
 * whether or not it won, so an out-of-order sequence can still be reconstructed
 * when someone asks what happened.
 */
export async function applyStatusEvent(params: {
  messageId: string;
  status: LogStatus;
  at: Date;
  errorCode?: number;
  errorTitle?: string;
}): Promise<"applied" | "ignored" | "unknown_message"> {
  const db = getDb();

  const indexSnap = await db
    .collection(MESSAGE_INDEX_COLLECTION)
    .doc(params.messageId)
    .get();

  if (!indexSnap.exists) return "unknown_message";

  const appointmentId = indexSnap.data()?.appointmentId as string | undefined;
  if (!appointmentId) return "unknown_message";

  const ref = db.collection(LOGS_COLLECTION).doc(appointmentId);

  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return "unknown_message" as const;

    const current = (snap.data()?.status as LogStatus) || "pending";
    const incoming = params.status;

    const moveForward =
      RANK[incoming] > RANK[current] ||
      // A failure is worth recording while the message is still only "sent",
      // but never after the patient has already read it.
      (incoming === "failed" && RANK[current] <= RANK.sent);

    if (!moveForward) return "ignored" as const;

    const update: Record<string, unknown> = {
      status: incoming,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (incoming === "delivered") {
      update.deliveredAt = admin.firestore.Timestamp.fromDate(params.at);
    } else if (incoming === "read") {
      update.readAt = admin.firestore.Timestamp.fromDate(params.at);
    } else if (incoming === "failed") {
      update.failureReason = params.errorTitle || "delivery_failed";
      update.failureCode = params.errorCode ?? null;
    }

    tx.set(ref, update, {merge: true});
    return "applied" as const;
  });

  await ref.collection("events").add({
    status: params.status,
    at: admin.firestore.Timestamp.fromDate(params.at),
    errorCode: params.errorCode ?? null,
    errorTitle: params.errorTitle ?? null,
    outcome: result,
    receivedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return result;
}

/** The clinic a phone number last heard from, for the auto-reply. */
export async function lastClinicFor(
  phone: string,
): Promise<{clinicName?: string; doctorId?: string} | null> {
  const snap = await getDb()
    .collection(LOGS_COLLECTION)
    .where("recipientPhone", "==", phone)
    .orderBy("createdAt", "desc")
    .limit(1)
    .get();

  if (snap.empty) return null;
  const data = snap.docs[0].data();
  return {clinicName: data.clinicName, doctorId: data.doctorId};
}
