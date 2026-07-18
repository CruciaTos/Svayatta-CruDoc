import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/repo/visits_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';

/// Shared Riverpod providers for visit data — mirrors the shape of
/// patients/data/providers/patient_providers.dart.
///
/// This is the single source of truth for visit-related providers. A
/// second copy of these (`features/appointments/providers/visits_providers.dart`)
/// and an orphaned third copy (`appointments_provider.dart`) used to
/// exist alongside this file, each independently declaring their own
/// `visitRepositoryProvider` — they've been merged into this file and
/// deleted, since two `Provider<VisitRepository>` instances imported
/// into the same file caused an ambiguous-import error.
final visitRepositoryProvider = Provider<VisitRepository>(
  (ref) => VisitRepository(),
);

/// Streams patientId -> their most recent visit that has already
/// occurred, refreshed automatically after every visit write.
final lastVisitPerPatientProvider = StreamProvider<Map<String, Visit>>(
  (ref) => ref.watch(visitRepositoryProvider).watchLastVisitPerPatient(),
);

/// Streams upcoming scheduled visits, soonest first.
final upcomingVisitsProvider = StreamProvider<List<Visit>>(
  (ref) => ref.watch(visitRepositoryProvider).watchUpcomingVisits(),
);

/// Streams a single patient's visit history, most recent first. Family
/// parameter is the patientId. Used by the patient details screen (real
/// session history + stats) and by the Last Patient card (session count).
final visitsForPatientProvider = StreamProvider.family<List<Visit>, String>(
  (ref, patientId) =>
      ref.watch(visitRepositoryProvider).watchVisitsForPatient(patientId),
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

/// Joins [upcomingVisitsProvider] with the patients feature's existing
/// `patientsStreamProvider`, so screens never need to do their own
/// patient lookups. Recomputes whenever either the visits list or the
/// patients list changes.
final visitsWithPatientsProvider =
    Provider<AsyncValue<List<VisitWithPatient>>>((ref) {
  final visitsAsync = ref.watch(upcomingVisitsProvider);
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