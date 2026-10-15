import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/core/services/gemini_json_client.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/models/physio_findings.dart';
import 'package:doctor_management_app/features/scribe/data/repo/consultation_note_repository.dart';
import 'package:doctor_management_app/features/scribe/services/scribe_processing_service.dart';

/// Returns [reply] for every call and remembers the last prompt.
class _FakeGemini extends GeminiJsonClient {
  _FakeGemini(this.reply) : super(apiKey: 'test', model: 'test-model');

  final Map<String, dynamic> reply;
  int calls = 0;
  String? lastPrompt;
  Uint8List? lastAudio;

  @override
  Future<Map<String, dynamic>> generateJson({
    required String systemPrompt,
    required String prompt,
    Uint8List? audioBytes,
    required Schema schema,
    String mimeType = 'audio/mp4',
    int maxOutputTokens = 8192,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    calls++;
    lastPrompt = prompt;
    lastAudio = audioBytes;
    return reply;
  }
}

const _conversation =
    'Doctor: What brings you in today? Patient: My right knee has hurt for '
    'three weeks since I twisted it playing football. Doctor: Take '
    'paracetamol 650 twice a day for five days and come back after a week.';

ConsultationNote _session({String specialty = SessionSpecialty.none}) {
  return ConsultationNote(
    id: 'n1',
    doctorId: 'd1',
    patientId: 'p1',
    visitId: 'v1',
    specialty: specialty,
    authorUid: 'd1',
    consentAt: DateTime(2026, 9, 22, 10),
    createdAt: DateTime(2026, 9, 22, 10),
  );
}

ConsultationNote _note({
  String chiefComplaint = '',
  String notes = '',
  List<String> diagnoses = const [],
  List<NotedMedicine> medicines = const [],
  String advice = '',
  PhysioFindings physio = PhysioFindings.empty,
}) {
  return ConsultationNote(
    id: 'n1',
    doctorId: 'd1',
    patientId: 'p1',
    visitId: 'v1',
    chiefComplaint: chiefComplaint,
    notes: notes,
    diagnosisSuggestions: diagnoses,
    medicines: medicines,
    advice: advice,
    physio: physio,
    createdAt: DateTime(2026, 9, 22, 10, 30),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScribeProcessingService.writeSessionNote', () {
    test('writes the notes and title from the transcript text alone', () async {
      final gemini = _FakeGemini({
        'notes':
            'Presenting complaint\nRight knee pain for 3 weeks.\n\n'
            'Medicines\n- Paracetamol 650 mg BD x 5 days',
        'title': 'Right knee pain',
        'confidenceNote': '',
      });
      final note = await ScribeProcessingService(
        client: gemini,
      ).writeSessionNote(session: _session(), transcript: _conversation);

      expect(gemini.calls, 1);
      expect(gemini.lastAudio, isNull, reason: 'audio never leaves the device');
      expect(gemini.lastPrompt, contains('Session date: 2026-09-22'));
      expect(gemini.lastPrompt, contains('twisted it playing football'));
      expect(note.chiefComplaint, 'Right knee pain');
      expect(note.notes, startsWith('Presenting complaint'));
      expect(note.notes, contains('Paracetamol 650 mg'));
      expect(note.transcript, contains('football'));
      // Who, when and consent come from the session, untouched.
      expect(note.id, 'n1');
      expect(note.patientId, 'p1');
      expect(note.visitId, 'v1');
      expect(note.consentAt, DateTime(2026, 9, 22, 10));
    });

    test('tells the model who the clinician is', () async {
      final gemini = _FakeGemini({'notes': 'Seen.', 'title': 'Review'});
      await ScribeProcessingService(client: gemini).writeSessionNote(
        session: _session(specialty: SessionSpecialty.physiotherapy),
        transcript: _conversation,
      );
      expect(gemini.lastPrompt, contains('a physiotherapist'));
    });

    test('too little conversation fails without calling the AI', () async {
      final gemini = _FakeGemini({'notes': 'x'});
      await expectLater(
        ScribeProcessingService(
          client: gemini,
        ).writeSessionNote(session: _session(), transcript: 'hello there'),
        throwsA(
          isA<ScribeProcessingException>().having(
            (e) => e.kind,
            'kind',
            ScribeFailureKind.noConversation,
          ),
        ),
      );
      expect(gemini.calls, 0);
    });

    test('no notes back means no consultation, never an invented note', () async {
      final gemini = _FakeGemini({
        'notes': '',
        'title': '',
        'confidenceNote': 'Only background noise.',
      });
      await expectLater(
        ScribeProcessingService(
          client: gemini,
        ).writeSessionNote(session: _session(), transcript: _conversation),
        throwsA(
          isA<ScribeProcessingException>()
              .having((e) => e.kind, 'kind', ScribeFailureKind.noConversation)
              .having((e) => e.message, 'message', contains('noise')),
        ),
      );
    });

    test('only transient failures are retryable', () {
      expect(ScribeFailureKind.offline.isRetryable, isTrue);
      expect(ScribeFailureKind.timeout.isRetryable, isTrue);
      expect(ScribeFailureKind.badResponse.isRetryable, isTrue);
      expect(ScribeFailureKind.notConfigured.isRetryable, isFalse);
      expect(ScribeFailureKind.noConversation.isRetryable, isFalse);
    });
  });

