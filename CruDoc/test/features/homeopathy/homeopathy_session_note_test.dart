import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_session_note.dart';
import 'package:doctor_management_app/features/homeopathy/services/homeopathy_session_scribe_service.dart';

final sessionDate = DateTime(2026, 10, 10);
final now = DateTime(2026, 10, 10, 11, 30);

HomeopathySessionNote parse(Map<String, dynamic> json) =>
    HomeopathySessionScribeService.noteFromParsed(
      json,
      id: 'n1',
      patientId: 'p1',
      doctorId: 'doc',
      visitId: 'v1',
      sessionDate: sessionDate,
      now: now,
    );

void main() {
  group('noteFromParsed', () {
    test('maps a full follow-up visit', () {
      final note = parse({
        'transcript': 'Doctor: How are the headaches? Patient: Much better.',
        'problemToday': 'Follow-up for right-sided migraine',
        'symptomStatus': 'better',
        'symptomDetails': 'Down from daily to twice a week',
        'oldSymptomsReturned': 'Old eczema behind the ears is back',
        'responseToRemedy': 'aggravatedThenBetter',
        'heringsLawObservation': 'Moving outward to the skin',
        'remedyGiven': 'Natrum muriaticum',
        'potency': '200C',
        'repetition': 'Single dose',
        'nextFollowUpDate': '2026-10-25',
      });

      expect(note.id, 'n1');
      expect(note.patientId, 'p1');
      expect(note.visitId, 'v1');
      expect(note.sessionDate, sessionDate);
      expect(note.problemToday, 'Follow-up for right-sided migraine');
      expect(note.symptomStatus, HomeopathySymptomStatus.better);
      expect(
        note.responseToRemedy,
        HomeopathyRemedyResponse.aggravatedThenBetter,
      );
      expect(note.oldSymptomsReturned, 'Old eczema behind the ears is back');
      expect(note.potency, '200C');
      expect(note.nextFollowUpDate, DateTime(2026, 10, 25));
      expect(note.createdAt, now);
    });

    test('missing, null and wrong-typed fields become empty', () {
      final note = parse({
        'problemToday': 'null',
        'symptomDetails': null,
        'potency': 30,
        'nextFollowUpDate': 'next month',
      });
      expect(note.problemToday, isEmpty);
      expect(note.symptomDetails, isEmpty);
      expect(note.potency, isEmpty);
      expect(note.nextFollowUpDate, isNull);
      expect(note.symptomStatus, HomeopathySymptomStatus.unspecified);
      expect(note.responseToRemedy, HomeopathyRemedyResponse.notApplicable);
      expect(note.isEmpty, isTrue);
    });

    test('every enum value the schema offers parses back to itself', () {
      for (final s in HomeopathySymptomStatus.values) {
        expect(HomeopathySymptomStatus.fromString(s.name), s);
      }
      for (final r in HomeopathyRemedyResponse.values) {
        expect(HomeopathyRemedyResponse.fromString(r.name), r);
      }
    });
  });

  test('local storage round-trips every field', () {
    final note = parse({
      'transcript': 't',
      'problemToday': 'Acidity',
      'symptomStatus': 'newProblem',
      'symptomDetails': 'sd',
      'oldSymptomsReturned': 'osr',
      'newSymptoms': 'ns',
      'modalitiesToday': 'worse after tea',
      'mentalStateToday': 'irritable',
      'generalsToday': 'thirstless',
      'complianceNotes': 'missed two doses',
      'intercurrentIllness': 'viral fever',
      'responseToRemedy': 'noAction',
      'heringsLawObservation': 'h',
      'clinicalImpression': 'ci',
      'remedyGiven': 'Puls',
      'potency': '30C',
      'repetition': 'BD x 5 days',
      'adviceGiven': 'avoid coffee',
      'nextFollowUpDate': '2026-11-01',
      'confidenceNote': 'c',
    });

    final back = HomeopathySessionNote.fromMap(note.toLocalMap());
    expect(back.toLocalMap(), note.toLocalMap());
  });

  test('the schema asks for every field the note stores', () {
    final schemaKeys = HomeopathySessionScribeService
        .responseSchema
        .properties!
        .keys
        .toSet();
    const notFromModel = {
      'id',
      'patientId',
      'doctorId',
      'visitId',
      'sessionDate',
      'createdAt',
      'updatedAt',
    };
    final noteKeys = parse(const {}).toLocalMap().keys.toSet().difference(
      notFromModel,
    );
    expect(schemaKeys, noteKeys);
  });
}
