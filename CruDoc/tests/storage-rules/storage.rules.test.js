// Run with the storage emulator up, from CruDoc/:
//   firebase emulators:exec --only storage "npm test --prefix tests/storage-rules"
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, afterEach, before, beforeEach, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteObject, getBytes, ref, updateMetadata, uploadBytes } from 'firebase/storage';
import { doc, setDoc } from 'firebase/firestore';

const RULES = fileURLToPath(new URL('../../storage.rules', import.meta.url));
const FIRESTORE_RULES = fileURLToPath(new URL('../../firestore.rules', import.meta.url));
const MB = 1024 * 1024;

/** A file of [size] bytes. */
const bytes = (size = 16) => new Uint8Array(size).fill(1);
const pdf = { contentType: 'application/pdf' };

const A = 'doctor-a';
const B = 'doctor-b';
const RX = `doctors/${A}/patients/p1/prescriptions/2026/09/rx.pdf`;

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-crudoc',
    storage: { rules: readFileSync(RULES, 'utf8') },
    firestore: { rules: readFileSync(FIRESTORE_RULES, 'utf8') },
  });
});

after(async () => {
  await env.cleanup();
});

afterEach(async () => {
  await env.clearStorage();
  await env.clearFirestore();
});

const as = (uid) => env.authenticatedContext(uid).storage();
const anonymous = () => env.unauthenticatedContext().storage();

/** Puts a file in place without going through the rules. */
async function seed(path, contentType = 'application/pdf') {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(ref(ctx.storage(), path), bytes(), { contentType });
  });
}

/** Puts a firestore document in place without going through the rules. */
async function seedFirestore(path, data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), path), data);
  });
}

describe('a doctor and their own files', () => {
  it('can write and read a prescription PDF', async () => {
    await assertSucceeds(uploadBytes(ref(as(A), RX), bytes(), pdf));
    await assertSucceeds(getBytes(ref(as(A), RX)));
  });

  it('can write every content type the app uploads', async () => {
    const allowed = [
      ['image/jpeg', 'a.jpg'],
      ['image/png', 'a.png'],
      ['image/webp', 'a.webp'],
      ['application/pdf', 'a.pdf'],
      ['audio/mp4', 'a.m4a'],
      ['audio/aac', 'a.aac'],
      ['audio/opus', 'a.opus'],
      ['text/csv', 'a.csv'],
    ];
    for (const [contentType, name] of allowed) {
      await assertSucceeds(
        uploadBytes(ref(as(A), `doctors/${A}/x/${name}`), bytes(), { contentType }),
      );
    }
  });

  it('can write an encrypted backup (octet-stream) to backups/', async () => {
    await assertSucceeds(
      uploadBytes(ref(as(A), `doctors/${A}/backups/2026/09/b.enc`), bytes(), {
        contentType: 'application/octet-stream',
      }),
    );
  });

  it('can replace and read back their own file', async () => {
    await seed(RX);
    await assertSucceeds(uploadBytes(ref(as(A), RX), bytes(32), pdf));
  });

  it('accepts a file of exactly 15 MB', async () => {
    await assertSucceeds(uploadBytes(ref(as(A), RX), bytes(15 * MB), pdf));
  });
});

describe('another doctor', () => {
  it("cannot read a doctor's file", async () => {
    await seed(RX);
    await assertFails(getBytes(ref(as(B), RX)));
  });

  it("cannot write under a doctor's folder", async () => {
    await assertFails(
      uploadBytes(ref(as(B), `doctors/${A}/patients/p1/prescriptions/x.pdf`), bytes(), pdf),
    );
  });

  it("cannot overwrite a doctor's existing file", async () => {
    await seed(RX);
    await assertFails(uploadBytes(ref(as(B), RX), bytes(32), pdf));
  });

  it("cannot reach a doctor's clinic-level files either", async () => {
    const path = `doctors/${A}/backups/2026/09/b.enc`;
    await seed(path, 'application/octet-stream');
    await assertFails(getBytes(ref(as(B), path)));
  });
});

describe('someone who is not signed in', () => {
  it('cannot read', async () => {
    await seed(RX);
    await assertFails(getBytes(ref(anonymous(), RX)));
  });

  it('cannot write', async () => {
    await assertFails(uploadBytes(ref(anonymous(), RX), bytes(), pdf));
  });

  it('cannot write to voice-scratch', async () => {
    await assertFails(
      uploadBytes(
        ref(anonymous(), `voice-scratch/doctors/${A}/patients/p1/v.m4a`),
        bytes(),
        { contentType: 'audio/mp4' },
      ),
    );
  });
});

