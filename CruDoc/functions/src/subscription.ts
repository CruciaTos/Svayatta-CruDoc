import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
// Imported directly rather than read off admin.firestore: the Functions
// emulator wraps admin.firestore in a bound copy that drops these
// statics, so admin.firestore.Timestamp / .FieldValue are undefined there
// (production is unaffected; the classes are the same either way).
import {Timestamp} from "firebase-admin/firestore";
import {decryptProfileField} from "./crypto/profileCipher";

// Features a doctor always keeps, even once a plan expires. Mirrors
// DoctorFeatureGuard.baseModules in the Flutter app.
export const BASE_MODULES = ["dashboard", "patients", "appointments", "inventory"];

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
export function sanitiseModules(raw: unknown): string[] {
  const picked = Array.isArray(raw) ?
    raw
      .map((m) => String(m).toLowerCase().trim())
      .filter((m) => VALID_MODULES.has(m)) :
    [];
  return Array.from(new Set<string>([...BASE_MODULES, ...picked]));
}

/** What a verified payment bought, for [writePaidPlan]. */
export interface PaidPlan {
  /** The paid modules bought; the base modules are added here. */
  modules: string[];
  amountInr: number;
  paymentMethod: string;
  /** The bank's reference for the transfer (the UTR, for UPI). */
  transactionReference: string;
  /** Extra fields for the receipt, e.g. the gateway's payment id. */
  receipt?: Record<string, unknown>;
}

/**
 * Activates [plan] for 30 days on [uid]'s profile, inside a transaction.
 *
 * Only ever called once a payment has been verified (see plan-payments.ts);
 * there is deliberately no callable that does this on a client's say-so. The
 * previous `activateDoctorFeatures` callable trusted the amount the app sent,
 * so anyone signed in could unlock every module for nothing.
 *
 * [user] is users/{uid} as read in the same transaction, for the receipt.
 */
export function writePaidPlan(
  tx: admin.firestore.Transaction,
  uid: string,
  user: admin.firestore.DocumentData,
  plan: PaidPlan,
): {transactionId: string; validUntil: Timestamp} {
  const db = admin.firestore();
  const modules = sanitiseModules(plan.modules);
  const now = Timestamp.now();
  const validUntil = Timestamp.fromDate(
    new Date(Date.now() + PLAN_DAYS * 24 * 60 * 60 * 1000),
  );
  const transactionId =
    `TXN_${Date.now()}_${Math.random().toString(36).slice(2, 8).toUpperCase()}`;
  const allowMultiDevice = modules.includes("multi_device_access");

  tx.set(
    db.collection("users").doc(uid),
    {
      enabledModules: modules,
      status: "active",
      expiresDate: validUntil,
      allowMultiDevice,
      lastPaymentDate: now,
      lastTransactionId: transactionId,
      lastPaymentAmount: plan.amountInr,
      lastPaymentMethod: plan.paymentMethod,
    },
    {merge: true},
  );
  tx.set(
    db.collection("doctor_settings").doc(uid),
    {
      doctorId: uid,
      enabledModules: modules,
      allowMultiDevice,
      lastModified: now,
    },
    {merge: true},
  );
  tx.set(db.collection("payment_transactions").doc(transactionId), {
    transactionId,
    doctorId: uid,
    doctorEmail: String(user.email ?? ""),
    doctorName: decryptProfileField(user.name, uid) ||
      decryptProfileField(user.displayName, uid) || "Doctor",
    amount: plan.amountInr,
    currency: "INR",
    paymentMethod: plan.paymentMethod,
    transactionReference: plan.transactionReference,
    activatedModules: modules,
    validUntil,
    status: "success",
    timestamp: now,
    ...(plan.receipt ?? {}),
  });

  return {transactionId, validUntil};
}

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
      rawExpires instanceof Timestamp ?
        rawExpires.toMillis() :
        0;
    if (
      (status === "trial" || status === "active") &&
      expiresMs > Date.now()
    ) {
      const patch: Record<string, unknown> = {};
      if (existing.role !== "doctor") patch.role = "doctor";
      if (existing.isDeleted !== false) patch.isDeleted = false;
      if (data.modules && Array.isArray(data.modules)) {
        patch.enabledModules = modules;
        patch.allowMultiDevice = allowMultiDevice;
      }
      if (Object.keys(patch).length > 0) {
        await userRef.set(patch, {merge: true});
      }

      return {
        started: false,
        alreadyActive: true,
        validUntil: new Date(expiresMs).toISOString(),
        enabledModules: Array.isArray(existing.enabledModules) && !data.modules ?
          existing.enabledModules :
          modules,
      };
    }

    const now = Timestamp.now();
    const validUntil = Timestamp.fromDate(
      new Date(Date.now() + PLAN_DAYS * 24 * 60 * 60 * 1000),
    );

    await userRef.set(
      {
        role: "doctor",
        isDeleted: false,
        status: "trial",
        subscriptionPlan: "Trial",
        expiresDate: validUntil,
        enabledModules: modules,
        allowMultiDevice,
        trialStartedAt: now,
      },
      {merge: true},
    );

    try {
      await admin.auth().setCustomUserClaims(uid, {
        role: "doctor",
        enabledModules: modules,
      });
    } catch (err) {
      console.warn("Failed to set custom claims for doctor:", err);
    }

    return {
      started: true,
      alreadyActive: false,
      validUntil: validUntil.toDate().toISOString(),
      enabledModules: modules,
    };
  },
);
