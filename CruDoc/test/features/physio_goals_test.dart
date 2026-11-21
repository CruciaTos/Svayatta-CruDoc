import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_extras_models.dart';

/// Goals drive two things the clinic cannot get wrong: which goal the card
/// asks the physio to review, and the line about goals that goes out on a
/// discharge summary the patient keeps.
void main() {
  final now = DateTime(2026, 11, 21);

  DentalRecord rec({
    required String text,
    DateTime? target,
    GoalStatus status = GoalStatus.open,
    String note = '',
    DateTime? setOn,
  }) => DentalRecord.create(
    'p1',
    RecKind.physioGoal,
    PhysioGoal.toData(text: text, target: target, status: status, note: note),
    at: setOn ?? now,
  );

  PhysioGoal goal({
    required String text,
    DateTime? target,
    GoalStatus status = GoalStatus.open,
    DateTime? setOn,
  }) => PhysioGoal.fromRecord(
    rec(text: text, target: target, status: status, setOn: setOn),
  );

  group('round trip', () {
    test('a goal survives being written and read back', () {
      final g = PhysioGoal.fromRecord(
        rec(
          text: 'Climb the stairs at home without the rail',
          target: DateTime(2026, 12, 10),
          status: GoalStatus.reached,
          note: 'Managed it twice this week',
        ),
      );
      expect(g.text, 'Climb the stairs at home without the rail');
      expect(g.target, DateTime(2026, 12, 10));
      expect(g.status, GoalStatus.reached);
      expect(g.note, 'Managed it twice this week');
      expect(g.isOpen, isFalse);
    });

    test('a goal with no target date keeps none', () {
      final g = PhysioGoal.fromRecord(rec(text: 'Walk the dog again'));
      expect(g.target, isNull);
      expect(g.daysLeft(now), isNull);
      expect(g.overdue(now), isFalse);
    });

    test('an unknown status reads as open rather than throwing', () {
      final g = PhysioGoal.fromRecord(
        DentalRecord.create('p1', RecKind.physioGoal, {
          'text': 'Lift the grandchild',
          'status': 'abandoned',
          'note': '',
        }, at: now),
      );
      expect(g.status, GoalStatus.open);
    });
  });

  group('overdue', () {
    test('a date gone by on an open goal is overdue', () {
      expect(
        goal(text: 'a', target: DateTime(2026, 11, 20)).overdue(now),
        isTrue,
      );
    });

    test('the target day itself is not yet late', () {
      final g = goal(text: 'a', target: DateTime(2026, 11, 21, 23, 30));
      expect(g.overdue(now), isFalse);
      expect(g.daysLeft(now), 0);
    });

    test('a settled goal never asks to be reviewed again', () {
      for (final s in [GoalStatus.reached, GoalStatus.missed]) {
        expect(
          goal(
            text: 'a',
            target: DateTime(2026, 10, 1),
            status: s,
          ).overdue(now),
          isFalse,
          reason: '${s.name} is already decided',
        );
      }
    });

    test('daysLeft counts whole days either side of today', () {
      expect(goal(text: 'a', target: DateTime(2026, 11, 28)).daysLeft(now), 7);
      expect(goal(text: 'a', target: DateTime(2026, 11, 14)).daysLeft(now), -7);
    });
  });

  group('physioGoals ordering', () {
    test('open goals lead, soonest target first, dateless ones last', () {
      final list = physioGoals([
        rec(text: 'reached', status: GoalStatus.reached),
        rec(text: 'no date'),
        rec(text: 'later', target: DateTime(2026, 12, 20)),
        rec(text: 'sooner', target: DateTime(2026, 11, 25)),
      ]);
      expect(
        [for (final g in list) g.text],
        ['sooner', 'later', 'no date', 'reached'],
      );
    });

    test('settled goals come newest first', () {
      final list = physioGoals([
        rec(
          text: 'older',
          status: GoalStatus.missed,
          setOn: DateTime(2026, 9, 1),
        ),
        rec(
          text: 'newer',
          status: GoalStatus.reached,
          setOn: DateTime(2026, 10, 1),
        ),
      ]);
      expect([for (final g in list) g.text], ['newer', 'older']);
    });
  });

  group('goalsDueForReview', () {
    test('picks out only the open goals whose date has passed', () {
      final goals = physioGoals([
        rec(text: 'late', target: DateTime(2026, 11, 1)),
        rec(text: 'due soon', target: DateTime(2026, 12, 1)),
        rec(text: 'no date'),
        rec(
          text: 'late but reached',
          target: DateTime(2026, 11, 1),
          status: GoalStatus.reached,
        ),
      ]);
      expect([for (final g in goalsDueForReview(goals, now)) g.text], ['late']);
    });
  });

  group('goalOutcomeLine', () {
    test('counts what was reached and what was not', () {
      final goals = physioGoals([
        rec(text: 'a', status: GoalStatus.reached),
        rec(text: 'b', status: GoalStatus.reached),
        rec(text: 'c', status: GoalStatus.missed),
        rec(text: 'd'),
      ]);
      expect(goalOutcomeLine(goals), 'Goals: 2 reached, 1 not reached');
    });

    test('says nothing when nobody settled a goal', () {
      final goals = physioGoals([
        rec(text: 'a'),
        rec(text: 'b', target: DateTime(2026, 10, 1)),
      ]);
      expect(goalOutcomeLine(goals), isNull);
    });

    test('says nothing at all when there are no goals', () {
      expect(goalOutcomeLine(const []), isNull);
    });

    test('names only the side that happened', () {
      String? lineFor(GoalStatus s) =>
          goalOutcomeLine(physioGoals([rec(text: 'a', status: s)]));
      expect(lineFor(GoalStatus.reached), 'Goals: 1 reached');
      expect(lineFor(GoalStatus.missed), 'Goals: 1 not reached');
    });
  });
}
