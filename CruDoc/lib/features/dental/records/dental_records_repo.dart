import 'package:doctor_management_app/core/utils/app_notice.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/database/local_database.dart';
import 'package:doctor_management_app/core/services/firestore_sync_service.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_desktop_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Kinds of dental clinical record.
abstract final class RecKind {
  static const perio = 'perio';
  static const perioDx = 'perioDx';
  static const srp = 'srp';
  static const endo = 'endo';
  static const consent = 'consent';
  static const recall = 'recall';
  static const recallRule = 'recallRule';
  static const pain = 'pain';
  static const tmd = 'tmd';
  static const frankl = 'frankl';
  static const checklist = 'checklist';
  static const meta = 'meta';

  /// Oral medicine history (one per patient, updated in place).
  static const omHistory = 'omHistory';

  /// Eruption chart (one per patient, updated in place).
  static const eruption = 'eruption';

  /// The clinic's own emergency protocols (no patient).
  static const emergencyProtocol = 'emergencyProtocol';

  /// Referrals sent and received (patientId = patient).
  static const referral = 'referral';

  /// Referral contacts / directory (patientId = '').
  static const referralContact = 'referralContact';

  /// Prosthodontic lab cases (patientId = patient).
  static const labCase = 'labCase';

  /// Orthodontic photo series (patientId = patient).
  static const photoSet = 'photoSet';

  /// Orthodontic cases (patientId = patient).
  static const orthoCase = 'orthoCase';

  /// Sedation and anaesthesia cases (patientId = patient).
  static const sedationCase = 'sedationCase';

  /// Clinic custom form templates (patientId = '').
  static const formTemplate = 'formTemplate';

  /// Patient filled form responses (patientId = patient).
  static const formResponse = 'formResponse';

  /// Physiotherapy session photo series (patientId = patient).
  static const physioPhotoSet = 'physioPhotoSet';

  /// Physiotherapy 3D muscle chart findings (patientId = patient).
  static const muscleChart = 'muscleChart';

  /// Files added from a visit's session pop-up: one record per visit,
  /// `{visitId, fileIds}` (any specialty).
  static const visitFiles = 'visitFiles';

  /// Physiotherapy exercises the physio added, or media attached to a bundled
  /// exercise: `{exerciseId, custom?, ...}` (patientId = '').
  static const physioExercise = 'physioExercise';

  /// Physiotherapy home exercise program (patientId = patient).
  static const physioHep = 'physioHep';

  /// One physiotherapy goal with a target date
  /// `{text, target, status, note}` (patientId = patient).
  static const physioGoal = 'physioGoal';

  /// Physiotherapy intake screening: which red and yellow flags were asked
  /// about and what the answer was `{flags: {id: present|absent}, note}`
  /// (patientId = patient, one per patient, updated in place).
  static const physioScreening = 'physioScreening';

  /// A saved home exercise program the clinic reuses, same shape as
  /// `physioHep` (`{title, note, items}`) but belonging to no patient
  /// (patientId = '', clinic-wide).
  static const physioHepTemplate = 'physioHepTemplate';

  /// Physiotherapy pain and function score `{pain, worst, function, note}`
  /// (patientId = patient).
  static const physioProgress = 'physioProgress';

  /// Physiotherapy ROM and strength assessment
  /// `{region, rows: [{move, lDeg, rDeg, lMmt, rMmt}], note}`
  /// (patientId = patient).
  static const physioRom = 'physioRom';

  /// Physiotherapy session package
  /// `{name, total, price?, validUntil?, note, used: [epochMs]}`
  /// (patientId = patient).
  static const physioPackage = 'physioPackage';

  /// Physiotherapy special test result `{testId, side, result, note}`
  /// (patientId = patient).
  static const physioTestResult = 'physioTestResult';

