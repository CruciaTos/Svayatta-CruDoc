const assert = require('node:assert/strict');
const {describe, it, beforeEach} = require('node:test');
const crypto = require('crypto');
const {NestedFakeDb, installNestedFake, Timestamp} = require('./fake-firestore-nested');

// Import compiled or required blobs module
const {
  isBlobReference,
  handleBlobFinalized,
  handlePatientFileWritten,
  cleanupEligibleBlobs,
} = require('../lib/blobs');

describe('Blob references helper', () => {
  it('identifies valid blob references', () => {
    const validSha = 'a'.repeat(64);
    assert.equal(isBlobReference({sha256: validSha}), true);
    assert.equal(isBlobReference({sha256: validSha, isDeleted: false}), true);

    assert.equal(isBlobReference(null), false);
    assert.equal(isBlobReference({}), false);
    assert.equal(isBlobReference({sha256: ''}), false);
    assert.equal(isBlobReference({sha256: 'short'}), false);
    assert.equal(isBlobReference({sha256: 'A'.repeat(64)}), false); // must be lowercase
    assert.equal(isBlobReference({sha256: validSha, isDeleted: true}), false);
  });
});

describe('handleBlobFinalized', () => {
  let db;
  const clinicId = 'c1';
  const content = 'Test file content for SHA-256 matching';
  const matchingSha = crypto.createHash('sha256').update(content).digest('hex');

  beforeEach(async () => {
    db = new NestedFakeDb();
    installNestedFake(db);
    await db.doc(`clinics/${clinicId}`).set({name: 'Clinic 1', storageBytes: 0, storageUsedGB: 0});
  });

  function createFakeBucket(fileContent) {
    let deleted = false;
    return {
      file: (name) => ({
        download: async () => [Buffer.from(fileContent)],
        delete: async () => {
          deleted = true;
        },
      }),
      wasDeleted: () => deleted,
    };
  }

  it('marks blob ready and increments clinic usage when fingerprint matches', async () => {
    const bucket = createFakeBucket(content);
    const result = await handleBlobFinalized(db, bucket, {
      name: `clinic-blobs/${clinicId}/${matchingSha}/original`,
      size: content.length,
      contentType: 'text/plain',
    });

    assert.equal(result.action, 'verified_ready');
    const blobSnap = await db.doc(`clinics/${clinicId}/blobs/${matchingSha}`).get();
    assert.equal(blobSnap.data().state, 'ready');
    assert.equal(blobSnap.data().sizeBytes, content.length);

    const clinicSnap = await db.doc(`clinics/${clinicId}`).get();
    assert.equal(clinicSnap.data().storageBytes, content.length);
  });

  it('deletes object and marks state bad when fingerprint mismatches', async () => {
    const bucket = createFakeBucket('Tampered or corrupted content');
    const result = await handleBlobFinalized(db, bucket, {
      name: `clinic-blobs/${clinicId}/${matchingSha}/original`,
      size: 100,
      contentType: 'text/plain',
    });

    assert.equal(result.action, 'mismatch_deleted');
    assert.equal(bucket.wasDeleted(), true);

    const blobSnap = await db.doc(`clinics/${clinicId}/blobs/${matchingSha}`).get();
    assert.equal(blobSnap.data().state, 'bad');

    // Audit log written
    const logs = await db.collection(`clinics/${clinicId}/access_logs`).get();
    assert.equal(logs.docs.length, 1);
    assert.equal(logs.docs[0].data().action, 'blob.tampered');
  });

  it('sets hasView: true when view arrives', async () => {
    const bucket = createFakeBucket('');
    const result = await handleBlobFinalized(db, bucket, {
      name: `clinic-blobs/${clinicId}/${matchingSha}/view`,
      size: 50,
      contentType: 'image/jpeg',
    });

    assert.equal(result.action, 'view_linked');
    const blobSnap = await db.doc(`clinics/${clinicId}/blobs/${matchingSha}`).get();
    assert.equal(blobSnap.data().hasView, true);
  });
});

