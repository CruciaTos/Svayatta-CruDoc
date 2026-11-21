// The shape of a patient-reported outcome measure, and how its score is
// worked out.
//
// These are validated instruments, which constrains what this code may do
// with them in two ways that matter more than any convenience:
//
//  * The item wording is the instrument. A reworded ODI option does not
//    produce an ODI score, so the text in the scale files is the published
//    wording and is not edited for tone, length or house style.
//  * The scoring rule is the instrument's, not ours. Where a rule says to
//    divide by the sections actually answered, that is what happens, and
//    nothing is extrapolated to fill a section the patient skipped.
//
// Scores are always derived, never stored. A record keeps the answers; the
// figure is computed on the way out, so correcting a scoring rule corrects
// the whole history rather than leaving old records carrying a number
// nothing can reproduce.

/// How a scale produces its figure.
enum ScaleKind {
  /// A set of items the patient answers, each worth a score.
  questionnaire,

  /// One figure measured by the physio — a time, a distance.
  measured,
}

/// One answerable item, e.g. an ODI section.
class ScaleItem {
  const ScaleItem(this.id, this.label, this.options);

  final String id;

  /// The section heading as the instrument prints it.
  final String label;

  /// The answer texts. The index is the score, so order is load-bearing and
  /// options are never re-sorted for display.
  final List<String> options;

  /// The highest score this item can contribute.
  int get maxScore => options.length - 1;
}

/// A named range of the reported figure, e.g. "Severe disability".
///
/// Ranges are contiguous and inclusive, so every possible figure falls in
/// exactly one band and none can report as unclassified.
class ScaleBand {
  const ScaleBand(this.from, this.to, this.label);

  final int from;
  final int to;
  final String label;

  bool contains(num v) => v >= from && v <= to;
}

/// One outcome measure.
class ScaleDef {
  const ScaleDef({
    required this.id,
    required this.name,
    required this.short,
    required this.region,
    required this.kind,
    required this.unit,
    required this.higherIsBetter,
    required this.source,
    this.items = const [],
    this.bands = const [],
    this.mdc,
    this.minAnswered = 0,
    this.usageNote = '',
    this.instruction = '',
  });

  final String id;

  /// The instrument's full name, shown once so the record says what was
  /// actually administered.
  final String name;

  /// What a physio writes in a note: `ODI`, `NDI`, `TUG`.
  final String short;

  /// The body region or purpose it is for, to pick from a list.
  final String region;

  final ScaleKind kind;

  /// What the figure is in: `%`, `s`, `m`.
  final String unit;

  /// Whether a bigger figure is a better result. False for a disability
  /// index, true for a walk distance.
  final bool higherIsBetter;

  /// Who published it, carried onto the report so a reader can check the
  /// instrument rather than taking our word for the score.
  final String source;

  final List<ScaleItem> items;
  final List<ScaleBand> bands;

  /// Minimal detectable change, in the reported unit: the smallest change
  /// that is unlikely to be measurement noise.
  ///
  /// Null where it depends on the population rather than the instrument, in
  /// which case no claim of real change is made at all. A figure invented
  /// for the sake of having one would turn noise into progress.
  final int? mdc;

  /// How many items must be answered before a figure is reported.
  final int minAnswered;

  /// Licence or administration note, shown where the scale is chosen.
  final String usageNote;

  /// How it is administered, for the physio handing it over.
  final String instruction;

  bool get isQuestionnaire => kind == ScaleKind.questionnaire;

  /// The highest raw score obtainable, over every item.
  int get maxRaw {
    var total = 0;
    for (final i in items) {
      total += i.maxScore;
    }
    return total;
  }

  ScaleItem? item(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// The band a figure falls in, or null when the scale has no bands.
  ScaleBand? bandFor(num value) {
    for (final b in bands) {
      if (b.contains(value)) return b;
    }
    return null;
  }
}
