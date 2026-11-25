import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/therapy/data/outcome_scale.dart';

// One completed outcome measure, and what it scores to.
//
// The record keeps answers, never the score. Scoring happens here on the way
// out, so a scoring rule that gets corrected corrects the whole history
// instead of leaving old records carrying a figure nothing can reproduce.
//
// Two refusals run through all of this, because the figure ends up on a
// report that another clinician or an insurer may read:
//
//  * A half-finished questionnaire reports no figure at all. It does not
//    report a figure over the items that happen to be answered and leave the
//    reader to notice the sample was small.
//  * A change smaller than the instrument's minimal detectable change is not
//    called an improvement. Where no MDC is established, no claim is made
//    either way rather than inventing a threshold.

/// A completed measure as stored (record kind `physioScaleScore`).
class OutcomeScore {
  const OutcomeScore({
    required this.scaleId,
    required this.answers,
    required this.value,
    required this.note,
    required this.record,
  });

  factory OutcomeScore.fromRecord(DentalRecord r) {
    final raw = r.data['answers'];
    final v = r.data['value'];
    return OutcomeScore(
      scaleId: r.str('scaleId'),
      answers: {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.value is int) '${e.key}': e.value as int,
      },
      value: v is num ? v.toDouble() : null,
      note: r.str('note'),
      record: r,
    );
  }

  final String scaleId;

  /// Chosen option index per item id. An unanswered item is absent, so a
  /// skipped section can never be confused with a score of zero.
  final Map<String, int> answers;

  /// The measured figure, for a scale that is one number (a time, a
  /// distance). Null for a questionnaire.
  final double? value;

  final String note;
  final DentalRecord record;

  String get id => record.id;
  DateTime get takenAt => record.recordedAt;

  static Map<String, dynamic> toData({
    required String scaleId,
    required Map<String, int> answers,
    required double? value,
    required String note,
  }) => {
    'scaleId': scaleId,
    'answers': {...answers},
    'value': ?value,
    'note': note,
  };

  /// Score this against its scale.
  ///
  /// The scale is passed in rather than looked up, so scoring stays pure and
  /// can be tested without loading any instrument.
  ScaleResult scoreWith(ScaleDef scale) => ScaleResult.of(scale, this);
}

/// What one completed measure comes to.
class ScaleResult {
  const ScaleResult({
    required this.scale,
    required this.score,
    required this.answered,
    required this.raw,
    required this.maxRaw,
    required this.figure,
    required this.takenAt,
  });

  factory ScaleResult.of(ScaleDef scale, OutcomeScore score) {
    if (!scale.isQuestionnaire) {
      return ScaleResult(
        scale: scale,
        score: score,
        answered: score.value == null ? 0 : 1,
        raw: 0,
        maxRaw: 0,
        figure: score.value,
        takenAt: score.takenAt,
      );
    }

    var raw = 0;
    var maxRaw = 0;
    var answered = 0;
    for (final item in scale.items) {
      final chosen = score.answers[item.id];
      if (chosen == null) continue;
      // An index outside the item's options is a record written against a
      // different version of the instrument. It is dropped rather than
      // clamped, because clamping would invent an answer.
      if (chosen < 0 || chosen > item.maxScore) continue;
      raw += chosen;
      maxRaw += item.maxScore;
      answered++;
    }

    // The instrument's own rule: a percentage of what the answered items
    // could have scored, so skipping a section lowers the denominator
    // instead of being read as no disability.
    final double? figure = answered >= scale.minAnswered && maxRaw > 0
        ? raw * 100 / maxRaw
        : null;

    return ScaleResult(
      scale: scale,
      score: score,
      answered: answered,
      raw: raw,
      maxRaw: maxRaw,
      figure: figure,
      takenAt: score.takenAt,
    );
  }

  final ScaleDef scale;
  final OutcomeScore score;

  /// Items answered, or 1 for a measured scale that has its figure.
  final int answered;

  final int raw;

  /// The most the answered items could have scored.
  final int maxRaw;

  /// The reported figure, or null when too little was answered to report
  /// one.
  final double? figure;

  final DateTime takenAt;

  bool get isReportable => figure != null;

  /// How many items are still missing before a figure can be reported.
  int get stillNeeded {
    if (!scale.isQuestionnaire) return figure == null ? 1 : 0;
    final short = scale.minAnswered - answered;
    return short > 0 ? short : 0;
  }

  /// The figure as whole units, which is how every one of these is reported.
  int? get rounded => figure?.round();

