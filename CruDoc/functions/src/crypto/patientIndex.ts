import * as admin from "firebase-admin";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {
  decryptField, PatientKeyring, patientKekPepperSecret, phoneIndexOf,
} from "./patientCipher";

/**
 * Keeps `phoneIndex` on every patient: an HMAC of their phone under the
 * clinic's key, so the AI receptionist can recognise a caller without the
 * phone being stored readable.
 *
 * Computed here rather than in the app so no app release is needed and a
 * client can't plant an index that points a caller at someone else's
 * record: whatever a client writes, this rewrites from the phone itself.
 * It writes only when the value changes, so its own update doesn't loop.
 *
 * Existing patients are filled in once by scripts/backfill-phone-index.js.
 */

let keyring: PatientKeyring | null = null;

export async function indexForPatient(
  data: admin.firestore.DocumentData,
  ring: PatientKeyring,
): Promise<string | null> {
  const clinicId = typeof data.doctorId === "string" ? data.doctorId : "";
  if (!clinicId) return null;
  const dek = await ring.dekFor(clinicId);
  // No key yet means nothing of this clinic's is encrypted, and an index
  // needs the key; it gets one the first time the clinic has a key.
  if (!dek) return null;
  return phoneIndexOf(decryptField(data.phone, dek), dek);
}

export const onPatientWrittenIndexPhone = onDocumentWritten(
  {
    document: "patients/{patientId}",
    region: "asia-south1",
    secrets: [patientKekPepperSecret],
  },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;
    const data = after.data() || {};

    keyring ??= new PatientKeyring(admin.firestore());
    let index: string | null;
    try {
      index = await indexForPatient(data, keyring);
    } catch (err) {
      console.error(
        `phoneIndex: cannot index patient ${after.id}: ${(err as Error).message}`,
      );
      return;
    }

    const current = typeof data.phoneIndex === "string" ? data.phoneIndex : null;
    if (current === index) return;

    await after.ref.update({
      phoneIndex: index ?? admin.firestore.FieldValue.delete(),
    });
  },
);
