/**
 * An in-memory stand-in for the Admin SDK's Firestore that understands
 * subcollections (clinics/{id}/members/{uid}), which test/fake-firestore.js
 * does not. Kept separate so the voice tests' fake is untouched.
 *
 * Supports: collection/doc chains of any depth, auto ids, get, set (with
 * merge), update, delete, where (== != in array-contains), limit, batch,
 * runTransaction (reads before writes), and the FieldValue sentinels
 * serverTimestamp, increment, arrayUnion and delete. Queries see only the
 * direct children of a collection, as Firestore does.
 */
const admin = require('firebase-admin');

const real = admin.firestore;
const {Timestamp} = real;

let autoId = 0;

function sentinel(v) {
  const name = v && typeof v === 'object' ? v.constructor && v.constructor.name : '';
  return ['ServerTimestampTransform', 'NumericIncrementTransform',
    'ArrayUnionTransform', 'DeleteTransform'].includes(name) ? name : null;
}

function isPlainObject(v) {
  return v && typeof v === 'object' && !Array.isArray(v) && !(v instanceof Timestamp) && !sentinel(v);
}

function apply(prev, data, merge) {
  const out = merge && isPlainObject(prev) ? {...prev} : {};
  for (const [k, v] of Object.entries(data)) {
    const kind = sentinel(v);
    if (kind === 'DeleteTransform') delete out[k];
    else if (kind === 'ServerTimestampTransform') out[k] = Timestamp.now();
    else if (kind === 'NumericIncrementTransform') out[k] = (typeof out[k] === 'number' ? out[k] : 0) + v.operand;
    else if (kind === 'ArrayUnionTransform') {
      const arr = Array.isArray(out[k]) ? [...out[k]] : [];
      for (const e of v.elements) if (!arr.some((x) => JSON.stringify(x) === JSON.stringify(e))) arr.push(e);
      out[k] = arr;
    } else if (merge && isPlainObject(v)) out[k] = apply(out[k], v, true);
    else out[k] = isPlainObject(v) ? apply({}, v, false) : v;
  }
  return out;
}

const clone = (v) => (v === undefined ? undefined : JSON.parse(JSON.stringify(v), (k, x) =>
  x && typeof x === 'object' && '_seconds' in x && '_nanoseconds' in x ?
    new Timestamp(x._seconds, x._nanoseconds) : x));

class Snap {
  constructor(ref, data) {
    this.ref = ref;
    this.id = ref.id;
    this.exists = data !== undefined;
    this._data = data;
  }
  data() {
    return clone(this._data);
  }
}

class DocRef {
  constructor(db, path) {
    this.db = db;
    this.path = path;
    this.id = path.split('/').pop();
  }
  collection(name) {
    return new CollectionRef(this.db, `${this.path}/${name}`);
  }
  async get() {
    return new Snap(this, this.db.store.get(this.path));
  }
  async set(data, opts = {}) {
    this.db.write(this.path, data, !!opts.merge);
  }
  async update(data) {
    if (!this.db.store.has(this.path)) throw new Error(`NOT_FOUND: ${this.path}`);
    this.db.write(this.path, data, true);
  }
  async delete() {
    this.db.store.delete(this.path);
  }
}

function matches(data, {field, op, value}) {
  const a = data[field];
  switch (op) {
  case '==': return JSON.stringify(a) === JSON.stringify(value);
  case '!=': return a !== undefined && JSON.stringify(a) !== JSON.stringify(value);
  case 'in': return value.some((v) => JSON.stringify(v) === JSON.stringify(a));
  case 'array-contains': return Array.isArray(a) && a.some((x) => JSON.stringify(x) === JSON.stringify(value));
  default: throw new Error(`fake firestore: op ${op}`);
  }
}

class Query {
  constructor(db, path, filters = [], limitN = null) {
    Object.assign(this, {db, path, filters, limitN});
  }
  where(field, op, value) {
    return new Query(this.db, this.path, [...this.filters, {field, op, value}], this.limitN);
  }
  orderBy() {
    return this;
  }
  limit(n) {
    return new Query(this.db, this.path, this.filters, n);
  }
  async get() {
    const depth = this.path.split('/').length + 1;
    let docs = [];
    for (const [p, data] of this.db.store) {
      if (!p.startsWith(`${this.path}/`) || p.split('/').length !== depth) continue;
      if (this.filters.every((f) => matches(data, f))) docs.push(new Snap(new DocRef(this.db, p), data));
    }
    if (this.limitN !== null) docs = docs.slice(0, this.limitN);
    return {docs, empty: docs.length === 0, size: docs.length};
  }
}

class CollectionRef extends Query {
  constructor(db, path) {
    super(db, path);
    this.id = path.split('/').pop();
  }
  doc(id) {
    return new DocRef(this.db, `${this.path}/${id || `auto${++autoId}`}`);
  }
  async add(data) {
    const ref = this.doc();
    await ref.set(data);
    return ref;
  }
}

