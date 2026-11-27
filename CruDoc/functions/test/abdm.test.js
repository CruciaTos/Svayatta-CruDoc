const assert = require('assert');
const crypto = require('crypto');

process.env.PATIENT_KEK_PEPPER = 'abdm-test-pepper-secret';

const {encryptForAbdm, seal, open} = require('../lib/abdm/crypto');
const {createAbdmClient} = require('../lib/abdm/client');
const {assertEntitledAccount, handleAbdmAction} = require('../lib/abdm/index');

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
  function docRef(path) {
    return {
      path,
      id: path.split('/').pop(),
      async get() {
        const val = store.get(path);
        return {
          exists: val !== undefined,
          id: path.split('/').pop(),
          data: () => (val === undefined ? undefined : {...val}),
        };
      },
      async set(data) {
        store.set(path, {...data});
      },
      async update(data) {
        const cur = store.get(path) || {};
        store.set(path, {...cur, ...data});
      },
    };
  }
  return {
    store,
    collection(name) {
      return {
        doc(id) {
          return docRef(`${name}/${id}`);
        },
      };
    },
    async runTransaction(fn) {
      let wrote = false;
      const tx = {
        // Real Firestore refuses a read after a write; so must the fake.
        get: (ref) => {
          if (wrote) throw new Error('Transaction read after write');
          return ref.get();
        },
        set: (ref, data) => {
          wrote = true;
          return ref.set(data);
        },
        update: (ref, data) => {
          wrote = true;
          return ref.update(data);
        },
      };
      return fn(tx);
    },
  };
}

function makeFakeFetch(publicKeyPem) {
  let sessionCalls = 0;
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({url, init});
    const makeRes = (status, body) => ({
      ok: status >= 200 && status < 300,
      status,
      headers: {get: () => 'application/json'},
      text: async () => JSON.stringify(body),
      arrayBuffer: async () => Buffer.from(JSON.stringify(body)),
    });
    if (url.endsWith('/gateway/v3/sessions')) {
      sessionCalls++;
      return makeRes(200, {accessToken: 'gw-tok-1', expiresIn: 1800});
    }
    if (url.endsWith('/profile/public/certificate')) {
      return makeRes(200, {
        publicKey: publicKeyPem,
        encryptionAlgorithm: 'RSA/ECB/OAEPWithSHA-1AndMGF1Padding',
      });
    }
    if (url.endsWith('/profile/login/request/otp')) {
      return makeRes(200, {txnId: 'txn-login-1', message: 'OTP sent'});
    }
    if (url.endsWith('/profile/login/verify')) {
      return makeRes(200, {token: 'x-tok-1', accounts: []});
    }
    if (url.endsWith('/profile/account')) {
      return makeRes(200, {
        ABHANumber: '91-1234-5678-9012',
        preferredAbhaAddress: 'rohit@sbx',
        name: 'Rohit Sharma',
        gender: 'M',
        dayOfBirth: '15',
        monthOfBirth: '08',
        yearOfBirth: '1990',
        mobile: '9876543210',
        kycVerified: true,
      });
    }
    return makeRes(404, {message: `Unhandled URL ${url}`});
  };
  fetchImpl.getSessionCalls = () => sessionCalls;
  fetchImpl.calls = calls;
  return fetchImpl;
}

