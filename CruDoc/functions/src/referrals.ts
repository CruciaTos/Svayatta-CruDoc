import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
// Imported directly for the same reason as in clinic.ts: the Functions
// emulator's bound admin.firestore drops these statics.
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import * as crypto from "crypto";
import {loadCaller, requirePerm, normalizeContactPhone} from "./clinic";
import {decryptProfileField} from "./crypto/profileCipher";
import {encryptField, getPepper, patientKekPepperSecret} from "./crypto/patientCipher";
import {ensureCrudocId, formatCrudocId, resolveCrudocId, spend} from "./crudoc-id";

// spend lives in crudoc-id.ts (clinic.ts needs it too, and referrals.ts
// imports clinic.ts); re-exported for the modules that import it from here.
export {spend};

/**
 * Referrals between doctors who both use CruDoc.
 *
 * A referral the app keeps today is a `dental_records` row in the sender's
 * own clinic, encrypted with that clinic's key, so no other account can see
 * it. Sending one to another doctor makes a copy in `referral_shares/{id}`:
 * readable by exactly two people (the sender and the recipient, see
 * firestore.rules), written only here. Neither doctor gets any access to the
 * other's clinic or patient records.
 *
 * The free-text fields of a share (patient name and phone, reason, findings,
 * question, reply, history notes) are encrypted like patient fields, with a
 * key derived from the share id and the app pepper, so they are not readable
 * in the Firebase console. The app derives the same key
 * (EncryptionKeyManager.shareKey); keep the two in step.
 *
 * Who can be found: a saved contact's phone or verified email is matched to
 * a CruDoc account, unless its owner turned off being found (the same
 * `users/{uid}.discoverable` the clinic invites use). Doctors who opt in are
 * also listed in `doctor_directory`, searchable by name, @handle, specialty
 * and city. Anyone can be found by their exact CruDoc ID. Any doctor found
 * one of these ways can receive a referral; staff accounts and clinic
 * managers who don't treat patients never can.
 */

export const SHARES = "referral_shares";
export const DIRECTORY = "doctor_directory";
export const HANDLES = "doctor_handles";
/** Storage folder the app uploads attachments to: <root>/<uid>/<shareId>/<name>. */
export const UPLOAD_ROOT = "referral_uploads";

/** How many contacts one matchContacts call may carry. */
export const MATCH_PER_CALL = 500;
/** How many phone numbers and emails one person may check per hour. */
export const MATCH_PER_HOUR = 2000;
/** How many referrals one doctor may send per day. */
export const SENDS_PER_DAY = 100;
export const MAX_ATTACHMENTS = 10;
/** Keep in sync with the referral_uploads rule in storage.rules. */
export const MAX_ATTACHMENT_BYTES = 15 * 1024 * 1024;
export const ATTACHMENT_TYPES = [
  "application/pdf",
  "image/jpeg",
  "image/png",
  "image/webp",
  "application/dicom",
];
/** How long an attachment link stays valid. */
export const ATTACHMENT_URL_MINUTES = 10;

export const URGENCIES = ["routine", "soon", "urgent"];
export const OPEN_STATUSES = ["sent", "acknowledged", "seen"];

export type Party = "sender" | "recipient";

/**
 * What each party may do to a share, from which statuses, and the status it
 * leaves. `to: null` keeps the status (a reply on its own).
 */
export const ACTIONS: Record<string, {by: Party; from: string[]; to: string | null}> = {
  accept: {by: "recipient", from: ["sent"], to: "acknowledged"},
  seen: {by: "recipient", from: ["sent", "acknowledged"], to: "seen"},
  complete: {by: "recipient", from: ["sent", "acknowledged", "seen"], to: "completed"},
  decline: {by: "recipient", from: ["sent", "acknowledged"], to: "declined"},
  reply: {by: "recipient", from: ["sent", "acknowledged", "seen", "completed"], to: null},
  withdraw: {by: "sender", from: ["sent", "acknowledged", "seen"], to: "withdrawn"},
};

