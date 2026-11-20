import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/therapy/data/exercise_library.dart';

/// One exercise in a program, with the dose the physio chose.
class HepItem {
  const HepItem({
    required this.exerciseId,
    required this.name,
    required this.sets,
    required this.reps,
    required this.holdSeconds,
    required this.perDay,
  });

  factory HepItem.fromExercise(ExerciseDef e) => HepItem(
    exerciseId: e.id,
    name: e.name,
    sets: e.sets,
    reps: e.reps,
    holdSeconds: e.holdSeconds,
    perDay: e.perDay,
  );

  factory HepItem.fromJson(Map<String, dynamic> j) => HepItem(
    exerciseId: j['exerciseId'] as String? ?? '',
    name: j['name'] as String? ?? '',
    sets: (j['sets'] as num?)?.toInt() ?? 1,
    reps: (j['reps'] as num?)?.toInt() ?? 1,
    holdSeconds: (j['hold'] as num?)?.toInt() ?? 0,
    perDay: (j['perDay'] as num?)?.toInt() ?? 1,
  );

  final String exerciseId;
  final String name;
  final int sets;
  final int reps;
  final int holdSeconds;
  final int perDay;

  HepItem copyWith({int? sets, int? reps, int? holdSeconds, int? perDay}) =>
      HepItem(
        exerciseId: exerciseId,
        name: name,
        sets: sets ?? this.sets,
        reps: reps ?? this.reps,
        holdSeconds: holdSeconds ?? this.holdSeconds,
        perDay: perDay ?? this.perDay,
      );

  Map<String, dynamic> toJson() => {
    'exerciseId': exerciseId,
    'name': name,
    'sets': sets,
    'reps': reps,
    'hold': holdSeconds,
    'perDay': perDay,
  };

  /// "3 sets x 10 reps, hold 5 s, 2 times a day".
  String get doseText {
    final parts = <String>[
      '$sets set${sets == 1 ? '' : 's'} x $reps rep${reps == 1 ? '' : 's'}',
      if (holdSeconds > 0) 'hold $holdSeconds s',
      '$perDay time${perDay == 1 ? '' : 's'} a day',
    ];
    return parts.join(', ');
  }
}

/// A home exercise program saved for a patient (record kind `physioHep`).
class HepProgram {
  const HepProgram({
    required this.id,
    required this.patientId,
    required this.title,
    required this.note,
    required this.items,
    required this.date,
    required this.record,
  });

  factory HepProgram.fromRecord(DentalRecord r) {
    final raw = r.data['items'];
    return HepProgram(
      id: r.id,
      patientId: r.patientId,
      title: r.str('title'),
      note: r.str('note'),
      items: [
        if (raw is List)
          for (final e in raw)
            if (e is Map) HepItem.fromJson(Map<String, dynamic>.from(e)),
      ],
      date: r.recordedAt,
      record: r,
    );
  }

  final String id;
  final String patientId;
  final String title;
  final String note;
  final List<HepItem> items;
  final DateTime date;
  final DentalRecord record;

  static Map<String, dynamic> toData({
    required String title,
    required String note,
    required List<HepItem> items,
  }) => {
    'title': title,
    'note': note,
    'items': [for (final i in items) i.toJson()],
  };
}

/// Library plus the physio's own exercises and attached photos / videos.
/// The muscles a program works: its exercises' muscles, in the order the
/// program lists them and without repeats.
///
/// An exercise the catalogue no longer has, and one whose point is movement
/// rather than a muscle, simply contribute nothing. Used to light up the 3D
/// chart, so the physio and the patient can see what the program is for.
List<String> programMuscles(HepProgram? program, List<ExerciseDef> catalog) {
  if (program == null) return const [];
  final byId = {for (final e in catalog) e.id: e};
  final out = <String>[];
  for (final item in program.items) {
    for (final m in byId[item.exerciseId]?.muscles ?? const <String>[]) {
      if (!out.contains(m)) out.add(m);
    }
  }
  return out;
}

