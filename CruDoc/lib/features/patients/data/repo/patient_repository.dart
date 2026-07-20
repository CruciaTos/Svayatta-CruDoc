import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/errors/patient_exceptions.dart';
import 'package:doctor_management_app/core/services/firestore_sync_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/services/patient_local_service.dart';

/// Clean API the presentation layer talks to for anything patient-related.
///
/// Reads and writes go through SQLite. Writes are marked pending locally and
/// the central sync engine is triggered in the background.
class PatientRepository {
  PatientRepository({
    PatientLocalService? localService,
    FirestoreSyncService? syncService,
  }) : _localService = localService ?? PatientLocalService(),
       _syncService = syncService ?? FirestoreSyncService.instance;

  final PatientLocalService _localService;
  final FirestoreSyncService _syncService;

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
      notes: patient.notes,
      packageBalance: patient.packageBalance,
      isArchived: patient.isArchived,
      createdAt: now,
      updatedAt: now,
    );

    await _localService.upsertPatient(patientWithId);
    unawaited(_syncService.triggerPostWriteSync());
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
    unawaited(_syncService.triggerPostWriteSync());
  }

  /// Saves the doctor's free-form note for a patient.
  Future<void> updateDoctorsNote(String patientId, String note) {
    return updatePatient(patientId, {'notes': note.trim()});
  }

  /// Soft-deletes a patient locally, then mirrors the existing Firestore delete.
  Future<void> deletePatient(String patientId) async {
    await _localService.softDeletePatient(patientId);
    unawaited(_syncService.triggerPostWriteSync());
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

  void _validate(Patient patient) {
    if (patient.firstName.trim().isEmpty) {
      throw const PatientValidationException('First name cannot be empty.');
    }
  }
}