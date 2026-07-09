import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/services/patient_firestore_service.dart';

/// Clean API the presentation layer talks to for anything patient-related.
///
/// Wraps [PatientFirestoreService] so the UI never has to know about
/// Firestore-specific types or query details. If the data source ever
/// changes (e.g. caching, offline support), only this class needs to
/// change — not the widgets that use it.
class PatientRepository {
  PatientRepository({PatientFirestoreService? firestoreService})
      : _firestoreService = firestoreService ?? PatientFirestoreService();

  final PatientFirestoreService _firestoreService;

  /// Creates a new patient and returns the newly assigned patient id.
  Future<String> createPatient(Patient patient) {
    return _firestoreService.createPatient(patient);
  }

  /// Updates an existing patient's fields.
  Future<void> updatePatient(String patientId, Map<String, dynamic> data) {
    return _firestoreService.updatePatient(patientId, data);
  }

  /// Permanently deletes a patient.
  Future<void> deletePatient(String patientId) {
    return _firestoreService.deletePatient(patientId);
  }

  /// Fetches a single patient by id.
  Future<Patient?> getPatient(String patientId) {
    return _firestoreService.getPatient(patientId);
  }

  /// Streams the live list of active (non-archived) patients.
  Stream<List<Patient>> watchPatients() {
    return _firestoreService.watchPatients();
  }

  /// Searches patients by name, phone, or exact patient id. See
  /// [PatientFirestoreService.searchPatients] for matching rules — use
  /// this before creating a new patient from the appointment screen so
  /// the doctor can pick an existing match instead of creating a
  /// duplicate.
  Future<List<Patient>> searchPatients(
    String query, {
    bool includeArchived = true,
  }) {
    return _firestoreService.searchPatients(
      query,
      includeArchived: includeArchived,
    );
  }
}