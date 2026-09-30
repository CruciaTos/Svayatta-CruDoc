// Run with the storage emulator up, from CruDoc/:
//   firebase emulators:exec --only storage "npm test --prefix tests/storage-rules"
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, afterEach, before, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { getBytes, ref, updateMetadata, uploadBytes } from 'firebase/storage';

const RULES = fileURLToPath(new URL('../../storage.rules', import.meta.url));
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
    projectId: 'crudoc-storage-rules-test',
    storage: { rules: readFileSync(RULES, 'utf8') },
  });
});

after(async () => {
  await env.cleanup();
});

afterEach(async () => {
  await env.clearStorage();
});

const as = (uid) => env.authenticatedContext(uid).storage();
const anonymous = () => env.unauthenticatedContext().storage();

/** Puts a file in place without going through the rules. */
async function seed(path, contentType = 'application/pdf') {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(ref(ctx.storage(), path), bytes(), { contentType });
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

  it('rejects DICOM and TIFF, which the rules do not list', async () => {
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
