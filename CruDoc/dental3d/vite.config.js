import { defineConfig } from 'vite';

// three's DRACOLoader references its own decoder files through
// `new URL(..., import.meta.url)`, which makes the bundler copy ~1.3 MB of
// decoders we never use (we point setDecoderPath at public/draco instead).
const stripDracoDefaults = {
  name: 'strip-draco-default-urls',
  transform(code, id) {
    if (!/DRACOLoader\.js$/.test(id)) return null;
    return { code: code.replace(/new URL\(\s*'[^']+',\s*import\.meta\.url\s*\)\.toString\(\)/g, "''"), map: null };
  },
};

// Built output goes next to the Flutter assets; all paths are relative so the
// folder can be served from any loopback URL.
export default defineConfig({
  base: './',
  plugins: [stripDracoDefaults],
  build: {
    outDir: '../assets/dental3d',
    emptyOutDir: true,
    chunkSizeWarningLimit: 1500,
    assetsInlineLimit: 0,
  },
  server: { host: '127.0.0.1', port: 5174, strictPort: true },
});