/** The status [action] by [party] leaves a share in [current]; throws when not allowed. */
export function nextStatus(current: string, action: string, party: Party): string {
  const rule = ACTIONS[action];
  if (!rule) {
    throw new HttpsError("invalid-argument", "Unknown referral action.");
  }
  if (rule.by !== party) {
    throw new HttpsError("permission-denied",
      party === "sender" ?
        "Only the doctor you referred to can do that." :
        "Only the referring doctor can do that.");
  }
  if (!rule.from.includes(current)) {
    throw new HttpsError("failed-precondition",
      `This referral is ${current}; it can't be changed that way any more.`);
  }
  return rule.to ?? current;
}

/** The key a share's text fields are encrypted with. Mirrors the app. */
export function shareKey(shareId: string, pepper: string): Buffer {
  return crypto.createHash("sha256")
    .update(`referral-share::${shareId}::${pepper}`, "utf8")
    .digest();
}

/** A trimmed string of at most [max] characters; "" when absent. */
export function cleanText(value: unknown, max: number, field: string): string {
  if (value === undefined || value === null) return "";
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be text.`);
  }
  const v = value.trim();
  if (v.length > max) {
    throw new HttpsError("invalid-argument", `${field} is too long (at most ${max} characters).`);
  }
  return v;
}

/**
 * A directory handle: 3-30 of a-z, 0-9, dot and underscore, not starting or
 * ending with a dot or underscore, no "..". A leading @ is dropped.
 */
export function normalizeHandle(raw: unknown): string {
  const h = String(raw ?? "").trim().replace(/^@/, "").toLowerCase();
  if (!/^[a-z0-9][a-z0-9._]{1,28}[a-z0-9]$/.test(h) || h.includes("..")) {
    throw new HttpsError("invalid-argument",
      "A handle is 3-30 letters, numbers, dots or underscores, like dr.smit_patil.");
  }
  return h;
}

/** Lower-case words of [s], with "dr" and punctuation dropped. */
function words(s: string): string[] {
  return s.toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((w) => w.length > 0 && w !== "dr");
}

/**
 * What a directory search can match: every prefix (2 to 15 characters) of
 * each word of the name, handle, specialty and city. Firestore has no text
 * search, so the app queries `searchTokens array-contains <typed word>`.
 */
export function searchTokens(card: {
  displayName?: string; handle?: string; specialty?: string; city?: string;
}): string[] {
  const out = new Set<string>();
  const sources = [
    ...words(card.displayName ?? ""),
    ...words(card.specialty ?? ""),
    ...words(card.city ?? ""),
  ];
  const handle = (card.handle ?? "").toLowerCase();
  if (handle) sources.push(handle, ...words(handle));
  for (const w of sources) {
    for (let n = 2; n <= Math.min(w.length, 15); n++) out.add(w.slice(0, n));
  }
  return [...out].slice(0, 120);
}

/**
 * Whether `users/{uid}` belongs to someone who treats patients: not a Super
 * Admin, not a clinic staff account. A clinic owner set up as a manager is
 * ruled out separately (that needs the clinic document).
 */
export function isDoctorProfile(u: Record<string, unknown> | undefined): boolean {
  if (!u) return false;
  if (u.role !== undefined && u.role !== null && u.role !== "doctor") return false;
  if (u.memberKind === "staff") return false;
  return true;
}

export interface DoctorCard {
  uid: string;
  displayName: string;
  specialty: string;
  clinicName: string;
  city: string;
  handle: string;
  listed: boolean;
  discoverable: boolean;
}

function cardJson(c: DoctorCard): Record<string, unknown> {
  return {
    uid: c.uid,
    name: c.displayName,
    specialty: c.specialty,
    clinicName: c.clinicName,
    city: c.city,
    handle: c.handle,
  };
}

/**
 * The doctor behind [uid], or null when there is none (no profile, a staff
 * account, a manager-owner). The directory card, if they made one, wins over
 * the profile: it is what they chose to show other doctors.
 */
export async function loadDoctor(uid: string): Promise<DoctorCard | null> {
  const db = admin.firestore();
  const [userSnap, dirSnap] = await Promise.all([
    db.collection("users").doc(uid).get(),
    db.collection(DIRECTORY).doc(uid).get(),
  ]);
  const u = userSnap.data();
  if (!userSnap.exists || !isDoctorProfile(u)) return null;
  if (u?.memberKind === "owner") {
    const clinic = await db.collection("clinics").doc(uid).get();
    if (clinic.data()?.ownerIsDoctor === false) return null;
  }
  const dir = dirSnap.data() || {};
  const profileName = decryptProfileField(u?.name, uid) ||
    decryptProfileField(u?.displayName, uid);
  const profileSpecialty = (typeof u?.specialty === "string" ? u.specialty.trim() : "") ||
    decryptProfileField(u?.specialization, uid);
  return {
    uid,
    displayName: String(dir.displayName || profileName || "Doctor"),
    specialty: String(dir.specialty || profileSpecialty || ""),
    clinicName: String(dir.clinicName || decryptProfileField(u?.clinicName, uid) || ""),
    city: String(dir.city || ""),
    handle: String(dir.handle || ""),
    listed: dir.listed === true,
    discoverable: u?.discoverable !== false,
  };
}

const DEAD_TOKEN_CODES = [
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
  "messaging/invalid-argument",
];

/**
 * A push notification to every device [uid] signed in on (Android, iOS).
 * Never says anything about the patient: it shows on a lock screen. Never
 * throws: a referral is sent whether or not the push gets through, and the
 * app shows it the next time it opens either way. [channelId] is an Android
 * channel the app creates (push_notifications.dart).
 */
export async function pushTo(uid: string, title: string, body: string,
  data: Record<string, string>, channelId = "referrals"): Promise<void> {
  try {
    const col = admin.firestore().collection("users").doc(uid).collection("device_tokens");
    const snap = await col.get();
    const docs = snap.docs.filter((d) => typeof d.data()?.token === "string");
    if (docs.length === 0) return;
    const res = await admin.messaging().sendEachForMulticast({
      tokens: docs.map((d) => d.data().token as string),
      notification: {title, body},
      data,
      android: {priority: "high", notification: {channelId}},
      apns: {payload: {aps: {sound: "default"}}},
    });
    await Promise.all(res.responses.map((r, i) =>
      !r.success && DEAD_TOKEN_CODES.includes(r.error?.code ?? "") ?
        docs[i].ref.delete() : Promise.resolve()));
  } catch (err) {
    console.warn(`[referrals] push to ${uid} failed`, err);
  }
}

/** "Dr. Smit Patil" for a card name, without doubling an existing "Dr". */
export function drName(name: string): string {
  const n = name.trim() || "Doctor";
  return /^dr\.?\s/i.test(n) ? n : `Dr. ${n}`;
}

const PUSH_TEXT: Record<string, (who: string) => string> = {
  accept: (who) => `${who} accepted your referral`,
  seen: (who) => `${who} has seen your patient`,
  complete: (who) => `${who} completed your referral`,
  decline: (who) => `${who} declined your referral`,
  reply: (who) => `${who} replied to your referral`,
  withdraw: (who) => `${who} withdrew a referral`,
};

function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
  return uid;
}

/** An attachment's file name: no folders, no "..", nothing odd. */
export function cleanFileName(raw: unknown): string {
  const name = typeof raw === "string" ? raw.trim() : "";
  const hasControl = [...name].some((ch) => ch.charCodeAt(0) < 0x20);
  if (!name || name.length > 120 || /[/\\]/.test(name) || name.includes("..") || hasControl) {
    throw new HttpsError("invalid-argument", "An attachment has an invalid file name.");
  }
  return name;
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

async function matchContacts(request: CallableRequest) {
  const data = request.data || {};
  const clinicId = String(data.clinicId ?? "").trim();
  const caller = await loadCaller(request, clinicId);
  requirePerm(caller, "clinical.view");

  if (!Array.isArray(data.contacts)) {
    throw new HttpsError("invalid-argument", "contacts must be a list.");
  }
  if (data.contacts.length > MATCH_PER_CALL) {
    throw new HttpsError("invalid-argument", `Send at most ${MATCH_PER_CALL} contacts at a time.`);
  }

  // identifier ("p:+91..." / "e:a@b.c") -> contact ids that carry it.
  const byKey = new Map<string, string[]>();
  const add = (key: string, id: string) => {
    const list = byKey.get(key) ?? [];
    if (!list.includes(id)) list.push(id);
    byKey.set(key, list);
  };
  for (const c of data.contacts as unknown[]) {
    if (!c || typeof c !== "object") continue;
    const {id, phone, email} = c as Record<string, unknown>;
    if (typeof id !== "string" || !id || id.length > 128) continue;
    const e164 = normalizeContactPhone(phone);
    if (e164) add(`p:${e164}`, id);
    const mail = typeof email === "string" ? email.trim().toLowerCase() : "";
    if (mail && EMAIL_RE.test(mail) && mail.length <= 254) add(`e:${mail}`, id);
  }
  if (byKey.size === 0) return {matches: []};

  await spend(caller.uid, "matchReferralContacts", byKey.size, MATCH_PER_HOUR, 3600_000,
    "That's a lot of contacts in one go. Try again in an hour.");

  const keys = [...byKey.keys()];
  const found = new Map<string, string>(); // identifier -> uid
  for (let i = 0; i < keys.length; i += 100) {
    const chunk = keys.slice(i, i + 100).map((k) =>
      k.startsWith("p:") ? {phoneNumber: k.slice(2)} : {email: k.slice(2)});
    const res = await admin.auth().getUsers(chunk);
    for (const u of res.users) {
      if (u.uid === caller.uid) continue;
      if (u.phoneNumber && byKey.has(`p:${u.phoneNumber}`)) found.set(`p:${u.phoneNumber}`, u.uid);
      // An unverified email proves nothing: anyone could sign up with
      // someone else's address and receive their referrals.
      const mail = (u.email ?? "").toLowerCase();
      if (mail && u.emailVerified === true && byKey.has(`e:${mail}`)) found.set(`e:${mail}`, u.uid);
    }
  }
  if (found.size === 0) return {matches: []};

  const cards = new Map<string, DoctorCard | null>();
  await Promise.all([...new Set(found.values())].map(async (uid) => {
    cards.set(uid, await loadDoctor(uid));
  }));

  // One match per contact; a phone match is preferred to an email one.
  const byContact = new Map<string, DoctorCard>();
  for (const prefix of ["p:", "e:"]) {
    for (const [key, uid] of found) {
      if (!key.startsWith(prefix)) continue;
      const card = cards.get(uid);
      if (!card || !card.discoverable) continue;
      for (const id of byKey.get(key) ?? []) {
        if (!byContact.has(id)) byContact.set(id, card);
      }
    }
  }
  return {
    matches: [...byContact.entries()].map(([id, card]) => ({id, ...cardJson(card)})),
  };
}

async function saveDirectoryProfile(request: CallableRequest) {
  const uid = requireUid(request);
  const data = request.data || {};
  const db = admin.firestore();
  const me = await loadDoctor(uid);
  if (!me) {
    throw new HttpsError("permission-denied", "Only doctors can be listed in the directory.");
  }

  const listed = data.listed === true;
  const handle = data.handle ? normalizeHandle(data.handle) : "";
  const displayName = cleanText(data.displayName, 80, "Name");
  const specialty = cleanText(data.specialty, 80, "Specialty");
  const city = cleanText(data.city, 60, "City");
  const clinicName = cleanText(data.clinicName, 100, "Clinic name");
  if (listed && (!handle || !displayName)) {
    throw new HttpsError("invalid-argument", "Add your name and a handle to be listed.");
  }

  const dirRef = db.collection(DIRECTORY).doc(uid);
  await db.runTransaction(async (tx) => {
    const current = await tx.get(dirRef);
    const oldHandle = String(current.data()?.handle || "");
    const claim = handle ? await tx.get(db.collection(HANDLES).doc(handle)) : null;
    if (claim?.exists && claim.data()?.uid !== uid) {
      throw new HttpsError("already-exists", "That handle is taken. Try another.");
    }
    if (oldHandle && oldHandle !== handle) tx.delete(db.collection(HANDLES).doc(oldHandle));
    if (handle) tx.set(db.collection(HANDLES).doc(handle), {uid});
    tx.set(dirRef, {
      uid,
      listed,
      handle,
      displayName,
      specialty,
      city,
      clinicName,
      searchTokens: listed ? searchTokens({displayName, handle, specialty, city}) : [],
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return {handle, listed};
}

async function send(request: CallableRequest) {
  const data = request.data || {};
  const db = admin.firestore();
  const clinicId = String(data.clinicId ?? "").trim();
  const caller = await loadCaller(request, clinicId);
  // Sending a referral hands clinical details to someone outside the clinic.
  requirePerm(caller, "clinical.view");

  if (data.consent !== true) {
    throw new HttpsError("failed-precondition",
      "Confirm the patient agreed to share their details with the other doctor.");
  }
  const shareId = String(data.shareId ?? "");
  if (!/^[A-Za-z0-9_-]{10,64}$/.test(shareId)) {
    throw new HttpsError("invalid-argument", "shareId is missing or invalid.");
  }
  const recipientUid = String(data.recipientUid ?? "").trim();
  if (!recipientUid) throw new HttpsError("invalid-argument", "Choose who to refer to.");
  if (recipientUid === caller.uid) {
    throw new HttpsError("invalid-argument", "You can't refer a patient to yourself.");
  }

  const [sender, recipient] = await Promise.all([loadDoctor(caller.uid), loadDoctor(recipientUid)]);
  if (!sender) {
    throw new HttpsError("permission-denied", "Only doctors can send referrals.");
  }
  // Any doctor on CruDoc can take a referral: the uid only ever comes from a
  // contact match, the directory or their exact CruDoc ID.
  if (!recipient) {
    throw new HttpsError("not-found",
      "That doctor can't receive referrals in CruDoc. Send it on WhatsApp or email instead.");
  }

  const p = (data.patient && typeof data.patient === "object" ? data.patient : {}) as
    Record<string, unknown>;
  const patientName = cleanText(p.name, 120, "Patient name");
  if (!patientName) throw new HttpsError("invalid-argument", "The patient's name is required.");
  const age = typeof p.age === "number" && Number.isInteger(p.age) && p.age >= 0 && p.age <= 150 ?
    p.age : null;
  const reason = cleanText(data.reason, 300, "Reason");
  if (!reason) throw new HttpsError("invalid-argument", "Give a reason for the referral.");
  const urgency = URGENCIES.includes(String(data.urgency)) ? String(data.urgency) : "routine";
  const teeth = Array.isArray(data.teeth) ?
    (data.teeth as unknown[]).slice(0, 32).map((t) => cleanText(String(t), 4, "Tooth")).filter(Boolean) :
    [];

  const rawFiles = Array.isArray(data.attachments) ? data.attachments as unknown[] : [];
  if (rawFiles.length > MAX_ATTACHMENTS) {
    throw new HttpsError("invalid-argument", `Attach at most ${MAX_ATTACHMENTS} files.`);
  }
  // Each file must already be uploaded, by this doctor, for this share.
  const bucket = admin.storage().bucket();
  const attachments = await Promise.all(rawFiles.map(async (f) => {
    const name = cleanFileName((f as Record<string, unknown>)?.name);
    const path = `${UPLOAD_ROOT}/${caller.uid}/${shareId}/${name}`;
    const file = bucket.file(path);
    const [exists] = await file.exists();
    if (!exists) {
      throw new HttpsError("failed-precondition", `"${name}" didn't finish uploading. Try again.`);
    }
    const [meta] = await file.getMetadata();
    const size = Number(meta.size || 0);
    const contentType = String(meta.contentType || "");
    if (size > MAX_ATTACHMENT_BYTES || !ATTACHMENT_TYPES.includes(contentType)) {
      throw new HttpsError("invalid-argument", `"${name}" can't be attached.`);
    }
    return {name, path, size, contentType};
  }));

  await spend(caller.uid, "referralSends", 1, SENDS_PER_DAY, 24 * 3600_000,
    "You've sent a lot of referrals today. Try again tomorrow.");

  const key = shareKey(shareId, getPepper());
  const enc = (s: string) => encryptField(s, key);
  const now = Date.now();
  const shareRef = db.collection(SHARES).doc(shareId);

  const created = await db.runTransaction(async (tx) => {
    const existing = await tx.get(shareRef);
    if (existing.exists) {
      // A retry of a send that already went through.
      if (existing.data()?.senderUid === caller.uid) return false;
      throw new HttpsError("already-exists", "Try sending again.");
    }
    tx.set(shareRef, {
      senderUid: caller.uid,
      senderClinicId: clinicId,
      senderName: sender.displayName,
      senderSpecialty: sender.specialty,
      senderClinicName: sender.clinicName,
      recipientUid,
      recipientName: recipient.displayName,
      recipientSpecialty: recipient.specialty,
      localReferralId: cleanText(data.localReferralId, 128, "Referral id"),
      status: "sent",
      urgency,
      teeth,
      patient: {
        name: enc(patientName),
        phone: enc(cleanText(p.phone, 30, "Patient phone")),
        gender: cleanText(p.gender, 20, "Gender"),
        age,
      },
      reason: enc(reason),
      findings: enc(cleanText(data.findings, 4000, "Findings")),
      question: enc(cleanText(data.question, 2000, "Question")),
      reply: "",
      attachments,
      history: [{status: "sent", at: now, by: caller.uid, note: enc("Sent through CruDoc")}],
      consentAt: Timestamp.fromMillis(now),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });

  if (created) {
    await db.collection("access_logs").add({
      doctorId: clinicId,
      actorUid: caller.uid,
      action: "referral.share",
      patientId: cleanText(data.patientId, 128, "Patient id"),
      target: shareId,
      recipientUid,
      platform: "server",
      at: FieldValue.serverTimestamp(),
    });
    const urgent = urgency === "urgent" ? "Urgent: " : "";
    await pushTo(recipientUid, `${urgent}New referral from ${drName(sender.displayName)}`,
      "Open CruDoc to see the patient and the details.", {type: "referral", shareId});
    // Not referrers yet: the referral also asks them (no second push; the
    // request shows in their notifications).
    await askReferrer(caller.uid, recipientUid, {push: false}).catch((err) =>
      console.warn("[referrals] referrer request with referral failed", err));
  }
  return {shareId};
}

async function update(request: CallableRequest) {
  const uid = requireUid(request);
  const data = request.data || {};
  const db = admin.firestore();
  const shareId = String(data.shareId ?? "");
  // What to do to it ("action" already names the callable's action).
  const action = String(data.step ?? "");
  if (!shareId) throw new HttpsError("invalid-argument", "shareId is required.");
  const note = cleanText(data.note, 1000, "Note");
  const reply = cleanText(data.reply, 8000, "Reply");
  if (action === "reply" && !reply) {
    throw new HttpsError("invalid-argument", "Write a reply first.");
  }

  const shareRef = db.collection(SHARES).doc(shareId);
  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(shareRef);
    if (!snap.exists) throw new HttpsError("not-found", "That referral no longer exists.");
    const d = snap.data() || {};
    const party: Party | null = d.senderUid === uid ? "sender" :
      d.recipientUid === uid ? "recipient" : null;
    if (!party) throw new HttpsError("permission-denied", "This isn't your referral.");
    const status = nextStatus(String(d.status), action, party);

    const key = shareKey(shareId, getPepper());
    const enc = (s: string) => encryptField(s, key);
    const history = Array.isArray(d.history) ? [...d.history] : [];
    history.push({status, at: Date.now(), by: uid, note: enc(note)});
    const changes: Record<string, unknown> = {
      status,
      history,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (reply && (action === "reply" || action === "complete")) changes.reply = enc(reply);
    if (action === "withdraw") {
      // The recipient keeps a note that it was withdrawn, and nothing about
      // the patient.
      changes.patient = {name: "", phone: "", gender: "", age: null};
      changes.findings = "";
      changes.question = "";
      changes.reply = "";
      changes.attachments = [];
    }
    tx.update(shareRef, changes);
    return {
      status,
      party,
      other: party === "sender" ? String(d.recipientUid) : String(d.senderUid),
      who: party === "sender" ? String(d.senderName || "") : String(d.recipientName || ""),
      files: action === "withdraw" && Array.isArray(d.attachments) ?
        (d.attachments as {path?: string}[]).map((a) => String(a.path || "")).filter(Boolean) : [],
    };
  });

  if (result.files.length) {
    const bucket = admin.storage().bucket();
    await Promise.all(result.files.map((p) =>
      bucket.file(p).delete().catch(() => undefined)));
  }
  await db.collection("access_logs").add({
    doctorId: uid,
    actorUid: uid,
    action: `referral.${action}`,
    target: shareId,
    platform: "server",
    at: FieldValue.serverTimestamp(),
  });
  await pushTo(result.other, PUSH_TEXT[action](drName(result.who)),
    "Open CruDoc to see the details.", {type: "referral", shareId});
  return {status: result.status};
}

