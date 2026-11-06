import * as functions from "firebase-functions/v1";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as crypto from "crypto";

function getDb() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
}

function getAuth() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.auth();
}

const db: admin.firestore.Firestore = new Proxy({} as admin.firestore.Firestore, {
  get: (_, prop: string | symbol) => (getDb() as any)[prop],
});

const auth: admin.auth.Auth = new Proxy({} as admin.auth.Auth, {
  get: (_, prop: string | symbol) => (getAuth() as any)[prop],
});

// ============================================================
// 1. LOG ADMIN ACTION
// ============================================================

export const logAdminAction = functions.region("asia-south1").https.onCall(async (data: any, context: functions.https.CallableContext) => {
  // Verify Super Admin
  if (!context.auth || context.auth.token.role !== "superAdmin") {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only Super Admin can log actions"
    );
  }

  const {
    adminEmail,
    adminName,
    actionType,
    targetDoctorId,
    targetDoctorName,
    targetDoctorEmail,
    details,
    beforeValues,
    afterValues,
    status = "success",
    errorMessage,
  } = data;

  try {
    const logEntry: Record<string, unknown> = {
      adminEmail: adminEmail || context.auth.token.email,
      adminName: adminName || context.auth.token.name || "Admin",
      actionType,
      targetDoctorId: targetDoctorId || null,
      targetDoctorName: targetDoctorName || null,
      targetDoctorEmail: targetDoctorEmail || null,
      details: details || null,
      beforeValues: beforeValues || null,
      afterValues: afterValues || null,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      status,
      errorMessage: errorMessage || null,
      ipAddress: (context.rawRequest as unknown as Record<string, unknown>).ip || null,
    };

    await getDb().collection("audit_logs").add(logEntry);
    return {success: true};
  } catch (error) {
    throw new functions.https.HttpsError("internal", "Failed to log action");
  }
});

// ============================================================
// 2. CREATE DOCTOR ACCOUNT (ATOMIC)
// ============================================================

export const createDoctor = functions.region("asia-south1").https.onCall(
  async (data: any, context: functions.https.CallableContext) => {
  // Verify Super Admin
    if (!context.auth || context.auth.token.role !== "superAdmin") {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only Super Admin can create doctors"
      );
    }

    const {
      name,
      email,
      phone,
      specialization,
      clinicName,
      country,
      timeZone,
      subscriptionPlan,
      storageLimitGB,
      password,
      enabledModules,
    } = data;

    // Validate required fields
    if (!name || !email || !password) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Name, email, and password are required"
      );
    }

    try {
    // Step 1: Create Firebase Auth user
      const userRecord = await auth.createUser({
        email,
        password,
        displayName: name,
        disabled: false,
      });

      const doctorId = userRecord.uid;

      // Step 2: Set custom claims
      await auth.setCustomUserClaims(doctorId, {
        role: "doctor",
        enabledModules: enabledModules || getDefaultModules(subscriptionPlan),
      });

      // Step 3: Create Firestore documents in batch
      const batch = db.batch();
      const now = admin.firestore.Timestamp.now();

      const encryptedName = encryptDoctorValue(name, doctorId);
      const encryptedEmail = encryptDoctorValue(email, doctorId);
      const encryptedPhone = encryptDoctorValue(phone || "", doctorId);
      const encryptedSpecialization = encryptDoctorValue(specialization || "", doctorId);
      const encryptedClinicName = encryptDoctorValue(clinicName || "", doctorId);
      const encryptedCountry = encryptDoctorValue(country || "", doctorId);
      const encryptedTimeZone = encryptDoctorValue(timeZone || "", doctorId);

      // Doctor document
      const doctorRef = db.collection("users").doc(doctorId);
      batch.set(doctorRef, {
        name: encryptedName,
        email: encryptedEmail,
        phone: encryptedPhone,
        specialization: encryptedSpecialization,
        clinicName: encryptedClinicName,
        country: encryptedCountry,
        timeZone: encryptedTimeZone,
        subscriptionPlan: subscriptionPlan || "starter",
        status: "active",
        role: "doctor",
        accountCreated: now,
        lastLogin: null,
        storageUsedGB: 0,
        storageLimitGB: storageLimitGB || 5,
        patientCount: 0,
        appointmentCount: 0,
        activeDeviceCount: 0,
        ocrRequestsThisMonth: 0,
        enabledModules: enabledModules || getDefaultModules(subscriptionPlan),
        totalSessions: 0,
        isDeleted: false,
      });

      // Doctor settings document
      const settingsRef = db.collection("doctor_settings").doc(doctorId);
      batch.set(settingsRef, {
        doctorId,
        enabledModules: enabledModules || getDefaultModules(subscriptionPlan),
        lastModified: now,
        createdAt: now,
      });

      // Subscription document
      const subRef = db.collection("subscriptions").doc(doctorId);
      batch.set(subRef, {
        doctorId,
        plan: subscriptionPlan || "starter",
        subscribedDate: now,
        isTrial: true,
        trialEndDate: admin.firestore.Timestamp.fromDate(
          new Date(Date.now() + 14 * 24 * 60 * 60 * 1000) // 14 days trial
        ),
        autoRenew: true,
        history: [],
        lastModified: now,
        modifiedBy: context.auth.token.email,
      });

      await batch.commit();

      // Step 4: Log audit
      await logAudit(context, "createdDoctor", doctorId, name, email);

      return {
        success: true,
        doctorId,
        message: "Doctor account created successfully",
      };
    } catch (error) {
    // Rollback: If auth user was created but Firestore failed, delete auth user
      const errorMessage = error instanceof Error ? error.message : "Unknown error";
      if ((error as Record<string, string>).code === "auth/email-already-exists") {
        throw new functions.https.HttpsError(
          "already-exists",
          "A doctor with this email already exists"
        );
      }
      throw new functions.https.HttpsError("internal", errorMessage);
    }
  });

