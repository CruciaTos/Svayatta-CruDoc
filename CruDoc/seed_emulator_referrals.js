/**
 * Fills the local Firebase emulators with two doctors in separate practices,
 * to try referrals between doctors by hand: Dr Asha Rao (surgeon) refers a
 * patient to Dr Smit Patil (anaesthesiologist), who sees it in Referrals.
 *
 * Talks ONLY to the emulators; it refuses to run unless the emulator host
 * variables are set, so it cannot touch a real project.
 *
 *   1. In functions/.secret.local put the app's pepper (the _appPepper
 *      value in lib/core/services/encryption_key_manager.dart):
 *        PATIENT_KEK_PEPPER=...
 *      Without it the referralNetwork function can't encrypt a referral.
 *   2. npm run build --prefix functions
 *   3. firebase emulators:start --only auth,firestore,functions,storage
 *   4. node seed_emulator_referrals.js
 *   5. Run the app twice, one per doctor, on two devices (two copies on one
 *      computer would share one local database):
 *        flutter run -d windows --dart-define=USE_FIREBASE_EMULATORS=true \
 *          --dart-define=EMULATOR_HOST=localhost
 *        flutter run -d emulator-5554 --dart-define=USE_FIREBASE_EMULATORS=true \
 *          --dart-define=EMULATOR_HOST=10.0.2.2
 *
 * Safe to re-run: every document is written by id, and auth users are
 * reused if they already exist.
 */
const path = require('path');
const {createRequire} = require('module');

const PROJECT_ID = process.env.SEED_PROJECT_ID || 'svayatta-crudoc-dev';
// 127.0.0.1 rather than localhost: Node resolves localhost to ::1 first and
// the emulators listen on IPv4.
const EMU_HOST = process.env.SEED_EMULATOR_HOST || '127.0.0.1';
const PASSWORD = 'Test1234';

process.env.FIRESTORE_EMULATOR_HOST = `${EMU_HOST}:8080`;
process.env.FIREBASE_AUTH_EMULATOR_HOST = `${EMU_HOST}:9099`;
process.env.GCLOUD_PROJECT = PROJECT_ID;

function loadAdmin() {
  try {
    return require('firebase-admin');
  } catch (_) {
    try {
      const fromFunctions = createRequire(
        path.join(__dirname, 'functions', 'package.json'));
      return fromFunctions('firebase-admin');
    } catch (_) {
      console.error('❌ Could not load firebase-admin.');
      console.error('   Run:  npm install --prefix functions');
      process.exit(1);
    }
  }
}

const admin = loadAdmin();
admin.initializeApp({projectId: PROJECT_ID});

const db = admin.firestore();
const auth = admin.auth();

/** Creates the auth user if missing (verified email + phone), returns its uid. */
async function ensureUser({email, phoneNumber, displayName}) {
  try {
    const existing = await auth.getUserByEmail(email);
    await auth.updateUser(existing.uid,
      {password: PASSWORD, displayName, phoneNumber, emailVerified: true});
    return existing.uid;
  } catch (err) {
    if (err.code !== 'auth/user-not-found') throw err;
    const created = await auth.createUser({
      email, phoneNumber, displayName, password: PASSWORD, emailVerified: true,
    });
    return created.uid;
  }
}

async function main() {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    console.error('❌ Refusing to run without FIRESTORE_EMULATOR_HOST.');
    process.exit(1);
  }
  const now = admin.firestore.FieldValue.serverTimestamp();

  const asha = await ensureUser({
    email: 'asha@crudoc.test', phoneNumber: '+919000000101', displayName: 'Dr Asha Rao',
  });
  const smit = await ensureUser({
    email: 'smit@crudoc.test', phoneNumber: '+919000000102', displayName: 'Dr Smit Patil',
  });

  // `onboarding` present makes the app skip onboarding.
  const profile = (name, email, phone, specialty, clinicName) => ({
    email, phone, name, displayName: name, specialty, specialization: specialty,
    clinicName, role: 'doctor', status: 'active', discoverable: true,
    enabledModules: ['dashboard', 'revenue', 'patients', 'appointments',
      'inventory', 'ai_assistant', 'omnichannel_messaging', 'queue'],
    onboarding: {practiceType: 'solo', completedAt: now},
    updatedAt: now,
  });
  await db.collection('users').doc(asha).set(profile('Dr Asha Rao',
    'asha@crudoc.test', '+919000000101', 'General Surgery', 'Rao Surgical'),
  {merge: true});
  await db.collection('users').doc(smit).set(profile('Dr Smit Patil',
    'smit@crudoc.test', '+919000000102', 'Anaesthesiology', 'City Hospital'),
  {merge: true});

  // Smit is listed in the directory, so search finds him too.
  await db.collection('doctor_directory').doc(smit).set({
    uid: smit, listed: true, handle: 'smit.patil', displayName: 'Smit Patil',
    specialty: 'Anaesthesiology', city: 'Pune', clinicName: 'City Hospital',
    searchTokens: ['sm', 'smi', 'smit', 'pa', 'pat', 'pati', 'patil',
      'smit.', 'smit.p', 'smit.pa', 'smit.pat', 'smit.pati', 'smit.patil',
      'an', 'ana', 'anae', 'anaes', 'anaest', 'anaesth', 'anaesthe',
      'anaesthes', 'anaesthesi', 'anaesthesio', 'anaesthesiol',
      'anaesthesiolo', 'anaesthesiolog', 'anaesthesiology', 'pu', 'pun', 'pune'],
    updatedAt: now,
  });
  await db.collection('doctor_handles').doc('smit.patil').set({uid: smit});

  const line = '─'.repeat(64);
  console.log(`\n✅ Seeded two doctors for referrals (project ${PROJECT_ID})\n`);
  console.log(line);
  console.log('SIGN IN  (password for both: ' + PASSWORD + ')');
  console.log(line);
  console.log('  asha@crudoc.test   Dr Asha Rao     surgeon, sends the referral');
  console.log('  smit@crudoc.test   Dr Smit Patil   anaesthesiologist, receives it');
  console.log(line);
  console.log('TRY');
  console.log(line);
  console.log('  As Asha: Referrals → Contacts → New contact, phone 9000000102');
  console.log('           → saving shows "On CruDoc: Dr. Smit Patil".');
  console.log('           (Or Contacts → Find on CruDoc → "smit" / "anaes".)');
  console.log('           New referral → pick a patient and Smit → tick the');
  console.log('           consent box → Send referral.');
  console.log('  As Smit: Referrals → Received: the referral, and a notification.');
  console.log('           Open it → Accept → Complete & reply.');
  console.log('  As Asha: the row moves Sent → Acknowledged → Completed, with a');
  console.log('           notification each time; open it to read the reply.');
  console.log('  Fallback: a contact with any other number → after saving, the');
  console.log('           WhatsApp / Email / Invite to CruDoc choices.');
  console.log(line);
}

main().then(() => process.exit(0)).catch((err) => {
  console.error(err);
  process.exit(1);
});
