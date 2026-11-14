import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import {getDb} from "../whatsapp/db";
import {patientKekPepperSecret} from "../crypto/patientCipher";
import {rejectSuperAdmin, requirePlanModule} from "../clinic-app-guard";
import {
  exchangeAuthCode, GmailError, gmailClientIdSecret,
  gmailClientSecretSecret, revokeToken,
} from "./gmail";
import {GMAIL_PRIVATE_DOC, GMAIL_STATUS_DOC} from "./deliver";
import {sendDueRecalls} from "./recalls";
import {openToken, sealToken} from "./vault";

/**
 * Connecting a clinic's own Gmail, and the daily recall schedule.
 *
 * Storage, per clinic (the clinic id is the owner's uid):
 *   clinics/{id}/private/gmail           server-only: the refresh token,
 *                                        sealed (vault.ts), plus the address
 *   clinics/{id}/messaging_status/gmail  readable by the clinic: state and
 *                                        address, never a token
 * firestore.rules closes the first completely and makes the second read-only.
 */

const REGION = "asia-south1";
const MESSAGING_MODULE = "omnichannel_messaging";

/** Desktop sign-in repeats its loopback redirect; mobile sends none. */
const LOOPBACK_REDIRECT = /^http:\/\/(127\.0\.0\.1|localhost|\[::1\])(:\d{1,5})?(\/[^\s]*)?$/;

/** The calling clinic owner's id. Staff and Super Admin are refused. */
async function requireOwner(request: CallableRequest): Promise<string> {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  rejectSuperAdmin(request);

  const me = (await getDb().collection("users").doc(uid).get()).data() ?? {};
  rejectSuperAdmin(request, me);
  const clinicId = typeof me.clinicId === "string" ? me.clinicId : "";
  if (clinicId && clinicId !== uid) {
    throw new HttpsError(
      "permission-denied", "Only the clinic owner can connect Gmail.",
    );
  }
  await requirePlanModule(uid, MESSAGING_MODULE, "Email reminders");
  return uid;
}

function clinicDocs(clinicId: string) {
  const clinic = getDb().collection("clinics").doc(clinicId);
  return {
    secret: clinic.collection(GMAIL_PRIVATE_DOC[0]).doc(GMAIL_PRIVATE_DOC[1]),
    status: clinic.collection(GMAIL_STATUS_DOC[0]).doc(GMAIL_STATUS_DOC[1]),
  };
}

/**
 * Exchanges the app's server auth code (offline access, gmail.send only) for a
 * refresh token and stores it sealed. Returns only the connected address.
 */
export const connectClinicGmail = onCall(
  {
    region: REGION,
    secrets: [
      gmailClientIdSecret, gmailClientSecretSecret, patientKekPepperSecret,
    ],
  },
  async (request) => {
    const clinicId = await requireOwner(request);

    const data = (request.data || {}) as {authCode?: unknown; redirectUri?: unknown};
    const authCode = typeof data.authCode === "string" ? data.authCode.trim() : "";
    const redirectUri = typeof data.redirectUri === "string" ?
      data.redirectUri.trim() : "";
    if (!authCode || authCode.length > 2048) {
      throw new HttpsError("invalid-argument", "authCode is required.");
    }
    if (redirectUri && !LOOPBACK_REDIRECT.test(redirectUri)) {
      throw new HttpsError("invalid-argument", "redirectUri is not allowed.");
    }

    let tokens;
    try {
      tokens = await exchangeAuthCode(authCode, redirectUri);
    } catch (err) {
      if (err instanceof GmailError) {
        throw new HttpsError(
          err.code === "oauth_client_unset" ? "failed-precondition" :
            "invalid-argument",
          err.message,
        );
      }
      throw err;
    }
    if (!tokens.email) {
      throw new HttpsError(
        "failed-precondition",
        "Google did not share the account's email address. Connect again.",
      );
    }

    const docs = clinicDocs(clinicId);
    const now = admin.firestore.FieldValue.serverTimestamp();
    await docs.secret.set({
      refreshTokenSealed: sealToken(clinicId, tokens.refreshToken),
      address: tokens.email,
      scope: tokens.scope,
      connectedAt: now,
    });
    await docs.status.set({
      state: "connected",
      address: tokens.email,
      connectedAt: now,
      updatedAt: now,
    });
    return {address: tokens.email};
  },
);

/** Revokes the token at Google and deletes the stored copy. */
export const disconnectClinicGmail = onCall(
  {region: REGION, secrets: [patientKekPepperSecret]},
  async (request) => {
    const clinicId = await requireOwner(request);
    const docs = clinicDocs(clinicId);

    const snap = await docs.secret.get();
    const token = snap.exists ?
      openToken(clinicId, snap.data()?.refreshTokenSealed) : null;
    if (token) await revokeToken(token);

    await docs.secret.delete();
    await docs.status.set({
      state: "disconnected",
      address: null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {ok: true};
  },
);

/**
 * Recalls due today, every morning at 10:00 IST. One run at a time: a second
 * would race the first for the same log documents (the transaction would catch
 * it, but not racing is cheaper).
 */
export const sendDueRecallsDaily = onSchedule(
  {
    schedule: "0 10 * * *",
    timeZone: "Asia/Kolkata",
    region: REGION,
    maxInstances: 1,
    timeoutSeconds: 540,
    memory: "512MiB",
    retryCount: 0,
    secrets: [
      patientKekPepperSecret, gmailClientIdSecret, gmailClientSecretSecret,
    ],
  },
  async () => {
    await sendDueRecalls();
  },
);
