import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/therapy/data/special_tests.dart';

/// The file's own promise is that these tests "only ever may suggest
/// something and always need clinical correlation; nothing here is a
/// diagnosis". That promise is the thing worth enforcing: a special test
/// result gets written into a patient's record and read later by somebody
/// who was not in the room, and a confidently worded interpretation is how
/// a screening test turns into a diagnosis nobody made.
void main() {
  group('nothing here diagnoses', () {
    test('every interpretation is hedged, not asserted', () {
      for (final t in kSpecialTests) {
        expect(
          t.suggests.toLowerCase(),
          contains('may suggest'),
          reason: '${t.id} states its interpretation outright',
        );
      }
    });

    test('every interpretation asks for clinical correlation', () {
      for (final t in kSpecialTests) {
        expect(
          t.suggests.toLowerCase(),
          contains('needs clinical correlation'),
          reason: '${t.id} does not ask for clinical correlation',
        );
      }
    });

    test('no interpretation claims certainty', () {
      // Words that would turn a screening test into a conclusion.
      const forbidden = [
        'confirms',
        'diagnoses',
        'diagnostic of',
        'proves',
        'rules out',
        'definitely',
        'indicates a diagnosis',
      ];
      for (final t in kSpecialTests) {
        final text = t.suggests.toLowerCase();
        for (final word in forbidden) {
          expect(text, isNot(contains(word)), reason: '${t.id} says "$word"');
        }
      }
    });
  });

  group('every test can actually be performed', () {
    test('each has a name, what it assesses, steps and a positive', () {
      for (final t in kSpecialTests) {
        expect(t.name.trim(), isNotEmpty, reason: t.id);
        expect(t.assesses.trim(), isNotEmpty, reason: t.id);
        expect(t.steps, isNotEmpty, reason: t.id);
        expect(t.positive.trim(), isNotEmpty, reason: t.id);
        expect(t.suggests.trim(), isNotEmpty, reason: t.id);
      }
    });

    test('no step is blank or padded', () {
      for (final t in kSpecialTests) {
        for (final s in t.steps) {
          expect(s.trim(), isNotEmpty, reason: t.id);
          expect(s.trim(), s, reason: 'padded step in ${t.id}');
        }
      }
    });

    test('a test has enough steps to be followed', () {
      // One line is a description, not a procedure.
      for (final t in kSpecialTests) {
        expect(t.steps.length, greaterThanOrEqualTo(3), reason: t.id);
      }
    });
  });

  group('identity', () {
    test('ids are unique', () {
      final seen = <String>{};
      final twice = <String>[];
      for (final t in kSpecialTests) {
        if (!seen.add(t.id)) twice.add(t.id);
      }
      expect(twice, isEmpty, reason: 'duplicated:\n${twice.join('\n')}');
    });

    test('names are unique', () {
      final names = [for (final t in kSpecialTests) t.name.toLowerCase()];
      expect(names.toSet().length, names.length);
    });

    test('lookup finds every test and nothing else', () {
      for (final t in kSpecialTests) {
        expect(specialTestById(t.id)?.id, t.id);
      }
      expect(specialTestById('not-a-test'), isNull);
    });

    test('every region has tests, so no region opens empty', () {
      for (final r in TestRegion.values) {
        expect(
          kSpecialTests.where((t) => t.region == r),
          isNotEmpty,
          reason: r.label,
        );
      }
    });
  });
}
