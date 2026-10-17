/**
 * Fills the local Firebase emulators with a clinic you can sign into, to try
 * the role and permission behaviour by hand.
 *
 * Talks ONLY to the emulators — it refuses to run unless the emulator host
 * variables are set, so it cannot touch a real project.
 *
 *   1. firebase emulators:start
 *   2. node seed_emulator_clinic.js
 *   3. flutter run -d windows \
 *        --dart-define=USE_FIREBASE_EMULATORS=true \
 *        --dart-define=EMULATOR_HOST=localhost
 *
 * The clinic is deliberately set up in the strict configuration — admins
 * have no clinical access and doctors are scoped to their own patients —
 * because that is the part worth seeing with your own eyes. Everything
 * is printed at the end, including who should be able to see what.
 *
 * Safe to re-run: every document is written by id, and auth users are
 * reused if they already exist.
 */
const path = require('path');
const {createRequire} = require('module');

const PROJECT_ID = process.env.SEED_PROJECT_ID || 'svayatta-crudoc-dev';
// 127.0.0.1 rather than localhost: Node resolves localhost to ::1 first and
// the emulators listen on IPv4, which fails with ECONNREFUSED ::1.
const EMU_HOST = process.env.SEED_EMULATOR_HOST || '127.0.0.1';
const PASSWORD = 'Test1234';

// Point the Admin SDK at the emulators before it initialises. Without these
// the SDK would look for real credentials and a real project.
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

const PERMS = [
  'patients.view', 'patients.edit', 'clinical.view', 'clinical.edit',
  'schedule', 'billing', 'revenue', 'inventory', 'messaging', 'ai',
  'team', 'settings',
];

const ROLE_TEMPLATES = [
  {id: 'admin', name: 'Admin', kind: 'staff', perms: PERMS, isSystem: true},
  {
    id: 'doctor', name: 'Doctor', kind: 'doctor',
    perms: ['patients.view', 'patients.edit', 'clinical.view', 'clinical.edit',
      'schedule', 'billing', 'messaging', 'ai'],
  },
  {
    id: 'receptionist', name: 'Receptionist', kind: 'staff',
    perms: ['patients.view', 'patients.edit', 'schedule', 'billing',
      'messaging'],
  },
  {
    id: 'assistant', name: 'Assistant / Nurse', kind: 'staff',
    perms: ['patients.view', 'clinical.view', 'schedule', 'inventory'],
  },
  {
    id: 'accountant', name: 'Accountant', kind: 'staff',
    perms: ['patients.view', 'billing', 'revenue'],
  },
];

/** Creates the auth user if missing, and returns its uid. */
async function ensureUser({email, displayName}) {
  try {
    const existing = await auth.getUserByEmail(email);
    await auth.updateUser(existing.uid, {password: PASSWORD, displayName});
    return existing.uid;
  } catch (err) {
    if (err.code !== 'auth/user-not-found') throw err;
    const created = await auth.createUser({
      email,
      password: PASSWORD,
      displayName,
      emailVerified: true,
    });
    return created.uid;
  }
}

