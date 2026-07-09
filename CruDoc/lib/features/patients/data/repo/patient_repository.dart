import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/errors/patient_exceptions.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/services/patient_firestore_service.dart';
import 'package:doctor_management_app/features/patients/data/services/patient_local_service.dart';

/// Clean API the presentation layer talks to for anything patient-related.
///
/// Phase 2 reads from SQLite and writes locally first, then mirrors the write
/// to Firestore in the background. Firestore retry/sync ownership moves to the
/// sync engine in Phase 3; until then failed mirrors remain marked `pending`.
class PatientRepository {
  PatientRepository({
    PatientFirestoreService? firestoreService,
    PatientLocalService? localService,
  }) : _firestoreService = firestoreService ?? PatientFirestoreService(),
       _localService = localService ?? PatientLocalService();

  final PatientFirestoreService _firestoreService;
  final PatientLocalService _localService;

  /// Creates a new patient and returns the newly assigned patient id.
  Future<String> createPatient(Patient patient) async {
    _validate(patient);

    final now = DateTime.now();
    final id = patient.id.trim().isEmpty ? const Uuid().v4() : patient.id;
    final patientWithId = Patient(
      id: id,
      firstName: patient.firstName,
      lastName: patient.lastName,
      phone: patient.phone,
      gender: patient.gender,
      dateOfBirth: patient.dateOfBirth,
      diagnosis: patient.diagnosis,
      packageBalance: patient.packageBalance,
      isArchived: patient.isArchived,
      createdAt: now,
      updatedAt: now,
    );

    await _localService.upsertPatient(patientWithId);
    unawaited(_mirrorCreateToFirestore(patientWithId));
    return id;
  }

  /// Updates an existing patient's fields.
  Future<void> updatePatient(
    String patientId,
    Map<String, dynamic> data,
  ) async {
    if (data.containsKey('firstName')) {
      final firstName = data['firstName'] as String? ?? '';
      if (firstName.trim().isEmpty) {
        throw const PatientValidationException('First name cannot be empty.');
      }
    }

    final localData = Map<String, dynamic>.from(data)
      ..['updatedAt'] = DateTime.now();

    await _localService.updatePatient(patientId, localData);
    unawaited(_mirrorUpdateToFirestore(patientId, localData));
  }

  /// Soft-deletes a patient locally, then mirrors the existing Firestore delete.
  Future<void> deletePatient(String patientId) async {
    await _localService.softDeletePatient(patientId);
    unawaited(_mirrorDeleteToFirestore(patientId));
  }

  /// Fetches a single patient by id.
  Future<Patient?> getPatient(String patientId) {
    return _localService.getPatient(patientId);
  }

  /// Streams the live list of active (non-archived) patients.
  Stream<List<Patient>> watchPatients() {
    return _localService.watchPatients();
  }

  /// Searches patients by name, phone, or exact patient id.
  Future<List<Patient>> searchPatients(
    String query, {
    bool includeArchived = true,
  }) {
    return _localService.searchPatients(
      query,
      includeArchived: includeArchived,
    );
  }

  Future<void> _mirrorCreateToFirestore(Patient patient) async {
    try {
      await _firestoreService.createPatient(patient);
      await _localService.markSynced(patient.id);
    } catch (_) {
      // Leave syncStatus=pending for the Phase 3 sync engine to retry.
    }
  }

  Future<void> _mirrorUpdateToFirestore(
    String patientId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _firestoreService.updatePatient(patientId, data);
      await _localService.markSynced(patientId);
    } catch (_) {
      // Leave syncStatus=pending for the Phase 3 sync engine to retry.
    }
  }

  Future<void> _mirrorDeleteToFirestore(String patientId) async {
    try {
      await _firestoreService.deletePatient(patientId);
      await _localService.markSynced(patientId);
    } catch (_) {
      // Leave syncStatus=pending for the Phase 3 sync engine to retry.
    }
  }

  void _validate(Patient patient) {
    if (patient.firstName.trim().isEmpty) {
      throw const PatientValidationException('First name cannot be empty.');
    }
  }
}
