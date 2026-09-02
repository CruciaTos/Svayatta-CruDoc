import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:doctor_management_app/core/database/local_database.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';

/// SQLite-backed walk-in queue data source.
///
/// Follows CruDoc's local-first architecture:
/// - Reads and writes interact with SQLite directly for offline-first responsiveness.
/// - Writes are marked with `syncStatus = 'pending'` for background synchronization by
///   [FirestoreSyncService].
/// - Assigns consecutive daily token numbers atomically per doctor and calendar date.
/// - Scoped to `doctorId` to prevent multi-tenant data leakage.
class QueueLocalService {
  factory QueueLocalService({LocalDatabaseService? databaseService}) {
    if (databaseService != null) {
      return QueueLocalService._(databaseService);
    }
    return instance;
  }

  QueueLocalService._(this._databaseService);

  static final QueueLocalService instance = QueueLocalService._(
    LocalDatabaseService.instance,
  );

  QueueLocalService.withDatabase(this._databaseService);

  final LocalDatabaseService _databaseService;

  static const String tableName = 'walk_in_queue';

  final StreamController<List<QueueEntry>> _queueController =
      StreamController<List<QueueEntry>>.broadcast();

  String get _currentDoctorId => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> notifyQueueChanged() => _emitTodaysQueue();

