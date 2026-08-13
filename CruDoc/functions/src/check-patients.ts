import * as admin from 'firebase-admin';
import * as crypto from 'crypto';

if (!admin.apps.length) {
  admin.initializeApp({
    projectId: 'svayatta-crudoc-dev',
  });
}

const db = admin.firestore();
const APP_PEPPER = '7TKgLHp1WG3Mh2yywTCgZWDXJ7rLcwZ161LiZ9ct8SE=';

function deriveKek(doctorId: string): Buffer {
  return crypto.createHash('sha256').update(`${doctorId}::${APP_PEPPER}`).digest();
}

async function getDoctorDek(doctorId: string): Promise<Buffer | null> {
  try {
    const keyDoc = await db.collection('doctor_keys').doc(doctorId).get();
    if (!keyDoc.exists) return null;
    const wrappedKey = keyDoc.data()?.wrappedKey as string | undefined;
    if (!wrappedKey || !wrappedKey.includes('.')) return null;

    const parts = wrappedKey.split('.');
    const iv = Buffer.from(parts[0], 'base64');
    const ciphertext = Buffer.from(parts[1], 'base64');

    const authTag = ciphertext.subarray(ciphertext.length - 16);
    const encryptedData = ciphertext.subarray(0, ciphertext.length - 16);

    const kek = deriveKek(doctorId);
    const decipher = crypto.createDecipheriv('aes-256-gcm', kek, iv);
    decipher.setAuthTag(authTag);

    return Buffer.concat([decipher.update(encryptedData), decipher.final()]);
  } catch (e) {
    return null;
  }
}

function decryptField(value: string | undefined, dek: Buffer | null): string {
  if (!value || !value.startsWith('enc:v1:')) return value || '';
  if (!dek) return value;

  try {
    const body = value.substring('enc:v1:'.length);
    const parts = body.split('.');
    const iv = Buffer.from(parts[0], 'base64');
    const ciphertext = Buffer.from(parts[1], 'base64');

    const authTag = ciphertext.subarray(ciphertext.length - 16);
    const encryptedData = ciphertext.subarray(0, ciphertext.length - 16);

    const decipher = crypto.createDecipheriv('aes-256-gcm', dek, iv);
    decipher.setAuthTag(authTag);

    return Buffer.concat([decipher.update(encryptedData), decipher.final()]).toString('utf8');
  } catch (e) {
    return value;
  }
}

async function checkPatients() {
  const snapshot = await db.collection('patients').get();
  console.log(`\n========================================`);
  console.log(`TOTAL PATIENT RECORDS IN FIRESTORE: ${snapshot.docs.length}`);
  console.log(`========================================\n`);

  for (let i = 0; i < snapshot.docs.length; i++) {
    const doc = snapshot.docs[i];
    const data = doc.data();
    const doctorId = data.doctorId as string;
    const dek = doctorId ? await getDoctorDek(doctorId) : null;

    const rawEmail = data.email as string | undefined;
    const decryptedEmail = decryptField(rawEmail, dek);

    const rawFirstName = data.firstName as string | undefined;
    const rawLastName = data.lastName as string | undefined;
    const rawFullName = data.fullName as string | undefined;

    const decryptedFirstName = decryptField(rawFirstName, dek);
    const decryptedLastName = decryptField(rawLastName, dek);
    const decryptedFullName = decryptField(rawFullName, dek);

    const displayName = decryptedFullName || `${decryptedFirstName} ${decryptedLastName}`.trim() || 'Unknown';

    console.log(`Patient #${i + 1} [ID: ${doc.id}]`);
    console.log(`  Name: ${displayName}`);
    console.log(`  Doctor ID: ${doctorId}`);
    console.log(`  Raw Stored Email: ${rawEmail ?? '(null/empty)'}`);
    console.log(`  Decrypted Email: ${decryptedEmail ?? '(null/empty)'}`);
    console.log(`----------------------------------------`);
  }
}

checkPatients().catch(console.error);