class Batch {
  constructor(db) {
    this.db = db;
    this.ops = [];
  }
  set(ref, data, opts = {}) {
    this.ops.push(() => this.db.write(ref.path, data, !!opts.merge));
    return this;
  }
  update(ref, data) {
    this.ops.push(() => {
      if (!this.db.store.has(ref.path)) throw new Error(`NOT_FOUND: ${ref.path}`);
      this.db.write(ref.path, data, true);
    });
    return this;
  }
  delete(ref) {
    this.ops.push(() => this.db.store.delete(ref.path));
    return this;
  }
  // Like the real WriteBatch, which the code under test detects by `create`.
  create(ref, data) {
    this.ops.push(() => this.db.write(ref.path, data, false));
    return this;
  }
  async commit() {
    if (this.db.failNextCommit) {
      this.db.failNextCommit = false;
      throw new Error('fake firestore: commit failed (injected)');
    }
    this.db.commits += 1;
    for (const op of this.ops) op();
  }
}

class Transaction {
  constructor(db) {
    this.db = db;
    this.writes = [];
  }
  async get(refOrQuery) {
    if (this.writes.length) throw new Error('Firestore transactions require all reads to be executed before all writes.');
    return refOrQuery.get();
  }
  set(ref, data, opts = {}) {
    this.writes.push(() => this.db.write(ref.path, data, !!opts.merge));
  }
  update(ref, data) {
    this.writes.push(() => {
      if (!this.db.store.has(ref.path)) throw new Error(`NOT_FOUND: ${ref.path}`);
      this.db.write(ref.path, data, true);
    });
  }
  delete(ref) {
    this.writes.push(() => this.db.store.delete(ref.path));
  }
}

class NestedFakeDb {
  constructor() {
    this.store = new Map();
    this.commits = 0;
  }
  write(path, data, merge) {
    this.store.set(path, apply(this.store.get(path), data, merge));
  }
  collection(name) {
    return new CollectionRef(this, name);
  }
  doc(path) {
    return new DocRef(this, path);
  }
  batch() {
    return new Batch(this);
  }
  async runTransaction(fn) {
    const tx = new Transaction(this);
    const result = await fn(tx);
    for (const w of tx.writes) w();
    return result;
  }
  /** Test helpers. */
  seed(path, data) {
    this.store.set(path, apply(undefined, data, false));
  }
  peek(path) {
    return clone(this.store.get(path));
  }
  /** Every document directly in [collectionPath]. */
  all(collectionPath) {
    const depth = collectionPath.split('/').length + 1;
    return [...this.store.entries()]
      .filter(([p]) => p.startsWith(`${collectionPath}/`) && p.split('/').length === depth)
      .map(([p, d]) => ({id: p.split('/').pop(), ...clone(d)}));
  }
}

/**
 * The handful of Admin SDK auth calls the clinic code makes: look users up,
 * create and delete them, and set custom claims. Errors carry the same
 * `auth/user-not-found` code the real SDK uses.
 */
class FakeAuth {
  constructor() {
    this.reset();
  }
  reset() {
    this.users = new Map();
  }
  notFound() {
    const e = new Error('There is no user record corresponding to the provided identifier.');
    e.code = 'auth/user-not-found';
    return e;
  }
  seedUser(user) {
    this.users.set(user.uid, {customClaims: {}, ...user});
  }
  find(pred) {
    for (const u of this.users.values()) if (pred(u)) return {...u};
    return null;
  }
  async getUser(uid) {
    const u = this.users.get(uid);
    if (!u) throw this.notFound();
    return {...u};
  }
  async getUserByEmail(email) {
    return this.find((u) => u.email === email) || Promise.reject(this.notFound());
  }
  async getUserByPhoneNumber(phoneNumber) {
    return this.find((u) => u.phoneNumber === phoneNumber) || Promise.reject(this.notFound());
  }
  async createUser(props) {
    const uid = `user${++autoId}`;
    this.users.set(uid, {uid, customClaims: {}, ...props});
    return {...this.users.get(uid)};
  }
  async deleteUser(uid) {
    if (!this.users.delete(uid)) throw this.notFound();
  }
  async setCustomUserClaims(uid, claims) {
    const u = this.users.get(uid);
    if (!u) throw this.notFound();
    u.customClaims = {...claims};
  }
  async revokeRefreshTokens() {}
}

/** Makes admin.auth() return `auth`. */
function installFakeAuth(auth) {
  Object.defineProperty(admin, 'auth', {value: () => auth, configurable: true, writable: true});
}

/** Makes admin.firestore() return `db`, keeping Timestamp, FieldValue etc. */
function installNestedFake(db) {
  const fake = () => db;
  for (const key of ['Timestamp', 'FieldValue', 'FieldPath', 'GeoPoint']) fake[key] = real[key];
  Object.defineProperty(admin, 'firestore', {value: fake, configurable: true, writable: true});
  if (!admin.apps.length) admin.initializeApp({projectId: 'fake-test'});
}

module.exports = {NestedFakeDb, installNestedFake, FakeAuth, installFakeAuth, Timestamp};
