# Antigravity brief: Charting visits as sessions (forward-merging chart, like git)

Paste this whole file into Antigravity. It is a standalone brief.

## ▶ DO NOW

Do Task 1 to Task 6 in order, then run the Check once at the end. Stop after the Check and report.

## Rules (how to work)

- Work without pausing. Write every task first, then run the Check once at the end.
- Change only the files named below. Do not rename, move or reformat anything else.
- Do not run `flutter run`, tests or a release build. Do not commit. Do not deploy anything.
- Where a task gives full code, copy it exactly. Where it describes a change, keep to the description.
- If a step doesn't match the code you see (a name or line is different), skip that step, write down what you saw, and carry on.
- All paths are relative to the `CruDoc/` folder (the Flutter app).
- UI rules: no hard-coded colours or sizes (use `context.cru`, `CruType`, `CruSpace`, `CruRadius`). Red is only for allergies and safety, amber means waiting/attention. One filled button per region.

---

## Background: what the user wants

In Charting, the right column lists the patient's **Visits**. Clicking a visit must **load that visit as a session**: the tooth chart shows the teeth as they were in that visit, and any change made now is saved **into that visit**.

Sessions work like commits on one git branch:

- Visit A changes tooth 16. Visit B (later) carries A forward and changes tooth 26.
- If you go back to A and change tooth 16 again, B and every later visit **pick that up**, because they never touched 16.
- If B had also changed tooth 16, that is a **collision**: B keeps its own 16, and A's new change stops at B. Later visits keep showing B's 16.
- Changes only flow **forward**, never backwards: editing B never changes what A shows.

### How the chart works today (so you know what you are changing)

- Every finding is a row in `tooth_chart_entries` (`ToothChartEntryModel`): one row per change, never edited in place. The chart is just **the newest row per tooth** (`DentalChart.latest` in `lib/features/dental/domain/dental_chart.dart`).
- Rows have **no visit link** today.
- Every chart on screen comes from `watchPatientChart` in `lib/features/dental/presentation/desktop/tooth_detail_screen.dart`, except the tooth detail dialog, which builds its own (`tooth_detail_view.dart`, around line 278).

### The model you will build

1. Each new chart row gets the **visit it was saved in** (`visitId`), plus the id of the row it replaced (`baseEntryId`, used only to flag conflicts).
2. The patient's visits, oldest first, are the **sessions**. Order: the visit's scheduled date and time, then created time, then id.
3. A row belongs to its visit's slot. A row with **no visit** (all old data, or saved when no visit was open) belongs to the last visit that had started when it was recorded (or before the first visit). This is worked out when reading. **No migration.**
4. **What a session shows:** for each tooth, the newest row from that session or any earlier one. Within one session, the newest write wins.
5. **Latest** (no session loaded) shows everything. It is the default.

That single rule gives forward merging, collisions and "never backwards" for free.

### Decided behaviour for the edge cases

| # | Situation | What happens |
|---|---|---|
| 1 | Edit visit A's tooth 16; later visits never touched 16 | Every later visit shows the new 16 (forward merge). |
| 2 | Edit A's tooth 16; visit B also changed 16 | Saved in A only; B and later keep B's 16. After saving, the tooth dialog says so in amber, naming B's date. |
| 3 | Edit a later visit | Earlier visits never change (never backwards). |
| 4 | In B, clear a finding that came from A | B saves a new "healthy" row (no condition, no treatment). A's row is untouched. Never delete another visit's row. |
| 5 | Undo a change made in this visit | "Undo this visit's change" in the tooth dialog soft-deletes this visit's rows for that tooth. The tooth falls back to what earlier visits said, and that carries forward to later visits that didn't touch it. |
| 6 | A changes 16 after B already changed 16 on top of A's old 16 | B keeps its change, but B is flagged: "An earlier visit changed 16 after this." Saving 16 again in B clears the flag (like resolving a git conflict). |
| 7 | Two visits on the same day | Separate sessions, ordered by time, then created time, then id. |
| 8 | A visit is rescheduled | Its changes move with it (the chart follows visit dates). |
| 9 | Old rows with no visit | Placed in the visit that was running when they were recorded. They show in that visit and later, but they aren't "owned" by it: undo can't remove them. |
| 10 | No visit today, nothing loaded | Changes save with no visit, ordered by their date, as today. The date picker stays. |
| 11 | Future booked visits | Not a session yet. Tapping one opens the visit dialog as before. Today's booked visit **is** a session. |
| 12 | Cancelled or missed visits | Not a session, unless they already have chart rows. Then they still count and can be loaded. |
| 13 | A visit with chart rows is deleted | Its rows stay and are placed by their date (rule 3), so nothing is lost. If that visit was loaded, Charting falls back to Latest. |
| 14 | Two devices edit the same tooth in the same visit, offline | Both rows sync (rows are never overwritten). The newest write in that visit wins. |
| 15 | A procedure is marked done | Its chart rows go into the procedure's visit; a new procedure gets the loaded visit or today's visit. |
| 16 | Perio and endo layers in an old visit | Show the newest perio exam / endo record from before the next visit. The plan always shows the current plan. Perio, endo and other records aren't saved per visit yet (phase 2). |
| 17 | Leave Charting or switch patient | Next time Charting opens on Latest. |
| 18 | Tap the visit that's already loaded (or today's visit while on Latest) | Opens that visit's notes dialog (the old tap behaviour). |

