import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/appointments/presentation/patient_picker_dialog.dart';
import 'package:doctor_management_app/features/appointments/presentation/schedule_visit_sheet.dart';
import 'package:doctor_management_app/features/appointments/data/repo/visits_repo.dart';

/// Opens a flow to schedule a new visit:
/// 1. Shows a patient picker dialog
/// 2. On selection, opens the schedule visit sheet
/// 3. Returns true if a visit was successfully scheduled
///
/// Example:
/// ```dart
/// final success = await promptScheduleVisit(
///   context,
///   pickerTitle: 'Schedule an appointment for',
/// );
/// ```
Future<bool> promptScheduleVisit(
  BuildContext context, {
  String pickerTitle = 'Select a patient',
}) async {
  // Step 1: Pick a patient
  final patient = await showPatientPickerDialog(
    context,
    title: pickerTitle,
  );

  if (patient == null || !context.mounted) return false;

  // Step 2: Open the schedule visit sheet for the selected patient
  final visitRepository = VisitRepository();
  final success = await showScheduleVisitSheet(
    context,
    patient: patient,
    visitRepository: visitRepository,
  );

  return success;
}
