# Antigravity tasks: progressive radiology image loading

You are building one feature in this codebase. This whole file is your brief.
Claude (the lead) reviews your work between steps and updates this file.

## ▶ DO NOW

**Coding is complete. Don't change any files.** The remaining steps are deploy
and testing, done by Soham or Claude (see "Deploy checklist").

---

## Rules

> Project: `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\CruDoc` — Flutter app on
> Firebase (project `svayatta-crudoc-dev`, region `asia-south1`). Shared widgets
> live in `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\crudoc_shared`.
> Follow the "Design" and "Gate decisions" sections below exactly.
> Rules:
> - Change ONLY the files the task names (you may create the new files it names).
>   Do not reformat or "improve" other code.
> - Never deploy (`firebase deploy`, `gcloud run deploy`), never `git commit`/`push`.
> - Never put real patient files, names or IDs in code, tests, logs or git.
>   Tests use synthetic images made with numpy or Dart.
> - Dart UI: read `CruDoc/.claude/rules/crudoc-ui.md` and follow it
>   (`context.cru` colours, `CruSpace`, `CruRadius`, `CruType`; no hard-coded colours/sizes).
> - Run only the test files the task names. Never run the whole `flutter test`
>   suite (parallel runs crash on sqlite3.dll).
> - If something in the task doesn't match the code you find, STOP and report
>   what you found instead of guessing.
> - When done, list every file you changed and paste the output of the Check.

---

## Design

**Goal.** A radiology image (RVG, OPG, ceph) opens fast at half resolution,
then upgrades to full quality by downloading only the missing bytes.
The original DICOM is never changed.

**Three copies of each image in Cloud Storage**
- Original DICOM (exists today):
  `doctors/{doctorId}/patients/{patientId}/clinical/imaging/{year}/{month}/{uuid}.dcm`
  (see `_uploadDated` in `lib/core/services/medical_storage_service.dart`)
- Thumbnail JPEG (exists today, `RadImageRef.previewPath`).
- NEW viewing file, one per frame:
  `doctors/{doctorId}/patients/{patientId}/clinical/imaging-view/{viewId}/frame_{n}.j2c`
  where `viewId` = lowercase hex SHA-256 of the original's storage path string.

**The viewing file** is a lossless JPEG 2000 codestream (HTJ2K or classic
J2K — decided in Task 1) written with:
- reversible (lossless) wavelet, 5 decomposition levels,
- progression order **RPCL**,
- **one tile-part per resolution level** (tile-parts split by "R"),
- a single tile (no tiling), single component (grayscale).

So the file is: main header, then tile-part 0 (lowest resolution) … tile-part 5
(full resolution), then the end marker `FF D9`.
- `previewEnd` = byte offset where the LAST tile-part starts.
- Preview = bytes `[0, previewEnd)` + `FF D9`, decoded with `reduce = 1`
  → half width × half height.
- Full = the whole file, decoded with `reduce = 0` → identical pixels to the original.
- Upgrading downloads only bytes `[previewEnd, total)` and appends them.

**Firestore doc** `radiology_views/{viewId}` (written ONLY by the server; clients
cannot read it — the default-deny rule already blocks it):
```
doctorId: string            // from the path
patientId: string           // from the path
sourcePath: string          // original's storage path
sourceGeneration: string    // Cloud Storage generation of the original
status: 'pending' | 'ready' | 'failed' | 'skipped'
reason: string              // why failed/skipped, '' when ready
codec: 'htj2k' | 'j2k'
width: int, height: int, frames: int
bitsStored: int, signed: bool
slope: number, intercept: number      // DICOM rescale, default 1 / 0
windowCenter: number|null, windowWidth: number|null
photometric: 'MONOCHROME1' | 'MONOCHROME2'
frameFiles: [ { path: string, total: int, previewEnd: int, sha256: string } ]
updatedAt: server timestamp
```
No patient name or DICOM header is copied anywhere. The `.j2c` holds pixels only.

**Who does what**
- Cloud Run service `imaging-view` (Python, folder `CruDoc/imaging-service/`):
  runs when an original is uploaded; builds the viewing files and the doc.
  When an original is deleted, deletes its viewing files and doc.
- Callable Cloud Function `getImagingView` (TypeScript, `CruDoc/functions/src/imaging.ts`):
  checks the doctor owns the image, returns **10-minute signed URLs** plus the
  metadata, and writes an `access_logs` entry with action `image.view`.