---

## Task 1: chart rows remember their visit

**1a.** File `lib/features/dental/data/models/tooth_chart_entry_model.dart`. Add two nullable `String` fields next to `procedureLogId`, everywhere `procedureLogId` appears in this file: the field list, the constructor (`this.visitId, this.baseEntryId,` optional), `fromJson`, `toJson`, `toMap`, `fromMap` and `copyWith`. Use the same map keys as the field names (`'visitId'`, `'baseEntryId'`). Doc comments:

```dart
  /// The visit (session) this change was saved in; null for older rows
  /// and changes saved outside a visit.
  final String? visitId;

  /// The row this change replaced on its tooth when it was saved ('' when
  /// there was none; null on older rows). Used to flag conflicts only.
  final String? baseEntryId;
```

**1b.** File `lib/core/services/local_database_service.dart`.
- In `_createToothChartEntriesTable`, add after the `procedureLogId TEXT,` line:
  ```
          visitId TEXT,
          baseEntryId TEXT,
  ```
- In the `_toothChartEntriesColumns` map, add next to the `procedureLogId` entry:
  ```dart
    'visitId': 'visitId TEXT',
    'baseEntryId': 'baseEntryId TEXT',
  ```
  (Existing databases get the columns added by `_ensureColumns`. No version bump.)

**1c.** File `lib/features/dental/data/repositories/dental_repository.dart`. Right after `saveToothChartEntry`, add:

```dart
  /// Soft-deletes a chart row (undoing a change in its own visit).
  Future<void> deleteToothChartEntry(String id) async {
    final db = await _localDbService.localDatabase;
    await db.update(
      'tooth_chart_entries',
      {
        'isDeleted': 1,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'syncStatus': 'pending',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
```

---

## Task 2: the session engine (new file, copy exactly)

Create `lib/features/dental/domain/chart_timeline.dart`:

