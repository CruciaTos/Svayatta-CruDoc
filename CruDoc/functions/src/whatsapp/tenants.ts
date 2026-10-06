import * as admin from "firebase-admin";
import {SecretManagerServiceClient} from "@google-cloud/secret-manager";
import {getDb} from "./db";

/**
 * Per-clinic WhatsApp credentials.
 *
 * Each clinic connects their own WhatsApp Business number through Embedded
 * Signup, so there is no single app-wide token. A clinic's access token is the
 * key to messaging its patients, so it is held in Secret Manager and never in
 * Firestore, and nothing a client can read ever carries it.
 *
 * Two stores, deliberately:
 *   whatsapp_tenants/{doctorId}      config the server can list and sweep over
 *   Secret Manager wa_token_{uid}    the token itself, with IAM and audit logs
 *
 * Splitting them is also what lets the sending functions bind no secrets at
 * deploy time. `defineSecret` bindings are fixed when a function deploys, so a
 * per-tenant secret cannot be bound that way — which is why the original
 * WhatsApp endpoints were never exported from index.ts.
 */

export const TENANTS_COLLECTION = "whatsapp_tenants";
export const CONNECTIONS_COLLECTION = "whatsapp_connections";

/** How long a resolved token is reused within one warm instance. */
const CRED_CACHE_TTL_MS = 90_000;

export type TenantStatus =
  | "connected"
  | "reauth_required"
  | "disconnected"
  | "pending_register";

export interface TenantConfig {
  doctorId: string;
  wabaId: string;
  phoneNumberId: string;
  displayPhoneNumber?: string;
  verifiedName?: string;
  qualityRating?: string;
  tokenSecretName: string;
  tokenVersion?: string;
  status: TenantStatus;
  /** IANA zone used to render dates and times for this clinic's patients. */
  timezone: string;
  /** Template language code, e.g. "en". Must match how templates were created. */
  defaultLanguage: string;
}

export interface TenantCreds extends TenantConfig {
  token: string;
}

/** The clinic has never connected a number, or has disconnected it. */
export class TenantNotConnectedError extends Error {
  constructor(public readonly doctorId: string) {
    super(`WhatsApp is not connected for doctor ${doctorId}`);
    this.name = "TenantNotConnectedError";
  }
}

/** The token was revoked; the clinic has to reconnect before sending resumes. */
export class TenantReauthRequiredError extends Error {
  constructor(public readonly doctorId: string) {
    super(`WhatsApp needs reconnecting for doctor ${doctorId}`);
    this.name = "TenantReauthRequiredError";
  }
}

let secretsClient: SecretManagerServiceClient | null = null;

function getSecrets(): SecretManagerServiceClient {
  if (!secretsClient) {
    secretsClient = new SecretManagerServiceClient();
  }
  return secretsClient;
}

function projectId(): string {
  const id =
    process.env.GCLOUD_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    process.env.FIREBASE_CONFIG_PROJECT_ID;
  if (!id) {
    throw new Error("Project id is unavailable; cannot address Secret Manager.");
  }
  return id;
}

/**
 * Secret ids allow letters, digits, underscore and hyphen. Firebase uids are
 * already within that set, but anything else is rejected rather than mangled:
 * two doctors must never collide onto one secret.
 */
export function secretIdFor(doctorId: string): string {
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(doctorId)) {
    throw new Error(`doctorId is not usable as a secret id: ${doctorId}`);
  }
  return `wa_token_${doctorId}`;
}

export function secretNameFor(doctorId: string): string {
  return `projects/${projectId()}/secrets/${secretIdFor(doctorId)}`;
}

interface CacheEntry {
  creds: TenantCreds;
  expiresAt: number;
}

/**
 * Per-instance cache. The reminder sweep runs every minute and may touch many
 * clinics, and an uncached Secret Manager read costs ~100ms. The TTL is short
 * so a rotated or revoked token is picked up quickly without a deploy.
 */
const credCache = new Map<string, CacheEntry>();

export function clearTenantCache(doctorId?: string): void {
  if (doctorId) {
    credCache.delete(doctorId);
  } else {
    credCache.clear();
  }
}

function toConfig(
  doctorId: string,
  data: admin.firestore.DocumentData,
): TenantConfig {
  return {
    doctorId,
    wabaId: data.wabaId || "",
    phoneNumberId: data.phoneNumberId || "",
    displayPhoneNumber: data.displayPhoneNumber,
    verifiedName: data.verifiedName,
    qualityRating: data.qualityRating,
    tokenSecretName: data.tokenSecretName || "",
    tokenVersion: data.tokenVersion,
    status: (data.status as TenantStatus) || "disconnected",
    timezone: data.timezone || "Asia/Kolkata",
    defaultLanguage: data.defaultLanguage || "en",
  };
}

/** Config without the token. Safe for listing, sweeps and support views. */
export async function getTenantConfig(
  doctorId: string,
): Promise<TenantConfig | null> {
  const snap = await getDb().collection(TENANTS_COLLECTION).doc(doctorId).get();
  if (!snap.exists) return null;
  return toConfig(doctorId, snap.data() || {});
}

/**
 * Everything needed to send as this clinic, token included.
 *
 * Throws rather than returning null: a caller that forgets to handle "not
 * connected" should fail loudly, not silently send from the wrong number.
 */
