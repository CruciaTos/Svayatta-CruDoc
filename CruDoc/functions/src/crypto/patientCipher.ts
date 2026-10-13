import * as crypto from "crypto";
import * as admin from "firebase-admin";
import {defineSecret} from "firebase-functions/params";
import {normalisePhone} from "../whatsapp/format";

/**
 * Server-side twin of the app's patient field encryption.
 *
 * The app encrypts patient `firstName`, `lastName`, `phone`, `notes` and
 * `diagnosis` before they reach Firestore (`lib/core/services/field_cipher.dart`)
 * with a per-clinic data key (DEK) that is stored wrapped in
 * `doctor_keys/{clinicId}` (`lib/core/services/encryption_key_manager.dart`).
 * Anything on the server that reads or writes those fields must use the same
 * scheme, or it reads ciphertext as if it were a name or a phone number.
 *
 * Wire format, all base64 (standard alphabet, padded):
 *   wrappedKey  "<iv>.<ciphertext+tag>"            AES-256-GCM under the KEK
 *   field       "enc:v1:<iv>.<ciphertext+tag>"     AES-256-GCM under the DEK
 * IVs are 12 bytes and the 16-byte GCM tag is appended to the ciphertext,
 * which is what the Dart `encrypt` package (PointyCastle GCM) produces.
 *
 * KEK = SHA-256("<clinicId>::<pepper>"). The pepper is the app constant
 * `_appPepper`, held here as the secret PATIENT_KEK_PEPPER rather than in
 * source. Keep functions/test/patient-cipher.test.js passing: it decrypts a
 * value made by the Dart code, so the two implementations can't drift apart.
 */

export const patientKekPepperSecret = defineSecret("PATIENT_KEK_PEPPER");

const FIELD_PREFIX = "enc:v1:";
const IV_BYTES = 12;
const TAG_BYTES = 16;

/** The pepper, from the secret in production or the env in tests/emulator. */
export function getPepper(): string {
  try {
    const val = patientKekPepperSecret.value();
    if (val && val.trim().length > 0) return val.trim();
  } catch (_) {
    // Not bound to this function, or running locally.
  }
  const env = (process.env.PATIENT_KEK_PEPPER || "").trim();
  if (!env) {
    throw new Error("PATIENT_KEK_PEPPER is not configured");
  }
  return env;
}

export function deriveKek(clinicId: string, pepper: string): Buffer {
  return crypto.createHash("sha256").update(`${clinicId}::${pepper}`, "utf8").digest();
}

function gcmEncrypt(key: Buffer, plain: Buffer): string {
  const iv = crypto.randomBytes(IV_BYTES);
  const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
  const body = Buffer.concat([cipher.update(plain), cipher.final(), cipher.getAuthTag()]);
  return `${iv.toString("base64")}.${body.toString("base64")}`;
}

function gcmDecrypt(key: Buffer, payload: string): Buffer {
  const dot = payload.indexOf(".");
  if (dot <= 0) throw new Error("Malformed ciphertext");
  const iv = Buffer.from(payload.slice(0, dot), "base64");
  const body = Buffer.from(payload.slice(dot + 1), "base64");
  if (iv.length !== IV_BYTES || body.length < TAG_BYTES) {
    throw new Error("Malformed ciphertext");
  }
  const decipher = crypto.createDecipheriv("aes-256-gcm", key, iv);
  decipher.setAuthTag(body.subarray(body.length - TAG_BYTES));
  return Buffer.concat([
    decipher.update(body.subarray(0, body.length - TAG_BYTES)),
    decipher.final(),
  ]);
}

export function wrapKey(dek: Buffer, kek: Buffer): string {
  return gcmEncrypt(kek, dek);
}

export function unwrapKey(wrapped: string, kek: Buffer): Buffer {
  const dek = gcmDecrypt(kek, wrapped);
  if (dek.length !== 32) throw new Error("Unwrapped key has the wrong length");
  return dek;
}

export function isEncrypted(value: unknown): boolean {
  return typeof value === "string" && value.startsWith(FIELD_PREFIX);
}

/** Encrypts one field. Empty stays empty; an encrypted value is left alone. */
export function encryptField(plain: string | null | undefined, dek: Buffer): string {
  if (!plain) return "";
  if (plain.startsWith(FIELD_PREFIX)) return plain;
  return FIELD_PREFIX + gcmEncrypt(dek, Buffer.from(plain, "utf8"));
}

/**
 * Decrypts one field. Plaintext written before encryption existed comes back
 * unchanged, as in the app. Unlike the app, a value that cannot be decrypted
 * returns null rather than the ciphertext: on the server, ciphertext mistaken
 * for a name or a phone number is the bug this module exists to prevent.
 */
export function decryptField(value: unknown, dek: Buffer | null): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value !== "string") return null;
  if (!value.startsWith(FIELD_PREFIX)) return value;
  if (!dek) return null;
  try {
    return gcmDecrypt(dek, value.slice(FIELD_PREFIX.length)).toString("utf8");
  } catch (_) {
    return null;
  }
}

/**
 * A one-way fingerprint of a phone number, so a patient can be found by phone
 * without the phone being stored readable. Keyed with the clinic's DEK, so the
 * same number gives a different index in every clinic.
 *
 * The number is canonicalised to an Indian mobile ("91" + 10 digits) first;
 * anything else has no index.
 */
export function phoneIndexOf(rawPhone: string | null | undefined, dek: Buffer): string | null {
  const phone = normalisePhone(rawPhone);
  if (!phone) return null;
  return crypto.createHmac("sha256", dek).update(phone, "utf8").digest("hex");
}

/**
 * Loads and caches each clinic's DEK for the life of the instance.
 *
 * A clinic whose app has never created a key gets none from `dekFor` (nothing
 * of theirs is encrypted yet). `getOrCreateDek` makes one the same way the app
 * would, in a transaction so it can't race the app creating its own.
 */
export class PatientKeyring {
  private readonly cache = new Map<string, Buffer | null>();

  constructor(
    private readonly db: admin.firestore.Firestore,
    private readonly pepper: string = getPepper(),
  ) {}

  async dekFor(clinicId: string): Promise<Buffer | null> {
    if (!clinicId) return null;
    const cached = this.cache.get(clinicId);
    if (cached) return cached;

    const snap = await this.db.collection("doctor_keys").doc(clinicId).get();
    const wrapped = snap.exists ? snap.data()?.wrappedKey : undefined;
    if (typeof wrapped !== "string") return null;

    const dek = unwrapKey(wrapped, deriveKek(clinicId, this.pepper));
    this.cache.set(clinicId, dek);
    return dek;
  }

  async getOrCreateDek(clinicId: string): Promise<Buffer> {
    const existing = await this.dekFor(clinicId);
    if (existing) return existing;

    const ref = this.db.collection("doctor_keys").doc(clinicId);
    const kek = deriveKek(clinicId, this.pepper);
    const dek = await this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const wrapped = snap.exists ? snap.data()?.wrappedKey : undefined;
      if (typeof wrapped === "string") return unwrapKey(wrapped, kek);

      const fresh = crypto.randomBytes(32);
      tx.set(ref, {
        wrappedKey: wrapKey(fresh, kek),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return fresh;
    });
    this.cache.set(clinicId, dek);
    return dek;
  }
}