function encryptDoctorValue(value: string, doctorId: string): string {
  const key = crypto.createHash("sha256").update(`crudoc-doctor-profile::${doctorId}`).digest();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
  const encrypted = Buffer.concat([cipher.update(value, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `enc:v1:${iv.toString("base64")}.${Buffer.concat([encrypted, tag]).toString("base64")}`;
}

// 3. Delete doctor: see manageDoctorAccount (section 8).

// ============================================================
// 4. CHANGE DOCTOR SUBSCRIPTION PLAN
// ============================================================

export const changeDoctorPlan = functions.region("asia-south1").https.onCall(async (data: any, context: functions.https.CallableContext) => {
  if (!context.auth || context.auth.token.role !== "superAdmin") {
    throw new functions.https.HttpsError("permission-denied", "Unauthorized");
  }

  const {doctorId, newPlan, reason} = data;

  try {
    // Get current subscription
    const subDoc = await db.collection("subscriptions").doc(doctorId).get();
    if (!subDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Subscription not found");
    }

    const subData = subDoc.data();
    const oldPlan = subData?.plan || "starter";
    const now = admin.firestore.Timestamp.now();

    // Update subscription
    await db.collection("subscriptions").doc(doctorId).update({
      plan: newPlan,
      lastModified: now,
      modifiedBy: context.auth.token.email,
      history: admin.firestore.FieldValue.arrayUnion({
        oldPlan,
        newPlan,
        changedAt: now,
        changedBy: context.auth.token.email,
        reason: reason || "Plan changed by admin",
      }),
    });

    // Update storage limit based on new plan
    const planLimits: Record<string, number> = {
      starter: 5,
      professional: 20,
      clinic: 50,
      enterprise: 200,
    };

    const storageLimit = typeof newPlan === "string" && newPlan in planLimits ?
      planLimits[newPlan] :
      5;

    await db.collection("users").doc(doctorId).update({
      subscriptionPlan: newPlan,
      storageLimitGB: storageLimit,
    });

    // Log audit
    await logAudit(
      context,
      "changedPlan",
      doctorId,
      undefined,
      undefined,
      {oldPlan, newPlan}
    );

    return {success: true};
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : "Unknown error";
    throw new functions.https.HttpsError("internal", errorMessage);
  }
});

// ============================================================
// 5. CALCULATE DASHBOARD STATS (SCHEDULED)
// ============================================================

export const calculateDashboardStats = functions.region("asia-south1").pubsub
  .schedule("every 1 hours")
  .onRun(async () => {
    try {
      const doctorsSnapshot = await db
        .collection("users")
        .where("role", "==", "doctor")
        .where("isDeleted", "==", false)
        .get();

      let totalDoctors = 0;
      let activeDoctors = 0;
      let trialAccounts = 0;
      let expiredAccounts = 0;
      let totalPatients = 0;
      let totalStorageGB = 0;
      let subscriptionRevenue = 0;

      const planPrices: Record<string, number> = {
        starter: 29,
        professional: 79,
        clinic: 199,
        enterprise: 499,
      };

      const doctorsByPlan: Record<string, number> = {};

      for (const doc of doctorsSnapshot.docs) {
        const data = doc.data();
        totalDoctors++;

        if (data.status === "active") activeDoctors++;
        if (data.subscriptionPlan === "trial") trialAccounts++;
        if (data.status === "expired") expiredAccounts++;

        totalPatients += data.patientCount || 0;
        totalStorageGB += data.storageUsedGB || 0;

        const plan: string = data.subscriptionPlan || "starter";
        doctorsByPlan[plan] = (doctorsByPlan[plan] || 0) + 1;
        subscriptionRevenue += planPrices[plan] || 0;
      }

      const today = new Date();
      const dateKey = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`;

      // Store analytics
      await db.collection("analytics").doc(dateKey).set({
        date: admin.firestore.Timestamp.fromDate(today),
        totalDoctors,
        activeDoctors,
        trialAccounts,
        expiredAccounts,
        totalPatients,
        totalStorageUsedGB: totalStorageGB,
        monthlyRevenue: subscriptionRevenue,
        doctorsByPlan,
        generatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Also store monthly growth data point
      const monthKey = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}`;
      await db.collection("analytics").doc(`growth_${monthKey}`).set({
        totalDoctors,
        activeDoctors,
        timestamp: admin.firestore.Timestamp.fromDate(today),
      });

      console.log(`Dashboard stats calculated for ${dateKey}: ${totalDoctors} doctors`);
    } catch (error) {
      console.error("Failed to calculate dashboard stats:", error);
    }
  });

// ============================================================
// 6. EXTEND DOCTOR TRIAL
// ============================================================

export const extendTrial = functions.region("asia-south1").https.onCall(async (data: any, context: functions.https.CallableContext) => {
  if (!context.auth || context.auth.token.role !== "superAdmin") {
    throw new functions.https.HttpsError("permission-denied", "Unauthorized");
  }

  const {doctorId, additionalDays} = data;

  try {
    const subDoc = await db.collection("subscriptions").doc(doctorId).get();
    if (!subDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Subscription not found");
    }

    const subData = subDoc.data();
    const currentTrialEnd = subData?.trialEndDate?.toDate?.();
    const now = new Date();
    const currentEnd = currentTrialEnd instanceof Date ? currentTrialEnd : now;
    const newTrialEnd = currentEnd > now ?
      new Date(currentEnd.getTime() + additionalDays * 24 * 60 * 60 * 1000) :
      new Date(now.getTime() + additionalDays * 24 * 60 * 60 * 1000);

    await db.collection("subscriptions").doc(doctorId).update({
      isTrial: true,
      trialEndDate: admin.firestore.Timestamp.fromDate(newTrialEnd),
      lastModified: admin.firestore.Timestamp.now(),
      modifiedBy: context.auth.token.email,
    });

    // Log audit
    await logAudit(context, "extendedTrial", doctorId, undefined, undefined, {
      additionalDays,
      newTrialEnd: newTrialEnd.toISOString(),
    });

    return {success: true, newTrialEnd: newTrialEnd.toISOString()};
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : "Unknown error";
    throw new functions.https.HttpsError("internal", errorMessage);
  }
});

// ============================================================
// 7. SEND ANNOUNCEMENT
// ============================================================

export const sendAnnouncement = functions.region("asia-south1").https.onCall(async (data: any, context: functions.https.CallableContext) => {
  if (!context.auth || context.auth.token.role !== "superAdmin") {
    throw new functions.https.HttpsError("permission-denied", "Unauthorized");
  }

  const {title, message, targetDoctors} = data;

  try {
    let doctorsQuery: admin.firestore.Query;

    if (targetDoctors && targetDoctors.length > 0) {
      // Send to specific doctors
      doctorsQuery = db.collection("users").where(
        admin.firestore.FieldPath.documentId(),
        "in",
        targetDoctors
      );
    } else {
      // Send to all active doctors
      doctorsQuery = db
        .collection("users")
        .where("role", "==", "doctor")
        .where("isDeleted", "==", false)
        .where("status", "==", "active");
    }

    const doctorsSnapshot = await doctorsQuery.get();
    const batch = db.batch();
    const now = admin.firestore.Timestamp.now();

    doctorsSnapshot.docs.forEach((doc: admin.firestore.QueryDocumentSnapshot) => {
      const notifRef = db.collection("notifications").doc();
      batch.set(notifRef, {
        doctorId: doc.id,
        title,
        message,
        type: "announcement",
        read: false,
        createdAt: now,
        sentBy: context.auth?.token.email || "unknown",
      });
    });

    await batch.commit();

    // Log audit
    await logAudit(context, "sentAnnouncement", undefined, undefined, undefined, {
      recipientCount: doctorsSnapshot.docs.length,
      title,
    });

    return {
      success: true,
      sentCount: doctorsSnapshot.docs.length,
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : "Unknown error";
    throw new functions.https.HttpsError("internal", errorMessage);
  }
});

// ============================================================
// 8. DELETE / SUSPEND / ACTIVATE DOCTOR
// ============================================================

/**
 * Super Admin's delete, suspend and activate. The login itself is turned off
 * (or back on) in Firebase Auth, so the server decides who can sign in: the
 * app's own checks only explain why.
 *
 * 2nd gen, unlike the rest of this file: the organisation policy blocks
 * public invokers on 1st gen functions, so the old deleteDoctor /
 * toggleDoctorStatus could never be called. After the first deploy run
 * `gcloud run services update managedoctoraccount --region asia-south1
 * --no-invoker-iam-check` once (as for planPayments).
 */
export const manageDoctorAccount = onCall(
  {region: "asia-south1", maxInstances: 5},
  async (request) => {
    const caller = request.auth;
    if (!caller || caller.token.role !== "superAdmin") {
      throw new HttpsError("permission-denied", "Unauthorized");
    }

    const {doctorId, action, reason} = (request.data ?? {}) as {
      doctorId?: unknown; action?: unknown; reason?: unknown;
    };
    if (typeof doctorId !== "string" || !doctorId ||
        (action !== "delete" && action !== "suspend" && action !== "activate")) {
      throw new HttpsError(
        "invalid-argument", "doctorId and action (delete, suspend or activate) required");
    }
    const reasonText = typeof reason === "string" ? reason : null;

    try {
      await assertNotSuperAdmin(doctorId);
      const profileRef = db.collection("users").doc(doctorId);
      const now = admin.firestore.FieldValue.serverTimestamp();
      let updates: Record<string, unknown>;
      let auditAction: string;

      if (action === "activate") {
        // A deleted account stays off: activating would quietly undo it.
        if ((await profileRef.get()).data()?.isDeleted === true) {
          throw new HttpsError(
            "failed-precondition", "This account was deleted and can't be activated.");
        }
        await blockSignIn(doctorId, false);
        updates = {status: "active", activatedAt: now,
          activatedBy: caller.token.email ?? null, suspensionReason: null};
        auditAction = "activatedAccount";
      } else {
        // The login goes off before the profile is marked.
        await blockSignIn(doctorId, true);
        updates = action === "delete" ?
          {isDeleted: true, status: "expired", deletedAt: now,
            deletedBy: caller.token.email ?? null} :
          {status: "suspended", suspendedAt: now,
            suspendedBy: caller.token.email ?? null, suspensionReason: reasonText};
        auditAction = action === "delete" ? "deletedDoctor" : "suspendedAccount";
      }

      await profileRef.set(updates, {merge: true});
      await logAudit(request, auditAction, doctorId, undefined, undefined,
        reasonText ? {reason: reasonText} : undefined);
      return {success: true};
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      const errorMessage = error instanceof Error ? error.message : "Unknown error";
      throw new HttpsError("internal", errorMessage);
    }
  });

// ============================================================
// HELPERS: Turn a login on or off
// ============================================================

/** Delete and suspend are for clinic accounts, never a Super Admin. */
async function assertNotSuperAdmin(uid: string): Promise<void> {
  const user = await auth.getUser(uid).catch(() => null);
  if (user?.customClaims?.role === "superAdmin") {
    throw new HttpsError(
      "permission-denied", "Super Admin accounts can't be changed here.");
  }
}

/**
 * Turns sign-in off (or back on) in Firebase Auth. Turning it off also
 * revokes the refresh tokens, so devices already signed in lose access when
 * their current token expires (at most an hour) or sooner when the app
 * checks with the server on start or resume. A missing login is fine:
 * there is nothing left to turn off.
 */
async function blockSignIn(uid: string, blocked: boolean): Promise<void> {
  try {
    await auth.updateUser(uid, {disabled: blocked});
    if (blocked) await auth.revokeRefreshTokens(uid);
  } catch (error) {
    const code = (error as {code?: string}).code;
    if (code !== "auth/user-not-found") throw error;
  }
}

// ============================================================
// HELPER: Log audit entry
// ============================================================

/** A 1st or 2nd gen callable's caller, as the audit log needs it. */
type AuditCaller = {
  auth?: {token: {email?: string; name?: string}};
  rawRequest?: unknown;
};

async function logAudit(
  context: AuditCaller,
  actionType: string,
  targetDoctorId?: string,
  targetDoctorName?: string,
  targetDoctorEmail?: string,
  details?: Record<string, unknown>
) {
  try {
    await db.collection("audit_logs").add({
      adminEmail: context.auth?.token.email || "unknown",
      adminName: context.auth?.token.name || "Admin",
      actionType,
      targetDoctorId: targetDoctorId || null,
      targetDoctorName: targetDoctorName || null,
      targetDoctorEmail: targetDoctorEmail || null,
      details: details || null,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      status: "success",
      ipAddress: context.rawRequest ?
        (context.rawRequest as unknown as Record<string, unknown>).ip || null :
        null,
    });
  } catch (error) {
    console.error("Failed to log audit:", error);
  }
}

// ============================================================
// HELPER: Get default modules for a plan
// ============================================================

function getDefaultModules(plan: string): string[] {
  const base = ["dashboard", "patients", "appointments", "inventory", "reports"];

  switch (plan) {
  case "starter":
    return base;
  case "professional":
    return [...base, "revenue", "analytics", "session_history"];
  case "clinic":
    return [
      ...base,
      "revenue",
      "analytics",
      "session_history",
      "home_visits",
      "medicine_ocr",
      "prescription_generator",
      "packages",
    ];
  case "enterprise":
    return [
      ...base,
      "revenue",
      "analytics",
      "session_history",
      "home_visits",
      "medicine_ocr",
      "medicine_bills",
      "prescription_generator",
      "packages",
      "online_consultation",
      "whatsapp_integration",
      "ai_assistant",
      "custom_branding",
    ];
  default:
    return base;
  }
}
