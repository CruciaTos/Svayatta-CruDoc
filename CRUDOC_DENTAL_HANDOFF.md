# CruDoc Dental Specialties: Implementation Handoff

This is the step-by-step plan for finishing every dental specialty in CruDoc. It's written so that another model (Sonnet on another account, DeepSeek, or any model **without access to the repository**) can do the work one task at a time, with you acting as its hands.

- **Repository:** `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc` (Flutter project in `CruDoc/`), branch `main`.
- **State this guide starts from:** commit `3330a9f` (Radiology module plus the dental clinical records).
- **Scope rule:** no major 3D/2D modelling work (CBCT 3D rendering, STL mesh rendering, AI image models). Where those appear, build a **clean placeholder page** that says "Not built yet" and lists what's coming. Everything else must be built completely and to a high standard.

---

## Part 0: How to use this guide

### 0.1 Who does what

| You (the human) | The model |
|---|---|
| Pick the next task (the order is in 0.6) | Writes the code for that one task |
| Paste the **Primer** (Part 1) + the **task** + the **files the task lists** into the chat | Returns **complete files** or exact FIND/REPLACE edits |
| Create folders and files, and paste the code in | Never guesses an API; asks you to paste a file if it needs one |
| Run `flutter analyze` and paste the errors back | Fixes them |
| Run the app and tick the task's acceptance checklist | — |
| Commit | — |

The model can't see your disk. **Everything it knows comes from what you paste.** If an answer uses a class or function that isn't in the Primer or the files you pasted, ask it: "Where is X defined? I don't have it." Then paste that file, or tell it to use what the Primer lists.

### 0.2 The loop for every task

1. Open a **new chat** for each task. A short context gives better code.
2. Paste the **prompt template** from 0.3, filled in.
3. The model replies with files. For each one:
   - **New file:** create the folder if it's missing, create the file, and paste the content.
   - **Modified file:** replace the whole file if the model gave the whole file. If it gave FIND/REPLACE blocks, use your editor's Find and replace each block exactly once. If a FIND isn't found, tell the model which block failed.
4. In PowerShell, run:
   ```
   cd C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\CruDoc
   flutter analyze lib/features/dental lib/features/shell lib/features/patients
   ```
   (Use the folders the task names.) Copy **every line with `error` or `warning`** back to the model and say: "Fix these. Give full corrected files or FIND/REPLACE."
5. Repeat until the analyzer shows no errors or warnings. Info lines are optional.
6. Close the app if it's running, then run `flutter run -d windows`. Go through the task's **Acceptance** list and tell the model about anything that doesn't behave.
7. Commit:
   ```
   git add -A
   git commit -m "<task id>: <short description>"
   ```

### 0.3 Prompt template (copy, fill, paste)

````
You are implementing one task in CruDoc, a Flutter 3.41 desktop app (Windows), Riverpod 3, local-first SQLite. You can't see the repository; I paste everything you need.

RULES
- Follow the PRIMER below exactly: its design rules, widgets, data patterns and code style.
- Use only APIs that appear in the PRIMER or in the files I paste. If you need something else, stop and ask me to paste the file that defines it.
- Output for NEW files: the complete file, in one code block, with the path as the first line comment, e.g. `// lib/features/dental/records/perio_staging.dart`.
- Output for CHANGED files: if the file is under 400 lines, return the complete file. Otherwise return FIND/REPLACE blocks: FIND must be copied verbatim from the file I pasted and be unique; REPLACE is the new text.
- Build everything the task asks for, completely. No TODOs, no "implement later", no fake data. The only placeholders allowed are the ones the task explicitly marks as PLACEHOLDER; they must say "Not built yet" or "Not connected yet" honestly.
- After the code, list any folders I must create, and say which folders to run `flutter analyze` on.

PRIMER
<paste Part 1 of the guide>

TASK
<paste the task section, e.g. "P3 · Staging and grading calculator">

FILES
<paste each file the task lists under "Give the model", each in its own code block with its path>
````

### 0.4 Human intervention you'll need (the whole project)

These are the things only you can do. Each task also lists its own.

1. **Paste files.** Each task lists the files to paste. To open one fast: `code <path>` or Notepad.
2. **Create folders and files.** Paths are always relative to `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\CruDoc\`.
3. **Search the code when a task says "find all places".** In PowerShell from the `CruDoc` folder:
   ```
   Get-ChildItem -Recurse lib -Filter *.dart | Select-String -Pattern 'isDentistProvider' | Select-Object Path, LineNumber, Line
   ```
   Paste the result to the model.
4. **Packages.** When a task says to add a package, run `flutter pub add <name>`, then `flutter pub get`. Never edit `pubspec.lock` by hand.
5. **Run the analyzer and the app** (0.2). If the build fails with "Cannot open include file" and a very long path, your folder path is too long for Windows. Build from the main folder (`C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\CruDoc`), or map a short drive with `subst R: C:\Soham\Kamachya_Goshti\Svayatta_CruDoc` and build from `R:\CruDoc`.
6. **`lib/firebase_options.dart`** is not in git. If a fresh checkout says it's missing, copy it from your main folder.
7. **Don't run two `flutter test` commands in the same folder at once.** It crashes on `sqlite3.dll`.
8. **Clinical review.** Norm tables, eruption ages, drug dose limits, consent wording, questionnaire wording and staging rules must be checked by a qualified dentist before real patients use them. Appendix D lists them all.
9. **Official questionnaire wording.** DC/TMD instruments (orofacial pain) and the ADA caries-risk form must be copied word for word from their official sources. You download them and paste the wording to the model (the task says where).
10. **Decisions only you can make.** Take these before the related tasks:
    - cloud provider and structure (Firestore, S3, Orthanc hosting)
    - AI provider and key
    - SMS gateway
    - WhatsApp Business API
    - the legal text for consents
11. **Test data.** Create a few patients in the app yourself. The code must never ship sample patients.
12. **Commits.** One commit per task keeps things easy to undo.

### 0.5 Rules to repeat to the model if its quality slips

- One filled (primary) button per region. Everything else is `secondary`, `inset`, or a capsule.
- No hard-coded colours, font sizes or radii. Use `context.cru`, `CruType`, `CruSpace`, `CruRadius` and `CruSize`.
- Red only for patient safety or allergies; violet only for AI; amber means waiting or attention; green means done.
- Every screen needs an empty state that explains what goes there and how to add the first item.
- Every element must earn its place: no dead buttons, no duplicate controls, no switches that do nothing.
- Controls shared across views of one screen stay in exactly the same position in every view.
- Numbers use tabular figures (`.tabular`).
- Never show fabricated patient data.

### 0.6 Where things stand and the order to work in

**Built already (don't rebuild):**
- **Radiology (Oral & Maxillofacial Radiologist sub-login):**
  - Worklist with DICOM/picture import and drag and drop
  - Patient matching and referral intake
  - 2D viewer with measurements, annotations, key images, export, CBCT slice stacks and a "3D" placeholder page
  - Filters, ceph tracing (all analyses including Wits and U1-SN), subtraction
  - Reports: templates, phrases, tooth findings, lesions, sign-off, addenda, PDF and share
  - Referrers with statements, fees into invoices, dose log, audit log, Settings → Radiology
  - PACS, scanner receiver, AI, dictation and secure links as honest "not connected" screens
- **Dental (all dentists):**
  - Tooth chart (2D and 3D), procedures, treatment plans, sterilization
  - Clinical records card: perio chart, endo notes, recalls (sidebar tab), consents with signature, pain and TMD screener, Frankl, WHO surgical checklist

**Tally against the spec (134 items):** 55 done, 17 partly done, 10 screen only (not connected or not built), 1 done differently, 51 not started.

**Order of work.** Each specialty is one phase and ends with a sub-login ("Log in as …" under Dentist). Easiest first:

| Order | Phase | Specialty | Effort |
|---|---|---|---|
| 1 | F | Shared foundations (sub-login framework, numbering setting, referrals) | Medium; do first |
| 2 | P | Periodontics | Low |
| 3 | OP | Orofacial Pain | Low |
| 4 | E | Endodontics | Low |
| 5 | PD | Pediatric Dentistry | Low–medium |
| 6 | PA | Oral & Maxillofacial Pathology | Low–medium |
| 7 | OM | Oral Medicine | Medium |
| 8 | AN | Dental Anesthesiology | Medium |
| 9 | PR | Prosthodontics | Medium (3D viewer = placeholder) |
| 10 | OR | Orthodontics | Medium (3D scans = placeholder) |
| 11 | PH | Public Health Dentistry | Medium |
| 12 | OS | Oral & Maxillofacial Surgery | Medium (CBCT planning = placeholder) |
| 13 | R | Radiology leftovers | Low–medium |
| 14 | C | Cloud and infrastructure | Needs your decisions first |

---

## Part 1: Primer (paste this into every session)

### 1.1 Stack and layout

- **Framework:** Flutter 3.41, Dart 3.11, Windows desktop first. There's also mobile code, but specialty screens are desktop-only.
- **State:** `flutter_riverpod` 3. Use `Provider`, `FutureProvider`, `FutureProvider.family`, `ConsumerWidget` and `ConsumerStatefulWidget`. `StateProvider` comes from `package:flutter_riverpod/legacy.dart` and is used only in older code.
- **Local database:** SQLite (SQLCipher) through `LocalDatabaseService.instance.localDatabase`. Tables are created on open with `CREATE TABLE IF NOT EXISTS`, with no migration ladder.
- **Packages available:**
  - flutter_riverpod, intl, uuid, path, path_provider, url_launcher, shared_preferences
  - pdf, printing
  - file_picker **v11**: methods are static, e.g. `FilePicker.pickFiles(...)`, `FilePicker.saveFile(...)`, `FilePicker.getDirectoryPath(...)`. There is no `.platform`.
  - image (pure Dart), archive, desktop_drop, geolocator
- **Import prefix:** `package:doctor_management_app/...`

**Key folders:**

```
lib/core/models/doctor_specialty.dart         specialties and sub-specialties
lib/core/providers/specialty_provider.dart    active specialty and isXxxProvider flags
lib/core/services/local_database_service.dart SQLite schema (tables created here)
lib/core/theme/                               design tokens (CruColors, CruType, tokens)
lib/shared/widgets/cru/cru.dart               design widgets (import this one file)
lib/features/dashboard/presentation/dashboard_actions.dart  DesktopTab indices
lib/features/dashboard/presentation/dashboard_screen.dart   dashboard cards
lib/features/shell/components/cru_sidebar.dart             sidebar groups
lib/features/shell/presentation/desktop_shell.dart         tab to screen switch
lib/features/patients/presentation/patient_details_view.dart  Patient details cards
lib/features/dental/presentation/desktop/dental_ui.dart    dental UI kit
lib/features/dental/records/                  clinical records (JSON store + screens)
lib/features/radiology/                       radiology module
```

### 1.2 Design system (Calm Clinical)

**Rules:**
- **Colour roles:** accent (Ink Blue) only for the single primary action, links and "now". Red only for allergies and patient safety. Violet (`c.ai`, `c.aiTint`) only for AI content. Amber means waiting or attention. Green means done. Patient avatars are grey monograms.
- **Radii:** cards 24, inputs and buttons 12, icon tiles 10, chips and pills fully round.
- **Spacing:** the 4-pt grid (4, 8, 12, 16, 20, 24, 32).
- **Type:** Geist, bundled. All numbers are tabular.
- **Motion:** 200–250 ms, easeOutCubic, no bounce.

**Colours:** `final c = context.cru;` gives:
- surfaces: `canvas`, `surface`, `inset`, `track`
- text: `label`, `label2`, `label3`
- lines: `separator`, `hairline`
- accent: `accent`, `onAccent`, `accentText`, `accentTint`
- status: `amber`, `amberText`, `amberTint`, `green`, `greenText`, `greenTint`, `redText`, `redTint`, `tealText`, `tealTint`
- AI: `ai`, `aiTint`
- other: `hoverFill`, `cardShadow`, `primaryButtonFill`, `primaryButtonText`

**Type styles:** `CruType.largeTitle`, `title`, `title2`, `headline`, `callout`, `text`, `subhead`, `caption`, `micro`, `groupLabel`, `metric`. Modifiers: `.w500`, `.w600`, `.tabular`, `.tint(color)`. Example: `CruType.subhead.w600.tabular.tint(c.label)`.

**Tokens:**
- `CruSpace.s2 … s32`, `CruSpace.cardGap` (20), `CruSpace.stackGap` (22), `CruSpace.mainPadding` (page padding)
- `CruRadius.card`, `CruRadius.control`, `CruRadius.bar`
- `CruSize.control` (40), `CruSize.chip`, `CruSize.pill`, `CruSize.squareButton`, `CruSize.rowCapsule`, `CruSize.monogramRow`, `CruSize.monogramList`, `CruSize.dialog` (420), `CruSize.formDialog` (760), `CruSize.rightColumn` (384), `CruSize.progressBar`
- `CruBreakpoint.wide`, `CruBreakpoint.compact`
- `CruMotion.of(context)`, `CruMotion.curve`
- `cruShape(radius, side: BorderSide(...))` returns a ShapeBorder

**Widgets** (import `package:doctor_management_app/shared/widgets/cru/cru.dart`):

```dart
CruButton(label: 'Save', onPressed: () {}, icon: CruIcons.plus,
    kind: CruButtonKind.primary /* secondary | inset | tinted | outline */, large: false, expand: false)
