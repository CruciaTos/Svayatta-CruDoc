import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/database/local_database.dart';
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
    }, conflictAlgorithm: LocalConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    final db = await _db.localDatabase;
    await db.update(
      'dental_records',
      {'isDeleted': 1, 'updatedAt': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Completed procedures since [since], for recall suggestions.
  Future<List<({String patientId, String name, DateTime at})>>
  completedProcedures(String doctorId, DateTime since) async {
    final db = await _db.localDatabase;
    final rows = await db.query(
      'procedure_log_entries',
      columns: ['patientId', 'procedureName', 'performedAt'],
      where:
          "doctorId = ? AND isDeleted = 0 AND status = 'completed' AND performedAt >= ?",
      whereArgs: [doctorId, since.millisecondsSinceEpoch],
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

/// One patient's records of a kind, newest first.
final patientRecordsProvider =
    FutureProvider.family<List<DentalRecord>, RecKey>((ref, k) {
      final doctorId = ref.watch(dentalDoctorIdProvider);
      return ref
          .watch(dentalRecordsRepoProvider)
          .forPatient(doctorId, k.patientId, k.kind);
    });

/// Every record of a kind in the clinic, newest first.
final clinicRecordsProvider = FutureProvider.family<List<DentalRecord>, String>(
  (ref, kind) {
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
    ..showSnackBar(
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

  /// Checklist: a clipboard with a tick.
  static const checklist = CruIconData(
    'M9 4.5H7.5A2.5 2.5 0 0 0 5 7v11.5A2.5 2.5 0 0 0 7.5 21h9a2.5 2.5 0 0 0 2.5-2.5V7a2.5 2.5 0 0 0-2.5-2.5H15'
    'M9 13l2 2 4-4',
    rects: [(9, 3, 6, 3, 1.5)],
  );
}