async function attachmentUrl(request: CallableRequest) {
  const uid = requireUid(request);
  const data = request.data || {};
  const db = admin.firestore();
  const shareId = String(data.shareId ?? "");
  const name = cleanFileName(data.name);
  const snap = await db.collection(SHARES).doc(shareId).get();
  const d = snap.data();
  if (!snap.exists || !d || (d.senderUid !== uid && d.recipientUid !== uid)) {
    throw new HttpsError("permission-denied", "This isn't your referral.");
  }
  const file = (Array.isArray(d.attachments) ? d.attachments : [])
    .find((a: {name?: string}) => a?.name === name);
  if (!file || !file.path) {
    throw new HttpsError("not-found", "That file is no longer shared.");
  }
  const [url] = await admin.storage().bucket().file(String(file.path)).getSignedUrl({
    version: "v4",
    action: "read",
    expires: Date.now() + ATTACHMENT_URL_MINUTES * 60_000,
  });
  await db.collection("access_logs").add({
    doctorId: uid,
    actorUid: uid,
    action: "referral.attachment.view",
    target: `${shareId}/${name}`,
    platform: "server",
    at: FieldValue.serverTimestamp(),
  });
  return {url};
}

/** The caller's own CruDoc ID ("K7Q9-2XMB"), made the first time. */
async function myCrudocId(request: CallableRequest) {
  const uid = requireUid(request);
  return {crudocId: formatCrudocId(await ensureCrudocId(uid))};
}

