import 'dart:math' as math;

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';

/// Clicks on empty time snap to this grid. The clinic's slot length isn't
/// stored (GAP), so this is the smallest duration the schedule dialog
/// offers, not a clinic setting.
const int kApptSnapMinutes = 15;

/// Pure calendar logic for the Appointments screens. No I/O.
abstract final class ApptsBuilder {
  static DateTime dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Monday of the week containing [t].
  static DateTime weekStart(DateTime t) =>
      dateOnly(t).subtract(Duration(days: t.weekday - DateTime.monday));

  /// The 7 dates Monday..Sunday of the week containing [t].
  static List<DateTime> weekDays(DateTime t) {
    final s = weekStart(t);
    return [for (var i = 0; i < 7; i++) DateTime(s.year, s.month, s.day + i)];
  }

  /// Every date shown in a Monday-first month grid (whole weeks).
  static List<DateTime> monthGrid(DateTime month) {
    final first = DateTime(month.year, month.month);
    final last = DateTime(month.year, month.month + 1, 0);
    final start = weekStart(first);
    final end = weekStart(last).add(const Duration(days: 6));
    final days = <DateTime>[];
    for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
      days.add(d);
    }
    return days;
  }

  // ---------------------------------------------------------------------
  // Items
  // ---------------------------------------------------------------------

  /// Turns visits into calendar items. Cancelled and deleted visits are
  /// dropped. Today's queue decides waiting / in consultation, the same
  /// way the dashboard does.
  static List<ApptItem> items({
    required List<Visit> visits,
    required List<Patient> patients,
    required List<QueueEntry> todaysQueue,
    required DateTime now,
  }) {
    final patientsById = {for (final p in patients) p.id: p};
    final queueByVisit = <String, QueueEntry>{
      for (final e in todaysQueue)
        if (e.linkedVisitId != null && e.linkedVisitId!.isNotEmpty)
          e.linkedVisitId!: e,
    };

    final live = visits
        .where((v) => !v.isDeleted && v.status != VisitStatus.cancelled)
        .toList()
      ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));

    // First visit per patient, for New vs Returning.
    final firstVisitId = <String, String>{};
    for (final v in live) {
      firstVisitId.putIfAbsent(v.patientId, () => v.id);
    }

    return _grouped([
      for (final v in live)
        _item(
          v,
          patientsById[v.patientId],
          sameDay(v.scheduledStart, now) ? queueByVisit[v.id] : null,
          firstVisitId[v.patientId] == v.id,
          now,
        ),
    ]);
  }

  /// Visits booked together (same group id) become one item, led by the
  /// first booked. Order is kept: the group sits where its lead was.
  static List<ApptItem> _grouped(List<ApptItem> items) {
    final byGroup = <String, List<ApptItem>>{};
    for (final i in items) {
      final g = i.visit.groupId;
      if (g != null && g.isNotEmpty) byGroup.putIfAbsent(g, () => []).add(i);
    }
    if (byGroup.values.every((m) => m.length < 2)) return items;
    for (final m in byGroup.values) {
      m.sort((a, b) => a.visit.createdAt.compareTo(b.visit.createdAt));
    }
    final done = <String>{};
    return [
      for (final i in items)
        if (i.visit.groupId == null ||
            i.visit.groupId!.isEmpty ||
            byGroup[i.visit.groupId]!.length < 2)
          i
        else if (done.add(i.visit.groupId!))
          ApptItem.group(byGroup[i.visit.groupId]!),
    ];
  }

  /// Patients (not appointments) with [status]: a couple seen together is
  /// two patients seen.
  static int patientsWith(Iterable<ApptItem> items, ApptStatus status) =>
      items.fold(
        0,
        (n, i) => n +
            (i.isGroup
                ? i.members.where((m) => m.status == status).length
                : (i.status == status ? 1 : 0)),
      );

  static ApptItem _item(
    Visit v,
    Patient? p,
    QueueEntry? q,
    bool isFirst,
    DateTime now,
  ) {
    final name = p == null ? 'Patient' : p.fullName.trim();
    final parts = name.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final first = parts.isEmpty ? name : parts.first;
    final short = parts.length > 1 ? '$first ${parts.last[0].toUpperCase()}.' : first;

    // A pre-booked visit enters the queue as "waiting" at its appointment
    // time, before the patient arrives, so it only counts as waiting once
    // that time has passed (same rule as the dashboard).
    final arrived = q != null && !q.checkedInAt.isAfter(now);
    final status = switch (v.status) {
      VisitStatus.completed => ApptStatus.done,
      VisitStatus.missed => ApptStatus.missed,
      _ => switch (q?.status) {
          QueueStatus.completed => ApptStatus.done,
          QueueStatus.inConsultation ||
          QueueStatus.called =>
            ApptStatus.inConsultation,
          QueueStatus.waiting when arrived => ApptStatus.waiting,
          _ => ApptStatus.booked,
        },
    };

    final reason = _clean(v.treatmentType) ?? _clean(q?.reason);
    return ApptItem(
      visit: v,
      patient: p,
      status: status,
      name: name,
      firstName: first,
      shortName: short,
      isNewPatient: isFirst,
      reason: reason,
      tokenNumber: q != null && q.tokenNumber > 0 ? q.tokenNumber : null,
      waitMinutes: status == ApptStatus.waiting
          ? math.max(0, now.difference(q!.checkedInAt).inMinutes)
          : null,
    );
  }

  static String? _clean(String? s) {
    final t = s?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  /// Items starting on [day], sorted by start.
  static List<ApptItem> forDay(List<ApptItem> all, DateTime day) =>
      all.where((i) => sameDay(i.start, day)).toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  /// Items starting within [from, to).
  static List<ApptItem> inRange(List<ApptItem> all, DateTime from, DateTime to) =>
      all
          .where((i) => !i.start.isBefore(from) && i.start.isBefore(to))
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  // ---------------------------------------------------------------------
  // Overlaps
  // ---------------------------------------------------------------------

  /// Groups one day's items transitively by overlap and assigns columns
  /// greedily by start time. Every item lands in exactly one group; a
  /// group of one is not an overlap.
  static List<OverlapGroup> groups(List<ApptItem> dayItems, DateTime now) {
    final sorted = [...dayItems]..sort((a, b) {
        final c = a.start.compareTo(b.start);
        return c != 0 ? c : b.end.compareTo(a.end);
      });
    final result = <OverlapGroup>[];
    var current = <ApptItem>[];
    DateTime? currentEnd;

    void flush() {
      if (current.isEmpty) return;
      result.add(_layout(current, now));
      current = [];
      currentEnd = null;
    }

    for (final item in sorted) {
      if (currentEnd != null && !item.start.isBefore(currentEnd!)) flush();
      current.add(item);
      currentEnd = currentEnd == null || item.end.isAfter(currentEnd!)
          ? item.end
          : currentEnd;
    }
    flush();
    return result;
  }

  static OverlapGroup _layout(List<ApptItem> items, DateTime now) {
    final columnEnds = <DateTime>[];
    final columnOf = <String, int>{};
    for (final item in items) {
      var col = columnEnds.indexWhere((end) => !item.start.isBefore(end));
      if (col == -1) {
        columnEnds.add(item.end);
        col = columnEnds.length - 1;
      } else {
        columnEnds[col] = item.end;
      }
      columnOf[item.id] = col;
    }

    var peak = 1;
    for (final i in items) {
      final c = items
          .where((o) => !o.start.isAfter(i.start) && o.end.isAfter(i.start))
          .length;
      peak = math.max(peak, c);
    }

    final end = items.map((i) => i.end).reduce((a, b) => a.isAfter(b) ? a : b);
    // Nothing stores "kept" yet (GAP), so a live overlap is unsorted.
    final kind = end.isAfter(now) ? OverlapKind.unsorted : OverlapKind.past;
    return OverlapGroup(
      items: items,
      columnOf: columnOf,
      columns: columnEnds.length,
      kind: kind,
      peak: peak,
    );
  }

  /// The visit to suggest moving: the most recently booked (createdAt).
  static ApptItem latestBooked(OverlapGroup g) =>
      g.items.reduce((a, b) => b.visit.createdAt.isAfter(a.visit.createdAt) ? b : a);

  // ---------------------------------------------------------------------
  // Ranges, slots, counts
  // ---------------------------------------------------------------------

  /// The range to draw for [items] on [day] (items may span a whole week;
  /// only their times of day are used). Working hours aren't stored
  /// (GAP): one continuous session from the earliest start to the latest
  /// end, rounded out to whole hours, with no break band. An empty day
  /// draws an unlabeled 9 AM to 6 PM canvas so empty time can be clicked.
  static DayRange range(List<ApptItem> items, DateTime day) {
    final d = dateOnly(day);
    if (items.isEmpty) {
      return DayRange(sessions: [
        ClinicSession(
          start: d.add(const Duration(hours: 9)),
          end: d.add(const Duration(hours: 18)),
        ),
      ]);
    }
    var startMin = 24 * 60;
    var endMin = 0;
    for (final i in items) {
      final s = i.start.hour * 60 + i.start.minute;
      final e = s + i.durationMinutes;
      startMin = math.min(startMin, s);
      endMin = math.max(endMin, e);
    }
    final startHour = startMin ~/ 60;
    final endHour = math.min(24, (endMin + 59) ~/ 60);
    return DayRange(sessions: [
      ClinicSession(
        start: d.add(Duration(hours: startHour)),
        end: d.add(Duration(hours: math.max(endHour, startHour + 1))),
      ),
    ]);
  }

  /// Snaps [t] down to the [kApptSnapMinutes] grid.
  static DateTime snap(DateTime t) {
    final m = (t.minute ~/ kApptSnapMinutes) * kApptSnapMinutes;
    return DateTime(t.year, t.month, t.day, t.hour, m);
  }

  /// The next free start at or after [after] where a visit of
  /// [durationMinutes] overlaps no other scheduled visit that day and
  /// ends by [rangeEnd]. Candidates are [after] and the end of every
  /// other visit. [excludeVisitId] is the visit being moved. Returns null
  /// when nothing fits.
  static DateTime? nextFreeSlot({
    required List<ApptItem> dayItems,
    required DateTime after,
    required int durationMinutes,
    required DateTime rangeEnd,
    String? excludeVisitId,
  }) {
    final others = dayItems
        .where((i) => i.id != excludeVisitId && i.status != ApptStatus.missed)
        .toList();
    final candidates = <DateTime>{
      after,
      for (final o in others)
        if (!o.end.isBefore(after)) o.end,
    }.toList()
      ..sort();
    final d = Duration(minutes: durationMinutes);
    for (final t in candidates) {
      final end = t.add(d);
      if (end.isAfter(rangeEnd)) continue;
      final clash = others.any((o) => t.isBefore(o.end) && o.start.isBefore(end));
      if (!clash) return t;
    }
    return null;
  }

  /// Counts for one day's items.
  static ApptDayCounts counts(List<ApptItem> dayItems, DateTime day, DateTime now) {
    final groups = ApptsBuilder.groups(dayItems, now);
    return ApptDayCounts(
      date: dateOnly(day),
      appointments: dayItems.length,
      // Appointments by slot, seen and missed by patient.
      seen: patientsWith(dayItems, ApptStatus.done),
      missed: patientsWith(dayItems, ApptStatus.missed),
      inConsultation:
          dayItems.where((i) => i.status == ApptStatus.inConsultation).length,
      waiting: dayItems.where((i) => i.status == ApptStatus.waiting).length,
      booked: dayItems.where((i) => i.status == ApptStatus.booked).length,
      unsortedOverlaps: groups
          .where((g) => g.isOverlap && g.kind == OverlapKind.unsorted)
          .length,
      firstStart: dayItems.isEmpty ? null : dayItems.first.start,
    );
  }

  /// Default Day selection: the first patient waiting, otherwise the next
  /// upcoming visit, otherwise null.
  static ApptItem? defaultSelection(List<ApptItem> dayItems, DateTime now) {
    for (final i in dayItems) {
      if (i.status == ApptStatus.waiting) return i;
    }
    for (final i in dayItems) {
      if (i.status == ApptStatus.booked && !i.start.isBefore(now)) return i;
    }
    return null;
  }
}