```dart
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';

typedef _Placed = ({ToothChartEntryModel entry, int slot, DateTime time});

/// A patient's chart as a line of visits (sessions), like commits on one
/// git branch. A chart row belongs to the visit it was saved in
/// ([ToothChartEntryModel.visitId]); a row without one (older data, or
/// saved outside a visit) belongs to the last visit that had started when
/// it was recorded.
///
/// What a visit shows: for each tooth, the newest row from that visit or
/// an earlier one. So a change made in an earlier visit carries forward
/// to later visits, unless a later visit changed that tooth itself (a
/// collision: the later change wins from there on). Changes never travel
/// backwards.
class ChartTimeline {
  ChartTimeline._(this.sessions, this._index, this._placed);

  factory ChartTimeline(
    Iterable<Visit> visits,
    List<ToothChartEntryModel> entries, {
    required DateTime now,
  }) {
    final withRows = <String>{
      for (final e in entries)
        if (!e.isDeleted && e.visitId != null) e.visitId!,
    };
    final endOfToday = DateTime(now.year, now.month, now.day + 1);
    final sessions = <Visit>[
      for (final v in visits)
        if (!v.isDeleted &&
            (withRows.contains(v.id) ||
                (v.status != VisitStatus.cancelled &&
                    v.status != VisitStatus.missed &&
                    v.scheduledStart.isBefore(endOfToday))))
          v,
    ]..sort(_bySession);
    final index = <String, int>{
      for (var i = 0; i < sessions.length; i++) sessions[i].id: i,
    };

    // The last visit that had started at [t]; -1 before the first.
    int slotAt(DateTime t) {
      var slot = -1;
      for (var i = 0; i < sessions.length; i++) {
        if (sessions[i].scheduledStart.isAfter(t)) break;
        slot = i;
      }
      return slot;
    }

    final placed = <_Placed>[];
    for (final e in entries) {
      if (e.isDeleted) continue;
      final own = e.visitId == null ? null : index[e.visitId];
      placed.add(
        own != null
            // In its visit: ordered by when it was written.
            ? (entry: e, slot: own, time: e.createdAt)
            // No (known) visit: by the date it was recorded for.
            : (entry: e, slot: slotAt(e.recordedAt), time: e.recordedAt),
      );
    }
    placed.sort((a, b) {
      final s = a.slot.compareTo(b.slot);
      if (s != 0) return s;
      final t = a.time.compareTo(b.time);
      if (t != 0) return t;
      return a.entry.id.compareTo(b.entry.id);
    });
    return ChartTimeline._(sessions, index, placed);
  }

  static int _bySession(Visit a, Visit b) {
    final s = a.scheduledStart.compareTo(b.scheduledStart);
    if (s != 0) return s;
    final c = a.createdAt.compareTo(b.createdAt);
    if (c != 0) return c;
    return a.id.compareTo(b.id);
  }

  /// The visits that are sessions, oldest first.
  final List<Visit> sessions;
  final Map<String, int> _index;

  /// Every live row, oldest first along the line.
  final List<_Placed> _placed;

  /// Whether [visitId] is a session that can be loaded.
  bool isSession(String? visitId) =>
      visitId != null && _index.containsKey(visitId);

  /// The session [visitId], or null.
  Visit? sessionOf(String? visitId) {
    final i = visitId == null ? null : _index[visitId];
    return i == null ? null : sessions[i];
  }

  /// Rows up to this position are visible; null (Latest) sees them all.
  int _limit(String? visitId) =>
      visitId == null ? sessions.length : (_index[visitId] ?? sessions.length);

  /// The rows [visitId] can see, oldest first (null: every row).
  List<ToothChartEntryModel> visibleAt(String? visitId) {
    final limit = _limit(visitId);
    return [
      for (final p in _placed)
        if (p.slot <= limit) p.entry,
    ];
  }

  /// Each tooth's row as [visitId] shows it (null: the latest chart).
  Map<String, ToothChartEntryModel> latestAt(String? visitId) {
    final map = <String, ToothChartEntryModel>{};
    for (final e in visibleAt(visitId)) {
      map[e.toothNumber] = e;
    }
    return map;
  }

  /// [visitId]'s own rows for [tooth] (what undo removes).
  List<ToothChartEntryModel> ownRows(String visitId, String tooth) => [
    for (final p in _placed)
      if (p.entry.visitId == visitId && p.entry.toothNumber == tooth) p.entry,
  ];

  /// Teeth [visitId] changed itself.
  Set<String> changedIn(String visitId) => {
    for (final p in _placed)
      if (p.entry.visitId == visitId) p.entry.toothNumber,
  };

  /// Later visits that changed [tooth] after [visitId], oldest first. An
  /// edit made in [visitId] carries forward only up to the first of them.
  List<Visit> laterChanges(String visitId, String tooth) {
    final i = _index[visitId];
    if (i == null) return const [];
    final slots = <int>{
      for (final p in _placed)
        if (p.slot > i && p.entry.toothNumber == tooth) p.slot,
    };
    return [
      for (final s in slots.toList()..sort())
        if (s >= 0 && s < sessions.length) sessions[s],
    ];
  }

  /// Teeth whose change in [visitId] was made on top of an older state:
  /// an earlier visit changed the tooth after (a conflict, as in git). The
  /// later change still wins; this only flags it. Saving the tooth again
  /// in [visitId] clears it.
  Set<String> conflictsIn(String visitId) {
    final i = _index[visitId];
    if (i == null) return const {};
    final before = <String, ToothChartEntryModel>{};
    final newestOwn = <String, ToothChartEntryModel>{};
    final beforeOwn = <String, ToothChartEntryModel?>{};
    for (final p in _placed) {
      if (p.slot > i) break;
      final e = p.entry;
      if (e.visitId == visitId) {
        newestOwn[e.toothNumber] = e;
        beforeOwn[e.toothNumber] = before[e.toothNumber];
      }
      before[e.toothNumber] = e;
    }
    return {
      for (final MapEntry(key: tooth, value: e) in newestOwn.entries)
        if (e.baseEntryId != null &&
            e.baseEntryId != (beforeOwn[tooth]?.id ?? ''))
          tooth,
    };
  }

  /// Where [visitId]'s view ends in time: when the next session starts
  /// (null for Latest or the last session). Records (perio, endo) from
  /// before this belong to that view.
  DateTime? cutoff(String? visitId) {
    final i = visitId == null ? null : _index[visitId];
    if (i == null || i + 1 >= sessions.length) return null;
    return sessions[i + 1].scheduledStart;
  }
}
```

