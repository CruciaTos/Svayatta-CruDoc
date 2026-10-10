import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

// Features a doctor always keeps, even once a plan expires. Mirrors
// DoctorFeatureGuard.baseModules in the Flutter app.
const BASE_MODULES = ["dashboard", "patients", "appointments", "inventory"];

// Every module key the app recognises. Anything outside this set is ignored
// so a tampered client cannot smuggle in unknown entitlements. Keep in sync
// with crudoc_shared/subscription/feature_catalog.dart and
// DoctorFeatureGuard.defaultModules.
const VALID_MODULES = new Set<string>([
  ...BASE_MODULES,
  "revenue",
  "home_visits",
  "omnichannel_messaging",
  "ai_assistant",
  "ai_agentic_calling",
  "multi_device_access",
  "queue",
  "campaigns",
  "scribe",
]);

// One paid cycle, and the trial, both run 30 days.
const PLAN_DAYS = 30;

/** Normalises a client-supplied module list: lowercased, known keys only,
 * base modules always included, de-duplicated. */
function sanitiseModules(raw: unknown): string[] {
  const picked = Array.isArray(raw) ?
    raw
      .map((m) => String(m).toLowerCase().trim())
      .filter((m) => VALID_MODULES.has(m)) :
    [];
  return Array.from(new Set<string>([...BASE_MODULES, ...picked]));
}

/**
 * Activates the selected paid modules for 30 days after an in-app payment.
 *
 * The client never writes its own entitlements; it hands over the chosen
 * modules and payment metadata and this function — running with admin
 * privileges — is the only writer of `enabledModules`, `status` and
 * `expiresDate`. The expiry is computed server-side so a tampered client
 * cannot grant itself a longer plan.
 */
export const activateDoctorFeatures = onCall(
  {region: "asia-south1", maxInstances: 10},
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const uid = request.auth.uid;
    const data = request.data || {};

    const modules = sanitiseModules(data.selectedModules);

    const amount = Number(data.amount);
    if (!Number.isFinite(amount) || amount < 0) {
      throw new HttpsError("invalid-argument", "A valid amount is required.");
    }
    const paymentMethod = String(data.paymentMethod ?? "Unknown").slice(0, 64);
    const transactionReference =
      String(data.transactionReference ?? "").slice(0, 128) || null;

    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    const validUntil = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + PLAN_DAYS * 24 * 60 * 60 * 1000),
    );
    const transactionId =
      `TXN_${Date.now()}_${Math.random().toString(36).slice(2, 8).toUpperCase()}`;
    const allowMultiDevice = modules.includes("multi_device_access");

    const userRef = db.collection("users").doc(uid);
    const txnRef = db.collection("payment_transactions").doc(transactionId);
    const settingsRef = db.collection("doctor_settings").doc(uid);

    const userSnap = await userRef.get();
    const userData = userSnap.data() || {};

    const batch = db.batch();
    batch.set(
      userRef,
      {
        enabledModules: modules,
        status: "active",
        expiresDate: validUntil,
        allowMultiDevice,
        lastPaymentDate: now,
        lastTransactionId: transactionId,
        lastPaymentAmount: amount,
        lastPaymentMethod: paymentMethod,
      },
      {merge: true},
    );
    batch.set(
      settingsRef,
      {
        doctorId: uid,
        enabledModules: modules,
        allowMultiDevice,
        lastModified: now,
      },
      {merge: true},
    );
    batch.set(txnRef, {
      transactionId,
      doctorId: uid,
      doctorEmail: request.auth.token.email ?? userData.email ?? "",
      doctorName: request.auth.token.name ?? userData.displayName ?? "Doctor",
      amount,
      currency: "INR",
      paymentMethod,
      transactionReference: transactionReference ?? transactionId,
      activatedModules: modules,
      validUntil,
      status: "success",
      timestamp: now,
    });
    await batch.commit();

    return {
      success: true,
      transactionId,
      validUntil: validUntil.toDate().toISOString(),
      enabledModules: modules,
    };
  },
);

/**
 * Starts (or returns) a doctor's free trial during onboarding.
 *
 * Like paid activation, the trial window is computed server-side so the
 * client cannot grant itself an arbitrarily long trial. It is idempotent:
 * once a doctor has an active trial or paid plan the existing expiry is
 * returned unchanged rather than extended.
 */
export const startDoctorTrial = onCall(
  {region: "asia-south1", maxInstances: 10},
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const uid = request.auth.uid;
    const data = request.data || {};
    const modules = sanitiseModules(data.modules);
    const allowMultiDevice = modules.includes("multi_device_access");

    const db = admin.firestore();
    const userRef = db.collection("users").doc(uid);
    const snap = await userRef.get();
    const existing = snap.data() || {};

    // Don't re-grant or extend an already active plan/trial.
    const status = String(existing.status ?? "").toLowerCase();
    const rawExpires = existing.expiresDate;
    const expiresMs =
      rawExpires instanceof admin.firestore.Timestamp ?
        rawExpires.toMillis() :
        0;
    if (
      (status === "trial" || status === "active") &&
      expiresMs > Date.now()
    ) {
      return {
        started: false,
        alreadyActive: true,
        validUntil: new Date(expiresMs).toISOString(),
        enabledModules: Array.isArray(existing.enabledModules) ?
          existing.enabledModules :
          modules,
      };
    }

    const now = admin.firestore.Timestamp.now();
    const validUntil = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + PLAN_DAYS * 24 * 60 * 60 * 1000),
    );

    await userRef.set(
      {
        status: "trial",
        subscriptionPlan: "Trial",
        expiresDate: validUntil,
        enabledModules: modules,
        allowMultiDevice,
        trialStartedAt: now,
      },
      {merge: true},
    );

    return {
      started: true,
      alreadyActive: false,
      validUntil: validUntil.toDate().toISOString(),
      enabledModules: modules,
    };
  },
);
