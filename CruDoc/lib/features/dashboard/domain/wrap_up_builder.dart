import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_models.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';

/// Evening "Wrap up the day" contents, from real records only.
///
/// Not included, for lack of data (GAPs in IMPLEMENTATION_REPORT.md):
/// clinic closing time, overdue follow-ups, matching the cash drawer,
/// and a "close the day" workflow.
class WrapUpData {
  const WrapUpData({
    required this.patientsLeft,
    required this.draftNames,
    required this.tomorrowCount,
    this.tomorrowFirst,
  });

  /// Still expected today (waiting, booked, in consultation, skipped).
  final int patientsLeft;

  /// Patients whose AI Scribe draft notes still need review.
  final List<String> draftNames;
  final int tomorrowCount;
  final DateTime? tomorrowFirst;

  bool get hasRows => draftNames.isNotEmpty || tomorrowCount > 0;
}

WrapUpData buildWrapUp({
  required DateTime now,
  required List<ScheduleItem> schedule,
  required List<Visit> visits,
  required List<ConsultationNote> notes,
  required List<Patient> patients,
}) {
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final tomorrows = visits
      .where((v) =>
          !v.isDeleted &&
          v.status != VisitStatus.cancelled &&
          v.scheduledStart.year == tomorrow.year &&
          v.scheduledStart.month == tomorrow.month &&
          v.scheduledStart.day == tomorrow.day)
      .toList()
    ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));

  final byId = {for (final p in patients) p.id: p};
  final draftPatientIds = <String>{};
  for (final n in notes) {
    if (n.status == ConsultationNoteStatus.draft) draftPatientIds.add(n.patientId);
  }
  final draftNames = [
    for (final id in draftPatientIds)
      if ((byId[id]?.fullName.trim() ?? '').isNotEmpty) byId[id]!.fullName.trim(),
  ]..sort();

  return WrapUpData(
    patientsLeft: schedule.where((i) => i.status.isOpen).length,
    draftNames: draftNames,
    tomorrowCount: tomorrows.length,
    tomorrowFirst: tomorrows.isEmpty ? null : tomorrows.first.scheduledStart,
  );
}
