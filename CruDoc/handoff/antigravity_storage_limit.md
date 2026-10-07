# Antigravity tasks: storage limit and storage breakdown

You are building one feature in this codebase. This whole file is your brief.
Claude (the lead) reviews your work between steps and updates this file.

## ▶ DO NOW

**Do Task S1, S2 and S3, in that order.** Run each task's Check before starting
the next. If a Check fails twice, or a task tells you to STOP, stop and report.
Stop after S3 and report: every file you changed, each Check output, and a
screenshot of the new Settings section. Do not start S4.

---

## Rules

> Project: `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\CruDoc`, a Flutter app on
> Firebase. Shared widgets live in `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\crudoc_shared`.
> Follow the "Design" section below exactly.
> - Change ONLY the files the task names (you may create the new files it names).
>   Do not reformat or "improve" other code.
> - Never deploy, never `git commit`/`push`.
> - Never delete or move real files outside a test's temporary folder while
>   developing. Tests use `Directory.systemTemp.createTemp()` and synthetic files.
> - Dart UI: read `CruDoc/.claude/rules/crudoc-ui.md` and follow it
>   (`context.cru` colours, `CruSpace`, `CruRadius`, `CruType`; no hard-coded colours/sizes).
> - Run only the test files the task names. Never run the whole `flutter test`
>   suite (parallel runs crash on sqlite3.dll).
> - If something in the task doesn't match the code you find, STOP and report
>   what you found instead of guessing.
> - When done, list every file you changed and paste the output of the Check.

---

## Design

**Goal.** In Settings, the doctor picks how much space CruDoc may use on this
device and sees what that space is made of. When the device passes 90% of the
limit, CruDoc removes old scans that are safely in the cloud, until usage is
back under 70%. Removed scans download again when opened.

**Where things live on the device** (all under `getApplicationSupportDirectory()`
unless noted):

| Category (label in UI) | Folders / files | Can CruDoc remove it? |
|---|---|---|
| Scans | `radiology/` (originals, `.views/`, `.previews/`) | Yes, if backed up (see below) |
| Photos & documents | `dental/`, `therapy/` | No (v1: shown only) |
| Patient records | the local database files (`local_database_service.dart`: Windows uses app support; Android/iOS use `getDatabasesPath()`), including `-wal` / `-shm` | Never |
| Voice recordings | `scribe/` | No (the scribe already deletes them after review) |
| Waiting to upload | `pending_uploads/` | Never |
| Temporary files | `getTemporaryDirectory()` | Yes, files older than 1 day |
| Other | everything else under app support | No |

**Limit setting**: stored per device in `SharedPreferences`, key
`storage.limitBytes` (int; `0` = no limit). Choices: 500 MB, 1 GB, 2 GB,
5 GB, 10 GB, 20 GB, No limit. Default when unset: **1 GB on Android/iOS,
10 GB on Windows/macOS**. Use 1 GB = 1024³ bytes.

**Cleanup rules (S4–S6)**
- Starts when total usage > 90% of the limit; stops below 70%. "Free up space
  now" runs it regardless of the 90% trigger and stops below 70%.
- Never touches: Patient records, Waiting to upload, Photos & documents, Voice
  recordings, Other.
- A scan original may be deleted only if ALL hold: its `RadImageRef.storagePath`
  is non-empty, `cloudStatus` is empty, and the cloud object's MD5
  (`FirebaseStorage.instance.ref(path).getMetadata()` → `md5Hash`, base64)
  equals the local file's MD5. Otherwise skip it.
- Protected (never removed): anything opened or imported in the last 7 days.
- Order: least recently opened first; ties → bigger first. Passes:
  1. Temporary files older than 1 day.
  2. Scan originals (verified as above).
  3. `.views/*/frame_n.j2c` beyond the preview: truncate the file to its sidecar
     `previewEnd` and set the sidecar `have` to `previewEnd` (keeps the preview).
  4. Remaining `.views/*` files entirely (file + sidecar).
