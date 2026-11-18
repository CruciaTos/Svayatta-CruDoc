/// One repertory rubric: a symptom phrase and the remedies that cover it.
///
/// Data files hold `const Rubric(...)` lists (see the header of
/// `repertory_part_mind.dart` for the format). The engine and the screens
/// only ever read rubrics through `Repertory` in `repertory_registry.dart`,
/// so adding rubrics never needs a code change outside a data file.
class Rubric {
  const Rubric({
    required this.id,
    required this.chapter,
    required this.path,
    required this.remedies,
  });

  /// Stable, unique and never reused: saved repertorizations store this id.
  final String id;

  /// Top-level group shown as a filter chip, e.g. "Mind".
  final String chapter;

  /// Breadcrumb, parts joined by " > ", e.g. "Mind > Fear > death, of".
  final String path;

  /// Remedy abbreviation (as written in `homeopathy_remedies.dart`, e.g.
  /// "Puls.") to grade: 1 plain, 2 italic, 3 bold.
  final Map<String, int> remedies;

  /// [path] lower-cased, for search.
  String get searchText => path.toLowerCase();

  /// The last part of the path, the symptom itself ("death, of").
  String get leaf {
    final i = path.lastIndexOf(' > ');
    return i < 0 ? path : path.substring(i + 3);
  }

  /// Everything before the last part ("Mind > Fear").
  String get parent {
    final i = path.lastIndexOf(' > ');
    return i < 0 ? '' : path.substring(0, i);
  }
}
