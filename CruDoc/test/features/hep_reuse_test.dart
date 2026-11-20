import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/therapy/data/exercise_library.dart';
import 'package:doctor_management_app/features/therapy/domain/hep_models.dart';

/// Reusing a programme and lifting the exercises a physio reaches for most.
/// The one that matters beyond convenience is the template: it is built from
/// one patient's programme and used on another, so nothing personal may ride
/// across with it.
void main() {
  final day0 = DateTime(2026, 5, 1);

  HepProgram program(
    List<String> exerciseIds, {
    int daysAgo = 0,
    String title = 'Knee rehab',
    String note = '',
    String patientId = 'p1',
  }) => HepProgram.fromRecord(
    DentalRecord.create(patientId, RecKind.physioHep, {
      'title': title,
      'note': note,
      'items': [
        for (final id in exerciseIds)
          {'exerciseId': id, 'name': id, 'sets': 3, 'reps': 10},
      ],
    }, at: day0.subtract(Duration(days: daysAgo))),
  );

  group('recentExerciseIds', () {
    test('newest programme first', () {
      final ids = recentExerciseIds([
        program(['old-one'], daysAgo: 30),
        program(['new-one'], daysAgo: 1),
      ]);
      expect(ids.first, 'new-one');
    });

    test('an exercise in two programmes appears once', () {
      final ids = recentExerciseIds([
        program(['a', 'b'], daysAgo: 1),
        program(['b', 'c'], daysAgo: 5),
      ]);
      expect(ids, ['a', 'b', 'c']);
    });

    test('stops at the limit', () {
      final ids = recentExerciseIds([
        program(['a', 'b', 'c', 'd', 'e']),
      ], limit: 3);
      expect(ids, hasLength(3));
    });

    test('no programmes, no recents', () {
      expect(recentExerciseIds(const []), isEmpty);
    });

    test('a blank exercise id is ignored', () {
      final ids = recentExerciseIds([program(['', 'a'])]);
      expect(ids, ['a']);
    });
  });

  group('orderExercises', () {
    ExerciseDef ex(String id, {bool favourite = false}) => ExerciseDef(
      id: id,
      name: id,
      region: ExerciseRegion.knee,
      goal: '',
      steps: const [],
      cautions: '',
      favourite: favourite,
    );

    test('starred first, then recent, then the rest', () {
      final out = orderExercises([
        ex('plain'),
        ex('recent'),
        ex('starred', favourite: true),
      ], ['recent']);
      expect([for (final e in out) e.id], ['starred', 'recent', 'plain']);
    });

    test('recents keep the order they were last used in', () {
      final out = orderExercises([
        ex('b'),
        ex('a'),
      ], ['a', 'b']);
      expect([for (final e in out) e.id], ['a', 'b']);
    });

    test('a starred exercise is not listed twice for being recent too', () {
      final out = orderExercises([ex('a', favourite: true)], ['a']);
      expect(out, hasLength(1));
    });

    test('nothing starred or recent leaves the order alone', () {
      final out = orderExercises([ex('a'), ex('b'), ex('c')], const []);
      expect([for (final e in out) e.id], ['a', 'b', 'c']);
    });

    test('every exercise survives the sort', () {
      final all = [for (final e in kExerciseLibrary) e];
      expect(orderExercises(all, ['knee-quad-set']), hasLength(all.length));
    });
  });

  group('HepTemplate', () {
    test('keeps the title and the exercises', () {
      final data = HepTemplate.toData(
        title: 'Post-op knee week 1',
        items: program(['knee-quad-set', 'lb-bridge']).items,
      );
      final t = HepTemplate.fromRecord(
        DentalRecord.create('', RecKind.physioHepTemplate, data),
      );
      expect(t.title, 'Post-op knee week 1');
      expect([for (final i in t.items) i.exerciseId], [
        'knee-quad-set',
        'lb-bridge',
      ]);
    });

    test('carries nothing about the patient it came from', () {
      // The template is used on other patients, so the note written about
      // this one must not travel with it.
      final source = program(
        ['knee-quad-set'],
        note: 'Mrs Rao is nervous about the stairs after her fall',
        patientId: 'p1',
      );
      final data = HepTemplate.toData(title: source.title, items: source.items);
      expect(data.containsKey('note'), isFalse);
      expect(data.toString(), isNot(contains('Rao')));

      final record = DentalRecord.create('', RecKind.physioHepTemplate, data);
      expect(record.patientId, isEmpty);
    });

    test('keeps the dose the physio set, not the library default', () {
      final items = program(['knee-quad-set']).items;
      final t = HepTemplate.fromRecord(
        DentalRecord.create(
          '',
          RecKind.physioHepTemplate,
          HepTemplate.toData(title: 'x', items: items),
        ),
      );
      expect(t.items.single.sets, 3);
      expect(t.items.single.reps, 10);
    });
  });
}
