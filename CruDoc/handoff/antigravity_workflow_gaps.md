# Antigravity tasks: close the daily-workflow gaps

You are building several small features in this codebase. This whole file is
your brief. Claude (the lead) reviews your work at each GATE and updates this
file.

## ▶ DO NOW

**Do every task in Phases 1 to 4 (R1..R7, B1..B4, N1, M1..M3), in order.**
Stop at the two GATE lines only. Phases 5 and 6 are NOT part of this run.

- After **Phase 1** and after **Phase 4** there is a GATE: stop, report every
  file you changed, the output of the end-of-phase analyze, and what you could
  not do (with the reason). Then wait.
- Anywhere a task says "STOP", that means: skip that part, write one line in
  your report saying what and why, and carry on with the next task.

---

## Rules

> Project: `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\CruDoc`, a Flutter app on
> Firebase (Windows desktop + phone). Shared widgets live in
> `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\crudoc_shared`.
> - Change ONLY the files a task names (you may create the new files it
>   names). Do not reformat, rename or "improve" other code. Run `dart format`
>   only on files you changed or created.
> - Never deploy, never `git commit` / `git push`.
> - UI: read `CruDoc/.claude/rules/crudoc-ui.md` first and follow it: colours
>   from `context.cru`, spacing `CruSpace`, radii `CruRadius`, text `CruType`.
>   No hard-coded colours or sizes. One filled button per dialog. Blue only
>   for the one primary action. Amber means waiting / needs attention.
> - Never show made-up sample data in app code.
> - Copy patterns from the file named in each task; do not invent new widgets
>   when a `Cru…` widget or `PatientDialog` / `CruFormDialog` already does it.
> - Never run the whole `flutter test` suite (parallel runs crash on
>   sqlite3.dll). Run only test files a task names. Do not write database
>   tests.
> - If the code you find does not match the task, skip that task, say what you
>   found, and carry on.

**How to work (no pauses):** write all the tasks of a phase first. Run
`flutter analyze lib/features` ONCE at the end of the phase (not after every
task) and fix what it reports in files you changed. Run slow commands in the
background while you continue. Do not stop to ask questions; make the
conservative choice, note it in your report, and carry on.

---

## Facts you need

| Thing | Where |
|---|---|
| Patient model (no schema change needed) | `lib/features/patients/data/models/patient.dart` |
| Create / edit patient (repo) | `lib/features/patients/data/repo/patient_repository.dart` (`createPatient(Patient) -> id`, `getPatient(id)`; it only requires a non-empty first name) |
| Providers | `lib/features/patients/data/providers/patient_providers.dart` (`patientsStreamProvider`, `patientRepositoryProvider`, `searchQueryProvider`) |
| Full "New patient" dialog | `lib/features/patients/presentation/desktop_add_edit_patient_dialog.dart` (needs gender + date of birth) |
| Patient picker | `lib/features/appointments/presentation/patient_picker_dialog.dart` |
| Schedule dialog | `lib/features/appointments/presentation/desktop_schedule_visit_dialog.dart` |
| Appointment actions | `lib/features/appointments/presentation/appointment_actions.dart` (`ApptActions`) |
| Visits repo | `lib/features/appointments/data/repo/visits_repo.dart` |
| Queue repo / screen | `lib/features/queue/data/repo/queue_repository.dart`, `lib/features/queue/presentation/desktop_queue_screen.dart` |
| Invoices / revenue | `lib/features/revenue/…` |
| WhatsApp text helpers | `lib/features/messaging/data/services/whatsapp_template_service.dart` |

**A "details pending" patient** already has a precedent: the radiology import
creates patients with only a name (`lib/features/radiology/presentation/rad_import_flow.dart`,
`_patientId`, case `_PatientLink.create`): empty phone, placeholder date of
birth `DateTime(now.year - 30, 1, 1)`, a note saying where they came from.
We reuse that. **No new database column.** "Details pending" is simply
`phone.trim().isEmpty`.

---

# PHASE 1: Registering people (the main gap)

Goal: a person with no record can be booked or checked in with just a name,
and the record can be completed later. A new patient is one click away from
the patient picker.

## R1. The quick patient helper

Create `lib/features/patients/domain/quick_patient.dart`:

```dart
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// A patient made from just a name (and maybe a phone), to hold a booking or
/// a token now and fill in the rest later.
Patient quickPatient(String name, {String phone = ''}) {
  final parts = name.trim().split(RegExp(r'\s+'));
  final now = DateTime.now();
  return Patient(
    id: '',
    firstName: parts.first,
    lastName: parts.length > 1 ? parts.sublist(1).join(' ') : '',
    phone: phone.trim(),
    gender: '',
    dateOfBirth: DateTime(now.year - 30, 1, 1),
    diagnosis: const [],
    notes: 'Added quickly. Details to be completed.',
    packageBalance: 0,
    isArchived: false,
    createdAt: now,
    updatedAt: now,
  );
}

/// Phone missing: the record still needs filling in.
bool patientDetailsPending(Patient p) => p.phone.trim().isEmpty;
```

(If `Patient`'s constructor needs other required arguments, pass the same
neutral values `rad_import_flow.dart` passes. Do not edit `patient.dart`.)

Add `test/features/patients/quick_patient_test.dart` (plain Dart test, no
database): "Smit Mhatre" gives first "Smit", last "Mhatre"; "Smit" gives an
empty last name; the phone is trimmed; `patientDetailsPending` is true for an
empty phone and false for "9321559866".
Check: `flutter test test/features/patients/quick_patient_test.dart`

## R2. The quick patient dialog

Create `lib/features/patients/presentation/quick_patient_dialog.dart` with

```dart
Future<Patient?> showQuickPatientDialog(
  BuildContext context, {
  String initialName = '',
  String initialPhone = '',
  String submitLabel = 'Add patient',
})
```

Copy the structure of `desktop_add_edit_patient_dialog.dart` (a `CruFormDialog`;
same title/leading style; Ctrl+Enter hint). Title "New patient", subtitle
"Just a name for now. Add the rest later." Two fields only: **Name**
(required, "Enter a name") and **Phone** (optional, tabular figures). On
submit: build `quickPatient(name, phone: phone)`, call
`patientRepositoryProvider.createPatient`, then `getPatient(id)` and pop with
that patient. On error show the same notice style as the other dialog. Use a
`ConsumerStatefulWidget` so it can read the providers.

## R3. Let the full dialog report who it created

In `desktop_add_edit_patient_dialog.dart` add an optional
`ValueChanged<String>? onCreated` to `showDesktopAddEditPatientDialog` and to
the dialog widget. In `_save`, in the create branch, keep the returned id
(`final id = await _repository.createPatient(...)`) and call
`widget.onCreated?.call(id)` before `Navigator.of(context).pop(true)`. Do not
change anything else (still pops `true`). Also thread the parameter through
`showAddPatientSheet` in `patient_form.dart` (new optional parameter, passed to
the desktop dialog only; the phone sheet ignores it).

## R4. The picker: new patient, empty state, search leak

In `patient_picker_dialog.dart`:

1. **Footer buttons.** Under the list (outside the `Expanded`), add a
   `CruSeparator` and a row with two capsule/inset buttons (not filled):
   **"Quick add"** and, only when the width is not phone
   (`!cruIsPhone(context)`), **"New patient (full details)"**.
   - Quick add: `final p = await showQuickPatientDialog(context, initialName: _searchController.text.trim());` if `p != null` then `Navigator.of(context).pop<Patient>(p)`.
   - Full: `String? id; final ok = await showAddPatientSheet(context, onCreated: (v) => id = v);` if `ok == true && id != null`, load `ref.read(patientRepositoryProvider).getPatient(id!)` and pop it.
2. **Empty state.** When the list is empty and a search is typed, show under
   the message a button: `Add "<query>" as a new patient` that runs Quick add
   with `initialName` = the query. When the list is empty with no query, show
   the same two buttons instead of "Create one to get started." text only.
3. **Search leak.** The picker writes the shared `searchQueryProvider`, so the
   Patients screen stays filtered after the picker closes. Fix: in
   `initState` clear it (`Future.microtask(() => ref.read(searchQueryProvider.notifier).state = '')`)
   and in `dispose` capture the notifier first
   (`late final _query = ref.read(searchQueryProvider.notifier);` assigned in
   `initState`) and do `Future.microtask(() => _query.state = '')`.
