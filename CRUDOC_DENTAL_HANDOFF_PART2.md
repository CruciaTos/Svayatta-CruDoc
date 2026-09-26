# CruDoc Dental: Handoff Part 2 (what's left, in order)

Read this first, then `handoff/CRUDOC_DENTAL_HANDOFF.md` (Part 1) for the detailed task specs it points to. Part 1's Primer (its Part 1) still applies in full: design system, record store, shell, code style.

- **Repository:** `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc`, Flutter app in `CruDoc/`, branch `main`.
- **Starts from:** commit `2b6f06c`.
- **You have the repository.** Read the files named below before changing them; never guess an API.

---

## 1. Where things stand

### Done and on main (don't rebuild)

- **Tooth chart:** 2.5D chart with Dental/Plan/Perio/Endo/All layers, tooth detail screen, 3D view.
  - `lib/features/dental/presentation/desktop/chart/` (`tooth_art.dart`, `tooth_chart_2d.dart`, `tooth_chart_data.dart`, `chart_legend.dart`)
  - `lib/features/dental/presentation/desktop/tooth_detail_screen.dart`, `tooth_chart_card.dart`
- **Part 1 tasks done:**
  - F1 sub-login framework, F2 tooth numbering (`lib/features/dental/domain/tooth_numbering.dart`, Settings → Dental).
  - P1–P5 perio: staging, plaque, root planing, perio patients page and card.
  - Sub-logins for all dental specialties except Orofacial Pain. Their sidebar pages show `DentalNotBuiltScreen` until built.
  - PD2 eruption chart: `specialties/pedo/eruption_chart.dart`.
  - PD5 large text and icons: `specialties/pedo/large_mode.dart`, and `CruIconScale` in `shared/widgets/cru/cru_icons.dart`.
  - OM2 oral medicine history: `specialties/oralmed/oralmed_history.dart`. Its allergies also feed the red allergy chip in Patient details.
  - AN8 emergency protocols: `specialties/anaesthesia/emergency_protocols.dart`, tab index 30. The clinic enters its own protocols.
  - Scan viewer: export the selected rectangle/ellipse ROI as PNG (`radiology/viewer/viewer_screen.dart`).
- **Record kinds added to `RecKind`:** `perioDx`, `srp`, `omHistory`, `eruption`, `emergencyProtocol`.

### Tab indices

- Used: 0–30 (30 = Emergency).
- **The next free index is 31.**
- Adding a tab touches five places, all in the same order:
  - `DesktopTab` in `lib/features/dashboard/presentation/dashboard_actions.dart`: the constant, `isDental`, and the title switch.
  - `_labels` and `_icons` in `lib/features/shell/presentation/desktop_shell.dart`.
  - `_buildScreen` in the same file.
  - `specialtyNav` in `lib/features/shell/components/cru_sidebar.dart`.

### Specialty pages still showing "Not built yet"

To build one, replace its `DentalNotBuiltScreen` case in `desktop_shell.dart` `_buildScreen` with the real screen:

- Root canals, Referrals
- Children
- Biopsies
- Lesions, Forms
- Sedation cases
- Lab cases
- Ortho patients
- Camps, Population
- Surgeries, Implants

---

## 2. Rules (short; the full ones are in `CruDoc/.claude/rules/crudoc-ui.md`)

- **Colours:** only tokens (`context.cru`), `CruType`, `CruSpace`, `CruRadius`, `CruSize`. Nothing hard-coded.
- **Colour meanings:**
  - Accent blue: the one primary action, selection and links.
  - Amber: waiting or attention.
  - Green: done.
  - **Red: allergies and patient safety only.**
  - **Violet (`c.ai`, `c.aiTint`): AI content only.**
- **Buttons:** one filled button per region; the rest are `secondary`, `inset` or capsules.
- **Numbers:** tabular (`.tabular`).
- **Tooth numbers:** always shown through `toothLabel(fdi, numbering)`, where `numbering = ref.watch(toothNumberingProvider).value ?? ToothNumbering.fdi`. Always stored as FDI.
- **No fabricated data:**
  - Never ship sample patients or findings.
  - Clinical content the clinic must approve (doses, protocols, questionnaire wording, legal text) is entered by the clinic or marked "needs review". Never invent it.
