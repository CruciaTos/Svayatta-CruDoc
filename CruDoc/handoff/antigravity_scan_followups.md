# Scan follow-ups — brief for Antigravity

Paste this whole file. It is the complete brief.

## ▶ DO NOW

Do **S1, S2 and S3**, in order, then run the Checks once. Then stop and report.

---

## Background (already built by Claude — do not change these files)

- The phone's home screen has a **Scan** quick action. It opens the document
  camera, crops each page, and the doctor chooses what the scan is for.
- `lib/features/scan/presentation/scan_flow.dart` — `startScanFlow(...)`, the
  entry point. Signature:
  ```dart
  Future<void> startScanFlow(
    BuildContext context, {
    Patient? patient,
    required bool clinical,
    required bool inventory,
    required bool revenue,
  })
  ```
- `lib/features/scan/data/scan_capture.dart` — `ScanCapture.hasCamera` is true on
  Android and iOS only.
- `ConsultationNote` (`lib/features/scribe/data/models/consultation_note.dart`)
  now has `final List<String> scanFileIds;` — the ids of the patient files that
  hold the handwritten pages a session note was read from. Empty for spoken
  sessions.
- Files: `FilesRepository.instance.file(id)` returns `Future<PatientFile?>`
  (`lib/features/files/data/files_repository.dart`). `fileThumbBytes(file)`
  (`lib/features/files/presentation/widgets/progressive_picture.dart`) returns
  the small JPEG thumbnail or null. `FilesActions.open(context, file,
  patientName: name)` (`lib/features/files/presentation/files_actions.dart`)
  opens a file full screen.

## Rules

- Read `.claude/rules/crudoc-ui.md` first and follow it: design tokens only
  (`context.cru` colours, `CruType`, `CruSpace`, `CruRadius`), no hard-coded
  colours or sizes, radii 12 for inset things.
- Change only the files each task names. Do not touch anything under
  `lib/features/scan/`, `file_viewer.dart` or the models.
- Match the code around you: same comment style (short `///` doc comments in
  plain words), same naming.
- No sample or made-up data. If there is nothing to show, show nothing.

### How to work

- Write every task in the DO NOW list first. Run the Checks only once, at the
  very end.
- A task-level **STOP** means: skip that part, write down why, carry on with
  the next task. Only a **GATE** line stops the whole run.

---

## S1 — Session note screen shows the scanned pages

File: `lib/features/scribe/presentation/session_note_screen.dart`

1. Create a new file `lib/features/scribe/presentation/widgets/session_scan_card.dart`
   with a `StatelessWidget` named `SessionScanCard`:
   ```dart
   /// The handwritten pages a session note was read from, as thumbnails.
   /// A tap opens the page full screen. Hidden when none are left.
   class SessionScanCard extends StatelessWidget {
     const SessionScanCard({super.key, required this.fileIds, required this.patientName});
     final List<String> fileIds;
     final String patientName;
     ...
   }
   ```
   - In `build`, use a `FutureBuilder<List<PatientFile>>` whose future is
     `Future.wait(fileIds.map(FilesRepository.instance.file))` then keep only
     files that are non-null and `!f.isDeleted`.
     Create the future once: make the widget a `StatefulWidget` and store the
     future in `initState`, so it is not re-run on every build.
   - While loading or when the list is empty: return `const SizedBox.shrink()`.
   - Otherwise return a `CruCard` (`padding: const EdgeInsets.all(CruSpace.s20)`)
     containing a `Column(crossAxisAlignment: CrossAxisAlignment.stretch)`:
     - `Text('SCANNED PAGES', style: CruType.groupLabel.tint(c.label2))`
       where `final c = context.cru;`
     - `const SizedBox(height: CruSpace.s12)`
     - a `Wrap(spacing: CruSpace.s10, runSpacing: CruSpace.s10, children: [...])`
       with one tile per file: a `CruPressable` (`semanticLabel: 'Open page N'`,
       `onTap: () => FilesActions.open(context, file, patientName: patientName)`)
       whose builder returns a `ClipRRect(borderRadius: BorderRadius.circular(12))`
       around a `SizedBox(width: 72, height: 96)` with
       `Image.memory(thumb, fit: BoxFit.cover)` when `fileThumbBytes(file)` is not
       null, else a `ColoredBox(color: c.inset)` with a centred
       `CruIcon(CruIcons.fileText, color: c.label3)`.
     Look at how `CruPressable` is used in
     `lib/features/patients/presentation/widgets/details/session_history_card.dart`
     (`builder: (context, hovered) => ...`) and copy that shape.
2. In `session_note_screen.dart`, inside the `if (edit == null) ...[` list, right
   after `SessionNoteBody(note: _note),` add:
   ```dart
   if (_note.scanFileIds.isNotEmpty) ...[
     const SizedBox(height: CruSpace.s16),
     SessionScanCard(
       fileIds: _note.scanFileIds,
       patientName: widget.patient?.fullName ?? '',
     ),
   ],
   ```
3. Still in `session_note_screen.dart`, give `SessionTranscriptCard` a new
   optional parameter `this.title = 'CONVERSATION TRANSCRIPT'` (a `final String
   title;` field) and use it instead of the hard-coded `'CONVERSATION
   TRANSCRIPT'` text. Where the screen builds it, pass
   `title: _note.scanFileIds.isEmpty ? 'CONVERSATION TRANSCRIPT' : 'AS WRITTEN'`.
   Also change the doc comment above the class to: `/// What the notes were
   written from — the conversation, or the handwriting as written — folded away
   by default.`

Check for S1: a note with `scanFileIds` shows a "SCANNED PAGES" card under the
note; a spoken note looks exactly as before.

## S2 — Session history marks scanned notes

File: `lib/features/patients/presentation/widgets/details/session_history_card.dart`

In `SessionRow.build`, the `sub` list is currently:
```dart
final sub = [
  DashFormat.time(t),
  if (note.isEdited) 'Edited',
].join(' · ');
```
Change it to:
```dart
final sub = [
  DashFormat.time(t),
  if (note.scanFileIds.isNotEmpty) 'Scanned',
  if (note.isEdited) 'Edited',
].join(' · ');
```
Nothing else in this file changes.

## S3 — "Scan" on a patient's Files card (phones only)

File: `lib/features/files/presentation/patient_files_card.dart`

The card's bottom has a `CruCapsuleButton(label: 'Add files', ...)` shown when
`canEdit`. Next to it (same `Align`, wrap the two in a
`Wrap(spacing: CruSpace.s8, children: [...])`), add a second capsule button,
only when `ScanCapture.hasCamera` is true:
```dart
CruCapsuleButton(
  label: 'Scan',
  icon: CruIcons.scan,
  onPressed: () => startScanFlow(
    context,
    patient: patient,
    clinical: ref.read(clinicCanProvider(ClinicPermission.clinicalEdit)),
    inventory: false,
    revenue: false,
  ),
),
```
Imports to add (only the ones not already there):
```dart
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/scan/data/scan_capture.dart';
import 'package:doctor_management_app/features/scan/presentation/scan_flow.dart';
```
If `CruCapsuleButton` does not take an `icon` of type `CruIconData`, **STOP**
this task (note it) — do not change `CruCapsuleButton`.

---

## Checks (once, at the end)

1. From `CruDoc/`: `flutter analyze lib/features/scribe lib/features/patients lib/features/files`
   — fix anything it reports in the files you changed. Ignore issues in files
   you did not touch.
2. Report: which tasks are done, anything skipped with the reason, and the
   analyze result.

GATE: stop here. Do not commit, push or build.
