import { fileURLToPath } from 'node:url';
import { readFileSync, writeFileSync } from 'node:fs';
import { defineConfig } from 'vite';

const shim = (name) => fileURLToPath(new URL(`./src/shims/${name}.js`, import.meta.url));

// Writes assets/cbct_viewer/layout.json from tokens.css so Flutter's poster
// layer can draw the same background and gutters. It runs after Vite empties
// the output folder, so it is regenerated on every build.
function layoutJson() {
  return {
    name: 'cbct-layout-json',
    closeBundle() {
      const css = readFileSync(fileURLToPath(new URL('./src/styles/tokens.css', import.meta.url)), 'utf8');
      const tokens = {};
      for (const [, name, value] of css.matchAll(/--([a-z0-9-]+):\s*([^;]+);/gi)) {
        const v = value.trim();
        tokens[name] = /^-?\d+(\.\d+)?(px|ms)$/.test(v) ? parseFloat(v) : v;
      }
      const out = { version: 1, bg: tokens.bg, background: tokens.bg, tokens };
      writeFileSync(fileURLToPath(new URL('../assets/cbct_viewer/layout.json', import.meta.url)), JSON.stringify(out));
    },
  };
}

// Builds the CBCT viewer into Flutter's assets folder (committed, so the app
// builds on a machine without Node). Stable file names, no hashes: Flutter
// lists asset folders one by one, and hashed names would leave stale files.
export default defineConfig({
  base: './',
  plugins: [layoutJson()],
  resolve: {
    // Node built-ins that vtk.js' xmlbuilder2 needs at module load: Vite's
    // empty stub for "events" crashes the whole bundle at startup.
    alias: [
      { find: /^events$/, replacement: shim('events') },
      { find: /^url$/, replacement: shim('url') },
    ],
  },
  build: {
    outDir: '../assets/cbct_viewer',
    emptyOutDir: true,
    assetsDir: 'a',
    target: 'es2020',
    sourcemap: false,
    // The target WebViews are Chromium/WebKit with native modulepreload; the
    // polyfill is network-capable code the viewer doesn't need.
    modulePreload: { polyfill: false },
    chunkSizeWarningLimit: 4000,
    rollupOptions: {
      output: {
        // One HTML entry, so one entry script. Vite would name it after the
        // HTML file (a/index.js); Flutter and the guide expect a/main.js.
        entryFileNames: 'a/main.js',
        chunkFileNames: 'a/[name].js',
        assetFileNames: (asset) =>
          (asset.names ?? [asset.name]).includes('index.css') ? 'a/main.css' : 'a/[name][extname]',
      },
    },
  },
  worker: {
    format: 'es',
    // Workers are bundled by a separate pipeline that ignores build.rollupOptions.
    rollupOptions: {
      output: {
        entryFileNames: 'a/[name].js',
        chunkFileNames: 'a/[name].js',
        assetFileNames: 'a/[name][extname]',
      },
    },
  },
});
