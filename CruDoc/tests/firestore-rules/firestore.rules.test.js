// Run with the Firestore emulator up, from CruDoc/:
//   firebase emulators:exec --project demo-crudoc --only firestore "npm test --prefix tests/firestore-rules"
import { readFileSync } from 'node:fs';
import { after, afterEach, before, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const RULES = fileURLToPath(new URL('../../firestore.rules', import.meta.url));

const A = 'doctor-a';
const B = 'doctor-b';
const ADMIN = 'admin-1';
const ADMIN_CLAIMS = { role: 'superAdmin', isTwoFAVerified: true };

// Every top-level collection the app keys by doctorId.
const DOCTOR_OWNED = [
  'patients',
  'appointments',
  'visitations',
  'walk_in_queue',
  'invoices',
  'revenue_entries',
  'pending_payments',
  'medicines',
  'stock_transactions',
  'dental_records',
  'radiology_docs',
  'homeopathy_case_sheets',
  'whatsapp_notification_logs',
  'dental_procedure_catalog',
  'tooth_chart_entries',
  'procedure_log_entries',
  'sterilization_log_entries',
  'treatment_plan_line_items',
];

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-crudoc-firestore-rules',
    firestore: { rules: readFileSync(RULES, 'utf8') },
  });
});

after(async () => {
  await env.cleanup();
});

afterEach(async () => {
  await env.clearFirestore();
});

const as = (uid, claims) => env.authenticatedContext(uid, claims).firestore();
const doctor = (uid) => as(uid, { role: 'doctor', email: `${uid}@clinic.test` });
const admin = () => as(ADMIN, ADMIN_CLAIMS);
const anonymous = () => env.unauthenticatedContext().firestore();

/** Puts a document in place without going through the rules. */
async function seed(path, data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), path), data);
  });
}

describe('doctor-owned clinical collections', () => {
  for (const name of DOCTOR_OWNED) {
    describe(name, () => {
      const path = `${name}/r1`;

      it('lets the owning doctor create, read, update and delete', async () => {
        const db = doctor(A);
        await assertSucceeds(setDoc(doc(db, path), { doctorId: A, v: 1 }));
        await assertSucceeds(getDoc(doc(db, path)));
        await assertSucceeds(updateDoc(doc(db, path), { v: 2 }));
        await assertSucceeds(
          getDocs(query(collection(db, name), where('doctorId', '==', A))),
        );
        await assertSucceeds(deleteDoc(doc(db, path)));
      });

      it('keeps another doctor out', async () => {
        await seed(path, { doctorId: A });
        const db = doctor(B);
        await assertFails(getDoc(doc(db, path)));
        await assertFails(updateDoc(doc(db, path), { v: 2 }));
        await assertFails(setDoc(doc(db, path), { doctorId: B }));
        await assertFails(deleteDoc(doc(db, path)));
        await assertFails(
          getDocs(query(collection(db, name), where('doctorId', '==', A))),
        );
      });

      it('keeps Super Admin out of patient data', async () => {
        await seed(path, { doctorId: A });
        await assertFails(getDoc(doc(admin(), path)));
      });

      it('keeps signed-out users out', async () => {
        await seed(path, { doctorId: A });
        await assertFails(getDoc(doc(anonymous(), path)));
        await assertFails(setDoc(doc(anonymous(), `${name}/r2`), { doctorId: A }));
      });
    });
  }

  it('refuses a list query without a doctorId filter', async () => {
    await seed('invoices/i1', { doctorId: A });
    await assertFails(getDocs(collection(doctor(A), 'invoices')));
  });

  it('refuses a record created in another doctor’s name', async () => {
    await assertFails(setDoc(doc(doctor(B), 'patients/p1'), { doctorId: A }));
  });

  it('refuses a record created without a doctorId', async () => {
    await assertFails(setDoc(doc(doctor(A), 'patients/p1'), { name: 'x' }));
  });

  it('refuses handing a record to another doctor', async () => {
    await seed('patients/p1', { doctorId: A });
    await assertFails(updateDoc(doc(doctor(A), 'patients/p1'), { doctorId: B }));
  });

  it('allows reading or deleting a record that does not exist yet', async () => {
    // The sync service deletes from both visit collections in one batch.
    const db = doctor(A);
    await assertSucceeds(getDoc(doc(db, 'visitations/missing')));
    const batch = writeBatch(db);
    batch.delete(doc(db, 'appointments/missing'));
    batch.delete(doc(db, 'visitations/missing'));
    await assertSucceeds(batch.commit());
  });
});

