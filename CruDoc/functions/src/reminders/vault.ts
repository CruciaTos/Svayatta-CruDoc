import * as crypto from "crypto";
import {getPepper} from "../crypto/patientCipher";

/**
 * Encrypts the clinic's Gmail refresh token before it is stored.
 *
 * AES-256-GCM, the same primitive and pepper as the patient field cipher
 * (crypto/patientCipher.ts), but with a key of its own: SHA-256 of
 * "gmail-refresh::<clinicId>::<pepper>". The patient DEK is deliberately not
 * reused, because the DEK is readable by the clinic's own devices and this
 * token must stay server-only. The clinic id is also bound in as additional
 * authenticated data, so a blob copied onto another clinic's document fails
 * to decrypt.
 *
 * Wire format: "gm:v1:<iv b64>.<ciphertext+tag b64>".
 */

const PREFIX = "gm:v1:";
const IV_BYTES = 12;
const TAG_BYTES = 16;

function keyFor(clinicId: string): Buffer {
  return crypto
    .createHash("sha256")
    .update(`gmail-refresh::${clinicId}::${getPepper()}`, "utf8")
    .digest();
}

export function sealToken(clinicId: string, token: string): string {
  const iv = crypto.randomBytes(IV_BYTES);
  const cipher = crypto.createCipheriv("aes-256-gcm", keyFor(clinicId), iv);
  cipher.setAAD(Buffer.from(clinicId, "utf8"));
  const body = Buffer.concat([
    cipher.update(Buffer.from(token, "utf8")),
    cipher.final(),
    cipher.getAuthTag(),
  ]);
  return `${PREFIX}${iv.toString("base64")}.${body.toString("base64")}`;
}

/** Returns null when the value is malformed or was sealed for another clinic. */
export function openToken(clinicId: string, sealed: unknown): string | null {
  if (typeof sealed !== "string" || !sealed.startsWith(PREFIX)) return null;
  const payload = sealed.slice(PREFIX.length);
  const dot = payload.indexOf(".");
  if (dot <= 0) return null;
  try {
    const iv = Buffer.from(payload.slice(0, dot), "base64");
    const body = Buffer.from(payload.slice(dot + 1), "base64");
    if (iv.length !== IV_BYTES || body.length < TAG_BYTES) return null;
    const decipher = crypto.createDecipheriv(
      "aes-256-gcm", keyFor(clinicId), iv,
    );
    decipher.setAAD(Buffer.from(clinicId, "utf8"));
    decipher.setAuthTag(body.subarray(body.length - TAG_BYTES));
    return Buffer.concat([
      decipher.update(body.subarray(0, body.length - TAG_BYTES)),
      decipher.final(),
    ]).toString("utf8");
  } catch (_) {
    return null;
  }
}
