import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/domain/chart_timeline.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/chart_session_providers.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/charting_screen.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// The last chart built per patient, with the lists it came from. The
/// providers hand back the same lists until something changes, so the
/// chart (and its painted picture) is reused instead of rebuilt.
final _charts =
    <
      String,
      (
        List<Object?>,
        List<Object?>,
        List<Object?>,
        List<Object?>,
        ChartTimeline,
        String?,
        ToothChartData,
      )
    >{};

/// A patient's chart from every source: findings, the plan, the latest
/// perio exam and the endo records.
ToothChartData watchPatientChart(WidgetRef ref, String patientId) {
  final entries =
      ref.watch(patientToothChartProvider(patientId)).value ??
      const <ToothChartEntryModel>[];
  final plan =
      ref.watch(patientTreatmentPlanProvider(patientId)).value ??
      const <TreatmentPlanLineItemModel>[];
  final perio =
      ref
          .watch(
            patientRecordsProvider((patientId: patientId, kind: RecKind.perio)),
          )
          .value ??
      const <DentalRecord>[];
  final endo =
      ref
          .watch(
            patientRecordsProvider((patientId: patientId, kind: RecKind.endo)),
          )
          .value ??
      const <DentalRecord>[];
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
}

/// Opens the patient's perio chart: Charting on its Perio tab.
Future<void> openPerioChart(BuildContext context, Patient patient) =>
    openCharting(context, patient, tab: ChartingTab.perio);
