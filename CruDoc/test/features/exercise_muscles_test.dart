import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/therapy/data/exercise_library.dart';
import 'package:doctor_management_app/features/therapy/domain/hep_models.dart';

/// The exercise library names the muscles each exercise works, as side-neutral
/// ids from the 3D viewer's catalogue. A mistyped id is the dangerous case: the
/// chart would highlight nothing at all and look like the exercise simply works
/// no muscles, with nothing anywhere to say it was a typo. So every id is
/// checked against the catalogue the viewer actually loads.
void main() {
  // Read the asset from disk rather than through rootBundle: this is a plain
  // unit test, and the file is the same one the WebView is served.
  final catalog =
      jsonDecode(File('assets/muscle_viewer/catalog.json').readAsStringSync())
          as Map<String, dynamic>;
  final muscles = (catalog['muscles'] as List).cast<Map<String, dynamic>>();

  /// Catalogue ids with the side suffix removed, which is what an exercise
  /// stores. `m_diaphragm` and a few other midline muscles have no suffix.
  final baseIds = <String>{
    for (final m in muscles)
      (m['id'] as String).replaceAll(RegExp(r'_(l|r)$'), ''),
  };

  test('the catalogue loaded', () {
    expect(muscles, isNotEmpty);
    expect(baseIds.length, lessThan(muscles.length)); // sides collapsed
  });

  test('every muscle id an exercise names exists in the catalogue', () {
    final unknown = <String>[];
    for (final e in kExerciseLibrary) {
      for (final m in e.muscles) {
        if (!baseIds.contains(m)) unknown.add('${e.id} -> $m');
      }
    }
    expect(
      unknown,
      isEmpty,
      reason: 'not in catalog.json:\n${unknown.join('\n')}',
    );
  });

  test('no exercise names the same muscle twice', () {
    for (final e in kExerciseLibrary) {
      expect(
        e.muscles.toSet().length,
        e.muscles.length,
        reason: '${e.id} repeats a muscle',
      );
    }
  });

  test('ids are side-neutral, so both sides can be highlighted', () {
    for (final e in kExerciseLibrary) {
      for (final m in e.muscles) {
        expect(
          m,
          isNot(matches(r'_(l|r)$')),
          reason: '${e.id} names one side only',
        );
      }
    }
  });

  test('a muscle list is short enough to read on the chart', () {
    for (final e in kExerciseLibrary) {
      expect(
        e.muscles.length,
        lessThanOrEqualTo(4),
        reason: '${e.id} highlights too much to be useful',
      );
    }
  });

  group('programMuscles', () {
    HepProgram program(List<String> exerciseIds) => HepProgram.fromRecord(
      DentalRecord.create('p1', RecKind.physioHep, {
        'title': 'Knee rehab',
        'note': '',
        'items': [
          for (final id in exerciseIds)
            {'exerciseId': id, 'name': id, 'sets': 3, 'reps': 10},
        ],
      }),
    );

    test('gathers the muscles of every exercise in the programme', () {
      final ids = programMuscles(
        program(['knee-quad-set', 'ankle-calf-raise']),
        kExerciseLibrary,
      );
      expect(ids, contains('m_vastus_medialis_muscle'));
      expect(ids, contains('m_soleus_muscle'));
    });

    test('never repeats a muscle two exercises share', () {
      final ids = programMuscles(
        program(['knee-quad-set', 'knee-mini-squat']),
        kExerciseLibrary,
      );
      expect(ids.toSet().length, ids.length);
    });

    test('keeps the order the programme lists them in', () {
      final ids = programMuscles(
        program(['ankle-calf-raise', 'knee-quad-set']),
        kExerciseLibrary,
      );
      expect(
        ids.indexOf('m_soleus_muscle'),
        lessThan(ids.indexOf('m_vastus_medialis_muscle')),
      );
    });

    test('an exercise with no muscle target contributes nothing', () {
      expect(
        programMuscles(program(['ankle-alphabet']), kExerciseLibrary),
        isEmpty,
      );
    });

    test('an exercise the catalogue no longer has is skipped', () {
      final ids = programMuscles(
        program(['was-deleted', 'knee-quad-set']),
        kExerciseLibrary,
      );
      expect(ids, contains('m_vastus_medialis_muscle'));
    });

    test('no programme means nothing is highlighted', () {
      expect(programMuscles(null, kExerciseLibrary), isEmpty);
    });
  });

  group('coverage', () {
    // Not every exercise has a muscle target: some exist for range,
    // balance or breath control. Those are deliberate, and listed here so
    // adding a strengthening exercise without muscles fails the test.
    const noTarget = {
      'shoulder-pendulum',
      'knee-heel-slide',
      'ankle-alphabet',
      'bal-tandem-stance',
      'breath-pursed-lip',
      // Balance work trains the reaction, not a muscle. Highlighting a
      // chart for these would point at whatever happened to be holding the
      // patient up rather than at the thing being trained.
      'bal-weight-shift',
      'bal-head-turns',
      'bal-single-leg-eyes-closed',
      'bal-cushion-stand',
      'bal-step-over',
    };

    test('no two exercises share an id', () {
      // Added after two were introduced by accident. A duplicate id is
      // quiet and nasty: the picker shows both, a saved programme resolves
      // to whichever comes first, and a physio editing one appears to edit
      // the other at random.
      final seen = <String>{};
      final twice = <String>[];
      for (final e in kExerciseLibrary) {
        if (!seen.add(e.id)) twice.add(e.id);
      }
      expect(twice, isEmpty, reason: 'duplicated:\n${twice.join('\n')}');
    });

    test('every exercise has a name, a goal and steps to follow', () {
      // A library entry with no steps is worse than a missing one: it looks
      // like an exercise the patient can be sent home with.
      for (final e in kExerciseLibrary) {
        expect(e.name.trim(), isNotEmpty, reason: e.id);
        expect(e.goal.trim(), isNotEmpty, reason: e.id);
        expect(e.steps, isNotEmpty, reason: e.id);
        expect(e.cautions.trim(), isNotEmpty, reason: e.id);
      }
    });

    test('every exercise names what to stop for', () {
      // The one line that has to be on all of them.
      for (final e in kExerciseLibrary) {
        expect(
          e.cautions.toLowerCase(),
          contains('stop'),
          reason: '${e.id} does not say when to stop',
        );
      }
    });

    test('every other exercise names its muscles', () {
      final missing = [
        for (final e in kExerciseLibrary)
          if (!e.hasMuscles && !noTarget.contains(e.id)) e.id,
      ];
      expect(
        missing,
        isEmpty,
        reason: 'no muscles set:\n${missing.join('\n')}',
      );
    });

    test('the exempt list has no stale entries', () {
      final ids = {for (final e in kExerciseLibrary) e.id};
      expect(noTarget.difference(ids), isEmpty);
      for (final id in noTarget) {
        final e = kExerciseLibrary.firstWhere((x) => x.id == id);
        expect(e.muscles, isEmpty, reason: '$id now has muscles: un-exempt it');
      }
    });
  });
}