---

## Task 3: session providers (new file, copy exactly)

Create `lib/features/dental/presentation/providers/chart_session_providers.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/domain/chart_timeline.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/patients/data/providers/patients_list_providers.dart';

/// The visit Charting has loaded as a session for a patient; null shows
/// the latest chart.
final chartSessionProvider = StateProvider.family<String?, String>(
  (ref, patientId) => null,
);

/// The patient's visits and chart rows as one line of sessions.
final chartTimelineProvider = Provider.family<ChartTimeline, String>((
  ref,
  patientId,
) {
  final visits =
      ref.watch(patientSummaryProvider(patientId)).value?.visits ??
      const <Visit>[];
  final entries =
      ref.watch(patientToothChartProvider(patientId)).value ??
      const <ToothChartEntryModel>[];
  return ChartTimeline(visits, entries, now: DateTime.now());
});

/// The loaded session for [patientId], if it is still one.
String? watchChartSession(WidgetRef ref, String patientId) {
  final id = ref.watch(chartSessionProvider(patientId));
  return ref.watch(chartTimelineProvider(patientId)).isSession(id) ? id : null;
}

/// The visit a new chart change for [patientId] is saved in: the loaded
/// session, else today's visit, else none (saved by its date).
Visit? chartWriteVisit(WidgetRef ref, String patientId) {
  final timeline = ref.read(chartTimelineProvider(patientId));
  final loaded = timeline.sessionOf(ref.read(chartSessionProvider(patientId)));
  if (loaded != null) return loaded;
  final visits = ref.read(patientSummaryProvider(patientId)).value?.visits;
  final now = DateTime.now();
  for (final v in visits ?? const <Visit>[]) {
    if (v.status == VisitStatus.cancelled) continue;
    if (DateUtils.isSameDay(v.scheduledStart, now)) return v;
  }
  return null;
}

/// What a new row on [tooth] saved in [visit] replaces ('' for nothing).
String chartBaseFor(WidgetRef ref, String patientId, Visit? visit, String tooth) =>
    ref.read(chartTimelineProvider(patientId)).latestAt(visit?.id)[tooth]?.id ??
    '';
```

---

## Task 4: the chart reads the loaded session

**4a.** File `lib/features/dental/presentation/desktop/chart/tooth_chart_data.dart`, `factory ToothChartData.from(...)`. Add an optional named parameter `Map<String, ToothChartEntryModel>? latest,` (next to `perioExam` and `endo`), and change the first line of the body from

```dart
    final latest = DentalChart.latest(entries);
```
to
```dart
    // A session's view when given; else the newest row per tooth.
    final latestRows = latest ?? DentalChart.latest(entries);
```
Then rename the uses of that local `latest` below it in this factory to `latestRows` (they are `latest.keys` and `latest[n]`).

