import {onDocumentCreated} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import {pushTo, drName} from "./referrals";
import {decryptProfileField} from "./crypto/profileCipher";

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
      const member = (await admin
        .firestore()
        .collection("clinics")
        .doc(clinicId)
        .collection("members")
        .doc(fromUid)
        .get()).data();
      // Profile names are encrypted (see profileCipher.ts); an unreadable
      // one comes back "", so the push never shows cipher text.
      let name = decryptProfileField(member?.name, fromUid);
      let staff = member?.kind === "staff";
      if (!name) {
        const user = (await admin.firestore().collection("users").doc(fromUid).get()).data();
        name = decryptProfileField(user?.name, fromUid) ||
          decryptProfileField(user?.displayName, fromUid);
        if (!member) staff = user?.memberKind === "staff";
      }
      if (name) senderName = staff ? name : drName(name);
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
      },
      // The app's Files channel (push_notifications.dart filesChannel).
      "files"
    );
  }
);
