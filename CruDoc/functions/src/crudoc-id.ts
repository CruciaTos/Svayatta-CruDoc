import * as admin from "firebase-admin";
import {FieldValue} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import * as crypto from "crypto";
import {decryptProfileField} from "./crypto/profileCipher";

/**
 * CruDoc IDs: every account's permanent, unique ID ("K7Q9-2XMB"), so two
 * people can find each other without having each other's number.
 *
 * Stored as `users/{uid}.crudocId` ("K7Q92XMB", no dash) and claimed in
 * `crudoc_ids/{id}` = {uid}, which only the functions read or write (see
 * firestore.rules). Lookups are exact (no partial matches, no listing) and
 * rate-limited, so IDs can't be guessed through the app.
 *
 * An exact ID always finds its owner: sharing it is how someone asks to be
 * found. `users/{uid}.discoverable` only governs matching by phone number
 * or contacts, as its switch says.
 */

export const CRUDOC_IDS = "crudoc_ids";
export const CRUDOC_ID_LENGTH = 8;
/** How many IDs one person may look up per hour. */
export const LOOKUPS_PER_HOUR = 60;

/** Crockford base32: no I, L, O or U, so an ID reads aloud and types cleanly. */
const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

/** A new random ID like "K7Q92XMB" (32^8, about a trillion of them). */
export function newCrudocId(): string {
  const bytes = crypto.randomBytes(CRUDOC_ID_LENGTH);
  let id = "";
  for (let i = 0; i < CRUDOC_ID_LENGTH; i++) id += ALPHABET[bytes[i] % 32];
  return id;
}

/**
 * What someone typed, as a stored ID: case, spaces and dashes don't matter,
 * a leading "CD" is dropped, O reads as 0 and I or L as 1. Null when it
 * can't be an ID.
 */
export function normalizeCrudocId(raw: unknown): string | null {
  let s = String(raw ?? "").toUpperCase().replace(/[\s-]/g, "");
  if (s.length === CRUDOC_ID_LENGTH + 2 && s.startsWith("CD")) s = s.slice(2);
  s = s.replace(/O/g, "0").replace(/[IL]/g, "1");
  if (s.length !== CRUDOC_ID_LENGTH) return null;
  return [...s].every((ch) => ALPHABET.includes(ch)) ? s : null;
}

/** "K7Q92XMB" -> "K7Q9-2XMB", how the app shows it. */
export function formatCrudocId(id: string): string {
  return `${id.slice(0, 4)}-${id.slice(4)}`;
}

/**
 * [uid]'s CruDoc ID, made and claimed the first time it is asked for. Only
 * for someone with a profile (`users/{uid}`): writing a bare document would
 * make an unknown account look like a doctor elsewhere.
 */
export async function ensureCrudocId(uid: string): Promise<string> {
  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);
  for (let attempt = 0; attempt < 5; attempt++) {
    const id = newCrudocId();
    const claimRef = db.collection(CRUDOC_IDS).doc(id);
    const got = await db.runTransaction(async (tx) => {
      const user = await tx.get(userRef);
      if (!user.exists) {
        throw new HttpsError("failed-precondition", "Finish setting up your profile first.");
      }
      const mine = user.data()?.crudocId;
      if (typeof mine === "string" && mine.length === CRUDOC_ID_LENGTH) return mine;
      const claim = await tx.get(claimRef);
      if (claim.exists) return null; // taken: try another
      tx.set(claimRef, {uid, createdAt: FieldValue.serverTimestamp()});
      tx.update(userRef, {crudocId: id});
      return id;
    });
    if (got) return got;
  }
  throw new HttpsError("internal", "Couldn't make your CruDoc ID. Try again.");
}

/** Who holds [id] (already normalized), or null. */
export async function uidForCrudocId(id: string): Promise<string | null> {
  const snap = await admin.firestore().collection(CRUDOC_IDS).doc(id).get();
  const uid = snap.data()?.uid;
  return typeof uid === "string" && uid ? uid : null;
}

/** Counts [n] uses of [key] against [limit] per [windowMs]; throws when over. */
export async function spend(uid: string, key: string, n: number, limit: number,
  windowMs: number, message: string): Promise<void> {
  const db = admin.firestore();
  const ref = db.collection("rate_limits").doc(uid);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const prev = snap.data()?.[key] || {};
    const now = Date.now();
    const fresh = !(typeof prev.windowStart === "number" && now - prev.windowStart < windowMs);
    const windowStart = fresh ? now : prev.windowStart;
    const used = fresh ? 0 : Number(prev.count || 0);
    if (used + n > limit) {
      throw new HttpsError("resource-exhausted", message);
    }
    tx.set(ref, {[key]: {windowStart, count: used + n}}, {merge: true});
  });
}

export interface CrudocTarget {
  uid: string;
  /** Formatted, "K7Q9-2XMB". */
  crudocId: string;
  /** Their profile name, "" when they have none. */
  name: string;
}

/**
 * The account whose CruDoc ID [raw] someone typed: the one exact-ID lookup
 * behind every "find a person" (referrals, clinic invites). Spends one of
 * the caller's hourly lookups, refuses their own ID, and is not-found when
 * no profile holds the ID.
 */
export async function resolveCrudocId(callerUid: string, raw: unknown): Promise<CrudocTarget> {
  const id = normalizeCrudocId(raw);
  if (!id) {
    throw new HttpsError("invalid-argument",
      "A CruDoc ID is 8 letters and numbers, like K7Q9-2XMB.");
  }
  await spend(callerUid, "crudocIdLookup", 1, LOOKUPS_PER_HOUR, 3600_000,
    "That's a lot of lookups. Try again in an hour.");
  const uid = await uidForCrudocId(id);
  if (uid === callerUid) {
    throw new HttpsError("invalid-argument", "That is your own CruDoc ID.");
  }
  const user = uid ? await admin.firestore().collection("users").doc(uid).get() : null;
  if (!uid || !user?.exists) {
    throw new HttpsError("not-found", "No one on CruDoc has that ID.");
  }
  const u = user.data() || {};
  return {
    uid,
    crudocId: formatCrudocId(id),
    name: decryptProfileField(u.name, uid) || decryptProfileField(u.displayName, uid),
  };
}
