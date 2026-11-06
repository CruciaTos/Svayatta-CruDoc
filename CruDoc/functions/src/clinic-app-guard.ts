import {CallableRequest, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {Timestamp} from "firebase-admin/firestore";

// Kept when a plan expires. Mirrors BASE_MODULES in subscription.ts and
// DoctorFeatureGuard.baseModules in the app.
const BASE_MODULES = ["dashboard", "patients", "appointments", "inventory"];

/**
 * Refuses unless the caller's clinic plan includes [module], the same list
 * Super Admin sets (`users/{clinicId}.enabledModules`). An expired plan keeps
 * only the base modules; a profile with no list keeps the app's defaults, so
 * it is allowed. Staff use their clinic's plan.
 */
export async function requirePlanModule(
  uid: string,
  module: string,
  feature: string,
): Promise<void> {
  const db = admin.firestore();
  const me = (await db.collection("users").doc(uid).get()).data() ?? {};
  const clinicId = typeof me.clinicId === "string" && me.clinicId ? me.clinicId : uid;
  const plan = clinicId === uid ?
    me :
    (await db.collection("users").doc(clinicId).get()).data() ?? {};

  const list = Array.isArray(plan.enabledModules) ?
    plan.enabledModules.map((m: unknown) => String(m).toLowerCase()) :
    null;
  const expires = plan.expiresDate instanceof Timestamp ? plan.expiresDate.toMillis() : null;
  const expired = String(plan.status ?? "").toLowerCase() === "expired" ||
    (expires !== null && expires < Date.now());
  const inPlan = list === null || list.includes(module);
  if (inPlan && (!expired || BASE_MODULES.includes(module))) return;

  throw new HttpsError(
    "permission-denied",
    `${feature} isn't in your plan. Add it in Subscription & Billing.`,
  );
}

/**
 * Super Admin logins run the Super Admin panel only, never a clinic: a
 * clinic, trial or plan started from one turned the admin into a "doctor"
 * (role and custom claims overwritten). Clinic-app functions call this
 * first, so the server refuses whatever the app does.
 */
export function rejectSuperAdmin(
  request: CallableRequest,
  profile?: Record<string, unknown>,
): void {
  if (request.auth?.token.role === "superAdmin" || profile?.role === "superAdmin") {
    throw new HttpsError(
      "permission-denied",
      "Super Admin accounts can't be used in the clinic app. " +
        "Sign in with a doctor account instead.",
    );
  }
}
