import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/services/field_cipher.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_case_sheet.dart';
import 'package:doctor_management_app/features/homeopathy/data/services/homeopathy_local_service.dart';

/// Repository coordinating SQLite and Cloud Firestore for Homeopathy Case Sheets.
class HomeopathyRepository {
  HomeopathyRepository({
    HomeopathyLocalService? localService,
    FirebaseFirestore? firestore,
  })  : _localService = localService ?? HomeopathyLocalService.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final HomeopathyLocalService _localService;
  final FirebaseFirestore _firestore;

  String get _currentDoctorId {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('No signed-in doctor — cannot access homeopathy case data.');
    }
    return uid;
  }

  /// Encrypts narrative clinical fields before persisting to Cloud Firestore.
  Map<String, dynamic> _encryptedForFirestore(HomeopathyCaseSheet sheet) {
    final map = sheet.toMap();
    // Encrypt sensitive clinical payload fields
    map['chiefProblem'] = FieldCipher.encrypt(sheet.overview.chiefProblem);
    map['consultationReason'] = FieldCipher.encrypt(sheet.overview.consultationReason);
    map['chiefComplaint'] = FieldCipher.encrypt(map['chiefComplaint'] as String?);
    map['modalities'] = FieldCipher.encrypt(map['modalities'] as String?);
    map['generalSymptoms'] = FieldCipher.encrypt(map['generalSymptoms'] as String?);
    map['physicalSymptoms'] = FieldCipher.encrypt(map['physicalSymptoms'] as String?);
    map['femaleReproductive'] = FieldCipher.encrypt(map['femaleReproductive'] as String?);
    map['mentalEmotional'] = FieldCipher.encrypt(map['mentalEmotional'] as String?);
    map['dreamsSleep'] = FieldCipher.encrypt(map['dreamsSleep'] as String?);
    map['sexualHistory'] = FieldCipher.encrypt(map['sexualHistory'] as String?);
    map['medicalHistory'] = FieldCipher.encrypt(map['medicalHistory'] as String?);
    map['physicalExamination'] = FieldCipher.encrypt(map['physicalExamination'] as String?);
    map['investigations'] = FieldCipher.encrypt(map['investigations'] as String?);
    map['peculiarSymptoms'] = FieldCipher.encrypt(map['peculiarSymptoms'] as String?);
    map['repertorizationNotes'] = FieldCipher.encrypt(map['repertorizationNotes'] as String?);
    map['suggestedRemedies'] = FieldCipher.encrypt(map['suggestedRemedies'] as String?);
    map['additionalNotes'] = FieldCipher.encrypt(map['additionalNotes'] as String?);
    return map;
  }

  Map<String, dynamic> _decryptedFromFirestore(Map<String, dynamic> raw) {
    final map = Map<String, dynamic>.from(raw);
    map['chiefProblem'] = FieldCipher.decrypt(map['chiefProblem'] as String? ?? '');
    map['consultationReason'] = FieldCipher.decrypt(map['consultationReason'] as String? ?? '');
    map['chiefComplaint'] = FieldCipher.decrypt(map['chiefComplaint'] as String? ?? '{}');
    map['modalities'] = FieldCipher.decrypt(map['modalities'] as String? ?? '{}');
    map['generalSymptoms'] = FieldCipher.decrypt(map['generalSymptoms'] as String? ?? '{}');
    map['physicalSymptoms'] = FieldCipher.decrypt(map['physicalSymptoms'] as String? ?? '{}');
    map['femaleReproductive'] = FieldCipher.decrypt(map['femaleReproductive'] as String? ?? '{}');
    map['mentalEmotional'] = FieldCipher.decrypt(map['mentalEmotional'] as String? ?? '{}');
    map['dreamsSleep'] = FieldCipher.decrypt(map['dreamsSleep'] as String? ?? '{}');
    map['sexualHistory'] = FieldCipher.decrypt(map['sexualHistory'] as String? ?? '{}');
    map['medicalHistory'] = FieldCipher.decrypt(map['medicalHistory'] as String? ?? '{}');
    map['physicalExamination'] = FieldCipher.decrypt(map['physicalExamination'] as String? ?? '{}');
    map['investigations'] = FieldCipher.decrypt(map['investigations'] as String? ?? '{}');
    map['peculiarSymptoms'] = FieldCipher.decrypt(map['peculiarSymptoms'] as String? ?? '');
    map['repertorizationNotes'] = FieldCipher.decrypt(map['repertorizationNotes'] as String? ?? '');
    map['suggestedRemedies'] = FieldCipher.decrypt(map['suggestedRemedies'] as String? ?? '');
    map['additionalNotes'] = FieldCipher.decrypt(map['additionalNotes'] as String? ?? '');
    return map;
  }

  /// Fetches the most recent case sheet for a patient.
  Future<HomeopathyCaseSheet?> getCaseSheetForPatient(String patientId) async {
    final doctorId = _currentDoctorId;

    if (kIsWeb) {
      final snap = await _firestore
          .collection('homeopathy_case_sheets')
          .where('patientId', isEqualTo: patientId)
          .where('doctorId', isEqualTo: doctorId)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) return null;
      final data = _decryptedFromFirestore(snap.docs.first.data());
      return HomeopathyCaseSheet.fromMap(data, id: snap.docs.first.id);
    }

    // Mobile: fetch from SQLite
    var sheet = await _localService.getCaseSheetForPatient(patientId);
    if (sheet == null) {
      // Try fetch once from Firestore if not yet cached locally
      try {
        final snap = await _firestore
            .collection('homeopathy_case_sheets')
            .where('patientId', isEqualTo: patientId)
            .where('doctorId', isEqualTo: doctorId)
            .limit(1)
            .get();

        if (snap.docs.isNotEmpty) {
          final data = _decryptedFromFirestore(snap.docs.first.data());
          sheet = HomeopathyCaseSheet.fromMap(data, id: snap.docs.first.id);
          await _localService.upsertCaseSheet(sheet, syncStatus: 'synced');
        }
      } catch (_) {
        // Fallback gracefully on network / security issues
      }
    }
    return sheet;
  }

  /// Stream of case sheet updates for a patient.
  Stream<HomeopathyCaseSheet?> watchCaseSheetForPatient(String patientId) async* {
    yield await getCaseSheetForPatient(patientId);

    if (!kIsWeb) {
      await for (final _ in _localService.changes) {
        yield await _localService.getCaseSheetForPatient(patientId);
      }
    }
  }

  /// Saves or updates a case sheet.
  Future<void> saveCaseSheet(HomeopathyCaseSheet caseSheet) async {
    final doctorId = _currentDoctorId;
    final now = DateTime.now();

    final sheetToSave = caseSheet.copyWith(
      id: caseSheet.id.isEmpty ? const Uuid().v4() : caseSheet.id,
      doctorId: doctorId,
      updatedAt: now,
    );

    if (!kIsWeb) {
      // 1. Save locally to SQLite for instant response
      await _localService.upsertCaseSheet(sheetToSave, syncStatus: 'pending');
    }

    // 2. Sync to Firestore with field encryption
    try {
      final encryptedData = _encryptedForFirestore(sheetToSave);
      await _firestore
          .collection('homeopathy_case_sheets')
          .doc(sheetToSave.id)
          .set(encryptedData, SetOptions(merge: true));

      if (!kIsWeb) {
        await _localService.upsertCaseSheet(
          sheetToSave,
          syncStatus: 'synced',
          lastSyncedAt: now.millisecondsSinceEpoch,
        );
      }
    } catch (e) {
      debugPrint('Error syncing homeopathy case sheet to Firestore: $e');
      if (kIsWeb) rethrow;
    }
  }
}