/**
 * The person whose CruDoc ID was typed: exact match only, never a list,
 * found even when they turned off being found by phone number. `isDoctor`
 * says whether they can receive a referral.
 */
async function findByCrudocId(request: CallableRequest) {
  const uid = requireUid(request);
  const person = await resolveCrudocId(uid, request.data?.crudocId);
  const doctor = await loadDoctor(person.uid);
  if (doctor) {
    return {...cardJson(doctor), crudocId: person.crudocId, isDoctor: true};
  }
  return {
    uid: person.uid, name: person.name || "CruDoc user", specialty: "", clinicName: "",
    city: "", handle: "", crudocId: person.crudocId, isDoctor: false,
  };
}

/**
 * One callable, one action per request, like clinicTeam:
 *   matchContacts        which saved referral contacts are on CruDoc
 *   saveDirectoryProfile list (or unlist) yourself, with a unique @handle
 *   send                 send a referral to another doctor
 *   update               step: accept / seen / complete / decline / reply / withdraw
 *   attachmentUrl        a short-lived link to one attached file
 *   myCrudocId           your own CruDoc ID, made the first time
 *   findByCrudocId       the one person with a CruDoc ID you typed
 *   requestReferrer      ask a doctor to be one of your referrers
 *   answerReferrer       accept or decline a referrer request to you
 */
