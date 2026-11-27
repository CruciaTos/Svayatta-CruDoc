const assert = require('assert');
const crypto = require('crypto');
const {FieldValue} = require('firebase-admin/firestore');

process.env.PATIENT_KEK_PEPPER = 'abdm-share-test-pepper';

const {deriveKek, wrapKey, encryptField, decryptField, isEncrypted, phoneIndexOf} = require('../lib/crypto/patientCipher');
const {createAbdmClient} = require('../lib/abdm/client');
const {handleAbdmCallback, processShare} = require('../lib/abdm/share');

let passed = 0;
async function test(name, fn) {
  try {
    await fn();
    passed++;
  } catch (err) {
    console.error(`FAIL  ${name}`);
    console.error(err);
    process.exitCode = 1;
  }
}

function makeFakeDb() {
  const store = new Map();
  let autoId = 1;

  function applyUpdate(cur, data) {
    const next = {...cur};
    for (const [k, v] of Object.entries(data)) {
      if (v && v.constructor && v.constructor.name === 'DeleteTransform') {
        delete next[k];
      } else {
        next[k] = v;
      }
    }
    return next;
  }

  function makeSnap(path, val) {
    return {
      exists: val !== undefined,
      id: path.split('/').pop(),
      ref: docRef(path),
      data: () => (val === undefined ? undefined : {...val}),
    };
  }

  function docRef(path) {
    return {
      path,
      id: path.split('/').pop(),
      async get() {
        return makeSnap(path, store.get(path));
      },
      async create(data) {
        if (store.has(path)) {
          const err = new Error('Document already exists');
          err.code = 6;
          throw err;
        }
        store.set(path, {...data});
      },
      async set(data) {
        store.set(path, {...data});
      },
      async update(data) {
        const cur = store.get(path) || {};
        store.set(path, applyUpdate(cur, data));
      },
    };
  }

  function makeQuery(collName, filters = [], limitN = Infinity) {
    return {
      where(field, op, val) {
        return makeQuery(collName, [...filters, {field, op, val}], limitN);
      },
      limit(n) {
        return makeQuery(collName, filters, n);
      },
      async get() {
        const docs = [];
        for (const [path, val] of store.entries()) {
          if (!path.startsWith(`${collName}/`)) continue;
          const ok = filters.every((f) => f.op === '==' && val[f.field] === f.val);
          if (ok) {
            docs.push(makeSnap(path, val));
            if (docs.length >= limitN) break;
          }
        }
        return {empty: docs.length === 0, docs};
      },
    };
  }

  return {
    store,
    collection(name) {
      return {
        doc(id) {
          const docId = id || `auto_${autoId++}`;
          return docRef(`${name}/${docId}`);
        },
        where(field, op, val) {
          return makeQuery(name, [{field, op, val}]);
        },
      };
    },
    async runTransaction(fn) {
      let wrote = false;
      const tx = {
        get(target) {
          if (wrote) {
            throw new Error('Firestore transaction rule violated: read after write');
          }
          return target.get();
        },
        set(ref, data) {
          wrote = true;
          return ref.set(data);
        },
        update(ref, data) {
          wrote = true;
          return ref.update(data);
        },
      };
      return fn(tx);
    },
  };
}

function makeFakeFetch() {
  const onShareBodies = [];
  const fetchImpl = async (url, init) => {
    const makeRes = (status, body) => ({
      ok: status >= 200 && status < 300,
      status,
      headers: {get: () => 'application/json'},
      text: async () => JSON.stringify(body),
    });
    if (url.endsWith('/gateway/v3/sessions')) {
      return makeRes(200, {accessToken: 'gw-tok-share', expiresIn: 1800});
    }
    if (url.endsWith('/patient-share/v3/on-share')) {
      onShareBodies.push(JSON.parse(init.body));
      return makeRes(202, {status: 'accepted'});
    }
    return makeRes(404, {message: `Unhandled ${url}`});
  };
  fetchImpl.onShareBodies = onShareBodies;
  return fetchImpl;
}

function makeResSpy() {
  const out = {statusCode: null, body: null, ended: false};
  const res = {
    status(code) {
      out.statusCode = code;
      return res;
    },
    json(body) {
      out.body = body;
      out.ended = true;
    },
    end() {
      out.ended = true;
    },
  };
  return {res, out};
}