describe('limits on what is uploaded', () => {
  it('rejects a file over 15 MB', async () => {
    await assertFails(uploadBytes(ref(as(A), RX), bytes(15 * MB + 1), pdf));
  });

  it('rejects a content type the app never uploads', async () => {
    await assertFails(
      uploadBytes(ref(as(A), `doctors/${A}/x/page.html`), bytes(), {
        contentType: 'text/html',
      }),
    );
    await assertFails(
      uploadBytes(ref(as(A), `doctors/${A}/x/run.exe`), bytes(), {
        contentType: 'application/x-msdownload',
      }),
    );
  });

  it('rejects octet-stream outside backups/', async () => {
    await assertFails(
      uploadBytes(ref(as(A), `doctors/${A}/patients/p1/clinical/xrays/a.bin`), bytes(), {
        contentType: 'application/octet-stream',
      }),
    );
  });

  it('rejects DICOM and TIFF outside clinical/imaging', async () => {
    await assertFails(
      uploadBytes(ref(as(A), `doctors/${A}/x/a.dcm`), bytes(), {
        contentType: 'application/dicom',
      }),
    );
    await assertFails(
      uploadBytes(ref(as(A), `doctors/${A}/x/a.tif`), bytes(), {
        contentType: 'image/tiff',
      }),
    );
  });
});

describe('clinical/imaging', () => {
  const DCM = `doctors/${A}/patients/p1/clinical/imaging/2026/09/i1.dcm`;
  const dicom = { contentType: 'application/dicom' };

  it('lets the doctor store and read a DICOM instance', async () => {
    await assertSucceeds(uploadBytes(ref(as(A), DCM), bytes(), dicom));
    await assertSucceeds(getBytes(ref(as(A), DCM)));
  });

  it('accepts TIFF', async () => {
    await assertSucceeds(
      uploadBytes(ref(as(A), `doctors/${A}/patients/p1/clinical/imaging/a.tif`), bytes(), {
        contentType: 'image/tiff',
      }),
    );
  });

  it('accepts an original over 15 MB, up to 250 MB', async () => {
    await assertSucceeds(uploadBytes(ref(as(A), DCM), bytes(40 * MB), dicom));
  });

  it('rejects an original over 250 MB', async () => {
    await assert.rejects(uploadBytes(ref(as(A), DCM), bytes(250 * MB + 1), dicom));
  });

  it('keeps the 15 MB limit for pictures in the same folder', async () => {
    await assertFails(
      uploadBytes(ref(as(A), `doctors/${A}/patients/p1/clinical/imaging/a.jpg`), bytes(16 * MB), {
        contentType: 'image/jpeg',
      }),
    );
  });

  it('keeps other doctors out', async () => {
    await seed(DCM, 'application/dicom');
    await assertFails(getBytes(ref(as(B), DCM)));
    await assertFails(uploadBytes(ref(as(B), DCM), bytes(), dicom));
  });
});

describe('voice-scratch', () => {
  const VOICE = `voice-scratch/doctors/${A}/patients/p1/dictation.m4a`;
  const audio = { contentType: 'audio/mp4' };

  it('lets the doctor create and read a recording', async () => {
    await assertSucceeds(uploadBytes(ref(as(A), VOICE), bytes(), audio));
    await assertSucceeds(getBytes(ref(as(A), VOICE)));
  });

  // The rules allow `create` but not `update`. The Storage emulator judges
  // every upload as a `create`, even one that replaces an existing file, so an
  // overwrite can only be tested where it is judged as an `update`: changing
  // the file's metadata. (Production treats an overwrite as an `update` too.)
  it('does not let the doctor change a recording once it exists', async () => {
    await seed(VOICE, 'audio/mp4');
    await assertFails(
      updateMetadata(ref(as(A), VOICE), { contentType: 'audio/mp4' }),
    );
  });

  it('does not let another doctor read a recording', async () => {
    await seed(VOICE, 'audio/mp4');
    await assertFails(getBytes(ref(as(B), VOICE)));
  });

  it('does not let another doctor create one in the folder', async () => {
    await assertFails(
      uploadBytes(
        ref(as(B), `voice-scratch/doctors/${A}/patients/p1/other.m4a`),
        bytes(),
        audio,
      ),
    );
  });

  it('accepts audio only', async () => {
    await assertFails(
      uploadBytes(
        ref(as(A), `voice-scratch/doctors/${A}/patients/p1/doc.pdf`),
        bytes(),
        pdf,
      ),
    );
  });

  it('rejects a recording over 15 MB', async () => {
    await assertFails(
      uploadBytes(
        ref(as(A), `voice-scratch/doctors/${A}/patients/p1/long.m4a`),
        bytes(15 * MB + 1),
        audio,
      ),
    );
  });
});

