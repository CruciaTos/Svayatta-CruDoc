/**
 * Backfills `adminClinicalAccess: true` on every clinic that predates the
 * field, so no existing clinic loses access when administrative authority is
 * separated from clinical privilege.
 *
 * Why `true` and not `false`: today a Clinic Admin reads every clinical
 * record (roleId === 'admin' short-circuits every permission check). Flipping
 * that to `false` wholesale would break live clinics with no warning, so
 * existing clinics keep what they have and are asked to opt down in-app.
 * New clinics are created with `false` by ensureClinic. See the RBAC
 * decisions record.
 *
 * Run from CruDoc/ with serviceAccountKey.json present:
 *
 *   node migrate_admin_clinical_access.js            # dry run, writes nothing
 *   node migrate_admin_clinical_access.js --apply    # performs the backfill
 *
 * Idempotent: a clinic that already has the field is left untouched, so this
 * is safe to re-run. Run it BEFORE deploying the rules change.
 *
 * It also reports (never changes) staff roles and members holding
 * clinical.edit, which the new rules stop inviting into.
 *
 * Rehearse first against the emulator, with nothing real touched:
 *
 *   set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
 *   node migrate_admin_clinical_access.js
 */
const fs = require('fs');
const path = require('path');
const {createRequire} = require('module');

const APPLY = process.argv.includes('--apply');
const BATCH_LIMIT = 400;

/**
 * firebase-admin is a dependency of the functions codebase, not the repo
 * root, so resolve it from there rather than requiring a root install.
 */
function loadAdmin() {
  try {
    return require('firebase-admin');
  } catch (rootErr) {
    try {
      const fromFunctions = createRequire(
        path.join(__dirname, 'functions', 'package.json'));
      return fromFunctions('firebase-admin');
    } catch (fnErr) {
      console.error('❌ Could not load firebase-admin.');
      console.error('   Run:  npm install --prefix functions');
      process.exit(1);
    }
  }
}

const admin = loadAdmin();

// Rehearsal mode: with FIRESTORE_EMULATOR_HOST set, run against the local
// emulator instead (no credentials needed, nothing real touched). Use it to
// try the whole migration on seeded data before running it for real.
const ON_EMULATOR = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
let projectId;

if (ON_EMULATOR) {
  projectId = process.env.GCLOUD_PROJECT || 'svayatta-crudoc-dev';
  admin.initializeApp({projectId});
} else {
  const serviceAccountPath = path.join(__dirname, 'serviceAccountKey.json');
  if (!fs.existsSync(serviceAccountPath)) {
    console.error('❌ serviceAccountKey.json not found next to this script.');
    console.error('   (Set FIRESTORE_EMULATOR_HOST to rehearse against the emulator.)');
    process.exit(1);
  }
  const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
  projectId = serviceAccount.project_id;
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId,
  });
}

/**
 * READ-ONLY. Lists roles and members that the new staff/clinical rule would
 * affect: a staff (non-doctor) role or member holding `clinical.edit`, other
 * than the built-in admin role.
 *
 * After deploy, inviting someone to such a role, or changing such a member's
 * role or kind, is refused. Existing members keep working. Nothing is changed
 * here, with or without --apply — fixing them is a decision for each clinic
 * (make the role a doctor role, or drop clinical.edit).
 */
async function reportStaffWritingClinical(db) {
  const writesClinical = (d) => d.kind !== 'doctor' &&
    Array.isArray(d.perms) && d.perms.includes('clinical.edit');

  const roles = (await db.collectionGroup('roles').get()).docs
    .filter((r) => r.id !== 'admin' && writesClinical(r.data()));
  const members = (await db.collectionGroup('members').get()).docs
    .filter((m) => m.data().active === true &&
      m.data().roleId !== 'admin' && writesClinical(m.data()));

  console.log('Staff roles/members holding clinical.edit (report only, never changed):');
  if (roles.length === 0 && members.length === 0) {
    console.log('  none — the new rule affects no existing clinic.\n');
    return;
  }
  for (const r of roles) {
    console.log(`  role    ${r.ref.path}  "${r.data().name || r.id}"`);
  }
  for (const m of members) {
    console.log(`  member  ${m.ref.path}  "${m.data().name || m.id}"`);
  }
  console.log(`  → ${roles.length} role(s), ${members.length} member(s). ` +
    'Invites to these roles will be refused after deploy.\n');
}

async function main() {
  const db = admin.firestore();
  console.log(`Project: ${projectId}${ON_EMULATOR ?
    `   (EMULATOR at ${process.env.FIRESTORE_EMULATOR_HOST} — rehearsal)` : ''}`);
  console.log(APPLY ?
    'Mode:    APPLY — documents will be written\n' :
    'Mode:    DRY RUN — nothing will be written (pass --apply to commit)\n');

  await reportStaffWritingClinical(db);

  const snap = await db.collection('clinics').get();

  const needsBackfill = [];
  let alreadySet = 0;

  for (const doc of snap.docs) {
    const value = doc.data().adminClinicalAccess;
    if (value === undefined) {
      needsBackfill.push(doc);
    } else {
      alreadySet += 1;
    }
  }

  console.log(`Clinics found:            ${snap.size}`);
  console.log(`Already have the field:   ${alreadySet}`);
  console.log(`To backfill with true:    ${needsBackfill.length}\n`);

  if (needsBackfill.length === 0) {
    console.log('✅ Nothing to do.');
    return;
  }

  for (const doc of needsBackfill) {
    const name = doc.data().name || '(unnamed)';
    console.log(`  ${APPLY ? 'backfilling' : 'would backfill'}  ${doc.id}  ${name}`);
  }

  if (!APPLY) {
    console.log('\nDry run complete. Re-run with --apply to write these changes.');
    return;
  }

  let written = 0;
  for (let i = 0; i < needsBackfill.length; i += BATCH_LIMIT) {
    const chunk = needsBackfill.slice(i, i + BATCH_LIMIT);
    const batch = db.batch();
    for (const doc of chunk) {
      batch.update(doc.ref, {
        adminClinicalAccess: true,
        adminClinicalAccessBackfilledAt:
          admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    written += chunk.length;
    console.log(`  committed ${written}/${needsBackfill.length}`);
  }

  console.log(`\n✅ Backfilled ${written} clinic${written === 1 ? '' : 's'}.`);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('❌ Migration failed:', err.message);
    process.exit(1);
  });
