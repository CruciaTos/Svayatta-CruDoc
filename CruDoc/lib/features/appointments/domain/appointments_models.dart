import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// The views the Appointments shell can host.
/// The Schedule's views: Live is today's queue board, the rest are the
/// calendar.
enum ApptsView {
  live('Live'),
  day('Day'),
  week('Week'),
  month('Month'),
  agenda('Agenda'),

  /// Physiotherapy only: the day's home visits with a route map.
  visits('Visits');

  const ApptsView(this.label);
  final String label;
}

/// The one status mapping used by Day, Week and overlaps. Built from
/// [VisitStatus] plus today's queue (waiting / in consultation).
enum ApptStatus {
  /// Completed: inset fill, green check, secondary text.
  done,

  /// Missed: inset fill, strikethrough, tertiary text.
  missed,

  /// In consultation: accent-tint fill, accent text.
  inConsultation,

  /// Arrived and waiting: amber-tint fill, amber text.
  waiting,

  /// Booked: white fill with a hairline.
  booked,
}

/// How an overlap group is marked in the gutter.
enum OverlapKind {
  /// In the future and not sorted out: amber bar + "`<n>` at once" pill,
  /// counted in the header summary.
  unsorted,

  /// Kept on purpose (grey bar, no pill, no count). Nothing stores this
  /// decision yet (GAP), so the builder never produces it today.
  kept,

  /// The overlap ended before now: blocks side by side, no marker.
  past,
}

/// One visit as the calendar draws it. Cancelled and deleted visits are
/// never turned into items.
class ApptItem {
  const ApptItem({
    required this.visit,
    required this.patient,
    required this.status,
    required this.name,
    required this.firstName,
    required this.shortName,
    required this.isNewPatient,
    this.reason,
    this.tokenNumber,
    this.waitMinutes,
    this.members = const [],
  });

  /// Visits booked together (same [Visit.groupId]) drawn as one
  /// appointment: "Rahul Verma & Priya Verma" (three or more: "Rahul
  /// Verma + 2"), their reasons joined. The first booked leads: its visit
  /// is the appointment's slot and place.
  factory ApptItem.group(List<ApptItem> members) {
    final lead = members.first;
    String names(List<String> n) =>
        n.length == 2 ? '${n[0]} & ${n[1]}' : '${n.first} + ${n.length - 1}';
    final statuses = {for (final m in members) m.status};
    final status = statuses.contains(ApptStatus.inConsultation)
        ? ApptStatus.inConsultation
        : statuses.contains(ApptStatus.waiting)
            ? ApptStatus.waiting
            : statuses.contains(ApptStatus.booked)
                ? ApptStatus.booked
                : statuses.contains(ApptStatus.done)
                    ? ApptStatus.done
                    : ApptStatus.missed;
    final reasons = {for (final m in members) ?m.reason};
    final waits = [for (final m in members) ?m.waitMinutes];
    return ApptItem(
      visit: lead.visit,
      patient: lead.patient,
      status: status,
      name: names([for (final m in members) m.name]),
      firstName: names([for (final m in members) m.firstName]),
      shortName: '${lead.shortName} +${members.length - 1}',
      isNewPatient: members.any((m) => m.isNewPatient),
      reason: reasons.isEmpty ? null : reasons.join(' · '),
      tokenNumber: members.map((m) => m.tokenNumber).nonNulls.firstOrNull,
      waitMinutes:
          waits.isEmpty ? null : waits.reduce((a, b) => a > b ? a : b),
      members: members,
    );
  }

  final Visit visit;
  final Patient? patient;
  final ApptStatus status;

  /// Full display name, e.g. "Kavya Iyer".
  final String name;

  /// e.g. "Kavya".
  final String firstName;

  /// "First L." for the Week view, e.g. "Kavya I.".
  final String shortName;

  /// No earlier non-cancelled visit for this patient.
  final bool isNewPatient;

  /// `Visit.treatmentType` (or the queue reason), trimmed; null if empty.
  final String? reason;

  /// Queue token, only when the visit is checked into today's queue.
  final int? tokenNumber;

  /// Minutes since arrival, only when [status] is waiting.
  final int? waitMinutes;