describe('access_logs', () => {
  const entry = (overrides = {}) => ({
    doctorId: A,
    actorUid: A,
    action: 'patient.view',
    patientId: 'p1',
    target: null,
    platform: 'windows',
    at: serverTimestamp(),
    ...overrides,
  });

  it('lets a doctor add to and read their own log', async () => {
    const db = doctor(A);
    await assertSucceeds(setDoc(doc(db, 'access_logs/l1'), entry()));
    await assertSucceeds(
      setDoc(doc(db, 'access_logs/l2'), entry({ action: 'file.download', target: 'doctors/a/x.pdf' })),
    );
    await assertSucceeds(getDoc(doc(db, 'access_logs/l1')));
    await assertSucceeds(
      getDocs(query(collection(db, 'access_logs'), where('doctorId', '==', A))),
    );
  });

  it('never lets an entry be changed or deleted', async () => {
    await seed('access_logs/l1', { doctorId: A, actorUid: A, action: 'patient.view' });
    await assertFails(updateDoc(doc(doctor(A), 'access_logs/l1'), { patientId: 'p2' }));
    await assertFails(deleteDoc(doc(doctor(A), 'access_logs/l1')));
    await assertFails(deleteDoc(doc(admin(), 'access_logs/l1')));
  });

  it("keeps another doctor out of a doctor's log", async () => {
    await seed('access_logs/l1', { doctorId: A, actorUid: A, action: 'patient.view' });
    await assertFails(getDoc(doc(doctor(B), 'access_logs/l1')));
    await assertFails(setDoc(doc(doctor(B), 'access_logs/l2'), entry()));
  });

  it('refuses back-dated, unknown or padded entries', async () => {
    const db = doctor(A);
    await assertFails(setDoc(doc(db, 'access_logs/l1'), entry({ at: new Date(2020, 0, 1) })));
    await assertFails(setDoc(doc(db, 'access_logs/l2'), entry({ action: 'patient.edit' })));
    await assertFails(setDoc(doc(db, 'access_logs/l3'), entry({ note: 'x' })));
    await assertFails(setDoc(doc(db, 'access_logs/l4'), entry({ actorUid: B })));
  });
});

describe('doctor_keys', () => {
  const key = { wrappedKey: 'iv.cipher' };

  it('lets a doctor create and read their own key once', async () => {
    await assertSucceeds(setDoc(doc(doctor(A), `doctor_keys/${A}`), key));
    await assertSucceeds(getDoc(doc(doctor(A), `doctor_keys/${A}`)));
    await assertFails(setDoc(doc(doctor(A), `doctor_keys/${A}`), { wrappedKey: 'other' }));
    await assertFails(deleteDoc(doc(doctor(A), `doctor_keys/${A}`)));
  });

  it("keeps another doctor and Super Admin away from a doctor's key", async () => {
    await seed(`doctor_keys/${A}`, key);
    await assertFails(getDoc(doc(doctor(B), `doctor_keys/${A}`)));
    await assertFails(getDoc(doc(admin(), `doctor_keys/${A}`)));
  });

  it('does not let a doctor plant a key for someone else', async () => {
    await assertFails(setDoc(doc(doctor(B), `doctor_keys/${A}`), key));
  });

  it('refuses extra fields', async () => {
    await assertFails(
      setDoc(doc(doctor(A), `doctor_keys/${A}`), { ...key, note: 'x' }),
    );
  });
});