async function main() {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    console.error('❌ Refusing to run without FIRESTORE_EMULATOR_HOST.');
    process.exit(1);
  }
  console.log(`Project:  ${PROJECT_ID}`);
  console.log(`Emulators: ${EMU_HOST} (firestore 8080, auth 9099)\n`);

  // ---- people ----------------------------------------------------------
  const owner = await ensureUser({
    email: 'owner@crudoc.test', displayName: 'Dr Asha Rao',
  });
  const manager = await ensureUser({
    email: 'manager@crudoc.test', displayName: 'Priya Nair',
  });
  const doctorTwo = await ensureUser({
    email: 'doctor2@crudoc.test', displayName: 'Dr Vikram Shah',
  });
  const doctorThree = await ensureUser({
    email: 'doctor3@crudoc.test', displayName: 'Dr Meera Pillai',
  });
  const recep = await ensureUser({
    email: 'reception@crudoc.test', displayName: 'Rahul Das',
  });

  const clinicId = owner; // a clinic's id is its owner's uid
  const now = admin.firestore.FieldValue.serverTimestamp();

  // ---- the clinic, in the strict configuration -------------------------
  await db.collection('clinics').doc(clinicId).set({
    name: 'Sunrise Dental',
    specialty: 'Dentist',
    ownerUid: owner,
    seats: {doctor: 5, staff: 10},
    // The two settings this exercise is about.
    adminClinicalAccess: false,
    clinicalAccessScope: 'assigned',
    status: 'active',
    createdAt: now,
  });

  for (const role of ROLE_TEMPLATES) {
    await db.collection('clinics').doc(clinicId)
      .collection('roles').doc(role.id).set({
        name: role.name,
        kind: role.kind,
        perms: role.perms,
        isSystem: role.id === 'admin',
        updatedAt: now,
      });
  }

  const members = [
    {
      uid: owner, name: 'Dr Asha Rao', email: 'owner@crudoc.test',
      kind: 'doctor', roleId: 'admin', roleName: 'Admin', perms: PERMS,
      isOwner: true, specialty: 'Dentist',
    },
    {
      uid: manager, name: 'Priya Nair', email: 'manager@crudoc.test',
      kind: 'staff', roleId: 'admin', roleName: 'Admin', perms: PERMS,
      isOwner: false, specialty: '',
    },
    {
      uid: doctorTwo, name: 'Dr Vikram Shah', email: 'doctor2@crudoc.test',
      kind: 'doctor', roleId: 'doctor', roleName: 'Doctor',
      perms: ROLE_TEMPLATES[1].perms, isOwner: false, specialty: 'Dentist',
    },
    {
      uid: doctorThree, name: 'Dr Meera Pillai', email: 'doctor3@crudoc.test',
      kind: 'doctor', roleId: 'doctor', roleName: 'Doctor',
      perms: ROLE_TEMPLATES[1].perms, isOwner: false, specialty: 'Dentist',
    },
    {
      uid: recep, name: 'Rahul Das', email: 'reception@crudoc.test',
      kind: 'staff', roleId: 'receptionist', roleName: 'Receptionist',
      perms: ROLE_TEMPLATES[2].perms, isOwner: false, specialty: '',
    },
  ];

  for (const m of members) {
    await db.collection('clinics').doc(clinicId)
      .collection('members').doc(m.uid).set({
        name: m.name,
        phone: '',
        email: m.email,
        kind: m.kind,
        roleId: m.roleId,
        roleName: m.roleName,
        perms: m.perms,
        active: true,
        isOwner: m.isOwner,
        specialty: m.specialty,
        qualification: '',
        registrationNo: '',
        joinedAt: now,
      }, {merge: true});
  }

  // ---- user profiles ---------------------------------------------------
  // `onboarding` present (or memberKind set) makes the app skip onboarding,
  // and the login screen requires a users/{uid} document to exist at all.
  const profile = (name, email, extra) => ({
    email,
    displayName: name,
    name,
    specialty: 'Dentist',
    specialization: 'Dentist',
    status: 'active',
    enabledModules: [
      'dashboard', 'revenue', 'patients', 'appointments', 'inventory',
      'home_visits', 'ai_assistant', 'omnichannel_messaging',
      'multi_device_access', 'queue',
    ],
    onboarding: {practiceType: 'clinic', completedAt: now},
    updatedAt: now,
    ...extra,
  });

  await db.collection('users').doc(owner).set(
    profile('Dr Asha Rao', 'owner@crudoc.test',
      {clinicId: owner, memberKind: 'owner'}), {merge: true});
  await db.collection('users').doc(manager).set(
    profile('Priya Nair', 'manager@crudoc.test',
      {clinicId, memberKind: 'staff'}), {merge: true});
  await db.collection('users').doc(doctorTwo).set(
    profile('Dr Vikram Shah', 'doctor2@crudoc.test',
      {clinicId, memberKind: 'doctor'}), {merge: true});
  await db.collection('users').doc(doctorThree).set(
    profile('Dr Meera Pillai', 'doctor3@crudoc.test',
      {clinicId, memberKind: 'doctor'}), {merge: true});
  await db.collection('users').doc(recep).set(
    profile('Rahul Das', 'reception@crudoc.test',
      {clinicId, memberKind: 'staff'}), {merge: true});

  // ---- patients --------------------------------------------------------
  // Names are stored in plain text on purpose: FieldCipher.decrypt passes
  // through anything without its `enc:v1:` prefix.
  const day = (y, m, d) => admin.firestore.Timestamp.fromDate(
    new Date(Date.UTC(y, m - 1, d)));

  const patients = [
    {
      id: 'seed-alice', firstName: 'Alice', lastName: 'Fernandes',
      phone: '+919876500001', gender: 'female', dob: day(1988, 3, 14),
      assignedDoctorUids: [doctorTwo],
    },
    {
      id: 'seed-bhavna', firstName: 'Bhavna', lastName: 'Kulkarni',
      phone: '+919876500002', gender: 'female', dob: day(1975, 11, 2),
      assignedDoctorUids: [doctorThree],
    },
    {
      id: 'seed-chetan', firstName: 'Chetan', lastName: 'Iyer',
      phone: '+919876500003', gender: 'male', dob: day(1996, 7, 21),
      assignedDoctorUids: [doctorTwo, doctorThree],
    },
    {
      id: 'seed-dinesh', firstName: 'Dinesh', lastName: 'Patil',
      phone: '+919876500004', gender: 'male', dob: day(1962, 1, 9),
      assignedDoctorUids: [], // walk-in nobody has claimed yet
    },
  ];

  for (const p of patients) {
    await db.collection('patients').doc(p.id).set({
      doctorId: clinicId,
      firstName: p.firstName,
      lastName: p.lastName,
      phone: p.phone,
      email: '',
      gender: p.gender,
      dateOfBirth: p.dob,
      diagnosis: [],
      notes: '',
      packageBalance: 0,
      isArchived: false,
      assignedDoctorUids: p.assignedDoctorUids,
      createdAt: now,
      updatedAt: now,
    });

    // A clinical record each, so clinical access is visible.
    await db.collection('dental_records').doc(`rec-${p.id}`).set({
      doctorId: clinicId,
      patientId: p.id,
      // The copy of the patient's assignment that a scoped doctor's sync
      // narrows on. In production the stamp*Assignment functions write it;
      // set here too so the demo never depends on them having run yet.
      assignedDoctorUids: p.assignedDoctorUids,
      note: `Clinical note for ${p.firstName} — only clinical roles see this.`,
      createdAt: now,
      updatedAt: now,
    });
  }

  // ---- what to expect --------------------------------------------------
  const line = '─'.repeat(72);
  console.log(`✅ Seeded clinic "Sunrise Dental"  (clinic id = ${clinicId})`);
  console.log(`   adminClinicalAccess: false     clinicalAccessScope: assigned\n`);
  console.log(line);
  console.log('SIGN IN  (password for all accounts: ' + PASSWORD + ')');
  console.log(line);
  console.log(`  owner@crudoc.test       Dr Asha Rao      owner, sees everything`);
  console.log(`  manager@crudoc.test     Priya Nair       Admin role, NO clinical access`);
  console.log(`  doctor2@crudoc.test     Dr Vikram Shah   doctor, Alice + Chetan`);
  console.log(`  doctor3@crudoc.test     Dr Meera Pillai  doctor, Bhavna + Chetan`);
  console.log(`  reception@crudoc.test   Rahul Das        front desk, all patients, no charts`);
  console.log(line);
  console.log('WHAT TO LOOK FOR');
  console.log(line);
  console.log('  Priya (admin):   can open Team, settings, billing and revenue,');
  console.log('                   but no clinical records anywhere. The owner can');
  console.log('                   grant it in Settings → Team → Clinical records.');
  console.log('  Dr Vikram:       patient list shows Alice and Chetan only.');
  console.log('                   Bhavna is absent from the list.');
  console.log('  Dr Meera:        patient list shows Bhavna and Chetan only.');
  console.log('  Rahul (desk):    all four patients, no clinical records.');
  console.log('  Dinesh:          assigned to nobody, so he stays reachable by');
  console.log('                   every doctor but is not in a scoped list.');
  console.log(line);
  console.log('Emulator UI: http://' + EMU_HOST + ':4000/firestore');
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('❌ Seeding failed:', err.message);
    if (String(err.message).includes('ECONNREFUSED')) {
      console.error('   Are the emulators running?  firebase emulators:start');
    }
    process.exit(1);
  });
