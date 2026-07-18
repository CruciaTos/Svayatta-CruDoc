import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/repo/visits_repo.dart';

/// Shared Riverpod providers for visit data — mirrors the shape of
/// patients/data/providers/patient_providers.dart.
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