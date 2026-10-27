/**
 * Node admin script to backfill existing patient_files records into the
 * single-copy clinic-blobs/ layout.
 *
 * Usage from CruDoc/functions:
 *   npx ts-node scripts/backfill_blobs.ts --project <projectId> --dry-run
 *   npx ts-node scripts/backfill_blobs.ts --project <projectId> --write
 *   npx ts-node scripts/backfill_blobs.ts --project <projectId> --delete-old
 */
import * as crypto from "crypto";
import * as admin from "firebase-admin";

const args = process.argv.slice(2);
const write = args.includes("--write");
const deleteOld = args.includes("--delete-old");
const dryRun = args.includes("--dry-run") || (!write && !deleteOld);

const projectIdx = args.indexOf("--project");
const projectId = projectIdx >= 0 ? args[projectIdx + 1] : process.env.GCLOUD_PROJECT;

if (!projectId && !admin.apps.length) {
  console.error("Pass --project <firebase-project-id> or set GCLOUD_PROJECT");
  process.exit(1);
}

if (!admin.apps.length) {
  admin.initializeApp({projectId});
}

const db = admin.firestore();
const bucket = admin.storage().bucket();

export async function runBackfill(options?: {
  write?: boolean;
  deleteOld?: boolean;
  dryRun?: boolean;
}) {
  const isWrite = options?.write ?? write;
  const isDeleteOld = options?.deleteOld ?? deleteOld;
  const isDryRun = options?.dryRun ?? dryRun;

  console.log(`[Backfill Blobs] Starting (dryRun=${isDryRun}, write=${isWrite}, deleteOld=${isDeleteOld})...`);

  const stats = {
    scanned: 0,
    alreadyMigrated: 0,
    migrated: 0,
    duplicates: 0,
    bytesSaved: 0,
    totalBytes: 0,
    errors: 0,
    oldDeleted: 0,
  };

  const knownBlobs = new Set<string>();

  // 1. Process patient_files records
  const filesSnap = await db.collection("patient_files").get();
  stats.scanned = filesSnap.docs.length;

  for (const doc of filesSnap.docs) {
    const data = doc.data();
    const storagePath = data.storagePath || "";
    const existingSha = data.sha256;
    const clinicId = data.doctorId || "";

    if (existingSha && storagePath.startsWith("clinic-blobs/")) {
      stats.alreadyMigrated++;
      knownBlobs.add(`${clinicId}/${existingSha}`);
      continue;
    }

    if (!storagePath.startsWith("patient-files/") || !clinicId) {
      continue;
    }

    try {
      const srcFile = bucket.file(storagePath);
      const [exists] = await srcFile.exists();
      if (!exists) {
        console.warn(`[Missing] Storage object not found for ${doc.id}: ${storagePath}`);
        stats.errors++;
        continue;
      }

      // Compute SHA-256 by streaming the object
      const hash = crypto.createHash("sha256");
      const [buffer] = await srcFile.download();
      hash.update(buffer);
      const sha256 = hash.digest("hex");
      const sizeBytes = buffer.length;
      stats.totalBytes += sizeBytes;

      const blobKey = `${clinicId}/${sha256}`;
      const isDuplicate = knownBlobs.has(blobKey);

      if (isDuplicate) {
        stats.duplicates++;
        stats.bytesSaved += sizeBytes;
      } else {
        knownBlobs.add(blobKey);
      }

      const newStoragePath = `clinic-blobs/${clinicId}/${sha256}/original`;
      const viewPath = data.viewPath as string | undefined;
      let newViewPath = "";

      if (!isDryRun && isWrite) {
        // Server-side copy if blob does not exist yet
        const destFile = bucket.file(newStoragePath);
        const [destExists] = await destFile.exists();
        if (!destExists) {
          await srcFile.copy(destFile);
        }

        if (viewPath && viewPath.startsWith("patient-files/")) {
          const srcView = bucket.file(viewPath);
          const [srcViewExists] = await srcView.exists();
          if (srcViewExists) {
            newViewPath = `clinic-blobs/${clinicId}/${sha256}/view`;
            const destView = bucket.file(newViewPath);
            const [destViewExists] = await destView.exists();
            if (!destViewExists) {
              await srcView.copy(destView);
            }
          }
        }

        // Update record in Firestore
        await doc.ref.update({
          sha256,
          storagePath: newStoragePath,
          ...(newViewPath ? {viewPath: newViewPath} : {}),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Ensure blob document exists and add ref
        const blobDoc = db.doc(`clinics/${clinicId}/blobs/${sha256}`);
        await db.runTransaction(async (txn) => {
          const bSnap = await txn.get(blobDoc);
          const currentCount = Number(bSnap.data()?.refCount) || 0;
          txn.set(
            blobDoc,
            {
              sizeBytes,
              contentType: data.contentType || "application/octet-stream",
              state: "ready",
              hasView: Boolean(newViewPath || bSnap.data()?.hasView),
              refCount: currentCount + 1,
              zeroSince: null,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true}
          );

          const refDoc = blobDoc.collection("refs").doc(doc.id);
          txn.set(refDoc, {
            fileId: doc.id,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        });
      }

      stats.migrated++;
    } catch (err) {
      console.error(`[Error] Failed to process ${doc.id}:`, err);
      stats.errors++;
    }
  }

  // 2. Delete old unreferenced objects if --delete-old requested
  if (isDeleteOld && !isDryRun) {
    console.log("[Backfill Blobs] Scanning for orphaned patient-files/ objects to delete...");
    const [allOldFiles] = await bucket.getFiles({prefix: "patient-files/"});

    // Collect all active storagePath and viewPath across patient_files
    const activePaths = new Set<string>();
    const refreshedFiles = await db.collection("patient_files").get();
    for (const d of refreshedFiles.docs) {
      const sp = d.data().storagePath;
      const vp = d.data().viewPath;
      if (sp) activePaths.add(sp);
      if (vp) activePaths.add(vp);
    }

    for (const f of allOldFiles) {
      if (!activePaths.has(f.name)) {
        await f.delete().catch(() => {});
        stats.oldDeleted++;
      }
    }
  }

  console.log("\n==================== Backfill Summary ====================");
  console.log(`Scanned records:          ${stats.scanned}`);
  console.log(`Already on blobs:         ${stats.alreadyMigrated}`);
  console.log(`Eligible to migrate:      ${stats.migrated}`);
  console.log(`Duplicate copies saved:   ${stats.duplicates}`);
  console.log(`Estimated bytes saved:    ${(stats.bytesSaved / (1024 * 1024)).toFixed(2)} MB`);
  console.log(`Total data size:          ${(stats.totalBytes / (1024 * 1024)).toFixed(2)} MB`);
  if (isDeleteOld) {
    console.log(`Old orphaned objects deleted: ${stats.oldDeleted}`);
  }
  console.log(`Errors encountered:       ${stats.errors}`);
  console.log("==========================================================");

  return stats;
}

if (require.main === module) {
  runBackfill()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error(err);
      process.exit(1);
    });
}
