import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/services/field_cipher.dart';
import 'package:doctor_management_app/features/appointments/data/repo/visits_repo.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/models/physio_findings.dart';
import 'package:doctor_management_app/features/scribe/data/services/consultation_note_local_service.dart';

/// Repository for the session notes the AI Scribe writes.
///
/// Session notes are the patient's session history. They are kept in the
/// clinic-wide `consultation_notes` collection (keyed by the clinic's
/// [ConsultationNote.doctorId], like `dental_records`), so every device and
/// every clinician with clinical access sees the same history.
class ConsultationNoteRepository {
  ConsultationNoteRepository({
    ConsultationNoteLocalService? localService,
    VisitRepository? visitRepository,
    FirebaseFirestore? firestore,
  }) : _localService = localService ?? ConsultationNoteLocalService(),
       _visitRepository = visitRepository ?? VisitRepository(),
       _firestoreOverride = firestore;

  static const collection = 'consultation_notes';

  final ConsultationNoteLocalService _localService;
  final VisitRepository _visitRepository;
  final FirebaseFirestore? _firestoreOverride;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  /// Fields holding PHI, encrypted with [FieldCipher] in Firestore. The list
  /// and map fields are JSON strings by the time they get here.
  static const _phiFields = [
    'transcript',
    'notes',
    'chiefComplaint',
    'advice',
    'confidenceNote',
    'symptoms',
    'diagnosisSuggestions',
    'medicines',
    'vitals',
    'physio',
  ];