  group('ScribeProcessingService.noteFromParsed', () {
    test('tolerates missing keys, wrong types and "null" strings', () {
      final note = ScribeProcessingService.noteFromParsed(
        {'notes': 42, 'title': 'null'},
        session: _session(),
        transcript: 'Doctor: Hello.',
      );
      expect(note.notes, isEmpty);
      expect(note.chiefComplaint, isEmpty);
      expect(note.confidenceNote, isEmpty);
      expect(note.transcript, 'Doctor: Hello.');
    });

    test('cleanNotes strips markdown and extra blank lines', () {
      expect(
        ScribeProcessingService.cleanNotes(
          '## **Presenting complaint**\nKnee pain.\n\n\n\n# Plan\n- Rest  ',
        ),
        'Presenting complaint\nKnee pain.\n\nPlan\n- Rest',
      );
    });
  });

  group('Session note fields', () {
    final session = _note(
      chiefComplaint: 'Migraine',
      notes: 'Presenting complaint\nMigraine, left side.',
    ).copyWith(
      specialty: SessionSpecialty.homeopathy,
      queueEntryId: 'q7',
      authorUid: 'doc-2',
      editedAt: DateTime(2026, 10, 1, 9),
      editedByUid: 'doc-3',
    );

    void expectSessionFields(ConsultationNote n) {
      expect(n.notes, 'Presenting complaint\nMigraine, left side.');
      expect(n.specialty, SessionSpecialty.homeopathy);
      expect(n.queueEntryId, 'q7');
      expect(n.authorUid, 'doc-2');
      expect(n.editedAt, DateTime(2026, 10, 1, 9));
      expect(n.editedByUid, 'doc-3');
      expect(n.isEdited, isTrue);
    }

    test('survive the local storage round trip', () {
      expectSessionFields(
        ConsultationNote.fromMap(session.toLocalMap(), id: 'n1'),
      );
    });

    test('survive the Firestore round trip', () {
      expectSessionFields(ConsultationNote.fromMap(session.toMap(), id: 'n1'));
    });

    test('older notes without them read back as a plain, unedited note', () {
      final legacy = _note().toLocalMap()
        ..remove('notes')
        ..remove('specialty')
        ..remove('queueEntryId')
        ..remove('authorUid')
        ..remove('editedAt')
        ..remove('editedByUid');
      final n = ConsultationNote.fromMap(legacy, id: 'n1');
      expect(n.notes, isEmpty);
      expect(n.specialty, SessionSpecialty.none);
      expect(n.queueEntryId, isNull);
      expect(n.authorUid, '');
      expect(n.isEdited, isFalse);
    });
  });

