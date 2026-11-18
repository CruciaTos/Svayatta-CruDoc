import 'package:doctor_management_app/features/homeopathy/data/repertory/repertory_registry.dart';
import 'package:doctor_management_app/features/homeopathy/data/repertory/rubric.dart';

/// A rubric the physician picked for the case, with its importance.
class SelectedRubric {
  const SelectedRubric(this.id, {this.weight = 1});

  final String id;

  /// 1 normal, 2 important, 3 characteristic.
  final int weight;

  SelectedRubric withWeight(int w) => SelectedRubric(id, weight: w);

  Map<String, dynamic> toJson() => {'id': id, 'weight': weight};

  static SelectedRubric? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    if (id is! String || id.isEmpty) return null;
    final w = (j['weight'] as num?)?.toInt() ?? 1;
    return SelectedRubric(id, weight: w.clamp(1, 3));
  }
}

/// How one remedy fared over the selected rubrics.
class RemedyScore {
  const RemedyScore({
    required this.abbr,
    required this.score,
    required this.covered,
    required this.grades,
  });

  final String abbr;

  /// Sum of grade x weight over the covered rubrics.
  final int score;

  /// Number of selected rubrics the remedy appears in.
  final int covered;

  /// Rubric id to the plain grade (1..3), for the grid cells.
  final Map<String, int> grades;
}

/// The grid: rubrics (rows) and the top remedies (columns).
class RepertorizationResult {
  const RepertorizationResult({required this.rubrics, required this.remedies});

  final List<Rubric> rubrics;
  final List<RemedyScore> remedies;

  /// Selected rubrics that none of the top 3 remedies cover (information
  /// only: it shows what a leading remedy does not explain).
  List<Rubric> get notCoveredByTop3 {
    final top = remedies.take(3).toList();
    if (top.isEmpty) return const [];
    return [
      for (final r in rubrics)
        if (top.every((t) => !t.grades.containsKey(r.id))) r,
    ];
  }
}

/// Scores the [selected] rubrics (pure function, no UI).
///
/// Per remedy: score = sum(grade x weight), covered = number of rubrics it
/// appears in. Remedies are ranked by covered, then score (Kent-style sum of
/// grades), then name; the top [top] are returned. Ids that are not in the
/// repertory are ignored.
RepertorizationResult repertorize(
  List<SelectedRubric> selected, {
  int top = 12,
  Repertory? repertory,
}) {
  final rep = repertory ?? Repertory.instance;
  final rubrics = <Rubric>[];
  final weights = <String, int>{};
  for (final s in selected) {
    final r = rep.byId(s.id);
    if (r == null || weights.containsKey(r.id)) continue;
    rubrics.add(r);
    weights[r.id] = s.weight.clamp(1, 3);
  }

  final score = <String, int>{};
  final grades = <String, Map<String, int>>{};
  for (final r in rubrics) {
    final w = weights[r.id]!;
    for (final e in r.remedies.entries) {
      score[e.key] = (score[e.key] ?? 0) + e.value * w;
      (grades[e.key] ??= {})[r.id] = e.value;
    }
  }

  final all = [
    for (final e in score.entries)
      RemedyScore(
        abbr: e.key,
        score: e.value,
        covered: grades[e.key]!.length,
        grades: Map.unmodifiable(grades[e.key]!),
      ),
  ]..sort(_rank);

  return RepertorizationResult(
    rubrics: rubrics,
    remedies: all.take(top).toList(),
  );
}

int _rank(RemedyScore a, RemedyScore b) {
  final c = b.covered.compareTo(a.covered);
  if (c != 0) return c;
  final s = b.score.compareTo(a.score);
  if (s != 0) return s;
  return a.abbr.compareTo(b.abbr);
}
