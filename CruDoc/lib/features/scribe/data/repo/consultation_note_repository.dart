import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/core/services/field_cipher.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:doctor_management_app/features/appointments/data/repo/visits_repo.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/services/consultation_note_local_service.dart';

/// Repository for consultation notes produced by the AI Scribe.
///
/// The critical constraint from the feature plan (§1):
/// **Nothing writes to Patient or Visit until [confirmNote] is called.**
/// [saveNote] only stores a draft locally — it does not touch patient data.
class ConsultationNoteRepository {
  ConsultationNoteRepository({
    ConsultationNoteLocalService? localService,
    PatientRepository? patientRepository,
    VisitRepository? visitRepository,
  }) : _localService = localService ?? ConsultationNoteLocalService(),
       _patientRepository = patientRepository ?? PatientRepository(),
       _visitRepository = visitRepository ?? VisitRepository();

  final ConsultationNoteLocalService _localService;
  final PatientRepository _patientRepository;
  final VisitRepository _visitRepository;

  String get _currentDoctorId {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('No signed-in doctor — cannot access scribe data.');
    }
    return uid;
  }

  // ---- Encryption helpers ----

  Map<String, dynamic> _encryptNoteForFirestore(Map<String, dynamic> map) {
    final out = Map<String, dynamic>.from(map);
    for (final field in const [
      'transcript',
      'chiefComplaint',
      'advice',
      'confidenceNote',
    ]) {
      if (out[field] is String) {
        out[field] = FieldCipher.encrypt(out[field] as String?);
      }
    }
    // symptoms and diagnosisSuggestions are stored as JSON strings
    if (out['symptoms'] is String) {
      out['symptoms'] = FieldCipher.encrypt(out['symptoms'] as String?);
    }
    if (out['diagnosisSuggestions'] is String) {
      out['diagnosisSuggestions'] =
          FieldCipher.encrypt(out['diagnosisSuggestions'] as String?);
    }
    if (out['medicines'] is String) {
      out['medicines'] = FieldCipher.encrypt(out['medicines'] as String?);
    }
    return out;
  }

  // ---- Write operations ----

  /// Saves an AI-produced draft note locally.
  ///
  /// Does NOT touch Patient or Visit — the doctor must call [confirmNote]
  /// after reviewing the draft to commit it to the patient record.
  Future<void> saveNote(ConsultationNote note) async {
    final encrypted = _encryptedForLocal(note);
    await _localService.upsertNote(encrypted);
  }

  /// Called when the doctor taps Confirm on the draft review screen.
  ///
  /// Performs in order:
  /// 1. Updates local note status to [ConsultationNoteStatus.confirmed]
  /// 2. Merges diagnosis suggestions into [Patient.diagnosis] (deduped, capped at 4)
  /// 3. Appends chief complaint + advice summary to [Patient.notes]
  /// 4. Sets [Visit.therapistNotes] from the confirmed advice
  /// 5. Writes the note to Firestore `users/{doctorId}/medical_records/{id}`
  /// 6. Schedules audio deletion from Firebase Storage
  Future<void> confirmNote(ConsultationNote note) async {
    final now = DateTime.now();
    final confirmed = note.copyWith(
      status: ConsultationNoteStatus.confirmed,
      confirmedAt: now,
      updatedAt: now,
    );

    // 1 — Update local note
    await _localService.updateNoteFields(note.id, {
      'status': ConsultationNoteStatus.confirmed.value,
      'confirmedAt': now.millisecondsSinceEpoch,
    });

    // 2 & 3 — Merge into patient record
    await _mergeIntoPatient(note);

    // 4 — Populate Visit.therapistNotes
    await _mergeIntoVisit(note);

    // 5 — Write to Firestore medical_records
    unawaited(_writeToFirestore(confirmed));

    // 6 — Delete raw audio from Firebase Storage
    if (note.audioStoragePath != null) {
      unawaited(_deleteAudio(note.audioStoragePath!));
    }
  }

  /// Called when the doctor taps Discard. Marks the note discarded locally
  /// and schedules audio deletion. No patient-record changes are made.
  Future<void> discardNote(ConsultationNote note) async {
    final now = DateTime.now();
    await _localService.updateNoteFields(note.id, {
      'status': ConsultationNoteStatus.discarded.value,
      'updatedAt': now.millisecondsSinceEpoch,
    });

    if (note.audioStoragePath != null) {
      unawaited(_deleteAudio(note.audioStoragePath!));
    }
  }

  // ---- Read operations ----

  Stream<List<ConsultationNote>> watchNotesForVisit(String visitId) =>
      _localService.watchNotesForVisit(visitId);

  Future<ConsultationNote?> getDraftForVisit(String visitId) =>
      _localService.getDraftForVisit(visitId);

  Future<ConsultationNote?> getNote(String noteId) =>
      _localService.getNote(noteId);

  // ---- Private helpers ----

  /// Returns a copy of [note] with PHI fields encrypted for local storage.
  ConsultationNote _encryptedForLocal(ConsultationNote note) {
    return ConsultationNote(
      id: note.id,
      doctorId: note.doctorId,
      patientId: note.patientId,
      visitId: note.visitId,
      transcript: FieldCipher.encrypt(note.transcript),
      chiefComplaint: FieldCipher.encrypt(note.chiefComplaint),
      symptoms: note.symptoms, // stored as JSON; encrypted at map level
      diagnosisSuggestions: note.diagnosisSuggestions,
      medicines: note.medicines,
      advice: FieldCipher.encrypt(note.advice),
      followUpDate: note.followUpDate,
      vitals: note.vitals,
      confidenceNote: note.confidenceNote,
      consentGiven: note.consentGiven,
      consentAt: note.consentAt,
      audioStoragePath: note.audioStoragePath,
      status: note.status,
      createdAt: note.createdAt,
      confirmedAt: note.confirmedAt,
      updatedAt: note.updatedAt,
    );
  }

  /// Merges the confirmed note's diagnosis suggestions into the patient record,
  /// following §8 of the feature plan:
  /// - Deduplicates against existing diagnoses (case-insensitive)
  /// - Caps at [Patient.maxDiagnoses] (4)
  /// - Puts overflow into [Patient.notes] instead of silently dropping
  /// - Appends chief complaint + advice summary to [Patient.notes]
  Future<void> _mergeIntoPatient(ConsultationNote note) async {
    final patient = await _patientRepository.getPatient(note.patientId);
    if (patient == null) return;

    final existingLower = patient.diagnosis.map((d) => d.toLowerCase()).toSet();
    final newDiagnoses = note.diagnosisSuggestions
        .where((d) => d.trim().isNotEmpty)
        .where((d) => !existingLower.contains(d.toLowerCase()))
        .toList();

    final combined = [...patient.diagnosis, ...newDiagnoses];
    final capped = combined.take(Patient.maxDiagnoses).toList();
    final overflow = combined.skip(Patient.maxDiagnoses).toList();

    // Build the note suffix
    final buffer = StringBuffer();
    if (note.chiefComplaint.trim().isNotEmpty) {
      buffer.writeln('[Scribe ${_formatDate(note.createdAt)}]');
      buffer.writeln('Chief complaint: ${note.chiefComplaint}');
      if (note.advice.trim().isNotEmpty) {
        buffer.writeln('Advice: ${note.advice}');
      }
      if (overflow.isNotEmpty) {
        buffer.writeln('Additional diagnoses: ${overflow.join(', ')}');
      }
    }

    final updatedNotes = patient.notes.trim().isEmpty
        ? buffer.toString().trim()
        : '${patient.notes.trim()}\n\n${buffer.toString().trim()}';

    final updates = <String, dynamic>{
      'diagnosis': Patient.diagnosisToStored(capped),
      if (buffer.isNotEmpty) 'notes': updatedNotes.trim(),
    };

    if (updates.isNotEmpty) {
      await _patientRepository.updatePatient(note.patientId, updates);
    }
  }

  /// Populates [Visit.therapistNotes] from the confirmed note's advice,
  /// as specified in §8 of the feature plan.
  Future<void> _mergeIntoVisit(ConsultationNote note) async {
    if (note.advice.trim().isEmpty && note.chiefComplaint.trim().isEmpty) {
      return;
    }

    final summaryParts = <String>[];
    if (note.chiefComplaint.trim().isNotEmpty) {
      summaryParts.add('Chief complaint: ${note.chiefComplaint}');
    }
    if (note.advice.trim().isNotEmpty) {
      summaryParts.add('Advice: ${note.advice}');
    }
    final summary = summaryParts.join('\n');

    try {
      await _visitRepository.updateVisit(note.visitId, {
        'therapistNotes': summary,
        if (note.diagnosisSuggestions.isNotEmpty)
          'treatmentType': note.diagnosisSuggestions.first,
      });
    } catch (_) {
      // Best-effort — don't fail the entire confirm flow if visit update
      // fails (e.g. visit was deleted between recording and confirm).
    }
  }

  Future<void> _writeToFirestore(ConsultationNote note) async {
    try {
      final map = _encryptNoteForFirestore(note.toMap());
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentDoctorId)
          .collection('medical_records')
          .doc(note.id)
          .set(map);
    } catch (e) {
      // Non-fatal: the note is already saved locally and patient/visit
      // are already updated. Firestore write is best-effort for now.
      debugPrint('[ScribeRepo] Firestore write failed: $e');
    }
  }

  Future<void> _deleteAudio(String storagePath) async {
    try {
      await FirebaseStorage.instance.ref(storagePath).delete();
    } catch (e) {
      debugPrint('[ScribeRepo] Audio deletion failed: $e');
    }
  }

  static String _formatDate(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}';
}
