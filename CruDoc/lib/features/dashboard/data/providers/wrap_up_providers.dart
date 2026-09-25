import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/domain/wrap_up_builder.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';

/// AI Scribe notes attached to today's visits. The scribe repository only
/// queries notes per visit, so this watches each of today's visits.
final todaysScribeNotesProvider = Provider<List<ConsultationNote>>((ref) {
  final schedule = ref.watch(dashboardDataProvider).schedule ?? const [];
  final visitIds = {
    for (final item in schedule)
      if (item.visitId != null) item.visitId!,
  };
  return [
    for (final id in visitIds) ...?ref.watch(notesForVisitProvider(id)).value,
  ];
});

/// Evening "Wrap up the day". Null until the schedule has loaded.
final wrapUpProvider = Provider<WrapUpData?>((ref) {
  final data = ref.watch(dashboardDataProvider);
  final visits = ref.watch(allVisitsProvider).value;
  final patients = ref.watch(patientsStreamProvider).value;
  if (data.schedule == null || visits == null || patients == null) return null;
  return buildWrapUp(
    now: data.now,
    schedule: data.schedule!,
    visits: visits,
    notes: ref.watch(todaysScribeNotesProvider),
    patients: patients,
  );
});
