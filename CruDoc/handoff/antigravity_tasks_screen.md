# Antigravity brief: rebuild the phone Tasks screen (PHONE ONLY)

You are rebuilding the **Tasks** tab of the CruDoc **phone** app. This is phone-only work: the Tasks tab exists only in the mobile shell. **Do not change any desktop screen, any desktop layout, or any file not listed under "Files you may touch".** Desktop keeps its own Worklist, Reports and Treatment plans pages exactly as they are.

Project root: `CruDoc/` (Flutter, package name `doctor_management_app`).

---

## 1. What the Tasks tab is for

The Tasks tab replaces three separate pages on the phone with ONE to-do list:

| Old desktop page | File | What it holds |
|---|---|---|
| Radiology **Worklist** | `lib/features/radiology/presentation/worklist_screen.dart` | Scans (studies) sent in for reading |
| Radiology **Reports** | `lib/features/radiology/presentation/reports/reports_screen.dart` | Reports being written / signed / sent |
| Dental **Treatment plans** | `lib/features/dental/presentation/desktop/treatment_plans_screen.dart` | Proposed and accepted procedures per patient |

Today's phone Tasks screen (`lib/features/mobile/mobile_tasks.dart`) just stacks these as plain lists. The doctor can't tell a worklist item from a report, and there is no search and no filter. **Read all three files above fully before starting** — copy their rules, don't invent new ones.

The key idea: **every item is one patient's job, at one stage, with one next step.** The doctor should see at a glance *what* the job is, *what stage* it is in, *what to do next*, and *how urgent* it is.

---

## 2. The unified logic (build this first, as pure Dart)

Create `lib/features/mobile/tasks/tasks_logic.dart`. It must have **no Flutter widgets**, only models and pure functions, so the logic is easy to follow.

### 2.1 Sources

```dart
enum TaskSource { scan, report, plan }
```

- `scan`: a radiology study that has not been read into a report yet (it was a **Worklist** row).
- `report`: a radiology study whose report is started but not yet sent (it was a **Reports** row).
- `plan`: one patient's dental treatment plan items that still need something (it was a **Treatment plans** row).

### 2.2 Stages: the one thing that tells items apart

Each task has exactly one stage. The stage decides its label, its next-step verb, its step number and its colour.

```dart
enum TaskStage {
  //            label               verb        source  step  of
  toRead     ('To read',          'Read',      scan,   1,    4),
  reading    ('Reading',          'Continue',  scan,   1,    4),
  drafting   ('Writing report',   'Write',     report, 2,    4),
  toSign     ('To sign',          'Sign',      report, 3,    4),
  toSend     ('Signed · to send', 'Send',      report, 4,    4),
  awaitingOk ('Waiting for OK',   'Follow up', plan,   1,    2),
  toTreat    ('To treat',         'Treat',     plan,   2,    2),
}
```

Give the enum fields: `label`, `verb`, `source`, `step`, `steps`.

**Mapping from the real data (these are the exact rules):**

Radiology: one `RadStudy` gives one task. Its status is `RadStudyStatus` in `lib/features/radiology/data/radiology_models.dart`:

| `study.status` | Stage | Meaning in plain words |
|---|---|---|
| `newStudy` | `toRead` | Arrived, never opened |
| `reading` | `reading` | Opened in the viewer, report not started |
| `draft` | `drafting` | Report started |
| `preliminary` | `toSign` | Report written, needs the signature |
| `finalised` | `toSend` | Signed, not yet sent to the referrer |
| `delivered` | — | Done: **not a task** (count it in "done today" if `updatedAt` is today) |

Dental plans: group `TreatmentPlanLineItemModel`s (`lib/features/dental/data/models/treatment_plan_line_item_model.dart`) **by patient**, skipping `isDeleted` items and items whose patient is not found. Status comes from `TreatmentPlanItemStatus.fromString(item.status)`. One patient can produce up to two tasks:

- the patient's **proposed** items → one task at `awaitingOk`
- the patient's **accepted** items → one task at `toTreat`
- `declined` and `invoiced` are not tasks. Count `invoiced` items whose `updatedAt` is today in "done today".