**4b.** File `lib/features/dental/presentation/desktop/tooth_detail_screen.dart`, function `watchPatientChart`. Add the import `package:doctor_management_app/features/dental/presentation/providers/chart_session_providers.dart` and `package:doctor_management_app/features/dental/domain/chart_timeline.dart`. Then:

- Change the cache map's record type (`_charts`, just above the function) so it holds 7 values: `(List<Object?>, List<Object?>, List<Object?>, List<Object?>, ChartTimeline, String?, ToothChartData)`. Keep however the existing four list types are written; add `ChartTimeline, String?,` before `ToothChartData`.
- Replace everything from `final last = _charts[patientId];` to the end of the function with:

```dart
  final timeline = ref.watch(chartTimelineProvider(patientId));
  final session = watchChartSession(ref, patientId);
  final last = _charts[patientId];
  if (last != null &&
      identical(last.$1, entries) &&
      identical(last.$2, plan) &&
      identical(last.$3, perio) &&
      identical(last.$4, endo) &&
      identical(last.$5, timeline) &&
      last.$6 == session) {
    return last.$7;
  }
  // An older session shows the records from before the next visit.
  final cutoff = timeline.cutoff(session);
  bool asOf(DentalRecord r) => cutoff == null || r.recordedAt.isBefore(cutoff);
  final perioAsOf = perio.where(asOf).toList();
  final data = ToothChartData.from(
    entries,
    plan,
    latest: timeline.latestAt(session),
    perioExam: perioAsOf.isEmpty ? null : perioAsOf.first,
    endo: endo.where(asOf).toList(),
  );
  _charts[patientId] = (entries, plan, perio, endo, timeline, session, data);
  return data;
```

**4c.** File `lib/features/dental/presentation/desktop/tooth_detail_view.dart`, in `build` (around line 278), where it does:

```dart
    final data = ToothChartData.from(entries, plan);
    final latest = DentalChart.latest(entries);
```
replace with:

