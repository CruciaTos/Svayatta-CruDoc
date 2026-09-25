import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/dental/data/models/dental_procedure_catalog_model.dart';
import 'package:doctor_management_app/features/dental/data/models/sterilization_log_model.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';

/// Whose dental records these are: the signed-in doctor (the demo
/// account when nobody is signed in, as the older dental screens do).
final dentalDoctorIdProvider = Provider<String>((ref) {
  final user = ref.watch(authStateProvider).value;
  return user?.uid ?? FirebaseAuth.instance.currentUser?.uid ?? 'doc_dental';
});

/// The clinic's procedure list and fees, archived ones included.
final dentalProcedureListProvider =
    FutureProvider<List<DentalProcedureCatalogModel>>((ref) {
  final doctorId = ref.watch(dentalDoctorIdProvider);
  return ref
      .watch(dentalRepositoryProvider)
      .getProcedureCatalog(doctorId, includeArchived: true);
});

/// Every patient's treatment plan items.
final clinicTreatmentPlansProvider =
    FutureProvider<List<TreatmentPlanLineItemModel>>((ref) {
  final doctorId = ref.watch(dentalDoctorIdProvider);
  return ref.watch(dentalRepositoryProvider).getAllTreatmentPlanLineItems(
        doctorId,
      );
});

/// Autoclave cycles, newest first.
final clinicSterilizationProvider =
    FutureProvider<List<SterilizationLogModel>>((ref) {
  final doctorId = ref.watch(dentalDoctorIdProvider);
  return ref.watch(dentalRepositoryProvider).getSterilizationLogs(doctorId);
});

/// Re-reads one patient's chart, procedures and plan (and the clinic-wide
/// plan list) after a change.
void refreshDentalPatient(WidgetRef ref, String patientId) {
  ref.invalidate(patientToothChartProvider(patientId));
  ref.invalidate(patientProcedureLogProvider(patientId));
  ref.invalidate(patientTreatmentPlanProvider(patientId));
  ref.invalidate(clinicTreatmentPlansProvider);
}