describe('handlePatientFileWritten (refs & refCount idempotency)', () => {
  let db;
  const clinicId = 'c1';
  const sha = 'e'.repeat(64);

  beforeEach(async () => {
    db = new NestedFakeDb();
    installNestedFake(db);
    await db.doc(`clinics/${clinicId}`).set({name: 'Clinic 1'});
  });

  it('adds ref doc and increments refCount on new patient file', async () => {
    const after = {
      doctorId: clinicId,
      patientId: 'p1',
      sha256: sha,
      contentType: 'application/pdf',
      isDeleted: false,
    };

    const res = await handlePatientFileWritten(db, 'file-1', undefined, after);
    assert.equal(res.added, true);

    const refDoc = await db.doc(`clinics/${clinicId}/blobs/${sha}/refs/file-1`).get();
    assert.equal(refDoc.exists, true);

    const blobDoc = await db.doc(`clinics/${clinicId}/blobs/${sha}`).get();
    assert.equal(blobDoc.data().refCount, 1);
    assert.equal(blobDoc.data().zeroSince, null);
  });

  it('is idempotent: duplicate write of the same record does not double-count', async () => {
    const after = {
      doctorId: clinicId,
      patientId: 'p1',
      sha256: sha,
      contentType: 'application/pdf',
      isDeleted: false,
    };

    // First run
    await handlePatientFileWritten(db, 'file-1', undefined, after);
    // Duplicate run
    await handlePatientFileWritten(db, 'file-1', undefined, after);

    const blobDoc = await db.doc(`clinics/${clinicId}/blobs/${sha}`).get();
    assert.equal(blobDoc.data().refCount, 1);
  });

  it('decrements refCount and sets zeroSince when file is deleted', async () => {
    const before = {
      doctorId: clinicId,
      patientId: 'p1',
      sha256: sha,
      contentType: 'application/pdf',
      isDeleted: false,
    };
    const after = {
      ...before,
      isDeleted: true,
    };

    // Add ref
    await handlePatientFileWritten(db, 'file-1', undefined, before);
    // Delete file
    const res = await handlePatientFileWritten(db, 'file-1', before, after);
    assert.equal(res.removed, true);

    const refDoc = await db.doc(`clinics/${clinicId}/blobs/${sha}/refs/file-1`).get();
    assert.equal(refDoc.exists, false);

    const blobDoc = await db.doc(`clinics/${clinicId}/blobs/${sha}`).get();
    assert.equal(blobDoc.data().refCount, 0);
    assert.notEqual(blobDoc.data().zeroSince, null);
  });
});

describe('cleanupEligibleBlobs', () => {
  let db;
  const clinicId = 'c1';
  const sha = 'f'.repeat(64);

  beforeEach(async () => {
    db = new NestedFakeDb();
    installNestedFake(db);
    await db.doc(`clinics/${clinicId}`).set({name: 'Clinic 1', storageBytes: 5000, storageUsedGB: 0.005});
  });

  it('cleans up blobs that have been zero-ref longer than grace period', async () => {
    const now = Date.now();
    const tenDaysAgo = now - 10 * 24 * 60 * 60 * 1000;

    await db.doc(`clinics/${clinicId}/blobs/${sha}`).set({
      sizeBytes: 2000,
      state: 'ready',
      refCount: 0,
      zeroSince: Timestamp.fromMillis(tenDaysAgo),
    });

    const deletedFiles = [];
    const fakeBucket = {
      file: (name) => ({
        delete: async () => {
          deletedFiles.push(name);
        },
      }),
    };

    const res = await cleanupEligibleBlobs(db, fakeBucket, {nowMs: now, graceMinutes: 7 * 24 * 60});
    assert.equal(res.purgedCount, 1);
    assert.equal(res.freedBytes, 2000);

    // Blob doc removed
    const blobSnap = await db.doc(`clinics/${clinicId}/blobs/${sha}`).get();
    assert.equal(blobSnap.exists, false);

    // Storage subtracted
    const clinicSnap = await db.doc(`clinics/${clinicId}`).get();
    assert.equal(clinicSnap.data().storageBytes, 3000);

    // Storage bucket files deleted
    assert.ok(deletedFiles.includes(`clinic-blobs/${clinicId}/${sha}/original`));
  });

  it('immediately cleans up zero-ref blob when purgeNow is set', async () => {
    const now = Date.now();
    await db.doc(`clinics/${clinicId}/blobs/${sha}`).set({
      sizeBytes: 1500,
      state: 'ready',
      refCount: 0,
      purgeNow: true,
      zeroSince: Timestamp.fromMillis(now), // 0 seconds ago
    });

    const fakeBucket = {
      file: () => ({delete: async () => {}}),
    };

    const res = await cleanupEligibleBlobs(db, fakeBucket, {nowMs: now, graceMinutes: 7 * 24 * 60});
    assert.equal(res.purgedCount, 1);
    assert.equal(res.freedBytes, 1500);
  });

  it('keeps zero-ref blobs that are within the 7-day grace period', async () => {
    const now = Date.now();
    const twoDaysAgo = now - 2 * 24 * 60 * 60 * 1000;

    await db.doc(`clinics/${clinicId}/blobs/${sha}`).set({
      sizeBytes: 2000,
      state: 'ready',
      refCount: 0,
      zeroSince: Timestamp.fromMillis(twoDaysAgo),
    });

    const fakeBucket = {
      file: () => ({delete: async () => {}}),
    };

    const res = await cleanupEligibleBlobs(db, fakeBucket, {nowMs: now, graceMinutes: 7 * 24 * 60});
    assert.equal(res.purgedCount, 0);

    const blobSnap = await db.doc(`clinics/${clinicId}/blobs/${sha}`).get();
    assert.equal(blobSnap.exists, true);
  });
});
