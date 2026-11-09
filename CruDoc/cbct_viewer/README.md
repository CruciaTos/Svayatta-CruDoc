# CruDoc CBCT viewer

The four-panel CBCT viewer (Axial, 3D, Coronal, Sagittal) that CruDoc shows in a
WebView on Windows PCs and tablets. Vite + Cornerstone3D, fully offline.

The whole brief and the step-by-step plan live in
`handoff/cbct_3d_viewer_build_guide.md`; the look to match is
`handoff/cbct_reference.png`.

## Commands

```powershell
cd cbct_viewer
npm ci            # install the exact versions in package-lock.json
npm run dev       # dev server (open /dev/dev.html once Step 3 exists)
npm run build     # writes ../assets/cbct_viewer (Flutter bundles it)
npm run shot -- 4 # screenshot for step 4 (script arrives in Step 3)
```

Or, from the project root: `powershell -File tool\build_cbct_viewer.ps1`
(runs `npm ci` + `npm run build` and lists the output).

**The build output in `assets/cbct_viewer/` is committed**, so the Flutter app
builds on a machine without Node. Rebuild it after every change to this folder.

## Rules

- **Offline.** No CDN, no web fonts, no analytics, no network calls except to the
  app's own loopback server. `index.html` carries a Content-Security-Policy
  (`connect-src 'self'`) that enforces it. Fonts live in `public/fonts/`.
- **No real patient scans** in code, tests, logs, screenshots or git. Tests use
  the synthetic jaw phantom (patient `TEST^PHANTOM`).
- **Exact versions.** Dependencies are pinned without `^`. Cornerstone `core`
  and `tools` share one version, and `@kitware/vtk.js` is the version Cornerstone
  depends on (`npm ls @kitware/vtk.js` must show a single copy).
- **No DICOM parsing here.** The app sends raw voxels, so there is no
  `dicom-image-loader`, `dicom-parser` or codec.
- **Stable output names**, no hashes (`a/main.js`), because Flutter lists asset
  folders and hashes would leave stale files.