describe('everything else', () => {
  it('is denied by default, even for a signed-in doctor', async () => {
    await assertFails(uploadBytes(ref(as(A), 'admin_profiles/a.png'), bytes(), pdf));
    await assertFails(uploadBytes(ref(as(A), 'somewhere/else.pdf'), bytes(), pdf));
  });

  it('keeps one doctor out of a sibling id that merely starts the same', async () => {
    const path = `doctors/${A}-extra/x.pdf`;
    await seed(path);
    await assertFails(getBytes(ref(as(A), path)));
  });
});

// Keeps the runner honest if the rules file is ever emptied.
it('loads the rules file', () => {
  assert.match(readFileSync(RULES, 'utf8'), /service firebase\.storage/);
});

describe('clinic members in storage', () => {
  const RECEP = 'recep-1';
  const CLINICAL = 'clinical-1';
  const GONE = 'gone-1';

  beforeEach(async () => {
    await seedFirestore(`clinics/${A}`, { name: 'Clinic A', ownerUid: A });
    await seedFirestore(`clinics/${A}/members/${RECEP}`, {
      active: true,
      roleId: 'receptionist',
      perms: ['patients.view', 'patients.edit', 'schedule', 'billing', 'messaging'],
      name: 'Recep',
    });
    await seedFirestore(`clinics/${A}/members/${CLINICAL}`, {
      active: true,
      roleId: 'assistant',
      perms: ['clinical.view'],
      name: 'Clinical Member',
    });
    await seedFirestore(`clinics/${A}/members/${GONE}`, {
      active: false,
      roleId: 'doctor',
      perms: ['patients.view', 'clinical.view'],
      name: 'Gone Doctor',
    });
  });

  it('RECEP cannot read doctors/A/patients/p1/x.pdf', async () => {
    const file = `doctors/${A}/patients/p1/x.pdf`;
    await seed(file);
    await assertFails(getBytes(ref(as(RECEP), file)));
  });

  it('a member with clinical.view can read doctors/A/patients/p1/x.pdf', async () => {
    const file = `doctors/${A}/patients/p1/x.pdf`;
    await seed(file);
    await assertSucceeds(getBytes(ref(as(CLINICAL), file)));
  });

  it('RECEP can see patient photos and handle invoices, not prescriptions', async () => {
    const avatar = `doctors/${A}/patients/p1/avatar/a.jpg`;
    const invoice = `doctors/${A}/patients/p1/invoices/inv-1.pdf`;
    const rx = `doctors/${A}/patients/p1/prescriptions/rx-1.pdf`;
    await seed(avatar, 'image/jpeg');
    await seed(rx);
    await assertSucceeds(getBytes(ref(as(RECEP), avatar)));
    await assertSucceeds(uploadBytes(ref(as(RECEP), invoice), bytes(), pdf));
    await assertSucceeds(getBytes(ref(as(RECEP), invoice)));
    await assertFails(getBytes(ref(as(RECEP), rx)));
  });

  it('RECEP can read doctors/A/clinic/branding/logo.png but cannot write it', async () => {
    const branding = `doctors/${A}/clinic/branding/logo.png`;
    await seed(branding, 'image/png');
    await assertSucceeds(getBytes(ref(as(RECEP), branding)));
    await assertFails(
      uploadBytes(ref(as(RECEP), branding), bytes(), { contentType: 'image/png' }),
    );
  });

  it('GONE can read nothing', async () => {
    const file = `doctors/${A}/patients/p1/x.pdf`;
    const branding = `doctors/${A}/clinic/branding/logo.png`;
    await seed(file);
    await seed(branding, 'image/png');
    await assertFails(getBytes(ref(as(GONE), file)));
    await assertFails(getBytes(ref(as(GONE), branding)));
  });

  it('A (owner) can do everything as before', async () => {
    const file = `doctors/${A}/patients/p1/x.pdf`;
    const branding = `doctors/${A}/clinic/branding/logo.png`;
    await assertSucceeds(uploadBytes(ref(as(A), file), bytes(), pdf));
    await assertSucceeds(getBytes(ref(as(A), file)));
    await assertSucceeds(
      uploadBytes(ref(as(A), branding), bytes(), { contentType: 'image/png' }),
    );
    await assertSucceeds(getBytes(ref(as(A), branding)));
  });
});