So "Worklist" becomes the stages **To read / Reading**, and "Reports" becomes **Writing report / To sign / Signed · to send**. That is how the doctor tells them apart, and the step number ("Step 2 of 4") shows how far along each one is.

### 2.3 The task model

```dart
class TaskItem {
  final String id;              // 'scan_<studyId>' / 'plan_<patientId>_<stage.name>'
  final TaskStage stage;
  TaskSource get source => stage.source;
  final String patientName;
  final String? patientId;      // null/empty when not matched to a CruDoc patient
  final String title;           // what: see 2.4
  final String? detail;         // second line: see 2.4
  final RadPriority? priority;  // scans/reports only
  final bool critical;          // study.critical (a critical finding the referrer must hear about)
  final DateTime since;         // when this stage started (see 2.5)
  final DateTime? dueAt;        // see 2.5
  final double? amount;         // plans: sum of estimatedPrice of its items
  final RadStudy? study;        // set for scan/report tasks
  final Patient? patient;       // set for plan tasks
  final List<TreatmentPlanLineItemModel> planItems; // empty for radiology
  final String searchText;      // lower-cased haystack, see 2.7
}
```

### 2.4 Title and detail text

- **Scan / report:** title = `'${study.modality.short} · ${study.clinicalQuestion.isNotEmpty ? study.clinicalQuestion : (study.description.isNotEmpty ? study.description : study.modality.label)}'`. Detail = the referrer's name (from `radReferrerByIdProvider`, a `Map<String, RadReferrer>`; `RadReferrer` has `name` and `clinic`), or `null` if there is no referrer.
- **Plan:** sort the items by `sequence`. Title = first item's `procedureName` + (its `toothNumbers` joined with ', ' after ' · ' if not empty) + (' (+N more)' if there are more items). Detail = for `awaitingOk`: `'N procedures proposed · ₹total'`; for `toTreat`: `'N to do · ₹total'`. Format rupees with `DashFormat.rupees` (`lib/features/dashboard/domain/dashboard_format.dart`).

### 2.5 Time: one "when" for every task

Radiology already has due times; plans don't. Give plans a **follow-up due date**, so every task can sit on the same timeline:

- Scan/report: `since = study.updatedAt`, `dueAt = study.dueAt` (it may be null).
- Plan `awaitingOk`: `since` = the newest `updatedAt` among its items; `dueAt = since + 7 days` (chase the patient for a decision after a week).
- Plan `toTreat`: `since` = the newest `updatedAt` among its items; `dueAt = since + 14 days` (accepted work should be booked within two weeks).

Then `bool isOverdue(DateTime now) => dueAt != null && now.isAfter(dueAt!)`.

### 2.6 Urgency order (the default sort, highest first)

Write `int compareUrgency(TaskItem a, TaskItem b, DateTime now)` and sort with it. Rules, in order:

1. `critical` before non-critical.
2. Overdue before not overdue.
3. Priority: `stat` > `urgent` > `routine` > no priority (plans).
4. Earlier `dueAt` first; a null `dueAt` goes last.
5. Older `since` first.

This matches the desktop worklist's `radNextUnread` rule (STAT first, then urgent, then the one due soonest). Re-use `radNextUnread` from `worklist_screen.dart` for the "Next to read" card.

### 2.7 Buckets (the section headers)

`TaskBucket bucketOf(TaskItem t, DateTime now)`:

- `overdue`: `isOverdue(now)` or `critical`. Header: **"Overdue"** (critical items sit here too, at the top).
- `today`: `dueAt` is today (same calendar day as `now`). Header: **"Due today"**.
- `later`: `dueAt` is after today. Header: **"Coming up"**.
- `noDate`: `dueAt == null`. Header: **"No deadline"**.

Within a bucket, sort with `compareUrgency`. Show only buckets that have items, in that order.

### 2.8 Search

`searchText` = lower-case of: the patient name, the title, the detail, the referrer name and clinic, `study.description`, `study.accession`, `study.modality.label`, and for plans every item's `procedureName` and tooth numbers. A query matches when **every** whitespace-separated word of the query is found in `searchText` (so "cbct ravi" finds Ravi's CBCT).

