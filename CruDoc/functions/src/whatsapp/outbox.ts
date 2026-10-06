import * as admin from "firebase-admin";
import {getDb} from "./db";

/**
 * The WhatsApp send queue.
 *
 * Every message goes through here rather than straight to Meta, because a send
 * can be impossible for reasons that resolve on their own: the clinic has not
 * connected their number yet, a template is still awaiting Meta's approval, or
 * Meta returned a transient error. Nothing in CruDoc falls back to opening the
 * WhatsApp app, so a message that cannot go now has to wait and go later.
 *
 * A queued row is therefore a promise to the doctor: they pressed send once,
 * and it leaves as soon as it can without them thinking about it again.
 */

export const OUTBOX_COLLECTION = "whatsapp_outbox";

/** Transient failures are retried this many times before giving up. */
const MAX_ATTEMPTS = 5;

/** First retry waits this long; each later one doubles, up to the cap. */
const BASE_BACKOFF_MS = 30_000;
const MAX_BACKOFF_MS = 60 * 60 * 1000;

/** How long a worker may hold a row before another may take it over. */
const CLAIM_LEASE_MS = 120_000;

export type OutboxState =
  | "queued"
  | "sending"
  | "sent"
  | "failed"
  /** The clinic has not connected a WhatsApp number yet. */
  | "blocked_tenant"
  /** The template is pending Meta approval, or was rejected. */
  | "blocked_template"
  /** The recipient asked to stop receiving messages. */
  | "blocked_optout";

/** Blocked rows wait for a world change rather than a timer. */
export const BLOCKED_STATES: OutboxState[] = [
  "blocked_tenant",
  "blocked_template",
  "blocked_optout",
];

export type OutboxKind =
  | "confirmation"
  | "reminder"
  | "reschedule"
  | "cancellation"
  | "invoice"
  | "prescription"
  | "report"
  | "recall"
  | "payment"
  | "followup"
  | "postop"
  | "critical"
  | "referral"
  | "lab"
  | "campaign";

export interface OutboxRow {
  id: string;
  doctorId: string;
  toPhone: string;
  patientId?: string | null;
  templateKey: string;
  params: Record<string, string>;
  documentStoragePath?: string | null;
  documentFilename?: string | null;
  kind: OutboxKind;
  state: OutboxState;
  attempts: number;
  nextAttemptAt?: admin.firestore.Timestamp | null;
  leaseExpiresAt?: admin.firestore.Timestamp | null;
  lastErrorCode?: number | string | null;
  lastError?: string | null;
  wamid?: string | null;
}

export interface EnqueueParams {
  doctorId: string;
  toPhone: string;
  templateKey: string;
  params: Record<string, string>;
  kind: OutboxKind;
  patientId?: string;
  documentStoragePath?: string;
  documentFilename?: string;
  /**
   * Makes the enqueue idempotent. Becomes the document id, so the same logical
   * message enqueued twice — a double-tap, a retried trigger, an appointment
   * document re-synced from a device — only ever sends once.
   */
  dedupeKey?: string;
  /** Hold the row rather than sending immediately (used by reminders). */
  notBefore?: Date;
}

export interface EnqueueResult {
  id: string;
  /** False when a row with this dedupeKey already existed. */
  created: boolean;
}

function backoffMs(attempts: number): number {
  return Math.min(BASE_BACKOFF_MS * Math.pow(2, attempts), MAX_BACKOFF_MS);
}

/** Doc ids may not contain "/", and stay readable for support. */
function sanitiseId(key: string): string {
  return key.replace(/[^A-Za-z0-9_.-]/g, "_").slice(0, 400);
}

/**
 * Adds a message to the queue.
 *
 * Does not send: the worker picks the row up. Callers are UI actions and
 * triggers, so this stays cheap and never throws on a duplicate.
 */
export async function enqueueWhatsApp(
  params: EnqueueParams,
): Promise<EnqueueResult> {
  const db = getDb();
  const id = params.dedupeKey ?
    sanitiseId(params.dedupeKey) :
    db.collection(OUTBOX_COLLECTION).doc().id;
  const ref = db.collection(OUTBOX_COLLECTION).doc(id);

  const row = {
    id,
    doctorId: params.doctorId,
    toPhone: params.toPhone,
    patientId: params.patientId ?? null,
    templateKey: params.templateKey,
    params: params.params,
    documentStoragePath: params.documentStoragePath ?? null,
    documentFilename: params.documentFilename ?? null,
    kind: params.kind,
    state: "queued" as OutboxState,
    attempts: 0,
    nextAttemptAt: params.notBefore ?
      admin.firestore.Timestamp.fromDate(params.notBefore) :
      admin.firestore.Timestamp.now(),
    leaseExpiresAt: null,
    lastErrorCode: null,
    lastError: null,
    wamid: null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  try {
    await ref.create(row);
    return {id, created: true};
  } catch (err) {
    // 6 = ALREADY_EXISTS. The message is already queued or already sent, which
    // is exactly what a dedupe key is for.
    const code = (err as {code?: number})?.code;
    if (code === 6) return {id, created: false};
    throw err;
  }
}

/**
 * Takes ownership of a row so two workers cannot send it at once.
 *
 * The lease matters because the fast path (a Firestore trigger) and the slow
 * path (the retry sweep) can reach the same row at the same moment.
 */
export async function claim(id: string): Promise<OutboxRow | null> {
  const db = getDb();
  const ref = db.collection(OUTBOX_COLLECTION).doc(id);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return null;
    const data = snap.data() as OutboxRow;

    if (data.state === "sent") return null;
    if (data.state === "sending") {
      const lease = data.leaseExpiresAt?.toMillis?.() ?? 0;
      if (lease > Date.now()) return null; // someone else holds it
    }
    if (BLOCKED_STATES.includes(data.state)) return null;
    if (data.state === "failed" && data.attempts >= MAX_ATTEMPTS) return null;

    const due = data.nextAttemptAt?.toMillis?.() ?? 0;
    if (due > Date.now()) return null; // not due yet

    tx.update(ref, {
      state: "sending",
      leaseExpiresAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + CLAIM_LEASE_MS,
      ),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {...data, id, state: "sending" as OutboxState};
  });
}