CruCapsuleButton(label: 'Open', onPressed: () {}, icon: CruIcons.whatsapp)   // list-row actions
CruIconButton(icon: CruIcons.close, semanticLabel: 'Close', tooltip: 'Close', onPressed: () {},
    size: CruSize.squareButton, iconSize: 18)
CruLink(label: 'Delete this record', onPressed: () {})
CruCard(semanticLabel: 'Name', padding: EdgeInsets.all(16), child: ...)
CruSeparator(indent: 60)
CruPill(text: 'Done', background: c.greenTint, foreground: c.greenText)
CruIconTile(icon: CruIcons.user, tone: CruTileTone.accent /* teal | amber | neutral | green */)
CruMonogram(name: 'Asha Kulkarni', size: CruSize.monogramRow)
CruSegmentedControl<T>(segments: [CruSegment(v, 'Label')], selected: v, onChanged: (v) {}, semanticLabel: 'Show')
CruIcon(CruIcons.chevronRight, size: 16, strokeWidth: 2, color: c.label3)
CruInfoPill(text: 'Today')
CruProgressBar(value: 0.4)
CruKeycap('Ctrl')

// Forms (dialog in the Calm Clinical form style)
CruFormDialog(title: 'Add X', subtitle: '…', leading: CruIconTile(...), submitLabel: 'Save',
    onSubmit: _save, busy: _saving, dirty: _dirty, notice: _error, footerHint: 'Ctrl + Enter to save',
    body: Form(key: _form, child: Column(children: [
      CruFormSection(first: true, title: 'Section', description: 'Why it matters.', children: [
        CruFieldRow(children: [ CruTextField(...), CruTextField(...) ]),
      ]),
    ])))
CruTextField(label: 'Name', controller: c, hint: '…', optional: true, help: '…', prefix: '₹',
    trailing: Widget?, maxLines: 1, keyboardType: …, inputFormatters: [...], validator: (v) => …,
    onChanged: (v) {}, tabular: false, autofocus: false, textCapitalization: …)
CruPickerField(label: 'Date', icon: CruIcons.calendar, value: 'text or null', placeholder: 'Pick…',
    onTap: () {}, optional: false, trailing: Widget?)
CruFieldFrame(label: 'Result', optional: true, help: '…', child: Widget)
```

**Icons:** `CruIcons.plus`, `close`, `check`, `chevronLeft`, `chevronRight`, `chevronDown`, `search`, `calendar`, `clock`, `user`, `userPlus`, `patients`, `phone`, `whatsapp`, `pen`, `settings`, `warning`, `more`, `download`, `importExport`, `arrowUpRight`, `sparkle`, `rupee`, `box`, `mic`, `home`, `help`.

A new icon is SVG path data on a 24-unit viewBox (stroke style):

```dart
static const myIcon = CruIconData('M4 12h16M12 4v16', circles: [(12, 12, 3)], rects: [(3, 3, 6, 6, 1.5)]);
```

### 1.3 Dental UI kit

From `lib/features/dental/presentation/desktop/dental_ui.dart`:

```dart
DentalFormat.date(d) /* 12 Sep 2026 */, .shortDate(d) /* 12 Sep */, .time(d) /* 3:40 PM */,
    .day(d, now) /* Today, Yesterday, Mon 21 Sep */, .sameDay(a, b)
DentalPageHeader(title: 'Recalls', subtitle: '3 overdue', actions: [CruButton(...)])  // page title row
DentalSearchField(controller: c, hint: 'Search …', onChanged: (v) {})
DentalEmptyState(icon: X, title: 'No … yet', body: 'What goes here and how to add it.', actions: [CruButton(...)])
DentalListRow(semanticLabel: '…', onTap: () {}, minHeight: 56, child: Row(...))  // hoverable row
DentalGroupLabel('Today', trailing: '3 items')
DentalChoiceChip(label: 'Yes', selected: bool, onTap: () {}, onSurface: false)
DentalChipWrap<T>(options: [...], label: (t) => '…', isSelected: (t) => …, onTap: (t) {})
DentalPanelDialog(title: '…', subtitle: '…', leading: Widget?, width: CruSize.formDialog,
    body: Widget /* scrolls */, footer: Row(...)?)   // list-style dialog
Future<bool> confirmDental(context, title: 'Delete?', body: '…', action: 'Delete')
Future<DateTime?> pickDentalDate(context, initial: d, last: d, helpText: '…')
```

The dashboard glance strip (`features/dashboard/presentation/widgets/glance_card.dart`):

```dart
GlanceStrip(semanticLabel: '…', cells: [
  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
      children: [GlanceLabel('Overdue'), GlanceMetric('3'), GlanceCaption(Text('Past due date'))]),
])
SkeletonCard(rows: 1, rowHeight: 72)   // features/dashboard/presentation/widgets/skeleton.dart
DashFormat.plural(3, 'study', 'studies')   // features/dashboard/domain/dashboard_format.dart
```

`DentalChart` (`features/dental/domain/dental_chart.dart`):
- `adultUpper` = 18…11, 21…28; `adultLower` = 48…41, 31…38
- `childUpper` = 55…51, 61…65; `childLower` = 85…81, 71…75
- `isValid(t)`, `isPrimary(t)`, `name(t)` (e.g. "Upper left first molar")

### 1.4 Data: the clinical records store (use this for all new dental data)

File: `lib/features/dental/records/dental_records_repo.dart`. Table `dental_records(id, doctorId, patientId, kind, data JSON, recordedAt, isDeleted, createdAt, updatedAt)`. One row is a `DentalRecord`, and each feature owns a `kind`.

```dart
abstract final class RecKind { perio, endo, consent, recall, recallRule, pain, tmd, frankl, checklist, meta }
// Add new kinds as constants here (e.g. 'referral', 'biopsy', 'labCase').

class DentalRecord {
  String id; String patientId /* '' for clinic-wide records */; String kind;
  Map<String, dynamic> data; DateTime recordedAt /* when it happened / due */;
  DateTime createdAt, updatedAt;
  String str(key); int? integer(key); double? number(key); DateTime? date(key) /* data[key] as epoch ms */;
  DentalRecord copyWith({Map<String,dynamic>? data, DateTime? recordedAt});
  factory DentalRecord.create(String patientId, String kind, Map<String,dynamic> data, {DateTime? at});
}

typedef RecKey = ({String patientId, String kind});
final patientRecordsProvider   // FutureProvider.family<List<DentalRecord>, RecKey>, newest first
final clinicRecordsProvider    // FutureProvider.family<List<DentalRecord>, String kind>, all patients
Future<void> saveDentalRecord(WidgetRef ref, DentalRecord r);   // saves + refreshes both providers
Future<void> deleteDentalRecord(WidgetRef ref, DentalRecord r); // soft delete + refresh
void recToast(BuildContext context, String message);            // snackbar
abstract final class RecIcons { perio, endo, consent, recall, pain, frankl, checklist }
// repository: ref.read(dentalRecordsRepoProvider).completedProcedures(doctorId, since)
//   returns (patientId, name, at) for completed procedures
// doctor id: ref.read(dentalDoctorIdProvider)
//   from features/dental/presentation/providers/dental_desktop_providers.dart
```

**Reading and saving:**

```dart
final list = ref.watch(patientRecordsProvider((patientId: p.id, kind: RecKind.endo))).value
    ?? const <DentalRecord>[];
await saveDentalRecord(ref, DentalRecord.create(p.id, RecKind.endo, {'tooth': '36', 'status': 'open'}));
await saveDentalRecord(ref, existing.copyWith(data: {...existing.data, 'status': 'done'}));
```

**Rules for JSON:**
- Only JSON-safe values: strings, numbers, bools, lists and maps.
- Store dates as `millisecondsSinceEpoch` ints.
- Store images as files. Store the file path, or base64 when small (under 100 KB, e.g. a signature).
- Files go under `getApplicationSupportDirectory()/dental/<feature>/`.

Existing legacy dental tables (older code, leave them as they are): `dental_procedure_catalog`, `tooth_chart_entries`, `procedure_log_entries`, `treatment_plan_line_items`, `sterilization_log_entries`. Providers are in `features/dental/presentation/providers/dental_providers.dart`:
- `patientToothChartProvider(id)`
- `patientProcedureLogProvider(id)`
- `patientTreatmentPlanProvider(id)`, whose items have `procedureName`, `estimatedPrice`, `status`, `isDeleted`

### 1.5 Patients

- **`Patient`** (`features/patients/data/models/patient.dart`): `id`, `firstName`, `lastName`, `fullName`, `phone`, `email`, `gender`, `dateOfBirth`, `age`, `diagnosis` (list), `notes`, `isArchived`.
- **All patients:** `ref.watch(patientsStreamProvider).value` (`features/patients/data/providers/patient_providers.dart`).
- **`PatientActions`** (`features/patients/presentation/patient_actions.dart`):
  - `call(context, p)`
  - `whatsApp(context, p, message: '…')`, which opens WhatsApp with the text
  - `newVisit(context, ref, p)`, which opens the booking form
  - `edit(context, ref, p)`
- **Picking a patient:** `pickRadPatient(context, title: '…', subtitle: '…')` from `features/radiology/presentation/radiology_dialogs.dart` returns a `Patient?`.
- **Patient details:** `lib/features/patients/presentation/patient_details_view.dart` builds cards in `_DetailsBody`.
  - For dentists: `chart = ToothChartCard(...)`, `procedures = DentalProceduresCard(...)`, `records = DentalRecordsCard(patient: p)`.
  - Wide layout: `_Stack([?imaging, ?chart, ?noPlan, planOrPayments, notes])` on the left and `_Stack([?procedures, ?records, visits, history])` on the right. `?x` means "include if not null".
- **Clinical records card:** `lib/features/dental/records/dental_records_card.dart`. Each feature adds one row: icon, title, a one-line status, and a tap to open.

### 1.6 Shell: adding a sidebar page

1. `lib/features/dashboard/presentation/dashboard_actions.dart` → `abstract final class DesktopTab`. It has indices 0–15 (dashboard 0 … recalls 15). Add `static const myTab = 16;` using **the next free number**, add it to `label(tab)`, and add it to `isDental(tab)` if only dentists should see it.
2. `lib/features/shell/presentation/desktop_shell.dart`:
   - Append a label to `_labels` and an icon to `_icons`. **The list position must equal the tab number.**
   - Add a `case DesktopTab.myTab: return const MyScreen();` in `_buildScreen`.
3. `lib/features/shell/components/cru_sidebar.dart` → `_groupsFor({required bool dentist, required bool radiologist})`: add `_NavItem(DesktopTab.myTab, 'Label', SomeIcon)` inside the right group.
4. Screen layout (copy this pattern):

```dart
class MyScreen extends ConsumerStatefulWidget { const MyScreen({super.key}); ... }
// build:
return Padding(padding: CruSpace.mainPadding, child: Column(
  crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    DentalPageHeader(title: 'Title', subtitle: 'Status line', actions: [/* secondary..., one primary last */]),
    const SizedBox(height: CruSpace.cardGap),
    GlanceStrip(...),                      // 3–4 numbers that matter
    const SizedBox(height: CruSpace.cardGap),
    Row(children: [CruSegmentedControl(...), const Spacer(), SizedBox(width: 280, child: DentalSearchField(...))]),
    const SizedBox(height: CruSpace.cardGap),
    Expanded(child: CruCard(padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: items.isEmpty ? Center(child: DentalEmptyState(...)) : ListView(children: [...]))),
  ]));
```

A full-screen page (not a tab) is pushed with:

```dart
Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
    builder: (_) => Theme(data: Theme.of(context), child: const MyPage())));