4. Show a small amber "Details pending" text (`CruType.caption`, amber text
   colour from `context.cru`) on a row when `patientDetailsPending(patient)`.

All callers of `showPatientPickerDialog` keep working unchanged: they just get
the new patient back like any other pick, so the schedule dialog / queue /
files flows continue straight on.

## R5. Warn about a duplicate phone

Create `lib/features/patients/domain/duplicate_patient.dart`:

```dart
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

/// An existing patient with the same phone (last 10 digits), or null.
Patient? duplicateByPhone(List<Patient> existing, String phone) {
  final d = _digits(phone);
  if (d.length < 7) return null;
  final tail = d.length > 10 ? d.substring(d.length - 10) : d;
  for (final p in existing) {
    final e = _digits(p.phone);
    if (e.length >= 7 && e.endsWith(tail)) return p;
  }
  return null;
}
```

Use it in BOTH the quick dialog (R2) and `desktop_add_edit_patient_dialog.dart`
`_save` (create branch only): read `patientsStreamProvider` value
(`ref.read(...).value ?? const []`; the full dialog may need to become a
`ConsumerStatefulWidget`: only if it is not one already). If a match is found
show a `PatientDialog` titled "<Name> already has this number", body "<full
name> · <phone>", buttons **"Use <first name>"** (quick dialog: pop that
patient; full dialog: pop `true` without creating) and **"Add anyway"**.
Add `test/features/patients/duplicate_patient_test.dart`: same number with
spaces and "+91" matches; fewer than 7 digits returns null; a different number
returns null.
Check: `flutter test test/features/patients/duplicate_patient_test.dart`

## R6. "Needs details" filter and chip

1. `lib/features/patients/domain/patients_models.dart`: add
   `needsDetails('Needs details')` to `PatientFilter` and make its `attention`
   getter (line ~21) true for it as well, mirroring `followUpOverdue`.
2. `lib/features/patients/domain/patients_builder.dart`: handle the new value
   everywhere `followUpOverdue` is handled in a `switch` (lines ~104 and ~139):
   filter = `patientDetailsPending(s.patient)`; sort = same default as `all`.
   If a `switch` has no sensible case, add one that mirrors `all`.
3. `lib/features/patients/presentation/widgets/details/identity_header.dart`:
   when `patientDetailsPending(patient)`, show a small amber chip "Details
   pending" next to the name, which opens the edit dialog (use the same
   `showEditPatientSheet` call the header already uses for editing).

## R7. Walk-in: register as a patient

1. `queue_repository.dart`: add

```dart
/// A walk-in token gets a patient record; the token keeps its number.
Future<void> linkWalkInToPatient(String entryId, String patientId) async {
  await _localService.updateEntry(entryId, {
    'patientId': patientId,
    'walkInName': null,
    'walkInPhone': null,
    'updatedAt': DateTime.now(),
  });
  unawaited(_syncService.triggerPostWriteSync());
}
```

   First read `queue_local_service.dart` `updateEntry`: if it cannot write
   null values, use empty strings for `walkInName` / `walkInPhone` instead.
2. `desktop_queue_screen.dart`: on a token card whose entry has no
   `patientId` (a walk-in), add an action **"Register as patient"** next to the
   existing per-token actions (copy how the other token actions are added). It
   calls `showQuickPatientDialog(context, initialName: entry.walkInName ?? '', initialPhone: entry.walkInPhone ?? '', submitLabel: 'Register')` and, when a
   patient comes back, `repo.linkWalkInToPatient(entry.id, patient.id)` and a
   snackbar "Registered <first name>".
3. `lib/features/scribe/presentation/consultation_scribe_launcher.dart`,
   `_launch` (line ~88-96): the message "Register … as a patient to keep
   session notes." stays, but add that the token card now has "Register as
   patient" (change the text to: `Use "Register as patient" on token #N to keep session notes.` where N is `entry.tokenNumber`).

### Phase 1 end

Run `flutter analyze lib/features/patients lib/features/appointments lib/features/queue lib/features/scribe` once, fix issues in your files, then the two named tests.

**GATE 1: STOP HERE. Report files changed, analyze output, test output.**

---

# PHASE 2: Booking safety and entry points

