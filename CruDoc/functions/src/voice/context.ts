import * as admin from "firebase-admin";
import * as crypto from "crypto";
import {getExpectedVoiceBotKey} from "../appointments";
import {
  decryptField, encryptField, PatientKeyring, phoneIndexOf,
} from "../crypto/patientCipher";
import {decryptProfileField} from "../crypto/profileCipher";
import {normalisePhone} from "../whatsapp/format";
import {DoctorSchedule, scheduleFrom} from "./schedule";

/**
 * What every `voiceApi` route needs: who is calling, on which clinic's line,
 * with which doctors.
 *
 * The line is found from `line_id`, the clinic's AI number, which each
 * clinic's copy of the Sarvam agent sends as a fixed variable. Sarvam's tools
 * receive the caller's number but not the number that was dialled or the
 * number that forwarded the call, so the agent has to say which line it is.
 */

/** Calls included per clinic per month unless the line or usage says otherwise. */
export const DEFAULT_INCLUDED_CALLS = 20;

const AI_MODULE = "ai_agentic_calling";

export function db(): admin.firestore.Firestore {
  return admin.firestore();
}

let sharedKeyring: PatientKeyring | null = null;
function keyring(): PatientKeyring {
  sharedKeyring ??= new PatientKeyring(db());
  return sharedKeyring;
}

/**
 * A refusal the agent can read out. Routes throw it; the router turns it into
 * `{ok: false, code, say}` with HTTP 200, so Sarvam passes the sentence to the
 * model instead of treating the call as a failed request.
 */
export class VoiceError extends Error {
  constructor(
    readonly code: string,
    readonly say: string,
    readonly extra: Record<string, unknown> = {},
  ) {
    super(code);
  }
}