  ScaleBand? get band {
    final f = figure;
    return f == null ? null : scale.bandFor(f.round());
  }

  /// The figure with its unit, e.g. `42%`, `13 s`. Null when not reportable,
  /// so a caller cannot print a figure that does not exist.
  String? get display {
    final r = rounded;
    if (r == null) return null;
    return scale.unit == '%' ? '$r%' : '$r ${scale.unit}';
  }

  /// One line for a card or report: the figure, what it means, and — when
  /// sections were skipped — that they were.
  String get line {
    final d = display;
    if (d == null) {
      return scale.isQuestionnaire
          ? 'Incomplete — $answered of ${scale.items.length} answered'
          : 'Not recorded';
    }
    final parts = [
      d,
      if (band != null) band!.label,
      if (scale.isQuestionnaire && answered < scale.items.length)
        'scored over $answered of ${scale.items.length}',
    ];
    return parts.join(' · ');
  }
}

/// The difference between two takings of the same scale.
class ScaleChange {
  const ScaleChange({
    required this.first,
    required this.latest,
    required this.delta,
  });

  final ScaleResult first;
  final ScaleResult latest;

  /// Latest minus first, in reported units. Negative where the figure went
  /// down, whether or not that is an improvement.
  final double delta;

  ScaleDef get scale => latest.scale;

  /// Whole days between the two takings.
  int get days =>
      DateTime(latest.takenAt.year, latest.takenAt.month, latest.takenAt.day)
          .difference(
            DateTime(
              first.takenAt.year,
              first.takenAt.month,
              first.takenAt.day,
            ),
          )
          .inDays;

  int get weeks => (days / 7).round();

  int get size => delta.abs().round();

  /// Whether the figure moved in the direction that is better for this
  /// scale. A disability index going down is better; a walk distance going
  /// up is better.
  bool get improved => scale.higherIsBetter ? delta > 0 : delta < 0;

  /// Whether the change is big enough to be more than measurement noise.
  ///
  /// False when the scale has no established MDC — not because the change is
  /// small, but because there is nothing to judge it against. Read it with
  /// [mdcKnown].
  bool get beyondMdc {
    final m = scale.mdc;
    return m != null && size >= m;
  }

  bool get mdcKnown => scale.mdc != null;

  /// The sentence for a report. Says what moved, over how long, and whether
  /// that exceeds the instrument's own noise floor — and stays silent on
  /// significance when the instrument has no MDC.
  String get reportLine {
    final from = first.display;
    final to = latest.display;
    if (from == null || to == null) return '';
    if (size == 0) {
      return '${scale.short} unchanged at $to over $weeks '
          'week${weeks == 1 ? '' : 's'}';
    }
    final direction = delta > 0 ? 'up' : 'down';
    final unit = scale.unit == '%' ? 'points' : scale.unit;
    final tail = !mdcKnown
        ? ''
        : (beyondMdc
              ? ', beyond the ${scale.mdc} $unit minimal detectable change'
              : ', within the ${scale.mdc} $unit measurement error');
    return '${scale.short} $direction $size $unit over $weeks '
        'week${weeks == 1 ? '' : 's'}, from $from to $to$tail';
  }
}

/// A patient's takings of one scale, oldest first, scored.
///
/// Oldest first because this is a trend: the first taking is the baseline
/// everything else is read against.
List<ScaleResult> scaleTrend(ScaleDef scale, Iterable<DentalRecord> recs) {
  final results = <ScaleResult>[];
  for (final r in recs) {
    final score = OutcomeScore.fromRecord(r);
    if (score.scaleId != scale.id) continue;
    results.add(score.scoreWith(scale));
  }
  results.sort((a, b) => a.takenAt.compareTo(b.takenAt));
  return results;
}

/// The change from the first reportable taking to the latest, or null when
/// there is not yet a pair to compare.
///
/// Unreportable takings are skipped rather than counted: two half-finished
/// questionnaires are not a trend.
ScaleChange? scaleChange(List<ScaleResult> trend) {
  final usable = [
    for (final r in trend)
      if (r.isReportable) r,
  ];
  if (usable.length < 2) return null;
  final first = usable.first;
  final latest = usable.last;
  return ScaleChange(
    first: first,
    latest: latest,
    delta: latest.figure! - first.figure!,
  );
}

/// The latest reportable taking of a scale, or null when there is none.
ScaleResult? latestResult(List<ScaleResult> trend) {
  for (final r in trend.reversed) {
    if (r.isReportable) return r;
  }
  return null;
}