export const referralNetwork = onCall(
  {region: "asia-south1", maxInstances: 10, secrets: [patientKekPepperSecret]},
  async (request) => {
    requireUid(request);
    switch (String(request.data?.action ?? "")) {
    case "matchContacts": return matchContacts(request);
    case "saveDirectoryProfile": return saveDirectoryProfile(request);
    case "send": return send(request);
    case "update": return update(request);
    case "attachmentUrl": return attachmentUrl(request);
    case "myCrudocId": return myCrudocId(request);
    case "findByCrudocId": return findByCrudocId(request);
    case "requestReferrer": return requestReferrer(request);
    case "answerReferrer": return answerReferrer(request);
    default: throw new HttpsError("invalid-argument", "Unknown action.");
    }
  }
);


// ───────────────────────────── Referrer requests ─────────────────────────────

const REQUESTS = "referrer_requests";
const REQUESTS_PER_DAY = 100;

/** One request doc per pair, named by who asked: "<from>_<to>". */
function requestRef(fromUid: string, toUid: string) {
  return admin.firestore().collection(REQUESTS).doc(`${fromUid}_${toUid}`);
}

/** The card fields a request shows about one side. */
function side(prefix: string, c: DoctorCard | null, uid: string,
  crudocId: string): Record<string, string> {
  return {
    [`${prefix}Uid`]: uid,
    [`${prefix}Name`]: c?.displayName ?? "",
    [`${prefix}Specialty`]: c?.specialty ?? "",
    [`${prefix}Clinic`]: c?.clinicName ?? "",
    [`${prefix}City`]: c?.city ?? "",
    [`${prefix}CrudocId`]: crudocId,
  };
}

