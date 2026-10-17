import {onDocumentWritten} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

/**
 * Keeps a copy of each patient's `assignedDoctorUids` on their clinical
 * records.
 *
 * Why a copy: in a clinic that scopes doctors to their own patients, the
 * clinic-wide sync reads clinical records with one query per collection. A
 * Firestore rule for a query is satisfied from the query's own filters, not
 * by reading each result, so it cannot look up each record's patient. The
 * rule can, however, check `where('assignedDoctorUids', 'array-contains',
 * uid)` — which needs the assignment on the record itself.
 *
 * The copy is never trusted on its own for single reads: firestore.rules
 * checks the real patient for those. It only lets the sync narrow its query.
 * Clients may not write it (the rules refuse); these functions own it.
 */

/** Collections holding a patient's clinical records. Keep in sync with
 * isClinicalRecord() in firestore.rules. */
export const CLINICAL_COLLECTIONS = [
  "dental_records",
  "radiology_docs",
  "homeopathy_case_sheets",
  "homeopathy_session_notes",
  "tooth_chart_entries",
  "procedure_log_entries",
  "treatment_plan_line_items",
];

const BATCH_LIMIT = 400;

/** Trimmed, unique, sorted: so two lists that mean the same compare equal. */
export function normalizeUids(input: unknown): string[] {
  if (!Array.isArray(input)) return [];
  const out = new Set<string>();
  for (const v of input) {
    const s = String(v ?? "").trim();
    if (s) out.add(s);
  }
  return Array.from(out).sort();
}

export function sameUids(a: unknown, b: unknown): boolean {
  const x = normalizeUids(a);
  const y = normalizeUids(b);
  return x.length === y.length && x.every((v, i) => v === y[i]);
}

/**
 * Writes [uids] onto every clinical record of [patientId] in [clinicId]
 * whose copy differs. Returns how many records changed.
 */
export async function copyAssignmentToRecords(
  clinicId: string,
  patientId: string,
  uids: string[]
): Promise<number> {
  const db = admin.firestore();
  let changed = 0;
  for (const coll of CLINICAL_COLLECTIONS) {
    const snap = await db.collection(coll)
      .where("doctorId", "==", clinicId)
      .where("patientId", "==", patientId)
      .get();
    const stale = snap.docs.filter((d) =>
      !sameUids(d.data().assignedDoctorUids, uids) ||
      !Array.isArray(d.data().assignedDoctorUids));
    for (let i = 0; i < stale.length; i += BATCH_LIMIT) {
      const batch = db.batch();
      for (const d of stale.slice(i, i + BATCH_LIMIT)) {
        batch.update(d.ref, {assignedDoctorUids: uids});
      }
      await batch.commit();
    }
    changed += stale.length;
  }
  return changed;
}

/**
 * Brings every clinical record in [clinicId] in line with its patient. Used
 * when a clinic starts scoping doctors, for records written before these
 * functions existed. Returns how many records changed.
 */
export async function copyAssignmentsForClinic(clinicId: string): Promise<number> {
  const db = admin.firestore();
  // One read of the patients and one per collection, rather than one per
  // patient per collection: a clinic with thousands of patients would
  // otherwise run past the callable's time limit.
  const patients = await db.collection("patients")
    .where("doctorId", "==", clinicId)
    .get();
  const assignmentOf = new Map<string, string[]>();
  for (const p of patients.docs) {
    assignmentOf.set(p.id, normalizeUids(p.data().assignedDoctorUids));
  }

  let changed = 0;
  for (const coll of CLINICAL_COLLECTIONS) {
    const snap = await db.collection(coll)
      .where("doctorId", "==", clinicId)
      .get();
    const updates: {ref: admin.firestore.DocumentReference; uids: string[]}[] = [];
    for (const d of snap.docs) {
      const uids = assignmentOf.get(String(d.data().patientId ?? ""));
      // A record whose patient is gone or elsewhere is left alone: the rules
      // already deny it to a scoped doctor.
      if (!uids) continue;
      const current = d.data().assignedDoctorUids;
      if (Array.isArray(current) && sameUids(current, uids)) continue;
      updates.push({ref: d.ref, uids});
    }
    for (let i = 0; i < updates.length; i += BATCH_LIMIT) {
      const batch = db.batch();
      for (const u of updates.slice(i, i + BATCH_LIMIT)) {
        batch.update(u.ref, {assignedDoctorUids: u.uids});
      }
      await batch.commit();
    }
    changed += updates.length;
  }
  return changed;
}

/** A patient's assignment changed: copy it to their clinical records. */
export const fanOutPatientAssignment = onDocumentWritten(
  {document: "patients/{patientId}", region: "asia-south1"},
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;
    const before = event.data?.before;
    const next = after.data() || {};
    const prev = before?.exists ? before.data() || {} : {};
    // Only act on an actual assignment change; every other patient edit
    // (name, phone, notes) is left alone.
    if (before?.exists && sameUids(prev.assignedDoctorUids, next.assignedDoctorUids)) {
      return;
    }
    const clinicId = String(next.doctorId ?? "");
    if (!clinicId) return;
    await copyAssignmentToRecords(
      clinicId,
      event.params.patientId,
      normalizeUids(next.assignedDoctorUids)
    );
  }
);

/**
 * A clinical record was written: give it its patient's assignment if it
 * lacks it or has a stale one. Converges in one extra write — the write this
 * makes fires the trigger again, which then finds the copy current.
 */
export async function stampRecord(
  ref: admin.firestore.DocumentReference,
  record: admin.firestore.DocumentData
): Promise<boolean> {
  const patientId = String(record.patientId ?? "");
  const clinicId = String(record.doctorId ?? "");
  if (!patientId || !clinicId) return false;
  const patientSnap = await admin.firestore()
    .collection("patients").doc(patientId).get();
  const patient = patientSnap.data();
  // Never copy from another clinic's patient, or from a patient that is gone.
  if (!patientSnap.exists || patient?.doctorId !== clinicId) return false;
  const uids = normalizeUids(patient?.assignedDoctorUids);
  if (Array.isArray(record.assignedDoctorUids) &&
      sameUids(record.assignedDoctorUids, uids)) {
    return false;
  }
  await ref.update({assignedDoctorUids: uids});
  return true;
}

function stampTrigger(collection: string) {
  return onDocumentWritten(
    {document: `${collection}/{recordId}`, region: "asia-south1"},
    async (event) => {
      const after = event.data?.after;
      if (!after?.exists) return;
      await stampRecord(after.ref, after.data() || {});
    }
  );
}

export const stampDentalRecordAssignment = stampTrigger("dental_records");
export const stampRadiologyDocAssignment = stampTrigger("radiology_docs");
export const stampHomeopathyCaseSheetAssignment =
  stampTrigger("homeopathy_case_sheets");
export const stampHomeopathySessionNoteAssignment =
  stampTrigger("homeopathy_session_notes");
export const stampToothChartEntryAssignment = stampTrigger("tooth_chart_entries");
export const stampProcedureLogEntryAssignment =
  stampTrigger("procedure_log_entries");
export const stampTreatmentPlanLineItemAssignment =
  stampTrigger("treatment_plan_line_items");
