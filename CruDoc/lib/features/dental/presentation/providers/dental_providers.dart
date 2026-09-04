import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dental_procedure_catalog_model.dart';
import '../../data/models/tooth_chart_entry_model.dart';
import '../../data/models/dental_procedure_log_model.dart';
import '../../data/models/sterilization_log_model.dart';
import '../../data/models/treatment_plan_line_item_model.dart';
import '../../data/repositories/dental_repository.dart';

/// Provider for [DentalRepository].
final dentalRepositoryProvider = Provider<DentalRepository>((ref) {
  return DentalRepository();
});

/// FutureProvider for fetching dental procedure catalog items for a doctor.
final dentalCatalogProvider =
    FutureProvider.family<List<DentalProcedureCatalogModel>, String>((ref, doctorId) async {
  final repository = ref.watch(dentalRepositoryProvider);
  return repository.getProcedureCatalog(doctorId, includeArchived: true);
});

/// FutureProvider for fetching tooth chart entries for a patient.
final patientToothChartProvider =
    FutureProvider.family<List<ToothChartEntryModel>, String>((ref, patientId) async {
  final repository = ref.watch(dentalRepositoryProvider);
  return repository.getToothChartForPatient(patientId);
});

/// FutureProvider for fetching dental procedure logs for a patient.
final patientProcedureLogProvider =
    FutureProvider.family<List<DentalProcedureLogModel>, String>((ref, patientId) async {
  final repository = ref.watch(dentalRepositoryProvider);
  return repository.getProcedureLogsForPatient(patientId);
});

/// FutureProvider for fetching dental procedure logs for a visit.
final visitProcedureLogProvider =
    FutureProvider.family<List<DentalProcedureLogModel>, String>((ref, visitId) async {
  final repository = ref.watch(dentalRepositoryProvider);
  return repository.getProcedureLogsForVisit(visitId);
});

/// FutureProvider for fetching treatment plan line items for a patient.
final patientTreatmentPlanProvider =
    FutureProvider.family<List<TreatmentPlanLineItemModel>, String>((ref, patientId) async {
  final repository = ref.watch(dentalRepositoryProvider);
  return repository.getTreatmentPlanLineItems(patientId);
});

/// FutureProvider for fetching sterilization log entries for a doctor.
final sterilizationLogProvider =
    FutureProvider.family<List<SterilizationLogModel>, String>((ref, doctorId) async {
  final repository = ref.watch(dentalRepositoryProvider);
  return repository.getSterilizationLogs(doctorId);
});

