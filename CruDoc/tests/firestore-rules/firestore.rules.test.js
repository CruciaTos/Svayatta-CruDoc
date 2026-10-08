// Run with the Firestore emulator up, from CruDoc/:
//   firebase emulators:exec --project demo-crudoc --only firestore "npm test --prefix tests/firestore-rules"
import { readFileSync } from 'node:fs';
import { after, afterEach, before, beforeEach, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  collectionGroup,
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

describe('whatsapp reminder log', () => {
  it('a doctor reads their own delivery rows but cannot write them', async () => {
    await seed('whatsapp_notification_logs/appt-1', {
      doctorId: A, status: 'sent', recipientPhone: '919876543210',
    });
    await assertSucceeds(getDoc(doc(doctor(A), 'whatsapp_notification_logs/appt-1')));
    await assertSucceeds(getDocs(query(
      collection(doctor(A), 'whatsapp_notification_logs'),
      where('doctorId', '==', A),
    )));

    // Only the functions that actually sent the message may say what happened.
    await assertFails(
      setDoc(doc(doctor(A), 'whatsapp_notification_logs/appt-2'), { doctorId: A }),
    );
    await assertFails(
      updateDoc(doc(doctor(A), 'whatsapp_notification_logs/appt-1'), { status: 'read' }),
    );
    await assertFails(deleteDoc(doc(doctor(A), 'whatsapp_notification_logs/appt-1')));
  });

  it('keeps one doctor out of another doctor\'s delivery rows', async () => {
    await seed('whatsapp_notification_logs/appt-1', { doctorId: A, status: 'sent' });
    await assertFails(getDoc(doc(doctor(B), 'whatsapp_notification_logs/appt-1')));
    await assertFails(getDocs(collection(doctor(B), 'whatsapp_notification_logs')));
  });

  it('hides opt-outs and auto-reply timers from everyone', async () => {
    // Keyed by phone and shared across clinics, so a readable row would tell
    // one doctor that a number also belongs to another practice's patient.
    await seed('whatsapp_optouts/919876543210', { phone: '919876543210' });
    await seed('whatsapp_autoreplies/919876543210', { phone: '919876543210' });
    await assertFails(getDoc(doc(doctor(A), 'whatsapp_optouts/919876543210')));
    await assertFails(getDocs(collection(doctor(A), 'whatsapp_optouts')));
    await assertFails(getDoc(doc(doctor(A), 'whatsapp_autoreplies/919876543210')));
    await assertFails(
      setDoc(doc(doctor(A), 'whatsapp_optouts/919876543210'), { phone: 'x' }),
    );
  });
});

describe('whatsapp per-clinic credentials', () => {
  it('keeps a doctor out of their own tenant record', async () => {
    // It names the Secret Manager entry holding the token that sends to this
    // clinic's patients. Only the Admin SDK may touch it.
    await seed(`whatsapp_tenants/${A}`, {
      doctorId: A,
      wabaId: 'waba-1',
      phoneNumberId: 'pn-1',
      tokenSecretName: 'projects/p/secrets/wa_token_doctor-a',
    });
    await assertFails(getDoc(doc(doctor(A), `whatsapp_tenants/${A}`)));
    await assertFails(getDocs(collection(doctor(A), 'whatsapp_tenants')));
    await assertFails(setDoc(doc(doctor(A), `whatsapp_tenants/${A}`), { wabaId: 'x' }));
    await assertFails(deleteDoc(doc(doctor(A), `whatsapp_tenants/${A}`)));
  });

  it('keeps a doctor out of the template subcollection too', async () => {
    await seed(`whatsapp_tenants/${A}/templates/appt_confirmation`, { status: 'APPROVED' });
    await assertFails(
      getDoc(doc(doctor(A), `whatsapp_tenants/${A}/templates/appt_confirmation`)),
    );
    await assertFails(
      setDoc(doc(doctor(A), `whatsapp_tenants/${A}/templates/x`), { status: 'APPROVED' }),
    );
  });

  it('hides the message index and onboarding nonces from everyone', async () => {
    await seed('whatsapp_message_index/wamid.abc', { doctorId: A });
    await seed('whatsapp_onboarding_sessions/nonce-1', { doctorId: A });
    await assertFails(getDoc(doc(doctor(A), 'whatsapp_message_index/wamid.abc')));
    await assertFails(getDoc(doc(doctor(A), 'whatsapp_onboarding_sessions/nonce-1')));
    // A readable nonce would let someone attach their own WhatsApp account to
    // another doctor.
    await assertFails(getDocs(collection(doctor(A), 'whatsapp_onboarding_sessions')));
  });

  it('lets a doctor read only their own connection status, and never write it', async () => {
    await seed(`whatsapp_connections/${A}`, {
      doctorId: A,
      connected: true,
      displayPhoneNumber: '+91 98765 43210',
    });
    await assertSucceeds(getDoc(doc(doctor(A), `whatsapp_connections/${A}`)));
    await assertFails(getDoc(doc(doctor(B), `whatsapp_connections/${A}`)));
    await assertFails(getDocs(collection(doctor(A), 'whatsapp_connections')));
    // Marking yourself connected must not be possible from a client.
    await assertFails(
      setDoc(doc(doctor(A), `whatsapp_connections/${A}`), { connected: true }),
    );
    await assertFails(
      updateDoc(doc(doctor(A), `whatsapp_connections/${A}`), { needsReauth: false }),
    );
  });
});

describe('everything else', () => {
  it('is denied by default, even for a signed-in doctor', async () => {
    await seed('medical_documents/m1', { doctorId: A });
    await assertFails(getDoc(doc(doctor(A), 'medical_documents/m1')));
    await assertFails(setDoc(doc(doctor(A), 'anything/x'), { doctorId: A }));
  });
});

describe('clinic members', () => {
  const RECEP = 'recep-1';
  const ADMIN2 = 'admin-2';
  const GONE = 'gone-1';

  beforeEach(async () => {
    await seed(`clinics/${A}`, { name: 'Clinic A', ownerUid: A });
    await seed(`clinics/${A}/members/${RECEP}`, {
      active: true,
      roleId: 'receptionist',
      perms: ['patients.view', 'patients.edit', 'schedule', 'billing', 'messaging'],
      name: 'Recep',
    });
    await seed(`clinics/${A}/members/${ADMIN2}`, {
      active: true,
      roleId: 'admin',
      perms: [],
      name: 'Admin 2',
    });
    await seed(`clinics/${A}/members/${GONE}`, {
      active: false,
      roleId: 'doctor',
      perms: ['patients.view', 'clinical.view'],
      name: 'Gone Doctor',
    });
  });

  it('1. RECEP can create, get, update and list patients with doctorId: A', async () => {
    const db = as(RECEP, { email: 'recep@clinic.test' });
    await assertSucceeds(setDoc(doc(db, 'patients/p1'), { doctorId: A, name: 'Alice' }));
    await assertSucceeds(getDoc(doc(db, 'patients/p1')));
    await assertSucceeds(updateDoc(doc(db, 'patients/p1'), { name: 'Alice Updated', doctorId: A }));
    await assertSucceeds(
      getDocs(query(collection(db, 'patients'), where('doctorId', '==', A))),
    );
  });

  it('2. RECEP can create appointments and invoices for A; can create but cannot list revenue_entries', async () => {
    const db = as(RECEP, { email: 'recep@clinic.test' });
    await assertSucceeds(setDoc(doc(db, 'appointments/apt1'), { doctorId: A }));
    await assertSucceeds(setDoc(doc(db, 'invoices/inv1'), { doctorId: A }));
    await assertSucceeds(setDoc(doc(db, 'revenue_entries/rev1'), { doctorId: A }));
    await assertFails(
      getDocs(query(collection(db, 'revenue_entries'), where('doctorId', '==', A))),
    );
  });

  it('3. RECEP cannot get or list dental_records / radiology_docs of A', async () => {
    await seed('dental_records/dr1', { doctorId: A });
    await seed('radiology_docs/rad1', { doctorId: A });
    const db = as(RECEP, { email: 'recep@clinic.test' });
    await assertFails(getDoc(doc(db, 'dental_records/dr1')));
    await assertFails(
      getDocs(query(collection(db, 'dental_records'), where('doctorId', '==', A))),
    );
    await assertFails(getDoc(doc(db, 'radiology_docs/rad1')));
    await assertFails(
      getDocs(query(collection(db, 'radiology_docs'), where('doctorId', '==', A))),
    );
  });

  it('4. RECEP cannot change doctorId of a patient from A to RECEP', async () => {
    await seed('patients/p2', { doctorId: A, name: 'Bob' });
    const db = as(RECEP, { email: 'recep@clinic.test' });
    await assertFails(updateDoc(doc(db, 'patients/p2'), { doctorId: RECEP }));
  });

  it('5. ADMIN2 can list revenue_entries and dental_records of A', async () => {
    await seed('revenue_entries/rev2', { doctorId: A });
    await seed('dental_records/dr2', { doctorId: A });
    const db = as(ADMIN2, { email: 'admin2@clinic.test' });
    await assertSucceeds(
      getDocs(query(collection(db, 'revenue_entries'), where('doctorId', '==', A))),
    );
    await assertSucceeds(
      getDocs(query(collection(db, 'dental_records'), where('doctorId', '==', A))),
    );
  });

  it("6. GONE can't read anything of A", async () => {
    await seed('patients/p3', { doctorId: A, name: 'Charlie' });
    const db = as(GONE, { email: 'gone@clinic.test' });
    await assertFails(getDoc(doc(db, 'patients/p3')));
    await assertFails(
      getDocs(query(collection(db, 'patients'), where('doctorId', '==', A))),
    );
  });

  it("7. Doctor B (not a member) can't read anything of A", async () => {
    await seed('patients/p4', { doctorId: A });
    const db = doctor(B);
    await assertFails(
      getDocs(query(collection(db, 'patients'), where('doctorId', '==', A))),
    );
  });

  it('8. RECEP can read clinics/A, list clinics/A/members, read clinics/A/roles/x; cannot read clinics/A/invites/x; ADMIN2 can', async () => {
    await seed(`clinics/${A}/roles/role1`, { name: 'Nurse' });
    await seed(`clinics/${A}/invites/inv1`, { name: 'Pending Person', status: 'pending' });
    const recepDb = as(RECEP, { email: 'recep@clinic.test' });
    await assertSucceeds(getDoc(doc(recepDb, `clinics/${A}`)));
    await assertSucceeds(getDocs(collection(recepDb, `clinics/${A}/members`)));
    await assertSucceeds(getDoc(doc(recepDb, `clinics/${A}/roles/role1`)));
    await assertFails(getDoc(doc(recepDb, `clinics/${A}/invites/inv1`)));

    const adminDb = as(ADMIN2, { email: 'admin2@clinic.test' });
    await assertSucceeds(getDoc(doc(adminDb, `clinics/${A}/invites/inv1`)));
  });

  it("9. RECEP can update their own member doc's name and modules; cannot set modules to string; cannot update perms or roleId; cannot update another member", async () => {
    const db = as(RECEP, { email: 'recep@clinic.test' });
    await assertSucceeds(
      updateDoc(doc(db, `clinics/${A}/members/${RECEP}`), {
        name: 'Recep New',
        modules: ['patients'],
      }),
    );
    await assertFails(
      updateDoc(doc(db, `clinics/${A}/members/${RECEP}`), { modules: 'not-a-list' }),
    );
    await assertFails(
      updateDoc(doc(db, `clinics/${A}/members/${RECEP}`), { perms: ['team'] }),
    );
    await assertFails(
      updateDoc(doc(db, `clinics/${A}/members/${RECEP}`), { roleId: 'admin' }),
    );
    await assertFails(
      updateDoc(doc(db, `clinics/${A}/members/${ADMIN2}`), { name: 'Hacked' }),
    );
  });

  it('10. Nobody (RECEP, ADMIN2, A) can create a member, role or invite doc directly', async () => {
    for (const uid of [RECEP, ADMIN2, A]) {
      const db = as(uid, { email: `${uid}@clinic.test` });
      await assertFails(setDoc(doc(db, `clinics/${A}/members/m_new`), { active: true }));
      await assertFails(setDoc(doc(db, `clinics/${A}/roles/r_new`), { name: 'Custom' }));
      await assertFails(setDoc(doc(db, `clinics/${A}/invites/i_new`), { status: 'pending' }));
    }
  });

  it('11. RECEP can get doctor_keys/A; B cannot', async () => {
    await seed(`doctor_keys/${A}`, { wrappedKey: 'secret_key' });
    const recepDb = as(RECEP, { email: 'recep@clinic.test' });
    await assertSucceeds(getDoc(doc(recepDb, `doctor_keys/${A}`)));
    const bDb = doctor(B);
    await assertFails(getDoc(doc(bDb, `doctor_keys/${A}`)));
  });

  it('12. A user cannot create or update users/{self} with clinicId or memberKind', async () => {
    const selfDb = as('user-new', { email: 'new@clinic.test' });
    await assertFails(setDoc(doc(selfDb, 'users/user-new'), { clinicId: 'c1' }));
    await assertFails(setDoc(doc(selfDb, 'users/user-new'), { memberKind: 'doctor' }));
    await assertSucceeds(setDoc(doc(selfDb, 'users/user-new'), { name: 'Valid User' }));
    await assertFails(updateDoc(doc(selfDb, 'users/user-new'), { clinicId: 'c1' }));
    await assertFails(updateDoc(doc(selfDb, 'users/user-new'), { memberKind: 'staff' }));
  });

  it('13. RECEP writes 25 patients docs for A in one writeBatch -> succeeds', async () => {
    const db = as(RECEP, { email: 'recep@clinic.test' });
    const batch = writeBatch(db);
    for (let i = 0; i < 25; i++) {
      batch.set(doc(db, `patients/batch_${i}`), { doctorId: A, index: i });
    }
    await assertSucceeds(batch.commit());
  });

  it("14. access_logs: RECEP can create an entry with doctorId: A, actorUid: RECEP; cannot list A's log; ADMIN2 can", async () => {
    const recepDb = as(RECEP, { email: 'recep@clinic.test' });
    await assertSucceeds(
      setDoc(doc(recepDb, 'access_logs/log_recep'), {
        doctorId: A,
        actorUid: RECEP,
        action: 'patient.view',
        patientId: 'p1',
        target: 'patients/p1',
        platform: 'windows',
        at: serverTimestamp(),
      }),
    );
    await assertFails(
      getDocs(query(collection(recepDb, 'access_logs'), where('doctorId', '==', A))),
    );

    const adminDb = as(ADMIN2, { email: 'admin2@clinic.test' });
    await assertSucceeds(
      getDocs(query(collection(adminDb, 'access_logs'), where('doctorId', '==', A))),
    );
  });
});

describe('super admin clinic monitoring (read only)', () => {
  const OWNER = 'owner-1';
  const seedClinic = async () => {
    await seed(`clinics/${OWNER}`, { name: 'Clinic', ownerUid: OWNER });
    await seed(`clinics/${OWNER}/members/m1`, { name: 'Dr M', roleId: 'doctor', perms: [], active: true });
    await seed(`clinics/${OWNER}/roles/r1`, { name: 'Nurse', perms: [] });
    await seed(`clinics/${OWNER}/invites/i1`, { name: 'Pending', status: 'pending' });
    await seed('access_logs/team1', { doctorId: OWNER, actorUid: OWNER, action: 'team.invite', platform: 'server' });
    await seed('access_logs/view1', { doctorId: OWNER, actorUid: 'm1', action: 'patient.view', patientId: 'p1', platform: 'windows' });
  };

  it('reads clinics, members, roles and invites', async () => {
    await seedClinic();
    const db = admin();
    await assertSucceeds(getDocs(collection(db, 'clinics')));
    await assertSucceeds(getDocs(collection(db, `clinics/${OWNER}/members`)));
    await assertSucceeds(getDocs(collection(db, `clinics/${OWNER}/roles`)));
    await assertSucceeds(getDocs(collection(db, `clinics/${OWNER}/invites`)));
  });

  it('reads members and invites across all clinics (collection group)', async () => {
    await seedClinic();
    await assertSucceeds(getDocs(collectionGroup(admin(), 'members')));
    await assertSucceeds(getDocs(collectionGroup(admin(), 'invites')));
    await assertFails(getDocs(collectionGroup(doctor(B), 'members')));
    await assertFails(getDocs(collectionGroup(as('x', { role: 'superAdmin' }), 'invites')));
  });

  it('cannot write members, roles or invites', async () => {
    await seedClinic();
    const db = admin();
    await assertFails(updateDoc(doc(db, `clinics/${OWNER}/members/m1`), { active: false }));
    await assertFails(setDoc(doc(db, `clinics/${OWNER}/roles/r2`), { name: 'x' }));
    await assertFails(deleteDoc(doc(db, `clinics/${OWNER}/invites/i1`)));
  });

  it('reads team events but never patient.view entries', async () => {
    await seedClinic();
    const db = admin();
    await assertSucceeds(
      getDocs(query(collection(db, 'access_logs'), where('platform', '==', 'server'))),
    );
    await assertSucceeds(getDoc(doc(db, 'access_logs/team1')));
    await assertFails(getDoc(doc(db, 'access_logs/view1')));
    await assertFails(getDocs(collection(db, 'access_logs')));
  });

  it('keeps a half-verified admin and other doctors out', async () => {
    await seedClinic();
    const half = as('x', { role: 'superAdmin' });
    await assertFails(getDocs(collection(half, `clinics/${OWNER}/members`)));
    await assertFails(getDocs(collection(doctor(B), `clinics/${OWNER}/members`)));
  });
});

describe('files screen: folders and patient files', () => {
  const DOC2 = 'doctor-2'; // other doctors in clinic A
  const DOC3 = 'doctor-3';
  const RECEP = 'recep-1'; // no clinical access
  const ADMIN2 = 'admin-2';

  const folder = (over = {}) => ({
    doctorId: A,
    ownerUid: A,
    parentId: '',
    rootId: 'f1',
    name: 'X-rays',
    sharing: 'private',
    visibleTo: [A],
    isDeleted: false,
    ...over,
  });
  const file = (over = {}) => ({
    doctorId: A,
    ownerUid: A,
    patientId: 'p1',
    folderId: '',
    rootId: '',
    name: 'opg.jpg',
    contentType: 'image/jpeg',
    sizeBytes: 1200,
    storagePath: '',
    visibleTo: [A],
    isDeleted: false,
    ...over,
  });
  const mine = (db, uid) =>
    query(
      collection(db, 'patient_files'),
      where('doctorId', '==', A),
      where('visibleTo', 'array-contains', uid),
    );
  const team = (db, name = 'patient_files') =>
    query(
      collection(db, name),
      where('doctorId', '==', A),
      where('visibleTo', 'array-contains', 'team'),
    );

  beforeEach(async () => {
    await seed(`clinics/${A}`, { name: 'Clinic A', ownerUid: A });
    for (const uid of [DOC2, DOC3]) {
      await seed(`clinics/${A}/members/${uid}`, {
        active: true,
        roleId: 'doctor',
        perms: ['patients.view', 'clinical.view', 'clinical.edit'],
        name: uid,
      });
    }
    await seed(`clinics/${A}/members/${RECEP}`, {
      active: true,
      roleId: 'receptionist',
      perms: ['patients.view', 'schedule'],
      name: 'Recep',
    });
    await seed(`clinics/${A}/members/${ADMIN2}`, {
      active: true,
      roleId: 'admin',
      perms: [],
      name: 'Admin 2',
    });
  });

  it('lets a doctor keep private folders and files', async () => {
    const db = doctor(A);
    await assertSucceeds(setDoc(doc(db, 'file_folders/f1'), folder()));
    await assertSucceeds(
      setDoc(doc(db, 'patient_files/x1'), file({ folderId: 'f1', rootId: 'f1' })),
    );
    await assertSucceeds(setDoc(doc(db, 'patient_files/x2'), file()));
    await assertSucceeds(getDocs(mine(db, A)));
    await assertSucceeds(getDoc(doc(db, 'patient_files/x1')));
  });

  it('keeps a private folder from colleagues, other clinics and Super Admin', async () => {
    await seed('file_folders/f1', folder());
    await seed('patient_files/x1', file({ folderId: 'f1', rootId: 'f1' }));
    for (const db of [as(DOC2), doctor(B), admin()]) {
      await assertFails(getDoc(doc(db, 'file_folders/f1')));
      await assertFails(getDoc(doc(db, 'patient_files/x1')));
    }
    // Listing what is shared with the team returns nothing, without error.
    await assertSucceeds(getDocs(team(as(DOC2))));
    // Listing someone else's private files is refused.
    await assertFails(getDocs(mine(as(DOC2), A)));
  });

  it('refuses a list without the visibility filter', async () => {
    await seed('patient_files/x1', file());
    await assertFails(
      getDocs(query(collection(doctor(A), 'patient_files'), where('doctorId', '==', A))),
    );
  });

  it('shares a folder with the clinic, but not with people without clinical access', async () => {
    await seed('file_folders/f1', folder({ sharing: 'team', visibleTo: [A, 'team'] }));
    await seed(
      'patient_files/x1',
      file({ folderId: 'f1', rootId: 'f1', visibleTo: [A, 'team'] }),
    );
    await assertSucceeds(getDoc(doc(as(DOC2), 'patient_files/x1')));
    await assertSucceeds(getDocs(team(as(DOC2))));
    await assertSucceeds(getDocs(team(as(DOC2), 'file_folders')));
    await assertFails(getDoc(doc(as(RECEP), 'patient_files/x1')));
    await assertFails(getDocs(team(as(RECEP))));
    await assertFails(getDoc(doc(doctor(B), 'patient_files/x1')));
  });

  it('shares a folder with chosen doctors only', async () => {
    await seed('file_folders/f1', folder({ sharing: 'people', visibleTo: [A, DOC2] }));
    await seed(
      'patient_files/x1',
      file({ folderId: 'f1', rootId: 'f1', visibleTo: [A, DOC2] }),
    );
    await assertSucceeds(getDoc(doc(as(DOC2), 'patient_files/x1')));
    await assertSucceeds(getDocs(mine(as(DOC2), DOC2)));
    await assertFails(getDoc(doc(as(DOC3), 'patient_files/x1')));
  });

  it('lets a colleague add their own files and folders to a shared folder', async () => {
    await seed('file_folders/f1', folder({ sharing: 'team', visibleTo: [A, 'team'] }));
    const db = as(DOC2);
    await assertSucceeds(
      setDoc(
        doc(db, 'patient_files/x9'),
        file({ ownerUid: DOC2, folderId: 'f1', rootId: 'f1', visibleTo: [A, 'team'] }),
      ),
    );
    await assertSucceeds(
      setDoc(
        doc(db, 'file_folders/f9'),
        folder({
          ownerUid: DOC2,
          parentId: 'f1',
          rootId: 'f1',
          visibleTo: [A, 'team'],
          sharing: 'team',
        }),
      ),
    );
  });

  it('refuses files with no patient, the wrong visibility or a faked owner', async () => {
    await seed('file_folders/f1', folder({ sharing: 'team', visibleTo: [A, 'team'] }));
    const db = as(DOC2);
    // No patient.
    await assertFails(
      setDoc(
        doc(db, 'patient_files/n1'),
        file({ ownerUid: DOC2, visibleTo: [DOC2], patientId: '' }),
      ),
    );
    // Visibility that isn't the folder's.
    await assertFails(
      setDoc(
        doc(db, 'patient_files/n2'),
        file({ ownerUid: DOC2, folderId: 'f1', rootId: 'f1', visibleTo: [DOC2] }),
      ),
    );
    // A loose file shared with the team.
    await assertFails(
      setDoc(
        doc(db, 'patient_files/n3'),
        file({ ownerUid: DOC2, visibleTo: [DOC2, 'team'] }),
      ),
    );
    // In someone else's name.
    await assertFails(
      setDoc(doc(db, 'patient_files/n4'), file({ ownerUid: A, visibleTo: [A] })),
    );
    // Into a private folder that isn't theirs.
    await seed('file_folders/p1', folder({ rootId: 'p1' }));
    await assertFails(
      setDoc(
        doc(db, 'patient_files/n5'),
        file({ ownerUid: DOC2, folderId: 'p1', rootId: 'p1', visibleTo: [A] }),
      ),
    );
  });

  it('lets only the owner, the folder owner or an admin change a shared file', async () => {
    await seed('file_folders/f1', folder({ sharing: 'team', visibleTo: [A, 'team'] }));
    await seed(
      'patient_files/x1',
      file({ ownerUid: DOC2, folderId: 'f1', rootId: 'f1', visibleTo: [A, 'team'] }),
    );
    await assertFails(updateDoc(doc(as(DOC3), 'patient_files/x1'), { name: 'mine now' }));
    await assertSucceeds(updateDoc(doc(as(DOC2), 'patient_files/x1'), { name: 'a.jpg' }));
    await assertSucceeds(updateDoc(doc(doctor(A), 'patient_files/x1'), { name: 'b.jpg' }));
    await assertSucceeds(updateDoc(doc(as(ADMIN2), 'patient_files/x1'), { name: 'c.jpg' }));
    await assertFails(updateDoc(doc(as(DOC2), 'patient_files/x1'), { ownerUid: DOC3 }));
    await assertFails(updateDoc(doc(as(DOC2), 'patient_files/x1'), { doctorId: B }));
  });

  it('lets the folder owner stop sharing, then restamp what is inside', async () => {
    await seed('file_folders/f1', folder({ sharing: 'team', visibleTo: [A, 'team'] }));
    await seed(
      'patient_files/x1',
      file({ ownerUid: DOC2, folderId: 'f1', rootId: 'f1', visibleTo: [A, 'team'] }),
    );
    const db = doctor(A);
    await assertSucceeds(
      updateDoc(doc(db, 'file_folders/f1'), { sharing: 'private', visibleTo: [A] }),
    );
    await assertSucceeds(updateDoc(doc(db, 'patient_files/x1'), { visibleTo: [A] }));
    await assertFails(getDoc(doc(as(DOC2), 'patient_files/x1')));
  });

  it('only shares top-level folders, and never deletes', async () => {
    await seed('file_folders/f1', folder());
    const db = doctor(A);
    // An inner folder that claims its own sharing.
    await assertFails(
      setDoc(
        doc(db, 'file_folders/f2'),
        folder({ parentId: 'f1', rootId: 'f1', visibleTo: [A, 'team'], sharing: 'team' }),
      ),
    );
    await assertSucceeds(
      setDoc(doc(db, 'file_folders/f2'), folder({ parentId: 'f1', rootId: 'f1' })),
    );
    await assertFails(deleteDoc(doc(db, 'file_folders/f1')));
    await seed('patient_files/x1', file());
    await assertFails(deleteDoc(doc(db, 'patient_files/x1')));
    await assertSucceeds(updateDoc(doc(db, 'patient_files/x1'), { isDeleted: true }));
  });
});