describe('users', () => {
  it('lets a doctor read and update their own profile', async () => {
    await seed(`users/${A}`, { email: `${A}@clinic.test`, role: 'doctor' });
    await assertSucceeds(getDoc(doc(doctor(A), `users/${A}`)));
    await assertSucceeds(updateDoc(doc(doctor(A), `users/${A}`), { clinicName: 'X' }));
  });

  it("keeps a doctor out of another doctor's profile", async () => {
    await seed(`users/${A}`, { email: `${A}@clinic.test` });
    await assertFails(getDoc(doc(doctor(B), `users/${A}`)));
    await assertFails(updateDoc(doc(doctor(B), `users/${A}`), { clinicName: 'X' }));
  });

  it('lets the login screen find a profile by the signed-in email only', async () => {
    await seed('users/precreated', { email: `${A}@clinic.test` });
    await assertSucceeds(
      getDocs(query(collection(doctor(A), 'users'), where('email', '==', `${A}@clinic.test`))),
    );
    await assertFails(
      getDocs(query(collection(doctor(B), 'users'), where('email', '==', `${A}@clinic.test`))),
    );
  });

  it('lets a new user create their own profile as a doctor', async () => {
    await assertSucceeds(setDoc(doc(doctor(A), `users/${A}`), { email: 'a@x', uid: A }));
    await assertSucceeds(setDoc(doc(doctor(B), `users/${B}`), { role: 'doctor' }));
  });

  it('never lets a user make themselves Super Admin', async () => {
    await assertFails(setDoc(doc(doctor(A), `users/${A}`), { role: 'superAdmin' }));
    await seed(`users/${B}`, { role: 'doctor' });
    await assertFails(updateDoc(doc(doctor(B), `users/${B}`), { role: 'superAdmin' }));
  });

  it("lets a doctor use their own subcollections but not another's", async () => {
    await assertSucceeds(
      setDoc(doc(doctor(A), `users/${A}/active_sessions/s1`), { status: 'active' }),
    );
    await assertSucceeds(
      setDoc(doc(doctor(A), `users/${A}/campaigns/c1/recipients/r1`), { x: 1 }),
    );
    await assertSucceeds(setDoc(doc(doctor(A), `users/${A}/medical_records/n1`), { x: 1 }));
    await assertFails(getDoc(doc(doctor(B), `users/${A}/medical_records/n1`)));
    await assertFails(setDoc(doc(doctor(B), `users/${A}/active_sessions/s2`), { x: 1 }));
  });

  it('lets Super Admin manage profiles and revoke sessions, not read notes', async () => {
    await seed(`users/${A}`, { role: 'doctor' });
    await seed(`users/${A}/active_sessions/s1`, { status: 'active' });
    await seed(`users/${A}/medical_records/n1`, { x: 1 });
    await assertSucceeds(getDocs(collection(admin(), 'users')));
    await assertSucceeds(updateDoc(doc(admin(), `users/${A}`), { status: 'Disabled' }));
    await assertSucceeds(getDocs(collection(admin(), `users/${A}/active_sessions`)));
    await assertSucceeds(deleteDoc(doc(admin(), `users/${A}/active_sessions/s1`)));
    await assertFails(getDoc(doc(admin(), `users/${A}/medical_records/n1`)));
  });

  it('does not treat a role claim without 2FA as Super Admin', async () => {
    await seed(`users/${A}`, { role: 'doctor' });
    const halfAdmin = as('x', { role: 'superAdmin' });
    await assertFails(getDoc(doc(halfAdmin, `users/${A}`)));
  });
});