  /// One completed outcome measure `{scaleId, answers: {itemId: index},
  /// value?, note}` (patientId = patient).
  ///
  /// `answers` for a questionnaire, `value` for a measure that is a single
  /// figure (a walk distance, a timed test). The score itself is never
  /// stored: it is derived from the answers every time, so a scoring rule
  /// that is corrected also corrects the history instead of leaving old
  /// records carrying a number nothing can reproduce.
  static const physioScaleScore = 'physioScaleScore';

  /// One electrotherapy or modality application in a session
  /// `{modalityId, site, minutes, params: {paramId: value}, note}`
  /// (patientId = patient).
  ///
  /// One record per application, not per session: a knee and a shoulder
  /// treated on the same day were two applications at two sets of settings,
  /// and a log that averaged them could not answer what was actually given.
  static const physioModality = 'physioModality';

  /// Homeopathy dose plan `{remedy, potency, pattern, days?, reviewOn, note,
  /// recallId?}` (patientId = patient).
  static const homeoDosePlan = 'homeoDosePlan';

  /// Homeopathy totality (one per patient, updated in place)
  /// `{items: [{source, text, tier, miasm, skip}], miasmCase: [...]}`.
  static const homeoTotality = 'homeoTotality';

  /// Homeopathy repertorization `{rubrics: [{id, weight}], note,
  /// chosenRemedy?}` (patientId = patient).
  static const homeoRepertorization = 'homeoRepertorization';

  /// Homeopathy remedy dispensed to a patient
  /// `{remedy, potency, form, qty, unit, note, stockId?, stockTaken?}`
  /// (patientId = patient).
  static const homeoDispense = 'homeoDispense';

  /// One visit's photographs of a skin case `{date, notes,
  /// sites: {key: label}, photos: {key: localPath}}` (patientId = patient).
  ///
  /// Sites are named per patient rather than chosen from a fixed list,
  /// because a skin case has its lesions wherever it has them: one wart on a
  /// thumb, or patches on both elbows and the scalp. The physiotherapy photo
  /// set uses fixed posture slots for the opposite reason — every patient
  /// has one anterior view.
  static const homeoLesionPhoto = 'homeoLesionPhoto';

  /// Homeopathy remedy stock line `{remedy, potency, form, qty, unit, low?}`
  /// (patientId = '', clinic-wide).
  static const homeoStock = 'homeoStock';
}

