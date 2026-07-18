import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/repo/visits_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';

/// Provides the single [VisitRepository] instance used across the
/// appointments/visitations feature. Mirrors [patientRepositoryProvider]
/// from the patients feature.
final visitRepositoryProvider = Provider<VisitRepository>(
  (ref) => VisitRepository(),
);

/// Live stream of active upcoming visits, ordered by start time
/// ascending. Backed by SQLite via [VisitRepository.watchUpcomingVisits] —
/// emits a fresh list automatically whenever a visit is created, updated,
/// rescheduled, cancelled, or soft-deleted. The UI should watch this (or
/// [visitsWithPatientsProvider] below) instead of holding any local list.
final visitsStreamProvider = StreamProvider<List<Visit>>(
  (ref) => ref.watch(visitRepositoryProvider).watchUpcomingVisits(),
);

/// A [Visit] paired with its resolved [Patient].
///
/// [Visit] only stores `patientId` — never the patient's name, phone,
/// etc. — so the UI needs this join to render a card or details screen.
/// [patient] is null if no matching patient could be found (e.g. it was
/// deleted/archived after the visit was created).
class VisitWithPatient {
  final Visit visit;
  final Patient? patient;
  const VisitWithPatient({required this.visit, required this.patient});
}

/// Joins [visitsStreamProvider] with the patients feature's existing
/// `patientsStreamProvider`, so screens never need to do their own
/// patient lookups. Recomputes whenever either the visits list or the
/// patients list changes.
final visitsWithPatientsProvider =
    Provider<AsyncValue<List<VisitWithPatient>>>((ref) {
  final visitsAsync = ref.watch(visitsStreamProvider);
  final patientsAsync = ref.watch(patientsStreamProvider);

  if (visitsAsync.isLoading || patientsAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (visitsAsync.hasError) {
    return AsyncValue.error(visitsAsync.error!, visitsAsync.stackTrace!);
  }
  if (patientsAsync.hasError) {
    return AsyncValue.error(patientsAsync.error!, patientsAsync.stackTrace!);
  }

  final visits = visitsAsync.value!;
  final patientsById = {for (final p in patientsAsync.value!) p.id: p};

  final combined = visits
      .map(
        (v) => VisitWithPatient(visit: v, patient: patientsById[v.patientId]),
      )
      .toList();

  return AsyncValue.data(combined);
});

/// Live visit history for a single patient, most recent first — intended
/// for [PatientDetailsPage]'s "Session History" section. `.family`
/// because each patient needs its own independent stream, keyed by
/// [patientId].
final visitsForPatientProvider = StreamProvider.family<List<Visit>, String>(
  (ref, patientId) =>
      ref.watch(visitRepositoryProvider).watchVisitsForPatient(patientId),
);