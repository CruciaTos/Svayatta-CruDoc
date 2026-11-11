// window.App3DBridge: the contract with the Flutter host (and the test harness).
// Inbound = methods below. Outbound = events sent three ways:
//   flutter_inappwebview handler 'dental3d', parent.postMessage, window 'app3d' CustomEvent.
export function createBridge({ store, actions, registry }) {
  let resolveReady;
  const ready = new Promise((r) => { resolveReady = r; });

  function emit(type, payload) {
    const packet = { type, ts: Date.now(), payload };
    try { window.flutter_inappwebview?.callHandler('dental3d', packet); } catch { /* host not ready */ }
    try { if (window.parent && window.parent !== window) window.parent.postMessage(packet, '*'); } catch { /* ignore */ }
    window.dispatchEvent(new CustomEvent('app3d', { detail: packet }));
  }

  const partPayload = (id) => {
    if (!id) return { nodeId: null, fdi: null, displayName: null, category: null, status: null };
    const part = registry.parts.get(id);
    const t = part.fdi ? store.get().teeth[part.fdi] : null;
    return {
      nodeId: id, fdi: part.fdi ?? null, displayName: part.displayName, category: part.category,
      status: t ? t.status : part.statusFlags?.status ?? 'normal',
    };
  };

  let last = store.get();
  let hoverTimer = 0, hoverPending = false, stateTimer = 0;
  store.subscribe((s, changed) => {
    if (changed.has('selectedId') || (changed.has('teeth') && s.selectedId)) {
      if (last.selectedId !== s.selectedId || changed.has('teeth')) emit('PART_SELECTED', partPayload(s.selectedId));
    }
    if (changed.has('hoveredId') && !hoverTimer) {
      emit('PART_HOVERED', partPayload(s.hoveredId));
      hoverTimer = setTimeout(() => {
        hoverTimer = 0;
        if (hoverPending) { hoverPending = false; emit('PART_HOVERED', partPayload(store.get().hoveredId)); }
      }, 120);
    } else if (changed.has('hoveredId')) hoverPending = true;
    const real = [...changed].some((k) => k !== 'hoveredId');
    if (real && !stateTimer) {
      stateTimer = setTimeout(() => { stateTimer = 0; emit('STATE_UPDATED', { ...store.snapshot(), persist: actions.getPersist() }); }, 80);
    }
    last = s;
  });

  const bridge = {
    ready,
    selectPart: (id) => actions.select(id ?? null, { fly: true }),
    setPartStatus: (id, status, hex) => actions.setPartStatus(id, status, hex),
    setExplode: (f) => actions.setExplode(f),
    setMode: (m) => actions.setMode(m),
    applyStateSnapshot: (s) => actions.applyStateSnapshot(s),
    loadPreset: (n) => actions.loadPreset(n),
    resetCamera: () => actions.resetCamera(),
    setCameraPreset: (n) => actions.setCameraPreset(n),
    setJawOpen: (f) => actions.setJawOpen(f),
    setLayer: (n, b) => actions.setLayer(n, b),
    setGumStyle: (n) => actions.setGumStyle(n),
    setQuality: (q) => actions.setQuality(q),
    getState: () => store.snapshot(),
    getPersist: () => actions.getPersist(),
    emit,
  };
  window.App3DBridge = bridge;
  return { bridge, markReady() { resolveReady(true); emit('READY', { parts: registry.map.size }); } };
}