```

### 1.7 Specialties and sub-logins

- **Model:** `lib/core/models/doctor_specialty.dart`.
  - `enum DoctorSpecialtyType { generalPhysician, cardiologist, pediatrician, dentist, dermatologist, orthopedic, gynecologist, psychiatrist, physiotherapy, homeopathy, oralRadiologist }`.
  - `DoctorSpecialty` fields: `type`, `label`, `shortLabel`, `tagline`, `icon`, `accentColor`, `gradientColors`, `demoEmail`, `demoPassword`, `quickActions`, and `parent` (the parent specialty type for a sub-login).
  - Helpers: `rootType`, `isUnder(type)`, `DoctorSpecialty.all` (top level only), `dentalSubspecialties`, `everything`, `subspecialtiesOf(type)`, `ofType(type)`, `fromString(raw)`.
- **Where the choice appears:** sub-logins show automatically under Dentist in sign-in (`SubspecialtyRow`), in onboarding, and in the specialty switcher ("Log in as" chips on the Dentist card). Adding an entry to `dentalSubspecialties` is enough for it to show up in all three.
- **Providers** (`lib/core/providers/specialty_provider.dart`):
  - `activeDoctorSpecialtyProvider` (a stream of `DoctorSpecialty`)
  - `isDentistProvider` (type == dentist)
  - `isOralRadiologistProvider`
  - Task F1 adds `isDentalClinicianProvider` and `activeDentalSubspecialtyProvider`.
- **Demo login:** `lib/core/services/demo_session_service.dart` → `_getDemoDoctorName` switches on the type. Add a case for every new type or it won't compile.

### 1.8 Common patterns

**PDF:**

```dart
import 'package:pdf/pdf.dart'; import 'package:pdf/widgets.dart' as pw; import 'package:printing/printing.dart';
final doc = pw.Document();
doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(36), build: (_) => [
  pw.Text('Title', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
  pw.TableHelper.fromTextArray(headers: ['A', 'B'], data: [['1', '2']]),
]));
await Printing.layoutPdf(name: 'File name', onLayout: (_) => doc.save());
// The default PDF font has no ₹. Write 'Rs' in PDFs.
```

**Clinic and doctor names:** `ref.read(doctorIdentityProvider).clinicName` and `.fullName` (both nullable), from `features/dashboard/data/providers/doctor_identity_provider.dart`.

**SMS:** `launchUrl(Uri(scheme: 'sms', path: phone, queryParameters: {'body': text}))` returns false when the computer has no SMS app. Show "No SMS app on this computer. Use WhatsApp instead."

**Email:** `launchUrl(Uri(scheme: 'mailto', path: email, queryParameters: {'subject': s, 'body': b}))`.

**Saving a file:** `final path = await FilePicker.saveFile(dialogTitle: '…', fileName: 'x.csv', bytes: bytes);`

**Opening a file with its default app:** `launchUrl(Uri.file(path))`.

**Charts:** draw small trend charts with a `CustomPainter`. Lines use `c.label` / `c.label3`, bars use `c.amber` at 35% alpha, and grid lines use `c.hairline`. Existing example: `_TrendPainter` in `perio_chart_screen.dart`.

### 1.9 Code style

- Short doc comments that say **why** or **what it's for**, e.g. `/// Recalls: who should come back.` No essays.
- Private widgets start with `_`. One feature goes in one folder, with files under about 600 lines (split big screens into files).
- UI copy is plain English, sentence case and short: "No recalls yet", "Save", "Add referral". Never shout ("SUBMIT!"), never use exclamation marks, and never say "Successfully".
- Handle loading: `value == null` means loading, so show `SkeletonCard` or `SizedBox`.
- Destructive actions ask first with `confirmDental`.
- All `TextEditingController`s and `FocusNode`s are disposed.
- After an `await`, check `if (!mounted) return;` (in State) or `if (!context.mounted) return;` before using `context`.
- Null-aware list elements are allowed: `[?maybeWidget]`. So are null-aware map entries: `{'k': ?maybeValue}`.

---

## Part 2: The tasks

Each task has the same layout:
- **Goal:** what it's for.
- **Give the model:** the Primer, this task, and these files.
- **Create / Change:** exact paths.
- **Data:** the record kind and its JSON shape.
- **Build:** screens, behaviour and edge cases.
- **Acceptance:** what you check in the app.
- **Human:** anything only you can do.

Task IDs: `F` foundations, `P` periodontics, `OP` orofacial pain, `E` endodontics, `PD` pediatric, `PA` pathology, `OM` oral medicine, `AN` anesthesiology, `PR` prosthodontics, `OR` orthodontics, `PH` public health, `OS` oral surgery, `R` radiology, `C` cloud.

---

## Phase F: Shared foundations (do these first, in order)

### F1 · Sub-login framework for dental specialists

**Goal.** Every dental specialist (Periodontist, Endodontist…) logs in "under Dentist". Specialists must get **all** the general dentist's screens (tooth chart, procedures, treatment plans, sterilization, recalls, clinical records) plus their own. Today several checks only let the plain "Dentist" type through, so a specialist would lose those screens. This task fixes that once and adds the hooks each specialty uses.

**Give the model:**
- `lib/core/models/doctor_specialty.dart`
- `lib/core/providers/specialty_provider.dart`
- `lib/features/shell/components/cru_sidebar.dart`
- `lib/features/patients/presentation/patient_details_view.dart`
- `lib/features/dashboard/presentation/dashboard_screen.dart`
- The search result from **Human** below.

**Change:**
1. `specialty_provider.dart`:
   - Change `isDentistProvider` so it means "treats dental patients": the Dentist family except the Oral & Maxillofacial Radiologist.
     ```dart
     /// Dentists and dental specialists who treat patients: the Dentist
     /// family except the Oral & Maxillofacial Radiologist (who reads scans).
     final isDentistProvider = Provider<bool>((ref) {
       final s = ref.watch(activeDoctorSpecialtyProvider).value;
       return s != null &&
           s.rootType == DoctorSpecialtyType.dentist &&
           s.type != DoctorSpecialtyType.oralRadiologist;
     });

     /// The dental specialty of this login (null for a general dentist and
     /// for other specialties). Specialty screens and cards key off this.
     final activeDentalSubspecialtyProvider = Provider<DoctorSpecialtyType?>((ref) {
       final s = ref.watch(activeDoctorSpecialtyProvider).value;
       return s != null && s.parent == DoctorSpecialtyType.dentist ? s.type : null;
     });
     ```
2. `patient_details_view.dart`: replace `final isDentist = specialty == DoctorSpecialtyType.dentist;` with `final isDentist = ref.watch(isDentistProvider);`. Keep the rest as it is.
3. `dashboard_screen.dart`: replace the `_isDentist` getter body (it checks for `'dent'` in the specialty text) with `ref.watch(isDentistProvider)`.
4. `lib/features/patients/presentation/patient_details.dart` around line 196 (mobile): replace `specialty.type == DoctorSpecialtyType.dentist` with `specialty.isUnder(DoctorSpecialtyType.dentist) && specialty.type != DoctorSpecialtyType.oralRadiologist`.
5. `cru_sidebar.dart`: add a `DoctorSpecialtyType? sub` parameter to `_groupsFor`, and call it with `sub: ref.watch(activeDentalSubspecialtyProvider)`. Add this at the end of the returned list:
   ```dart
   // Specialty pages for this dental login (each phase adds its own).
   if (specialtyNav(sub).isNotEmpty) _NavGroup(specialtyNavTitle(sub), specialtyNav(sub)),
   ```
   Put `specialtyNav` and `specialtyNavTitle` in the same file, above `_groupsFor`:
   ```dart
   /// Extra sidebar pages per dental specialty. Phases add cases here.
   List<_NavItem> specialtyNav(DoctorSpecialtyType? sub) => switch (sub) {
         _ => const [],
       };
   String specialtyNavTitle(DoctorSpecialtyType? sub) =>
       sub == null ? '' : DoctorSpecialty.ofType(sub).shortLabel;
   ```
6. **Create** `lib/features/dental/specialties/specialty_cards.dart`:
   ```dart
   /// Dashboard cards for the dental specialty of this login. Each phase adds
   /// a case; general dentists get none.
   List<Widget> dentalSpecialtyCards(DoctorSpecialtyType? sub, ValueChanged<int> onNavigate) =>
       switch (sub) {
         _ => const <Widget>[],
       };
   ```
   In `dashboard_screen.dart`, after the `DentalTodayCard` line in `left`, add:
   ```dart
   ...dentalSpecialtyCards(ref.watch(activeDentalSubspecialtyProvider), widget.onNavigateToTab),
   ```

**The sub-login template.** Each phase's step 1 fills this in:
1. `doctor_specialty.dart`:
   - Add the enum value (e.g. `periodontist`) at the **end** of `DoctorSpecialtyType`.
   - Add a const like this:
     ```dart
     static const _periodontist = DoctorSpecialty._(
       type: DoctorSpecialtyType.periodontist,
       parent: DoctorSpecialtyType.dentist,
       label: 'Periodontist',
       shortLabel: 'Perio',
       tagline: 'Gum Health, Perio Charting & Maintenance',
       icon: Icons.spa_outlined,
       accentColor: Color(0xFF0F766E),
       gradientColors: [Color(0xFFCCFBF1), Color(0xFF99F6E4), Color(0xFFE0F2FE)],
       demoEmail: 'perio@crudoc.com',
       demoPassword: 'demo1234',
       quickActions: ['Perio chart', 'Recalls', 'Staging', 'Root planing'],
     );
     ```
   - Add it to `dentalSubspecialties`.
   - In `fromString`, add a keyword check **before** the `'dent'` check, e.g. `if (lower.contains('periodont')) return _periodontist;`.
2. `demo_session_service.dart`: add a `case DoctorSpecialtyType.periodontist: return 'Dr. …';` (a neutral demo name).
3. `cru_sidebar.dart` `specialtyNav`: add the specialty's pages.
4. `specialty_cards.dart`: add the specialty's dashboard card.

**Acceptance:**
- A general dentist sees exactly what they saw before.
- The Radiologist login still has no chairside dental pages.
- The analyzer is clean.

**Human.** Before starting, run this and paste the output:

```
Get-ChildItem -Recurse lib -Filter *.dart | Select-String -Pattern "isDentistProvider|DoctorSpecialtyType.dentist|contains\('dent'\)" | Select-Object Path, LineNumber, Line
```

---

### F2 · Tooth numbering setting (FDI or Universal)

**Goal.** Each clinic chooses how tooth numbers are **shown**. Storage always stays FDI (`'36'`).

**Give the model:**
- `lib/features/dental/domain/dental_chart.dart`
- `lib/features/dental/records/dental_records_repo.dart`
- `lib/features/settings/presentation/desktop_settings_screen.dart`
- Every file from the Human search below.

**Create** `lib/features/dental/domain/tooth_numbering.dart`:

```dart
enum ToothNumbering { fdi, universal }

/// The label to show for an FDI tooth id.
///
/// Universal: permanent teeth run 1–32 from the upper right third molar
/// (18→1 … 11→8, 21→9 … 28→16, 38→17 … 31→24, 41→25 … 48→32). Primary
/// teeth run A–T (55→A … 51→E, 61→F … 65→J, 75→K … 71→O, 81→P … 85→T).
String toothLabel(String fdi, ToothNumbering n) { ... }

/// The clinic's choice, stored as a meta record (kind 'meta', data
/// {'what': 'numbering', 'value': 'fdi' | 'universal'}). Default FDI.
final toothNumberingProvider = FutureProvider<ToothNumbering>(...);
Future<void> setToothNumbering(WidgetRef ref, ToothNumbering n);
```

**Settings.** In `desktop_settings_screen.dart`, add `SettingsSection.dental('Dental', DentalIcons.tooth)`, shown only when `isDentistProvider` is true. Filter it the same way `radiology` is filtered for radiologists: the `sections:` list passed to `_SectionList`. The section has one card, "Tooth numbering", with a `CruSegmentedControl` (FDI, Universal) and a line explaining the difference. F3, P and PD tasks add rows to this section later.

**Change.** In every place a tooth id is **displayed** (not stored or looked up), wrap it: `Text(toothLabel(t, numbering))`, where `final numbering = ref.watch(toothNumberingProvider).value ?? ToothNumbering.fdi;`. Typical places:
- the 2D and 3D tooth charts (tooth number text and callouts)
- the tooth condition editor and tooth history sheet
- procedure rows
- treatment plan rows
- perio chart headers
- the endo list
- consents that list teeth
- radiology report tooth findings

Input fields that take a tooth number stay FDI. Their hint says "FDI".

**Acceptance.** Switch to Universal: the chart, perio chart and procedure lists show 1–32 and A–T. Switch back and FDI shows again. Nothing stored changes.

**Human.** Run this and paste the result. Then paste each listed file in turn, several per session if they're small:

```
Get-ChildItem -Recurse lib\features\dental,lib\features\patients,lib\features\radiology\presentation\reports -Filter *.dart | Select-String -Pattern "tooth|Tooth" | Select-String -Pattern "Text\(" | Select-Object Path, LineNumber, Line
```

---

### F3 · Referrals: sent and received

**Goal.** Refer a patient to a specialist (sent), or log a patient referred to you (received). Track status, attach files, produce a referral or reply letter, and send it by WhatsApp or email. Endodontics, Oral Surgery, Orthodontics, Pathology and Oral Medicine all use this.

**Give the model:**
- `lib/features/dental/records/dental_records_repo.dart`
- `lib/features/dental/records/recalls.dart` (as the style reference for a full screen with a glance strip, list rows and a popup menu)
- `lib/features/dental/records/dental_records_card.dart`
- `lib/features/shell/presentation/desktop_shell.dart`
- `lib/features/shell/components/cru_sidebar.dart`
- `lib/features/dashboard/presentation/dashboard_actions.dart`

**Create:**
- `lib/features/dental/referrals/referral_models.dart`: kinds, statuses and helpers.
- `lib/features/dental/referrals/referrals_screen.dart`: the sidebar tab.
- `lib/features/dental/referrals/referral_dialogs.dart`: the new/edit referral dialog, the contact picker, the contact dialog and the status menu.
- `lib/features/dental/referrals/referral_pdf.dart`: the letter PDFs.

**Data** (add to `RecKind`: `referral`, `referralContact`):

```jsonc
// referralContact  (patientId '')
{ "name": "Dr. Rao", "clinic": "", "specialty": "Endodontist", "phone": "", "email": "", "city": "", "notes": "" }
// referral  (patientId = the patient; recordedAt = created)
{ "direction": "out" | "in",
  "contactId": "...", "contactName": "Dr. Rao", "contactSpecialty": "Endodontist",
  "reason": "Retreatment 36", "teeth": ["36"], "findings": "…", "question": "…",
  "urgency": "routine" | "soon" | "urgent",
  "attachments": ["C:\\…\\dental\\referrals\\<id>\\iopa.jpg"],
  "status": "draft" | "sent" | "acknowledged" | "seen" | "completed" | "declined",
  "history": [ { "status": "sent", "at": 1790000000000, "note": "" } ],
  "reply": "text of the treatment summary (received referrals)" }
```

