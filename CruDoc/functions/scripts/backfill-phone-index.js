/**
 * One-time backfill of `patients.phoneIndex` (see src/crypto/patientIndex.ts,
 * which keeps it current from then on).
 *
 * Usage, from functions/:
 *   npm run build
 *   gcloud auth application-default login     # once, an account with Firestore access
 *   set PATIENT_KEK_PEPPER=<the app's _appPepper>   (PowerShell: $env:PATIENT_KEK_PEPPER="...")
 *   node scripts/backfill-phone-index.js --project svayatta-crudoc-dev           # dry run
 *   node scripts/backfill-phone-index.js --project svayatta-crudoc-dev --write   # apply
 *
 * Prints counts only, never names or numbers.
 */
const admin = require('firebase-admin');
const {PatientKeyring} = require('../lib/crypto/patientCipher');
const {indexForPatient} = require('../lib/crypto/patientIndex');

const args = process.argv.slice(2);
const write = args.includes('--write');
const projectIdx = args.indexOf('--project');
const projectId = projectIdx >= 0 ? args[projectIdx + 1] : undefined;
if (!projectId) {
  console.error('Pass --project <firebase project id>');
  process.exit(1);
}

admin.initializeApp({projectId});
const db = admin.firestore();

async function main() {
  const ring = new PatientKeyring(db);
  const counts = {scanned: 0, alreadyCurrent: 0, updated: 0, noIndex: 0, errors: 0};
  let last = null;
  let batch = db.batch();
  let pending = 0;

  for (;;) {
    let q = db.collection('patients').orderBy(admin.firestore.FieldPath.documentId()).limit(500);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      counts.scanned++;
      const data = doc.data();
      let index;
      try {
        index = await indexForPatient(data, ring);
      } catch (err) {
        counts.errors++;
        continue;
      }
      if (!index) counts.noIndex++;
      const current = typeof data.phoneIndex === 'string' ? data.phoneIndex : null;
      if (current === index) {
        counts.alreadyCurrent++;
        continue;
      }
      counts.updated++;
      if (write) {
        batch.update(doc.ref, {
          phoneIndex: index ?? admin.firestore.FieldValue.delete(),
        });
        if (++pending === 400) {
          await batch.commit();
          batch = db.batch();
          pending = 0;
        }
      }
    }
    last = snap.docs[snap.docs.length - 1];
  }

  if (write && pending) await batch.commit();
  console.log(`${write ? 'Applied' : 'Dry run'}:`, counts);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