### 2.9 Filters

```dart
enum TaskFilter { all, urgent, overdue, toRead, reading, drafting, toSign, toSend, awaitingOk, toTreat }
```

- `urgent`: `critical` or priority is `stat`/`urgent`.
- `overdue`: `bucketOf == overdue`.
- The rest: `stage ==` that stage.

Write `bool matchesFilter(TaskItem t, TaskFilter f, DateTime now)` and `Map<TaskFilter, int> filterCounts(List<TaskItem> all, DateTime now)`.

### 2.10 The builder

```dart
class TaskBoard {
  final List<TaskItem> items;   // all tasks, sorted by urgency
  final int doneToday;          // delivered studies + invoiced plan items updated today
  final RadStudy? nextToRead;   // radNextUnread(studies), null if none
}

TaskBoard buildTaskBoard({
  required List<RadStudy>? studies,          // null when radiology is off or loading
  required Map<String, RadReferrer> referrers,
  required List<TreatmentPlanLineItemModel>? planItems, // null when dental is off or loading
  required Map<String, Patient> patientsById,
  required DateTime now,
});
```

---

## 3. Data and gating (keep exactly as the current mobile_tasks.dart does)

- Which sources apply: build `tabs = { for (t in sidebarTabs(dental: ref.watch(dentalFeaturesProvider), access: ref.watch(clinicAccessProvider).value)) t.tab }`.
  - Radiology is on if `tabs.contains(DesktopTab.worklist) || tabs.contains(DesktopTab.reports)`.
  - Dental plans are on if `tabs.contains(DesktopTab.treatmentPlans)`.
- Radiology data: `ref.watch(radStudiesProvider)` (AsyncValue<List<RadStudy>>) and `ref.watch(radReferrerByIdProvider)` from `lib/features/radiology/data/radiology_providers.dart`.
- Plan data: `ref.watch(clinicTreatmentPlansProvider)` (`lib/features/dental/presentation/providers/dental_desktop_providers.dart`), plus `ref.watch(patientsStreamProvider)` (`lib/features/patients/data/providers/patient_providers.dart`). The patient's display name is `patient.fullName`.
- Pass `null` for a source that is off. While a source that is on is still loading, show a loading row (`MobileLoading`), not an empty state.
- `now`: `DateTime.now()` once per build.

---

## 4. The screen (rewrite `lib/features/mobile/mobile_tasks.dart`)

Keep the public class and constructor exactly: `MobileTasksScreen({super.key, required List<String> enabledModules})`. `mobile_shell.dart` uses it, and you must **not** edit the shell.

Make it a `ConsumerStatefulWidget`. State: `TaskFilter _filter = TaskFilter.all`, a `TextEditingController _search`, `String _query`. Dispose the controller.

Build everything from the phone kit `lib/features/mobile/mobile_kit.dart`: `MobileHeader`, `MobileCircleButton`, `MobileSearchField(controller:, hint:, onChanged:)`, `MobileChip(label:, selected:, onTap:, count:)`, `MobileRowGroup(title:, children:)`, `MobileRow(leading:, title:, subtitle:, trailing:, onTap:, onLongPress:)`, `MobileIconTile(icon:, tone:)`, `MobilePill(text, tone:, icon:)`, `MobileEmpty(icon:, title:, body:)`, `MobileLoading`, `showMobileActionSheet` / `MobileSheetAction`, `mobileRoot(context)`, `mobileSay`, `MobileMetrics`, `MobileHaptics`. **Look at `lib/features/mobile/mobile_patients.dart` and copy how it lays out its search field and its chip row**, so Tasks looks like Patients.

Layout, top to bottom, inside one `ListView` with bottom padding `MobileMetrics.bottom(context)`:

1. **Header.** `MobileHeader(title: 'Tasks', subtitle: …, trailing: + button)`.
   - Subtitle: `'N to do · M overdue · K done today'`. Leave out any part that is 0; use `'All caught up'` when N is 0; use `null` while loading.
   - The + button only appears if at least one of these actions is available. It opens `showMobileActionSheet` with:
     - radiology on: **Import scans** → `runRadImport(context, ref)` (`lib/features/radiology/presentation/rad_import_flow.dart`)
     - radiology on: **Capture RVG** → `showRvgCaptureDialog(mobileRoot(context))` (`lib/features/radiology/presentation/rvg_capture_dialog.dart`)
     - dental on: **New treatment plan** → `showPatientPickerDialog(mobileRoot(context), title: 'Plan treatment for')`, then if a patient was picked `showTreatmentPlanDialog(mobileRoot(context), patient: p)`, then `ref.invalidate(clinicTreatmentPlansProvider)`.
2. **Search.** `MobileSearchField(hint: 'Search patient, scan, procedure or referrer')`, wired to `_query`.
3. **Filter chips.** One horizontally scrolling row of `MobileChip`s. `All` is always shown. Every other filter is shown **only if its count > 0** (or if it is the selected one). Each shows its count. Labels: All, Urgent, Overdue, To read, Reading, Writing report, To sign, To send, Waiting for OK, To treat. Tapping one selects it, with `MobileHaptics.select()`.
4. **Next to read card.** Only when the filter is All or To read, the search is empty, and `board.nextToRead != null`. It is one compact `MobileCard`:
   - left: the modality short name in a `MobileIconTile`
   - text: patient name, then `'${modality.short} · ${priority.label}'`, plus the due time if any
   - right: a filled `MobilePrimaryButton`-style **Read** button → `openRadStudy(context, ref, study)` (`lib/features/radiology/open_study.dart`; this also marks the study as being read)

   This is the single primary action on the page. Don't add another filled button anywhere else.
5. **Buckets.** For each non-empty bucket, in the order Overdue, Due today, Coming up, No deadline: a `MobileRowGroup(title: '<Header> · <count>')` containing the filtered and searched tasks' rows (§5). Don't cap the rows; the filter and search are how the doctor narrows them.
6. **Empty states.**
   - No source applies to this doctor: `MobileEmpty(icon: CruIcons.check, title: 'No tasks here yet', body: 'Scans to report and treatment plans show up here once radiology or dental features are on.')`.
   - Sources on but no tasks at all: `MobileEmpty(title: 'All caught up', body: 'Nothing is waiting on you right now.')`.
   - Tasks exist but the filter or search hides them all: `MobileEmpty(title: 'No matches', body: 'Try another filter or search.')`, plus a small link that resets both.
7. **See all pages.** At the very bottom, one quiet `MobileRowGroup(title: 'Full lists')` with chevron rows that open the original full pages:
   - **Worklist** → `openMobileDestination(context, DesktopTab.worklist, backLabel: 'Tasks')`
   - **Reports** → `openMobileDestination(context, DesktopTab.reports, backLabel: 'Tasks')`
   - **Treatment plans** → `openMobileDestination(context, DesktopTab.treatmentPlans, backLabel: 'Tasks')`

   Show each row only if its tab is in `tabs`. `openMobileDestination` is in `lib/features/mobile/mobile_more.dart`.

---

## 5. One task row

`MobileRow` with:

- **leading**: `MobileIconTile`, coloured by source so the three kinds read apart at a glance.
  - scan → icon `RadIcons.worklist`, tone `MobileTone.indigo`
  - report → icon `RadIcons.report`, tone `MobileTone.teal`
  - plan → icon `DentalIcons.plan`, tone `MobileTone.blue`

  (`RadIcons` is in `lib/features/radiology/presentation/radiology_ui.dart`; `DentalIcons` is in `lib/features/dental/presentation/desktop/dental_icons.dart`.)
- **title**: `patientName`.
- **subtitle**: `'${t.title}'`, then on the same line `' · ${detail}'` if there is one, then `' · '` and the time text:
  - overdue: `'Overdue <Xh/Xd>'`
  - due today: `'Due <h:mm a>'` (`DashFormat.time`)
  - later: `'Due <d MMM>'` (`DashFormat.shortDate`)
  - no date: `'<age> ago'` from `since`

  Keep it to 2 lines (`maxLines` in the row, if `MobileRow` supports it; otherwise keep the text short).