## B1. Turn the overlap check back on

`visits_repo.dart` `createVisit` has `_checkOverlap(...)` commented out with a
"TEMPORARY" note. Un-comment ONLY that `_checkOverlap` call (it reads the
local database, as `rescheduleVisit` already does). Leave `_checkPatient`
commented out (it reads Firestore and crashed the app). Update the doc comment
above `createVisit`: say the overlap and same-patient checks are on and the
patient check is still off. The schedule dialog already handles
`VisitOverlapWarning`, `VisitOverlapLimitExceededException` and
`SamePatientDoubleBookingException`; do not change it.
`createVisitGroup` / `addToGroup` already pass `acknowledgeOverlap: true`;
leave them.

## B2. Booking in the past asks first

`desktop_schedule_visit_dialog.dart`, at the top of `_submit` (before
`_saving` is set): if `_start.isBefore(DateTime.now().subtract(const Duration(minutes: 5)))`
show a `PatientDialog` (import `patient_dialogs.dart` is already there) titled
"This time has already passed", body the date and time, buttons "Change time" /
"Book anyway". "Change time" returns without saving; "Book anyway" continues.
Skip the question when `acknowledgeOverlap` is true (a retry after an overlap
confirmation).

## B3. Click an empty Week slot to book

`lib/features/appointments/presentation/widgets/week/week_grid.dart`, in
`_DayColumn.build`, add above `...blocks` (so blocks stay on top) when
`!opening`:

```dart
Positioned.fill(
  child: Consumer(
    builder: (context, ref, _) => MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final minutes = (d.localPosition.dy / pxPerMinute).floor();
          final t = DateTime(day.year, day.month, day.day, 0, startMinute + minutes);
          ApptActions.newAppointment(context, ref, start: ApptsBuilder.snap(t));
        },
      ),
    ),
  ),
),
```

Imports: `flutter_riverpod`, `appointment_actions.dart`. Copy the exact
approach from `day_grid.dart` (the "Empty time: New appointment" block).

## B4. "Book follow-up" from a visit

1. `appointment_actions.dart`: give `ApptActions.newAppointment` an optional
   `Patient? patient`. When it is not null, skip `showPatientPickerDialog` and
   use it. Keep every existing call working.
2. `lib/features/patients/presentation/widgets/details/visit_session_dialog.dart`:
   next to the existing invoice button (around line 404), add an inset button
   **"Book follow-up"** that calls `ApptActions.newAppointment(context, ref, patient: <this visit's patient>, day: <visit date + 7 days>)`. If this widget has no
   `WidgetRef`, make the smallest change to get one (`ConsumerWidget`).

### Phase 2 end: no analyze yet (run it once at the end of Phase 4).

---

# PHASE 3: Tell the patient

## N1. Cancel and reschedule notices (WhatsApp link, no server)

1. `whatsapp_template_service.dart`: add, next to `buildConfirmationMessage`,
   `static String buildCancellationMessage({required Visit visit, required Patient patient, required String clinicName})` ("Hello <first name>, your appointment on <date> at <time> at <clinic> has been cancelled. Please reply to book a new time.") and
   `buildRescheduleMessage({required DateTime oldStart, required DateTime newStart, required Patient patient, required String clinicName})` ("… has been moved from <old> to <new>."). Format dates with `ApptFormat.dateLine` / `ApptFormat.time` (`lib/features/appointments/presentation/widgets/shell/appt_format.dart`). Clinic name: use whatever `buildConfirmationMessage` callers use; if none, "your clinic".
