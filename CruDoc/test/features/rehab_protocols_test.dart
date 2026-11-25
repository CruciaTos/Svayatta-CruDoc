import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/therapy/data/exercise_library.dart';
import 'package:doctor_management_app/features/therapy/data/rehab_protocols.dart';

/// A protocol is a list of exercise ids, and an id that does not resolve is
/// invisible: the exercise is silently dropped from the programme the
/// patient is sent home with, and nothing anywhere says so. That is the
/// failure these tests exist to prevent.
void main() {
  final libraryIds = {for (final e in kExerciseLibrary) e.id};

  group('protocols resolve', () {
    test('every exercise a protocol names exists in the library', () {
      final broken = <String>[];
      for (final p in kRehabProtocols) {
        for (final item in p.items) {
          if (!libraryIds.contains(item.exerciseId)) {
            broken.add('${p.id} → ${item.exerciseId}');
          }
        }
      }
      expect(
        broken,
        isEmpty,
        reason:
            'protocols naming exercises that do not exist:\n'
            '${broken.join('\n')}',
      );
    });

    test('no protocol lists the same exercise twice', () {
      for (final p in kRehabProtocols) {
        final seen = <String>{};
        final twice = <String>[];
        for (final item in p.items) {
          if (!seen.add(item.exerciseId)) twice.add(item.exerciseId);
        }
        expect(twice, isEmpty, reason: '${p.id} repeats:\n${twice.join()}');
      }
    });

    test('no protocol is empty', () {
      // An empty protocol is worse than a missing one: it looks like a
      // programme the physio can hand over.
      for (final p in kRehabProtocols) {
        expect(p.items, isNotEmpty, reason: p.id);
      }
    });

    test('a protocol is short enough to actually be done at home', () {
      // Beyond about eight exercises a home programme stops being followed.
      for (final p in kRehabProtocols) {
        expect(
          p.items.length,
          lessThanOrEqualTo(8),
          reason: '${p.id} has ${p.items.length} exercises',
        );
      }
    });
  });

  group('protocols are identifiable', () {
    test('ids are unique', () {
      final seen = <String>{};
      final twice = <String>[];
      for (final p in kRehabProtocols) {
        if (!seen.add(p.id)) twice.add(p.id);
      }
      expect(twice, isEmpty, reason: 'duplicated:\n${twice.join('\n')}');
    });

    test('every protocol has a name and a description', () {
      for (final p in kRehabProtocols) {
        expect(p.name.trim(), isNotEmpty, reason: p.id);
        expect(p.description.trim(), isNotEmpty, reason: p.id);
      }
    });

    test('names are unique, so two cannot be told apart only by id', () {
      final names = [for (final p in kRehabProtocols) p.name.toLowerCase()];
      expect(names.toSet().length, names.length);
    });
  });

  group('doses', () {
    test('an overridden dose is a positive number, never zero', () {
      // A null means "use the exercise's own dose". A zero would mean the
      // patient is told to do it no times.
      for (final p in kRehabProtocols) {
        for (final i in p.items) {
          for (final (label, value) in [
            ('sets', i.sets),
            ('reps', i.reps),
            ('perDay', i.perDay),
          ]) {
            if (value != null) {
              expect(
                value,
                greaterThan(0),
                reason: '${p.id} → ${i.exerciseId} $label is $value',
              );
            }
          }
          if (i.holdSeconds != null) {
            expect(
              i.holdSeconds,
              greaterThan(0),
              reason: '${p.id} → ${i.exerciseId} holdSeconds',
            );
          }
        }
      }
    });

    test('nothing is prescribed more than four times a day', () {
      for (final p in kRehabProtocols) {
        for (final i in p.items) {
          if (i.perDay != null) {
            expect(i.perDay, lessThanOrEqualTo(4), reason: p.id);
          }
        }
      }
    });
  });

  test('the disclaimer still says it is a starting point', () {
    // Shown on screen with every protocol. If this wording ever drifts into
    // sounding like a prescription, that is a problem.
    expect(kProtocolDisclaimer.toLowerCase(), contains('starting point'));
    expect(kProtocolDisclaimer.toLowerCase(), contains('adjust'));
  });
}
