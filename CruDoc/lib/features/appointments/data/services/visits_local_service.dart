import 'dart:async';

import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite-backed visit data source.
///
/// Repositories read from this service in Phase 2. Writes are stored locally
/// first and mirrored to Firestore by the repository until the Phase 3 sync
/// engine takes over retry/upload responsibility.
class VisitLocalService {
  factory VisitLocalService({LocalDatabaseService? databaseService}) {
    if (databaseService != null) {
      return VisitLocalService._(databaseService);
    }
    return instance;
  }

  VisitLocalService._(this._databaseService);

  static final VisitLocalService instance = VisitLocalService._(
    LocalDatabaseService.instance,
  );

  VisitLocalService.withDatabase(this._databaseService);

  final LocalDatabaseService _databaseService;
  final StreamController<List<Visit>> _upcomingVisitsController =
      StreamController<List<Visit>>.broadcast();
  final Map<String, StreamController<List<Visit>>> _patientVisitControllers =
      <String, StreamController<List<Visit>>>{};

  Future<String> upsertVisit(
    Visit visit, {
    String syncStatus = 'pending',
    bool pendingDelete = false,
    int? lastSyncedAt,
  }) async {
    final db = await _databaseService.database;
    await db.insert(
      'visits',
      _toRow(
        visit,
        syncStatus: syncStatus,
        pendingDelete: pendingDelete,
        lastSyncedAt: lastSyncedAt,
      ),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _emitAll();
    return visit.id;
  }

  Future<void> updateVisit(
    String visitId,
    Map<String, dynamic> data, {
    String syncStatus = 'pending',
    bool? pendingDelete,
    int? lastSyncedAt,
  }) async {
    final db = await _databaseService.database;
    final row = _updateDataToRow(data)
      ..['syncStatus'] = syncStatus
      ..['updatedAt'] = _dateTimeToMillis(
        data['updatedAt'] is DateTime
            ? data['updatedAt'] as DateTime
            : DateTime.now(),
      );

    if (pendingDelete != null) {
      row['pendingDelete'] = pendingDelete ? 1 : 0;
    }
    if (lastSyncedAt != null) {
      row['lastSyncedAt'] = lastSyncedAt;
    }

    await db.update('visits', row, where: 'id = ?', whereArgs: [visitId]);
    await _emitAll();
  }

  Future<Visit?> getVisit(String visitId) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      'visits',
      where: 'id = ? AND isActive = 1',
      whereArgs: [visitId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Stream<List<Visit>> watchUpcomingVisits({DateTime? from}) {
    Future<void>.microtask(() => _emitUpcomingVisits(from: from));
    return _upcomingVisitsController.stream;
  }

  Stream<List<Visit>> watchVisitsForPatient(
    String patientId, {
    bool includeDeleted = false,
  }) {
    final key = _patientStreamKey(patientId, includeDeleted: includeDeleted);
    final controller = _patientVisitControllers.putIfAbsent(
      key,
      () => StreamController<List<Visit>>.broadcast(),
    );
    Future<void>.microtask(
      () => _emitVisitsForPatient(patientId, includeDeleted: includeDeleted),
    );
    return controller.stream;
  }

  Future<List<Visit>> findOverlapping({
    required DateTime start,
    required DateTime end,
    String? excludeVisitId,
  }) async {
    final db = await _databaseService.database;
    final lookbackStart = start.subtract(
      const Duration(minutes: kMaxVisitDurationMinutes),
    );
    final rows = await db.query(
      'visits',
      where: 'isActive = 1 AND scheduledStart >= ? AND scheduledStart < ?',
      whereArgs: [_dateTimeToMillis(lookbackStart), _dateTimeToMillis(end)],
      orderBy: 'scheduledStart ASC',
    );

    final overlapping = rows.map(_fromRow).where((visit) {
      if (visit.id == excludeVisitId) return false;
      if (visit.isDeleted) return false;
      if (visit.status != VisitStatus.scheduled) return false;
      return visit.scheduledStart.isBefore(end) &&
          start.isBefore(visit.scheduledEnd);
    }).toList()..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));

    return overlapping;
  }

  Future<void> markSynced(String visitId, {DateTime? syncedAt}) async {
    final db = await _databaseService.database;
    await db.update(
      'visits',
      {
        'syncStatus': 'synced',
        'pendingDelete': 0,
        'lastSyncedAt': _dateTimeToMillis(syncedAt ?? DateTime.now()),
      },
      where: 'id = ?',
      whereArgs: [visitId],
    );
    await _emitAll();
  }

  Future<void> _emitAll() async {
    await _emitUpcomingVisits();
    for (final key in _patientVisitControllers.keys) {
      final parsed = _parsePatientStreamKey(key);
      await _emitVisitsForPatient(
        parsed.patientId,
        includeDeleted: parsed.includeDeleted,
      );
    }
  }

