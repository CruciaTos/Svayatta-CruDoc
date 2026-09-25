import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// Where the evening session starts. The clinic's own session times are
/// not stored anywhere yet (see IMPLEMENTATION_REPORT.md, GAP "clinic
/// hours"), so this is the spec's default: 17:00.
const int kEveningSessionStartHour = 17;

/// Where Auto appearance hands back to Day in the morning.
const int kDaySessionStartHour = 5;

bool isEveningSession(DateTime t) =>
    t.hour >= kEveningSessionStartHour || t.hour < kDaySessionStartHour;

/// Status of one schedule row, derived from `QueueStatus` / `VisitStatus`.
enum ScheduleStatus {
  inConsultation,
  called,
  waiting,
  booked,
  done,
  missed,
  skipped;

  bool get isNow => this == inConsultation || this == called;

  /// Still expected to be seen today.
  bool get isOpen =>
      this == inConsultation || this == called || this == waiting ||
      this == booked || this == skipped;
}

/// One row in Today's schedule: a booked visit, a queue token, or both
/// (a booked visit that has been checked in).
class ScheduleItem {
  const ScheduleItem({
    required this.id,
    required this.time,
    required this.name,
    required this.firstName,
    required this.status,
    this.ageSex,
    this.reason,
    this.kindLabel,
    this.waitMinutes,
    this.tokenNumber,
    this.patient,
    this.queueEntryId,
    this.visitId,
  });

  final String id;

  /// Appointment time, or check-in time for a walk-in.
  final DateTime time;
  final String name;
  final String firstName;
  final ScheduleStatus status;

  /// "45 M".
  final String? ageSex;

  /// Reason for the visit, when one was recorded.
  final String? reason;

  /// "Returning", "New patient", "Walk-in", "Home visit".
  final String? kindLabel;

  /// For waiting rows.
  final int? waitMinutes;
  final int? tokenNumber;
  final Patient? patient;
  final String? queueEntryId;
  final String? visitId;
}

class GlanceData {
  const GlanceData({
    required this.seen,
    required this.total,
    required this.waiting,
    this.averageWaitMinutes,
  });

  final int seen;

  /// Everyone expected today (seen + still to see).
  final int total;
  final int waiting;
  final int? averageWaitMinutes;

  int get stillToSee => total - seen;
  double get progress => total == 0 ? 0 : seen / total;
}

class CollectedToday {
  const CollectedToday({
    required this.today,
    required this.sameDayLastWeek,
    required this.weekdayName,
  });

  final double today;
  final double sameDayLastWeek;

  /// "Wednesday".
  final String weekdayName;

  double get difference => today - sameDayLastWeek;
}

/// The earliest waiting patient.
class UpNextData {
  const UpNextData({
    required this.entryId,
    required this.name,
    required this.waitMinutes,
    required this.details,
    required this.isNextInCallOrder,
    this.tokenNumber,
    this.reason,
    this.patient,
    this.servingName,
  });

  final String entryId;
  final String name;
  final int waitMinutes;

  /// "23 y · Female · Returning · Last visit 14 Aug, seasonal allergy".
  final String details;

  /// True when `QueueRepository.callNext` would call this token. The
  /// repository can only call the next token in its own order, so the
  /// dashboard can start this consultation directly only when this is it.
  final bool isNextInCallOrder;
  final int? tokenNumber;
  final String? reason;
  final Patient? patient;

  /// Someone already being served, if any.
  final String? servingName;
}

class CollectionDay {
  const CollectionDay({
    required this.date,
    required this.amount,
    required this.isToday,
  });

  final DateTime date;
  final double amount;
  final bool isToday;
}

class CollectionsData {
  const CollectionsData({required this.days});

  /// Oldest first, today last.
  final List<CollectionDay> days;

  double get total => days.fold(0, (sum, d) => sum + d.amount);
  double get max => days.fold(0, (m, d) => d.amount > m ? d.amount : m);
}

enum AttentionKind { lowStock, expiring }

class AttentionItem {
  const AttentionItem({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
  });

  final AttentionKind kind;
  final String title;
  final String subtitle;
  final String actionLabel;
}

/// Everything the dashboard shows, computed from repository data.
/// Sections are null while their source is still loading.
class DashboardData {
  const DashboardData({
    required this.now,
    this.glance,
    this.collected,
    this.upNext,
    this.nextBooking,
    this.schedule,
    this.collections,
    this.attention,
  });

  final DateTime now;
  final GlanceData? glance;
  final CollectedToday? collected;
  final UpNextData? upNext;

  /// The next booked visit that hasn't checked in (for "No one waiting").
  final DateTime? nextBooking;
  final List<ScheduleItem>? schedule;
  final CollectionsData? collections;
  final List<AttentionItem>? attention;

  bool get scheduleReady => schedule != null;
}
