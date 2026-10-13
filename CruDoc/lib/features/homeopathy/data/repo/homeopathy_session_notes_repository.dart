import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:doctor_management_app/core/services/field_cipher.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_session_note.dart';
import 'package:doctor_management_app/features/homeopathy/data/services/homeopathy_session_notes_local_service.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';

/// Repository coordinating SQLite and Cloud Firestore for homeopathy
/// session (follow-up visit) notes — a patient's session history.
class HomeopathySessionNotesRepository {
  HomeopathySessionNotesRepository({
    HomeopathySessionNotesLocalService? localService,
    FirebaseFirestore? firestore,
  }) : _localService =
           localService ?? HomeopathySessionNotesLocalService.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final HomeopathySessionNotesLocalService _localService;
  final FirebaseFirestore _firestore;

  static const _collection = 'homeopathy_session_notes';

  String get _currentDoctorId {
    final uid = ClinicSession.instance.tenantId;
    if (uid == null || uid.isEmpty) {
      throw StateError(
        'No signed-in doctor — cannot access homeopathy session notes.',
      );
    }
    return uid;
  }

  // Narrative clinical fields encrypted before leaving the device, same as
  // HomeopathyRepository does for the case sheet.
  static const _encryptedFields = [
    'problemToday',
    'symptomDetails',
    'oldSymptomsReturned',
    'newSymptoms',
    'modalitiesToday',
    'mentalStateToday',
    'generalsToday',
    'complianceNotes',
    'intercurrentIllness',
    'heringsLawObservation',
    'clinicalImpression',
    'adviceGiven',
    'transcript',
  ];

  Map<String, dynamic> _encryptedForFirestore(HomeopathySessionNote note) {
    final map = note.toMap();
    for (final field in _encryptedFields) {
      map[field] = FieldCipher.encrypt(map[field] as String?);
    }
    return map;
  }

  Map<String, dynamic> _decryptedFromFirestore(Map<String, dynamic> raw) {
    final map = Map<String, dynamic>.from(raw);
    for (final field in _encryptedFields) {
      map[field] = FieldCipher.decrypt(map[field] as String? ?? '');
    }
    return map;
  }

  /// This patient's full session history, most recent visit first.
  Future<List<HomeopathySessionNote>> getSessionHistory(
    String patientId,
  ) async {
    final doctorId = _currentDoctorId;

    if (kIsWeb) {
      final snap = await _firestore
          .collection(_collection)
          .where('patientId', isEqualTo: patientId)
          .where('doctorId', isEqualTo: doctorId)
          .orderBy('sessionDate', descending: true)
          .get();
      return snap.docs
          .map(
            (d) => HomeopathySessionNote.fromMap(
              _decryptedFromFirestore(d.data()),
              id: d.id,
            ),
          )
          .toList();
    }

    // Mobile: local cache first.
    final local = await _localService.getSessionHistory(patientId);
    if (local.isNotEmpty) return local;

    // Nothing cached yet — pull once from Firestore and seed the cache.
    try {
      final snap = await _firestore
          .collection(_collection)
          .where('patientId', isEqualTo: patientId)
          .where('doctorId', isEqualTo: doctorId)
          .orderBy('sessionDate', descending: true)
          .get();
      final notes = snap.docs
          .map(
            (d) => HomeopathySessionNote.fromMap(
              _decryptedFromFirestore(d.data()),
              id: d.id,
            ),
          )
          .toList();
      for (final note in notes) {
        await _localService.upsertSessionNote(note, syncStatus: 'synced');
      }
      return notes;
    } catch (_) {
      return const [];
    }
  }

  /// Streams this patient's session history, refreshing on local writes.
  Stream<List<HomeopathySessionNote>> watchSessionHistory(
    String patientId,
  ) async* {
    yield await getSessionHistory(patientId);

    if (!kIsWeb) {
      await for (final _ in _localService.changes) {
        yield await _localService.getSessionHistory(patientId);
      }
    }
  }

  /// Saves a session note as a NEW entry in the patient's history. Unlike
  /// the case sheet, these are never merged into an existing record — each
  /// visit is its own row, kept forever.
  Future<HomeopathySessionNote> saveSessionNote(
    HomeopathySessionNote note,
  ) async {
    final now = DateTime.now();
    final toSave = note.copyWith(doctorId: _currentDoctorId, updatedAt: now);

    if (!kIsWeb) {
      await _localService.upsertSessionNote(toSave, syncStatus: 'pending');
    }

    try {
      final encrypted = _encryptedForFirestore(toSave);
      await _firestore
          .collection(_collection)
          .doc(toSave.id)
          .set(encrypted, SetOptions(merge: true));

      if (!kIsWeb) {
        await _localService.upsertSessionNote(
          toSave,
          syncStatus: 'synced',
          lastSyncedAt: now.millisecondsSinceEpoch,
        );
      }
    } catch (e) {
      debugPrint('Error syncing homeopathy session note to Firestore: $e');
      if (kIsWeb) rethrow;
    }

    return toSave;
  }

  Future<void> deleteSessionNote(String id) async {
    if (!kIsWeb) {
      await _localService.deleteSessionNote(id);
    }
    try {
      await _firestore.collection(_collection).doc(id).delete();
    } catch (e) {
      debugPrint('Error deleting homeopathy session note from Firestore: $e');
      if (kIsWeb) rethrow;
    }
  }
}
