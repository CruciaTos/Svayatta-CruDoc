import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";

/**
 * The profile fields clinic app builds before 21 Oct 2026 didn't write:
 * `role`, `isDeleted` and `accountCreated`. Without them Super Admin's
 * lists, counts and queries (`role == "doctor"`) miss the account.
 *
 * Returns only what is missing. Super Admins, other roles and clinic staff
 * (`memberKind: "staff"`) get nothing.
 */
export function profileDefaults(
  data: Record<string, unknown>,
  createTime?: Timestamp,
): Record<string, unknown> {
  const role = typeof data.role === "string" ? data.role : "";
  if (role && role !== "doctor") return {};
  if (data.memberKind === "staff") return {};

  const patch: Record<string, unknown> = {};
  if (!role) patch.role = "doctor";
  if (data.isDeleted === undefined || data.isDeleted === null) {
    patch.isDeleted = false;
  }
  if (!(data.accountCreated instanceof Timestamp)) {
    patch.accountCreated =
      data.createdAt instanceof Timestamp ?
        data.createdAt :
        createTime ?? FieldValue.serverTimestamp();
  }
  return patch;
}

/**
 * Fills in [profileDefaults] whenever a profile is written, so accounts
 * made by older app builds still in use show up in Super Admin. It stops
 * after one pass: the next write finds nothing missing.
 */
export const fillProfileDefaults = onDocumentWritten(
  {document: "users/{uid}", region: "asia-south1"},
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;
    const patch = profileDefaults(after.data() ?? {}, after.createTime);
    if (Object.keys(patch).length === 0) return;
    await after.ref.set(patch, {merge: true});
  },
);
