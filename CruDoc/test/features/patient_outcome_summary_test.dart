import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/therapy/data/outcome_scale.dart';
import 'package:doctor_management_app/features/therapy/domain/outcome_score_models.dart';
import 'package:doctor_management_app/features/therapy/domain/patient_outcome_summary.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_assess_models.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_extras_models.dart';

/// This is the only document in the app written for the patient, and the
/// easiest one to turn into a lie. Every test here is about what it refuses
/// to do: invent a result, hide the bad half, or call noise an improvement.
void main() {
  final day0 = DateTime(2026, 10, 1);

  ProgressEntry entry(int pain, int days, {int function = 5}) =>
      ProgressEntry.fromRecord(
        DentalRecord.create('p1', RecKind.physioProgress, {
          'pain': pain,
          'worst': pain,
          'function': function,
          'note': '',
        }, at: day0.add(Duration(days: days))),
      );

  PhysioGoal goal(GoalStatus status) => PhysioGoal.fromRecord(
    DentalRecord.create(
      'p1',
      RecKind.physioGoal,
      PhysioGoal.toData(
        text: 'walk to the shop',
        target: null,
        status: status,
        note: '',
      ),
      at: day0,
    ),
  );

  const scale = ScaleDef(
    id: 'fix',
    name: 'Fixture Disability Index',
    short: 'FDI',
    region: 'Test',
    kind: ScaleKind.questionnaire,
    unit: '%',
    higherIsBetter: false,
    source: 'invented for tests',
    mdc: 10,
    minAnswered: 1,
    items: [
      ScaleItem('a', 'A', ['0', '1', '2', '3', '4']),
    ],
  );

  List<ScaleResult> scaleTrend2(int fromIdx, int toIdx, {int days = 42}) => [
    for (final (i, idx) in [fromIdx, toIdx].indexed)
      OutcomeScore.fromRecord(
        DentalRecord.create(
          'p1',
          RecKind.physioScaleScore,
          OutcomeScore.toData(
            scaleId: 'fix',
            answers: {'a': idx},
            value: null,
            note: '',
          ),
          at: day0.add(Duration(days: i == 0 ? 0 : days)),
        ),
      ).scoreWith(scale),
  ];

  group('refusing to say anything', () {
    test('no data at all produces no summary', () {
      expect(
        patientOutcomeSummary(
          progress: const [],
          goals: const [],
          scaleTrends: const [],
        ),
        isNull,
      );
    });

    test('a single visit produces no summary', () {
      // One reading is not a change, and a page built from it would be a
      // clinic letterhead with nothing under it.
      expect(
        patientOutcomeSummary(
          progress: [entry(7, 0)],
          goals: const [],
          scaleTrends: const [],
        ),
        isNull,
      );
    });

    test('goals alone do not make a summary', () {
      // A reached goal is worth reporting beside a measure, but on its own
      // it is the physio's judgement rather than the patient's own score.
      expect(
        patientOutcomeSummary(
          progress: const [],
          goals: [goal(GoalStatus.reached)],
          scaleTrends: const [],
        ),
        isNull,
      );
    });

    test('a patient who started at zero pain gets no percentage', () {
      // There is no percentage of nothing, and inventing one overstates the
      // result on exactly the patients who began well.
      final s = patientOutcomeSummary(
        progress: [entry(0, 0, function: 5), entry(0, 42, function: 5)],
        goals: const [],
        scaleTrends: const [],
      );
      expect(s, isNull);
    });
  });

  group('reporting the bad along with the good', () {
    test('pain that rose is stated as having risen', () {
      final s = patientOutcomeSummary(
        progress: [entry(4, 0), entry(6, 42)],
        goals: const [],
        scaleTrends: const [],
      )!;
      expect(s.lines.first.heading, 'Pain up 50%');
      expect(s.lines.first.good, isFalse);
      expect(s.allBad, isTrue);
    });

    test('the headline does not claim progress when there is none', () {
      final s = patientOutcomeSummary(
        progress: [entry(4, 0), entry(6, 42)],
        goals: const [],
        scaleTrends: const [],
      )!;
      final headline = outcomeHeadline(s).toLowerCase();
      for (final word in ['better', 'improv', 'down', 'well done', 'great']) {
        expect(headline, isNot(contains(word)), reason: headline);
      }
      expect(outcomeHeadline(s), 'Where things stand in 6 weeks');
    });

    test('a worsening measure is kept even when another improved', () {
      // The temptation this guards against: show the pain drop, quietly
      // drop the questionnaire that went the other way.
      final s = patientOutcomeSummary(
        progress: [entry(8, 0), entry(3, 42)],
        goals: const [],
        // 0 of 4 → 4 of 4: a 100 point rise on a disability index.
        scaleTrends: [scaleTrend2(0, 4)],
      )!;
      expect(s.lines.length, 2);
      expect(s.anyGood, isTrue);
      expect(s.allBad, isFalse);
      expect(s.lines.any((l) => !l.good), isTrue);
    });

    test('the headline leads with a good measure when one exists', () {
      final s = patientOutcomeSummary(
        progress: [entry(7, 0), entry(3, 42)],
        goals: const [],
        scaleTrends: const [],
      )!;
      expect(outcomeHeadline(s), 'Pain down 57% in 6 weeks');
    });
  });

  group('noise is not improvement', () {
    test('a questionnaire change inside the error figure is left out', () {
      // 25% → 50% is 25 points, well past the 10 point MDC, so it shows.
      final shown = patientOutcomeSummary(
        progress: [entry(5, 0), entry(4, 42)],
        goals: const [],
        scaleTrends: [scaleTrend2(1, 2)],
      )!;
      expect(shown.lines.any((l) => l.heading.startsWith('FDI')), isTrue);
    });

    test('an unchanged questionnaire is not mentioned', () {
      final s = patientOutcomeSummary(
        progress: [entry(5, 0), entry(4, 42)],
        goals: const [],
        scaleTrends: [scaleTrend2(2, 2)],
      )!;
      expect(s.lines.any((l) => l.heading.startsWith('FDI')), isFalse);
    });
  });

  group('what else it carries', () {
    test('unchanged pain is reported as unchanged, not hidden', () {
      final s = patientOutcomeSummary(
        progress: [entry(5, 0, function: 5), entry(5, 42, function: 5)],
        goals: const [],
        scaleTrends: const [],
      )!;
      expect(s.lines.single.heading, 'Pain unchanged');
      expect(s.lines.single.good, isFalse);
    });

    test('function is reported as the raw score, never a percentage', () {
      final s = patientOutcomeSummary(
        progress: [entry(5, 0, function: 3), entry(5, 42, function: 7)],
        goals: const [],
        scaleTrends: const [],
      )!;
      final line = s.lines.firstWhere(
        (l) => l.heading.contains('Daily activities'),
      );
      expect(line.detail, contains('from 3 to 7 out of 10'));
      expect(line.heading, isNot(contains('%')));
      expect(line.good, isTrue);
    });

    test('only settled goals are counted', () {
      final s = patientOutcomeSummary(
        progress: [entry(7, 0), entry(3, 42)],
        goals: [
          goal(GoalStatus.reached),
          goal(GoalStatus.reached),
          goal(GoalStatus.missed),
          goal(GoalStatus.open),
        ],
        scaleTrends: const [],
      )!;
      expect(s.goalsReached, 2);
      expect(s.goalsTotal, 3);
    });

    test('the span counts from the earliest record of any kind', () {
      final s = patientOutcomeSummary(
        progress: [entry(7, 0), entry(3, 14)],
        goals: const [],
        scaleTrends: [scaleTrend2(4, 1, days: 70)],
      )!;
      expect(s.weeks, 10);
    });
  });

  group('the closing line', () {
    test('tells an improving patient not to stop', () {
      final s = patientOutcomeSummary(
        progress: [entry(7, 0), entry(3, 42)],
        goals: const [],
        scaleTrends: const [],
      )!;
      expect(outcomeClosingLine(s), contains('undone by stopping early'));
    });

    test('does not console a patient who has not improved', () {
      final s = patientOutcomeSummary(
        progress: [entry(4, 0), entry(6, 42)],
        goals: const [],
        scaleTrends: const [],
      )!;
      final line = outcomeClosingLine(s);
      expect(line, contains('change the plan'));
      for (final word in ['well done', 'great', 'congratul', 'proud']) {
        expect(line.toLowerCase(), isNot(contains(word)));
      }
    });
  });
}