/**
 * Asks [toUid] to become one of [fromUid]'s referrers. Already linked
 * (either way round): nothing changes. They had asked [fromUid] first:
 * that counts as both agreeing. Returns the resulting status.
 */
export async function askReferrer(fromUid: string, toUid: string,
  opts: {push: boolean}): Promise<string> {
  const [mine, theirs] = await Promise.all([
    requestRef(fromUid, toUid).get(), requestRef(toUid, fromUid).get(),
  ]);
  if (mine.data()?.status === "accepted" || theirs.data()?.status === "accepted") {
    return "accepted";
  }
  if (theirs.data()?.status === "pending") {
    await theirs.ref.update({status: "accepted", answeredAt: FieldValue.serverTimestamp()});
    return "accepted";
  }
  if (mine.data()?.status === "pending") return "pending";
  const [from, to] = await Promise.all([loadDoctor(fromUid), loadDoctor(toUid)]);
  if (!to) {
    throw new HttpsError("failed-precondition",
      "That person isn't a doctor on CruDoc, so they can't be a referrer.");
  }
  const [fromId, toId] = await Promise.all([ensureCrudocId(fromUid), ensureCrudocId(toUid)]);
  await mine.ref.set({
    ...side("from", from, fromUid, formatCrudocId(fromId)),
    ...side("to", to, toUid, formatCrudocId(toId)),
    status: "pending",
    createdAt: FieldValue.serverTimestamp(),
    answeredAt: null,
  });
  if (opts.push) {
    await pushTo(toUid, `${drName(from?.displayName ?? "A doctor")} wants to add you as a referrer`,
      "Open CruDoc to accept or decline.", {type: "referrer_request", fromUid});
  }
  return "pending";
}

