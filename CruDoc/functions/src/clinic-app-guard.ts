import {CallableRequest, HttpsError} from "firebase-functions/v2/https";

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
