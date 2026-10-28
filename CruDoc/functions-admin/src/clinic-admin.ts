import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

/** Most seats of one kind a clinic can be given from the console. */
const MAX_SEATS = 500;

/**
 * Super Admin sets how many doctor and staff seats a clinic has
 * (`clinics/{clinicId}.seats`). The clinicTeam function in the main
 * codebase counts active members plus pending invites against these
 * before it sends an invite. Lowering a limit below what is in use keeps
 * everyone already there; it only blocks new invites.
 *
 * The rules don't let the console write clinics/{id}, so it goes through
 * here, with an audit entry.
 */
export const setClinicSeats = onCall(async (request) => {
  const token = request.auth?.token;
  if (!token || token.role !== "superAdmin" || token.isTwoFAVerified !== true) {
    throw new HttpsError("permission-denied", "Only Super Admin can change clinic seats.");
  }

  const data = (request.data || {}) as Record<string, unknown>;
  const clinicId = typeof data.clinicId === "string" ? data.clinicId.trim() : "";
  if (!clinicId) throw new HttpsError("invalid-argument", "clinicId is required.");
  const doctor = seats(data.doctor, "doctor");
  const staff = seats(data.staff, "staff");

  const db = admin.firestore();
  const clinicRef = db.collection("clinics").doc(clinicId);
  const snap = await clinicRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "Clinic not found.");

  const before = snap.get("seats") ?? null;
  await clinicRef.update({
    seats: {doctor, staff},
    seatsSetBy: token.email ?? request.auth?.uid ?? "superAdmin",
    seatsSetAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  try {
    await db.collection("audit_logs").add({
      adminEmail: token.email || "unknown",
      adminName: token.name || "Admin",
      actionType: "updatedClinicSeats",
      targetDoctorId: clinicId,
      details: {clinicId, doctor, staff},
      beforeValues: {seats: before},
      afterValues: {seats: {doctor, staff}},
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      status: "success",
    });
  } catch (error) {
    console.error("Failed to write audit log:", error);
  }

  return {success: true, seats: {doctor, staff}};
});

function seats(value: unknown, kind: string): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1 || value > MAX_SEATS) {
    throw new HttpsError(
      "invalid-argument",
      `${kind} seats must be a whole number from 1 to ${MAX_SEATS}.`
    );
  }
  return value;
}