- Flutter plugin `crudoc_j2k` (`CruDoc/packages/crudoc_j2k/`): decodes the
  codestream with OpenJPEG through `dart:ffi`. **Android and Windows only** for
  now; other platforms fall back to downloading the original as today.
- App: downloads with HTTP Range requests into
  `{studyDir}/.views/{imageId}/frame_{n}.j2c` (+ `frame_{n}.json` sidecar),
  decodes, shows the preview **upscaled to full width/height** so annotations,
  measurements, zoom and pan keep the same coordinates, then swaps to full quality.

**When full quality loads**
- Always, if the setting "Always open scans at full quality" is on
  (default ON on Windows/macOS, OFF on Android/iOS).
- When the doctor picks a measuring tool (length, angle, area, ellipse, rectangle,
  path, calibrate).
- When zoom shows more than 0.5 screen pixel per image pixel (the preview has
  only half the pixels, so beyond that it looks soft).
- Before a key image is captured for a report.
- When the doctor taps "Full quality" on the "Preview" badge.

**Fallbacks (always safe)**: feature flag off, web, unsupported platform, view not
ready, any download/decode error, or checksum mismatch → the old path (download the
original with `RadCloudFetch`, decode with `loadRadPixels`).

**Feature flag**: Remote Config bool `rad_progressive_view`, default `false`.

**Not in scope now**: CBCT (no 3D viewer yet), web, iOS/macOS decoder, the 1 GB
local storage cap (separate project; later it will trim `.views` files back to
`previewEnd` instead of deleting them).

---

## Gate decisions (Claude)

- **Task 0:** no Docker; everything local runs in WSL (see "Done: Tasks 0–1").
- **Tasks 2–4:** approved (Task 3b fixed the path pattern and added generation checks).
- **Task 5:** decoder works (tests pass). The `nuget.exe` Antigravity downloaded is
  Microsoft-signed (checked). Android already works: Claude confirmed the debug APK
  contains `libcrudoc_j2k.so` for arm64-v8a, armeabi-v7a and x86_64. Task 5b fixes
  the Windows install step; it rebuilds the APK only to prove the CMake change
  didn't break Android.
