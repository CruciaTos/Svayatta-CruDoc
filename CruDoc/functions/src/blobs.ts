import * as crypto from "crypto";
import * as admin from "firebase-admin";
import {onObjectFinalized} from "firebase-functions/v2/storage";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";

const BLOB_PATH_RE = /^clinic-blobs\/([^/]+)\/([0-9a-f]{64})\/(original|view)$/;
const SHA256_HEX_RE = /^[0-9a-f]{64}$/;
const DEFAULT_GRACE_DAYS = 7;

/**
 * Returns whether a patient_files record represents an active reference to a blob.
 * A record is an active reference if it has a valid 64-char lowercase sha256 and is not deleted.
 */
export function isBlobReference(data: unknown): boolean {
  if (!data || typeof data !== "object") return false;
  const d = data as Record<string, unknown>;
  if (d.isDeleted === true) return false;
  if (typeof d.sha256 !== "string") return false;
  return SHA256_HEX_RE.test(d.sha256);
}

/**
 * Handles Storage upload finalization for clinic-blobs/{clinicId}/{sha256}/{original|view}.
 */
export async function handleBlobFinalized(
  db: admin.firestore.Firestore,
  bucket: any,
  objectData: {
    name?: string;
    size?: string | number;
    contentType?: string;
    metadata?: Record<string, string>;
  }
): Promise<{action: string; sha256?: string; clinicId?: string} | null> {
  const name = objectData.name || "";
  const match = BLOB_PATH_RE.exec(name);
  if (!match) return null;

  const clinicId = match[1];
  const expectedSha256 = match[2];
  const kind = match[3];
  const blobRef = db.doc(`clinics/${clinicId}/blobs/${expectedSha256}`);

  if (kind === "view") {
    await blobRef.set(
      {
        hasView: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
    return {action: "view_linked", sha256: expectedSha256, clinicId};
  }

  // Handle 'original'
  const file = bucket.file(name);
  const hash = crypto.createHash("sha256");

  // Read and stream object bytes to compute SHA-256
  const buffer = await file.download().then((res: [Buffer]) => res[0]);
  hash.update(buffer);
  const computedSha256 = hash.digest("hex");

  if (computedSha256 !== expectedSha256) {
    // Mismatch: delete the uploaded object, mark state: 'bad', and log audit
    await file.delete().catch(() => {});
    await blobRef.set(
      {
        state: "bad",
        mismatchDigest: computedSha256,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
    await db.collection(`clinics/${clinicId}/access_logs`).add({
      action: "blob.tampered",
      sha256: expectedSha256,
      computedSha256,
      path: name,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {action: "mismatch_deleted", sha256: expectedSha256, clinicId};
  }

  // Fingerprint matches: record blob state and update clinic usage
  const sizeBytes = Number(objectData.size) || buffer.length || 0;
  const contentType = objectData.contentType || "application/octet-stream";

  await db.runTransaction(async (txn) => {
    const snap = await txn.get(blobRef);
    const existing = snap.data();
    const alreadyReady = existing?.state === "ready";

    const refCount = typeof existing?.refCount === "number" ? existing.refCount : 0;
    const zeroSince = refCount === 0
      ? (existing?.zeroSince || admin.firestore.FieldValue.serverTimestamp())
      : null;

    const clinicRef = db.doc(`clinics/${clinicId}`);
    const clinicSnap = await txn.get(clinicRef);
    const currentBytes = Number(clinicSnap.data()?.storageBytes) || 0;

    // All reads completed above. Now perform writes:
    txn.set(
      blobRef,
      {
        sizeBytes,
        contentType,
        state: "ready",
        hasView: existing?.hasView === true,
        refCount,
        zeroSince,
        uploadedBy: objectData.metadata?.uploadedBy || existing?.uploadedBy || "",
        createdAt: existing?.createdAt || admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    // Only add to usage once per clinic copy
    if (!alreadyReady && sizeBytes > 0) {
      const newTotalBytes = currentBytes + sizeBytes;
      const newGb = Math.round((newTotalBytes / (1024 * 1024 * 1024)) * 1000) / 1000;

      txn.set(
        clinicRef,
        {
          storageBytes: newTotalBytes,
          storageUsedGB: newGb,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
    }
  });

  return {action: "verified_ready", sha256: expectedSha256, clinicId};
}

/**
 * Handles updates to patient_files/{fileId} to maintain blob references and counts.
 * Safe to run twice because it verifies doc existence under refs/{fileId}.
 */
export async function handlePatientFileWritten(
  db: admin.firestore.Firestore,
  fileId: string,
  beforeData: Record<string, unknown> | undefined,
  afterData: Record<string, unknown> | undefined
): Promise<{removed?: boolean; added?: boolean}> {
  const hadRef = isBlobReference(beforeData);
  const hasRef = isBlobReference(afterData);

  const oldClinic = String(beforeData?.doctorId || "");
  const oldSha = String(beforeData?.sha256 || "");
  const newClinic = String(afterData?.doctorId || "");
  const newSha = String(afterData?.sha256 || "");

  // If both existed and reference target hasn't changed, nothing to do
  if (hadRef && hasRef && oldClinic === newClinic && oldSha === newSha) {
    return {};
  }

  let removed = false;
  let added = false;

  // 1. Remove old reference if present
  if (hadRef && oldClinic && oldSha) {
    const oldBlobRef = db.doc(`clinics/${oldClinic}/blobs/${oldSha}`);
    const oldRefDoc = oldBlobRef.collection("refs").doc(fileId);

    await db.runTransaction(async (txn) => {
      const refSnap = await txn.get(oldRefDoc);
      const blobSnap = await txn.get(oldBlobRef);

      if (refSnap.exists) {
        txn.delete(oldRefDoc);
        if (blobSnap.exists) {
          const currentCount = Number(blobSnap.data()?.refCount) || 1;
          const nextCount = Math.max(0, currentCount - 1);
          txn.update(oldBlobRef, {
            refCount: nextCount,
            zeroSince: nextCount === 0
              ? admin.firestore.FieldValue.serverTimestamp()
              : (blobSnap.data()?.zeroSince || null),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
        removed = true;
      }
    });
  }

  // 2. Add new reference if present
  if (hasRef && newClinic && newSha) {
    const newBlobRef = db.doc(`clinics/${newClinic}/blobs/${newSha}`);
    const newRefDoc = newBlobRef.collection("refs").doc(fileId);

    await db.runTransaction(async (txn) => {
      const refSnap = await txn.get(newRefDoc);
      const blobSnap = await txn.get(newBlobRef);

      if (!refSnap.exists) {
        txn.set(newRefDoc, {
          fileId,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        if (blobSnap.exists) {
          const currentCount = Number(blobSnap.data()?.refCount) || 0;
          txn.update(newBlobRef, {
            refCount: currentCount + 1,
            zeroSince: null,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } else {
          // Stub blob entry until upload finalizes
          txn.set(newBlobRef, {
            sizeBytes: 0,
            contentType: String(afterData?.contentType || ""),
            state: "pending",
            hasView: false,
            refCount: 1,
            zeroSince: null,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
        added = true;
      }
    });
  }

  return {removed, added};
}

/**
 * Deletes unreferenced blobs whose zeroSince has exceeded grace period,
 * or immediately if purgeNow is set.
 */
export async function cleanupEligibleBlobs(
  db: admin.firestore.Firestore,
  bucket: any,
  options?: {graceMinutes?: number; nowMs?: number}
): Promise<{purgedCount: number; freedBytes: number}> {
  const now = options?.nowMs ?? Date.now();
  const graceMinutes = options?.graceMinutes ?? (
    process.env.BLOB_CLEANUP_GRACE_MINUTES
      ? Number(process.env.BLOB_CLEANUP_GRACE_MINUTES)
      : DEFAULT_GRACE_DAYS * 24 * 60
  );
  const graceMs = graceMinutes * 60 * 1000;

  let purgedCount = 0;
  let freedBytes = 0;

  const clinicsSnap = await db.collection("clinics").get();

  for (const clinicDoc of clinicsSnap.docs) {
    const clinicId = clinicDoc.id;
    const blobsSnap = await db.collection(`clinics/${clinicId}/blobs`).get();

    for (const blobDoc of blobsSnap.docs) {
      const data = blobDoc.data();
      const refCount = Number(data.refCount) || 0;
      const purgeNow = data.purgeNow === true;

      let zeroSinceMs: number | null = null;
      if (data.zeroSince?.toMillis) {
        zeroSinceMs = data.zeroSince.toMillis();
      } else if (data.zeroSince?.toDate) {
        zeroSinceMs = data.zeroSince.toDate().getTime();
      } else if (data.zeroSince?._seconds) {
        zeroSinceMs = data.zeroSince._seconds * 1000;
      }

      const isExpired = zeroSinceMs != null && (now - zeroSinceMs >= graceMs);

      if (refCount === 0 && (purgeNow || isExpired)) {
        const sha256 = blobDoc.id;
        const sizeBytes = Number(data.sizeBytes) || 0;

        // 1. Delete bucket objects (original and view)
        if (bucket) {
          await bucket.file(`clinic-blobs/${clinicId}/${sha256}/original`).delete().catch(() => {});
          await bucket.file(`clinic-blobs/${clinicId}/${sha256}/view`).delete().catch(() => {});
        }

        // 2. Delete all refs subcollection documents
        const refsSnap = await blobDoc.ref.collection("refs").get();
        for (const r of refsSnap.docs) {
          await r.ref.delete().catch(() => {});
        }

        // 3. Delete blob doc
        await blobDoc.ref.delete().catch(() => {});

        // 4. Subtract storage usage from clinic
        if (sizeBytes > 0) {
          const clinicRef = db.doc(`clinics/${clinicId}`);
          await db.runTransaction(async (txn) => {
            const cSnap = await txn.get(clinicRef);
            const currentBytes = Number(cSnap.data()?.storageBytes) || 0;
            const newBytes = Math.max(0, currentBytes - sizeBytes);
            const newGb = Math.round((newBytes / (1024 * 1024 * 1024)) * 1000) / 1000;
            txn.update(clinicRef, {
              storageBytes: newBytes,
              storageUsedGB: newGb,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          });
        }

        purgedCount++;
        freedBytes += sizeBytes;
      }
    }
  }

  return {purgedCount, freedBytes};
}

// ----------------------------------------------------------------------
// Exported Cloud Functions triggers (asia-south1)
// ----------------------------------------------------------------------

export const onBlobFinalized = onObjectFinalized(
  {
    region: "asia-south1",
    bucket: process.env.STORAGE_BUCKET || "default",
  },
  async (event) => {
    const db = admin.firestore();
    const bucket = admin.storage().bucket(event.data.bucket);
    await handleBlobFinalized(db, bucket, event.data);
  }
);

export const onPatientFileWritten = onDocumentWritten(
  {
    document: "patient_files/{fileId}",
    region: "asia-south1",
  },
  async (event) => {
    const db = admin.firestore();
    const fileId = event.params.fileId;
    const beforeData = event.data?.before.data();
    const afterData = event.data?.after.data();
    await handlePatientFileWritten(db, fileId, beforeData, afterData);
  }
);

export const cleanUpBlobs = onSchedule(
  {
    schedule: "every day 03:00",
    region: "asia-south1",
    timeZone: "Asia/Kolkata",
  },
  async () => {
    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    await cleanupEligibleBlobs(db, bucket);
  }
);