/** Timing-safe check of the shared `X-Api-Key`. */
export function apiKeyMatches(provided: unknown): boolean {
  const expected = getExpectedVoiceBotKey();
  if (!expected || typeof provided !== "string" || !provided) return false;
  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/**
 * Any Indian number (mobile or landline such as 080 6426 1740) as digits
 * with the country code, or null. Used for line ids, not for messaging.
 */
export function indianNumberDigits(raw: unknown): string | null {
  if (typeof raw !== "string" && typeof raw !== "number") return null;
  let digits = String(raw).replace(/\D/g, "").replace(/^0+/, "");
  if (digits.length === 10) digits = `91${digits}`;
  return digits.length === 12 && digits.startsWith("91") ? digits : null;
}

/** Sarvam interaction ids contain "/", which a document id cannot. */
export function callDocId(interactionId: string): string {
  return interactionId.replace(/[/\s]+/g, "_").slice(0, 300);
}

export function str(body: Record<string, unknown>, key: string): string {
  const v = body[key];
  if (typeof v === "string") return v.trim();
  if (typeof v === "number") return String(v);
  return "";
}

export interface Line {
  id: string;
  clinicId: string;
  doctorIds: string[];
  publishedNumber: string | null;
  status: "pending_test" | "active" | "paused";
  includedCalls: number | null;
  raw: admin.firestore.DocumentData;
}

export interface Doctor {
  id: string;
  name: string;
  schedule: DoctorSchedule;
  enabled: boolean;
}

export interface CallContext {
  now: Date;
  body: Record<string, unknown>;
  line: Line;
  clinicId: string;
  clinicName: string;
  /** The doctors this line books for, in the order the line lists them. */
  doctors: Doctor[];
  moduleEnabled: boolean;
  /** The caller's mobile, when it is a usable Indian mobile and not the doctor's own number. */
  callerPhone: string | null;
  /** True when the AI must ask the caller for their mobile number. */
  askPhone: boolean;
  /**
   * The caller id is the doctor's own published number: either the doctor's
   * setup test call, or a forwarded call where the network hid the patient.
   */
  callerIsDoctor: boolean;
  interactionId: string;
  callId: string;
}

function doctorName(id: string, data: admin.firestore.DocumentData | undefined): string {
  const raw = [data?.aiReceptionist?.announceAs, data?.displayName, data?.name, data?.fullName]
    .map((v) => decryptProfileField(v, id))
    .find((v) => v) || "";
  if (!raw) return "the doctor";
  return /^dr\.?\s/i.test(raw) ? raw : `Dr. ${raw}`;
}

function toDoctor(id: string, data: admin.firestore.DocumentData | undefined): Doctor {
  return {
    id,
    name: doctorName(id, data),
    schedule: scheduleFrom(data?.aiReceptionist),
    enabled: data?.aiReceptionist?.enabled !== false,
  };
}

export async function loadLine(lineId: string): Promise<Line | null> {
  const snap = await db().collection("voice_lines").doc(lineId).get();
  if (!snap.exists) return null;
  const d = snap.data() || {};
  const clinicId = typeof d.doctorId === "string" ? d.doctorId : "";
  if (!clinicId) return null;
  const doctorIds = Array.isArray(d.doctorIds) && d.doctorIds.length ?
    d.doctorIds.filter((x: unknown): x is string => typeof x === "string" && !!x) :
    [clinicId];
  return {
    id: snap.id,
    clinicId,
    doctorIds,
    publishedNumber: indianNumberDigits(d.publishedNumber),
    status: d.status === "active" || d.status === "paused" ? d.status : "pending_test",
    includedCalls: typeof d.includedCalls === "number" ? d.includedCalls : null,
    raw: d,
  };
}

/**
 * Builds the context, or throws `unknown_line` when the agent sent no line
 * or one CruDoc doesn't know.
 */
export async function loadContext(body: Record<string, unknown>): Promise<CallContext> {
  const lineId = indianNumberDigits(body.line_id);
  const line = lineId ? await loadLine(lineId) : null;
  if (!line) {
    throw new VoiceError(
      "unknown_line",
      "Sorry, this number is not set up yet. Please call your doctor's own number.",
    );
  }

  const userIds = [...new Set([line.clinicId, ...line.doctorIds])];
  const [clinicSnap, ...userSnaps] = await Promise.all([
    db().collection("clinics").doc(line.clinicId).get(),
    ...userIds.map((id) => db().collection("users").doc(id).get()),
  ]);
  const users = new Map(userSnaps.map((s) => [s.id, s.exists ? s.data() : undefined]));
  const owner = users.get(line.clinicId);

  const clinicName = [
    line.raw.clinicName, clinicSnap.data()?.name, owner?.clinicName, owner?.practiceName,
  ].map((v) => decryptProfileField(v, line.clinicId)).find((v) => v) || "the clinic";

  const modules: string[] = Array.isArray(owner?.enabledModules) ?
    owner.enabledModules.map((m: unknown) => String(m).toLowerCase()) :
    [];

  const caller = normalisePhone(str(body, "caller"));
  // When the phone company hides the patient's number on a forwarded call,
  // the caller id is the doctor's own number. That is not the patient.
  const callerIsDoctor = !!caller && caller === line.publishedNumber;
  const callerPhone = caller && !callerIsDoctor ? caller : null;

  const interactionId = str(body, "interaction_id") || `no-id-${Date.now()}`;

  return {
    now: new Date(),
    body,
    line,
    clinicId: line.clinicId,
    clinicName,
    doctors: line.doctorIds.map((id) => toDoctor(id, users.get(id))),
    moduleEnabled: modules.includes(AI_MODULE),
    callerPhone,
    askPhone: !callerPhone,
    callerIsDoctor,
    interactionId,
    callId: callDocId(interactionId),
  };
}

/** The caller's phone for a write: theirs, or the one they told the AI. */
export function phoneForBooking(ctx: CallContext): string {
  if (ctx.callerPhone) return ctx.callerPhone;
  const told = normalisePhone(str(ctx.body, "patient_phone"));
  if (told) return told;
  throw new VoiceError(
    "phone_required",
    "Could you please tell me your 10-digit mobile number?",
  );
}

/**
 * The caller's phone index at this clinic, or null when we don't know their
 * number. Lookups only, so it never creates a clinic key.
 */
export async function callerIndexFor(ctx: CallContext): Promise<string | null> {
  const phone = ctx.callerPhone ?? normalisePhone(str(ctx.body, "patient_phone"));
  if (!phone) return null;
  const dek = await keyring().dekFor(ctx.clinicId);
  return dek ? phoneIndexOf(phone, dek) : null;
}

export async function clinicKey(ctx: CallContext): Promise<Buffer> {
  return keyring().getOrCreateDek(ctx.clinicId);
}

export async function readableKey(ctx: CallContext): Promise<Buffer | null> {
  return keyring().dekFor(ctx.clinicId);
}

export {decryptField, encryptField, phoneIndexOf};

/**
 * The doctor the model means. Accepts the id, or a name when the model sends
 * that instead. With one doctor on the line, nothing needs to be sent.
 */
export function pickDoctor(ctx: CallContext, raw: string): Doctor {
  if (!raw) {
    if (ctx.doctors.length === 1) return ctx.doctors[0];
    throw new VoiceError(
      "doctor_required",
      `Which doctor would you like to see: ${ctx.doctors.map((d) => d.name).join(" or ")}?`,
    );
  }
  const byId = ctx.doctors.find((d) => d.id === raw);
  if (byId) return byId;
  const needle = raw.toLowerCase().replace(/^dr\.?\s*/, "").trim();
  const byName = ctx.doctors.filter((d) => d.name.toLowerCase().includes(needle));
  if (needle && byName.length === 1) return byName[0];
  if (ctx.doctors.length === 1) return ctx.doctors[0];
  throw new VoiceError(
    "doctor_not_on_line",
    `I can book with ${ctx.doctors.map((d) => d.name).join(" or ")}. Which one would you like?`,
  );
}

/** A doctor of this clinic who may not be on this line (for existing visits). */
export async function doctorById(ctx: CallContext, id: string): Promise<Doctor> {
  const onLine = ctx.doctors.find((d) => d.id === id);
  if (onLine) return onLine;
  const snap = await db().collection("users").doc(id).get();
  return toDoctor(id, snap.exists ? snap.data() : undefined);
}

/** Notes what the AI did on this call; `/call-ended` derives the outcome from it. */
export async function recordAction(
  ctx: CallContext,
  action: Record<string, unknown>,
): Promise<void> {
  await db().collection("voice_calls").doc(ctx.callId).set({
    doctorId: ctx.clinicId,
    lineId: ctx.line.id,
    interactionId: ctx.interactionId,
    actions: admin.firestore.FieldValue.arrayUnion({...action, at: ctx.now.toISOString()}),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}
