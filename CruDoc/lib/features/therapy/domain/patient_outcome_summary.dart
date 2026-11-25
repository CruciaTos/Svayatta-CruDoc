import 'package:doctor_management_app/features/therapy/domain/outcome_score_models.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_assess_models.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_extras_models.dart';

// What a patient is told about their own progress.
//
// This is the one document in the app written for the patient rather than
// for a clinician or an insurer, and it is the easiest one to turn into a
// lie. "You improved 42%" is a marketing line that happens to be made of
// clinical data, and the temptations are specific:
//
//  * saying something when there is nothing to say,
//  * reporting the flattering measure and dropping the rest,
//  * calling measurement noise an improvement,
//  * showing a percentage of a baseline that was already zero.
//
// So the rule here is that the summary reports every measure it has or none
// of them, and refuses to exist at all when nothing can be stated honestly.
// A patient who has not improved gets a page that says so, or gets no page.
// It is better to hand over nothing than something they will quote back.

/// One thing the summary can say, already worded for the patient.
class OutcomeLine {
  const OutcomeLine(this.heading, this.detail, {required this.good});

  /// The short figure, e.g. `Pain down 57%`.
  final String heading;

  /// The plain-language sentence under it.
  final String detail;

  /// Whether this measure moved the patient's way. Drives nothing but
  /// presentation, and is never used to decide what to leave out.
  final bool good;
}

/// Everything the summary will say about one patient.
class PatientOutcomeSummary {
  const PatientOutcomeSummary({
    required this.lines,
    required this.weeks,
    required this.sessions,
    required this.goalsReached,
    required this.goalsTotal,
  });

  final List<OutcomeLine> lines;

  /// How long the patient has been coming, in whole weeks.
  final int weeks;

  /// Sessions attended, when that is known.
  final int sessions;

  final int goalsReached;
  final int goalsTotal;

  bool get isEmpty => lines.isEmpty;

  /// Whether anything at all moved the patient's way.
  ///
  /// Used to decide the wording of the closing line, never to decide whether
  /// to show a measure.
  bool get anyGood => lines.any((l) => l.good);

  /// Whether every measure moved against the patient.
  bool get allBad => lines.isNotEmpty && lines.every((l) => !l.good);
}

/// Builds the summary, or returns null when there is nothing honest to say.
///
/// Null rather than an empty page, so the caller has to tell the physio why
/// no summary was produced instead of handing the patient a sheet with a
/// clinic logo and no content.
PatientOutcomeSummary? patientOutcomeSummary({
  required List<ProgressEntry> progress,
  required List<PhysioGoal> goals,
  required List<List<ScaleResult>> scaleTrends,
  int sessions = 0,
}) {
  final lines = <OutcomeLine>[];

  // Pain. Already refuses to answer when there is one reading, or when the
  // patient started at zero.
  final pain = painChange(progress);
  if (pain != null) {
    final dir = pain.improved ? 'down' : (pain.worse ? 'up' : 'unchanged');
    lines.add(
      OutcomeLine(
        pain.percent == 0
            ? 'Pain unchanged'
            : 'Pain $dir ${pain.percent.abs()}%',
        pain.percent == 0
            ? 'Your pain score has stayed at ${pain.to} out of 10.'
            : 'Your pain score went from ${pain.from} to ${pain.to} out of '
                  '10.',
        good: pain.improved,
      ),
    );
  }

  // Function, where it was scored more than once. Reported as the raw
  // figures rather than a percentage: the function score is a 0 to 10
  // judgement, and a percentage of it reads more precise than it is.
  if (progress.length >= 2) {
    final from = progress.first.function;
    final to = progress.last.function;
    if (from != to) {
      lines.add(
        OutcomeLine(
          'Daily activities ${to > from ? 'easier' : 'harder'}',
          'Your own score for getting through the day went from $from to '
              '$to out of 10.',
          good: to > from,
        ),
      );
    }
  }

  // Scored questionnaires, but only where the instrument itself says the
  // change is bigger than its own measurement error. A patient must not be
  // told they improved on the strength of noise.
  for (final trend in scaleTrends) {
    final change = scaleChange(trend);
    if (change == null || change.size == 0) continue;
    if (change.mdcKnown && !change.beyondMdc) continue;
    final scale = change.scale;
    lines.add(
      OutcomeLine(
        '${scale.short} ${change.improved ? 'better' : 'worse'} '
            'by ${change.size}${scale.unit == '%' ? ' points' : ' ${scale.unit}'}',
        'Your ${scale.name} score went from ${change.first.display} to '
            '${change.latest.display}.',
        good: change.improved,
      ),
    );
  }

  if (lines.isEmpty) return null;

  // How long, measured across whatever was actually recorded.
  final dates = <DateTime>[
    for (final p in progress) p.date,
    for (final t in scaleTrends)
      for (final r in t) r.takenAt,
  ]..sort();
  final days = dates.length < 2 ? 0 : dates.last.difference(dates.first).inDays;

  final reached = [
    for (final g in goals)
      if (g.status == GoalStatus.reached) g,
  ].length;
  final settled = [
    for (final g in goals)
      if (g.status != GoalStatus.open) g,
  ].length;

  return PatientOutcomeSummary(
    lines: lines,
    weeks: days < 7 ? (days > 0 ? 1 : 0) : (days / 7).round(),
    sessions: sessions,
    goalsReached: reached,
    goalsTotal: settled,
  );
}

/// The headline, worded for the patient.
///
/// Leads with the measure that moved most in the patient's favour when
/// anything did, and says so plainly when nothing has. It never leads with a
/// good measure while a bad one is also on the page — both are shown either
/// way, this only decides which sentence sits at the top.
String outcomeHeadline(PatientOutcomeSummary s) {
  final span = s.weeks == 0
      ? 'so far'
      : 'in ${s.weeks} week${s.weeks == 1 ? '' : 's'}';
  if (s.allBad) {
    return 'Where things stand $span';
  }
  final good = [
    for (final l in s.lines)
      if (l.good) l,
  ];
  if (good.isEmpty) return 'Where things stand $span';
  return '${good.first.heading} $span';
}

/// The closing line: what the patient should do next.
///
/// Deliberately not a congratulation. A patient who has improved is being
/// told to keep going, because stopping is what undoes it, and a patient who
/// has not is being told the plan will be looked at rather than being
/// consoled.
String outcomeClosingLine(PatientOutcomeSummary s) {
  if (s.allBad) {
    return 'These are your own recorded scores. Your physiotherapist will '
        'go through them with you and change the plan where it needs '
        'changing.';
  }
  if (s.anyGood) {
    return 'Keep going with your home exercises — most of this is undone by '
        'stopping early. Bring this with you to your next visit.';
  }
  return 'Bring this with you to your next visit.';
}
