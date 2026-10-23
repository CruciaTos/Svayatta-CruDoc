/**
 * One-time backfill of the profile fields older clinic builds didn't write
 * (role, isDeleted, accountCreated). src/profile-defaults.ts keeps them
 * filled from then on.
 *
 * Usage, from functions/:
 *   npm run build
 *   gcloud auth application-default login     # once, an account with Firestore access
 *   node scripts/backfill-profile-defaults.js --project svayatta-crudoc-dev           # dry run
 *   node scripts/backfill-profile-defaults.js --project svayatta-crudoc-dev --write   # apply
 *
 * Prints counts only, never names or emails.
 */
const admin = require('firebase-admin');
const {profileDefaults} = require('../lib/profile-defaults');

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
  const counts = {scanned: 0, complete: 0, needsFix: 0, written: 0};
  const fields = {};
  const snap = await db.collection('users').get();
  let batch = db.batch();
  let pending = 0;
  for (const doc of snap.docs) {
    counts.scanned++;
    const patch = profileDefaults(doc.data(), doc.createTime);
    const keys = Object.keys(patch);
    if (keys.length === 0) {
      counts.complete++;
      continue;
    }
    counts.needsFix++;
    for (const k of keys) fields[k] = (fields[k] || 0) + 1;
    if (!write) continue;
    batch.set(doc.ref, patch, {merge: true});
    pending++;
    if (pending === 400) {
      await batch.commit();
      counts.written += pending;
      batch = db.batch();
      pending = 0;
    }
  }
  if (write && pending > 0) {
    await batch.commit();
    counts.written += pending;
  }
  console.log(write ? 'Applied.' : 'Dry run (pass --write to apply).');
  console.log(counts);
  console.log('fields to fill:', fields);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