describe('subscriptions, feature flags and doctor settings', () => {
  for (const name of ['subscriptions', 'feature_flags', 'doctor_settings']) {
    it(`${name}: doctor reads own, Super Admin writes`, async () => {
      await seed(`${name}/${A}`, { plan: 'starter' });
      await assertSucceeds(getDoc(doc(doctor(A), `${name}/${A}`)));
      await assertFails(getDoc(doc(doctor(B), `${name}/${A}`)));
      await assertFails(setDoc(doc(doctor(A), `${name}/${A}`), { plan: 'pro' }));
      await assertSucceeds(setDoc(doc(admin(), `${name}/${A}`), { plan: 'pro' }));
    });
  }
});

describe('payments and upgrade requests', () => {
  for (const name of ['payment_transactions', 'upgrade_requests']) {
    it(`${name}: doctor creates and reads own only`, async () => {
      await assertSucceeds(setDoc(doc(doctor(A), `${name}/t1`), { doctorId: A }));
      await assertSucceeds(getDoc(doc(doctor(A), `${name}/t1`)));
      await assertFails(getDoc(doc(doctor(B), `${name}/t1`)));
      await assertFails(setDoc(doc(doctor(B), `${name}/t2`), { doctorId: A }));
      await assertFails(updateDoc(doc(doctor(A), `${name}/t1`), { status: 'x' }));
      await assertSucceeds(updateDoc(doc(admin(), `${name}/t1`), { status: 'x' }));
    });
  }
});

describe('admin-only collections', () => {
  for (const name of ['audit_logs', 'analytics', 'api_keys', 'api_logs', 'system_config']) {
    it(`${name}: Super Admin only`, async () => {
      await seed(`${name}/x`, { a: 1 });
      await assertFails(getDoc(doc(doctor(A), `${name}/x`)));
      await assertSucceeds(getDoc(doc(admin(), `${name}/x`)));
    });
  }

  it('audit logs cannot be changed or deleted, even by Super Admin', async () => {
    await seed('audit_logs/x', { a: 1 });
    await assertFails(updateDoc(doc(admin(), 'audit_logs/x'), { a: 2 }));
    await assertFails(deleteDoc(doc(admin(), 'audit_logs/x')));
  });

  it('any signed-in user can read the client keys', async () => {
    await seed('system_config/client_keys', { googleMapsApiKey: 'k' });
    await assertSucceeds(getDoc(doc(doctor(A), 'system_config/client_keys')));
    await assertFails(getDoc(doc(anonymous(), 'system_config/client_keys')));
    await assertFails(setDoc(doc(doctor(A), 'system_config/client_keys'), { k: 1 }));
  });

  it('plans are readable by any signed-in user, written by Super Admin', async () => {
    await seed('plans/p', { a: 1 });
    await assertSucceeds(getDoc(doc(doctor(A), 'plans/p')));
    await assertFails(setDoc(doc(doctor(A), 'plans/p'), { a: 2 }));
  });
});

describe('notifications and support tickets', () => {
  it('a doctor reads and marks their own notification only', async () => {
    await seed('notifications/n1', { doctorId: A, read: false });
    await assertSucceeds(getDoc(doc(doctor(A), 'notifications/n1')));
    await assertSucceeds(updateDoc(doc(doctor(A), 'notifications/n1'), { read: true }));
    await assertFails(getDoc(doc(doctor(B), 'notifications/n1')));
    await assertFails(setDoc(doc(doctor(A), 'notifications/n2'), { doctorId: A }));
  });

  it('a doctor opens tickets in their own name only', async () => {
    await assertSucceeds(setDoc(doc(doctor(A), 'support_tickets/t1'), { doctorId: A }));
    await assertFails(setDoc(doc(doctor(B), 'support_tickets/t2'), { doctorId: A }));
    await assertFails(getDoc(doc(doctor(B), 'support_tickets/t1')));
  });
});

describe('everything else', () => {
  it('is denied by default, even for a signed-in doctor', async () => {
    await seed('medical_documents/m1', { doctorId: A });
    await assertFails(getDoc(doc(doctor(A), 'medical_documents/m1')));
    await assertFails(setDoc(doc(doctor(A), 'anything/x'), { doctorId: A }));
  });
});
