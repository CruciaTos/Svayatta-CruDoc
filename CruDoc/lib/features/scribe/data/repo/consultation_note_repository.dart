import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/services/field_cipher.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:doctor_management_app/features/appointments/data/repo/visits_repo.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/models/physio_findings.dart';
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
    // symptoms, diagnosisSuggestions, medicines, vitals and physio are
    // JSON strings by now.
    for (final field in const [
      'transcript',
      'chiefComplaint',
      'advice',
      'confidenceNote',
      'symptoms',
      'diagnosisSuggestions',
      'medicines',
      'vitals',
      'physio',
    ]) {
      if (out[field] is String) {
        out[field] = FieldCipher.encrypt(out[field] as String?);
      }
    }
    return out;
  }

  // ---- Write operations ----

  /// Saves an AI-produced draft note locally.
  ///
  /// Does NOT touch Patient or Visit — the doctor must call [confirmNote]
  /// after reviewing the draft to commit it to the patient record.
  Future<void> saveNote(ConsultationNote note) async {
    await _localService.upsertNote(_encryptedForLocal(note));
  }

  /// Called when the doctor taps Confirm on the draft review screen, with
  /// the doctor's edited version of the note.
  ///
  /// Performs in order:
  /// 1. Saves the note locally as [ConsultationNoteStatus.confirmed]
  /// 2. Merges diagnosis suggestions into [Patient.diagnosis] (deduped, capped at 4)
  /// 3. Appends a dated summary to [Patient.notes]
  /// 4. Appends a summary to [Visit.therapistNotes] (existing text is kept)
  /// 5. Writes the note to Firestore `users/{doctorId}/medical_records/{id}`
  /// 6. Schedules audio deletion from Firebase Storage
  Future<void> confirmNote(ConsultationNote note) async {
    final now = DateTime.now();
    final confirmed = note.copyWith(
      status: ConsultationNoteStatus.confirmed,
      confirmedAt: now,
      updatedAt: now,
    );

    // 1 — Persist the doctor's edits together with the confirmed status
    await saveNote(confirmed);

    // 2 & 3 — Merge into patient record
    await _mergeIntoPatient(confirmed);

    // 4 — Append to Visit.therapistNotes
    await _mergeIntoVisit(confirmed);

    // 5 — Write to Firestore medical_records
    unawaited(_writeToFirestore(confirmed));

    // 6 — Delete raw audio from Firebase Storage
    final audioPath = note.audioStoragePath;
    if (audioPath != null && audioPath.isNotEmpty) {
      unawaited(_deleteAudio(audioPath));
    }
  }

  /// Called when the doctor taps Discard. Marks the note discarded locally
  /// and schedules audio deletion. No patient-record changes are made.
  Future<void> discardNote(ConsultationNote note) async {
    await _localService.updateNoteFields(note.id, {
      'status': ConsultationNoteStatus.discarded.value,
    });

    final audioPath = note.audioStoragePath;
    if (audioPath != null && audioPath.isNotEmpty) {
      unawaited(_deleteAudio(audioPath));
    }
  }

  // ---- Read operations ----

  Stream<List<ConsultationNote>> watchNotesForVisit(String visitId) =>
      _localService
          .watchNotesForVisit(visitId)
          .map((notes) => notes.map(_decryptedFromLocal).toList());

  /// The newest unreviewed draft for [visitId], so an interrupted review
  /// (app closed, sheet dismissed) can be resumed instead of re-recorded.
  Future<ConsultationNote?> getDraftForVisit(String visitId) async {
    final note = await _localService.getDraftForVisit(visitId);
    return note == null ? null : _decryptedFromLocal(note);
  }

  Future<ConsultationNote?> getNote(String noteId) async {
    final note = await _localService.getNote(noteId);
    return note == null ? null : _decryptedFromLocal(note);
  }

  // ---- Pure helpers (exposed for tests) ----

  /// Merges [suggestions] into [existing] per §8 of the feature plan:
  /// case-insensitive dedupe, capped at [Patient.maxDiagnoses], with the
  /// overflow returned separately so it can go into notes rather than being
  /// silently dropped. Also used by the review UI to preview the result.
  static ({List<String> diagnoses, List<String> overflow}) mergeDiagnoses(
    List<String> existing,
    List<String> suggestions,
  ) {
    final seen = existing.map((d) => d.trim().toLowerCase()).toSet();
    final added = <String>[];
    for (final raw in suggestions) {
      final d = raw.trim();
      if (d.isEmpty || !seen.add(d.toLowerCase())) continue;
      added.add(d);
    }
    final combined = [...existing, ...added];
    return (
      diagnoses: combined.take(Patient.maxDiagnoses).toList(),
      overflow: combined.skip(Patient.maxDiagnoses).toList(),
    );
  }

  /// The block appended to [Visit.therapistNotes] on confirm, laid out as a
  /// SOAP note. Only filled fields are included.
  @visibleForTesting
  static String buildVisitSummary(ConsultationNote note) {
    final p = note.physio;
    final sections = <SoapSection, List<String>>{
      for (final s in SoapSection.values) s: [],
    };

    void add(SoapSection section, String label, String value) {
      if (value.trim().isNotEmpty) {
        sections[section]!.add('$label: ${value.trim()}');
      }
    }

    // Subjective
    add(SoapSection.subjective, 'Chief complaint', note.chiefComplaint);
    final pain = [
      if (p.textOf('painNow').isNotEmpty) 'now ${p.textOf('painNow')}',
      if (p.textOf('painWorst').isNotEmpty) 'worst ${p.textOf('painWorst')}',
      if (p.textOf('painBest').isNotEmpty) 'best ${p.textOf('painBest')}',
    ].join(', ');
    add(SoapSection.subjective, 'Pain (NPRS)', pain);
    add(SoapSection.subjective, 'Symptoms', note.symptoms.join(', '));

    // Assessment
    add(
      SoapSection.assessment,
      'Diagnosis',
      note.diagnosisSuggestions.join(', '),
    );

    for (final spec in PhysioFindings.textSpecs) {
      if (spec.compact) continue; // pain scores already combined above
      add(spec.section, spec.label, p.textOf(spec.key));
    }
    for (final spec in PhysioFindings.listSpecs) {
      final label = spec.key == 'redFlags' ? '⚠ ${spec.label}' : spec.label;
      add(spec.section, label, p.listOf(spec.key).join('; '));
    }
    add(
      SoapSection.subjective,
      'Medications',
      note.medicines.map(_formatMedicine).join('; '),
    );

    // Objective
    final vitals = [
      if ((note.vitals['bp'] ?? '').trim().isNotEmpty)
        'BP ${note.vitals['bp']!.trim()}',
      if ((note.vitals['pulse'] ?? '').trim().isNotEmpty)
        'Pulse ${note.vitals['pulse']!.trim()}',
      if ((note.vitals['temp'] ?? '').trim().isNotEmpty)
        'Temp ${note.vitals['temp']!.trim()}',
    ].join(', ');
    add(SoapSection.objective, 'Vitals', vitals);

    for (final spec in PhysioFindings.tableSpecs) {
      final rows = p.tableOf(spec.key);
      if (rows.isEmpty) continue;
      sections[spec.section]!.add(
        '${spec.label}:\n${rows.map((r) => '  • ${PhysioFindings.formatRow(spec, r)}').join('\n')}',
      );
    }

    // Plan
    add(SoapSection.plan, 'Advice', note.advice);
    if (note.followUpDate != null) {
      add(
        SoapSection.plan,
        'Follow-up',
        DateFormat('d MMM yyyy').format(note.followUpDate!),
      );
    }

    final lines = <String>[
      'AI Scribe note (${DateFormat('d MMM yyyy, h:mm a').format(note.createdAt)})',
    ];
    for (final section in SoapSection.values) {
      final items = sections[section]!;
      if (items.isEmpty) continue;
      lines
        ..add('')
        ..add('${section.letter} — ${section.title.toUpperCase()}')
        ..addAll(items);
    }
    return lines.join('\n');
  }

  static String _formatMedicine(NotedMedicine m) {
    final details = [
      m.dosage,
      m.instructions,
    ].map((s) => s.trim()).where((s) => s.isNotEmpty).join(', ');
    return details.isEmpty ? m.name.trim() : '${m.name.trim()} ($details)';
  }

  // ---- Private helpers ----

  /// Returns a copy of [note] with free-text PHI encrypted for local storage.
  /// (The list fields are JSON-encoded by [ConsultationNote.toLocalMap] and
  /// live in the SQLCipher-encrypted database.)
  ConsultationNote _encryptedForLocal(ConsultationNote note) {
    return note.copyWith(
      transcript: FieldCipher.encrypt(note.transcript),
      chiefComplaint: FieldCipher.encrypt(note.chiefComplaint),
      advice: FieldCipher.encrypt(note.advice),
      confidenceNote: FieldCipher.encrypt(note.confidenceNote),
    );
  }

  ConsultationNote _decryptedFromLocal(ConsultationNote note) {
    return note.copyWith(
      transcript: FieldCipher.decrypt(note.transcript),
      chiefComplaint: FieldCipher.decrypt(note.chiefComplaint),
      advice: FieldCipher.decrypt(note.advice),
      confidenceNote: FieldCipher.decrypt(note.confidenceNote),
    );
  }

  /// Merges the confirmed note into the patient record (§8):
  /// diagnoses via [mergeDiagnoses], plus a dated summary appended to
  /// [Patient.notes] that also carries any diagnosis overflow.
  Future<void> _mergeIntoPatient(ConsultationNote note) async {
    final patient = await _patientRepository.getPatient(note.patientId);
    if (patient == null) return;

    final merged = mergeDiagnoses(patient.diagnosis, note.diagnosisSuggestions);

    final redFlags = note.physio.listOf('redFlags');
    final lines = <String>[
      if (note.chiefComplaint.trim().isNotEmpty)
        'Chief complaint: ${note.chiefComplaint.trim()}',
      // Carried onto the patient record so they're seen on every future visit.
      if (redFlags.isNotEmpty) '⚠ Red flags: ${redFlags.join('; ')}',
      if (note.advice.trim().isNotEmpty) 'Advice: ${note.advice.trim()}',
      if (merged.overflow.isNotEmpty)
        'Additional diagnoses: ${merged.overflow.join(', ')}',
    ];

    final updates = <String, dynamic>{
      'diagnosis': Patient.diagnosisToStored(merged.diagnoses),
    };
    if (lines.isNotEmpty) {
      final block = [
        '[Scribe ${DateFormat('d/M/yyyy').format(note.createdAt)}]',
        ...lines,
      ].join('\n');
      updates['notes'] = patient.notes.trim().isEmpty
          ? block
          : '${patient.notes.trim()}\n\n$block';
    }

    await _patientRepository.updatePatient(note.patientId, updates);
  }

  /// Appends the confirmed note's summary to [Visit.therapistNotes] (§8),
  /// keeping whatever the doctor had already written for this session.
  Future<void> _mergeIntoVisit(ConsultationNote note) async {
    try {
      final visit = await _visitRepository.getVisit(note.visitId);
      if (visit == null) return;

      final summary = buildVisitSummary(note);
      final existing = visit.therapistNotes?.trim() ?? '';
      final hasTreatmentType = visit.treatmentType?.trim().isNotEmpty ?? false;

      await _visitRepository.updateVisit(note.visitId, {
        'therapistNotes': existing.isEmpty ? summary : '$existing\n\n$summary',
        if (!hasTreatmentType && note.diagnosisSuggestions.isNotEmpty)
          'treatmentType': note.diagnosisSuggestions.first,
      });
    } catch (e) {
      // Best-effort — don't fail the entire confirm flow if the visit update
      // fails (e.g. visit was deleted between recording and confirm).
      debugPrint('[ScribeRepo] Visit update failed: $e');
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
}
