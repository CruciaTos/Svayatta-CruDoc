import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/repo/visits_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';

final visitRepositoryProvider = Provider<VisitRepository>(
  (ref) => VisitRepository(),
);

/// Streams patientId -> their most recent visit that has already
/// occurred, refreshed automatically after every visit write.
final lastVisitPerPatientProvider = StreamProvider<Map<String, Visit>>(
  (ref) {
    ref.watch(authStateProvider);
    return ref.watch(visitRepositoryProvider).watchLastVisitPerPatient();
  },
);

/// Streams upcoming scheduled visits, soonest first.
final upcomingVisitsProvider = StreamProvider<List<Visit>>(
  (ref) {
    ref.watch(authStateProvider);
    return ref.watch(visitRepositoryProvider).watchUpcomingVisits();
  },
);

/// Streams today's scheduled visits (clinic + home combined), soonest
/// first.
final todaysVisitsProvider = StreamProvider<List<Visit>>(
  (ref) {
    ref.watch(authStateProvider);
    return ref.watch(visitRepositoryProvider).watchTodaysVisits();
  },
);

/// Streams the most recently created/updated visits (any status),
/// newest first. Feeds the dashboard's "Recent Activity" card.
final recentVisitsProvider = StreamProvider<List<Visit>>(
  (ref) {
    ref.watch(authStateProvider);
    return ref.watch(visitRepositoryProvider).watchRecentVisits();
  },
);

/// Streams ALL non-deleted visits (past, present, future) for calendar view.
final allVisitsProvider = StreamProvider<List<Visit>>(
  (ref) {
    ref.watch(authStateProvider);
    return ref.watch(visitRepositoryProvider).watchAllVisits();
  },
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

/// Joins [todaysVisitsProvider] with patient data — the dashboard's
/// "Today's Visits" card equivalent of [visitsWithPatientsProvider].
final todaysVisitsWithPatientsProvider =
    Provider<AsyncValue<List<VisitWithPatient>>>((ref) {
  final visitsAsync = ref.watch(todaysVisitsProvider);
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

/// Joins [allVisitsProvider] with patient data for calendar views
/// showing past, present, and future appointments.
final allVisitsWithPatientsProvider =
    Provider<AsyncValue<List<VisitWithPatient>>>((ref) {
  final visitsAsync = ref.watch(allVisitsProvider);
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