import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/session_history_card.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/repo/consultation_note_repository.dart';
import 'package:doctor_management_app/features/scribe/presentation/session_note_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

ConsultationNote _session({
  String id = 'n1',
  String chiefComplaint = '',
  String notes = '',
  String confidenceNote = '',
  List<String> diagnoses = const [],
  String advice = '',
  String specialty = SessionSpecialty.homeopathy,
  DateTime? at,
  DateTime? editedAt,
}) {
  return ConsultationNote(
    id: id,
    doctorId: 'clinic-1',
    patientId: 'p1',
    visitId: 'v1',
    specialty: specialty,
    chiefComplaint: chiefComplaint,
    notes: notes,
    confidenceNote: confidenceNote,
    diagnosisSuggestions: diagnoses,
    advice: advice,
    status: ConsultationNoteStatus.confirmed,
    createdAt: at ?? DateTime(2026, 10, 3, 10, 30),
    editedAt: editedAt,
  );
}

Patient _patient() => Patient.fromMap(const {
  'firstName': 'Asha',
  'lastName': 'Rao',
  'phone': '9000000000',
}, id: 'p1');

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: CruTheme.day(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  group('soapSections', () {
    test('groups filled fields in SOAP order and skips empty sections', () {
      final groups = ConsultationNoteRepository.soapSections(
        _session(chiefComplaint: 'Migraine', advice: 'Avoid coffee'),
      );
      expect(groups.map((g) => g.section.letter), ['S', 'P']);
      expect(groups.first.lines, ['Chief complaint: Migraine']);
      expect(groups.last.lines, ['Advice: Avoid coffee']);
    });

    test('an empty note has no sections', () {
      expect(ConsultationNoteRepository.soapSections(_session()), isEmpty);
    });
  });

  group('sessionTitle', () {
    test('prefers the title, then the first diagnosis', () {
      expect(
        sessionTitle(_session(chiefComplaint: 'Migraine', diagnoses: ['X'])),
        'Migraine',
      );
      expect(sessionTitle(_session(diagnoses: [' ', 'Sinusitis'])), 'Sinusitis');
    });

    test('falls back to the kind of session', () {
      expect(sessionTitle(_session()), 'Homeopathy session note');
      expect(
        sessionTitle(_session(specialty: SessionSpecialty.physiotherapy)),
        'Physiotherapy session note',
      );
      expect(
        sessionTitle(_session(specialty: SessionSpecialty.none)),
        'Session note',
      );
    });
  });

  group('editableNotesOf', () {
    test('is the notes as written', () {
      expect(
        editableNotesOf(_session(notes: 'Advice\nRest.', advice: 'ignored')),
        'Advice\nRest.',
      );
    });

    test('lays an older structured note out as SOAP text', () {
      expect(
        editableNotesOf(
          _session(chiefComplaint: 'Migraine', advice: 'Avoid coffee'),
        ),
        'Subjective\nChief complaint: Migraine\n\nPlan\nAdvice: Avoid coffee',
      );
    });
  });

  group('SessionHistoryCard', () {
    testWidgets('lists sessions newest first with their titles', (t) async {
      await _pump(
        t,
        SessionHistoryCard(
          patient: _patient(),
          sessions: [
            _session(id: 'a', chiefComplaint: 'Migraine'),
            _session(
              id: 'b',
              chiefComplaint: 'Knee pain',
              at: DateTime(2026, 9, 20, 9),
              editedAt: DateTime(2026, 9, 22),
            ),
          ],
        ),
      );
      expect(find.text('Session notes'), findsOneWidget);
      expect(find.text('Migraine'), findsOneWidget);
      expect(find.text('Knee pain'), findsOneWidget);
      expect(find.text('9:00 AM · Edited'), findsOneWidget);
      expect(find.text('See all'), findsNothing);
    });

    testWidgets('shows four sessions until See all is tapped', (t) async {
      final sessions = [
        for (var i = 0; i < 6; i++)
          _session(id: 's$i', chiefComplaint: 'Visit $i'),
      ];
      await _pump(
        t,
        SessionHistoryCard(patient: _patient(), sessions: sessions),
      );
      expect(find.text('Visit 3'), findsOneWidget);
      expect(find.text('Visit 4'), findsNothing);

      await t.tap(find.text('See all'));
      await t.pump();
      expect(find.text('Visit 5'), findsOneWidget);
      expect(find.text('Show less'), findsOneWidget);
    });
  });

  group('Session note view', () {
    testWidgets('shows the notes under their headings', (t) async {
      await _pump(
        t,
        SessionNoteBody(
          note: _session(
            notes:
                'Presenting complaint\nRight knee pain for 3 weeks.\n\n'
                'Advice\n- Avoid squatting\n- Ice twice a day\n\n'
                'Patient was anxious about surgery.',
            confidenceNote: 'Dose of the gel was unclear.',
          ),
        ),
      );
      expect(find.text('PRESENTING COMPLAINT'), findsOneWidget);
      expect(find.text('Right knee pain for 3 weeks.'), findsOneWidget);
      expect(find.text('ADVICE'), findsOneWidget);
      expect(find.text('- Avoid squatting\n- Ice twice a day'), findsOneWidget);
      // A one-line block is a paragraph, not a heading.
      expect(find.text('Patient was anxious about surgery.'), findsOneWidget);
      expect(find.text('⚠ Check: Dose of the gel was unclear.'), findsOneWidget);
    });

    testWidgets('lays an older note out as SOAP sections', (t) async {
      await _pump(
        t,
        SessionNoteBody(
          note: _session(chiefComplaint: 'Migraine', advice: 'Avoid coffee'),
        ),
      );
      expect(find.text('SUBJECTIVE'), findsOneWidget);
      expect(find.text('PLAN'), findsOneWidget);
      expect(find.text('Chief complaint: Migraine'), findsOneWidget);
      expect(find.text('Advice: Avoid coffee'), findsOneWidget);
    });

    testWidgets('marks the note as AI-made, and edited once changed', (
      t,
    ) async {
      await _pump(
        t,
        SessionNoteHeader(note: _session(editedAt: DateTime(2026, 10, 5))),
      );
      expect(find.text('AI scribe'), findsOneWidget);
      expect(find.text('Edited 5 Oct 2026'), findsOneWidget);

      await _pump(t, SessionNoteHeader(note: _session()));
      expect(find.textContaining('Edited'), findsNothing);
    });
  });
}
