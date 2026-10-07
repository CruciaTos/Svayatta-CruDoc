import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {createHash} from "crypto";
import {loadCaller, requirePerm} from "./clinic";

interface FrameFileInput {
  path: string;
  total: number;
  previewEnd: number;
  sha256: string;
}

export const getImagingView = onCall(
  {region: "asia-south1", maxInstances: 10},
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError(
        "unauthenticated",
        "Authentication required to access imaging views."
      );
    }
    const storagePath = String(request.data?.storagePath ?? "");

    // doctors/{clinicId}/patients/.../clinical/imaging/...: the clinic's
    // owner, or a member who may see clinical records.
    const parts = storagePath.split("/");
    const clinicId = parts[0] === "doctors" ? parts[1] ?? "" : "";
    if (!clinicId || parts.some((p) => p === "" || p === "..") ||
        !storagePath.includes("/clinical/imaging/")) {
      throw new HttpsError(
        "permission-denied",
        "Access denied to the requested imaging view."
      );
    }
    const caller = await loadCaller(request, clinicId);
    requirePerm(caller, "clinical.view");

    const viewId = createHash("sha256").update(storagePath).digest("hex");
    const snap = await admin.firestore().collection("radiology_views").doc(viewId).get();

    if (!snap.exists) {
      return {status: "missing"};
    }

    const data = snap.data() || {};
    if (data.doctorId !== clinicId) {
      throw new HttpsError(
        "permission-denied",
        "Access denied to the requested imaging view."
      );
    }

    if (data.status !== "ready") {
      return {status: data.status};
    }

    const rawFrames: FrameFileInput[] = Array.isArray(data.frameFiles) ? data.frameFiles : [];
    const bucket = admin.storage().bucket();
    const expires = Date.now() + 10 * 60 * 1000;

    const frameFiles = await Promise.all(
      rawFrames.map(async (frame) => {
        const [url] = await bucket.file(frame.path).getSignedUrl({
          version: "v4",
          action: "read",
          expires,
        });
        return {
          url,
          total: frame.total,
          previewEnd: frame.previewEnd,
          sha256: frame.sha256,
        };
      })
    );

    const patientMatch = storagePath.match(/\/patients\/([^/]+)/);
    const patientId = patientMatch ? patientMatch[1] : "";

    await admin.firestore().collection("access_logs").add({
      doctorId: clinicId,
      actorUid: caller.uid,
      action: "image.view",
      patientId,
      target: storagePath,
      platform: "server",
      at: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      status: "ready",
      codec: data.codec,
      width: data.width,
      height: data.height,
      frames: data.frames,
      bitsStored: data.bitsStored,
      signed: data.signed,
      slope: data.slope,
      intercept: data.intercept,
      windowCenter: data.windowCenter,
      windowWidth: data.windowWidth,
      photometric: data.photometric,
      frameFiles,
    };
  }
);
