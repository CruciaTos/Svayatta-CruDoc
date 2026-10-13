/**
 * A small in-memory stand-in for the Admin SDK's Firestore, enough for the
 * voiceApi tests to run without the emulator (which needs Java 21).
 *
 * Supports: collection/doc/add, get/set(merge)/update/delete, where with
 * == >= < > <= in, orderBy, limit, runTransaction (serial, reads before
 * writes enforced like the real one), and the FieldValue sentinels
 * serverTimestamp, increment, arrayUnion and delete. Not concurrency: two
 * bookings racing is exercised as two in a row, which is what the slot lock
 * has to get right either way.
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

function comparable(v) {
  return v instanceof Timestamp ? v.toMillis() : v;
}

class Snap {
  constructor(ref, data) {
    this.ref = ref;
    this.id = ref.id;
    this.exists = data !== undefined;
    this._data = data;
  }
  data() {
    return this._data === undefined ? undefined : JSON.parse(JSON.stringify(this._data), (k, v) =>
      v && typeof v === 'object' && '_seconds' in v && '_nanoseconds' in v ?
        new Timestamp(v._seconds, v._nanoseconds) : v);
  }
}

class DocRef {
  constructor(db, collection, id) {
    this.db = db;
    this.collectionName = collection;
    this.id = id;
    this.path = `${collection}/${id}`;
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

class Query {
  constructor(db, collection, filters = [], order = null, limitN = null) {
    Object.assign(this, {db, collection, filters, order, limitN});
  }
  where(field, op, value) {
    return new Query(this.db, this.collection, [...this.filters, {field, op, value}], this.order, this.limitN);
  }
  orderBy(field) {
    return new Query(this.db, this.collection, this.filters, field, this.limitN);
  }
  limit(n) {
    return new Query(this.db, this.collection, this.filters, this.order, n);
  }
  async get() {
    let docs = [];
    for (const [path, data] of this.db.store) {
      const [coll, id] = path.split('/');
      if (coll !== this.collection) continue;
      const ok = this.filters.every(({field, op, value}) => {
        const a = comparable(data[field]);
        const b = comparable(value);
        switch (op) {
        case '==': return a === b;
        case '>=': return a !== undefined && a >= b;
        case '>': return a !== undefined && a > b;
        case '<': return a !== undefined && a < b;
        case '<=': return a !== undefined && a <= b;
        case 'in': return value.includes(a);
        default: throw new Error(`fake firestore: op ${op}`);
        }
      });
      if (ok) docs.push(new Snap(new DocRef(this.db, coll, id), data));
    }
    if (this.order) docs.sort((x, y) => comparable(x._data[this.order]) - comparable(y._data[this.order]));
    if (this.limitN !== null) docs = docs.slice(0, this.limitN);
    return {docs, empty: docs.length === 0, size: docs.length};
  }
}

class CollectionRef extends Query {
  constructor(db, name) {
    super(db, name);
  }
  doc(id) {
    return new DocRef(this.db, this.collection, id || `auto${++autoId}`);
  }
  async add(data) {
    const ref = this.doc();
    await ref.set(data);
    return ref;
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

class FakeDb {
  constructor() {
    this.store = new Map();
  }
  write(path, data, merge) {
    this.store.set(path, apply(this.store.get(path), data, merge));
  }
  collection(name) {
    return new CollectionRef(this, name);
  }
  async runTransaction(fn) {
    const tx = new Transaction(this);
    const result = await fn(tx);
    for (const w of tx.writes) w();
    return result;
  }
  /** Test helper: the stored document, or undefined. */
  peek(path) {
    const raw = this.store.get(path);
    return raw === undefined ? undefined : new Snap({id: path.split('/')[1]}, raw).data();
  }
  all(collection) {
    return [...this.store.entries()]
      .filter(([p]) => p.startsWith(`${collection}/`))
      .map(([p]) => ({id: p.split('/')[1], ...this.peek(p)}));
  }
}

/** Makes admin.firestore() return `db`, keeping Timestamp, FieldValue etc. */
function installFakeFirestore(db) {
  const fake = () => db;
  for (const key of ['Timestamp', 'FieldValue', 'FieldPath', 'GeoPoint']) fake[key] = real[key];
  Object.defineProperty(admin, 'firestore', {value: fake, configurable: true, writable: true});
  if (!admin.apps.length) admin.initializeApp({projectId: 'fake-test'});
}

module.exports = {FakeDb, installFakeFirestore, Timestamp};
