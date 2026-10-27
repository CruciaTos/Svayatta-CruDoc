import {onDocumentCreated} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import {pushTo, drName} from "./referrals";

/**
 * Sends a push notification to the recipient when a new file offer is created.
 */
export const onFileOfferCreated = onDocumentCreated(
  {
    document: "clinics/{clinicId}/file_offers/{offerId}",
    region: "asia-south1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    if (!data || data.status !== "sent") return;

    const toUid = data.to;
    const fromUid = data.from;
    const clinicId = event.params.clinicId;
    const offerId = event.params.offerId;

    if (!toUid || !fromUid) return;

    let senderName = "A colleague";
    try {
      const memberDoc = await admin
        .firestore()
        .collection("clinics")
        .doc(clinicId)
        .collection("members")
        .doc(fromUid)
        .get();
      if (memberDoc.exists && memberDoc.data()?.name) {
        senderName = drName(memberDoc.data()!.name);
      } else {
        const userDoc = await admin.firestore().collection("users").doc(fromUid).get();
        const rawName = userDoc.data()?.name || userDoc.data()?.displayName;
        if (rawName) senderName = drName(rawName);
      }
    } catch (_) {
      // Keep the generic sender name.
    }

    await pushTo(
      toUid,
      "New file shared",
      `${senderName} shared a file with you`,
      {
        type: "file_offer",
        clinicId,
        offerId,
        batchId: data.batchId || "",
      }
    );
  }
);