- **trailing**: a small column, right-aligned:
  - a `MobilePill(stage.label, tone: …)`. Tones: toRead → amber (it is waiting), reading → blue, drafting → slate, toSign → amber, toSend → green (it is done, only sending is left), awaitingOk → amber, toTreat → blue.
  - under it, a tiny caption `'Step ${stage.step} of ${stage.steps}'`.
  - if `critical`, put a red `MobilePill('Critical', tone: MobileTone.red …)` **instead of** the stage pill. (Red is allowed only for patient safety, and a critical finding is that.) If `priority` is stat/urgent and the item is not critical, prefix the subtitle with `'STAT · '` or `'Urgent · '`.

  If `MobileTone` has no red, read `mobile_kit.dart` and use what it offers for red (`c.redText` / `c.redTint` exist on `context.cru`).
- **onTap**: do the stage's next step:
  - toRead, reading → `openRadStudy(context, ref, study)`
  - drafting, toSign, toSend → `openRadReport(context, study)`
  - awaitingOk, toTreat → `showTreatmentPlanDialog(mobileRoot(context), patient: t.patient!)`, then `ref.invalidate(clinicTreatmentPlansProvider)`
- **onLongPress**: `showMobileActionSheet(context, title: patientName, subtitle: '${stage.label} · Step x of y', actions: …)`:
  - scan/report:
    - View scans → `openRadStudy`
    - Write report → `openRadReport`
    - Set priority → a second sheet with Routine / Urgent / STAT. On pick: `final ctrl = ref.read(radiologyProvider); await ctrl.saveStudy(study.copyWith(priority: p, dueAt: await ctrl.dueFor(p, study.receivedAt)));`. This copies the desktop worklist's `_RowAction.routine/urgent/stat` code in `worklist_screen.dart`, so read that code and match it exactly, including its `auditAction` if it passes one.
    - Invoice → `invoiceRadStudy(context, ref, study)`. Only when `study.status` is finalised or delivered, `study.fee != null` and `!study.invoiced`.
  - plan:
    - Open plan → `showTreatmentPlanDialog`
    - for awaitingOk: **Mark accepted** → for each item: `await ref.read(dentalRepositoryProvider).updateTreatmentPlanLineItemStatus(item.id, TreatmentPlanItemStatus.accepted.code)`, then `ref.invalidate(clinicTreatmentPlansProvider)`, then `mobileSay(context, 'Plan accepted.')`
    - for awaitingOk: **Mark declined** → the same with `.declined.code`. Confirm first with a small dialog, because it is destructive.
    - Open patient → `openMobilePatient(context, t.patient!)` (in `mobile_more.dart`)
  - Add **Open patient** for radiology tasks too, but only when `study.patientId` is not empty and the patient exists in `patientsById`.

  Check `TreatmentPlanItemStatus` for a `code` getter. If it doesn't have one, use `.name`, the same as the desktop treatment plan dialog does (read `dental_dialogs.dart` around `TreatmentPlanItemStatus.accepted` to see what it writes).

---

## 6. Rules

- Follow `CruDoc/.claude/rules/crudoc-ui.md`. Use design tokens only (`context.cru`, `MobileType`, `CruSpace`, `CruRadius`); no hard-coded colours or sizes. Motion is 200–250 ms easeOutCubic. Use tabular figures for numbers. Amber means waiting, green means done, red is only for the critical finding, and violet is not used at all.
- **No fabricated data.** Hide anything that is missing (no referrer → no referrer text; no due date → "No deadline" bucket).
- There is one filled button on the page: Read in the Next to read card.
- This is phone only. Don't touch desktop pages, `mobile_shell.dart`, `mobile_more.dart` or any radiology or dental file. Only call their public functions.
- Don't add packages, tests or docs.

## 7. Files you may touch

- `lib/features/mobile/tasks/tasks_logic.dart` (new)
- `lib/features/mobile/mobile_tasks.dart` (rewrite)

Nothing else.

## 8. Finish

1. Run `flutter analyze lib/features/mobile` and fix every error and warning in your two files.
2. Report what you built, and any function from this brief whose name or signature turned out to be different from what is written here, and what you used instead.