- Runs at app start (after sign-in), after a scan is downloaded or imported,
  and from the button. Never on the UI thread for the scanning/MD5 work.

---

## Task S1 — Measure storage by category

Create `CruDoc/lib/core/storage/storage_usage.dart`:
```dart
enum StorageCategory {
  scans('Scans'),
  photosDocs('Photos & documents'),
  records('Patient records'),
  voice('Voice recordings'),
  pendingUploads('Waiting to upload'),
  temp('Temporary files'),
  other('Other');
  const StorageCategory(this.label);
  final String label;
}

class StorageUsage {
  const StorageUsage(this.bytes);
  final Map<StorageCategory, int> bytes;
  int get total => bytes.values.fold(0, (a, b) => a + b);
  double share(StorageCategory c) => total == 0 ? 0 : (bytes[c] ?? 0) / total;
}

/// Sizes every category (see handoff Design table). Runs the folder walk in
/// an isolate. Missing folders count as 0; unreadable files are skipped.
Future<StorageUsage> measureStorageUsage();

/// The pure part, for tests: [supportDir], [tempDir] and [dbFiles] given explicitly.
@visibleForTesting
StorageUsage measureStorageUsageIn({
  required Directory supportDir,
  required Directory tempDir,
  required List<File> dbFiles,
});
```
- `records` = sum of `dbFiles` that exist. To find them, read how
  `local_database_service.dart` builds its database path(s) and reuse that
  (add a small public helper there that returns the db file paths, without
  changing how the database opens). If the database file sits inside
  `supportDir`, don't count it twice under `other`.
- Top-level folders under app support map to categories exactly as in the
  Design table; anything else → `other`.

Create `CruDoc/test/core/storage/storage_usage_test.dart`: build a temp
support dir with files in `radiology/`, `dental/`, `pending_uploads/`,
`scribe/`, `misc/`, a temp dir, and a fake db file; check every category's
bytes and that `share()` values add up to 1.

Check:
```
dart analyze lib/core/storage test/core/storage
flutter test test/core/storage/storage_usage_test.dart
```

---

## Task S2 — The limit preference

Create `CruDoc/lib/core/storage/storage_limit.dart`:
```dart
const List<int> storageLimitChoices = [
  500 * 1024 * 1024, 1 << 30, 2 << 30, 5 * (1 << 30), 10 * (1 << 30), 20 * (1 << 30), 0,
]; // 0 = no limit

int defaultStorageLimitBytes(); // 1 GB on Android/iOS, 10 GB otherwise (web: 0)
Future<int> readStorageLimitBytes();          // SharedPreferences 'storage.limitBytes'
Future<void> writeStorageLimitBytes(int bytes);
String formatStorageBytes(int bytes);         // "640 MB", "1.2 GB", "No limit" for 0
```
Plus Riverpod providers next to them, following the style of an existing
provider in `lib/features/settings/data/appearance_provider.dart`:
`storageLimitProvider` (reads/writes the preference) and
`storageUsageProvider` (`FutureProvider` calling `measureStorageUsage()`,
refreshable with `ref.invalidate`).

Create `CruDoc/test/core/storage/storage_limit_test.dart` for
`formatStorageBytes` (0, 999 bytes, 640 MB, 1 GB, 1.5 GB, 0 → "No limit") and
read/write round trip with `SharedPreferences.setMockInitialValues`.

Check:
```
dart analyze lib/core/storage test/core/storage
flutter test test/core/storage/storage_limit_test.dart
```

---

## Task S3 — "Storage on this device" in Settings

1. In `lib/features/settings/presentation/desktop_settings_screen.dart`:
   - Add `storage('Storage on this device', <an existing CruIcons icon that fits, e.g. a disk/box/archive icon; pick one that exists>)`
     to `enum SettingsSection`, placed after `devices`.
   - Add `SettingsSection.storage => const StorageSettingsSection()` to the
     `body` switch.
   - Make sure the phone also lists it: check how `lib/features/mobile/mobile_more.dart`
     lists Settings sections; if it uses its own list, add `storage` there too.