final exerciseCatalogProvider = Provider<List<ExerciseDef>>((ref) {
  final recs =
      ref.watch(clinicRecordsProvider(RecKind.physioExercise)).value ??
      const <DentalRecord>[];
  final custom = <ExerciseDef>[];
  final media = <String, DentalRecord>{};
  for (final r in recs) {
    final id = r.str('exerciseId');
    if (id.isEmpty) continue;
    if (r.data['custom'] == true) {
      custom.add(_customFromRecord(r));
    } else {
      media[id] = r;
    }
  }
  return [
    for (final e in kExerciseLibrary)
      if (media[e.id] case final m?)
        e
            .withMedia(
              recordId: m.id,
              photoPath: _path(m, 'photo'),
              videoPath: _path(m, 'video'),
              videoLink: _link(m),
            )
            .withFavourite(m.data['favourite'] == true)
      else
        e,
    ...custom,
  ];
});

/// A programme the clinic saved to reuse on the next patient.
///
/// The same shape as a [HepProgram] but belonging to nobody, so saving one
/// copies the items and nothing about the patient it came from: no name, no
/// note about their case, nothing that would leak one patient's details into
/// another's programme.
class HepTemplate {
  const HepTemplate({
    required this.title,
    required this.items,
    required this.record,
  });

  factory HepTemplate.fromRecord(DentalRecord r) {
    final raw = r.data['items'];
    return HepTemplate(
      title: r.str('title'),
      items: [
        if (raw is List)
          for (final e in raw)
            if (e is Map) HepItem.fromJson(Map<String, dynamic>.from(e)),
      ],
      record: r,
    );
  }

  final String title;
  final List<HepItem> items;
  final DentalRecord record;

  String get id => record.id;
  DateTime get date => record.recordedAt;

  /// The record data for a template taken from [program]. The programme's
  /// own note is left behind: it was written about that patient.
  static Map<String, dynamic> toData({
    required String title,
    required List<HepItem> items,
  }) => {
    'title': title,
    'items': [for (final i in items) i.toJson()],
  };
}

/// The clinic's saved programmes, newest first.
final hepTemplatesProvider = Provider<List<HepTemplate>>((ref) {
  final recs =
      ref.watch(clinicRecordsProvider(RecKind.physioHepTemplate)).value ??
      const <DentalRecord>[];
  return [for (final r in recs) HepTemplate.fromRecord(r)]
    ..sort((a, b) => b.date.compareTo(a.date));
});

/// Exercise ids the clinic has prescribed lately, most recent first.
///
/// Taken from the programmes already written rather than a list of its own:
/// what a physio reached for last week is the best guess at what they want
/// next, and it needs nothing stored to work.
List<String> recentExerciseIds(
  List<HepProgram> programs, {
  int limit = 8,
}) {
  final newestFirst = [...programs]..sort((a, b) => b.date.compareTo(a.date));
  final out = <String>[];
  for (final p in newestFirst) {
    for (final i in p.items) {
      if (i.exerciseId.isEmpty || out.contains(i.exerciseId)) continue;
      out.add(i.exerciseId);
      if (out.length >= limit) return out;
    }
  }
  return out;
}

/// Starred first, then recently prescribed, then everything else.
///
/// Within each band the order [all] already has is kept, so the library stays
/// predictable: the picker lifts things to the top, it never reshuffles.
List<ExerciseDef> orderExercises(
  List<ExerciseDef> all,
  List<String> recentIds,
) {
  final rank = {
    for (var i = 0; i < recentIds.length; i++) recentIds[i]: i,
  };
  final favourites = <ExerciseDef>[];
  final recent = <ExerciseDef>[];
  final rest = <ExerciseDef>[];
  for (final e in all) {
    if (e.favourite) {
      favourites.add(e);
    } else if (rank.containsKey(e.id)) {
      recent.add(e);
    } else {
      rest.add(e);
    }
  }
  recent.sort((a, b) => rank[a.id]!.compareTo(rank[b.id]!));
  return [...favourites, ...recent, ...rest];
}

/// Every programme in the clinic, for [recentExerciseIds].
final recentExercisesProvider = Provider<List<String>>((ref) {
  final recs =
      ref.watch(clinicRecordsProvider(RecKind.physioHep)).value ??
      const <DentalRecord>[];
  return recentExerciseIds([for (final r in recs) HepProgram.fromRecord(r)]);
});