function validShareBody(overrides = {}) {
  return {
    intent: 'PROFILE_SHARE',
    metaData: {
      hipId: 'HIP-1',
      context: 'OPD1',
      hprId: null,
      ...(overrides.metaData || {}),
    },
    profile: {
      patient: {
        abhaNumber: '91-1234-5678-9012',
        abhaAddress: 'asha.rao@sbx',
        name: 'Asha Rao',
        gender: 'F',
        dayOfBirth: '15',
        monthOfBirth: '8',
        yearOfBirth: '1992',
        phoneNumber: '9876543210',
        ...(overrides.patient || {}),
      },
    },
  };
}

function setupClinicKey(db, clinicId) {
  const dek = crypto.randomBytes(32);
  const kek = deriveKek(clinicId, process.env.PATIENT_KEK_PEPPER);
  db.store.set(`doctor_keys/${clinicId}`, {wrappedKey: wrapKey(dek, kek)});
  return dek;
}

(async () => {
  const CALLBACK_KEY = 'secret-cb-key-123';

  await test('wrong callback key returns 404', async () => {
    const db = makeFakeDb();
    const {res, out} = makeResSpy();
    await handleAbdmCallback(db, CALLBACK_KEY, {
      method: 'POST',
      path: '/wrong-key/api/v3/hip/patient/share',
      headers: {},
      body: {},
    }, res);
    assert.strictEqual(out.statusCode, 404);
  });

  await test('missing bearer token returns 401', async () => {
    const db = makeFakeDb();
    const {res, out} = makeResSpy();
    await handleAbdmCallback(db, CALLBACK_KEY, {
      method: 'POST',
      path: `/${CALLBACK_KEY}/api/v3/hip/patient/share`,
      headers: {},
      body: {},
    }, res);
    assert.strictEqual(out.statusCode, 401);
  });

  await test('unknown facility returns 403', async () => {
    const db = makeFakeDb();
    const {res, out} = makeResSpy();
    await handleAbdmCallback(db, CALLBACK_KEY, {
      method: 'POST',
      path: `/${CALLBACK_KEY}/api/v3/hip/patient/share`,
      headers: {
        authorization: 'Bearer tok',
        'x-hip-id': 'UNKNOWN-HIP',
        'request-id': 'req-1',
      },
      body: validShareBody({metaData: {hipId: 'UNKNOWN-HIP'}}),
    }, res);
    assert.strictEqual(out.statusCode, 403);
  });

  await test('repeated REQUEST-ID creates only one share', async () => {
    const db = makeFakeDb();
    db.store.set('abdmFacilities/HIP-1', {clinicId: 'clinic-1', approved: true});

    for (let i = 0; i < 2; i++) {
      const {res, out} = makeResSpy();
      await handleAbdmCallback(db, CALLBACK_KEY, {
        method: 'POST',
        path: `/${CALLBACK_KEY}/api/v3/hip/patient/share`,
        headers: {
          authorization: 'Bearer tok',
          'x-hip-id': 'HIP-1',
          'request-id': 'req-dup-1',
        },
        body: validShareBody(),
      }, res);
      assert.strictEqual(out.statusCode, 200);
    }
    const shareDocs = [...db.store.keys()].filter((k) => k.startsWith('abdmShares/'));
    assert.strictEqual(shareDocs.length, 1);
  });

  await test('new patient stored encrypted with one token and on-share success', async () => {
    const db = makeFakeDb();
    const dek = setupClinicKey(db, 'clinic-1');
    db.store.set('abdmFacilities/HIP-1', {clinicId: 'clinic-1', approved: true});

    const {res, out} = makeResSpy();
    await handleAbdmCallback(db, CALLBACK_KEY, {
      method: 'POST',
      path: `/${CALLBACK_KEY}/api/v3/hip/patient/share`,
      headers: {
        authorization: 'Bearer tok',
        'x-hip-id': 'HIP-1',
        'request-id': 'req-new-1',
      },
      body: validShareBody(),
    }, res);
    assert.strictEqual(out.statusCode, 200);

    const shareId = [...db.store.keys()].find((k) => k.startsWith('abdmShares/')).split('/')[1];
    const fakeFetch = makeFakeFetch();
    const client = createAbdmClient({fetchImpl: fakeFetch, clientId: 'c', clientSecret: 's'});

    await processShare(db, client, shareId);

    const patients = [...db.store.entries()].filter(([k]) => k.startsWith('patients/'));
    assert.strictEqual(patients.length, 1);
    const pData = patients[0][1];
    assert.ok(isEncrypted(pData.firstName));
    assert.strictEqual(decryptField(pData.firstName, dek), 'Asha');
    assert.strictEqual(decryptField(pData.abhaNumber, dek), '91-1234-5678-9012');
    assert.strictEqual(decryptField(pData.abhaAddress, dek), 'asha.rao@sbx');

    const queueDocs = [...db.store.entries()].filter(([k]) => k.startsWith('walk_in_queue/'));
    assert.strictEqual(queueDocs.length, 1);
    assert.strictEqual(queueDocs[0][1].tokenNumber, 1);
    assert.strictEqual(queueDocs[0][1].status, 'waiting');
    assert.strictEqual(queueDocs[0][1].reason, 'ABHA scan (OPD1)');

    assert.strictEqual(fakeFetch.onShareBodies.length, 1);
    assert.strictEqual(fakeFetch.onShareBodies[0].acknowledgement.status, 'SUCCESS');
    assert.strictEqual(fakeFetch.onShareBodies[0].acknowledgement.profile.tokenNumber, '1');
    assert.strictEqual(fakeFetch.onShareBodies[0].error, undefined);

    const shareAfter = db.store.get(`abdmShares/${shareId}`);
    assert.strictEqual(shareAfter.status, 'done');
    assert.strictEqual(shareAfter.payload, undefined);
  });

  await test('missing birth day leaves dateOfBirth out', async () => {
    const db = makeFakeDb();
    setupClinicKey(db, 'clinic-1');
    db.store.set('abdmFacilities/HIP-1', {clinicId: 'clinic-1', approved: true});

    const {res} = makeResSpy();
    await handleAbdmCallback(db, CALLBACK_KEY, {
      method: 'POST',
      path: `/${CALLBACK_KEY}/api/v3/hip/patient/share`,
      headers: {
        authorization: 'Bearer tok',
        'x-hip-id': 'HIP-1',
        'request-id': 'req-nodob-1',
      },
      body: validShareBody({patient: {dayOfBirth: null, monthOfBirth: null, yearOfBirth: '1990'}}),
    }, res);

    const shareId = [...db.store.keys()].find((k) => k.startsWith('abdmShares/')).split('/')[1];
    const client = createAbdmClient({fetchImpl: makeFakeFetch(), clientId: 'c', clientSecret: 's'});
    await processShare(db, client, shareId);

    const pData = [...db.store.entries()].find(([k]) => k.startsWith('patients/'))[1];
    assert.strictEqual(pData.dateOfBirth, undefined);
  });

  await test('returning patient by number and by address-only reuses record and same-day token', async () => {
    const db = makeFakeDb();
    setupClinicKey(db, 'clinic-1');
    db.store.set('abdmFacilities/HIP-1', {clinicId: 'clinic-1', approved: true});
    const fakeFetch = makeFakeFetch();
    const client = createAbdmClient({fetchImpl: fakeFetch, clientId: 'c', clientSecret: 's'});

    // 1st share creates patient + token 1
    {
      const {res} = makeResSpy();
      await handleAbdmCallback(db, CALLBACK_KEY, {
        method: 'POST',
        path: `/${CALLBACK_KEY}/api/v3/hip/patient/share`,
        headers: {authorization: 'Bearer tok', 'x-hip-id': 'HIP-1', 'request-id': 'req-r1'},
        body: validShareBody(),
      }, res);
      const id = [...db.store.keys()].filter((k) => k.startsWith('abdmShares/')).pop().split('/')[1];
      await processShare(db, client, id);
    }

    // 2nd share by same ABHA number -> reuses patient and token 1
    {
      const {res} = makeResSpy();
      await handleAbdmCallback(db, CALLBACK_KEY, {
        method: 'POST',
        path: `/${CALLBACK_KEY}/api/v3/hip/patient/share`,
        headers: {authorization: 'Bearer tok', 'x-hip-id': 'HIP-1', 'request-id': 'req-r2'},
        body: validShareBody(),
      }, res);
      const id = [...db.store.entries()]
        .find(([k, v]) => k.startsWith('abdmShares/') && v.status === 'received')[0]
        .split('/')[1];
      await processShare(db, client, id);
    }

    // 3rd share by address only (abhaNumber: null) -> reuses patient and token 1
    {
      const {res} = makeResSpy();
      await handleAbdmCallback(db, CALLBACK_KEY, {
        method: 'POST',
        path: `/${CALLBACK_KEY}/api/v3/hip/patient/share`,
        headers: {authorization: 'Bearer tok', 'x-hip-id': 'HIP-1', 'request-id': 'req-r3'},
        body: validShareBody({patient: {abhaNumber: null}}),
      }, res);
      const id = [...db.store.entries()]
        .find(([k, v]) => k.startsWith('abdmShares/') && v.status === 'received')[0]
        .split('/')[1];
      await processShare(db, client, id);
    }

    const patients = [...db.store.keys()].filter((k) => k.startsWith('patients/'));
    const queueDocs = [...db.store.keys()].filter((k) => k.startsWith('walk_in_queue/'));
    assert.strictEqual(patients.length, 1);
    assert.strictEqual(queueDocs.length, 1);
    assert.strictEqual(fakeFetch.onShareBodies[2].acknowledgement.profile.tokenNumber, '1');
  });

  await test('failure reply has error and no acknowledgement', async () => {
    const db = makeFakeDb();
    // No doctor_keys for clinic-1 -> processShare fails
    db.store.set('abdmFacilities/HIP-1', {clinicId: 'clinic-1', approved: true});

    const {res} = makeResSpy();
    await handleAbdmCallback(db, CALLBACK_KEY, {
      method: 'POST',
      path: `/${CALLBACK_KEY}/api/v3/hip/patient/share`,
      headers: {authorization: 'Bearer tok', 'x-hip-id': 'HIP-1', 'request-id': 'req-fail-1'},
      body: validShareBody(),
    }, res);

    const shareId = [...db.store.keys()].find((k) => k.startsWith('abdmShares/')).split('/')[1];
    const fakeFetch = makeFakeFetch();
    const client = createAbdmClient({fetchImpl: fakeFetch, clientId: 'c', clientSecret: 's'});

    await processShare(db, client, shareId);

    assert.strictEqual(fakeFetch.onShareBodies.length, 1);
    assert.ok(fakeFetch.onShareBodies[0].error);
    assert.strictEqual(fakeFetch.onShareBodies[0].acknowledgement, undefined);

    const shareAfter = db.store.get(`abdmShares/${shareId}`);
    assert.strictEqual(shareAfter.status, 'failed');
    assert.strictEqual(shareAfter.payload, undefined);
  });

  await test('failed success reply sets reply_failed and sends no error', async () => {
    const db = makeFakeDb();
    setupClinicKey(db, 'clinic-1');
    db.store.set('abdmFacilities/HIP-1', {clinicId: 'clinic-1', approved: true});

    const {res} = makeResSpy();
    await handleAbdmCallback(db, CALLBACK_KEY, {
      method: 'POST',
      path: `/${CALLBACK_KEY}/api/v3/hip/patient/share`,
      headers: {authorization: 'Bearer tok', 'x-hip-id': 'HIP-1', 'request-id': 'req-replyfail'},
      body: validShareBody(),
    }, res);
    const shareId = [...db.store.keys()].find((k) => k.startsWith('abdmShares/')).split('/')[1];

    const calls = [];
    const failReplyFetch = async (url, init) => {
      if (url.endsWith('/gateway/v3/sessions')) {
        return {ok: true, status: 200, headers: {get: () => 'application/json'}, text: async () => JSON.stringify({accessToken: 't', expiresIn: 1800})};
      }
      if (url.endsWith('/patient-share/v3/on-share')) {
        calls.push(JSON.parse(init.body));
        return {ok: false, status: 500, headers: {get: () => 'application/json'}, text: async () => JSON.stringify({message: 'Gateway down'})};
      }
      return {ok: false, status: 404, headers: {get: () => 'application/json'}, text: async () => '{}'};
    };
    const client = createAbdmClient({fetchImpl: failReplyFetch, clientId: 'c', clientSecret: 's'});

    await processShare(db, client, shareId);
    assert.strictEqual(calls.length, 1);
    assert.ok(calls[0].acknowledgement);
    assert.strictEqual(calls[0].error, undefined);
    assert.strictEqual(db.store.get(`abdmShares/${shareId}`).status, 'reply_failed');
  });

  await test('processing one share twice gives one patient and one reply', async () => {
    const db = makeFakeDb();
    setupClinicKey(db, 'clinic-1');
    db.store.set('abdmFacilities/HIP-1', {clinicId: 'clinic-1', approved: true});

    const {res} = makeResSpy();
    await handleAbdmCallback(db, CALLBACK_KEY, {
      method: 'POST',
      path: `/${CALLBACK_KEY}/api/v3/hip/patient/share`,
      headers: {authorization: 'Bearer tok', 'x-hip-id': 'HIP-1', 'request-id': 'req-twice'},
      body: validShareBody(),
    }, res);
    const shareId = [...db.store.keys()].find((k) => k.startsWith('abdmShares/')).split('/')[1];

    const fakeFetch = makeFakeFetch();
    const client = createAbdmClient({fetchImpl: fakeFetch, clientId: 'c', clientSecret: 's'});
    await processShare(db, client, shareId);
    await processShare(db, client, shareId);

    const patients = [...db.store.keys()].filter((k) => k.startsWith('patients/'));
    assert.strictEqual(patients.length, 1);
    assert.strictEqual(fakeFetch.onShareBodies.length, 1);
  });

  await test('patient born 1 January stored as Asia/Kolkata midnight matches by phone', async () => {
    const db = makeFakeDb();
    const dek = setupClinicKey(db, 'clinic-1');
    db.store.set('abdmFacilities/HIP-1', {clinicId: 'clinic-1', approved: true});

    // 1 Jan 1995 00:00 IST = 31 Dec 1994 18:30 UTC
    const jan1Ist = new Date('1994-12-31T18:30:00.000Z');
    db.store.set('patients/pat-jan1', {
      doctorId: 'clinic-1',
      firstName: encryptField('Asha', dek),
      lastName: encryptField('Rao', dek),
      phone: encryptField('9876543210', dek),
      phoneIndex: phoneIndexOf('9876543210', dek),
      dateOfBirth: jan1Ist,
      abhaNumber: '',
      abhaAddress: '',
      isActive: true,
    });

    const {res} = makeResSpy();
    await handleAbdmCallback(db, CALLBACK_KEY, {
      method: 'POST',
      path: `/${CALLBACK_KEY}/api/v3/hip/patient/share`,
      headers: {authorization: 'Bearer tok', 'x-hip-id': 'HIP-1', 'request-id': 'req-jan1'},
      body: validShareBody({patient: {yearOfBirth: '1995', monthOfBirth: '1', dayOfBirth: '1'}}),
    }, res);
    const shareId = [...db.store.keys()].find((k) => k.startsWith('abdmShares/')).split('/')[1];

    const fakeFetch = makeFakeFetch();
    const client = createAbdmClient({fetchImpl: fakeFetch, clientId: 'c', clientSecret: 's'});
    await processShare(db, client, shareId);

    const patients = [...db.store.keys()].filter((k) => k.startsWith('patients/'));
    assert.strictEqual(patients.length, 1);
    assert.strictEqual(patients[0], 'patients/pat-jan1');
  });

  await test('phone match holding a different ABHA number is not reused', async () => {
    const db = makeFakeDb();
    const dek = setupClinicKey(db, 'clinic-1');
    db.store.set('abdmFacilities/HIP-1', {clinicId: 'clinic-1', approved: true});

    db.store.set('patients/pat-other-abha', {
      doctorId: 'clinic-1',
      firstName: encryptField('Asha', dek),
      lastName: encryptField('Rao', dek),
      phone: encryptField('9876543210', dek),
      phoneIndex: phoneIndexOf('9876543210', dek),
      dateOfBirth: new Date('1992-08-15T00:00:00.000Z'),
      abhaNumber: encryptField('91-9999-8888-7777', dek),
      abhaAddress: encryptField('other@sbx', dek),
      isActive: true,
    });

    const {res} = makeResSpy();
    await handleAbdmCallback(db, CALLBACK_KEY, {
      method: 'POST',
      path: `/${CALLBACK_KEY}/api/v3/hip/patient/share`,
      headers: {authorization: 'Bearer tok', 'x-hip-id': 'HIP-1', 'request-id': 'req-diff-abha'},
      body: validShareBody(),
    }, res);
    const shareId = [...db.store.keys()].find((k) => k.startsWith('abdmShares/')).split('/')[1];

    const fakeFetch = makeFakeFetch();
    const client = createAbdmClient({fetchImpl: fakeFetch, clientId: 'c', clientSecret: 's'});
    await processShare(db, client, shareId);

    const patients = [...db.store.keys()].filter((k) => k.startsWith('patients/'));
    assert.strictEqual(patients.length, 2);
  });

  console.log(`abdm-share.test.js: ${passed} passed`);
})();
