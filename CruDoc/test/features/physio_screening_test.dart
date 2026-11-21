import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/therapy/data/physio_flags.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_extras_models.dart';

/// A red flag means "send this patient to a doctor". If it is recorded and
/// then fails to show, the screening has done harm rather than nothing, so
/// the rules that decide whether a flag is raised are pinned here — including
/// the difference between a flag that was asked about and one that was not.
void main() {
  PhysioScreening screening(
    Map<String, FlagAnswer> answers, {
    String note = '',
  }) => PhysioScreening.fromRecord(
    DentalRecord.create(
      'p1',
      RecKind.physioScreening,
      PhysioScreening.toData(answers: answers, note: note),
    ),
  );

  group('the flag list itself', () {
    test('has both kinds', () {
      expect(physioFlagsOf(FlagKind.red), isNotEmpty);
      expect(physioFlagsOf(FlagKind.yellow), isNotEmpty);
    });

    test('every id is unique, since a saved screening stores it', () {
      final ids = [for (final f in kPhysioFlags) f.id];
      expect(ids.toSet().length, ids.length);
    });

    test('every flag has a label to ask with', () {
      for (final f in kPhysioFlags) {
        expect(f.label.trim(), isNotEmpty, reason: f.id);
      }
    });

    test('lookup by id finds them, and misses are null', () {
      expect(physioFlagById('bladder-bowel')?.kind, FlagKind.red);
      expect(physioFlagById('no-such-flag'), isNull);
    });
  });

  group('raising a flag', () {
    test('a present red flag raises the banner', () {
      final s = screening({'bladder-bowel': FlagAnswer.present});
      expect(s.hasRed, isTrue);
      expect(s.presentOf(FlagKind.red).single.id, 'bladder-bowel');
    });

    test('a screened-and-absent red flag raises nothing', () {
      final s = screening({'bladder-bowel': FlagAnswer.absent});
      expect(s.hasRed, isFalse);
      expect(s.presentOf(FlagKind.red), isEmpty);
    });

    test('yellow flags do not raise the red banner', () {
      final s = screening({'fear-avoidance': FlagAnswer.present});
      expect(s.hasRed, isFalse);
      expect(s.hasYellow, isTrue);
    });

    test('present flags come back in list order, every time', () {
      final s = screening({
        'trauma': FlagAnswer.present,
        'bladder-bowel': FlagAnswer.present,
      });
      final ids = [for (final f in s.presentOf(FlagKind.red)) f.id];
      final expected = [
        for (final f in physioFlagsOf(FlagKind.red))
          if (ids.contains(f.id)) f.id,
      ];
      expect(ids, expected);
    });
  });

  group('not asked is not the same as absent', () {
    test('an empty screening has asked nothing and raises nothing', () {
      final s = screening(const {});
      expect(s.started, isFalse);
      expect(s.asked, 0);
      expect(s.unanswered, kPhysioFlags.length);
      expect(s.hasRed, isFalse);
    });

    test('a flag never asked about reads as notAsked', () {
      final s = screening({'trauma': FlagAnswer.absent});
      expect(s.answerFor('bladder-bowel'), FlagAnswer.notAsked);
      expect(s.answerFor('trauma'), FlagAnswer.absent);
    });

    test('asking counts, whichever way the answer went', () {
      final s = screening({
        'trauma': FlagAnswer.absent,
        'bladder-bowel': FlagAnswer.present,
      });
      expect(s.asked, 2);
      expect(s.unanswered, kPhysioFlags.length - 2);
    });

    test('notAsked is not written to the record, so it stays small', () {
      final data = PhysioScreening.toData(
        answers: {
          'trauma': FlagAnswer.notAsked,
          'bladder-bowel': FlagAnswer.present,
        },
        note: '',
      );
      expect((data['flags'] as Map).keys, ['bladder-bowel']);
    });

    test('an id dropped from the list is ignored, not raised', () {
      // Removing a flag leaves its answer behind in records already saved.
      // It must not raise a banner for a question the clinic no longer asks,
      // and it must not count towards the current list either.
      final s = screening({'a-flag-we-removed': FlagAnswer.present});
      expect(s.hasRed, isFalse);
      expect(s.presentOf(FlagKind.red), isEmpty);
      expect(s.asked, 0);
      expect(s.unanswered, kPhysioFlags.length);
    });
  });

  group('screeningOf', () {
    test('takes the newest record', () {
      final old = DentalRecord.create(
        'p1',
        RecKind.physioScreening,
        PhysioScreening.toData(
          answers: {'trauma': FlagAnswer.present},
          note: 'old',
        ),
        at: DateTime(2026, 1, 1),
      );
      final recent = DentalRecord.create(
        'p1',
        RecKind.physioScreening,
        PhysioScreening.toData(answers: const {}, note: 'recent'),
        at: DateTime(2026, 6, 1),
      );
      expect(screeningOf([old, recent]).note, 'recent');
    });

    test('no records gives an empty screening, not a crash', () {
      final s = screeningOf(const []);
      expect(s.started, isFalse);
      expect(s.record, isNull);
      expect(s.at, isNull);
    });
  });
}