String? _path(DentalRecord r, String key) {
  final v = r.str(key);
  return v.isEmpty ? null : v;
}

String? _link(DentalRecord r) {
  final v = r.str('link');
  return v.isEmpty ? null : v;
}

ExerciseDef _customFromRecord(DentalRecord r) {
  final steps = r.data['steps'];
  return ExerciseDef(
    id: r.str('exerciseId'),
    name: r.str('name'),
    region: ExerciseRegion.fromName(r.str('region')),
    goal: r.str('goal'),
    steps: [if (steps is List) ...steps.map((s) => s.toString())],
    cautions: r.str('cautions'),
    sets: r.integer('sets') ?? 3,
    reps: r.integer('reps') ?? 10,
    holdSeconds: r.integer('hold') ?? 0,
    perDay: r.integer('perDay') ?? 1,
    level: ExerciseLevel.fromName(r.str('level')),
    isCustom: true,
    recordId: r.id,
    photoPath: _path(r, 'photo'),
    videoPath: _path(r, 'video'),
    videoLink: _link(r),
  );
}

/// Saves a new custom exercise.
Future<void> saveCustomExercise(
  WidgetRef ref, {
  required String name,
  required ExerciseRegion region,
  required String goal,
  required List<String> steps,
  required String cautions,
  required int sets,
  required int reps,
  required int holdSeconds,
  required int perDay,
  required ExerciseLevel level,
}) async {
  final r = DentalRecord.create('', RecKind.physioExercise, {
    'custom': true,
    'name': name,
    'region': region.name,
    'goal': goal,
    'steps': steps,
    'cautions': cautions,
    'sets': sets,
    'reps': reps,
    'hold': holdSeconds,
    'perDay': perDay,
    'level': level.name,
  });
  await saveDentalRecord(
    ref,
    r.copyWith(data: {...r.data, 'exerciseId': 'c-${r.id}'}),
  );
}

/// Copies a photo or video into app storage and attaches it to [e], so it is
/// reused whenever the exercise is prescribed. [kind] is 'photo' or 'video'.
Future<void> attachExerciseFile(
  WidgetRef ref,
  ExerciseDef e,
  String kind,
  String sourcePath,
) async {
  final dir = await getApplicationSupportDirectory();
  final target = Directory(p.join(dir.path, 'therapy', 'exercises', e.id));
  if (!target.existsSync()) target.createSync(recursive: true);
  final dest = p.join(
    target.path,
    '$kind-${DateTime.now().millisecondsSinceEpoch}${p.extension(sourcePath)}',
  );
  await File(sourcePath).copy(dest);
  final old = kind == 'photo' ? e.photoPath : e.videoPath;
  await _updateMedia(ref, e, {kind: dest});
  if (old != null) {
    try {
      await File(old).delete();
    } catch (_) {}
  }
}

/// Sets or clears the pasted video link.
Future<void> setExerciseLink(WidgetRef ref, ExerciseDef e, String link) =>
    _updateMedia(ref, e, {'link': link.trim()});

/// Removes the attached 'photo' or 'video'.
Future<void> removeExerciseFile(
  WidgetRef ref,
  ExerciseDef e,
  String kind,
) async {
  final old = kind == 'photo' ? e.photoPath : e.videoPath;
  await _updateMedia(ref, e, {kind: ''});
  if (old != null) {
    try {
      await File(old).delete();
    } catch (_) {}
  }
}

Future<void> _updateMedia(
  WidgetRef ref,
  ExerciseDef e,
  Map<String, dynamic> change,
) async {
  final recs =
      ref.read(clinicRecordsProvider(RecKind.physioExercise)).value ??
      const <DentalRecord>[];
  final existing = recs.where((r) => r.id == e.recordId).firstOrNull;
  if (existing != null) {
    await saveDentalRecord(
      ref,
      existing.copyWith(data: {...existing.data, ...change}),
    );
  } else {
    await saveDentalRecord(
      ref,
      DentalRecord.create('', RecKind.physioExercise, {
        'exerciseId': e.id,
        ...change,
      }),
    );
  }
}
