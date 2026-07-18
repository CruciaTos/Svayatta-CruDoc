import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// A view-model that pairs a [Visit] with its resolved [Patient].
/// [patient] is nullable because a visit’s patient record might be deleted
/// later, but the visit itself should still be displayable.
class VisitWithPatient {
  final Visit visit;
  final Patient? patient;
  const VisitWithPatient({required this.visit, required this.patient});
}

/// Live list of all upcoming (non‑deleted) visits, each enriched with its
/// matching [Patient] record.  Re-emits whenever visits or patients change.
final visitsWithPatientsProvider =
    StreamProvider<List<VisitWithPatient>>((ref) {
  final visitsStream = ref.watch(visitsStreamProvider);
  final patientsStream = ref.watch(patientsStreamProvider);

  return visitsStream.asyncMap((visits) async {
    final patients = await patientsStream.first; // already loaded
    final patientMap = <String, Patient>{};
    for (final p in patients) {
      patientMap[p.id] = p;
    }
    return visits.map((v) {
      return VisitWithPatient(
        visit: v,
        patient: patientMap[v.patientId],
      );
    }).toList();
  });
});