- **Placeholders:** features that can't be wired yet get an honest "Not connected yet" / "Not built yet" state. Never fake success.
- **Empty states:** every screen explains what goes there and has the action to add the first item.

### Reuse these (all exist)

- **Records store** (`lib/features/dental/records/dental_records_repo.dart`):
  - `DentalRecord.create(patientId, kind, data)` and `r.copyWith(data:, recordedAt:)`
  - `saveDentalRecord(ref, r)` and `deleteDentalRecord(ref, r)`
  - `patientRecordsProvider((patientId:, kind:))` and `clinicRecordsProvider(kind)`
  - `recToast(context, msg)`
- **Dental UI kit** (`presentation/desktop/dental_ui.dart`):
  - Dialogs and pages: `DentalPanelDialog` (saves as you go), `DentalPageHeader`.
  - Chips: `DentalChipWrap`, `DentalChoiceChip`.
  - Lists and states: `DentalListRow`, `DentalEmptyState`, `DentalGroupLabel`.
  - Helpers: `confirmDental`, `pickDentalDate`, `DentalFormat`.
- **Forms:** `CruFormDialog` for forms with Save/Cancel; `CruFormSection`, `CruFieldFrame`, `CruFieldRow`, `CruTextField`.
- **Actions:**
  - WhatsApp: `PatientActions.whatsApp(context, patient, message: ...)`.
  - Picking a patient: `pickRadPatient` (radiology dialogs).
  - Files: `FilePicker.pickFiles(...)` and `FilePicker.saveFile(...)` (static API, v11).
- **Patient record card:** new per-patient features add a row to `DentalRecordsCard` (`lib/features/dental/records/dental_records_card.dart`). Copy how the "Oral medicine history" and "Eruption" rows are done.

### Windows and tooling gotchas

- **Verify:** `flutter analyze` on the folders you touched, and fix all errors and warnings you introduced. A few warnings already exist in `web_dashboard_view.dart`; leave them.
- **Tests:** never run two `flutter test` commands in the same folder at once; it crashes on `sqlite3.dll`.
- **Missing `lib/firebase_options.dart`:** it isn't in git. Copy it from the main folder.
- **Generated plugin files:** after `flutter pub get`, the generated plugin files under `macos/` and `windows/` may change only in line endings. Don't commit those.
- **Commits:** one per task, message `"<task id>: <what>"`.

---

## 3. Work order

### Step 1 — Firestore sync for dental records and radiology (approved)

**Goal.** Dental records and radiology documents live in local SQLite (source of truth, works offline) and mirror to Firestore when online, like the rest of the app.

**Read first:**
- `lib/core/services/firestore_sync_service.dart` (the existing sync pattern: follow it exactly)
- `lib/core/services/local_database_service.dart` (tables and migrations)
- `lib/features/dental/records/dental_records_repo.dart`
- `lib/features/radiology/data/radiology_repository.dart`
- `firestore.rules`