/// One clinical record (a perio exam, an endo record, a signed consent,
/// a recall…) stored as JSON, so each kind can grow without migrations.
class DentalRecord {
  const DentalRecord({
    required this.id,
    required this.patientId,
    required this.kind,
    required this.data,
    required this.recordedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DentalRecord.create(
    String patientId,
    String kind,
    Map<String, dynamic> data, {
    DateTime? at,
  }) {
    final now = DateTime.now();
    return DentalRecord(
      id: const Uuid().v4(),
      patientId: patientId,
      kind: kind,
      data: data,
      recordedAt: at ?? now,
      createdAt: now,
      updatedAt: now,
    );
  }

  final String id;

  /// Empty for clinic-wide records (recall rules).
  final String patientId;
  final String kind;
  final Map<String, dynamic> data;

  /// When it happened (exam date, signing time, recall due date…).
  final DateTime recordedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  String str(String key) => data[key] is String ? data[key] as String : '';
  int? integer(String key) => (data[key] as num?)?.toInt();
  double? number(String key) => (data[key] as num?)?.toDouble();
  DateTime? date(String key) => data[key] is int
      ? DateTime.fromMillisecondsSinceEpoch(data[key] as int)
      : null;

  DentalRecord copyWith({Map<String, dynamic>? data, DateTime? recordedAt}) =>
      DentalRecord(
        id: id,
        patientId: patientId,
        kind: kind,
        data: data ?? this.data,
        recordedAt: recordedAt ?? this.recordedAt,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}

/// Local store for dental clinical records (`dental_records` table).
class DentalRecordsRepository {
  DentalRecordsRepository({LocalDatabaseService? db})
    : _db = db ?? LocalDatabaseService.instance;

  final LocalDatabaseService _db;

  static final StreamController<void> _changesController =
      StreamController<void>.broadcast();
  static Stream<void> get changes => _changesController.stream;
  static void notifyRecordsChanged() {
    if (!_changesController.isClosed) {
      _changesController.add(null);
    }
  }

  DentalRecord _fromRow(Map<String, Object?> r) {
    Map<String, dynamic> data;
    try {
      final d = jsonDecode(r['data'] as String? ?? '{}');
      data = d is Map ? Map<String, dynamic>.from(d) : {};
    } catch (_) {
      data = {};
    }
    DateTime t(Object? v) =>
        DateTime.fromMillisecondsSinceEpoch((v as int?) ?? 0);
    return DentalRecord(
      id: r['id'] as String,
      patientId: r['patientId'] as String? ?? '',
      kind: r['kind'] as String? ?? '',
      data: data,
      recordedAt: t(r['recordedAt']),
      createdAt: t(r['createdAt']),
      updatedAt: t(r['updatedAt']),
    );
  }

  Future<List<DentalRecord>> forPatient(
    String doctorId,
    String patientId,
    String kind,
  ) async {
    final db = await _db.localDatabase;
    final rows = await db.query(
      'dental_records',
      where: 'doctorId = ? AND patientId = ? AND kind = ? AND isDeleted = 0',
      whereArgs: [doctorId, patientId, kind],
      orderBy: 'recordedAt DESC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Every record of one patient, newest first, in a single query.
  Future<List<DentalRecord>> allForPatient(
    String doctorId,
    String patientId,
  ) async {
    final db = await _db.localDatabase;
    final rows = await db.query(
      'dental_records',
      where: 'doctorId = ? AND patientId = ? AND isDeleted = 0',
      whereArgs: [doctorId, patientId],
      orderBy: 'recordedAt DESC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<DentalRecord?> byId(String id) async {
    final db = await _db.localDatabase;
    final rows = await db.query(
      'dental_records',
      where: 'id = ? AND isDeleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<List<DentalRecord>> all(String doctorId, String kind) async {
    final db = await _db.localDatabase;
    final rows = await db.query(
      'dental_records',
      where: 'doctorId = ? AND kind = ? AND isDeleted = 0',
      whereArgs: [doctorId, kind],
      orderBy: 'recordedAt DESC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<void> save(String doctorId, DentalRecord r) async {
    final db = await _db.localDatabase;
    await db.insert('dental_records', {
      'id': r.id,
      'doctorId': doctorId,
      'patientId': r.patientId,
      'kind': r.kind,
      'data': jsonEncode(r.data),
      'recordedAt': r.recordedAt.millisecondsSinceEpoch,
      'isDeleted': 0,
      'createdAt': r.createdAt.millisecondsSinceEpoch,
      'updatedAt': r.updatedAt.millisecondsSinceEpoch,
      'syncStatus': 'pending',
      'pendingDelete': 0,
    }, conflictAlgorithm: LocalConflictAlgorithm.replace);
    notifyRecordsChanged();
    unawaited(FirestoreSyncService.instance.triggerPostWriteSync());
  }

  /// Saves many records in transactions of at most 400 rows, then syncs once.
  Future<void> saveMany(String doctorId, List<DentalRecord> records) async {
    if (records.isEmpty) return;
    final db = await _db.localDatabase;
    for (var i = 0; i < records.length; i += 400) {
      final chunk = records.skip(i).take(400);
      await db.transaction((txn) async {
        for (final r in chunk) {
          await txn.insert('dental_records', {
            'id': r.id,
            'doctorId': doctorId,
            'patientId': r.patientId,
            'kind': r.kind,
            'data': jsonEncode(r.data),
            'recordedAt': r.recordedAt.millisecondsSinceEpoch,
            'isDeleted': 0,
            'createdAt': r.createdAt.millisecondsSinceEpoch,
            'updatedAt': r.updatedAt.millisecondsSinceEpoch,
            'syncStatus': 'pending',
            'pendingDelete': 0,
          }, conflictAlgorithm: LocalConflictAlgorithm.replace);
        }
      });
    }
    notifyRecordsChanged();
    unawaited(FirestoreSyncService.instance.triggerPostWriteSync());
  }

  Future<void> delete(String id) async {
    final db = await _db.localDatabase;
    await db.update(
      'dental_records',
      {
        'isDeleted': 1,
        'syncStatus': 'pending',
        'pendingDelete': 0,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyRecordsChanged();
    unawaited(FirestoreSyncService.instance.triggerPostWriteSync());
  }

  /// Completed procedures since [since], for recall suggestions.
  Future<List<({String patientId, String name, DateTime at})>>
  completedProcedures(
    String doctorId,
    DateTime since, {
    String? patientId,
  }) async {
    final db = await _db.localDatabase;
    final rows = await db.query(
      'procedure_log_entries',
      columns: ['patientId', 'procedureName', 'performedAt'],
      where:
          "doctorId = ? AND isDeleted = 0 AND status = 'completed' AND performedAt >= ?"
          '${patientId == null ? '' : ' AND patientId = ?'}',
      whereArgs: [
        doctorId,
        since.millisecondsSinceEpoch,
        ?patientId,
      ],
      orderBy: 'performedAt DESC',
    );
    return [
      for (final r in rows)
        (
          patientId: r['patientId'] as String? ?? '',
          name: r['procedureName'] as String? ?? '',
          at: DateTime.fromMillisecondsSinceEpoch(
            r['performedAt'] as int? ?? 0,
          ),
        ),
    ];
  }
}

final dentalRecordsRepoProvider = Provider<DentalRecordsRepository>(
  (ref) => DentalRecordsRepository(),
);

typedef RecKey = ({String patientId, String kind});

final dentalRecordsVersionProvider = StreamProvider<int>((ref) async* {
  yield 0;
  int version = 0;
  await for (final _ in DentalRecordsRepository.changes) {
    yield ++version;
  }
});

/// One patient's records of a kind, newest first.
final patientRecordsProvider =
    FutureProvider.family<List<DentalRecord>, RecKey>((ref, k) {
      ref.watch(dentalRecordsVersionProvider);
      final doctorId = ref.watch(dentalDoctorIdProvider);
      return ref
          .watch(dentalRecordsRepoProvider)
          .forPatient(doctorId, k.patientId, k.kind);
    });

/// All of one patient's records grouped by kind, each list newest first.
/// One query, so a card showing every kind stays light.
final patientRecordsByKindProvider =
    FutureProvider.family<Map<String, List<DentalRecord>>, String>((
      ref,
      patientId,
    ) async {
      ref.watch(dentalRecordsVersionProvider);
      final doctorId = ref.watch(dentalDoctorIdProvider);
      final all = await ref
          .watch(dentalRecordsRepoProvider)
          .allForPatient(doctorId, patientId);
      final byKind = <String, List<DentalRecord>>{};
      for (final r in all) {
        (byKind[r.kind] ??= []).add(r);
      }
      return byKind;
    });

/// Every record of a kind in the clinic, newest first.
final clinicRecordsProvider = FutureProvider.family<List<DentalRecord>, String>(
  (ref, kind) {
    ref.watch(dentalRecordsVersionProvider);
    final doctorId = ref.watch(dentalDoctorIdProvider);
    return ref.watch(dentalRecordsRepoProvider).all(doctorId, kind);
  },
);

/// Saves [r] and refreshes the lists that show it.
Future<void> saveDentalRecord(WidgetRef ref, DentalRecord r) async {
  await ref
      .read(dentalRecordsRepoProvider)
      .save(ref.read(dentalDoctorIdProvider), r);
  ref.invalidate(
    patientRecordsProvider((patientId: r.patientId, kind: r.kind)),
  );
  ref.invalidate(clinicRecordsProvider(r.kind));
}

Future<void> deleteDentalRecord(WidgetRef ref, DentalRecord r) async {
  await ref.read(dentalRecordsRepoProvider).delete(r.id);
  ref.invalidate(
    patientRecordsProvider((patientId: r.patientId, kind: r.kind)),
  );
  ref.invalidate(clinicRecordsProvider(r.kind));
}

/// A short message at the bottom of the window.
void recToast(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showIsland(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        width: 420,
      ),
    );
}

/// Stroke icons for the clinical records (24-unit viewBox).
abstract final class RecIcons {
  /// Perio: a tooth with the gum line.
  static const perio = CruIconData(
    'M7 4c-2 0-3 1.6-3 3.8 0 2 .8 3.5 1.4 5 .6 1.5.8 3.3 1 5 .2 1.4.8 2.2 1.6 2.2 1 0 1.3-.9 1.6-2.4l.6-3c.2-1 .9-1.6 1.8-1.6s1.6.6 1.8 1.6l.6 3c.3 1.5.6 2.4 1.6 2.4.8 0 1.4-.8 1.6-2.2.2-1.7.4-3.5 1-5 .6-1.5 1.4-3 1.4-5C20 5.6 19 4 17 4c-1.6 0-2.9.9-5 .9S8.6 4 7 4zM3 11.5c3 1.5 6 1.5 9 0s6-1.5 9 0',
  );

  /// Endo: a root with its canal.
  static const endo = CruIconData(
    'M8 3.5h8M9 3.5c0 5 1 10 3 17 2-7 3-12 3-17M12 6v10',
  );

  /// Consent: a page with a signature.
  static const consent = CruIconData(
    'M14 3.5H7.5a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2V8zM14 3.5V8h4.5'
    'M8.5 16c1.2 0 1.6-3 2.5-3s.4 2.5 1.4 2.5 1-1 1.8-1 .6 1 1.3 1',
  );

  /// Recall: a bell.
  static const recall = CruIconData(
    'M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2h-15zM10 20.5a2 2 0 0 0 4 0',
  );

  /// Pain: a pulse line.
  static const pain = CruIconData('M3 12h4l2-5 3 10 2.5-7 1.5 2H21');

  /// Behaviour: a face.
  static const frankl = CruIconData(
    'M8.5 14.5c.9 1.2 2.1 1.8 3.5 1.8s2.6-.6 3.5-1.8',
    circles: [(12, 12, 8.5), (9, 10, 0.6), (15, 10, 0.6)],
  );

  /// Medical history: a page with a medical cross.
  static const history = CruIconData(
    'M14 3.5H7.5a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2V8zM14 3.5V8h4.5'
    'M12 11.5v6M9 14.5h6',
  );

  /// Root planing: a curette.
  static const srp = CruIconData(
    'M4.5 19.5l9.5-9.5M14 10c-1-2-.5-4 1.3-5.2 1.6-1.1 3.7-.6 4.2 1',
  );

  /// Photo series: a camera.
  static const camera = CruIconData(
    'M4 8.5a2 2 0 0 1 2-2h2l1.5-2h5l1.5 2h2a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z',
    circles: [(12, 12.5, 3.5)],
  );

  /// Forms: a page with ticked lines.
  static const form = CruIconData(
    'M7.5 3.5h9a2 2 0 0 1 2 2v13a2 2 0 0 1-2 2h-9a2 2 0 0 1-2-2v-13a2 2 0 0 1 2-2z'
    'M8.5 9l1 1 2-2M13.5 9H16M8.5 14l1 1 2-2M13.5 14H16',
  );

  /// Checklist: a clipboard with a tick.
  static const checklist = CruIconData(
    'M9 4.5H7.5A2.5 2.5 0 0 0 5 7v11.5A2.5 2.5 0 0 0 7.5 21h9a2.5 2.5 0 0 0 2.5-2.5V7a2.5 2.5 0 0 0-2.5-2.5H15'
    'M9 13l2 2 4-4',
    rects: [(9, 3, 6, 3, 1.5)],
  );
}