export async function getTenantCreds(doctorId: string): Promise<TenantCreds> {
  const cached = credCache.get(doctorId);
  if (cached && cached.expiresAt > Date.now()) {
    return cached.creds;
  }

  const config = await getTenantConfig(doctorId);
  if (!config || config.status === "disconnected") {
    throw new TenantNotConnectedError(doctorId);
  }
  if (config.status === "reauth_required") {
    throw new TenantReauthRequiredError(doctorId);
  }
  if (!config.wabaId || !config.phoneNumberId || !config.tokenSecretName) {
    throw new TenantNotConnectedError(doctorId);
  }

  let token: string;
  try {
    const [version] = await getSecrets().accessSecretVersion({
      name: `${config.tokenSecretName}/versions/latest`,
    });
    token = version.payload?.data?.toString() || "";
  } catch (err) {
    console.error(`[WhatsApp] token read failed for ${doctorId}`, err);
    throw new TenantNotConnectedError(doctorId);
  }

  if (!token) {
    throw new TenantNotConnectedError(doctorId);
  }

  const creds: TenantCreds = {...config, token};
  credCache.set(doctorId, {creds, expiresAt: Date.now() + CRED_CACHE_TTL_MS});
  return creds;
}

/**
 * Stores a clinic's token, creating the secret on first connect and adding a
 * version on reconnect. Returns the resource name and the new version number.
 */
export async function writeTenantToken(
  doctorId: string,
  token: string,
): Promise<{secretName: string; version: string}> {
  const client = getSecrets();
  const parent = `projects/${projectId()}`;
  const secretId = secretIdFor(doctorId);
  const secretName = `${parent}/secrets/${secretId}`;

  try {
    await client.createSecret({
      parent,
      secretId,
      secret: {
        replication: {automatic: {}},
        labels: {app: "crudoc", kind: "whatsapp-tenant-token"},
      },
    });
  } catch (err) {
    // 6 = ALREADY_EXISTS, which is the reconnect case. Anything else is real.
    const code = (err as {code?: number})?.code;
    if (code !== 6) throw err;
  }

  const [added] = await client.addSecretVersion({
    parent: secretName,
    payload: {data: Buffer.from(token, "utf8")},
  });

  const version = added.name?.split("/").pop() || "latest";
  clearTenantCache(doctorId);
  return {secretName, version};
}

/**
 * The non-secret view the app reads to show connection state. Written by the
 * server only; `firestore.rules` denies every client write.
 */
async function writeConnectionMirror(
  doctorId: string,
  config: TenantConfig,
): Promise<void> {
  await getDb()
    .collection(CONNECTIONS_COLLECTION)
    .doc(doctorId)
    .set(
      {
        doctorId,
        connected: config.status === "connected",
        status: config.status,
        displayPhoneNumber: config.displayPhoneNumber || null,
        verifiedName: config.verifiedName || null,
        needsReauth: config.status === "reauth_required",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
}

/** Records a freshly connected (or reconnected) clinic and its token. */
export async function saveTenant(params: {
  doctorId: string;
  wabaId: string;
  phoneNumberId: string;
  token: string;
  displayPhoneNumber?: string;
  verifiedName?: string;
  timezone?: string;
  defaultLanguage?: string;
}): Promise<TenantConfig> {
  const {secretName, version} = await writeTenantToken(
    params.doctorId,
    params.token,
  );

  const config: TenantConfig = {
    doctorId: params.doctorId,
    wabaId: params.wabaId,
    phoneNumberId: params.phoneNumberId,
    displayPhoneNumber: params.displayPhoneNumber,
    verifiedName: params.verifiedName,
    tokenSecretName: secretName,
    tokenVersion: version,
    status: "connected",
    timezone: params.timezone || "Asia/Kolkata",
    defaultLanguage: params.defaultLanguage || "en",
  };

  await getDb()
    .collection(TENANTS_COLLECTION)
    .doc(params.doctorId)
    .set(
      {
        ...config,
        displayPhoneNumber: config.displayPhoneNumber || null,
        verifiedName: config.verifiedName || null,
        connectedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );

  await writeConnectionMirror(params.doctorId, config);
  clearTenantCache(params.doctorId);
  return config;
}

/**
 * Flags a clinic as needing to reconnect. Called when Meta rejects the token,
 * so queued messages stop being retried against a credential that cannot work
 * and the app can prompt the doctor instead.
 */
export async function markReauthRequired(
  doctorId: string,
  errorCode?: number | string,
): Promise<void> {
  clearTenantCache(doctorId);

  await getDb()
    .collection(TENANTS_COLLECTION)
    .doc(doctorId)
    .set(
      {
        status: "reauth_required",
        lastErrorCode: errorCode ?? null,
        lastErrorAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );

  await getDb()
    .collection(CONNECTIONS_COLLECTION)
    .doc(doctorId)
    .set(
      {
        doctorId,
        connected: false,
        status: "reauth_required",
        needsReauth: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
}

/**
 * True when a Meta error means the token is no longer usable, as opposed to a
 * transient failure worth retrying.
 *
 * 190 is the OAuth family (expired, revoked, password changed); 102 and 463
 * are session errors; 10 and 200-299 are permission errors that a retry with
 * the same token cannot fix.
 */
export function isAuthError(code?: number): boolean {
  if (typeof code !== "number") return false;
  return code === 190 || code === 102 || code === 463 || code === 10 ||
    (code >= 200 && code <= 299);
}
