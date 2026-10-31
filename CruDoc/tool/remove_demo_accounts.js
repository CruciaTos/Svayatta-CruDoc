// Removes the shared demo accounts (doctor@crudoc.com, dental@crudoc.com, …)
// and everything they own from the live Firebase project.
//
//   node tool/remove_demo_accounts.js            dry run: lists what it finds
//   node tool/remove_demo_accounts.js --delete   deletes it
//
// Needs Google credentials for the project:
//   gcloud auth application-default login
//
// Only the demo addresses below are touched. Any other @crudoc.com account
// is listed so you can see it, never deleted.

const admin = require('../functions/node_modules/firebase-admin');

const PROJECT = 'svayatta-crudoc-dev';
const BUCKET = 'svayatta-crudoc-dev.firebasestorage.app';
const DELETE = process.argv.includes('--delete');

// Same list as DoctorSpecialty.demoEmail in lib/core/models/doctor_specialty.dart.
const DEMO_EMAILS = [
  'doctor@crudoc.com',
  'cardio@crudoc.com',
  'pedia@crudoc.com',
  'dental@crudoc.com',
  'derm@crudoc.com',
  'ortho@crudoc.com',
  'gynec@crudoc.com',
  'psych@crudoc.com',
  'physio@crudoc.com',
  'homeo@crudoc.com',
];

// Fields that tie a document to the account that owns it.
const UID_FIELDS = [
  'doctorId', 'doctorUid', 'ownerUid', 'ownerId', 'uid', 'userId', 'createdBy',
];
const EMAIL_FIELDS = ['email', 'doctorEmail'];

// Storage folders keyed by the doctor's uid (see storage.rules). The clinic
// id of a solo doctor is their uid, so clinic-blobs is covered too.
const STORAGE_PREFIXES = (uid) => [
  `doctors/${uid}/`,
  `patient-files/${uid}/`,
  `voice-scratch/doctors/${uid}/`,
  `referral_uploads/${uid}/`,
  `clinic-blobs/${uid}/`,
];

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: PROJECT,
  storageBucket: BUCKET,
});
const db = admin.firestore();
const auth = admin.auth();
const bucket = admin.storage().bucket();

async function findDemoUsers() {
  const demo = [];
  const otherCrudoc = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const u of page.users) {
      const email = (u.email || '').toLowerCase();
      if (DEMO_EMAILS.includes(email)) demo.push(u);
      else if (email.endsWith('@crudoc.com')) otherCrudoc.push(u);
    }
    pageToken = page.pageToken;
  } while (pageToken);
  return { demo, otherCrudoc };
}

// Every top-level document owned by these accounts: by id, by owner field,
// or by email. Returns a Map path -> DocumentReference.
async function findDocs(users) {
  const uids = users.map((u) => u.uid);
  const emails = users.map((u) => u.email.toLowerCase());
  const found = new Map();
  const add = (ref) => found.set(ref.path, ref);

  const collections = await db.listCollections();
  for (const col of collections) {
    for (const uid of uids) {
      const byId = await col.doc(uid).get();
      if (byId.exists) add(byId.ref);
    }
    // `in` takes up to 30 values; there are at most 10 demo accounts.
    for (const field of UID_FIELDS) {
      const snap = await col.where(field, 'in', uids).get();
      snap.docs.forEach((d) => add(d.ref));
    }
    for (const field of EMAIL_FIELDS) {
      const snap = await col.where(field, 'in', emails).get();
      snap.docs.forEach((d) => add(d.ref));
    }
  }

  // Memberships in other clinics.
  const members = await db.collectionGroup('members').where('uid', 'in', uids).get();
  members.docs.forEach((d) => add(d.ref));
  return found;
}

async function findFiles(users) {
  const files = [];
  for (const u of users) {
    for (const prefix of STORAGE_PREFIXES(u.uid)) {
      const [list] = await bucket.getFiles({ prefix });
      files.push(...list);
    }
  }
  return files;
}

async function main() {
  console.log(`Project: ${PROJECT}  (${DELETE ? 'DELETING' : 'dry run'})\n`);

  const { demo, otherCrudoc } = await findDemoUsers();
  console.log(`Demo accounts found: ${demo.length}`);
  demo.forEach((u) => console.log(`  ${u.email}  ${u.uid}`));
  if (otherCrudoc.length) {
    console.log(`\nOther @crudoc.com accounts (left alone): ${otherCrudoc.length}`);
    otherCrudoc.forEach((u) => console.log(`  ${u.email}  ${u.uid}`));
  }
  if (!demo.length) {
    console.log('\nNothing to remove.');
    return;
  }

  const docs = await findDocs(demo);
  const byCollection = {};
  for (const path of docs.keys()) {
    const col = path.split('/')[0];
    byCollection[col] = (byCollection[col] || 0) + 1;
  }
  console.log(`\nFirestore documents (plus their subcollections): ${docs.size}`);
  Object.entries(byCollection)
    .sort((a, b) => b[1] - a[1])
    .forEach(([col, n]) => console.log(`  ${col}: ${n}`));

  const files = await findFiles(demo);
  console.log(`\nStorage files: ${files.length}`);
  files.slice(0, 20).forEach((f) => console.log(`  ${f.name}`));
  if (files.length > 20) console.log(`  … and ${files.length - 20} more`);

  if (!DELETE) {
    console.log('\nDry run only. Run again with --delete to remove all of the above.');
    return;
  }

  console.log('\nDeleting Firestore documents…');
  for (const ref of docs.values()) await db.recursiveDelete(ref);
  console.log('Deleting storage files…');
  for (const f of files) await f.delete({ ignoreNotFound: true });
  console.log('Deleting login accounts…');
  const result = await auth.deleteUsers(demo.map((u) => u.uid));
  result.errors.forEach((e) => console.log(`  failed: ${demo[e.index].email}: ${e.error.message}`));

  // The Super Admin dashboard caches its totals per day; drop today's so it
  // recounts without the demo doctors.
  const now = new Date();
  const todayKey = [
    now.getFullYear(),
    String(now.getMonth() + 1).padStart(2, '0'),
    String(now.getDate()).padStart(2, '0'),
  ].join('-');
  await db.collection('analytics').doc(todayKey).delete();
  console.log(`Cleared Super Admin dashboard cache for ${todayKey}.`);

  console.log(
    `\nDone: ${docs.size} documents, ${files.length} files, ` +
      `${result.successCount} accounts removed.`,
  );
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
