import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' as riverpod_legacy;

import 'package:doctor_management_app/core/utils/search_normalisation.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';

final patientRepositoryProvider = Provider<PatientRepository>(
  (ref) => PatientRepository(),
);

final patientsStreamProvider = StreamProvider<List<Patient>>(
  (ref) => ref.watch(patientRepositoryProvider).watchPatients(),
);

final searchQueryProvider = riverpod_legacy.StateProvider<String>((ref) => '');

final filteredPatientsProvider = Provider<AsyncValue<List<Patient>>>((ref) {
  final patientsAsync = ref.watch(patientsStreamProvider);
  final query = ref.watch(searchQueryProvider).trim();

  if (query.isEmpty) return patientsAsync;

  final normalizedQuery = normalizeForSearch(query);
  final normalizedPhoneQuery = normalizePhoneDigits(query);
  final canMatchPhone = normalizedPhoneQuery.length >= 1;

  return patientsAsync.whenData((patients) {
    return patients.where((patient) {
      final nameMatch = normalizeForSearch(
        patient.fullName,
      ).contains(normalizedQuery);
      final phoneMatch =
          canMatchPhone &&
          normalizePhoneDigits(patient.phone).contains(normalizedPhoneQuery);
      final diagnosisMatch = normalizeForSearch(
        patient.diagnosisDisplay,
      ).contains(normalizedQuery);

      return nameMatch || phoneMatch || diagnosisMatch;
    }).toList();
  });
});

/// A patient paired with one of their visits — used by the "Last Patient"
/// and "Upcoming Patient" summary cards.
typedef PatientVisit = ({Patient patient, Visit visit});

Patient? _findPatientById(List<Patient> patients, String patientId) {
  for (final patient in patients) {
    if (patient.id == patientId) return patient;
  }
  return null;
}

/// The patient from the single most recent visit that has already
/// occurred, or null if there's no visit history yet. Feeds
/// [LastPatientsCard].
final lastPatientProvider = Provider<AsyncValue<PatientVisit?>>((ref) {
  final patientsAsync = ref.watch(patientsStreamProvider);
  final lastVisitsAsync = ref.watch(lastVisitPerPatientProvider);

  return patientsAsync.when(
    loading: () => const AsyncValue.loading(),
    error: (error, stack) => AsyncValue.error(error, stack),
    data: (patients) => lastVisitsAsync.when(
      loading: () => const AsyncValue.loading(),
      error: (error, stack) => AsyncValue.error(error, stack),
      data: (lastVisits) {
        Visit? mostRecent;
        for (final visit in lastVisits.values) {
          if (mostRecent == null ||
              visit.scheduledStart.isAfter(mostRecent.scheduledStart)) {
            mostRecent = visit;
          }
        }
        if (mostRecent == null) return const AsyncValue.data(null);

        final patient = _findPatientById(patients, mostRecent.patientId);
        if (patient == null) return const AsyncValue.data(null);

        return AsyncValue.data((patient: patient, visit: mostRecent));
      },
    ),
  );
});

/// The patient from the earliest upcoming scheduled visit, or null if
/// nothing is scheduled. Feeds [UpcomingPatientCard].
final upcomingPatientProvider = Provider<AsyncValue<PatientVisit?>>((ref) {
  final patientsAsync = ref.watch(patientsStreamProvider);
  final upcomingAsync = ref.watch(upcomingVisitsProvider);

  return patientsAsync.when(
    loading: () => const AsyncValue.loading(),
    error: (error, stack) => AsyncValue.error(error, stack),
    data: (patients) => upcomingAsync.when(
      loading: () => const AsyncValue.loading(),
      error: (error, stack) => AsyncValue.error(error, stack),
      data: (upcoming) {
        if (upcoming.isEmpty) return const AsyncValue.data(null);

        final nextVisit = upcoming.first; // already ordered soonest-first
        final patient = _findPatientById(patients, nextVisit.patientId);
        if (patient == null) return const AsyncValue.data(null);

        return AsyncValue.data((patient: patient, visit: nextVisit));
      },
    ),
  );
});