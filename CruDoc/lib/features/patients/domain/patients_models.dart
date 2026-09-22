import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// Single-select filter chips on the Patients list, in display order.
enum PatientFilter {
  all('All'),
  last7Days('Last 7 days'),
  followUpOverdue('Follow-up overdue'),
  balanceDue('Balance due'),
  inTreatment('In treatment'),
  newThisMonth('New this month');

  const PatientFilter(this.label);
  final String label;

  /// Amber dot before the label: needs attention.
  bool get attention => this == followUpOverdue || this == balanceDue;

  /// Work-through filters open straight into split mode with the first
  /// patient selected, a summary strip and their own sort.
  bool get workThrough => this == followUpOverdue || this == balanceDue;
}

enum PatientSort {
  lastVisit('Last visit'),
  name('Name'),
  amountDue('Amount due'),
  mostOverdue('Most overdue'),
  newest('Recently added');

  const PatientSort(this.label);
  final String label;
}

/// How one visit reads on Patient details (Visits card, stepper).
enum VisitRowStatus {
  /// Scheduled, still ahead.
  booked,

  /// Completed.
  done,

  /// Scheduled, time has passed, never marked done or missed. Amber
  /// "not recorded" with an Update action — never "Pending".
  notRecorded,
  cancelled,
  missed,
}

/// Everything the Patients screens show about one patient, derived only
/// from the patient record and that patient's visits (so the list,
/// preview and details can never disagree).
class PatientSummary {
  const PatientSummary({
    required this.patient,
    required this.visits,
    required this.lastVisit,
    required this.nextVisit,
    required this.overdueSince,
    required this.completedCount,
    required this.latestNote,
    required this.balance,
    required this.isNewThisMonth,
    required this.seenToday,
    required this.seenWithin7Days,
    required this.inTreatment,
  });

  final Patient patient;

  /// This patient's non-deleted visits, newest first.
  final List<Visit> visits;

  /// Latest completed visit that has started.
  final Visit? lastVisit;

  /// Earliest scheduled visit from now on.
  final Visit? nextVisit;

  /// When nothing is booked ahead but a booked visit passed without being
  /// recorded: that visit's time. Drives "Follow-up overdue".
  final DateTime? overdueSince;

  /// Completed visits: the one count used everywhere ("N visits").
  final int completedCount;

  /// Newest visit with a note (`therapistNotes`), if any.
  final Visit? latestNote;

  /// `Patient.packageBalance`, never negative.
  final double balance;

  final bool isNewThisMonth;
  final bool seenToday;
  final bool seenWithin7Days;

  /// Has been seen and has a visit booked ahead.
  final bool inTreatment;

  String get id => patient.id;
  String get name => patient.fullName;
  bool get hasBalance => balance > 0;
  bool get followUpOverdue => overdueSince != null;

  /// Latest visit's treatment text, if any was recorded.
  String? get treatment {
    for (final v in visits) {
      final t = v.treatmentType?.trim();
      if (t != null && t.isNotEmpty && v.status == VisitStatus.completed) {
        return t;
      }
    }
    return null;
  }

  String? get condition {
    final d = patient.diagnosisDisplay.trim();
    return d.isEmpty ? null : d;
  }

  /// Visits ahead, soonest first.
  List<Visit> upcoming(DateTime now) => visits
      .where((v) =>
          v.status == VisitStatus.scheduled && !v.scheduledStart.isBefore(now))
      .toList()
    ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));

  /// Visits that have started, newest first.
  List<Visit> past(DateTime now) =>
      visits.where((v) => v.scheduledStart.isBefore(now)).toList();
}

/// A titled run of rows ("Seen today 2"). [title] is null for a single
/// untitled group.
class PatientGroup {
  const PatientGroup({required this.title, required this.rows});
  final String? title;
  final List<PatientSummary> rows;
}

/// "₹78,400 outstanding · 12 patients" above the Balance due list.
class BalanceStripData {
  const BalanceStripData({required this.total, required this.patients});
  final double total;
  final int patients;
}

/// "7 patients · longest overdue 41 days" above Follow-up overdue.
class FollowUpStripData {
  const FollowUpStripData({required this.patients, required this.longestDays});
  final int patients;
  final int longestDays;
}