```dart
    // The loaded session's view (Latest when none).
    final timeline = ref.watch(chartTimelineProvider(p.id));
    final session = watchChartSession(ref, p.id);
    final visible = timeline.visibleAt(session);
    final latest = timeline.latestAt(session);
    final data = ToothChartData.from(entries, plan, latest: latest);
```
In the `timeline` list right below (the tooth's history; it starts `for (final e in entries)`), change `for (final e in entries)` to `for (final e in visible)`. Rename that local history list from `timeline` to `history` if the name clashes with the new `timeline` variable (it will). Update its uses (`shown = ... timeline ...`) to `history`. Add the import for `chart_session_providers.dart`.

---

## Task 5: saving goes into the session

Add the `chart_session_providers.dart` import wherever you use it.

**5a. Tooth detail save** (`tooth_detail_view.dart`, the method that calls `saveToothChartEntry`, around line 190–235).
- At the start of the `try`, before building the row, add:
  ```dart
      final visit = chartWriteVisit(ref, p.id);
      final timelineBefore = ref.read(chartTimelineProvider(p.id));
  ```
- In the `ToothChartEntryModel(...)` add:
  ```dart
              visitId: visit?.id,
              baseEntryId: chartBaseFor(ref, p.id, visit, _tooth),
  ```
  and change `recordedAt: at,` to `recordedAt: visit?.scheduledStart ?? at,`.
- Add a state field next to `_notice`: `String? _carryNote;` and clear it wherever `_notice = null;` is set (in `_load`, `_edit` and the start of save).
- In the success `setState` after saving, add:
  ```dart
        final later = visit == null
            ? const <Visit>[]
            : timelineBefore.laterChanges(visit.id, _tooth);
        _carryNote = later.isEmpty
            ? null
            : 'Saved in the ${DentalFormat.shortDate(visit!.scheduledStart)} visit. '
                  'The ${DentalFormat.shortDate(later.first.scheduledStart)} visit '
                  'also changed this tooth, so from then on the chart keeps '
                  'that change.';
  ```
- Show it under the `_notice` text (around line 669), in amber, not red:
  ```dart
          if (_carryNote != null) ...[
            const SizedBox(height: CruSpace.s8),
            Text(_carryNote!, style: CruType.subhead.tint(c.amberText)),
          ],
  ```

**5b. Date field in the tooth detail** (the `CruPickerField(label: 'Date', ...)` around line 641). When `chartWriteVisit(ref, p.id)` is not null, show the visit instead of a date you can pick: `value: 'Visit · ${DentalFormat.shortDate(visit.scheduledStart)}'`, `onTap: null` (if `CruPickerField` requires a non-null `onTap`, pass `() {}`), and no "Today" pill. When it is null, keep the field exactly as it is now.

**5c. Undo this visit's change** (tooth detail). Under the save status line ("Saved to the chart" / "As on the chart"), when `chartWriteVisit(ref, p.id)` is not null and `timeline.ownRows(visit.id, _tooth)` is not empty, show a `CruLink` with the label `"Undo this visit's change"`. On press:
  ```dart
    final repo = ref.read(dentalRepositoryProvider);
    for (final r in timeline.ownRows(visit.id, _tooth)) {
      await repo.deleteToothChartEntry(r.id);
    }
    refreshDentalPatient(ref, p.id);
    if (mounted) setState(() => _draftFor = null); // reload the draft
  ```
  (`_draftFor = null` makes `build` call `_load` again with the new latest row. If that doesn't happen in this file, call `_load(...)` the way `build` does.)

**5d. The other finding dialog** (`lib/features/dental/presentation/desktop/dental_dialogs.dart`, `_ToothFindingDialogState`, the `saveToothChartEntry(ToothChartEntryModel(...))` around line 138). Same as 5a's first two bullets: get `visit` with `chartWriteVisit(ref, widget.patient.id)` (use whatever the patient field is called there), add `visitId` and `baseEntryId` (tooth = the dialog's tooth), and `recordedAt: visit?.scheduledStart ?? at`. No carry note needed here.

**5e. Procedures** (same file, `_ProcedureLogDialogState`, around line 449):
- `visitId: e?.visitId,` → `visitId: e?.visitId ?? chartWriteVisit(ref, widget.patient.id)?.id,`
- In the chart rows written for a completed procedure (the `for (final tooth in teeth)` loop), add `visitId: log.visitId,` and `baseEntryId: chartBaseFor(ref, widget.patient.id, ref.read(chartTimelineProvider(widget.patient.id)).sessionOf(log.visitId), tooth),`.

---

## Task 6: Charting loads sessions from the Visits card

File `lib/features/dental/presentation/desktop/charting_screen.dart`. Add the imports for `chart_session_providers.dart` and `package:doctor_management_app/features/patients/presentation/widgets/details/visit_session_dialog.dart` (if not already imported).

**6a. Open on Latest.** In `initState`, add:
```dart
    // Each time Charting opens it starts on the latest chart.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(chartSessionProvider(widget.patient.id).notifier).state = null;
      }
    });
```

**6b. Tap a visit = load it.** In `build`, find `void openVisit(Visit v) => showVisitSessionDialog(context, visit: v, patient: p);` and replace with:
```dart
    final session = watchChartSession(ref, p.id);
    final timeline = ref.watch(chartTimelineProvider(p.id));
    // A visit row loads that visit as a session; tapping the one already
    // shown (today's on Latest) opens its notes. Visits that aren't a
    // session yet (future, cancelled) open their notes too.
    void openVisit(Visit v) {
      final shown = session ?? today?.id;
      if (!timeline.isSession(v.id) || v.id == shown) {
        showVisitSessionDialog(context, visit: v, patient: p);
        return;
      }
      ref.read(chartSessionProvider(p.id).notifier).state =
          v.id == today?.id ? null : v.id;
    }
```
(`today` is already defined in `build`: `final today = summary == null ? null : PatientActions.todaysVisit(summary, now);`. If it is defined below `openVisit`, move these lines below it.)

**6c. Show which visit is loaded.** Give `_VisitsCard` a new field `final String? viewing;` (required in the constructor, pass `viewing: session` where `_VisitsCard(` is built), and pass it to each `_VisitRow` as `viewing: v.id == widget.viewing`. In `_VisitRow` add `final bool viewing;`. When `viewing` is true: the row background is `c.inset` (instead of the hover/today colour), and the status text on the right reads `'Viewing'` in `CruType.caption.w600.tint(c.label)`.

**6d. The session bar.** Add this widget at the end of `charting_screen.dart`:

```dart
/// Above the workspaces while an older visit is loaded: which visit, what
/// it changed, any conflicts, and the way back to the latest chart.
class _SessionBar extends StatelessWidget {
  const _SessionBar({
    required this.visit,
    required this.changed,
    required this.conflicts,
    required this.onNotes,
    required this.onLatest,
  });

  final Visit visit;
  final Set<String> changed;
  final Set<String> conflicts;
  final VoidCallback onNotes;
  final VoidCallback onLatest;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    String teeth(Set<String> s) => (s.toList()..sort()).join(', ');
    return Container(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s16,
        CruSpace.s12,
        CruSpace.s12,
        CruSpace.s12,
      ),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.control),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Viewing the ${DentalFormat.shortDate(visit.scheduledStart)} '
                  'visit · ${visitTitle(visit)}',
                  style: CruType.callout.w600.tint(c.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: CruSpace.s2),
                Text(
                  changed.isEmpty
                      ? 'No changes in this visit yet. Changes made here carry '
                            'forward to later visits, except on teeth they changed.'
                      : 'Changed here: ${teeth(changed)}. Changes carry forward '
                            'to later visits, except on teeth they changed.',
                  style: CruType.subhead.tint(c.label2),
                ),
                if (conflicts.isNotEmpty) ...[
                  const SizedBox(height: CruSpace.s2),
                  Text(
                    'An earlier visit changed ${teeth(conflicts)} after this '
                    'visit did. Save the tooth again here to keep it as it is.',
                    style: CruType.subhead.tint(c.amberText),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          CruButton(
            label: 'Visit notes',
            kind: CruButtonKind.secondary,
            onPressed: onNotes,
          ),
          const SizedBox(width: CruSpace.s8),
          CruButton(
            label: 'Back to latest',
            kind: CruButtonKind.secondary,
            onPressed: onLatest,
          ),
        ],
      ),
    );
  }
}
```

Then in `build`, in the `final below = Column(` children, right after `switcher,`, add:
```dart
            if (session != null) ...[
              const SizedBox(height: CruSpace.s10),
              _SessionBar(
                visit: timeline.sessionOf(session)!,
                changed: timeline.changedIn(session),
                conflicts: timeline.conflictsIn(session),
                onNotes: () => showVisitSessionDialog(
                  context,
                  visit: timeline.sessionOf(session)!,
                  patient: p,
                ),
                onLatest: () =>
                    ref.read(chartSessionProvider(p.id).notifier).state = null,
              ),
            ],
```

(`visitTitle` and `DentalFormat` are already used in this file by `_VisitRow`; if `visitTitle` isn't visible here, use `visit.treatmentType ?? 'Visit'`.)

---

## Check (once, at the end)

Run from `CruDoc/`:

```
flutter analyze lib/features/dental lib/core/services/local_database_service.dart lib/features/patients/presentation/widgets/details/visit_session_dialog.dart
```

Fix any errors and warnings in the files you changed. Then stop and report:

1. Which tasks you did, and any step you skipped (with what you saw instead).
2. The final `flutter analyze` output.

Do not run the app. The user will test on the PC:

1. Open a patient with two past visits A (older) and B (newer). In Latest, mark tooth 16 fractured (saved in today's visit, or outside a visit if there is none).
2. Tap visit A in Visits: the bar says "Viewing the … visit", and the chart shows the teeth as of A.
3. In A, mark tooth 21 caries. Tap B: tooth 21 shows caries there too (carried forward).
4. In B, mark tooth 21 restored. Tap A, change 21 to fractured: the tooth dialog shows the amber "also changed this tooth" note. Tap B: it still shows 21 restored, and its bar flags 21 ("An earlier visit changed 21 after this visit did").
5. In B, open 21 and save it again: the flag clears.
6. Tap A, open 21, "Undo this visit's change": A shows 21 as it was before A (healthy). B still shows 21 restored, and its bar flags 21 again (A changed underneath it).
7. In A, mark tooth 34 missing. Tap B and the latest chart: 34 shows missing in both (no later visit touched it).
8. "Back to latest" returns to the full chart.