2. `appointment_actions.dart`: in `cancel` and `reschedule`, after success, add
   a snackbar action **"Tell patient"** (only when
   `WhatsAppTemplateService.isValidWhatsAppPhone(patient.phone)`; for groups use
   the lead's patient). It opens `buildDirectWhatsAppUrl(rawPhone:, message:)`
   with `launchUrl(..., mode: LaunchMode.externalApplication)`. A snackbar has
   one action, so leave `moveTo` (drag and drop) alone: it already uses its one
   action for Undo. Say so in your report.

---

# PHASE 4: Money and the end of the day

## M1. Record a payment on an unpaid invoice (partial payments)

Read `desktop_create_invoice_dialog.dart` (`_syncPaidAmountToTotal`,
`_selectedStatus`) and `desktop_invoices_screen.dart` first. The invoice
dialog already has a "paid amount". Find where that paid amount is saved (the
`billJson` or a model field). STOP this task (skip, report) if the paid
amount is not saved anywhere.
Otherwise add, on invoices whose status is Pending or Overdue, a row action
**"Record payment"** in `desktop_invoices_screen.dart`: a small `PatientDialog`
with an amount field (default = balance due, must be > 0 and <= balance).
It adds the amount to the saved paid amount, creates a matching income
`RevenueEntry` through `RevenueRepository.createRevenueEntry` (copy how
`markPendingPaymentAsPaid` builds its entry in `revenue_repo.dart`), and when
the balance reaches 0 sets the invoice status to `'Paid'` (use the existing
invoice update method the screen already uses for status changes).

## M2. Refund

In `desktop_invoices_screen.dart`, on invoices with status `'Paid'`, add a row
action **"Refund"**: dialog with amount (default = amount paid, max = amount
paid) and a reason (required). On confirm: create an expense `RevenueEntry`
(`TransactionKind.expense`, `RevenueType.miscellaneous`, note
`Refund · invoice <invoiceNumber> · <reason>`) via `createRevenueEntry`, then
set the invoice status to `'Cancelled'` only when the refund equals the full
amount; for a partial refund leave the status as is. Show a snackbar "Refunded
₹X".

## M3. Close the day

`lib/features/dashboard/presentation/widgets/wrap_up_card.dart` already shows
the evening "Wrap up the day" card (`wrap_up_builder.dart` lists what it
cannot do yet: no close-the-day). Add a button **"Day summary"** on that card
that opens a dialog (`PatientDialog` or a small `CruFormDialog`) showing, for
today, from the providers the dashboard already uses (find them in
`dashboard_screen.dart` / `lib/features/dashboard/data/providers/`): patients
seen, booked patients who did not come, collected today (the same figure the
"Collected today" card shows), expenses today, new pending dues today, and
low-stock medicine count (from the inventory provider the alert listener
uses). A **"Copy summary"** button copies a plain-text version to the
clipboard (`Clipboard.setData`). Show only numbers that exist; hide a row if
its source cannot be found. No made-up figures.

### Phase 4 end

Run `flutter analyze lib/features` once; fix issues in files you changed.

Then check by running the app (Windows) and report each as OK / not OK:
1. New appointment, picker opens, "Quick add" with only a name books a visit.
2. Same, from a search with no matches ("Add "<query>" as a new patient").
3. Entering a phone that exists shows the duplicate dialog.
4. Patients list: filter "Needs details" shows the quick-added person; the
   chip opens the edit dialog.
5. Queue: a walk-in token shows "Register as patient"; after it, the token
   has the patient's name.
6. Booking the same patient twice at the same time shows the red notice.
7. Booking in the past asks first.
8. Clicking an empty Week slot opens the picker with that time.
9. Cancel shows "Tell patient" (when the patient has a phone).
10. Invoices: Record payment, Refund and Day summary open and save.

**GATE 2: STOP HERE. Report all of the above.**

---

# LATER (not in this run; Claude will update this file)

- **P5 Archive / restore patient** (details top bar menu + an "Archived"
  filter; the `isArchived` field and the booking guard already exist).
- **P6 Export / import patients as CSV** (`file_picker` and `share_plus` are
  already in `pubspec.yaml`; write the CSV by hand, no new package; replace
  `PatientActions.importUnavailable`).
- **F1 Waiting-room display board** (full-screen "Now serving / Next" view
  from the queue screen, for a second monitor).
- **F2 "Items used" on a visit** (records stock dispense through
  `InventoryRepository.recordTransaction`).

## Not for Antigravity (Claude keeps)

- **Automatic reminders before a visit** (needs a scheduled Cloud Function
  and a messaging vendor decision).
- **Merging two patient records** (touches visits, files, invoices, queue).
- **Re-enabling `_checkPatient`** (the Firestore read that crashed the app)
  and any sync / Firestore rules change.
- Generic consent forms outside dental, lab work orders outside
  prosthodontics, prescription templates.

## Done

(nothing yet)
