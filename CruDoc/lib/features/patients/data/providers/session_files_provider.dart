import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/files_providers.dart';

/// A file deliberately kept out of every session: stored like a link, so
/// the day it was added on does not claim it.
const kNoVisit = 'none';

/// Which of a patient's files belong to which visit.
///
/// A file belongs to a visit when it was added from that visit's session
/// pop-up (a [RecKind.visitFiles] record), or, when it isn't linked to
/// any visit, when it was added on the day of a visit that wasn't
/// cancelled or missed.
class SessionFiles {
  const SessionFiles({required this.files, required this.links});

  static const empty = SessionFiles(files: [], links: {});

  /// The patient's files, newest first.
  final List<PatientFile> files;

  /// File id → the visit it was added to, or [kNoVisit].
  final Map<String, String> links;

  /// [visit]'s files, newest first. [extraIds] adds files linked some
  /// other way (pages a Scribe session scanned).
  List<PatientFile> forVisit(
    Visit visit, {
    Iterable<String> extraIds = const [],
  }) {
    final extra = extraIds.toSet();
    final countsByDay =
        visit.status != VisitStatus.cancelled &&
        visit.status != VisitStatus.missed;
    return [
      for (final f in files)
        if (links[f.id] == visit.id ||
            extra.contains(f.id) ||
            (countsByDay &&
                !links.containsKey(f.id) &&
                _sameDay(f.createdAt, visit.scheduledStart)))
          f,
    ];
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// [SessionFiles] for one patient.
final sessionFilesProvider = Provider.family<SessionFiles, String>((
  ref,
  patientId,
) {
  final files = ref.watch(patientFilesProvider(patientId)).value;
  if (files == null || files.isEmpty) return SessionFiles.empty;
  final records =
      ref
          .watch(
            patientRecordsProvider((
              patientId: patientId,
              kind: RecKind.visitFiles,
            )),
          )
          .value ??
      const <DentalRecord>[];
  final links = <String, String>{};
  for (final r in records) {
    final visitId = r.str('visitId');
    final ids = r.data['fileIds'];
    if (visitId.isEmpty || ids is! List) continue;
    for (final id in ids) {
      links['$id'] = visitId;
    }
  }
  return SessionFiles(files: files, links: links);
});

/// Links [fileIds] to [visit] (adds to its record, or starts one).
Future<void> linkFilesToVisit(
  WidgetRef ref,
  Visit visit,
  Iterable<String> fileIds,
) => setFilesVisit(ref, visit.patientId, fileIds, visit);

/// Puts the patient's [fileIds] in [visit]'s session, taking them out of
/// any other. With no [visit] they belong to no session.
Future<void> setFilesVisit(
  WidgetRef ref,
  String patientId,
  Iterable<String> fileIds,
  Visit? visit,
) async {
  final ids = fileIds.toSet();
  if (ids.isEmpty) return;
  final provider = patientRecordsProvider((
    patientId: patientId,
    kind: RecKind.visitFiles,
  ));
  final records = await ref.read(provider.future);
  final target = visit?.id ?? kNoVisit;
  DentalRecord? existing;
  final leaving = <DentalRecord>[];
  for (final r in records) {
    final held = r.data['fileIds'];
    if (r.str('visitId') == target && existing == null) {
      existing = r;
    } else if (held is List && held.any((id) => ids.contains('$id'))) {
      leaving.add(
        r.copyWith(
          data: {
            ...r.data,
            'fileIds': [
              for (final id in held)
                if (!ids.contains('$id')) '$id',
            ],
          },
        ),
      );
    }
  }
  final before = existing?.data['fileIds'];
  final merged = <String>{
    if (before is List)
      for (final id in before) '$id',
    ...ids,
  }.toList();
  final record = existing == null
      ? DentalRecord.create(patientId, RecKind.visitFiles, {
          'visitId': target,
          'fileIds': merged,
        }, at: visit?.scheduledStart)
      : existing.copyWith(data: {...existing.data, 'fileIds': merged});
  for (final r in leaving) {
    await saveDentalRecord(ref, r);
  }
  await saveDentalRecord(ref, record);
}