**Build:**
1. **Local columns.** Add `syncStatus` (`'pending'` | `'synced'`), `pendingDelete` and `lastSyncedAt` to the `dental_records` table (and the radiology document table). Use the same migration mechanism the database service already uses for other tables: bump the version and `ALTER TABLE`. Existing rows start as `pending`.
2. **Writes.** `save` and `delete` in `DentalRecordsRepository` set `syncStatus = 'pending'` (delete stays a soft delete with `isDeleted = 1`).
3. **Push.** Upload pending rows to Firestore under the same per-doctor path the existing sync service uses for its collections (e.g. `.../dental_records/{id}`). Encrypt the `data` JSON with the existing `FieldCipher` before upload, as the other models encrypt notes. On success, set `synced` and `lastSyncedAt`.
4. **Pull and merge.** Last write wins on `updatedAt`. Never overwrite a local `pending` row with an older remote one.
5. **Trigger.** Run it wherever the existing sync runs (app start, sign-in, connectivity back, periodic); don't add a new scheduler.
6. **Rules.** Add rules in `firestore.rules` for the new collection(s): only the owning doctor reads and writes.
7. **Out of scope:**
   - Clinic-wide roles and sharing between doctors (the user's decision is still open).
   - Images and scan files (they wait for S3, which waits for company incorporation). Only JSON documents sync.

**Acceptance:**
- Create a perio exam offline; go online; it appears in Firestore encrypted.
- Edit it on a second signed-in machine; the first machine picks up the newer version.
- A deleted record stays deleted on both machines.

### Step 2 — AI second read with Gemini (the 7 AI items; the key comes later)

**Spec items this closes:**
1. Caries overlay
2. Bone-loss estimate
3. Periapical lesion flag
4. Impacted tooth detection
5. Confidence per finding
6. Accept/reject/edit before anything enters the record
7. Auto-fill the report from accepted findings

**Read first:**
- `lib/features/radiology/viewer_plus/ai/ai_panels.dart` (today it says "No AI key connected")
- `lib/core/services/gemini_json_client.dart` (already calls Gemini with JSON output; reuse it and its model constant)
- How the scribe reads the key: `GEMINI_API_KEY` in `.env.local`; see `dart_test.yaml` and the scribe services
- `lib/features/radiology/viewer/viewer_export.dart` (`radRenderPaneView` for pixels)
- `lib/features/radiology/data/radiology_models.dart`
- `lib/features/radiology/presentation/reports/report_editor_screen.dart`, `tooth_findings.dart`

**Create `lib/features/radiology/ai/rad_ai.dart`:**

```dart
enum RadAiKind { caries, boneLoss, periapical, impacted }

class RadAiFinding {
  final String id;
  final RadAiKind kind;
  final String label;         // "Distal caries", "Horizontal bone loss ~30%"
  final double confidence;    // 0..1
  final Rect? box;            // normalised 0..1 on the image, null if none
  final String tooth;         // FDI or ''
  final String status;        // 'pending' | 'accepted' | 'rejected' | 'edited'
}

abstract class RadAiProvider {
  bool get connected;
  Future<List<RadAiFinding>> secondRead(Uint8List pngPixelsOnly, {required String modality});
}

class NoAiProvider implements RadAiProvider { /* connected false; secondRead throws StateError('No AI key connected') */ }
class GeminiRadAiProvider implements RadAiProvider { /* see below */ }

final radAiProviderProvider = Provider<RadAiProvider>(...); // Gemini when a key is present, else NoAiProvider
```

**`GeminiRadAiProvider`:**
- **Key.** Read it the same way the scribe does. **Until the user supplies a key, keep the placeholder `GEMINI_API_KEY=` empty in `.env.local` / `.env.example`.** An empty key means `connected == false` and the panels keep saying "No AI key connected".
- **De-identify.** Render the image with `radRenderPaneView(..., withAnnotations: false)` and encode PNG. Send pixels only: no DICOM header, no patient name or dates, and no burned-in text overlays if the image has them (skip images whose modality is unknown).
- **Prompt.** Ask for JSON only, validated against a schema: a list of `{kind, label, confidence, box: [x0,y0,x1,y1] normalised, tooth}` for the four kinds. State plainly that it's a second reader for a dentist, not a diagnosis.
- **Parse.** Clamp boxes to 0..1, drop malformed items, and cap to about 20 findings. Network or quota errors show "Couldn't reach the AI: <reason>". Never show invented results.

**Store.** On the study, under a new `aiReads` list: `{at, model, findings: [...]}`. Keep every run; findings carry their status. Log each run and each accept or reject with the existing radiology audit log (`ctl.log(...)`).

**UI (`ai_panels.dart` and the viewer side panel):**
- **Run.** A "Run second read" button is enabled only when `connected`. While running, show progress; the result is a list grouped by kind.
- **Each finding:** label, tooth (`toothLabel`), a confidence pill (e.g. "72%"), and buttons **Accept**, **Reject**, **Edit** (label/tooth).
- **Overlay.** Boxes drawn on the viewer in **violet** (AI colour), dashed while pending, solid when accepted, hidden when rejected. A toggle hides all AI marks.
- **Record.** Nothing enters the study's findings or the report until accepted.
- **Label.** Every AI item is marked "AI suggestion" with the sparkle icon (`CruIcons.sparkle`).

**Report auto-fill.** In the report editor, add a button "Add accepted AI findings". It inserts each accepted finding into the tooth findings (`tooth → text`) and/or the findings text, suffixed "(AI-assisted, confirmed)". The radiologist can edit it afterwards like any text.

**Acceptance:**
- With no key: everything says "No AI key connected" and nothing crashes.
- With a key: running on an OPG lists findings with confidences.
- Accept two and reject one: only the two appear via "Add accepted AI findings".
- The audit log shows the run and the decisions.

**Regulatory note (leave as a comment near the provider):** AI findings shown to clinicians may fall under India's CDSCO Software-as-a-Medical-Device rules. Keep them clearly labelled as suggestions that need confirmation.

### Step 3 — the 26 remaining features (Part 1 specs, in this order)

Build each exactly as Part 1 specifies, with the adjustments noted here.

| # | Part 1 task | What it adds | Notes |
|---|---|---|---|
| 1 | **F3** Referrals | New/edit referral, contacts, status tracker, letter PDF, WhatsApp/email send | Replace the "Referrals" `DentalNotBuiltScreen` (tab 18). Add a "Referrals" row to `DentalRecordsCard`. Everything below reuses its contacts. |
| 2 | **PR2** Lab partners | Contacts with specialty "Dental lab" and `turnaroundDays` | Extends F3 contacts. |
| 3 | **PR3** Lab cases | Rx form, stage pipeline (list and board), files, patient message on "received" | Replaces the "Lab cases" tab (24). Card row "Lab cases". |
| 4 | **PR4** 3D scan placeholder | `.stl/.ply/.obj` show a "3D" chip; the page shows name, size, STL triangle count, "Open with default app" | No rendering (3D is deferred). |
| 5 | **PR5** Export case | ZIP with files + `order.json` + `order.pdf` | Direct exocad/3Shape is "not connected yet". |
| 6 | **OR3** Photo series | 8-slot photo sets | Needed by OR4. |
| 7 | **OR2** Ortho case | Appliance, visits, aligners, retention | Card row "Ortho". |
| 8 | **OR4** Before/after slider | Drag divider, PNG export | |
| 9 | **OR6** Ortho patients page | Replaces tab 25 | Keep the wear-time "not connected yet" note. |
| 10 | **PA2** Biopsy log | Status pipeline, lab from F3 contacts, report PDF attach, "Tell patient" | Replaces tab 20. Card row "Biopsies". |
| 11 | **OM3** Lesion tracker | Site chips, entries with photo and size, compare, "Refer for biopsy" | Replaces tab 21. Card row "Lesions". |
| 12 | **OM4** Form builder | Templates, fill, responses | Replaces tab 22. Card row "Forms". |
| 13 | **AN2** Pre-op | `sedationCase` record | Allergies in red. |
| 14 | **AN3** Vitals log | Case page, chart, red safety alerts, "vitals due" | Add "Log to case" to the Emergency page (tab 30) once the case page exists. |
| 15 | **AN4** Drug log + LA max-dose calculator | | Keep the dose table in one const list with "Check against your local formulary". |
| 16 | **AN6** Sedation cases page | Replaces tab 23 | AN5 (Aldrete) and AN7 (Bluetooth placeholder) go with it. |
| 17 | **PH2** Camps + quick registration | Offline, keyboard-first; creates real patients | Replaces tab 26. |
| 18 | **PH3** DMFT helper | Prefill screenings from the tooth chart | |
| 19 | **PH4** Population dashboard | Prevalence by age, mean DMFT, needs, demographics, top procedures | Replaces tab 27. Charts show n and an honest empty state. |
| 20 | **PH5** CSV + camp summary PDF + NGO report | | The NGO/government layout needs the user's template: until then, "Report for NGO / government: send us the funding body's template" (honest placeholder). |

(Those 20 tasks close the 26 spec items. PR3 and PH4/PH5 each close several.)

**Not in scope:**
- **Clinical content others must supply:** DC/TMD wording (OP2–OP3) and the ADA caries-risk form (PD3).
- **Cloud and hardware:** anything needing S3, EC2/Orthanc, clinic roles and sharing, Bluetooth monitors, or a patient app.
- **3D rendering:** keep those pages as honest placeholders.

---

## 4. How to check your work (each task)

1. Run `flutter analyze` on the folders you touched: no new errors or warnings.
2. Run the app (`flutter run -d windows` from `CruDoc/`) and go through the task's Acceptance list in Part 1.
3. Sign in as the matching specialty (Dentist → the specialty chip). Its sidebar page should open the real screen, not "Not built yet".
4. Check a general dentist still sees nothing new except the card rows meant for all dentists.
5. Commit: `"<task id>: <what>"`.
