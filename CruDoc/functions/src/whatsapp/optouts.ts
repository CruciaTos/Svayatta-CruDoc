import * as admin from "firebase-admin";
import {getDb} from "./db";

/**
 * Patients who asked to stop receiving reminders.
 *
 * Opt-out is global rather than per clinic. A patient replying STOP is
 * replying to the CruDoc number, and their message carries nothing that says
 * which clinic prompted it — so honouring it for one clinic and continuing for
 * another would be both unimplementable and wrong.
 *
 * Keyed by the normalised phone number, not by patient id, because the same
 * person can exist as separate records under different clinics and the request
 * was made by the holder of the phone.
 */

export const OPTOUTS_COLLECTION = "whatsapp_optouts";

/**
 * Words that stop the reminders.
 *
 * "BAND" is "बंद" transliterated, which is how a Hindi or Marathi speaker is
 * likely to type it on a Latin keyboard. The Devanagari spelling is accepted
 * too. Matching is case-insensitive and ignores surrounding punctuation.
 */
const STOP_WORDS = new Set([
  "stop", "unsubscribe", "cancel", "band", "बंद", "बन्द",
]);

const START_WORDS = new Set([
  "start", "subscribe", "resume", "chalu", "चालू",
]);

export type ReplyIntent = "stop" | "start" | "other";

/**
 * Classifies an inbound message.
 *
 * Only a message that is essentially just the keyword counts. "Please stop
 * sending these" is a stop, but a sentence that merely contains the word
 * inside other text is left as "other" so a human can read it.
 */
export function classifyReply(text: string | null | undefined): ReplyIntent {
  if (!text) return "other";

  // Marks are kept alongside letters: the anusvara in "बंद" and the virama in
  // "बन्द" are combining marks, and stripping them leaves a different word.
  const cleaned = text
    .toLowerCase()
    .replace(/[^\p{L}\p{M}\s]/gu, " ")
    .trim()
    .replace(/\s+/g, " ");

  if (!cleaned) return "other";

  const words = cleaned.split(" ");
  if (words.length > 4) return "other";

  if (words.some((w) => STOP_WORDS.has(w))) return "stop";
  if (words.some((w) => START_WORDS.has(w))) return "start";
  return "other";
}

export async function isOptedOut(phone: string): Promise<boolean> {
  const snap = await getDb().collection(OPTOUTS_COLLECTION).doc(phone).get();
  return snap.exists;
}

/** Phones from the given list that have opted out. */
export async function filterOptedOut(phones: string[]): Promise<Set<string>> {
  const unique = [...new Set(phones)].filter(Boolean);
  if (!unique.length) return new Set();

  const db = getDb();
  const out = new Set<string>();

  // getAll takes refs in one round trip; chunked because Firestore caps the
  // number of documents per call.
  for (let i = 0; i < unique.length; i += 300) {
    const refs = unique
      .slice(i, i + 300)
      .map((p) => db.collection(OPTOUTS_COLLECTION).doc(p));
    const snaps = await db.getAll(...refs);
    for (const s of snaps) {
      if (s.exists) out.add(s.id);
    }
  }

  return out;
}

export async function optOut(
  phone: string,
  source: "reply" | "manual" = "reply",
): Promise<void> {
  await getDb().collection(OPTOUTS_COLLECTION).doc(phone).set({
    phone,
    source,
    optedOutAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

export async function optIn(phone: string): Promise<void> {
  await getDb().collection(OPTOUTS_COLLECTION).doc(phone).delete();
}