- **Task 1:** **GO. Codec = `htj2k` (codec A, OpenJPH encode, OpenJPEG decode).**
  It's about 4% bigger than classic J2K but decodes about 3.7× faster
  (chest X-ray 184 ms vs 793 ms), which matters on phones. Every sample was
  lossless; the preview averages 27% of the bytes.
  - `ojph_compress` input file must end in `.raw` (little-endian; it rejects `.rawl`).
    Use exactly the flags in `spike/out/report.md`.
  - The preview has the same value range as the full image (no rescale needed).
  - Use fixture `synthetic_a.j2c` with `previewEnd_a` wherever a task says
    "the codec chosen at the gate". Never delete `packages/crudoc_j2k/test/fixtures/`
    (Task 5's `flutter create` must keep it).
  - An already-compressed original can be smaller than its viewing file
    (`pydicom:JPEG2000.dcm`). That's fine; build the viewing file anyway.

---

## Done: Tasks 0–1 (environment + codec test)

- Docker isn't used. Python tools run in WSL Ubuntu 24.04 with a venv at
  `~/.venvs/imaging-view`; OpenJPH and OpenJPEG are already installed by
  `imaging-service/install_tools.sh` (the Dockerfile reuses it for deploy).
- Run anything in the service from PowerShell like this:
  ```powershell
  wsl -e bash -lc "cd /mnt/c/Soham/Kamachya_Goshti/Svayatta_CruDoc/CruDoc/imaging-service && ~/.venvs/imaging-view/bin/python <script or -m pytest ...>"
  ```
- Codec flags, sample files and timings: `imaging-service/spike/out/report.md`.
- Test fixtures: `packages/crudoc_j2k/test/fixtures/`.

---

## Done: Tasks 2–3 (conversion + Cloud Run handler)

- `imaging-service/convert.py`: `tilepart_ends`, `encode_frame`, `decode_full`,
  `build_view` (skips colour / no-pixels / too-many-frames / too-large; verifies
  every frame is lossless and has 6 tile-parts).
- `imaging-service/main.py`: `on_storage_event` → `process_finalized` /
  `process_deleted`; writes `radiology_views/{viewId}`.
- Tests in `imaging-service/tests/`; deploy notes in `imaging-service/README.md`.

---

## Done: Tasks 3b–4 (review fixes + callable)

- `main.py` path pattern now matches `clinical/imaging/{year}/{month}/{uuid}.dcm`;
  generation checks stop stale writes and wrong deletes; clients are reused.
- `functions/src/imaging.ts`: `getImagingView({storagePath})` → `{status, codec, width,
  height, frames, bitsStored, signed, slope, intercept, windowCenter, windowWidth,
  photometric, frameFiles: [{url, total, previewEnd, sha256}]}`; `status` is
  `ready | pending | failed | skipped | missing`. URLs last 10 minutes. Exported from `index.ts`.

---

## Done: Task 5 (decoder plugin, mostly)

- `packages/crudoc_j2k/`: `src/crudoc_j2k.c` (OpenJPEG decode from memory, strict
  mode off), `src/CMakeLists.txt`, `lib/crudoc_j2k.dart` with `J2kImage`,
  `J2kDecodeException`, `j2kSupported`, `decodeJ2k(bytes, {reduce})`;
  env override `CRUDOC_J2K_LIB` for tests. Both plugin tests pass.
- Added to `CruDoc/pubspec.yaml` as a path dependency.
- Still open → Task 5b: Windows install step fails, APK build not confirmed.

---

## Done: Task 5b (CMake fix)

- `packages/crudoc_j2k/src/CMakeLists.txt` adds OpenJPEG with `EXCLUDE_FROM_ALL` (no
  install-rule clash) and clears OpenJPEG's cached output paths. Windows bundles
  `crudoc_j2k.dll` next to the app exe; the APK carries `libcrudoc_j2k.so` per ABI.

---

## Done: Tasks 6–8 (fetch, decode, setting, flag)

Use these exact names in Task 9:
- `lib/features/radiology/data/radiology_view_fetch.dart`: `RadViewInfo` (`ready`,
  `width`, `height`, `frames`, `slope`, `intercept`, `windowCenter`, `windowWidth`,
  `photometric`, frame list), `RadViewFetch.instance.info(storagePath)` →
  `RadViewInfo?`, `RadViewFetch.instance.ensure(studyDir:, imageId:, storagePath:,
  frame:, full:)` → `File`.
- `lib/features/radiology/imaging/rad_view_pixels.dart`:
  `loadRadViewPixels(file, info, frame:, full:, pixelSpacingMm:)` → `RadPixels`
  (preview already upscaled to full size).
- `lib/features/radiology/imaging/rad_pixels.dart`: `RadPixels.isPreview`,
  `radPixelsWithStats(...)`.
- `lib/features/radiology/viewer/viewer_prefs.dart`: `RadViewerPrefs.fullQuality`,
  `RadViewerPrefs.fullQualityKey` (`'v2d.fullQuality'`), `defaultFullQuality()`.
- `lib/features/radiology/data/rad_progressive_flag.dart`: `radProgressiveViewEnabled()`.
- Viewer prefs are saved with `radiologyProvider`'s `saveViewerPrefs(Map)` into
  `RadSettings.viewer`; `viewer_screen.dart` reads them once when it opens.

---

## Done: Tasks 8b–9 (setting + viewer wiring)

- Radiology settings → Work card has "Always open scans at full quality".
- `--dart-define=RAD_PROGRESSIVE=true` forces the feature on for testing.
- `radiologyProvider.pixelsOf(...)` picks the viewing file or falls back to the original;
  `viewer_screen.dart` upgrades on measuring tools, zoom > 0.5, key-image capture and the
  Preview pill's "Full quality" button. Fallback verified with the backend not deployed.

---

## Done: Tasks 10–11 (backfill + JPEG 2000 import)

- `imaging-service/backfill.py --doctor <uid> [--run]` (dry run by default);
  `process_finalized` now returns `'ready' | 'skipped' | 'failed'`.
- `DicomFile.encapsulatedFrame(frame)`; `rad_pixels.dart` `_fromDicom` decodes
  JPEG 2000 / HTJ2K DICOMs with `decodeJ2k` on Android/Windows.

---

## Done: Task 12 (final review fixes)

- Short downloads now throw (never shown as full quality); per-file download queue
  survives errors; undecodable JPEG 2000 DICOMs show the normal message; no duplicate
  reload; Preview pill uses `RadInk.overlayBorder`. 5 tests pass, analyzer clean.

---

## Deploy checklist (Soham or Claude — not Antigravity)

**Status 2026-10-04 (Claude):** steps 1–4 done. Bucket and Firestore are in
ASIA-SOUTH1. APIs are on and IAM is granted. `imaging-view` is live and both
triggers are active. Smoke test passed: the upload produced a ready doc that
matches the spike byte for byte, and the delete removed the view and the doc.
Step 5 was deployed but the callable is **blocked (HTTP 403)**: the org's
domain-restricted sharing policy forbids `allUsers`, which affects every v2
callable in this project. Soham must choose the fix: either
`gcloud run services update <svc> --no-invoker-iam-check` per callable (each
already checks Firebase auth in code), or an org-policy exception for this
project. Steps 7–8 wait on that.

PowerShell, one line per command. First add gcloud to
PATH (`%LOCALAPPDATA%\Google\Cloud SDK\google-cloud-sdk\bin`) and log in:
`gcloud auth login`.

**1. Variables**
```powershell
$P = "svayatta-crudoc-dev"
$B = "svayatta-crudoc-dev.firebasestorage.app"
$N = gcloud projects describe $P --format="value(projectNumber)"
$SA = "$N-compute@developer.gserviceaccount.com"
$GCS = gcloud storage service-agent --project $P
```
(Confirm `$B` with `gcloud storage buckets list --project $P`.)

**2. Data stays in India — must print `ASIA-SOUTH1`, otherwise stop and ask Claude**
```powershell
gcloud storage buckets describe gs://$B --format="value(location)"
```

**3. APIs and permissions (once)**
```powershell
gcloud services enable run.googleapis.com eventarc.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com pubsub.googleapis.com --project $P
gcloud projects add-iam-policy-binding $P --member="serviceAccount:$GCS" --role="roles/pubsub.publisher"
foreach ($r in "roles/eventarc.eventReceiver","roles/run.invoker","roles/datastore.user","roles/storage.objectAdmin") { gcloud projects add-iam-policy-binding $P --member="serviceAccount:$SA" --role=$r }
gcloud iam service-accounts add-iam-policy-binding $SA --member="serviceAccount:$SA" --role="roles/iam.serviceAccountTokenCreator" --project $P
```

**4. Conversion service + triggers** (from `CruDoc\imaging-service`; Cloud Build builds the Dockerfile)
```powershell
gcloud run deploy imaging-view --source . --region asia-south1 --project $P --no-allow-unauthenticated --memory 4Gi --cpu 2 --timeout 900 --concurrency 1 --max-instances 5 --set-env-vars VIEW_CODEC=htj2k
gcloud eventarc triggers create imaging-view-finalized --location asia-south1 --project $P --destination-run-service imaging-view --destination-run-region asia-south1 --event-filters "type=google.cloud.storage.object.v1.finalized" --event-filters "bucket=$B" --service-account $SA
gcloud eventarc triggers create imaging-view-deleted --location asia-south1 --project $P --destination-run-service imaging-view --destination-run-region asia-south1 --event-filters "type=google.cloud.storage.object.v1.deleted" --event-filters "bucket=$B" --service-account $SA
```

**5. Callable function** (from `CruDoc`)
```powershell
firebase deploy --only functions:getImagingView --project $P
```

**6. Smoke test with the public sample** (replace `<UID>` with your Firebase uid)
```powershell
gcloud storage cp imaging-service\spike\samples\chest_pa.dcm "gs://$B/doctors/<UID>/patients/smoketest/clinical/imaging/2026/10/smoke.dcm" --content-type=application/dicom
gcloud run services logs read imaging-view --region asia-south1 --project $P --limit 20
```
Expect `status=ready`. Then remove it and expect `status=deleted`:
`gcloud storage rm "gs://$B/doctors/<UID>/patients/smoketest/clinical/imaging/2026/10/smoke.dcm"`

**7. Backfill existing scans** (dry run first; bring the counts to Claude before `--run`)
```powershell
gcloud auth application-default login
wsl -e bash -lc "cd /mnt/c/Soham/Kamachya_Goshti/Svayatta_CruDoc/CruDoc/imaging-service && GOOGLE_APPLICATION_CREDENTIALS=/mnt/c/Users/Soham/AppData/Roaming/gcloud/application_default_credentials.json GOOGLE_CLOUD_PROJECT=svayatta-crudoc-dev ~/.venvs/imaging-view/bin/python backfill.py --doctor <UID>"
```

**8. End-to-end test** (Remote Config flag stays OFF; use the build switch)
- Build with `--dart-define=RAD_PROGRESSIVE=true` for Windows and the Pixel.
- Setting "Always open scans at full quality" OFF. Import a study on the Pixel,
  open it on Windows (so the original isn't local there): the Preview pill shows;
  the Length tool switches to full quality without the image jumping.
- Note the `[rad] Preview/Full decoded in … ms` lines on both devices.
- Only then turn on Remote Config `rad_progressive_view` for everyone.
