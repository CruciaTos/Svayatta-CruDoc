import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/models/physio_findings.dart';
import 'package:doctor_management_app/features/scribe/data/repo/consultation_note_repository.dart';
import 'package:doctor_management_app/features/scribe/presentation/scribe_draft_form_controller.dart';
import 'package:doctor_management_app/features/scribe/presentation/widgets/scribe_draft_form.dart';
import 'package:doctor_management_app/features/scribe/presentation/widgets/scribe_palette.dart';
import 'package:doctor_management_app/features/scribe/services/scribe_processing_service.dart';

ConsultationNote _parse(Map<String, dynamic> json) {
  return ScribeProcessingService.noteFromParsed(
    parsed: json,
    noteId: 'n1',
    doctorId: 'd1',
    patientId: 'p1',
    visitId: 'v1',
    consentAt: DateTime(2026, 9, 22, 10),
    now: DateTime(2026, 9, 22, 10, 30),
  );
}

ConsultationNote _note({
  String chiefComplaint = '',
  List<String> symptoms = const [],
  List<String> diagnoses = const [],
  List<NotedMedicine> medicines = const [],
  String advice = '',
  String transcript = '',
  PhysioFindings physio = PhysioFindings.empty,
}) {
  return ConsultationNote(
    id: 'n1',
    doctorId: 'd1',
    patientId: 'p1',
    visitId: 'v1',
    chiefComplaint: chiefComplaint,
    symptoms: symptoms,
    diagnosisSuggestions: diagnoses,
    medicines: medicines,
    advice: advice,
    transcript: transcript,
    physio: physio,
    createdAt: DateTime(2026, 9, 22, 10, 30),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScribeProcessingService.noteFromParsed', () {
    test('maps a complete response onto the draft', () {
      final note = _parse({
        'transcript': 'Doctor: What brings you in?\nPatient: Fever.',
        'chiefComplaint': 'Fever for 3 days',
        'symptoms': ['Fever', 'Body ache'],
        'diagnosisSuggestions': ['Viral fever'],
        'medicines': [
          {
            'name': 'Paracetamol 650 mg',
            'dosage': '1 tab TDS',
            'instructions': 'After food',
          },
        ],
        'advice': 'Fluids and rest',
        'followUpDate': '2026-09-27',
        'vitalsIfMentioned': {'bp': '120/80', 'temp': '101 F', 'pulse': null},
        'transcriptSummaryConfidenceNote': 'Some background noise.',
      });

      expect(note.transcript, startsWith('Doctor:'));
      expect(note.chiefComplaint, 'Fever for 3 days');
      expect(note.symptoms, ['Fever', 'Body ache']);
      expect(note.diagnosisSuggestions, ['Viral fever']);
      expect(note.medicines.single.name, 'Paracetamol 650 mg');
      expect(note.medicines.single.dosage, '1 tab TDS');
      expect(note.followUpDate, DateTime(2026, 9, 27));
      expect(note.vitals, {'bp': '120/80', 'temp': '101 F', 'pulse': null});
      expect(note.confidenceNote, 'Some background noise.');
      expect(note.status, ConsultationNoteStatus.draft);
      expect(note.consentAt, DateTime(2026, 9, 22, 10));
    });

    test('never invents content for an empty response', () {
      final note = _parse({});

      expect(note.transcript, isEmpty);
      expect(note.chiefComplaint, isEmpty);
      expect(note.symptoms, isEmpty);
      expect(note.diagnosisSuggestions, isEmpty);
      expect(note.medicines, isEmpty);
      expect(note.advice, isEmpty);
      expect(note.followUpDate, isNull);
      expect(note.vitals.values, everyElement(isNull));
    });

    test('tolerates wrong types, "null" strings and duplicates', () {
      final note = _parse({
        'chiefComplaint': 'null',
        'symptoms': ['Cough', ' cough ', '', 'Cold'],
        'diagnosisSuggestions': 'not a list',
        'medicines': [
          {'name': '  ', 'dosage': '5 ml'},
          {'name': 'Cetirizine', 'dosage': null},
          'garbage',
        ],
        'followUpDate': 'next week',
        'vitalsIfMentioned': 'n/a',
      });

      expect(note.chiefComplaint, isEmpty);
      expect(note.symptoms, ['Cough', 'Cold']);
      expect(note.diagnosisSuggestions, isEmpty);
      expect(note.medicines.map((m) => m.name), ['Cetirizine']);
      expect(note.medicines.single.dosage, isEmpty);
      expect(note.followUpDate, isNull);
      expect(note.vitals.values, everyElement(isNull));
    });

    test('extractJson strips markdown fences and prose', () {
      expect(
        ScribeProcessingService.extractJson('```json\n{"a": 1}\n```'),
        '{"a": 1}',
      );
      expect(
        ScribeProcessingService.extractJson('Here you go: {"a": 1} thanks'),
        '{"a": 1}',
      );
      expect(ScribeProcessingService.extractJson(' {"a": 1} '), '{"a": 1}');
    });

    test('only transient failures are retryable', () {
      expect(ScribeFailureKind.offline.isRetryable, isTrue);
      expect(ScribeFailureKind.timeout.isRetryable, isTrue);
      expect(ScribeFailureKind.badResponse.isRetryable, isTrue);
      expect(ScribeFailureKind.notConfigured.isRetryable, isFalse);
      expect(ScribeFailureKind.audio.isRetryable, isFalse);
    });
  });

  group('ConsultationNoteRepository helpers', () {
    test('mergeDiagnoses dedupes case-insensitively', () {
      final result = ConsultationNoteRepository.mergeDiagnoses(
        ['Hypertension'],
        ['hypertension', 'Type 2 diabetes', 'Type 2 Diabetes', ' '],
      );
      expect(result.diagnoses, ['Hypertension', 'Type 2 diabetes']);
      expect(result.overflow, isEmpty);
    });

    test('mergeDiagnoses caps at four and returns the overflow', () {
      final result = ConsultationNoteRepository.mergeDiagnoses(
        ['A', 'B', 'C'],
        ['D', 'E', 'F'],
      );
      expect(result.diagnoses, ['A', 'B', 'C', 'D']);
      expect(result.overflow, ['E', 'F']);
    });

    test('buildVisitSummary lists only the filled sections', () {
      final summary = ConsultationNoteRepository.buildVisitSummary(
        _note(
          chiefComplaint: 'Knee pain',
          diagnoses: ['Osteoarthritis'],
          medicines: const [
            NotedMedicine(name: 'Diclofenac gel', instructions: 'Apply BD'),
          ],
        ),
      );
      expect(summary, contains('AI Scribe note (22 Sep 2026'));
      expect(summary, contains('Chief complaint: Knee pain'));
      expect(summary, contains('Diagnosis: Osteoarthritis'));
      expect(summary, contains('Medications: Diclofenac gel (Apply BD)'));
      expect(summary, isNot(contains('Advice:')));
      expect(summary, isNot(contains('Follow-up:')));
    });
  });

  group('ScribeDraftFormController', () {
    test('toNote applies edits and drops blank entries', () {
      final form = ScribeDraftFormController(
        _note(
          chiefComplaint: 'Cough',
          medicines: const [NotedMedicine(name: 'Syrup A')],
        ),
      );
      form.chiefComplaint.text = '  Dry cough for a week ';
      form.addSymptom('Cough');
      form.addSymptom('cough'); // duplicate, ignored
      form.addMedicine(); // left blank, dropped
      form.bp.text = ' 130/85 ';

      final note = form.toNote();
      expect(note.chiefComplaint, 'Dry cough for a week');
      expect(note.symptoms, ['Cough']);
      expect(note.medicines.map((m) => m.name), ['Syrup A']);
      expect(note.vitals['bp'], '130/85');
      expect(note.vitals['temp'], isNull);
      form.dispose();
    });

    test('confirm needs the review tick and some content', () {
      final form = ScribeDraftFormController(_note());
      expect(form.isEmpty, isTrue);
      form.setReviewed(true);
      expect(form.canConfirm, isFalse);

      form.advice.text = 'Rest';
      expect(form.canConfirm, isTrue);

      form.setReviewed(false);
      expect(form.canConfirm, isFalse);
      form.dispose();
    });
  });

  group('ScribeDraftForm widget', () {
    Future<ScribeDraftFormController> pumpForm(WidgetTester tester) async {
      final form = ScribeDraftFormController(
        _note(
          chiefComplaint: 'Fever',
          medicines: const [
            NotedMedicine(name: 'Med One'),
            NotedMedicine(name: 'Med Two'),
          ],
        ),
      );
      addTearDown(form.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScribeDraftForm(
                controller: form,
                palette: ScribePalette.mobile,
              ),
            ),
          ),
        ),
      );
      return form;
    }

    testWidgets('typing in a medicine keeps text across rebuilds', (
      tester,
    ) async {
      final form = await pumpForm(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Med One'),
        'Med 1',
      );
      await tester.pump();
      // Trigger an unrelated rebuild (previously recreated the controllers).
      form.setReviewed(true);
      await tester.pump();

      expect(find.widgetWithText(TextField, 'Med 1'), findsOneWidget);
      expect(form.toNote().medicines.first.name, 'Med 1');
    });

    testWidgets("removing a medicine doesn't shift its neighbour's text", (
      tester,
    ) async {
      final form = await pumpForm(tester);

      await tester.tap(find.byTooltip('Remove medicine').first);
      await tester.pump();

      expect(find.widgetWithText(TextField, 'Med One'), findsNothing);
      expect(find.widgetWithText(TextField, 'Med Two'), findsOneWidget);
      expect(form.toNote().medicines.map((m) => m.name), ['Med Two']);
    });

    testWidgets('shows the manual-entry notice for a blank note', (
      tester,
    ) async {
      final form = ScribeDraftFormController(_note());
      addTearDown(form.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScribeDraftForm(
                controller: form,
                palette: ScribePalette.desktop,
              ),
            ),
          ),
        ),
      );
      expect(
        find.textContaining('Write the consultation note'),
        findsOneWidget,
      );
      expect(find.textContaining('AI-generated draft'), findsNothing);
    });
  });

  group('Physiotherapy fields', () {
    final physioJson = {
      'painNow': '6/10',
      'painWorst': 8,
      'painLocation': ['Right knee, medial', 'right knee, medial'],
      'onset': 'Twisted knee playing football 3 weeks ago',
      'redFlags': ['Night pain unrelieved by rest'],
      'redFlagsCleared': ['No locking'],
      'unknownField': 'ignored',
      'rom': [
        {'movement': 'Knee flexion', 'side': 'R', 'value': 'AROM 95°'},
        {'movement': '', 'side': 'L', 'value': '130°'},
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
      'shortTermGoals': ['Pain < 3/10 in 2 weeks'],
    };

    test('noteFromParsed maps the physio object and cleans it', () {
      final note = _parse({'physio': physioJson});
      final p = note.physio;

      expect(p.textOf('painNow'), '6/10');
      expect(p.textOf('painWorst'), '8'); // numbers are kept as text
      expect(p.listOf('painLocation'), ['Right knee, medial']);
      expect(p.listOf('redFlags'), ['Night pain unrelieved by rest']);
      expect(p.tableOf('rom'), hasLength(1)); // row without a movement dropped
      expect(p.tableOf('rom').single['value'], 'AROM 95°');
      expect(p.tableOf('homeExercises').single['frequency'], '');
      expect(p.toJson().containsKey('unknownField'), isFalse);
      expect(p.isEmpty, isFalse);
    });

    test('missing or malformed physio data is empty, never invented', () {
      expect(_parse({}).physio.isEmpty, isTrue);
      expect(_parse({'physio': 'garbage'}).physio.isEmpty, isTrue);
      expect(
        _parse({
          'physio': {
            'painNow': 'null',
            'rom': 'n/a',
            'aggravating': [' ', null],
          },
        }).physio.isEmpty,
        isTrue,
      );
    });

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
      expect(summary, contains('• Quadriceps (R): 4/5'));
      expect(summary, contains('• McMurray (R): Positive'));
      expect(summary, contains('• IFT: Knee, 4-pole, 15 min'));
      expect(summary, contains('• Static quads: 3 × 10, hold 5 s'));
      expect(summary, isNot(contains('Neurological screen')));
    });

    test('form controller round-trips physio edits', () {
      final form = ScribeDraftFormController(
        _note(physio: PhysioFindings.fromJson(physioJson)),
      );
      form.physioText['painNow']!.text = ' 4/10 ';
      form.addPhysioListItem('aggravating', 'Stairs');
      form.removePhysioListItem('redFlags', 0);
      final spec = PhysioFindings.tableSpecs.firstWhere(
        (t) => t.key == 'specialTests',
      );
      form.addTableRow(spec).cells['test']!.text = 'Lachman';
      form.addTableRow(spec); // left blank, dropped

      final p = form.toNote().physio;
      expect(p.textOf('painNow'), '4/10');
      expect(p.listOf('aggravating'), ['Stairs']);
      expect(p.listOf('redFlags'), isEmpty);
      expect(p.tableOf('specialTests').map((r) => r['test']), [
        'McMurray',
        'Lachman',
      ]);
      form.dispose();
    });

    test('a physio-only note can be confirmed', () {
      final form = ScribeDraftFormController(_note());
      form.setReviewed(true);
      expect(form.canConfirm, isFalse);
      form.physioText['palpation']!.text = 'Tender medial joint line';
      expect(form.canConfirm, isTrue);
      form.dispose();
    });

    testWidgets('AI draft hides empty fields and flags red flags', (
      tester,
    ) async {
      final form = ScribeDraftFormController(
        _note(
          chiefComplaint: 'Knee pain',
          transcript: 'Doctor: ...',
          physio: PhysioFindings.fromJson(physioJson),
        ),
      );
      addTearDown(form.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScribeDraftForm(
                controller: form,
                palette: ScribePalette.desktop,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Red flags reported'), findsOneWidget);
      expect(find.text('RANGE OF MOTION'), findsOneWidget);
      expect(find.text('PALPATION'), findsNothing);

      final addObjective = find.textContaining('Add fields').at(1);
      await tester.ensureVisible(addObjective);
      await tester.tap(addObjective);
      await tester.pump();
      expect(find.text('PALPATION'), findsOneWidget);
    });
  });
}