  group('ConsultationNoteRepository.buildVisitSummary', () {
    test('adds the session notes as written', () {
      final summary = ConsultationNoteRepository.buildVisitSummary(
        _note(
          chiefComplaint: 'Knee pain',
          notes: 'Presenting complaint\nRight knee pain for 3 weeks.',
        ),
      );
      expect(summary, startsWith('Session note (22 Sep 2026'));
      expect(summary, endsWith('Right knee pain for 3 weeks.'));
    });

    test('lays an older structured note out with only its filled fields', () {
      final summary = ConsultationNoteRepository.buildVisitSummary(
        _note(
          chiefComplaint: 'Knee pain',
          diagnoses: ['Osteoarthritis'],
          medicines: const [
            NotedMedicine(name: 'Diclofenac gel', instructions: 'Apply BD'),
          ],
        ),
      );
      expect(summary, contains('Session note (22 Sep 2026'));
      expect(summary, contains('Chief complaint: Knee pain'));
      expect(summary, contains('Diagnosis: Osteoarthritis'));
      expect(summary, contains('Medications: Diclofenac gel (Apply BD)'));
      expect(summary, isNot(contains('Advice:')));
      expect(summary, isNot(contains('Follow-up:')));
    });
  });

  group('Older physiotherapy notes', () {
    final physioJson = {
      'painNow': '6/10',
      'painWorst': 8,
      'redFlags': ['Night pain unrelieved by rest'],
      'rom': [
        {'movement': 'Knee flexion', 'side': 'R', 'value': 'AROM 95°'},
      ],
      'strength': [
        {'muscle': 'Quadriceps', 'side': 'R', 'grade': '4/5'},
      ],
      'specialTests': [
        {'test': 'McMurray', 'side': 'R', 'result': 'Positive'},
      ],
      'treatment': [
        {'intervention': 'IFT', 'details': 'Knee, 4-pole', 'minutes': '15'},
      ],
      'homeExercises': [
        {'exercise': 'Static quads', 'dosage': '3 × 10, hold 5 s'},
      ],
    };

    test('physio survives the storage round trip', () {
      final p = PhysioFindings.fromJson(physioJson);
      final restored = PhysioFindings.fromStored(p.toStored());
      expect(restored.toJson(), p.toJson());
      expect(PhysioFindings.fromStored('{not json').isEmpty, isTrue);
      expect(PhysioFindings.fromStored(null).isEmpty, isTrue);

      final note = _note(physio: p);
      final fromLocal = ConsultationNote.fromMap(note.toLocalMap(), id: 'n1');
      expect(fromLocal.physio.toJson(), p.toJson());
    });

    test('buildVisitSummary is laid out as SOAP', () {
      final summary = ConsultationNoteRepository.buildVisitSummary(
        _note(
          chiefComplaint: 'Right knee pain',
          diagnoses: ['Medial meniscus injury'],
          advice: 'Avoid squatting',
          physio: PhysioFindings.fromJson(physioJson),
        ),
      );

      final s = summary.indexOf('S — SUBJECTIVE');
      final o = summary.indexOf('O — OBJECTIVE');
      final a = summary.indexOf('A — ASSESSMENT');
      final pl = summary.indexOf('P — PLAN');
      expect([s, o, a, pl], everyElement(greaterThan(0)));
      expect(s < o && o < a && a < pl, isTrue);

      expect(summary, contains('Pain (NPRS): now 6/10, worst 8'));
      expect(summary, contains('⚠ Red flags present: Night pain'));
      expect(summary, contains('• Knee flexion (R): AROM 95°'));
      expect(summary, contains('• McMurray (R): Positive'));
      expect(summary, contains('• IFT: Knee, 4-pole, 15 min'));
    });
  });
}
