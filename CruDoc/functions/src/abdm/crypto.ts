import * as crypto from "crypto";

export function toPem(key: string): string {
  if (key.includes("BEGIN")) return key;
  const body = key.replace(/\s+/g, "").match(/.{1,64}/g)!.join("\n");
  return `-----BEGIN PUBLIC KEY-----\n${body}\n-----END PUBLIC KEY-----\n`;
}

export function encryptForAbdm(plain: string, publicKey: string, algorithm: string): string {
  if (!/OAEPWithSHA-1AndMGF1/i.test(algorithm)) {
    throw new Error(`Unsupported ABDM algorithm: ${algorithm}`);
  }
  return crypto.publicEncrypt(
    {key: toPem(publicKey), padding: crypto.constants.RSA_PKCS1_OAEP_PADDING, oaepHash: "sha1"},
    Buffer.from(plain, "utf8"),
  ).toString("base64");
}

/** Seals an ABDM token before it is written to Firestore. */
export function seal(plain: string, secret: string): string {
  const key = crypto.createHash("sha256").update(`abdm-flow:${secret}`).digest();
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv("aes-256-gcm", key, iv);
  const data = Buffer.concat([c.update(plain, "utf8"), c.final()]);
  return Buffer.concat([iv, c.getAuthTag(), data]).toString("base64");
}

export function open(sealed: string, secret: string): string {
  const key = crypto.createHash("sha256").update(`abdm-flow:${secret}`).digest();
  const raw = Buffer.from(sealed, "base64");
  const d = crypto.createDecipheriv("aes-256-gcm", key, raw.subarray(0, 12));
  d.setAuthTag(raw.subarray(12, 28));
  return Buffer.concat([d.update(raw.subarray(28)), d.final()]).toString("utf8");
}