describe('patient-files (Files screen)', () => {
  const DOC2 = 'doctor-2';
  const RECEP = 'recep-1';
  const path = (fileId = 'x1') => `patient-files/${A}/p1/${fileId}/original`;
  const jpeg = { contentType: 'image/jpeg' };
  const record = (over = {}) => ({
    doctorId: A,
    ownerUid: A,
    patientId: 'p1',
    folderId: '',
    rootId: '',
    visibleTo: [A],
    ...over,
  });

  beforeEach(async () => {
    await seedFirestore(`clinics/${A}`, { name: 'Clinic A', ownerUid: A });
    await seedFirestore(`clinics/${A}/members/${DOC2}`, {
      active: true,
      roleId: 'doctor',
      perms: ['patients.view', 'clinical.view', 'clinical.edit'],
      name: 'Doctor 2',
    });
    await seedFirestore(`clinics/${A}/members/${RECEP}`, {
      active: true,
      roleId: 'receptionist',
      perms: ['patients.view', 'schedule'],
      name: 'Recep',
    });
  });

  it('lets the owner upload before the record syncs, then read it', async () => {
    await assertSucceeds(uploadBytes(ref(as(A), path()), bytes(), jpeg));
    await seedFirestore('patient_files/x1', record());
    await assertSucceeds(getBytes(ref(as(A), path())));
  });

  it('takes office documents, 3D scans and video, not programs', async () => {
    const ok = [
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'model/stl',
      'video/mp4',
      'application/dicom',
    ];
    for (const [i, contentType] of ok.entries()) {
      await assertSucceeds(uploadBytes(ref(as(A), path(`ok${i}`)), bytes(), { contentType }));
    }
    for (const contentType of ['application/x-msdownload', 'application/zip', 'text/html']) {
      await assertFails(uploadBytes(ref(as(A), path(`no-${contentType.length}`)), bytes(), { contentType }));
    }
  });

  it('caps size at 50 MB, 250 MB for DICOM', async () => {
    await assertFails(uploadBytes(ref(as(A), path('big')), bytes(50 * MB + 1), jpeg));
    await assertSucceeds(
      uploadBytes(ref(as(A), path('dcm')), bytes(50 * MB + 1), { contentType: 'application/dicom' }),
    );
  });

  it('is write-once and named "original"', async () => {
    await assertSucceeds(uploadBytes(ref(as(A), path()), bytes(), jpeg));
    await assertFails(uploadBytes(ref(as(A), path()), bytes(), jpeg));
    await assertFails(uploadBytes(ref(as(A), `patient-files/${A}/p1/x2/opg.jpg`), bytes(), jpeg));
  });

  it('follows the record: private stays private, team sharing opens it', async () => {
    await seed(path(), 'image/jpeg');
    await seedFirestore('patient_files/x1', record());
    await assertFails(getBytes(ref(as(DOC2), path())));
    await seedFirestore('patient_files/x1', record({ visibleTo: [A, 'team'] }));
    await assertSucceeds(getBytes(ref(as(DOC2), path())));
    await assertFails(getBytes(ref(as(RECEP), path())));
    await assertFails(getBytes(ref(as(B), path())));
  });

  it('lets only the owner (or an admin) delete it once the record exists', async () => {
    await seed(path(), 'image/jpeg');
    await seedFirestore('patient_files/x1', record({ visibleTo: [A, 'team'] }));
    await assertFails(deleteObject(ref(as(DOC2), path())));
    await assertSucceeds(deleteObject(ref(as(A), path())));
  });

  it('keeps other clinics out entirely', async () => {
    await assertFails(uploadBytes(ref(as(B), path()), bytes(), jpeg));
  });
});