  /// Ensures the `walk_in_queue` table and indexes exist.
  Future<void> ensureTableCreated(LocalDatabase db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        id TEXT PRIMARY KEY,
        doctorId TEXT NOT NULL DEFAULT '',
        patientId TEXT,
        walkInName TEXT,
        walkInPhone TEXT,
        tokenNumber INTEGER NOT NULL DEFAULT 0,
        queueDate TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'waiting',
        priority TEXT NOT NULL DEFAULT 'normal',
        reason TEXT,
        checkedInAt INTEGER NOT NULL,
        calledAt INTEGER,
        consultationStartedAt INTEGER,
        completedAt INTEGER,
        linkedVisitId TEXT,
        isDeleted INTEGER NOT NULL DEFAULT 0,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        syncStatus TEXT NOT NULL DEFAULT 'pending',
        pendingDelete INTEGER NOT NULL DEFAULT 0,
        lastSyncedAt INTEGER
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_walk_in_queue_doctor_date
      ON $tableName (doctorId, queueDate, isDeleted)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_walk_in_queue_status
      ON $tableName (doctorId, queueDate, status)
    ''');
  }

  /// Atomically assigns the next token number for the specified date and doctor,
  /// saves the entry into SQLite, and broadcasts the updated queue.
  Future<QueueEntry> checkIn(QueueEntry draft) async {
    final db = await _databaseService.localDatabase;
    await ensureTableCreated(db);

    final doctorId = draft.doctorId.isNotEmpty ? draft.doctorId : _currentDoctorId;
    final dateKey = draft.queueDate.isNotEmpty
        ? draft.queueDate
        : queueDateKeyFor(draft.checkedInAt);

    // Run atomically inside transaction to ensure consecutive token numbering
    final createdEntry = await db.transaction<QueueEntry>((txn) async {
      final maxTokenRows = await txn.rawQuery(
        '''
        SELECT MAX(tokenNumber) as maxToken 
        FROM $tableName 
        WHERE doctorId = ? AND queueDate = ?
        ''',
        [doctorId, dateKey],
      );

      int nextToken = 1;
      if (maxTokenRows.isNotEmpty && maxTokenRows.first['maxToken'] != null) {
        final currentMax = (maxTokenRows.first['maxToken'] as num).toInt();
        nextToken = currentMax + 1;
      }

      final entryWithToken = draft.copyWith(
        tokenNumber: nextToken,
        queueDate: dateKey,
        updatedAt: DateTime.now(),
      );

      final row = _toRow(entryWithToken, syncStatus: 'pending');
      await txn.insert(
        tableName,
        row,
        conflictAlgorithm: LocalConflictAlgorithm.replace,
      );

      return entryWithToken;
    });

    await _emitTodaysQueue();
    return createdEntry;
  }

  /// Fetches today's non-deleted queue entries for the signed-in doctor.
  Future<List<QueueEntry>> getTodaysQueue([DateTime? date]) async {
    final db = await _databaseService.localDatabase;
    await ensureTableCreated(db);

    final dateKey = queueDateKeyFor(date ?? DateTime.now());
    final doctorId = _currentDoctorId;

    final rows = await db.query(
      tableName,
      where: 'doctorId = ? AND queueDate = ? AND isDeleted = 0',
      whereArgs: [doctorId, dateKey],
      orderBy: 'tokenNumber ASC',
    );

    return rows.map(_fromRow).toList();
  }

  /// Fetches a single queue entry by [entryId].
  Future<QueueEntry?> getEntry(String entryId) async {
    final db = await _databaseService.localDatabase;
    await ensureTableCreated(db);

    final rows = await db.query(
      tableName,
      where: 'id = ?',
      whereArgs: [entryId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Updates specified fields of a queue entry and triggers a reactive broadcast.
  Future<void> updateEntry(
    String entryId,
    Map<String, dynamic> data, {
    String syncStatus = 'pending',
    bool? pendingDelete,
    int? lastSyncedAt,
  }) async {
    final db = await _databaseService.localDatabase;
    await ensureTableCreated(db);

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

    await db.update(
      tableName,
      row,
      where: 'id = ?',
      whereArgs: [entryId],
    );

    await _emitTodaysQueue();
  }

  /// Inserts or replaces a queue entry (used during Firestore sync download).
  Future<String> upsertEntry(
    QueueEntry entry, {
    String syncStatus = 'synced',
    bool pendingDelete = false,
    int? lastSyncedAt,
  }) async {
    final db = await _databaseService.localDatabase;
    await ensureTableCreated(db);

    final row = _toRow(
      entry,
      syncStatus: syncStatus,
      pendingDelete: pendingDelete,
      lastSyncedAt: lastSyncedAt,
    );

    final count = await db.update(
      tableName,
      row,
      where: 'id = ?',
      whereArgs: [entry.id],
    );

    if (count == 0) {
      await db.insert(
        tableName,
        row,
        conflictAlgorithm: LocalConflictAlgorithm.replace,
      );
    }

    await _emitTodaysQueue();
    return entry.id;
  }

  /// Soft-deletes an entry from the queue.
  Future<void> softDeleteEntry(String entryId) async {
    await updateEntry(
      entryId,
      {
        'isDeleted': true,
        'updatedAt': DateTime.now(),
      },
      pendingDelete: true,
    );
  }

  /// Streams today's active walk-in queue entries in real-time.
  Stream<List<QueueEntry>> watchTodaysQueue([DateTime? date]) {
    Future<void>.microtask(() => _emitTodaysQueue(date));
    return _queueController.stream;
  }

  Future<void> _emitTodaysQueue([DateTime? date]) async {
    if (_queueController.isClosed) return;
    try {
      final entries = await getTodaysQueue(date);
      if (!_queueController.isClosed) {
        _queueController.add(entries);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error emitting today\'s queue: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Serialization Helpers
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _toRow(
    QueueEntry entry, {
    String syncStatus = 'pending',
    bool pendingDelete = false,
    int? lastSyncedAt,
  }) {
    return {
      'id': entry.id,
      'doctorId': entry.doctorId,
      'patientId': entry.patientId,
      'walkInName': entry.walkInName,
      'walkInPhone': entry.walkInPhone,
      'tokenNumber': entry.tokenNumber,
      'queueDate': entry.queueDate,
      'status': entry.status.value,
      'priority': entry.priority.value,
      'reason': entry.reason,
      'checkedInAt': _dateTimeToMillis(entry.checkedInAt),
      'calledAt': _nullableDateTimeToMillis(entry.calledAt),
      'consultationStartedAt': _nullableDateTimeToMillis(entry.consultationStartedAt),
      'completedAt': _nullableDateTimeToMillis(entry.completedAt),
      'linkedVisitId': entry.linkedVisitId,
      'isDeleted': entry.isDeleted ? 1 : 0,
      'createdAt': _dateTimeToMillis(entry.createdAt),
      'updatedAt': _dateTimeToMillis(entry.updatedAt),
      'syncStatus': syncStatus,
      'pendingDelete': pendingDelete ? 1 : 0,
      'lastSyncedAt': lastSyncedAt,
    };
  }

  QueueEntry _fromRow(Map<String, dynamic> row) {
    return QueueEntry(
      id: row['id'] as String,
      doctorId: row['doctorId'] as String? ?? '',
      patientId: row['patientId'] as String?,
      walkInName: row['walkInName'] as String?,
      walkInPhone: row['walkInPhone'] as String?,
      tokenNumber: (row['tokenNumber'] as num?)?.toInt() ?? 0,
      queueDate: row['queueDate'] as String? ?? '',
      status: QueueStatus.fromValue(row['status'] as String?),
      priority: QueuePriority.fromValue(row['priority'] as String?),
      reason: row['reason'] as String?,
      checkedInAt: _millisToDateTime(row['checkedInAt'] as int?),
      calledAt: _nullableMillisToDateTime(row['calledAt'] as int?),
      consultationStartedAt: _nullableMillisToDateTime(
        row['consultationStartedAt'] as int?,
      ),
      completedAt: _nullableMillisToDateTime(row['completedAt'] as int?),
      linkedVisitId: row['linkedVisitId'] as String?,
      isDeleted: (row['isDeleted'] as int? ?? 0) == 1,
      createdAt: _millisToDateTime(row['createdAt'] as int?),
      updatedAt: _millisToDateTime(row['updatedAt'] as int?),
    );
  }

  Map<String, dynamic> _updateDataToRow(Map<String, dynamic> data) {
    final row = <String, dynamic>{};
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value is DateTime) {
        row[key] = _dateTimeToMillis(value);
      } else if (value is QueueStatus) {
        row[key] = value.value;
      } else if (value is QueuePriority) {
        row[key] = value.value;
      } else if (value is bool) {
        row[key] = value ? 1 : 0;
      } else {
        row[key] = value;
      }
    }
    return row;
  }

  int _dateTimeToMillis(DateTime dateTime) => dateTime.millisecondsSinceEpoch;

  int? _nullableDateTimeToMillis(DateTime? dateTime) =>
      dateTime?.millisecondsSinceEpoch;

  DateTime _millisToDateTime(int? millis) {
    if (millis == null || millis == 0) return DateTime.now();
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  DateTime? _nullableMillisToDateTime(int? millis) {
    if (millis == null || millis == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
}
