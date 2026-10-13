import * as crypto from "crypto";

/**
 * Reads the doctor profile fields Super Admin encrypts on `users/{uid}`
 * (name, clinicName, phone, ...; see `encryptDoctorValue` in super-admin.ts).
 *
 * Same "enc:v1:<iv>.<ciphertext+tag>" shape as patient fields but a
 * different key: SHA-256("crudoc-doctor-profile::<uid>"). Anything that puts
 * a doctor's or clinic's name in front of a patient (WhatsApp reminders, the
 * AI receptionist's greeting) must read them through this, or it says the
 * ciphertext out loud.
 *
 * Returns the plain value, the value unchanged when it isn't encrypted, and
 * "" when it is encrypted but can't be read, so callers fall back to their
 * next source instead of using ciphertext.
 */
export function decryptProfileField(value: unknown, uid: string): string {
  if (typeof value !== "string" || !value) return "";
  if (!value.startsWith("enc:v1:")) return value.trim();
  try {
    const body = value.slice("enc:v1:".length);
    const dot = body.indexOf(".");
    const iv = Buffer.from(body.slice(0, dot), "base64");
    const sealed = Buffer.from(body.slice(dot + 1), "base64");
    const key = crypto.createHash("sha256").update(`crudoc-doctor-profile::${uid}`).digest();
    const decipher = crypto.createDecipheriv("aes-256-gcm", key, iv);
    decipher.setAuthTag(sealed.subarray(sealed.length - 16));
    return Buffer.concat([
      decipher.update(sealed.subarray(0, sealed.length - 16)),
      decipher.final(),
    ]).toString("utf8").trim();
  } catch (_) {
    return "";
  }
}
