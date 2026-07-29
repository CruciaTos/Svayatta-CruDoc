import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

admin.initializeApp();

const db = admin.firestore();
const auth = admin.auth();

// ============================================================
// 1. LOG ADMIN ACTION
// ============================================================

export const logAdminAction = functions.https.onCall(async (data: any, context: functions.https.CallableContext) => {
  // Verify Super Admin
  if (!context.auth || context.auth.token.role !== 'superAdmin') {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Only Super Admin can log actions'
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
    status = 'success',
    errorMessage,
  } = data;

  try {
    const logEntry: Record<string, unknown> = {
      adminEmail: adminEmail || context.auth.token.email,
      adminName: adminName || context.auth.token.name || 'Admin',
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

    await db.collection('audit_logs').add(logEntry);
    return { success: true };
  } catch (error) {
    throw new functions.https.HttpsError('internal', 'Failed to log action');
  }
});

// ============================================================
// 2. CREATE DOCTOR ACCOUNT (ATOMIC)
// ============================================================

export const createDoctor = functions.https.onCall(async (data: any, context: functions.https.CallableContext) => {
  // Verify Super Admin
  if (!context.auth || context.auth.token.role !== 'superAdmin') {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Only Super Admin can create doctors'
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
      'invalid-argument',
      'Name, email, and password are required'
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
      role: 'doctor',
      enabledModules: enabledModules || getDefaultModules(subscriptionPlan),
    });

    // Step 3: Create Firestore documents in batch
    const batch = db.batch();
    const now = admin.firestore.Timestamp.now();

    // Doctor document
    const doctorRef = db.collection('users').doc(doctorId);
    batch.set(doctorRef, {
      name,
      email,
      phone: phone || '',
      specialization: specialization || '',
      clinicName: clinicName || '',
      country: country || '',
      timeZone: timeZone || '',
      subscriptionPlan: subscriptionPlan || 'starter',
      status: 'active',
      role: 'doctor',
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
    const settingsRef = db.collection('doctor_settings').doc(doctorId);
    batch.set(settingsRef, {
      doctorId,
      enabledModules: enabledModules || getDefaultModules(subscriptionPlan),
      lastModified: now,
      createdAt: now,
    });

    // Subscription document
    const subRef = db.collection('subscriptions').doc(doctorId);
    batch.set(subRef, {
      doctorId,
      plan: subscriptionPlan || 'starter',
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
    await logAudit(context, 'createdDoctor', doctorId, name, email);

    return {
      success: true,
      doctorId,
      message: 'Doctor account created successfully',
    };
  } catch (error) {
    // Rollback: If auth user was created but Firestore failed, delete auth user
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    if ((error as Record<string, string>).code === 'auth/email-already-exists') {
      throw new functions.https.HttpsError(
        'already-exists',
        'A doctor with this email already exists'
      );
    }
    throw new functions.https.HttpsError('internal', errorMessage);
  }
});

// ============================================================
// 3. DELETE DOCTOR (SOFT DELETE WITH CASCADE)
// ============================================================

export const deleteDoctor = functions.https.onCall(async (data: any, context: functions.https.CallableContext) => {
  if (!context.auth || context.auth.token.role !== 'superAdmin') {
    throw new functions.https.HttpsError('permission-denied', 'Unauthorized');
  }

  const { doctorId } = data;
  if (!doctorId) {
    throw new functions.https.HttpsError('invalid-argument', 'Doctor ID required');
  }

  try {
    const batch = db.batch();
    const now = admin.firestore.Timestamp.now();

    // Soft delete user document
    batch.update(db.collection('users').doc(doctorId), {
      isDeleted: true,
      status: 'expired',
      deletedAt: now,
      deletedBy: context.auth.token.email,
    });

    // Disable Firebase Auth user
    await auth.updateUser(doctorId, { disabled: true });

    await batch.commit();

    // Log audit
    await logAudit(context, 'deletedDoctor', doctorId);

    return { success: true, message: 'Doctor account deleted' };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    throw new functions.https.HttpsError('internal', errorMessage);
  }
});

// ============================================================
// 4. CHANGE DOCTOR SUBSCRIPTION PLAN
// ============================================================

export const changeDoctorPlan = functions.https.onCall(async (data: any, context: functions.https.CallableContext) => {
  if (!context.auth || context.auth.token.role !== 'superAdmin') {
    throw new functions.https.HttpsError('permission-denied', 'Unauthorized');
  }

  const { doctorId, newPlan, reason } = data;

  try {
    // Get current subscription
    const subDoc = await db.collection('subscriptions').doc(doctorId).get();
    if (!subDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Subscription not found');
    }

    const subData = subDoc.data();
    const oldPlan = subData?.plan || 'starter';
    const now = admin.firestore.Timestamp.now();

    // Update subscription
    await db.collection('subscriptions').doc(doctorId).update({
      plan: newPlan,
      lastModified: now,
      modifiedBy: context.auth.token.email,
      history: admin.firestore.FieldValue.arrayUnion({
        oldPlan,
        newPlan,
        changedAt: now,
        changedBy: context.auth.token.email,
        reason: reason || 'Plan changed by admin',
      }),
    });

    // Update storage limit based on new plan
    const planLimits: Record<string, number> = {
      starter: 5,
      professional: 20,
      clinic: 50,
      enterprise: 200,
    };

    const storageLimit = typeof newPlan === 'string' && newPlan in planLimits
      ? planLimits[newPlan]
      : 5;

    await db.collection('users').doc(doctorId).update({
      subscriptionPlan: newPlan,
      storageLimitGB: storageLimit,
    });

    // Log audit
    await logAudit(
      context,
      'changedPlan',
      doctorId,
      undefined,
      undefined,
      { oldPlan, newPlan }
    );

    return { success: true };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    throw new functions.https.HttpsError('internal', errorMessage);
  }
});

// ============================================================
// 5. CALCULATE DASHBOARD STATS (SCHEDULED)
// ============================================================

export const calculateDashboardStats = functions.pubsub
  .schedule('every 1 hours')
  .onRun(async () => {
    try {
      const doctorsSnapshot = await db
        .collection('users')
        .where('role', '==', 'doctor')
        .where('isDeleted', '==', false)
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

        if (data.status === 'active') activeDoctors++;
        if (data.subscriptionPlan === 'trial') trialAccounts++;
        if (data.status === 'expired') expiredAccounts++;

        totalPatients += data.patientCount || 0;
        totalStorageGB += data.storageUsedGB || 0;

        const plan: string = data.subscriptionPlan || 'starter';
        doctorsByPlan[plan] = (doctorsByPlan[plan] || 0) + 1;
        subscriptionRevenue += planPrices[plan] || 0;
      }

      const today = new Date();
      const dateKey = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;

      // Store analytics
      await db.collection('analytics').doc(dateKey).set({
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
      const monthKey = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}`;
      await db.collection('analytics').doc(`growth_${monthKey}`).set({
        totalDoctors,
        activeDoctors,
        timestamp: admin.firestore.Timestamp.fromDate(today),
      });

      console.log(`Dashboard stats calculated for ${dateKey}: ${totalDoctors} doctors`);
    } catch (error) {
      console.error('Failed to calculate dashboard stats:', error);
    }
  });

// ============================================================
// 6. EXTEND DOCTOR TRIAL
// ============================================================

export const extendTrial = functions.https.onCall(async (data: any, context: functions.https.CallableContext) => {
  if (!context.auth || context.auth.token.role !== 'superAdmin') {
    throw new functions.https.HttpsError('permission-denied', 'Unauthorized');
  }

  const { doctorId, additionalDays } = data;

  try {
    const subDoc = await db.collection('subscriptions').doc(doctorId).get();
    if (!subDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Subscription not found');
    }

    const subData = subDoc.data();
    const currentTrialEnd = subData?.trialEndDate?.toDate?.();
    const now = new Date();
    const currentEnd = currentTrialEnd instanceof Date ? currentTrialEnd : now;
    const newTrialEnd = currentEnd > now
      ? new Date(currentEnd.getTime() + additionalDays * 24 * 60 * 60 * 1000)
      : new Date(now.getTime() + additionalDays * 24 * 60 * 60 * 1000);

    await db.collection('subscriptions').doc(doctorId).update({
      isTrial: true,
      trialEndDate: admin.firestore.Timestamp.fromDate(newTrialEnd),
      lastModified: admin.firestore.Timestamp.now(),
      modifiedBy: context.auth.token.email,
    });

    // Log audit
    await logAudit(context, 'extendedTrial', doctorId, undefined, undefined, {
      additionalDays,
      newTrialEnd: newTrialEnd.toISOString(),
    });

    return { success: true, newTrialEnd: newTrialEnd.toISOString() };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    throw new functions.https.HttpsError('internal', errorMessage);
  }
});

// ============================================================
// 7. SEND ANNOUNCEMENT
// ============================================================

export const sendAnnouncement = functions.https.onCall(async (data: any, context: functions.https.CallableContext) => {
  if (!context.auth || context.auth.token.role !== 'superAdmin') {
    throw new functions.https.HttpsError('permission-denied', 'Unauthorized');
  }

  const { title, message, targetDoctors } = data;

  try {
    let doctorsQuery: admin.firestore.Query;

    if (targetDoctors && targetDoctors.length > 0) {
      // Send to specific doctors
      doctorsQuery = db.collection('users').where(
        admin.firestore.FieldPath.documentId(),
        'in',
        targetDoctors
      );
    } else {
      // Send to all active doctors
      doctorsQuery = db
        .collection('users')
        .where('role', '==', 'doctor')
        .where('isDeleted', '==', false)
        .where('status', '==', 'active');
    }

    const doctorsSnapshot = await doctorsQuery.get();
    const batch = db.batch();
    const now = admin.firestore.Timestamp.now();

    doctorsSnapshot.docs.forEach((doc: admin.firestore.QueryDocumentSnapshot) => {
      const notifRef = db.collection('notifications').doc();
      batch.set(notifRef, {
        doctorId: doc.id,
        title,
        message,
        type: 'announcement',
        read: false,
        createdAt: now,
        sentBy: context.auth?.token.email || 'unknown',
      });
    });

    await batch.commit();

    // Log audit
    await logAudit(context, 'sentAnnouncement', undefined, undefined, undefined, {
      recipientCount: doctorsSnapshot.docs.length,
      title,
    });

    return {
      success: true,
      sentCount: doctorsSnapshot.docs.length,
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    throw new functions.https.HttpsError('internal', errorMessage);
  }
});

// ============================================================
// 8. SUSPEND/ACTIVATE DOCTOR
// ============================================================

export const toggleDoctorStatus = functions.https.onCall(async (data: any, context: functions.https.CallableContext) => {
  if (!context.auth || context.auth.token.role !== 'superAdmin') {
    throw new functions.https.HttpsError('permission-denied', 'Unauthorized');
  }

  const { doctorId, action, reason } = data;
  const isSuspend = action === 'suspend';

  try {
    const updates: Record<string, unknown> = {};

    if (isSuspend) {
      updates.status = 'suspended';
      updates.suspendedAt = admin.firestore.FieldValue.serverTimestamp();
      updates.suspendedBy = context.auth.token.email;
      updates.suspensionReason = reason || null;
    } else {
      updates.status = 'active';
      updates.activatedAt = admin.firestore.FieldValue.serverTimestamp();
      updates.activatedBy = context.auth.token.email;
      updates.suspensionReason = null;
    }

    await db.collection('users').doc(doctorId).update(updates);
    await auth.updateUser(doctorId, { disabled: isSuspend });

    // Log audit
    await logAudit(
      context,
      isSuspend ? 'suspendedAccount' : 'activatedAccount',
      doctorId,
      undefined,
      undefined,
      { reason }
    );

    return { success: true };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    throw new functions.https.HttpsError('internal', errorMessage);
  }
});

// ============================================================
// HELPER: Log audit entry
// ============================================================

async function logAudit(
  context: functions.https.CallableContext,
  actionType: string,
  targetDoctorId?: string,
  targetDoctorName?: string,
  targetDoctorEmail?: string,
  details?: Record<string, unknown>
) {
  try {
    await db.collection('audit_logs').add({
      adminEmail: context.auth?.token.email || 'unknown',
      adminName: context.auth?.token.name || 'Admin',
      actionType,
      targetDoctorId: targetDoctorId || null,
      targetDoctorName: targetDoctorName || null,
      targetDoctorEmail: targetDoctorEmail || null,
      details: details || null,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      status: 'success',
      ipAddress: context.rawRequest
        ? (context.rawRequest as unknown as Record<string, unknown>).ip || null
        : null,
    });
  } catch (error) {
    console.error('Failed to log audit:', error);
  }
}

// ============================================================
// HELPER: Get default modules for a plan
// ============================================================

function getDefaultModules(plan: string): string[] {
  const base = ['dashboard', 'patients', 'appointments', 'inventory', 'reports'];

  switch (plan) {
    case 'starter':
      return base;
    case 'professional':
      return [...base, 'revenue', 'analytics', 'session_history'];
    case 'clinic':
      return [
        ...base,
        'revenue',
        'analytics',
        'session_history',
        'home_visits',
        'medicine_ocr',
        'prescription_generator',
        'packages',
      ];
    case 'enterprise':
      return [
        ...base,
        'revenue',
        'analytics',
        'session_history',
        'home_visits',
        'medicine_ocr',
        'medicine_bills',
        'prescription_generator',
        'packages',
        'online_consultation',
        'whatsapp_integration',
        'ai_assistant',
        'custom_branding',
      ];
    default:
      return base;
  }
}