/** requestReferrer {uid}: ask that doctor to be your referrer. */
async function requestReferrer(request: CallableRequest) {
  const uid = requireUid(request);
  const to = String(request.data?.uid ?? "").trim();
  if (!to) throw new HttpsError("invalid-argument", "Choose a doctor.");
  if (to === uid) throw new HttpsError("invalid-argument", "That's you.");
  await spend(uid, "referrerRequests", 1, REQUESTS_PER_DAY, 24 * 3600_000,
    "That's a lot of requests today. Try again tomorrow.");
  return {status: await askReferrer(uid, to, {push: true})};
}

/** answerReferrer {fromUid, accept}: accept or decline a request to you. */
async function answerReferrer(request: CallableRequest) {
  const uid = requireUid(request);
  const fromUid = String(request.data?.fromUid ?? "").trim();
  const accept = request.data?.accept === true;
  const ref = requestRef(fromUid, uid);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "That request is gone.");
  if (snap.data()?.status !== "pending") return {status: snap.data()?.status};
  const status = accept ? "accepted" : "declined";
  await ref.update({status, answeredAt: FieldValue.serverTimestamp()});
  const me = await loadDoctor(uid);
  await pushTo(fromUid,
    `${drName(me?.displayName ?? "The doctor")} ${accept ? "accepted" : "declined"} your referrer request`,
    accept ? "They're now in your referrers." : "They were not added to your referrers.",
    {type: "referrer_request", toUid: uid});
  return {status};
}
