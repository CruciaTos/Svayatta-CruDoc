import {setGlobalOptions} from "firebase-functions/v2";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

admin.initializeApp();
setGlobalOptions({region: "asia-south1", maxInstances: 10});

/**
 * Super Admin access is for Svayatta staff only: anyone who signs in to the
 * console with a verified @svayatta.in address. The console signs people in
 * with an email link, which is what proves they own the mailbox.
 */
const ADMIN_EMAIL_DOMAIN = "@svayatta.in";

/**
 * Called by the console right after sign-in. Grants the claims that
 * firestore.rules checks (isSuperAdmin) and keeps the users/{uid} profile
 * the console reads. Setting a profile's isActive to false blocks that
 * person without touching their mailbox.
 */
export const claimSuperAdmin = onCall(async (request) => {
  const token = request.auth?.token;
  if (!request.auth || !token) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }

  const email = (token.email ?? "").toLowerCase();
  if (!email.endsWith(ADMIN_EMAIL_DOMAIN) || token.email_verified !== true) {
    throw new HttpsError(
      "permission-denied",
      `Super Admin is limited to verified ${ADMIN_EMAIL_DOMAIN} accounts.`
    );
  }

  const uid = request.auth.uid;
  const profileRef = admin.firestore().collection("users").doc(uid);
  const profile = await profileRef.get();
  if (profile.exists && profile.get("isActive") === false) {
    throw new HttpsError(
      "permission-denied",
      "This admin account is disabled."
    );
  }

  if (token.role !== "superAdmin" || token.isTwoFAVerified !== true) {
    await admin.auth().setCustomUserClaims(uid, {
      role: "superAdmin",
      isTwoFAVerified: true,
    });
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  await profileRef.set(
    {
      email,
      role: "superAdmin",
      isActive: true,
      isTwoFAEnabled: false,
      isTwoFAVerified: true,
      failedLoginAttempts: 0,
      lockedUntil: null,
      lastLogin: now,
      ...(profile.exists ? {} : {
        name: token.name ?? "Super Admin",
        profilePictureUrl: "",
        accountCreated: now,
      }),
    },
    {merge: true}
  );

  return {granted: true};
});

export * from "./receptionist-admin";