  String get _currentUid {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('No signed-in doctor — cannot access scribe data.');
    }
    return uid;
  }

  /// The clinic the signed-in person works in (their own uid when solo).
  String get _tenantId {
    final tenant = ClinicSession.instance.tenantId;
    return tenant == null || tenant.isEmpty ? _currentUid : tenant;
  }

  // ---- Encryption helpers ----

  Map<String, dynamic> _encryptNoteForFirestore(Map<String, dynamic> map) {
    final out = Map<String, dynamic>.from(map);
    for (final field in _phiFields) {
      if (out[field] is String) {
        out[field] = FieldCipher.encrypt(out[field] as String?);
      }
    }
    return out;
  }

  ConsultationNote _noteFromFirestore(String id, Map<String, dynamic> raw) {
    final map = Map<String, dynamic>.from(raw);
    for (final field in _phiFields) {
      if (map[field] is String) {
        map[field] = FieldCipher.decrypt(map[field] as String);
      }
    }
    return ConsultationNote.fromMap(map, id: id);
  }

  // ---- Write operations ----

  /// Adds the session note the scribe wrote to the patient's record:
  ///
  /// 1. Saves it on this device as their newest session note
  /// 2. Appends it to [Visit.therapistNotes] (existing text is kept)
  /// 3. Uploads it to the clinic's `consultation_notes` collection, so the
  ///    clinic's other devices see it (retried later if offline)
  ///
  /// Returns the note as saved.
  Future<ConsultationNote> saveSessionNote(ConsultationNote note) async {
    final now = DateTime.now();
    final saved = note.copyWith(
      doctorId: _tenantId,
      authorUid: note.authorUid.isEmpty ? _currentUid : null,
      status: ConsultationNoteStatus.confirmed,
      confirmedAt: now,
      updatedAt: now,
    );

    if (kIsWeb) {
      await _firestore
          .collection(collection)
          .doc(saved.id)
          .set(_encryptNoteForFirestore(saved.toMap()));
      ConsultationNoteLocalService.notifyChanged();
    } else {
      await _localService.upsertNote(
        _encryptedForLocal(saved),
        syncStatus: ConsultationNoteLocalService.syncPending,
      );
    }

    await _mergeIntoVisit(saved);
    if (!kIsWeb) unawaited(_upload(saved));
    return saved;
  }

  /// Saves a doctor's later changes to a confirmed session note.
  ///
  /// Only the note itself changes: the copy appended to the visit when it
  /// was saved is left as it was, so an edit never duplicates text there.
  Future<ConsultationNote> updateSessionNote(ConsultationNote note) async {
    final now = DateTime.now();
    final edited = note.copyWith(
      doctorId: note.doctorId.isEmpty ? _tenantId : null,
      status: ConsultationNoteStatus.confirmed,
      editedAt: now,
      editedByUid: _currentUid,
      updatedAt: now,
    );

    if (kIsWeb) {
      await _firestore
          .collection(collection)
          .doc(edited.id)
          .set(_encryptNoteForFirestore(edited.toMap()));
      ConsultationNoteLocalService.notifyChanged();
      return edited;
    }

    await _localService.upsertNote(
      _encryptedForLocal(edited),
      syncStatus: ConsultationNoteLocalService.syncPending,
    );
    unawaited(_upload(edited));
    return edited;
  }

  // ---- Read operations ----

  Stream<List<ConsultationNote>> watchNotesForVisit(String visitId) =>
      _localService
          .watchNotesForVisit(visitId)
          .map((notes) => notes.map(_decryptedFromLocal).toList());

  Future<ConsultationNote?> getNote(String noteId) async {
    final note = await _localService.getNote(noteId);
    return note == null ? null : _decryptedFromLocal(note);
  }

  /// The patient's session history — confirmed notes, newest first.
  ///
  /// Emits the device's copy straight away, then again once the clinic's
  /// cloud copy has been merged in, and after every later write.
  Stream<List<ConsultationNote>> watchSessionHistory(String patientId) async* {
    if (kIsWeb) {
      yield* _firestore
          .collection(collection)
          .where('doctorId', isEqualTo: _tenantId)
          .where('patientId', isEqualTo: patientId)
          .snapshots()
          .map(
            (snap) => _newestFirst([
              for (final doc in snap.docs) _noteFromFirestore(doc.id, doc.data()),
            ]),
          );
      return;
    }

    yield await _localHistory(patientId);
    unawaited(refreshSessionHistory(patientId));
    await for (final _ in ConsultationNoteLocalService.changes) {
      yield await _localHistory(patientId);
    }
  }

  /// Pushes any session notes saved offline, then pulls the clinic's copy
  /// of [patientId]'s history onto this device. A note changed here and not
  /// yet uploaded is never overwritten by an older cloud copy.
  Future<void> refreshSessionHistory(String patientId) async {
    if (kIsWeb) return;
    try {
      await uploadPendingNotes();
      final snap = await _firestore
          .collection(collection)
          .where('doctorId', isEqualTo: _tenantId)
          .where('patientId', isEqualTo: patientId)
          .get();
      for (final doc in snap.docs) {
        final remote = _noteFromFirestore(doc.id, doc.data());
        if (remote.status != ConsultationNoteStatus.confirmed) continue;
        final local = await _localService.localStamp(remote.id);
        final remoteStamp =
            (remote.updatedAt ?? remote.createdAt).millisecondsSinceEpoch;
        final keepLocal =
            local != null &&
            (local.syncStatus == ConsultationNoteLocalService.syncPending ||
                local.updatedAt >= remoteStamp);
        if (keepLocal) continue;
        await _localService.upsertNote(
          _encryptedForLocal(remote),
          syncStatus: ConsultationNoteLocalService.syncSynced,
        );
      }
    } catch (e) {
      // Offline or not allowed to read clinical records: the device's copy
      // is still shown.
      debugPrint('[ScribeRepo] Session history refresh failed: $e');
    }
  }

  /// Uploads every confirmed note still waiting to reach the cloud.
  Future<void> uploadPendingNotes() async {
    if (kIsWeb) return;
    final pending = await _localService.getPendingUploads();
    for (final note in pending) {
      await _upload(_decryptedFromLocal(note));
    }
  }

  Future<List<ConsultationNote>> _localHistory(String patientId) async {
    final notes = await _localService.getSessionHistory(patientId);
    return notes.map(_decryptedFromLocal).toList();
  }

  static List<ConsultationNote> _newestFirst(List<ConsultationNote> notes) =>
      notes
          .where((n) => n.status == ConsultationNoteStatus.confirmed)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  // ---- Pure helpers (exposed for tests) ----

  /// The block appended to [Visit.therapistNotes] when a session note is
  /// saved: the notes as written, or a SOAP layout of an older structured
  /// note's filled fields.
  @visibleForTesting
  static String buildVisitSummary(ConsultationNote note) {
    final lines = <String>[
      'Session note (${DateFormat('d MMM yyyy, h:mm a').format(note.createdAt)})',
    ];
    final notes = note.notes.trim();
    if (notes.isNotEmpty) {
      return [...lines, '', notes].join('\n');
    }
    for (final group in soapSections(note)) {
      lines
        ..add('')
        ..add('${group.section.letter} — ${group.section.title.toUpperCase()}')
        ..addAll(group.lines);
    }
    return lines.join('\n');
  }

  /// An older structured note's filled fields grouped as a SOAP note, in
  /// SOAP order, with empty sections left out. Shared by
  /// [buildVisitSummary] and the session note view, so both always say the
  /// same thing.
  static List<({SoapSection section, List<String> lines})> soapSections(
    ConsultationNote note,
  ) {
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

    return [
      for (final section in SoapSection.values)
        if (sections[section]!.isNotEmpty)
          (section: section, lines: sections[section]!),
    ];
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
      notes: FieldCipher.encrypt(note.notes),
      chiefComplaint: FieldCipher.encrypt(note.chiefComplaint),
      advice: FieldCipher.encrypt(note.advice),
      confidenceNote: FieldCipher.encrypt(note.confidenceNote),
    );
  }

  ConsultationNote _decryptedFromLocal(ConsultationNote note) {
    return note.copyWith(
      transcript: FieldCipher.decrypt(note.transcript),
      notes: FieldCipher.decrypt(note.notes),
      chiefComplaint: FieldCipher.decrypt(note.chiefComplaint),
      advice: FieldCipher.decrypt(note.advice),
      confidenceNote: FieldCipher.decrypt(note.confidenceNote),
    );
  }

  /// Appends the session note to [Visit.therapistNotes], keeping whatever
  /// the doctor had already written for this session. A walk-in's session
  /// has no visit, so there is nothing to append to.
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
      // Best-effort — the session note is already saved; don't fail it if
      // the visit update fails (e.g. the visit was deleted meanwhile).
      debugPrint('[ScribeRepo] Visit update failed: $e');
    }
  }

  /// Writes [note] to the clinic's session history and marks the local copy
  /// synced. A failure leaves it pending for [uploadPendingNotes].
  Future<void> _upload(ConsultationNote note) async {
    try {
      await _firestore
          .collection(collection)
          .doc(note.id)
          .set(_encryptNoteForFirestore(note.toMap()));
      if (kIsWeb) return;
      // A newer edit saved while this upload was in flight stays pending.
      final local = await _localService.localStamp(note.id);
      final uploaded = (note.updatedAt ?? note.createdAt).millisecondsSinceEpoch;
      if (local != null && local.updatedAt <= uploaded) {
        await _localService.setSyncStatus(
          note.id,
          ConsultationNoteLocalService.syncSynced,
        );
      }
    } catch (e) {
      debugPrint('[ScribeRepo] Session note upload failed: $e');
    }
  }
}
