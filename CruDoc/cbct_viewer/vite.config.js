import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';

const shim = (name) => fileURLToPath(new URL(`./src/shims/${name}.js`, import.meta.url));

// Builds the CBCT viewer into Flutter's assets folder (committed, so the app
// builds on a machine without Node). Stable file names, no hashes: Flutter
// lists asset folders one by one, and hashed names would leave stale files.
export default defineConfig({
  base: './',
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