export async function markSent(id: string, wamid: string): Promise<void> {
  await getDb().collection(OUTBOX_COLLECTION).doc(id).update({
    state: "sent",
    wamid,
    leaseExpiresAt: null,
    lastError: null,
    lastErrorCode: null,
    sentAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/**
 * Records a transient failure and schedules the next attempt, or gives up once
 * the attempt budget is spent.
 */
export async function markRetryable(
  id: string,
  error: string,
  errorCode?: number | string,
): Promise<void> {
  const db = getDb();
  const ref = db.collection(OUTBOX_COLLECTION).doc(id);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return;
    const attempts = ((snap.data()?.attempts as number) || 0) + 1;
    const exhausted = attempts >= MAX_ATTEMPTS;

    tx.update(ref, {
      state: exhausted ? "failed" : "queued",
      attempts,
      leaseExpiresAt: null,
      nextAttemptAt: exhausted ?
        null :
        admin.firestore.Timestamp.fromMillis(Date.now() + backoffMs(attempts)),
      lastError: error.slice(0, 500),
      lastErrorCode: errorCode ?? null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

/** A failure that retrying cannot fix, such as an invalid recipient. */
export async function markFailed(
  id: string,
  error: string,
  errorCode?: number | string,
): Promise<void> {
  await getDb().collection(OUTBOX_COLLECTION).doc(id).update({
    state: "failed",
    leaseExpiresAt: null,
    nextAttemptAt: null,
    lastError: error.slice(0, 500),
    lastErrorCode: errorCode ?? null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/**
 * Parks a row until the world changes — the clinic connects, or Meta approves
 * the template. No timer: {@link releaseBlocked} wakes these rows.
 */
export async function markBlocked(
  id: string,
  state: Extract<OutboxState, "blocked_tenant" | "blocked_template" | "blocked_optout">,
  reason: string,
): Promise<void> {
  await getDb().collection(OUTBOX_COLLECTION).doc(id).update({
    state,
    leaseExpiresAt: null,
    nextAttemptAt: null,
    lastError: reason.slice(0, 500),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/**
 * Re-queues a clinic's parked messages after the blocker clears.
 *
 * This is what makes the promise good: connecting a number, or a template
 * turning approved, drains everything that was waiting on it.
 */
export async function releaseBlocked(params: {
  doctorId: string;
  state: OutboxState;
  templateKey?: string;
  limit?: number;
}): Promise<number> {
  const db = getDb();
  let q = db
    .collection(OUTBOX_COLLECTION)
    .where("doctorId", "==", params.doctorId)
    .where("state", "==", params.state);

  if (params.templateKey) {
    q = q.where("templateKey", "==", params.templateKey);
  }

  const snap = await q.limit(params.limit ?? 500).get();
  if (snap.empty) return 0;

  const batch = db.batch();
  for (const d of snap.docs) {
    batch.update(d.ref, {
      state: "queued",
      // Give the blocker a moment to settle before the sweep picks these up.
      nextAttemptAt: admin.firestore.Timestamp.fromMillis(Date.now() + 5_000),
      attempts: 0,
      lastError: null,
      lastErrorCode: null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  return snap.size;
}

/**
 * Rows due to be sent, oldest first.
 *
 * Also picks up rows whose lease expired while a worker was mid-send — a
 * function timing out must not strand a message.
 */
export async function dueRows(limit = 100): Promise<OutboxRow[]> {
  const db = getDb();
  const now = admin.firestore.Timestamp.now();

  const [queued, stalled] = await Promise.all([
    db
      .collection(OUTBOX_COLLECTION)
      .where("state", "==", "queued")
      .where("nextAttemptAt", "<=", now)
      .orderBy("nextAttemptAt")
      .limit(limit)
      .get(),
    db
      .collection(OUTBOX_COLLECTION)
      .where("state", "==", "sending")
      .where("leaseExpiresAt", "<=", now)
      .orderBy("leaseExpiresAt")
      .limit(limit)
      .get(),
  ]);

  const rows = new Map<string, OutboxRow>();
  for (const d of [...queued.docs, ...stalled.docs]) {
    rows.set(d.id, {...(d.data() as OutboxRow), id: d.id});
  }
  return [...rows.values()];
}