**Build:**
- **Sidebar tab "Referrals"** (next free `DesktopTab` index, in the Patients group, dentists only):
  - **Header:** "Referrals" with a status subtitle ("4 open · 1 urgent"). Actions: secondary "Contacts" (contact list dialog) and primary "New referral".
  - **Glance strip:** Open sent, Waiting for reply (sent or acknowledged), Received to see, Completed this month.
  - **Segments:** Sent · Received · Completed. Plus search.
  - **Rows:** date · patient · to or from · reason · urgency pill (urgent is amber; red is not used) · status pill · a WhatsApp capsule · a "…" menu.
    - The menu for sent referrals: Mark acknowledged, Mark seen, Mark completed, Declined, Letter (PDF), Delete.
    - For received referrals: Book visit (`PatientActions.newVisit`), Write reply, Mark completed.
  - **Empty state:** says what referrals are and has "New referral".
- **New/edit referral dialog** (`CruFormDialog`):
  - direction segments (I'm referring / Referred to me)
  - patient (`pickRadPatient` unless given)
  - contact picker with "Add contact"
  - reason, teeth (FDI, comma separated, validated with `DentalChart.isValid`), findings, question, urgency segments
  - attachments: "Add files" uses `FilePicker.pickFiles(allowMultiple: true)`. Copy each file into `getApplicationSupportDirectory()/dental/referrals/<referralId>/`. Show the list with open (`launchUrl(Uri.file(path))`) and remove.
  - Save creates a draft.
- **Send:**
  - "WhatsApp" builds the letter PDF, saves it to the referral folder, opens WhatsApp to the contact's phone with a short message (patient, reason, urgency, "letter attached"), and shows a "Show letter in folder" snackbar action. Sets status `sent` and adds a history entry.
  - "Email" is the same with `mailto:`.
- **Letter PDF:**
  - clinic and doctor header
  - To, Date, Re: patient (name, age, sex)
  - Reason, Teeth, Findings, Question, Urgency
  - "Attached: N files"
  - Signature line (doctor name)
  - For received referrals, a "Treatment summary" letter back to the referrer with the reply text.
- **Patient details:** add a "Referrals" row to `DentalRecordsCard`: "2 open · last to Dr. Rao". Tap opens the patient's referrals in a `DentalPanelDialog` with "New referral".
- **Shared case access (PLACEHOLDER).** At the bottom of the referral dialog show an inset note: "Sharing the case with the other doctor inside CruDoc needs the cloud: not connected yet." No button.

**Acceptance:**
- Create a contact, then a referral with 2 attachments, send it on WhatsApp (the letter opens and saves), and mark it seen then completed. The glance numbers update.
- Log a received referral, book the visit, write a reply, and print the reply letter.
- The patient card shows the referrals.

**Human:**
- Try WhatsApp on a real number.
- Check the letter wording and layout with a dentist.

---

## Phase P: Periodontics

### P1 · Periodontist sub-login

Follow the F1 template:
- **Enum and label:** `periodontist`, label "Periodontist", short label "Perio".
- **Sidebar group "Perio":** "Perio patients" (the P5 screen). Recalls is already in the Patients group.
- **Dashboard:** the P5 card.

**Give the model:** the files listed in F1's template, plus this list.

### P2 · Staging and grading (2017 AAP/EFP classification)

**Goal.** Turn a perio exam into a diagnosis: health, gingivitis, or periodontitis Stage I–IV, extent, Grade A–C. The periodontist confirms and edits it.

**Give the model:**
- `lib/features/dental/records/perio_chart_screen.dart` (it defines `PerioTooth`, `PerioSummary` and `perioSummaryOf`)
- `dental_records_repo.dart`

**Create** `lib/features/dental/records/perio_staging.dart` and add a "Stage and grade" secondary button to the perio chart header. It opens a `DentalPanelDialog`.

**Data:** kind `perioDx` (add to `RecKind`), recordedAt = the exam date:

```jsonc
{ "examId": "<perio record id>", "diagnosis": "periodontitis" | "gingivitis" | "health",
  "stage": 1-4, "extent": "localized" | "generalized" | "molarIncisor", "grade": "A" | "B" | "C",
  "inputs": { "boneLossPct": 25, "teethLostToPerio": 0, "age": 45, "smokingPerDay": 0,
              "diabetes": "none" | "controlled" | "uncontrolled", "hba1c": 6.4,
              "complexity": ["verticalDefect", "furcationII", "ridgeDefect", "mastDysfunction", "biteCollapse", "under20Teeth"] },
  "auto": { same fields as computed }, "overridden": true | false, "notes": "" }
```

**Rules** (implement exactly, and show the reasoning in the dialog):
- **Periodontitis vs. health or gingivitis (intact periodontium):**
  - Periodontitis if interdental CAL ≥ 2 mm at ≥ 2 non-adjacent teeth, or buccal/oral CAL ≥ 3 mm with PD > 3 mm at ≥ 2 teeth.
  - Otherwise, if bleeding ≥ 10%, it's gingivitis: localized for 10–30% and generalized above 30%.
  - Otherwise health.
- **Stage, from worst interdental CAL:** 1–2 mm → I; 3–4 mm → II; ≥ 5 mm → III. Radiographic bone loss (entered by the doctor) overrides it: < 15% → I, 15–33% → II, beyond the coronal third → III.
  - Tooth loss from perio: 1–4 teeth makes it at least III; ≥ 5 teeth makes it IV.
  - Complexity raises the stage: max PD ≥ 6 mm, vertical defect ≥ 3 mm, furcation II/III or a moderate ridge defect make it at least III. Masticatory dysfunction, secondary occlusal trauma (mobility ≥ 2), a severe ridge defect, bite collapse, or fewer than 20 teeth make it IV.
- **Extent:** localized if < 30% of teeth are involved (CAL ≥ 3 mm), otherwise generalized. "Molar/incisor pattern" is a manual choice.
- **Grade:** start at B.
  - It's A when bone loss % ÷ age < 0.25, and C when > 1.0.
  - Risk factors can only raise it: smoking < 10 per day → at least B, ≥ 10 → C; diabetes with HbA1c < 7 → at least B, ≥ 7 → C.
- The dialog shows the computed result, every input (editable), and a line per rule that fired ("Stage III: max PD 7 mm at 46"). "Save diagnosis" stores it. If the doctor changes the result, `overridden` becomes true.

**UI:**
- Left column: inputs (bone loss %, teeth lost, age prefilled from the patient, smoking chips, diabetes chips with HbA1c, complexity checkboxes).
- Right column: the result in large type ("Periodontitis · Stage III · Generalized · Grade B"), with the reasons listed below it.
- The perio chart header subtitle shows the saved diagnosis for the loaded exam.

**Acceptance.** A chart with max CAL 5 mm at 3 teeth, 28% bone loss, a 40-year-old non-smoker, gives Stage III, generalized, Grade B, with the reasons shown. Change the smoking input to ≥ 10 per day and it becomes Grade C.

**Human.** A periodontist should check the rules against the 2017 classification paper (Tonetti, Greenwell & Kornman 2018) before clinical use.

### P3 · Plaque index (O'Leary)

**Goal.** Record which tooth surfaces have plaque, and track hygiene over time.

**Give the model:** `perio_chart_screen.dart` and `dental_records_repo.dart`.

**Change:**
- Add a `CruSegmentedControl` at the top of the perio chart card: "Pockets · Plaque".
- In Plaque mode, show the same arches with 4 small squares per tooth (M, D, B, L). Clicking toggles plaque (filled `c.label`). Missing teeth are skipped.
- Show the score = surfaces with plaque ÷ (present teeth × 4) × 100, one decimal place, next to the other summary numbers.
- Store it in the same perio record: `data['plaque'] = {'16': [true, false, true, false], …}` (order M, D, B, L).
- The trend chart gets a third series, plaque %, as a dashed `c.label2` line.
- The PDF print adds a "Plaque" row per arch and the score.

**Acceptance.** Toggling surfaces updates the % live, it saves, the % appears in the history list and the trend, and it prints.

### P4 · Root planing by quadrant (SRP)

**Goal.** Plan and record non-surgical therapy by quadrant, then re-evaluate.

**Create** `lib/features/dental/records/srp_dialog.dart`, and add a row "Root planing" to `DentalRecordsCard` (dentists; all logins).

**Data:** kind `srp`, one record per course of therapy:

```jsonc
{ "quadrants": { "UR": {"status": "planned" | "done", "date": ms, "anaesthesia": "Lidocaine 2% 1 cartridge", "notes": ""},
                 "UL": {...}, "LL": {...}, "LR": {...} },
  "reevaluationDue": ms, "reevaluatedExamId": "" }
```

**Build:**
- A dialog with 4 quadrant tiles in a 2×2 grid laid out like the mouth. UR is top-left, which is correct from the dentist's view.
- Each tile shows its status and date. Tapping opens a small form: done date, anaesthesia, notes.
- When all planned quadrants are done, show "Re-evaluate on <done + 6 weeks>" with a button "Set recall". It creates a recall (kind `recall`, reason "Perio re-evaluation", due in 6 weeks, `status: 'pending'`).
- The card row shows "2 of 4 quadrants done" or "Re-evaluation due 12 Oct".

**Acceptance:**
- Plan all four, finish two: the card says 2 of 4.
- Finish all four and set the recall: it shows on the Recalls page.

### P5 · Perio patients page and dashboard card

**Goal.** A periodontist's worklist: who has active disease, who is due for maintenance.

**Create:**
- `lib/features/dental/specialties/perio/perio_patients_screen.dart`, the "Perio patients" tab from P1.
- `lib/features/dental/specialties/perio/perio_today_card.dart`.

**Build:**
- **The page's glance strip:**
  - patients charted
  - deep pockets: patients whose latest exam has sites ≥ 6 mm
  - bleeding ≥ 30%: patients whose latest exam is at or above it
  - maintenance due: open recalls whose reason contains "perio", due within 14 days or overdue
- **List:** one row per charted patient, from `clinicRecordsProvider(RecKind.perio)` grouped by patient using the newest exam.
  - Each row: name · last exam date · mean PD · bleeding % · sites ≥ 6 · the stage and grade if a `perioDx` exists · next recall date.
  - Segments: All · Active disease (stage III/IV or sites ≥ 6) · Maintenance due.
  - Tapping a row opens `PerioChartScreen(patient)`. Look the patient up in `patientsStreamProvider`.
- **Card:** three rows, like `DentalTodayCard`:
  - Maintenance due (count), which opens the Recalls tab
  - Active disease (count), which opens Perio patients
  - Exams this month (count)

**Acceptance.** The numbers match what you entered; the rows open the right chart.

### P6 · Patient perio report (plain language)

**Goal.** A one-page PDF the patient takes home: their gum health in plain words.

**Create** `lib/features/dental/records/perio_patient_report.dart`. Add a "Patient report" secondary button in the perio chart header.

**Content:**
- clinic header, patient, date
- "Your gum health": the diagnosis in plain words, e.g. "Gum disease (periodontitis), stage 2 of 4" with a short explanation
- "Bleeding gums": bleeding % with one line ("Healthy gums bleed at less than 10% of places")
- "Deep pockets": number of sites ≥ 5 mm
- "Plaque": plaque %
- a small upper/lower diagram with a coloured dot per tooth (grey healthy, amber pocket 4–5 mm, dark amber ≥ 6 mm)
- "What to do": brushing, cleaning between the teeth and the recall date, from the patient's recall
- a comparison with the previous exam ("Bleeding went from 42% to 18%")

**Acceptance.** It prints for a patient with 2 exams and shows the comparison.

**Human.** A periodontist checks the patient-facing wording.

---

## Phase OP: Orofacial Pain

### OP1 · Orofacial pain specialist sub-login

- **Enum and label:** `orofacialPain`, label "Orofacial Pain Specialist", short label "Pain".
- **Sidebar group "Pain":** "Pain patients" (OP7).
- **Dashboard:** the OP7 card.

### OP2 · DC/TMD Symptom Questionnaire (Axis I)

**Goal.** The official DC/TMD symptom questionnaire, whose answers point to which Axis I diagnoses to examine.

**Human, before starting.** Download from the INfORM / DC/TMD consortium site (rdc-tmdinternational.org, "DC/TMD Symptom Questionnaire", English). Paste the exact question text and answer options to the model. The instrument is free to use; keep the wording exact.

**Give the model:** `lib/features/dental/records/clinical_forms.dart` (the existing TMD screener pattern), `dental_records_repo.dart`, and the questionnaire text.

**Create** `lib/features/dental/specialties/pain/dc_tmd_forms.dart`: a stepper dialog (`DentalPanelDialog`, width `CruSize.formDialog`). Its sections follow the questionnaire: Pain, Headache, Jaw joint noises, Closed locking, Open locking.
- Answers are chips (Yes/No, or the listed options).
- Skip logic follows the form. For example, if "Pain in jaw, temple, in the ear, or in front of the ear" is No, skip the pain follow-ups.

**Data:** kind `dctmdSq`: `{ "answers": { "q1": "yes", "q2": {...} }, "flags": ["myalgia", "arthralgia", "headacheAttributed", "discDisplacement", "degenerative", "subluxation"] }`.

**Build.** After saving, show "Examine for:" with the flagged diagnoses, derived from the questionnaire's published decision rules. Store the flags. It's listed in the Pain and TMD dialog under the screener.

**Acceptance.** Answers with jaw pain changed by chewing flag myalgia or arthralgia to examine. A "No" to pain skips the pain follow-ups.

### OP3 · Axis II instruments: GCPS v2, JFLS-8, PHQ-4, OBC

**Human, before starting.** Download the official GCPS v2.0, JFLS-8, PHQ-4 and Oral Behaviors Checklist from the same site. Paste the wording.

**Create** `lib/features/dental/specialties/pain/axis2_forms.dart`: one dialog per instrument, with the same pattern as OP2.

**Scoring (implement exactly):**
- **GCPS v2:**
  - Characteristic Pain Intensity (CPI) = the mean of the current, worst and average pain items (0–10) × 10.
  - Disability points come from the interference items and disability days, as the scoring manual says.
  - Grade 0 = no pain. I = CPI < 50 with < 3 disability points. II = CPI ≥ 50 with < 3 points. III = 3–4 points. IV = 5–6 points.
- **JFLS-8:** the mean of the answered items (0–10). Show the score to one decimal place.
- **PHQ-4:** items 0–3. Anxiety (the first 2) ≥ 3 → "anxiety screen positive". Depression (the last 2) ≥ 3 → "depression screen positive". Total 0–12: 0–2 normal, 3–5 mild, 6–8 moderate, 9–12 severe.
- **OBC:** 21 items 0–4, summed. 0–16 normal, 17–24 some, 25+ high (flag in amber).

**Data:** kinds `gcps`, `jfls8`, `phq4`, `obc`, each `{ "answers": [...], "score": …, "grade"/"band": … }`.

**UI:** a new "Questionnaires" list in the Pain and TMD dialog: each instrument with its last score, date and "Take". Positive PHQ-4 results show an amber line: "Consider referral for psychological support."

**Acceptance:** each form scores correctly on a hand-worked example (write 2 examples per form in the task chat and check them).

### OP4 · Jaw movement tracker

**Create** `lib/features/dental/specialties/pain/jaw_movements.dart`, with a "Jaw movements" row in `DentalRecordsCard` (shown for all dentists).

**Data:** kind `jawRange`:

```jsonc
{ "painFreeOpening": 34, "maxUnassisted": 38, "maxAssisted": 42, "lateralRight": 8, "lateralLeft": 9,
  "protrusion": 7, "deviation": "none" | "corrected" | "uncorrectedRight" | "uncorrectedLeft",
  "sounds": {"rightClick": true, "leftClick": false, "rightCrepitus": false, "leftCrepitus": false},
  "painOnOpening": true, "notes": "" }
```

**Build:**
- A dialog with number fields in mm (tabular, `trailing: 'mm'`) and chips.
- A trend chart of max unassisted opening over visits, with a dashed reference line at 40 mm ("usual lower limit").
- The card row shows "Opening 38 mm (was 31)".

**Acceptance.** Three entries make a trend, and values under 40 show in amber.

### OP5 · Splint therapy tracker

**Data:** kind `splint`: `{ "type": "Stabilisation (Michigan)" | "Anterior repositioning" | "Soft" | "Other", "arch": "upper" | "lower", "delivered": ms, "adjustments": [{"date": ms, "note": ""}], "wearHours": 8, "outcome": "improving" | "no change" | "worse" | "", "status": "active" | "stopped" }`.

**Build:**
- A dialog listing the patient's splints and "New splint".
- Each splint shows its adjustments timeline, "Add adjustment", wear hours reported, outcome chips, and Stop.
- A card row "Splint".

**Acceptance.** Adding a splint with 2 adjustments shows them in date order.

### OP6 · Pain diary over WhatsApp

**Goal.** Ask the patient for a daily pain score; the doctor enters the replies.

**Build.**
- In the Pain and TMD dialog, add a "Send diary request" button. It opens WhatsApp (`PatientActions.whatsApp`) with this editable template: "Hello {name}, please reply once a day with your jaw pain from 0 (none) to 10 (worst) for the next {days} days."
- The existing score entry has a "Date" picker, so the doctor can back-date replies.
- The trend shows all scores.
- Placeholder, shown honestly as an inset note: "Automatic collection of WhatsApp replies needs the WhatsApp Business API: not connected yet."

### OP7 · Pain patients page and dashboard card

- **Page:**
  - patients with any `pain`/`tmd`/`gcps`/`jawRange` record
  - columns: last pain score · GCPS grade · opening mm · splint status
  - segments: All · High impact (GCPS III/IV) · Positive PHQ-4
- **Card:** screened this month, high impact, splints active.

---

## Phase E: Endodontics

### E1 · Endodontist sub-login

- **Enum and label:** `endodontist`, label "Endodontist", short label "Endo".
- **Sidebar group "Endo":** "Root canals" (the E4 page) and "Referrals" (from F3; move it here for this login if you like, but don't duplicate it).
- **Dashboard:** the E4 card.

### E2 · Multi-visit root canal stages

**Give the model:** `lib/features/dental/records/endo_dialog.dart` and `dental_records_repo.dart`.

**Change** `endo_dialog.dart`. Add a "Visits" section with a stage list per visit:
- **Stages:** Access and diagnosis → Cleaning and shaping → Intracanal medicament → Obturation → Final restoration.
- **Each visit:** date (picker), stage (chips), medicament (Calcium hydroxide, Triple antibiotic paste, Ledermix, Other), notes.
- **Data:** add `"visits": [{"date": ms, "stage": "shaping", "medicament": "Calcium hydroxide", "notes": ""}]` to the endo record.

**The endo list** shows a 5-dot progress stepper per tooth (done in `c.label`, pending in `c.inset`) and "Next: Obturation". A "Book next visit" capsule calls `PatientActions.newVisit`.

**Acceptance.** Add 2 visits and the stepper shows 2 of 5; the status becomes "Obturated" when an obturation visit exists. Keep that consistent with `obturatedOn`: set it automatically from the obturation visit.

### E3 · Periapical healing reviews (PAI)

**Goal.** Follow each treated tooth's periapical healing over time.

**Data:** add `"reviews": [{"date": ms, "pai": 1-5, "symptoms": false, "sinusTract": false, "tenderToPercussion": false, "notes": ""}]` to the endo record.

**Build:**
- A "Reviews" section in the endo dialog with "Add review": date, PAI chips 1–5 with their meanings, and symptom checkboxes.
  - PAI 1: normal periapical structures.
  - PAI 2: small changes in bone structure.
  - PAI 3: changes in bone structure with some mineral loss.
  - PAI 4: periodontitis with a well-defined radiolucent area.
  - PAI 5: severe periodontitis with exacerbating features.
- **Outcome** after ≥ 1 year from obturation:
  - "Healed": PAI ≤ 2, no symptoms.
  - "Healing": PAI decreasing, no symptoms.
  - "Not healed": PAI ≥ 3 at 4 years, or symptoms.
  - Show it as a pill (green, amber, amber).
- "Set review recall" creates recalls at 6 and 12 months after obturation, with reason "Root canal review".
- A small PAI trend per tooth: dots over time.

**Acceptance:** PAI 4 → 3 → 2 over a year with no symptoms reads "Healed".

### E4 · Root canals page and dashboard card

- **Page:** every endo record across patients (`clinicRecordsProvider(RecKind.endo)`).
  - Segments: In progress · Reviews due · Completed.
  - Rows: patient, tooth, stage stepper, next step, last visit date, outcome pill.
- **Card:** in progress (count), reviews due (from recalls with reason containing "root canal"), completed this month.

### E5 · Received referrals for endo

Uses F3 with direction "in". Add to the endo record an optional `"referralId"` link. When a received referral with teeth is marked "seen", offer "Start endo record for tooth 36", which opens the endo dialog prefilled. The reply letter pulls in the endo summary (diagnosis, canals and working lengths, obturation, the latest PAI).

**Acceptance.** Received referral → seen → endo record created → the reply letter includes the treatment summary.

---

## Phase PD: Pediatric Dentistry

### PD1 · Pediatric dentist sub-login

- **Enum and label:** `pediatricDentist`, label "Pediatric Dentist", short label "Pedo".
- **Sidebar group "Pedo":** "Children" (PD6).
- **Dashboard:** the PD6 card.

### PD2 · Eruption chart

**Goal.** For each child, record which teeth have erupted or exfoliated, and flag teeth that are late compared with normal ages.

**Create** `lib/features/dental/specialties/pedo/eruption_chart.dart`, with a "Eruption" row in `DentalRecordsCard` shown when the patient's age is under 16.

**Data:** kind `eruption`. One record per patient, updated in place:

```jsonc
{ "teeth": { "51": {"status": "exfoliated", "date": ms}, "11": {"status": "erupting", "date": ms}, … } }
// status: "notErupted" | "erupting" | "erupted" | "exfoliated" (primary only) | "missing"
```

**Normal ranges** (a table in code; a pediatric dentist must verify it):
- **Primary teeth, eruption in months:**
  - upper: A/E 8–12, B/D 9–13, C 16–22, first molar 13–19, second molar 25–33
  - lower: A 6–10, B 10–16, C 17–23, first molar 14–18, second molar 23–31
- **Permanent teeth, eruption in years:**
  - upper: central 7–8, lateral 8–9, canine 11–12, first premolar 10–11, second premolar 10–12, first molar 6–7, second molar 12–13, third 17–21
  - lower: central 6–7, lateral 7–8, canine 9–10, first premolar 10–12, second premolar 11–12, first molar 6–7, second molar 11–13, third 17–21

**Build:**
- Two rows of chips per arch: primary on top (55…65 / 85…75) and permanent below.
- Each chip shows the tooth label (F2) and its status colour: not erupted = inset, erupting = amber tint, erupted = green tint, exfoliated = grey struck through, missing = hairline outline.
- Clicking a chip cycles through the statuses and stamps today's date; right-click opens a menu with a date picker.
- Late flag: if the child's age is past the upper end of the range and the tooth isn't erupted, add an amber ring and list it under "Later than usual". Retained primary teeth (the permanent successor has erupted, the primary is still present) are listed under "Retained primary".

**Acceptance.** A 9-year-old with 11 not erupted is flagged late (the upper range ends at 8). Marking 51 exfoliated and 11 erupted clears the flag.

### PD3 · Caries risk assessment (ADA)

**Human, before starting.** Download the ADA Caries Risk Assessment forms (ages 0–6 and over 6) from ada.org. Paste the items with their category (Contributing conditions, General health conditions, Clinical conditions) and which column each answer counts toward (Low, Moderate, High).

**Create** `lib/features/dental/specialties/pedo/caries_risk.dart`, with a "Caries risk" row in `DentalRecordsCard` for all dentists.

**Rules:**
- The form version comes from the age: 0–6 or over 6.
- Each answer has a risk level. **Any** High answer → High. Otherwise any Moderate → Moderate. Otherwise Low.
- Suggested recall: High 3 months, Moderate 6 months, Low 6–12 months. A button "Set recall" creates it.

**Data:** kind `cariesRisk`: `{ "form": "0-6" | "over6", "answers": {...}, "risk": "low" | "moderate" | "high" }`.

**UI:** the form grouped by category, chip answers, and the result live at the top. High shows as an amber pill; red is not used.

### PD4 · Sealants and fluoride

**Data:**
- kind `sealant`: `{ "tooth": "36", "placed": ms, "material": "Resin" | "GIC", "reviews": [{"date": ms, "state": "retained" | "partial" | "lost"}] }`
- kind `fluoride`: `{ "product": "NaF varnish 5%", "date": ms, "notes": "" }`

**Build:**
- One dialog "Sealants and fluoride".
- Sealants: the permanent molars and premolars (the 6 and 7 teeth) as chips showing their state. "Due" suggestions: 6s from age 6 and 7s from age 12 if erupted (from PD2) and not sealed. "Add sealant" and "Review" per tooth.
- Fluoride: list with date and product, "Add application", and "Next due" 6 months after the last one (3 months if caries risk is High).
- A card row: "Sealed 4 of 4 · fluoride due 12 Oct".

### PD5 · Large text and icons mode

**Goal.** A calmer, bigger interface for chairside use with children.

**Build:**
- **Setting:** in F2's Settings → Dental section, a switch "Larger text and icons (chairside)". Store it as a meta record `{'what': 'largeMode', 'value': true}`.
- **Effect:** when on, `DesktopShell` wraps the **content area** (not the sidebar) in `MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.2)), child: content)`.
- Check that Patient details, the tooth chart and the records dialogs don't overflow at 1.2×. Fix any overflow with `Flexible`/`Expanded` or `maxLines`/ellipsis; don't shrink the text back.

**Acceptance.** Toggle it on and the content grows 20%, the sidebar stays the same, and there's no overflow stripe on Patient details or the records dialogs at 1366×768.

### PD6 · Children page and dashboard card

- **Page:**
  - patients under 16
  - columns: age · last Frankl rating · caries risk · sealants state · eruption flags count · next recall
  - segments: All · High caries risk · Eruption flags
- **Card:** children seen this month, high risk, sealants due.

---

## Phase PA: Oral & Maxillofacial Pathology

### PA1 · Oral pathologist sub-login

- **Enum and label:** `oralPathologist`, label "Oral & Maxillofacial Pathologist", short label "OMP".
- **Sidebar group "Pathology":** "Biopsies" (PA2).
- **Dashboard:** the PA6 card.

### PA2 · Biopsy log

**Create:**
- `lib/features/dental/specialties/pathology/biopsy_models.dart`
- `biopsies_screen.dart`
- `biopsy_dialog.dart`

**Data:** kind `biopsy`, recordedAt = the collection date:

```jsonc
{ "site": "Left lateral border of tongue", "teeth": [], "procedure": "incisional" | "excisional" | "punch" | "brush" | "FNAC",
  "clinicalDiagnosis": "…", "differentials": ["…"], "specimens": 1, "fixative": "10% formalin",
  "labContactId": "<referralContact id>", "labName": "…", "labRef": "",
  "status": "collected" | "sent" | "atLab" | "reported" | "reviewed" | "informed",
  "history": [{"status": "sent", "at": ms}], "expectedBy": ms,
  "report": {"date": ms, "gross": "", "microscopic": "", "diagnosis": "", "comment": "", "pdfPath": ""},
  "photos": [{"path": "…", "caption": ""}], "followUp": ms }
```

**Build.** A "Biopsies" tab:
- **Glance:** awaiting report, overdue (past `expectedBy`, amber), to review, to tell patient.
- **Segments:** Open · Reported · Closed. Plus search.
- **Rows:** date · patient · site · lab · status pill · days at lab.
- **Dialog:** all fields; the lab is chosen from F3's contacts, filtered to specialty "Lab" or anything.
  - "Mark sent" sets `expectedBy` to today + 7 days (editable).
  - "Attach report PDF" copies the file into `dental/biopsies/<id>/`.
  - Status buttons move it along.
  - "Tell patient" opens WhatsApp with a neutral template: "Your biopsy result is ready. Please book a visit to discuss it." Results are never sent by message.
- **Patient card row:** "Biopsies".

**Acceptance.** Create → sent → reported with a PDF → reviewed → informed. An overdue one turns amber.

### PA3 · Specimen label with QR code

**Human.** Run `flutter pub add barcode`. The `pdf` package draws barcodes, but the import needs the package listed.

**Build.** "Print label" in the biopsy dialog makes a PDF at 62×29 mm (`PdfPageFormat(62 * PdfPageFormat.mm, 29 * PdfPageFormat.mm)`) containing:
- the patient name, age and sex
- the site, date and specimen number
- `pw.BarcodeWidget(barcode: Barcode.qrCode(), data: biopsyId, width: 18 * PdfPageFormat.mm, height: 18 * PdfPageFormat.mm)`

It prints with `Printing.layoutPdf`.

### PA4 · Histopathology report (when you are the reporting pathologist)

**Build.** A "Write report" section in the biopsy dialog: gross, microscopic, special stains, diagnosis, comment, and a signature (name and qualification from Settings → Radiology signature, or the doctor's name). "Sign report" locks it and produces a PDF with the letterhead, patient, specimen details and sections, then sets the status to `reported`. Signed reports can take an addendum, never an edit.

**Acceptance.** A signed report is locked and its PDF prints; an addendum is appended with its date.

### PA5 · Slide and clinical photos

**Build.**
- "Add photos" (`FilePicker.pickFiles(type: FileType.image, allowMultiple: true)`) copies the files into the biopsy folder.
- The gallery grid shows thumbnails (`Image.file(File(path), cacheWidth: 400, fit: BoxFit.cover)`) with captions.
- Clicking opens a full-screen viewer with `InteractiveViewer` (pan and zoom, `maxScale: 8`), left/right arrows and the caption.
- Delete asks first.

This is simple viewing, not image processing.

### PA6 · Pathology dashboard card

Card: awaiting reports, overdue, to review.

---

## Phase OM: Oral Medicine

### OM1 · Oral medicine specialist sub-login

- **Enum and label:** `oralMedicine`, label "Oral Medicine Specialist", short label "OralMed".
- **Sidebar group "Oral medicine":** "Lesions" (OM3) and "Forms" (OM4).
- **Dashboard:** the OM6 card.

### OM2 · Oral medicine history

**Create** `lib/features/dental/specialties/oralmed/oralmed_history.dart`, with a card row "Oral medicine history" (all dentists).

**Data:** kind `omHistory`. One per patient, updated in place, with the history of changes kept in `versions`:

```jsonc
{ "systemic": ["Diabetes", "Hypertension", "Thyroid", "Asthma", "Epilepsy", "Bleeding disorder", "Hepatitis", "HIV", "Pregnancy", "Cancer / radiotherapy", "Other"],
  "systemicNotes": "", "medications": [{"name": "Metformin", "dose": "500 mg", "frequency": "BD"}],
  "allergies": [{"to": "Penicillin", "reaction": "Rash"}],
  "habits": {"tobacco": "none" | "smoked" | "chewed" | "both", "packYears": 0, "arecaNut": false, "alcohol": "none" | "occasional" | "regular"},
  "complaint": "", "duration": "", "versions": [{"at": ms, "summary": ""}] }
```

**Build:**
- A `CruFormDialog` with sections: Systemic conditions (chips plus notes), Medicines (a table-like list with add and remove rows), Allergies, Habits (chips), Chief complaint and duration.
- **Allergies show as red chips wherever the record card shows them.** This is patient safety.
- Tobacco or areca nut use flags an amber line "High-risk habits: screen for oral potentially malignant disorders."

### OM3 · Lesion tracker (photos, size, site, over time)

**Create:**
- `lib/features/dental/specialties/oralmed/lesions_screen.dart` (the tab)
- `lesion_dialog.dart`

**Data:** kind `lesion`. One record per lesion; each visit is an entry:

```jsonc
{ "site": "Right buccal mucosa", "siteCode": "buccalR", "type": "White patch" | "Red patch" | "Ulcer" | "Swelling" | "Pigmented" | "Other",
  "firstSeen": ms, "status": "active" | "resolved" | "biopsied",
  "entries": [{"date": ms, "lengthMm": 12, "widthMm": 8, "description": "", "photo": "path", "painVas": 2}],
  "biopsyId": "" }
```

**Build:**
- **Site picker:** a simple labelled grid of oral sites (Upper lip, Lower lip, Buccal mucosa L/R, Tongue dorsum, Tongue lateral L/R, Floor of mouth, Hard palate, Soft palate, Gingiva upper/lower, Retromolar L/R). Chips, no drawing.
- **Entries:** size in mm, a description, and an optional photo (file pick, copied into `dental/lesions/<id>/`).
- **Compare:** pick two entries to see the photos side by side with sizes and dates, plus the change in size (area = length × width, % change). A shrink shows green, growth amber.
- "Refer for biopsy" creates a biopsy (PA2) prefilled with the site and links `biopsyId`.
- **The Lesions tab:** all active lesions across patients, with growth flags (area up more than 20% since the previous entry, amber).

**Acceptance.** Three entries with photos compare correctly, growth is flagged, and the biopsy link opens the biopsy.

### OM4 · Custom form builder

**Goal.** The clinic designs its own forms (for example a burning mouth symptom form) and fills them in per patient.

**Create:**
- `lib/features/dental/specialties/forms/form_builder.dart`: the builder dialog.
- `form_fill.dart`: the fill dialog.
- `forms_screen.dart`: the tab listing form templates.

**Data:**
- kind `formTemplate` (patientId ''):
  ```jsonc
  { "name": "Burning mouth", "fields": [ {"id": "f1", "label": "Where does it burn?", "type": "text" | "longText" | "number" | "choice" | "multiChoice" | "yesNo" | "date" | "scale10", "options": ["Tongue", "Lips"], "required": true, "unit": "" } ] }
  ```
- kind `formResponse` (patientId = the patient): `{ "templateId": "…", "templateName": "…", "answers": {"f1": "…"} }`.

**Build:**
- **Builder:** add a field (type chips), set its label and options, reorder with up/down buttons, mark it required, delete it. There's a live preview on the right.
- **Fill:** fields render by type: `CruTextField`, chip wraps, a slider for scale10, the date picker. Required fields are validated. Save.
- **Patient card row "Forms":** the responses list plus "Fill a form" (pick a template).
- A response opens read-only, with "Edit" to change it (the edit is saved with an updated time).

**Acceptance.** Build a form with every field type, fill it, reopen it; required fields block saving.

### OM5 · Oral cancer screening checklist

**Data:** kind `ocScreen`: `{ "items": {"lips": "normal" | "abnormal", …}, "riskHabits": [...], "result": "no abnormality" | "refer", "notes": "" }`.

**Build:**
- A dialog listing the standard visual and tactile examination sites (extraoral: face, neck and lymph nodes; intraoral: lips, labial mucosa, buccal mucosa, gingiva, tongue (dorsum, ventral, lateral), floor of mouth, hard and soft palate, oropharynx). Each site has Normal / Abnormal chips; Abnormal asks for a note.
- The result is "No abnormality detected" or "Refer / biopsy". The latter offers to create a lesion (OM3).
- A card row with the last result.

### OM6 · Oral medicine dashboard card

Card: active lesions, lesions growing, screens this month.

**PLACEHOLDER: drug interaction checks.** In the OM2 medicines section, show an inset note: "Checking medicines against each other needs a drug database: not connected yet." No fake warnings.

---

## Phase AN: Dental Anesthesiology

### AN1 · Dental anesthesiologist sub-login

- **Enum and label:** `dentalAnesthesiologist`, label "Dental Anesthesiologist", short label "Anaesth".
- **Sidebar group "Anaesthesia":** "Sedation cases" (AN6).
- **Dashboard:** the AN6 card.

### AN2 · Pre-operative assessment

**Create** `lib/features/dental/specialties/anaesthesia/preop_dialog.dart`.

**Data:** kind `sedationCase`. One per sedation or GA episode, holding everything from AN2 to AN5:

```jsonc
{ "procedure": "Extraction 38, 48", "planned": "IV sedation" | "Oral sedation" | "Inhalation (N2O)" | "GA",
  "preop": { "asa": 1-5, "weightKg": 62, "heightCm": 168, "fastingSolidsHours": 6, "fastingClearHours": 2,
             "mallampati": 1-4, "airwayNotes": "", "allergies": "", "medications": "", "lastMeal": ms,
             "escort": true, "consentId": "" },
  "vitals": [ {"at": ms, "hr": 72, "sys": 120, "dia": 80, "spo2": 98, "rr": 14, "etco2": null, "sedation": 2, "note": ""} ],
  "drugs":  [ {"at": ms, "drug": "Midazolam", "dose": 2, "unit": "mg", "route": "IV", "note": ""} ],
  "recovery": { "aldrete": {"activity": 2, "respiration": 2, "circulation": 2, "consciousness": 2, "spo2": 2}, "dischargedAt": ms, "dischargedTo": "" },
  "status": "planned" | "inProgress" | "recovery" | "discharged" }
```

**Build:**
- The pre-op form: ASA I–V chips, each with its one-line meaning; weight/height with BMI shown; fasting hours; Mallampati I–IV chips; airway notes; allergies (red if present); medications; escort present; a consent link (it opens the consent from the existing records, or "New consent" with type surgical).
- **Warnings (amber):**
  - fasting solids < 6 h or clear fluids < 2 h
  - no escort for IV sedation or GA
  - ASA ≥ 3: "Consider hospital setting"
- "Start case" sets the status to inProgress and opens AN3.

### AN3 · Intra-operative vitals log

**Build:**
- A full-screen page `sedation_case_screen.dart` with a vitals entry row: HR, Sys, Dia, SpO₂, RR, EtCO₂ (optional), sedation score (Ramsay 1–6 chips) and a note. "Add" stamps the current time; there's an edit button per row.
- A vitals chart: HR and systolic/diastolic lines, and SpO₂ on a second axis 80–100.
- **Alerts (red, patient safety):** SpO₂ < 94, HR < 50 or > 120, systolic < 90 or > 180. Show them as a red banner at the top while the latest value is out of range.
- **Reminder** (not auto-logging): every 5 minutes an amber "Vitals due" pill appears if no entry has been made.

### AN4 · Drug and dose log with local anaesthetic maximum-dose calculator

**Build:**
- **Drug entry:** drug (a common-list chip wrap plus free text), dose, unit, route, time (defaults to now).
- **Running totals:** summed per drug.
- **Local anaesthetic calculator** (patient weight from AN2). For each LA: the max dose in mg, the cartridges so far, and the cartridges left. Formula: mg per cartridge = concentration % × 10 × volume in ml. Defaults to be checked by the clinician:

| Anaesthetic | Max mg/kg | Absolute max | Typical cartridge |
|---|---|---|---|
| Lidocaine 2% + adrenaline | 4.4 | 300 mg | 1.8 ml = 36 mg |
| Articaine 4% + adrenaline | 7.0 | 500 mg | 1.7 ml = 68 mg |
| Mepivacaine 3% plain | 4.4 | 300 mg | 1.8 ml = 54 mg |
| Prilocaine 4% | 8.0 | 600 mg | 1.8 ml = 72 mg |
| Bupivacaine 0.5% + adrenaline | 1.3 | 90 mg | 1.8 ml = 9 mg |

- Totals over 80% of the maximum show amber; over 100% show red, which is patient safety.
- The table of values sits in one const list so the clinic can review it. Show "Check against your local formulary" under the calculator.

### AN5 · Recovery and discharge (modified Aldrete score)

**Build:**
- Five items (activity, respiration, circulation, consciousness, SpO₂), each 0–2, with plain descriptions.
- The total is shown; ≥ 9 enables "Discharge".
- Discharge records the time and "discharged to" (the escort's name), then offers post-op instructions over WhatsApp (an editable template).

### AN6 · Sedation cases page, card and printable record

- **Page:** cases by status: Planned · In progress · Recovery · Discharged.
- **Card:** today's cases, in recovery, discharged today.
- **Print:** a PDF sedation record with the pre-op table, vitals table and chart snapshot (a simple table is fine), drugs with totals, Aldrete, discharge, and signature.

### AN7 · PLACEHOLDER: Bluetooth monitors

In the case page header, add a secondary "Connect monitor" button. It opens an honest dialog: "Pairing a Bluetooth pulse oximeter or BP monitor to log vitals automatically isn't built yet. Enter readings by hand for now." List the device types it will support. No fake pairing.

### AN8 · Emergency protocol cards

**Human.** Provide the clinic's approved protocols: anaphylaxis, syncope, hypoglycaemia, asthma, seizure, chest pain, local anaesthetic toxicity, airway obstruction. Use your national guidelines (in India, for example, the Indian Resuscitation Council or your institution's), checked by a clinician. Paste the steps and doses.

**Build.**
- A header button "Emergency" in the case page, plus a sidebar entry under Anaesthesia. It opens a full-screen, large-text list of protocols.
- Each protocol is a card with numbered steps and drug doses **exactly as supplied**, plus a one-tap "Start timer" (a count-up timer at the top) and "Log to case" (adds a note row to the vitals log).

---

## Phase PR: Prosthodontics

### PR1 · Prosthodontist sub-login

- **Enum and label:** `prosthodontist`, label "Prosthodontist", short label "Prostho".
- **Sidebar group "Prostho":** "Lab cases" (PR3).
- **Dashboard:** the PR7 card.

### PR2 · Lab partners

Reuse F3 contacts with specialty "Dental lab". Add a "Standard turnaround (days)" field to the contact data (`turnaroundDays`). Add a "Labs" filter in the contacts dialog.

### PR3 · Lab prescription and case pipeline

**Create:**
- `lib/features/dental/specialties/prostho/lab_cases_screen.dart`
- `lab_case_dialog.dart`
- `lab_rx_pdf.dart`

**Data:** kind `labCase`:

```jsonc
{ "labContactId": "…", "labName": "…", "type": "Crown" | "Bridge" | "Veneer" | "Inlay/Onlay" | "Implant crown" | "Complete denture" | "Partial denture" | "Night guard" | "Other",
  "teeth": ["36"], "material": "Zirconia" | "E.max" | "PFM" | "Metal" | "Acrylic" | "Other", "shade": "A2", "shadeSystem": "VITA classical",
  "margin": "Chamfer" | "Shoulder" | "Feather", "notes": "", "due": ms,
  "stage": "scanned" | "sent" | "design" | "milling" | "qc" | "shipped" | "received" | "fitted" | "remake",
  "history": [{"stage": "sent", "at": ms, "note": ""}],
  "files": [{"path": "…", "kind": "scan" | "photo" | "design" | "other", "name": "…"}] }
```

**Build:**
- **Tab "Lab cases":**
  - Glance: at lab, due this week, overdue (amber), received to fit.
  - View toggle: **List · Board**. The board has columns per stage and cards you can drag between columns (use `Draggable`/`DragTarget`). Stage changes add to the history.
- **Dialog:** all fields; teeth use FDI with the F2 display; a shade chip wrap (A1–D4 plus a custom entry); due defaults to today + the lab's turnaround.
- **Files:** "Add files" copies into `dental/labcases/<id>/`; open and remove.
- **Messages:**
  - "Send to lab" makes the Rx PDF and opens WhatsApp or email to the lab.
  - When the stage becomes "received", offer to message the patient: "Your crown is ready. Please book a visit to fit it."
- **Rx PDF:** clinic, lab, patient (name, age), case type, teeth, material, shade, margin, notes, due date, signature.
- **Patient card row:** "Lab cases".

**Acceptance.** Create a case → send (the PDF opens) → drag it through the board → received → fitted. The history keeps the order and overdue cases show amber.

### PR4 · PLACEHOLDER: 3D scan viewer (STL, PLY, OBJ)

**Build.**
- In the lab case files list, `.stl`/`.ply`/`.obj` files show a "3D" chip.
- Opening one shows a page `scan_viewer_placeholder.dart` with the file name, size and, for STL, the **triangle count** (binary STL: a 4-byte little-endian count after the 80-byte header; ASCII: count the lines containing `facet normal`).
- It also shows this note: "3D view of scans isn't built yet. Open the file in your CAD or lab software." There's a button "Open with default app" (`launchUrl(Uri.file(path))`).

No rendering.

### PR5 · Export case for the lab (exocad / 3Shape)

**Build.** "Export case" makes a ZIP (package `archive`, already present) containing all case files plus `order.json` (the case data) and `order.pdf` (the Rx). It saves with `FilePicker.saveFile(fileName: 'Case_<patient>_<date>.zip', bytes: zipBytes)`.

The dialog note says labs import this manually. Direct exocad/3Shape integration: "not connected yet".

### PR6 · Denture stage tracker

**Data:** kind `denture`: `{ "arch": "upper" | "lower" | "both", "type": "complete" | "partial", "stages": [{"stage": "Primary impression" | "Secondary impression" | "Jaw relation" | "Try-in" | "Insertion" | "Review", "date": ms, "notes": ""}], "labCaseId": "" }`.

**Build.** A dialog with a vertical stepper of the stages. Tapping a stage records its date and notes. "Link lab case" picks a PR3 case. A card row: "Denture: Try-in done 12 Sep".

### PR7 · Prostho dashboard card

Card: at lab, overdue, to fit this week.

---

## Phase OR: Orthodontics

### OR1 · Orthodontist sub-login

- **Enum and label:** `orthodontist`, label "Orthodontist", short label "Ortho".
- **Sidebar group "Ortho":** "Ortho patients" (OR6).
- **Dashboard:** the OR6 card.

**Important:** `fromString` must check `'orthodont'` **before** the existing `'ortho'` keyword (which maps to Orthopedic).

### OR2 · Treatment and appliance tracker

**Create** `lib/features/dental/specialties/ortho/ortho_case_dialog.dart`.

**Data:** kind `orthoCase`:

```jsonc
{ "appliance": "Fixed (MBT 0.022)" | "Fixed (Roth)" | "Clear aligners" | "Removable" | "Functional" | "Other",
  "start": ms, "estimatedMonths": 18, "aligners": {"total": 30, "current": 12, "changeEveryDays": 10},
  "visits": [{"date": ms, "archwireUpper": "0.016 NiTi", "archwireLower": "0.016 NiTi", "elastics": "Class II 3/16 medium",
              "procedures": ["Bond 17"], "notes": "", "photoSetId": ""}],
  "phase": "leveling" | "working" | "finishing" | "retention", "debondDate": ms, "retainers": {"upper": "Essix", "lower": "Bonded 3-3"} }
```

**Build:**
- A dialog with a progress bar: months elapsed out of the estimate, or aligner current out of total.
- A visits timeline, newest first, with "Add visit". Wires are chips from a standard list plus free text.
- Phase chips.
- **Aligners:** "Next aligner change on <date>" and a WhatsApp reminder template to the patient.
- **Retention:** retainer types, and "Set retention recall" (3, 6 and 12 months).
- A card row "Ortho": "Aligner 12 of 30" or "Working phase · 9 of 18 months".

### OR3 · Standard photo series

**Create** `ortho_photos.dart`.

**Data:** kind `photoSet`: `{ "label": "Start" | "Progress" | "Debond" | custom, "photos": {"frontal": path, "smile": path, "profile": path, "intraFrontal": path, "intraRight": path, "intraLeft": path, "occlusalUpper": path, "occlusalLower": path} }`.

**Build:**
- A grid of 8 slots with silhouette labels. Click a slot to pick a file (copied into `dental/ortho/<patientId>/<setId>/`); replace or remove.
- The completion count "6 of 8".
- Sets are listed by date.

### OR4 · Before/after slider

**Build.**
- Pick two photo sets and one view (for example "frontal").
- A single image area shows the "after" photo, with the "before" photo clipped by a vertical divider you drag (`ClipRect` + `Align(widthFactor:)` or a `CustomClipper`).
- Labels "Before · date" and "After · date".
- "Export" renders side by side to PNG (a `RepaintBoundary` → `toImage` → PNG) and saves it via `FilePicker.saveFile`.

Simple image compositing only.

### OR5 · PLACEHOLDERS: ceph superimposition and 3D scans

- **Ceph superimposition:** in the ceph tracing screen (radiology), a disabled "Superimpose" item with the note "Superimposing two tracings isn't built yet."
- **3D model scans:** use PR4's placeholder viewer.

### OR6 · Ortho patients page and card

- **Page:** active cases with phase, progress, next visit and last wire. Segments: Active · Retention · Finished.
- **Card:** active, visits this week, aligner changes due, retention recalls due.

**Wear-time compliance (PLACEHOLDER):** "Patients logging aligner wear needs the patient app: not connected yet."

---

## Phase PH: Public Health Dentistry

### PH1 · Public health dentist sub-login

- **Enum and label:** `publicHealthDentist`, label "Public Health Dentist", short label "PHD".
- **Sidebar group "Public health":** "Camps" (PH2) and "Population" (PH4).
- **Dashboard:** the PH6 card.

### PH2 · Camps and quick registration (works offline)

**Create:**
- `lib/features/dental/specialties/publichealth/camps_screen.dart`
- `camp_dialog.dart`
- `screening_form.dart`

**Data:**
- kind `camp` (patientId ''): `{ "name": "School camp, Kothrud", "date": ms, "place": "", "type": "School" | "Village" | "Workplace" | "Elderly" | "Other", "team": ["Dr. …"], "notes": "", "status": "planned" | "done" }`
- kind `screening` (patientId = the created patient): `{ "campId": "…", "dmft": {"d": 2, "m": 0, "f": 1}, "dmftPrimary": {"d": 3, "m": 0, "f": 0}, "ohiS": 1.2, "fluorosis": "none" | "questionable" | "very mild" | "mild" | "moderate" | "severe", "needs": ["Filling", "Extraction", "Scaling", "Referral"], "referred": true }`

**Build:**
- **Camps tab:** planned and done camps, "New camp".
- **Camp page:** the registrations list plus **quick registration**.
  - A compact single-row form: name, age, sex, phone (optional), then **Enter** saves and clears for the next person.
  - It creates a real patient with the existing `patientRepositoryProvider`'s `createPatient(Patient(...))`. Date of birth is estimated from age (1 July of the birth year) and flagged "age estimated" in the notes.
  - Keyboard-first: Tab and Enter move through it.
- **Screening form per person:** DMFT (D, M, F counters, with the total shown), primary dmft (for age < 12), OHI-S (debris and calculus index entry → score), fluorosis (Dean's index chips), treatment needs chips, and a "Refer to clinic" toggle.
- Everything is local, so it works without internet.

**Acceptance.** Registering 10 people takes about a minute with the keyboard; the screenings save; the camp shows the counts.

### PH3 · DMFT from the tooth chart

**Build.** A helper `computeDmft(List<ToothChartEntryModel>)` in `lib/features/dental/specialties/publichealth/dmft.dart`:
- **D** = teeth with the caries condition
- **M** = missing due to caries (missing condition, excluding teeth marked "not erupted")
- **F** = restored or filled, with no caries

Use it to prefill the screening when a camp patient already has a tooth chart.

### PH4 · Population dashboard

**Create** `population_screen.dart`.

**Build.**
- **Filters:** camp (All or one), date range, age group (0–5, 6–12, 13–18, 19–34, 35–59, 60+), sex.
- **Charts** (`CustomPainter` bars; bars in `c.label2`, the highlighted group in `c.label`):
  - caries prevalence by age group (% with D + M + F > 0)
  - mean DMFT by age group
  - treatment needs breakdown
  - sex and age distribution
  - procedures done in the clinic (from `procedure_log_entries` grouped by name, top 10)
- Every chart shows its n. Empty data shows "No screenings in this range", never zeros pretending to be data.

### PH5 · CSV export and reports

**Build:**
- "Export CSV" writes one row per screening (camp, date, age, sex, D, M, F, dmft, OHI-S, fluorosis, needs, referred) with a header row, UTF-8. Save with `FilePicker.saveFile(fileName: 'screenings.csv', bytes: utf8.encode(csv))`. Quote fields containing commas.
- "Camp summary PDF": camp details, the number screened, the prevalence, mean DMFT, needs and referrals, a table by age group, and the team.
- "Report for NGO / government": the same data in their required table layout. **Human:** paste the template the funding body requires, and the model maps the fields onto it.

### PH6 · Public health dashboard card

Card: camps this month, people screened, referrals to follow up (referred = true, with no clinic visit since).

---

## Phase OS: Oral & Maxillofacial Surgery

### OS1 · Oral surgeon sub-login

- **Enum and label:** `oralSurgeon`, label "Oral & Maxillofacial Surgeon", short label "OMFS".
- **Sidebar group "Surgery":** "Surgeries" (OS5) and "Implants" (OS3).
- **Dashboard:** the OS5 card.

### OS2 · Operation notes

**Create** `lib/features/dental/specialties/surgery/op_note_dialog.dart`.

**Data:** kind `opNote`: `{ "procedure": "Surgical removal of 38", "teeth": ["38"], "anaesthesia": "LA: Articaine 4% 1.7 ml IANB" | "IV sedation" | "GA", "incision": "", "flap": "", "boneRemoval": "", "sectioning": "", "closure": "Vicryl 3-0, 3 sutures", "haemostasis": "", "complications": "none", "specimen": false, "biopsyId": "", "checklistId": "", "duration": 35, "surgeon": "", "assistant": "" }`.

**Build:**
- **Templates** (a picker at the top that pre-fills the fields; editable): surgical extraction, impacted third molar, alveoloplasty, frenectomy, cyst enucleation, implant placement, incision and drainage.
- **Links:** the WHO checklist (existing) and "Specimen sent", which creates a PA2 biopsy.
- Print a PDF op note.

### OS3 · Implant registry

**Data:** kind `implant`: `{ "site": "36", "brand": "", "system": "", "diameter": 4.3, "length": 10, "lot": "", "ref": "", "placed": ms, "torqueNcm": 35, "isq": 72, "boneGraft": "", "membrane": "", "healing": "submerged" | "transmucosal" | "immediate load", "abutment": "", "restoredOn": ms, "status": "osseointegrating" | "restored" | "failed" | "removed" }`.

**Build:**
- A dialog for placing or editing: diameter chips 3.0–6.0, length chips 6–16, lot/REF fields, torque/ISQ numbers.
- **Warnings:** torque < 20 Ncm (amber, "Consider delayed loading"); ISQ < 60 (amber).
- "Set review recall" creates recalls at 3 months (restoration) and 12 months (review).
- **Tab "Implants":** all implants with the brand/lot search. It's useful for recalls on a lot.
- **Patient card row:** "Implants: 2 (36, 46)".

### OS4 · Post-op instruction library

**Data:** kind `postOpTemplate` (patientId ''): `{ "name": "After extraction", "text": "…" }`.

**Build:** a library dialog to add, edit or delete templates. The seeds are 4 templates: extraction, third molar surgery, implant, biopsy. **Human:** approve the wording.

"Send" picks a template and patient, then opens WhatsApp with the text. It's used from the op note ("Send instructions").

### OS5 · Surgeries page, card and CBCT planning placeholder

- **Page:** op notes by date, with a filter by procedure.
- **Card:** surgeries this week, implants awaiting restoration, reviews due.
- **PLACEHOLDER: CBCT planning.** "Plan implant on CBCT" opens the existing CBCT 3D placeholder page (`openRadCbct3d` in `lib/features/radiology/open_study.dart`) when the patient has a CBCT study. Otherwise it shows "Implant planning on CBCT isn't built yet."

---

## Phase R: Radiology leftovers

### R1 · Denoise filter

**Give the model:**
- `lib/features/radiology/viewer_plus/image_filters.dart`
- `lib/features/radiology/viewer/side_panel.dart` (the Adjust tab)

**Change.** Add `denoise` (0 = off, 1 = light 3×3, 2 = strong 5×5) to `RadFilterSettings` (JSON and copyWith). Apply a **median** filter on the Float32 values inside `applyValueFilters`, before sharpen and CLAHE, in the same isolate. Add a "Noise reduction" segmented control (Off · Light · Strong) to the Adjust tab. `changesValues` must include it.

**Acceptance.** Strong visibly smooths a noisy IOPA; turning it off restores the original; it's remembered per study type like the other filters.

### R2 · DICOMweb client (needs a PACS to test)

**Human, before starting.**
- Install Orthanc for Windows (orthanc-server.com), enable its DICOMweb plugin, and upload a few test studies.
- Note the address, for example `http://localhost:8042/dicom-web`.
- The PACS password or token is stored with `flutter_secure_storage` (already a dependency).

**Give the model:**
- `lib/features/radiology/presentation/pacs_dialogs.dart`
- `lib/features/radiology/data/radiology_models.dart`
- `lib/features/radiology/imaging/rad_import.dart`

**Create** `lib/features/radiology/pacs/dicomweb_client.dart`, using the `http` package (already present):
- **QIDO-RS:** `GET {base}/studies?PatientName=…&PatientID=…&StudyDate=YYYYMMDD-YYYYMMDD&ModalitiesInStudy=CT&includefield=all`, `Accept: application/dicom+json`. Parse the DICOM JSON: the tag keys like `00100010` hold `{"vr": "PN", "Value": [{"Alphabetic": "…"}]}`.
- **WADO-RS:** download a study as multipart: `GET {base}/studies/{uid}`, `Accept: multipart/related; type="application/dicom"`. Split the parts on the boundary into `.dcm` files in a temp folder, then feed them to the existing `scanForImport`, then the study form.
- **STOW-RS (send):** `POST {base}/studies` with `multipart/related; type="application/dicom"`.
- **Auth:** none, basic (username + password from secure storage), or bearer.

**Change** `pacs_dialogs.dart`:
- Replace the "not connected" states with real calls: Test connection = QIDO `studies?limit=1`; Search shows results; Download imports.
- Errors show plainly ("Couldn't reach the PACS: <reason>").
- The scanner receiver (C-STORE) stays a placeholder.

**Acceptance.** Search for a known patient, download the study, and it appears on the worklist.

### R3 · AI provider adapter (keeps "no key" honest)

**Create** `lib/features/radiology/ai/rad_ai.dart`:

```dart
abstract class RadAiProvider {
  bool get connected;
  Future<List<RadAiFinding>> secondRead(Uint8List deidentifiedPng, {required String modality});
}
class RadAiFinding { String label; double confidence; Rect? box; /* image pixels */ String tooth; }
class NoAiProvider implements RadAiProvider { connected => false; secondRead => throw StateError('No AI key connected'); }
final radAiProviderProvider = Provider<RadAiProvider>((ref) => NoAiProvider());
```

Wire the existing AI panels (`viewer_plus/ai/ai_panels.dart`) to read `connected` from this provider instead of assuming it's false. Nothing else changes until you choose a provider.

**Human:** choose the provider and key later (for example Firebase AI / Gemini, already a dependency). Only then write a `GeminiRadAiProvider`, with de-identification (strip DICOM tags, send pixels only) and a review-before-use flow.

### R4 · PLACEHOLDERS that stay placeholders

- the CBCT 3D viewer
- MPR / crosshair / slab
- JPEG 2000 / JPEG-LS decoding
- the C-STORE receiver

These are already honest placeholders; leave them.

---

## Phase C: Cloud and infrastructure (only after your decisions)

**Decisions you must make first, one line each:**
1. Firestore collections, or keep local and sync later?
2. Where images live (S3 bucket and region, or Firebase Storage)?
3. Orthanc hosting (AWS EC2 with Docker, or none)?
4. Per-clinic access rules and roles (doctor, receptionist, radiologist)?
5. Data protection: DPDP consent text and retention periods.

**When decided, the tasks are:**
- **C1 · Sync layer for `dental_records` and `radiology_docs`:** a Firestore mirror keyed by clinic, last-write-wins on `updatedAt`, and an offline queue. Follow the existing `lib/core/services/firestore_sync_service.dart` pattern. Give the model that file.
- **C2 · Security rules** for the new collections: clinic scoping, and doctors only for clinical kinds.
- **C3 · Image upload to storage** with the path `/{clinicId}/{patientId}/imaging/{studyId}/...` plus a thumbnail. Keep the local copy as a cache.
- **C4 · Shared case access for referrals (F3):** a referral shares a read-only snapshot with the other doctor's clinic. This replaces the F3 placeholder.
- **C5 · Secure report links (Radiology):** a signed URL with an expiry. This replaces the "Cloud not connected yet" button.

Each needs its own detailed spec once the decisions are made. Don't start them before.

---

## Appendix A · Acceptance run-through after each phase

1. Run `flutter analyze` on the phase's folders. No errors or warnings.
2. Run `flutter run -d windows`.
3. Log in as the phase's specialty (sign-in: pick Dentist, then the specialty chip; or use the specialty switcher's Dentist card, "Log in as").
4. Check the sidebar shows the specialty group and nothing is duplicated.
5. Check the dashboard shows the specialty card, with correct numbers after you add data.
6. Check Patient details (records card): each new row opens its dialog, saves, and reopens with the data.
7. Go through each task's Acceptance list.
8. Switch to General dentist: the specialty pages disappear and everything else still works.
9. Switch to Radiologist: no chairside dental pages appear.
10. Switch Day/Evening appearance: nothing is unreadable.
11. Resize to 1366×768: no overflow stripes.
12. Commit.

## Appendix B · Troubleshooting (errors models often cause)

| Error | Fix |
|---|---|
| `The getter 'platform' isn't defined for the type 'FilePicker'` | file_picker v11 is static: use `FilePicker.pickFiles(...)`, not `FilePicker.platform.pickFiles` |
| `An element in a constant set can't override '=='` (with `LogicalKeyboardKey`) | Make it `final` instead of `const`, or compare `keyId`s |
| `Undefined name` for a widget like `CruSwitch` | It doesn't exist. Use Flutter's `Switch(activeColor: c.label)` or `DentalChoiceChip` |
| `The method 'toothName' isn't defined for 'DentalChart'` | It's `DentalChart.name(tooth)` |
| `Can't use 'ref' after the widget was disposed` | Don't save in `dispose()`. Save on back with `PopScope(onPopInvokedWithResult: …)`, or debounce while editing |
| `The argument type 'X?' can't be assigned to 'X'` inside a `where`/`if` | Null-check first, or use `!` only after a check on the same variable |
| `Missing case clause for DoctorSpecialtyType.<new>` | Add the new type to every `switch`: `demo_session_service.dart` `_getDemoDoctorName` is the usual one |
| RenderFlex overflowed | Wrap text in `Flexible`/`Expanded` with `maxLines: 1, overflow: TextOverflow.ellipsis` |
| Build: `Cannot open include file … flutter_secure_storage_windows_plugin.h` | The path is too long. Build from a shorter folder or `subst R:` (0.4 item 5) |
| `firebase_options.dart` missing | Copy it from the main folder (it isn't in git) |
| `PathExistsException … sqlite3.dll` | Two `flutter test` runs in one folder: run one at a time |
| Riverpod: `StateProvider` not found | `import 'package:flutter_riverpod/legacy.dart';` |
| A switch over a String enum name misses a value | Use `values.firstWhere((e) => e.name == raw, orElse: () => default)` |

## Appendix C · Clinical content that needs a dentist's review before real use

| Where | What to verify |
|---|---|
| P2 | 2017 AAP/EFP staging and grading thresholds |
| P6 | Patient-facing perio wording |
| OP2–OP3 | Exact DC/TMD wording and scoring (from the official manual) |
| E3 | PAI descriptions and healing outcome criteria (ESE guidelines) |
| PD2 | Eruption age ranges |
| PD3 | ADA caries risk items and thresholds |
| OM2 / OM5 | High-risk habit guidance, oral cancer screening sites |
| AN2 | Fasting thresholds, ASA wording |
| AN4 | Local anaesthetic maximum doses and cartridge contents |
| AN5 | Modified Aldrete criteria |
| AN8 | Emergency protocols and drug doses (must come from your approved source) |
| OS3 | Torque and ISQ warning thresholds |
| OS4, E (post-op), consents | Instruction and consent wording (legal and clinical) |
| Radiology templates and phrases | Report wording already seeded in the app |
| Recalls | Default recall intervals |

## Appendix D · Map of what already exists (so nobody rebuilds it)

```
lib/core/models/doctor_specialty.dart            Dentist + Oral & Maxillofacial Radiologist sub-login
lib/core/widgets/subspecialty_row.dart           "General / <sub-specialty>" chooser used at sign-in and onboarding
lib/features/shell/components/specialty_switcher_dialog.dart  "Log in as" chips on the Dentist card
lib/features/dental/records/
  dental_records_repo.dart    JSON record store, RecKind, providers, RecIcons, recToast
  dental_records_card.dart    Clinical records card on Patient details
  perio_chart_screen.dart     Perio chart (full screen), PerioSummary, trend, PDF
  endo_dialog.dart            Endo list + endo record dialog
  consent_dialog.dart         Consents with signature pad, PDF
  recalls.dart                Recalls tab, rules, suggestions, set-recall dialog
  clinical_forms.dart         Pain + TMD screener, Frankl, WHO surgical checklist
lib/features/radiology/       Radiology module (worklist, viewer, viewer_plus, reports, referrers, PACS UI, settings)
  open_study.dart             openRadStudy, openRadReport, openRadCbct3d, radRoute
  presentation/radiology_dialogs.dart  pickRadPatient, referrer dialogs, fees, audit, dose log, invoice
  presentation/radiology_ui.dart       RadIcons, RadFormat, pills, RadNotConnected
lib/features/dental/presentation/desktop/  tooth chart (2D/3D), procedures, treatment plans, sterilization, dental_ui kit
```

**Sidebar indices in use:**

| Index | Tab |
|---|---|
| 0 | dashboard |
| 1 | patients |
| 2 | inventory |
| 3 | revenue |
| 4 | appointments |
| 5 | campaigns |
| 6 | scribe |
| 7 | queue |
| 8 | settings |
| 9 | treatmentPlans |
| 10 | sterilization |
| 11 | procedures |
| 12 | worklist |
| 13 | reports |
| 14 | referrers |
| 15 | recalls |

**The next free index is 16.** Each new tab takes the next number, and `desktop_shell.dart` `_labels`/`_icons` must stay in the same order.

---

*End of guide.*
