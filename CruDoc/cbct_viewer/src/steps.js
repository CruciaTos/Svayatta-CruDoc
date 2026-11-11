// Runs a generator that yields now and then, either all at once (tests, small jobs)
// or in slices of about `budgetMs` with a pause between them, so the page keeps drawing.
// A step is "do a little work, `yield`". The generator's return value is the result.

export function runSync(gen) {
  for (;;) {
    const r = gen.next();
    if (r.done) return r.value;
  }
}

const pause = () => new Promise((resolve) => setTimeout(resolve, 0));

// `cancelled()` (optional): stop early and resolve to undefined.
export async function runAsync(gen, budgetMs = 8, cancelled = null) {
  let t0 = performance.now();
  for (;;) {
    const r = gen.next();
    if (r.done) return r.value;
    if (performance.now() - t0 >= budgetMs) {
      await pause();
      if (cancelled && cancelled()) return undefined;
      t0 = performance.now();
    }
  }
}