(async () => {
  const {publicKey, privateKey} = crypto.generateKeyPairSync('rsa', {
    modulusLength: 2048,
    publicKeyEncoding: {type: 'spki', format: 'pem'},
    privateKeyEncoding: {type: 'pkcs8', format: 'pem'},
  });

  await test('encrypt/decrypt with generated RSA key pair', async () => {
    const cipher = encryptForAbdm(
      '123456789012',
      publicKey,
      'RSA/ECB/OAEPWithSHA-1AndMGF1Padding',
    );
    const plain = crypto.privateDecrypt(
      {key: privateKey, padding: crypto.constants.RSA_PKCS1_OAEP_PADDING, oaepHash: 'sha1'},
      Buffer.from(cipher, 'base64'),
    ).toString('utf8');
    assert.strictEqual(plain, '123456789012');
  });

  await test('seal/open round trip', async () => {
    const token = 'eyJ.secret.xtoken';
    const sealed = seal(token, 'my-secret');
    assert.notStrictEqual(sealed, token);
    assert.strictEqual(open(sealed, 'my-secret'), token);
  });

  await test('gateway token cached across two calls', async () => {
    const fakeFetch = makeFakeFetch(publicKey);
    const client = createAbdmClient({
      fetchImpl: fakeFetch,
      clientId: 'cid',
      clientSecret: 'csec',
    });
    const t1 = await client.getGatewayToken();
    const t2 = await client.getGatewayToken();
    assert.strictEqual(t1, 'gw-tok-1');
    assert.strictEqual(t2, 'gw-tok-1');
    assert.strictEqual(fakeFetch.getSessionCalls(), 1);
  });

  await test('third resend is refused', async () => {
    const fakeFetch = makeFakeFetch(publicKey);
    const client = createAbdmClient({
      fetchImpl: fakeFetch,
      clientId: 'cid',
      clientSecret: 'csec',
    });
    const db = makeFakeDb();

    // First send
    const r1 = await handleAbdmAction(db, client, 'u1', 'c1', {
      action: 'sendOtp',
      kind: 'aadhaar',
      channel: 'aadhaar',
      identifier: '123456789012',
    });
    assert.strictEqual(r1.resendsLeft, 2);

    // Advance lastAt in fake db to bypass 60s wait for test
    for (const [k, v] of db.store.entries()) {
      if (k.startsWith('abdmOtpLimits/') && !k.includes('user_')) {
        db.store.set(k, {...v, lastAt: Date.now() - 61000});
      }
    }
    const r2 = await handleAbdmAction(db, client, 'u1', 'c1', {
      action: 'sendOtp',
      kind: 'aadhaar',
      channel: 'aadhaar',
      identifier: '123456789012',
      flowId: r1.flowId,
    });
    assert.strictEqual(r2.resendsLeft, 1);

    for (const [k, v] of db.store.entries()) {
      if (k.startsWith('abdmOtpLimits/') && !k.includes('user_')) {
        db.store.set(k, {...v, lastAt: Date.now() - 61000});
      }
    }
    const r3 = await handleAbdmAction(db, client, 'u1', 'c1', {
      action: 'sendOtp',
      kind: 'aadhaar',
      channel: 'aadhaar',
      identifier: '123456789012',
      flowId: r1.flowId,
    });
    assert.strictEqual(r3.resendsLeft, 0);

    for (const [k, v] of db.store.entries()) {
      if (k.startsWith('abdmOtpLimits/') && !k.includes('user_')) {
        db.store.set(k, {...v, lastAt: Date.now() - 61000});
      }
    }
    await assert.rejects(
      () => handleAbdmAction(db, client, 'u1', 'c1', {
        action: 'sendOtp',
        kind: 'aadhaar',
        channel: 'aadhaar',
        identifier: '123456789012',
        flowId: r1.flowId,
      }),
      /Maximum OTP resend attempts reached/,
    );
  });

  await test('second patient cannot take a linked ABHA', async () => {
    const fakeFetch = makeFakeFetch(publicKey);
    const client = createAbdmClient({
      fetchImpl: fakeFetch,
      clientId: 'cid',
      clientSecret: 'csec',
    });
    const db = makeFakeDb();

    const s1 = await handleAbdmAction(db, client, 'u1', 'c1', {
      action: 'sendOtp',
      kind: 'aadhaar',
      channel: 'aadhaar',
      identifier: '999988887777',
    });
    const v1 = await handleAbdmAction(db, client, 'u1', 'c1', {
      action: 'verifyOtp',
      flowId: s1.flowId,
      otp: '123456',
    });
    assert.strictEqual(v1.profile.abhaNumber, '91-1234-5678-9012');

    const link1 = await handleAbdmAction(db, client, 'u1', 'c1', {
      action: 'link',
      flowId: s1.flowId,
      patientId: 'pat-1',
    });
    assert.strictEqual(link1.linked, true);

    const link2 = await handleAbdmAction(db, client, 'u1', 'c1', {
      action: 'link',
      flowId: s1.flowId,
      patientId: 'pat-2',
    });
    assert.strictEqual(link2.linked, false);
    assert.strictEqual(link2.existingPatientId, 'pat-1');
  });

  await test('consent cannot be skipped, and a failed mobile check is refused', async () => {
    const base = makeFakeFetch(publicKey);
    const client = createAbdmClient({
      fetchImpl: async (url, init) => {
        if (url.endsWith('/enrollment/auth/byAbdm')) {
          const body = {authResult: 'failed', message: 'Invalid OTP'};
          return {ok: true, status: 200, text: async () => JSON.stringify(body)};
        }
        return base(url, init);
      },
      clientId: 'cid',
      clientSecret: 'csec',
    });
    const db = makeFakeDb();
    const login = await handleAbdmAction(db, client, 'u1', 'c1', {
      action: 'sendOtp', kind: 'aadhaar', identifier: '111122223333',
    });
    await assert.rejects(
      () => handleAbdmAction(db, client, 'u1', 'c1', {
        action: 'sendOtp', kind: 'create', identifier: '444455556666', flowId: login.flowId,
      }),
      /consent is required/,
    );

    db.store.set('abdmFlows/f1', {
      clinicId: 'c1', uid: 'u1', kind: 'commMobile', txnId: 't', verified: true,
      expiresAt: Date.now() + 60000,
    });
    await assert.rejects(
      () => handleAbdmAction(db, client, 'u1', 'c1', {
        action: 'verifyOtp', flowId: 'f1', otp: '000000',
      }),
      /Invalid OTP/,
    );
  });

  await test('assertEntitledAccount allows active/trial and rejects bare/suspended/deleted', async () => {
    const db = makeFakeDb();
    await assert.rejects(() => assertEntitledAccount(db, 'missing'), /Finish setting up/);

    db.store.set('users/bare', {email: 'a@b.com'});
    await assert.rejects(() => assertEntitledAccount(db, 'bare'), /Finish setting up/);

    db.store.set('users/suspended', {status: 'suspended', isDeleted: false});
    await assert.rejects(() => assertEntitledAccount(db, 'suspended'), /Finish setting up/);

    db.store.set('users/deleted', {status: 'active', isDeleted: true});
    await assert.rejects(() => assertEntitledAccount(db, 'deleted'), /Finish setting up/);

    db.store.set('users/trial', {status: 'trial', isDeleted: false, trialStartedAt: 1});
    await assertEntitledAccount(db, 'trial');

    db.store.set('users/active', {status: 'active', isDeleted: false});
    await assertEntitledAccount(db, 'active');
  });

  await test('searchMobile and searchAddress enforce 30 searches per 30 mins', async () => {
    const base = makeFakeFetch(publicKey);
    const searchFetch = async (url, init) => {
      if (url.endsWith('/phr/web/login/abha/search')) {
        return {
          ok: true,
          status: 200,
          headers: {get: () => 'application/json'},
          text: async () => JSON.stringify({authMethods: ['MOBILE_OTP'], blockedAuthMethods: []}),
        };
      }
      return base(url, init);
    };
    const client = createAbdmClient({fetchImpl: searchFetch, clientId: 'cid', clientSecret: 'csec'});
    const db = makeFakeDb();

    for (let i = 0; i < 30; i++) {
      await handleAbdmAction(db, client, 'u-search', 'c1', {
        action: 'searchAddress',
        abhaAddress: 'test@sbx',
      });
    }
    await assert.rejects(
      () => handleAbdmAction(db, client, 'u-search', 'c1', {
        action: 'searchMobile',
        mobile: '9876543210',
      }),
      /Too many searches/,
    );
  });

  await test('searchMobile returns empty accounts on 404 or not found', async () => {
    const notFoundFetch = async (url) => {
      if (url.endsWith('/gateway/v3/sessions')) {
        return {ok: true, status: 200, headers: {get: () => 'application/json'}, text: async () => JSON.stringify({accessToken: 't', expiresIn: 1800})};
      }
      if (url.endsWith('/profile/public/certificate')) {
        return {ok: true, status: 200, headers: {get: () => 'application/json'}, text: async () => JSON.stringify({publicKey, encryptionAlgorithm: 'RSA/ECB/OAEPWithSHA-1AndMGF1Padding'})};
      }
      return {ok: false, status: 404, headers: {get: () => 'application/json'}, text: async () => JSON.stringify({message: 'ABHA not found'})};
    };
    const client = createAbdmClient({fetchImpl: notFoundFetch, clientId: 'cid', clientSecret: 'csec'});
    const db = makeFakeDb();
    const res = await handleAbdmAction(db, client, 'u1', 'c1', {
      action: 'searchMobile',
      mobile: '9876543210',
    });
    assert.strictEqual(res.flowId, null);
    assert.deepStrictEqual(res.accounts, []);
  });

  console.log(`abdm.test.js: ${passed} passed`);
})();