  Future<void> _emitUpcomingVisits({DateTime? from}) async {
    if (_upcomingVisitsController.isClosed) return;

    final db = await _databaseService.database;
    final start = from ?? DateTime.now();
    final rows = await db.query(
      'visits',
      where:
          'isActive = 1 AND isDeleted = 0 AND status = ? AND scheduledStart >= ?',
      whereArgs: [VisitStatus.scheduled.value, _dateTimeToMillis(start)],
      orderBy: 'scheduledStart ASC',
    );
    if (!_upcomingVisitsController.isClosed) {
      _upcomingVisitsController.add(rows.map(_fromRow).toList());
    }
  }

  Future<void> _emitVisitsForPatient(
    String patientId, {
    required bool includeDeleted,
  }) async {
    final key = _patientStreamKey(patientId, includeDeleted: includeDeleted);
    final controller = _patientVisitControllers[key];
    if (controller == null || controller.isClosed) return;

    final db = await _databaseService.database;
    final rows = await db.query(
      'visits',
      where: includeDeleted
          ? 'isActive = 1 AND patientId = ?'
          : 'isActive = 1 AND patientId = ? AND isDeleted = 0',
      whereArgs: [patientId],
      orderBy: 'scheduledStart DESC',
    );
    if (!controller.isClosed) {
      controller.add(rows.map(_fromRow).toList());
    }
  }

  Map<String, dynamic> _toRow(
    Visit visit, {
    required String syncStatus,
    required bool pendingDelete,
    int? lastSyncedAt,
  }) {
    return {
      'id': visit.id,
      'patientId': visit.patientId,
      'scheduledStart': _dateTimeToMillis(visit.scheduledStart),
      'durationMinutes': visit.durationMinutes,
      'address': visit.address,
      'latitude': visit.latitude,
      'longitude': visit.longitude,
      'status': visit.status.value,
      'isDeleted': visit.isDeleted ? 1 : 0,
      'isActive': pendingDelete ? 0 : 1,
      'invoiceId': visit.invoiceId,
      'packageId': visit.packageId,
      'treatmentType': visit.treatmentType,
      'therapistNotes': visit.therapistNotes,
      'reminderStatus': visit.reminderStatus,
      'calendarEventId': visit.calendarEventId,
      'createdAt': _dateTimeToMillis(visit.createdAt),
      'updatedAt': _dateTimeToMillis(visit.updatedAt),
      'syncStatus': syncStatus,
      'pendingDelete': pendingDelete ? 1 : 0,
      'lastSyncedAt': lastSyncedAt,
    };
  }

  Map<String, dynamic> _updateDataToRow(Map<String, dynamic> data) {
    final row = <String, dynamic>{};
    for (final entry in data.entries) {
      switch (entry.key) {
        case 'scheduledStart':
        case 'createdAt':
        case 'updatedAt':
          if (entry.value is DateTime) {
            row[entry.key] = _dateTimeToMillis(entry.value as DateTime);
          } else if (entry.value is int) {
            row[entry.key] = entry.value;
          }
          break;
        case 'durationMinutes':
          row[entry.key] = (entry.value as num).toInt();
          break;
        case 'latitude':
        case 'longitude':
          row[entry.key] = entry.value == null
              ? null
              : (entry.value as num).toDouble();
          break;
        case 'isDeleted':
        case 'isActive':
          if (entry.value is bool) {
            row[entry.key] = entry.value as bool ? 1 : 0;
          } else if (entry.value is int) {
            row[entry.key] = entry.value;
          }
          break;
        case 'patientId':
        case 'address':
        case 'status':
        case 'invoiceId':
        case 'packageId':
        case 'treatmentType':
        case 'therapistNotes':
        case 'reminderStatus':
        case 'calendarEventId':
          row[entry.key] = entry.value;
          break;
      }
    }
    return row;
  }

  Visit _fromRow(Map<String, Object?> row) {
    return Visit(
      id: row['id'] as String,
      patientId: row['patientId'] as String? ?? '',
      scheduledStart: _millisToDateTime(row['scheduledStart']),
      durationMinutes: (row['durationMinutes'] as num?)?.toInt() ?? 30,
      address: row['address'] as String? ?? '',
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
      status: VisitStatus.fromValue(row['status'] as String?),
      isDeleted: row['isDeleted'] == 1,
      invoiceId: row['invoiceId'] as String?,
      packageId: row['packageId'] as String?,
      treatmentType: row['treatmentType'] as String?,
      therapistNotes: row['therapistNotes'] as String?,
      reminderStatus: row['reminderStatus'] as String?,
      calendarEventId: row['calendarEventId'] as String?,
      createdAt: _millisToDateTime(row['createdAt']),
      updatedAt: _millisToDateTime(row['updatedAt']),
    );
  }

  String _patientStreamKey(String patientId, {required bool includeDeleted}) =>
      '$patientId|$includeDeleted';

  ({String patientId, bool includeDeleted}) _parsePatientStreamKey(String key) {
    final separatorIndex = key.lastIndexOf('|');
    if (separatorIndex == -1) {
      return (patientId: key, includeDeleted: false);
    }
    return (
      patientId: key.substring(0, separatorIndex),
      includeDeleted: key.substring(separatorIndex + 1) == 'true',
    );
  }

  int _dateTimeToMillis(DateTime value) => value.millisecondsSinceEpoch;

  DateTime _millisToDateTime(Object? value) {
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return DateTime.now();
  }
}