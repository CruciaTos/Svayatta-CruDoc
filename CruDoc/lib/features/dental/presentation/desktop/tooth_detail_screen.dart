import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/records/perio_chart_screen.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// A patient's chart from every source: findings, the plan, the latest
/// perio exam and the endo records.
ToothChartData watchPatientChart(WidgetRef ref, String patientId) {
  final entries = ref.watch(patientToothChartProvider(patientId)).value ??
      const <ToothChartEntryModel>[];
  final plan = ref.watch(patientTreatmentPlanProvider(patientId)).value ??
      const <TreatmentPlanLineItemModel>[];
  final perio = ref
          .watch(patientRecordsProvider((patientId: patientId, kind: RecKind.perio)))
          .value ??
      const <DentalRecord>[];
  final endo = ref
          .watch(patientRecordsProvider((patientId: patientId, kind: RecKind.endo)))
          .value ??
      const <DentalRecord>[];
  return ToothChartData.from(
    entries,
    plan,
    perioExam: perio.isEmpty ? null : perio.first,
    endo: endo,
  );
}

/// Opens the patient's perio chart full screen.
Future<void> openPerioChart(BuildContext context, Patient patient) =>
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => Theme(
          data: Theme.of(context),
          child: PerioChartScreen(patient: patient),
        ),
      ),
    );
