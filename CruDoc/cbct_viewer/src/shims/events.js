// Node's "events" is not available in the browser. xmlbuilder2 (pulled in by
// vtk.js' XML readers through Cornerstone's Mesh loader) does
// `class XMLBuilderCBImpl extends require('events').EventEmitter` at module
// load, so an empty stub crashes the whole bundle at startup. The viewer never
// reads or writes VTK XML, so a minimal emitter is enough.
export class EventEmitter {
  constructor() {
    this._events = new Map();
  }
  on(name, fn) {
    const list = this._events.get(name) || [];
    list.push(fn);
    this._events.set(name, list);
    return this;
  }
  addListener(name, fn) {
    return this.on(name, fn);
  }
  once(name, fn) {
    const wrap = (...args) => {
      this.off(name, wrap);
      fn.apply(this, args);
    };
    return this.on(name, wrap);
  }
  off(name, fn) {
    const list = this._events.get(name);
    if (list) this._events.set(name, list.filter((f) => f !== fn));
    return this;
  }
  removeListener(name, fn) {
    return this.off(name, fn);
  }
  removeAllListeners(name) {
    if (name === undefined) this._events.clear();
    else this._events.delete(name);
    return this;
  }
  emit(name, ...args) {
    const list = this._events.get(name);
    if (!list || list.length === 0) return false;
    for (const fn of [...list]) fn.apply(this, args);
    return true;
  }
  listenerCount(name) {
    const list = this._events.get(name);
    return list ? list.length : 0;
  }
}
export default EventEmitter;
