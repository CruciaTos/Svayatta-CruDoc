import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/services/encryption_key_manager.dart';
import 'package:doctor_management_app/core/errors/patient_exceptions.dart';
import 'package:doctor_management_app/core/services/field_cipher.dart';
import 'package:doctor_management_app/core/services/firestore_sync_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/services/patient_local_service.dart';

/// Clean API the presentation layer talks to for anything patient-related.
///
/// Reads and writes go through SQLite on mobile, and directly through Cloud Firestore
/// on Web to ensure Web & Mobile stay 100% connected with identical live data.
class PatientRepository {
  PatientRepository({
    PatientLocalService? localService,
    FirestoreSyncService? syncService,
  }) : _localService = localService ?? PatientLocalService(),
       _syncService = syncService ?? FirestoreSyncService.instance;

  final PatientLocalService _localService;
  final FirestoreSyncService _syncService;

  /// The signed-in doctor's UID. Every patient read/write is scoped to
  /// this — without it, the Web branch below (which talks to Firestore
  /// directly) would read and write every doctor's shared `patients`
  /// collection instead of just this doctor's own data.
  String get _currentDoctorId {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('No signed-in doctor — cannot access patient data.');
    }
    return uid;
  }

  /// Encrypts the free-text PHI fields of a patient map before it leaves
  /// the device for Firestore. Structural fields (ids, dates, flags,
  /// `doctorId`) are left as-is so Firestore can still query/sort on them.
  Map<String, dynamic> _encryptedForFirestore(Map<String, dynamic> map) {
    final out = Map<String, dynamic>.from(map);
    if (out.containsKey('firstName')) {
      out['firstName'] = FieldCipher.encrypt(out['firstName'] as String?);
    }
    if (out.containsKey('lastName')) {
      out['lastName'] = FieldCipher.encrypt(out['lastName'] as String?);
    }
    if (out.containsKey('phone')) {
      out['phone'] = FieldCipher.encrypt(out['phone'] as String?);
    }
    if (out.containsKey('diagnosis')) {
      if (out['diagnosis'] is List) {
        out['diagnosis'] = (out['diagnosis'] as List)
            .map((d) => FieldCipher.encrypt(d.toString()))
            .toList();
      } else if (out['diagnosis'] is String) {
        out['diagnosis'] = FieldCipher.encrypt(out['diagnosis'] as String?);
      }
    }
    if (out.containsKey('notes')) {
      out['notes'] = FieldCipher.encrypt(out['notes'] as String?);
    }
    return out;
  }

  Map<String, dynamic> _decryptedFromFirestore(Map<String, dynamic> map) {
    final out = Map<String, dynamic>.from(map);
    if (out['firstName'] is String) {
      out['firstName'] = FieldCipher.decrypt(out['firstName'] as String);
    }
    if (out['lastName'] is String) {
      out['lastName'] = FieldCipher.decrypt(out['lastName'] as String);
    }
    if (out['phone'] is String) {
      out['phone'] = FieldCipher.decrypt(out['phone'] as String);
    }
    if (out['diagnosis'] is String) {
      out['diagnosis'] = FieldCipher.decrypt(out['diagnosis'] as String);
    } else if (out['diagnosis'] is List) {
      out['diagnosis'] = (out['diagnosis'] as List)
          .map((d) => FieldCipher.decrypt(d.toString()))
          .toList();
    }
    if (out['notes'] is String) {
      out['notes'] = FieldCipher.decrypt(out['notes'] as String);
    }
    return out;
  }

  /// Creates a new patient and returns the newly assigned patient id.
  Future<String> createPatient(Patient patient) async {
    _validate(patient);

    final now = DateTime.now();
    final id = patient.id.trim().isEmpty ? const Uuid().v4() : patient.id;
    final patientWithId = Patient(
      id: id,
      doctorId: _currentDoctorId,
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

    if (kIsWeb) {
      if (!FieldCipher.isReady) {
        await EncryptionKeyManager.instance.loadForDoctor(_currentDoctorId);
      }
      await FirebaseFirestore.instance
          .collection('patients')
          .doc(id)
          .set(_encryptedForFirestore(patientWithId.toMap()));
      return id;
    }

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
      ..['updatedAt'] = DateTime.now()
      // doctorId is set once at creation and must never change on update.
      ..remove('doctorId');

    if (kIsWeb) {
      if (!FieldCipher.isReady) {
        await EncryptionKeyManager.instance.loadForDoctor(_currentDoctorId);
      }
      await FirebaseFirestore.instance
          .collection('patients')
          .doc(patientId)
          .update(_encryptedForFirestore(localData));
      return;
    }

    await _localService.updatePatient(patientId, localData);
    unawaited(_syncService.triggerPostWriteSync());
  }

  /// Saves the doctor's free-form note for a patient.
  Future<void> updateDoctorsNote(String patientId, String note) {
    return updatePatient(patientId, {'notes': note.trim()});
  }

  /// Soft-deletes a patient locally, then mirrors the existing Firestore delete.
  Future<void> deletePatient(String patientId) async {
    if (kIsWeb) {
      await FirebaseFirestore.instance
          .collection('patients')
          .doc(patientId)
          .update({
        'isArchived': true,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      return;
    }
    await _localService.softDeletePatient(patientId);
    unawaited(_syncService.triggerPostWriteSync());
  }

  /// Fetches a single patient by id.
  Future<Patient?> getPatient(String patientId) async {
    if (kIsWeb) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.uid.isEmpty) return null;
      if (!FieldCipher.isReady) {
        await EncryptionKeyManager.instance.loadForDoctor(user.uid);
      }
      final doc = await FirebaseFirestore.instance
          .collection('patients')
          .doc(patientId)
          .get();
      if (!doc.exists || doc.data() == null) return null;
      return Patient.fromMap(_decryptedFromFirestore(doc.data()!), id: doc.id);
    }
    return _localService.getPatient(patientId);
  }

  /// Streams the live list of active (non-archived) patients.
  ///
  /// On web, we load the encryption key **before** returning the stream.
  /// If the key cannot be loaded (e.g., not yet available), an error is
  /// thrown, which the StreamProvider will surface as an error state instead
  /// of hanging in loading.
  Stream<List<Patient>> watchPatients() async* {
    if (kIsWeb) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.uid.isEmpty) {
        yield const [];
        return;
      }

      // Ensure encryption key is loaded once before listening to Firestore.
      // If it fails, the error propagates to the stream listener.
      if (!FieldCipher.isReady) {
        await EncryptionKeyManager.instance.loadForDoctor(user.uid);
      }

      // Now yield from the Firestore snapshot stream.
      yield* FirebaseFirestore.instance
          .collection('patients')
          .where('doctorId', isEqualTo: user.uid)
          .snapshots()
          .map((snapshot) {
            final list = snapshot.docs
                .map((doc) => Patient.fromMap(
                      _decryptedFromFirestore(doc.data()),
                      id: doc.id,
                    ))
                .where((p) => !p.isArchived)
                .toList();
            list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return list;
          });
    } else {
      // Mobile: stream from local database.
      yield* _localService.watchPatients();
    }
  }

  /// Searches patients by name, phone, or exact patient id.
  Future<List<Patient>> searchPatients(
    String query, {
    bool includeArchived = true,
  }) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return const [];

    if (kIsWeb) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.uid.isEmpty) return const [];
      if (!FieldCipher.isReady) {
        await EncryptionKeyManager.instance.loadForDoctor(user.uid);
      }
      final snap = await FirebaseFirestore.instance
          .collection('patients')
          .where('doctorId', isEqualTo: user.uid)
          .get();

      final list = snap.docs
          .map((doc) => Patient.fromMap(
                _decryptedFromFirestore(doc.data()),
                id: doc.id,
              ))
          .where((p) => includeArchived || !p.isArchived)
          .where((p) {
            final nameMatch = p.fullName.toLowerCase().contains(cleanQuery);
            final phoneMatch = p.phone.toLowerCase().contains(cleanQuery);
            final diagMatch = p.diagnosisDisplay.toLowerCase().contains(cleanQuery);
            final idMatch = p.id.toLowerCase() == cleanQuery;
            return nameMatch || phoneMatch || diagMatch || idMatch;
          })
          .toList();

      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    }

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