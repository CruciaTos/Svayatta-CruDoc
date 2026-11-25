import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';

// Photographs of a skin case over the course of treatment.
//
// Built around a named site rather than a fixed view, which is the one thing
// the physiotherapy photo set gets to do differently: every patient has an
// anterior posture view, but a skin case has its lesions wherever it has
// them. One wart on a left thumb, or psoriasis on both elbows and the scalp.
// So the sites are named by the homeopath on the first visit and reused
// after that, which is also what makes a comparison honest — two photographs
// only mean something side by side if they are of the same place.
//
// A photograph is evidence, so nothing here crops, enhances, rotates or
// re-encodes one. The file is copied as it came off the camera and the
// record points at it.

/// A site key: safe as a file name, stable across visits, and derived from
/// the label so the same site typed the same way lands in the same series.
///
/// Returns an empty string for a label with nothing usable in it, which the
/// caller must treat as "not a site" rather than storing under an empty key.
String lesionSiteKey(String label) {
  final slug = label
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return slug;
}

/// One visit's photographs (record kind `homeoLesionPhoto`).
class LesionPhotoSet {
  const LesionPhotoSet({
    required this.date,
    required this.notes,
    required this.sites,
    required this.photos,
    required this.record,
  });

  factory LesionPhotoSet.fromRecord(DentalRecord r) {
    Map<String, String> strings(Object? raw) => {
      if (raw is Map)
        for (final e in raw.entries)
          if (e.value is String && (e.value as String).trim().isNotEmpty)
            '${e.key}': (e.value as String).trim(),
    };
    return LesionPhotoSet(
      date: r.date('date') ?? r.recordedAt,
      notes: r.str('notes'),
      sites: strings(r.data['sites']),
      photos: strings(r.data['photos']),
      record: r,
    );
  }

  final DateTime date;
  final String notes;

  /// Site key to the label as the homeopath typed it, so a site keeps its
  /// wording even after the key has been slugged.
  final Map<String, String> sites;

  /// Site key to the photograph's local path.
  final Map<String, String> photos;

  final DentalRecord record;

  String get id => record.id;

  /// Sites in this set that actually have a photograph.
  List<String> get photographed => [
    for (final key in photos.keys)
      if (photos[key]!.trim().isNotEmpty) key,
  ];

  /// The label for a site, falling back to the key when a record has a
  /// photograph under a site whose label was lost.
  String labelFor(String key) => sites[key] ?? key;

  String? pathFor(String key) => photos[key];

  static Map<String, dynamic> toData({
    required DateTime date,
    required String notes,
    required Map<String, String> sites,
    required Map<String, String> photos,
  }) => {
    'date': date.millisecondsSinceEpoch,
    'notes': notes,
    'sites': {...sites},
    'photos': {...photos},
  };
}

/// A patient's photograph sets, newest visit first.
List<LesionPhotoSet> lesionPhotoSets(Iterable<DentalRecord> recs) =>
    [for (final r in recs) LesionPhotoSet.fromRecord(r)]
      ..sort((a, b) => b.date.compareTo(a.date));

/// One site followed across visits — what the homeopath actually looks at.
class LesionSeries {
  const LesionSeries(this.key, this.label, this.shots);

  final String key;
  final String label;

  /// Photographs of this site, oldest first: the first one is the baseline
  /// everything after it is judged against.
  final List<LesionShot> shots;

  int get count => shots.length;
  LesionShot get first => shots.first;
  LesionShot get latest => shots.last;

  /// Whole days from the first photograph to the latest.
  int get days => DateTime(latest.date.year, latest.date.month, latest.date.day)
      .difference(DateTime(first.date.year, first.date.month, first.date.day))
      .inDays;

  int get weeks => (days / 7).round();

  /// Whether there are two photographs to put side by side.
  ///
  /// A single photograph is a record, not a comparison, and offering a
  /// before and after built from one image would be a lie about what the
  /// clinic has.
  bool get canCompare => shots.length >= 2;
}

/// One photograph of one site.
class LesionShot {
  const LesionShot({
    required this.date,
    required this.path,
    required this.notes,
    required this.set,
  });

  final DateTime date;
  final String path;
  final String notes;
  final LesionPhotoSet set;
}

/// Every site the patient has photographs of, each with its own series.
///
/// Ordered by the site that was photographed most recently, so the lesion
/// being followed now comes first. A site is matched by key, so the same
/// place typed with different capitalisation stays one series.
List<LesionSeries> lesionSeriesOf(List<LesionPhotoSet> sets) {
  final shots = <String, List<LesionShot>>{};
  final labels = <String, String>{};

  // Oldest first so each series builds in order and the earliest label wins,
  // which keeps a site's name as it was first written rather than as it was
  // last retyped.
  final ordered = [...sets]..sort((a, b) => a.date.compareTo(b.date));
  for (final set in ordered) {
    for (final key in set.photographed) {
      (shots[key] ??= []).add(
        LesionShot(
          date: set.date,
          path: set.photos[key]!,
          notes: set.notes,
          set: set,
        ),
      );
      labels.putIfAbsent(key, () => set.labelFor(key));
    }
  }

  final series = [
    for (final key in shots.keys)
      LesionSeries(key, labels[key] ?? key, shots[key]!),
  ]..sort((a, b) => b.latest.date.compareTo(a.latest.date));
  return series;
}

/// The sites a patient already has, for offering them again on a new visit.
///
/// Reusing a site rather than retyping it is what keeps a series intact, so
/// these are offered as the first thing on a new set.
List<({String key, String label})> knownLesionSites(
  List<LesionPhotoSet> sets,
) => [for (final s in lesionSeriesOf(sets)) (key: s.key, label: s.label)];

/// A line for the case record: how long this site has been followed.
///
/// Says nothing about whether it improved. Judging a lesion from a
/// photograph is the homeopath's call, and a model that guessed at it from
/// two images would be inventing a clinical finding.
String lesionSeriesLine(LesionSeries s) {
  if (!s.canCompare) return '1 photograph';
  final span = s.weeks == 0
      ? '${s.days} day${s.days == 1 ? '' : 's'}'
      : '${s.weeks} week${s.weeks == 1 ? '' : 's'}';
  return '${s.count} photographs over $span';
}
