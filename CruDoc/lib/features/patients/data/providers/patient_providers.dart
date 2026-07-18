import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' as riverpod_legacy;

import 'package:doctor_management_app/core/utils/search_normalisation.dart';
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
  final canMatchPhone = normalizedPhoneQuery.length >= 3;

  return patientsAsync.whenData((patients) {
    return patients.where((patient) {
      final nameMatch = normalizeForSearch(
        patient.fullName,
      ).contains(normalizedQuery);
      final phoneMatch =
          canMatchPhone &&
          normalizePhoneDigits(patient.phone).contains(normalizedPhoneQuery);

      return nameMatch || phoneMatch;
    }).toList();
  });
});