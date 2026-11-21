import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/therapy/data/modality_catalog.dart';

/// One electrotherapy or thermal application, as it was actually given
/// (record kind `physioModality`).
///
/// The settings are kept exactly as typed, in a map keyed by the catalogue's
/// parameter ids, and nothing is normalised or filled in. A parameter the
/// physio left blank stays absent, because a log that invented 1.0 W/cm²
/// because that is the usual figure would be worse than one that admits the
/// intensity was never written down.
class ModalityApplication {
  const ModalityApplication({
    required this.modalityId,
    required this.site,
    required this.minutes,
    required this.params,
    required this.note,
    required this.record,
  });

  factory ModalityApplication.fromRecord(DentalRecord r) {
    final raw = r.data['params'];
    return ModalityApplication(
      modalityId: r.str('modalityId'),
      site: r.str('site'),
      minutes: r.data['minutes'] is int ? r.data['minutes'] as int : null,
      params: {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.value is String && (e.value as String).trim().isNotEmpty)
              '${e.key}': (e.value as String).trim(),
      },
      note: r.str('note'),
      record: r,
    );
  }

  final String modalityId;

  /// Where it was applied, in the physio's words ("R knee", "L shoulder").
  final String site;

  /// Treatment time. Null when it was not recorded.
  final int? minutes;

  /// Settings by catalogue parameter id. Only what was filled in.
  final Map<String, String> params;

  final String note;
  final DentalRecord record;

  String get id => record.id;
  DateTime get givenAt => record.recordedAt;

  /// The catalogue entry, or null for a modality no longer in the catalogue.
  ModalityDef? get def => modalityById(modalityId);

  /// What to call it. Falls back to the stored id so a record from a removed
  /// modality is still identifiable rather than appearing blank.
  String get label => def?.short ?? modalityId;

  /// The settings as one line, e.g. `80 Hz · 200 µs · 18 mA`.
  ///
  /// Ordered by the catalogue rather than by the map, so the same treatment
  /// always reads the same way, and parameters the catalogue has dropped are
  /// left out rather than appearing without a label.
  String get settingsLine {
    final d = def;
    if (d == null) return params.values.join(' · ');
    final parts = <String>[];
    for (final p in d.params) {
      final v = params[p.id];
      if (v == null) continue;
      parts.add(p.unit.isEmpty ? v : '$v ${p.unit}');
    }
    return parts.join(' · ');
  }

  /// Everything about the application on one line, for a card or a report
  /// row: what, where, how long, at what settings.
  String get summaryLine {
    final parts = [
      label,
      if (site.trim().isNotEmpty) site.trim(),
      if (minutes != null) '$minutes min',
      if (settingsLine.isNotEmpty) settingsLine,
    ];
    return parts.join(' · ');
  }

  /// True when the catalogue asks for a setting that was not recorded.
  ///
  /// Surfaced rather than silently tolerated: an application logged without
  /// its settings is the thing this feature exists to prevent, so the card
  /// says so and the physio can still fix it.
  bool get isIncomplete {
    final d = def;
    if (d == null) return false;
    for (final p in d.params) {
      if (!params.containsKey(p.id)) return true;
    }
    return minutes == null;
  }

  static Map<String, dynamic> toData({
    required String modalityId,
    required String site,
    required int? minutes,
    required Map<String, String> params,
    required String note,
  }) => {
    'modalityId': modalityId,
    'site': site,
    // Null-aware: an unrecorded time leaves no key at all, rather than
    // writing a zero that would read as a treatment given for no time.
    'minutes': ?minutes,
    'params': {
      for (final e in params.entries)
        if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
    },
    'note': note,
  };
}

/// A patient's applications, most recent first.
List<ModalityApplication> modalityApplications(Iterable<DentalRecord> recs) =>
    [for (final r in recs) ModalityApplication.fromRecord(r)]
      ..sort((a, b) => b.givenAt.compareTo(a.givenAt));

/// One day's applications, which is how a physio reads the log back: what
/// was done in that session, not a flat list of machines.
class ModalityDay {
  const ModalityDay(this.day, this.applications);

  final DateTime day;
  final List<ModalityApplication> applications;

  /// The modalities used that day, each named once and in the order they
  /// were given, e.g. `IFT · US`.
  String get line {
    final seen = <String>[];
    for (final a in applications.reversed) {
      if (!seen.contains(a.label)) seen.add(a.label);
    }
    return seen.join(' · ');
  }
}

/// The applications grouped by the day they were given, newest day first.
List<ModalityDay> modalityDays(List<ModalityApplication> apps) {
  final byDay = <DateTime, List<ModalityApplication>>{};
  for (final a in apps) {
    final d = DateTime(a.givenAt.year, a.givenAt.month, a.givenAt.day);
    (byDay[d] ??= []).add(a);
  }
  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final d in days) ModalityDay(d, byDay[d]!)];
}

/// How many sessions used each modality, most used first.
///
/// For the progress report: over an episode of care, "IFT ×12, US ×5" is the
/// useful summary, not twelve identical rows.
List<({String label, int count})> modalityTally(
  List<ModalityApplication> apps,
) {
  final counts = <String, int>{};
  for (final a in apps) {
    counts[a.label] = (counts[a.label] ?? 0) + 1;
  }
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      // Same count: alphabetical, so the order does not shuffle between
      // builds of the same report.
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  return [for (final e in entries) (label: e.key, count: e.value)];
}

/// The one-line summary of modalities used, or null when none were.
String? modalityTallyLine(List<ModalityApplication> apps) {
  final tally = modalityTally(apps);
  if (tally.isEmpty) return null;
  return [for (final t in tally) '${t.label} ×${t.count}'].join(', ');
}
