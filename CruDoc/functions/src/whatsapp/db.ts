import * as admin from "firebase-admin";

/**
 * The Admin SDK Firestore handle, initialising the app on first use.
 *
 * Lives in its own module so every WhatsApp module can share one handle
 * without importing a sibling that imports it back.
 */
export function getDb(): admin.firestore.Firestore {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
}