2. Create `lib/features/settings/presentation/storage_settings_section.dart`
   with `StorageSettingsSection` (ConsumerWidget). Use the same card widgets the
   other sections in `desktop_settings_screen.dart` use (if `_SettingsCard` is
   private, copy its look with a small private widget in your file; don't
   change `desktop_settings_screen.dart`'s privacy). Content, top to bottom:
   - **Usage line**: "Using 640 MB of 1 GB" (or "Using 640 MB · no limit").
   - **One stacked bar** (full width, `CruRadius` rounded, ~10 px tall): one
     segment per category with bytes > 0, width = its share of the limit
     (or of the total when there's no limit); the empty remainder in the
     track colour. Colours: one distinct `context.cru` accent per category,
     the same in Day and Evening themes. Never hard-code colours.
   - **Legend**, one row per category with bytes > 0, biggest first: colour
     dot, label, size (`formatStorageBytes`), percent of total (whole number,
     "<1%" for tiny). Under "Waiting to upload" add the caption
     "Never removed". Under "Patient records" add "Never removed".
   - **Limit picker**: the 7 choices from `storageLimitChoices`, shown with
     `formatStorageBytes`. Copy the choice control style used in the
     Appearance section (find `_AppearanceSection`). Saving writes the
     preference and refreshes the bar.
   - **Explainer** (caption style): "When this device passes 90% of the limit,
     CruDoc removes scans you haven't opened for a week. They stay in the cloud
     and download again when you open them."
   - **Button** "Free up space now": for now, disabled with the tooltip
     "Coming next" (S6 wires it).
   - While `storageUsageProvider` loads, show the layout with a spinner where
     the numbers go; on error, show "Couldn't measure storage" and a Retry text
     button that invalidates the provider.

Check:
```
dart analyze lib/features/settings lib/core/storage
flutter build windows --debug
```
Then run the Windows app (`flutter run -d windows`), open Settings → Storage
on this device, change the limit, and take a screenshot. Quit the app.

🛑 GATE — report the files changed, Check output and the screenshot.

---

## Task S4 — Remember when each scan was last opened

(Not yet: wait for Claude's go-ahead in DO NOW.)
Create `lib/features/radiology/data/rad_last_opened.dart`: a small index stored
at `radiology/<doctorId>/.last_opened.json` mapping each image's relative path
(`<studyId>/<relativePath>`) to epoch ms. `touch(doctorId, studyId, relativePath)`
updates it (writes at most once every 5 s, merged, via a temp file + rename);
`read(doctorId)` returns the map. Call `touch` from `fileOf` and `pixelsOf`
in `radiology_providers.dart`, and when a study is imported (find the import
save path in `radiology_repository.dart`). Test with a temp folder.

## Task S5 — The cleanup planner (pure)

(Not yet.) Create `lib/core/storage/storage_cleanup_plan.dart` with a pure
function: given candidate files (path, size, lastOpened, kind: temp | original |
viewBeyondPreview | viewWhole, previewEnd if any, protected flag), current
total, and limit → ordered list of actions (delete / truncateTo) following the
Design rules (start > 90%, stop < 70%, protected never, order by passes then
oldest then biggest). Thorough unit tests.

## Task S6 — Run the cleanup

(Not yet.) Create `lib/core/storage/storage_cleanup_service.dart`: collects
candidates (scans via the radiology repository so each file is tied to its
`RadImageRef`; temp files), verifies scan originals by MD5 against cloud
metadata just before deleting each one, applies the plan, returns bytes freed.
Wire triggers (app start after sign-in, after scan download/import) and the
"Free up space now" button (shows "Freed 230 MB" or "Nothing to remove").

## After all tasks (Claude + you)
- Claude reviews the whole diff, especially S6's delete path.
- Test on the Pixel with the limit set to 500 MB and a few large scans.
