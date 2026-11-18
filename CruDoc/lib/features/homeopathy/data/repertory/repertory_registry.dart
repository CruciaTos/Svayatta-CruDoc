import 'package:doctor_management_app/features/homeopathy/data/homeopathy_remedies.dart';
import 'package:doctor_management_app/features/homeopathy/data/repertory/repertory_part_generals.dart';
import 'package:doctor_management_app/features/homeopathy/data/repertory/repertory_part_mind.dart';
import 'package:doctor_management_app/features/homeopathy/data/repertory/repertory_part_particulars.dart';
import 'package:doctor_management_app/features/homeopathy/data/repertory/rubric.dart';

/// Every bundled repertory data file. To add rubrics, create a new data file
/// holding a `const List<Rubric>` (copy the header comment of
/// `repertory_part_mind.dart`) and add ONE line here. Nothing else changes.
const List<List<Rubric>> allRepertoryParts = [
  kRepertoryMind,
  kRepertoryGenerals,
  kRepertoryParticulars,
];

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// All rubrics merged from [allRepertoryParts] and indexed by id.
///
/// Remedy abbreviations are matched to the app's own list
/// (`homeopathyRemedies`) ignoring case and full stops, and rewritten to the
/// app's spelling. An unknown abbreviation, an out-of-range grade or a
/// repeated id is dropped, with an assert in debug builds.
class Repertory {
  Repertory._(this.rubrics, this._byId, this.chapters);

  final List<Rubric> rubrics;
  final Map<String, Rubric> _byId;

  /// Chapter names in the order they first appear.
  final List<String> chapters;

  Rubric? byId(String id) => _byId[id];

  static Repertory? _instance;

  static Repertory get instance =>
      _instance ??= Repertory.build(allRepertoryParts);

  /// Builds an index from [parts]. Public so a data file can be checked on
  /// its own.
  factory Repertory.build(List<List<Rubric>> parts) {
    final abbr = <String, String>{
      for (final r in homeopathyRemedies) _norm(r.abbr): r.abbr,
    };
    final byId = <String, Rubric>{};
    final out = <Rubric>[];
    final chapters = <String>[];
    for (final part in parts) {
      for (final r in part) {
        if (byId.containsKey(r.id)) {
          assert(false, 'Repertory: repeated rubric id "${r.id}"');
          continue;
        }
        final cleaned = <String, int>{};
        for (final e in r.remedies.entries) {
          final canonical = abbr[_norm(e.key)];
          if (canonical == null) {
            assert(false, 'Repertory: unknown remedy "${e.key}" in "${r.id}"');
            continue;
          }
          if (e.value < 1 || e.value > 3) {
            assert(false, 'Repertory: grade ${e.value} in "${r.id}"');
            continue;
          }
          cleaned[canonical] = e.value;
        }
        if (cleaned.isEmpty) continue;
        final rubric = Rubric(
          id: r.id,
          chapter: r.chapter,
          path: r.path,
          remedies: Map.unmodifiable(cleaned),
        );
        byId[r.id] = rubric;
        out.add(rubric);
        if (!chapters.contains(r.chapter)) chapters.add(r.chapter);
      }
    }
    return Repertory._(
      List.unmodifiable(out),
      Map.unmodifiable(byId),
      List.unmodifiable(chapters),
    );
  }

  /// Rubrics whose path contains every word typed (any order), optionally
  /// limited to [chapter]. Shortest paths first when searching.
  List<Rubric> search(String text, {String? chapter}) {
    final words = text
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final hits = <Rubric>[
      for (final r in rubrics)
        if ((chapter == null || r.chapter == chapter) &&
            words.every(r.searchText.contains))
          r,
    ];
    if (words.isNotEmpty) {
      hits.sort((a, b) => a.path.length.compareTo(b.path.length));
    }
    return hits;
  }
}