  String get id => visit.id;

  /// Everyone on this appointment when patients are seen together (the
  /// first booked leads); empty for a single patient.
  final List<ApptItem> members;

  bool get isGroup => members.length > 1;

  int get patientCount => isGroup ? members.length : 1;

  /// This visit and, for a group, everyone else's.
  List<Visit> get visits =>
      isGroup ? [for (final m in members) m.visit] : [visit];

  /// Seen at the patient's home (physiotherapy), not at the clinic.
  bool get isHomeVisit => visit.visitType == VisitType.home;

  /// The home address, trimmed; null for clinic visits or when none was
  /// saved.
  String? get homeAddress {
    if (!isHomeVisit) return null;
    final a = visit.address.trim();
    return a.isEmpty ? null : a;
  }

  /// Reason, then the home address for home visits: the second line of
  /// every row and block.
  String? get detailLine {
    final parts = [?reason, ?homeAddress];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  DateTime get start => visit.scheduledStart;
  DateTime get end => visit.scheduledEnd;
  int get durationMinutes => visit.durationMinutes;

  /// Same test as `Visit.overlapsWith`: touching edges don't overlap.
  bool overlaps(ApptItem o) => start.isBefore(o.end) && o.start.isBefore(end);
}

/// A transitive group of overlapping visits on one day, laid out the way
/// Apple Calendar does: greedy columns by start time.
class OverlapGroup {
  const OverlapGroup({
    required this.items,
    required this.columnOf,
    required this.columns,
    required this.kind,
    required this.peak,
  });

  /// Sorted by start time.
  final List<ApptItem> items;

  /// Visit id -> column index (0-based).
  final Map<String, int> columnOf;

  /// Number of columns; each block is 1/[columns] wide with a 4 px gap.
  final int columns;
  final OverlapKind kind;

  /// Most visits sharing one moment ("`<n>` at once").
  final int peak;

  DateTime get start => items.first.start;
  DateTime get end =>
      items.map((i) => i.end).reduce((a, b) => a.isAfter(b) ? a : b);

  /// The earliest moment where [peak] visits overlap (for "2 visits at
  /// 12:30 PM").
  DateTime get peakStart {
    var best = items.first.start;
    var bestCount = 0;
    for (final i in items) {
      final count = items
          .where((o) => !o.start.isAfter(i.start) && o.end.isAfter(i.start))
          .length;
      if (count > bestCount) {
        bestCount = count;
        best = i.start;
      }
    }
    return best;
  }

  /// A group of one is not an overlap.
  bool get isOverlap => items.length > 1;
}

/// A drawn time range on the grid (one session, or the whole day when
/// working hours aren't stored).
class ClinicSession {
  const ClinicSession({required this.start, required this.end, this.label});

  /// "Morning session"; null when working hours aren't stored (GAP).
  final String? label;
  final DateTime start;
  final DateTime end;
}

/// The time ranges a day (or a whole week) draws. Working hours aren't
/// stored (GAP), so today this is always one continuous range from the
/// first to the last appointment, rounded out to whole hours, and there
/// is no break band.
class DayRange {
  const DayRange({required this.sessions});

  final List<ClinicSession> sessions;

  DateTime get start => sessions.first.start;
  DateTime get end => sessions.last.end;

  /// True when there is a break band between sessions.
  bool get hasBreak => sessions.length > 1;
}

/// Counts for one day, used by the header summary, Week column headers
/// and Month tiles.
class ApptDayCounts {
  const ApptDayCounts({
    required this.date,
    required this.appointments,
    required this.seen,
    required this.missed,
    required this.inConsultation,
    required this.waiting,
    required this.booked,
    required this.unsortedOverlaps,
    this.firstStart,
  });

  /// Date only (midnight).
  final DateTime date;

  /// Every non-cancelled visit that day.
  final int appointments;
  final int seen;
  final int missed;
  final int inConsultation;
  final int waiting;

  /// Still to come (booked, not yet arrived).
  final int booked;

  /// Unsorted future overlap groups that day.
  final int unsortedOverlaps;
  final DateTime? firstStart;

  bool get hasUnsortedOverlap => unsortedOverlaps > 0;
}
