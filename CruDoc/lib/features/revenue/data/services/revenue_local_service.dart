import 'dart:async';

import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite-backed revenue data source.
///
/// Backs both the `revenue_entries` and `pending_payments` tables — kept
/// in one service since `RevenueRepository.markPendingPaymentAsPaid`
/// writes to both in a single logical operation. Repositories read from
/// this service in Phase 2; writes are stored locally first and mirrored
/// to Firestore by the Phase 3 sync engine.
class RevenueLocalService {
  factory RevenueLocalService({LocalDatabaseService? databaseService}) {
    if (databaseService != null) {
      return RevenueLocalService._(databaseService);
    }
    return instance;
  }

  RevenueLocalService._(this._databaseService);

  static final RevenueLocalService instance = RevenueLocalService._(
    LocalDatabaseService.instance,
  );

  RevenueLocalService.withDatabase(this._databaseService);

  final LocalDatabaseService _databaseService;
  final StreamController<List<RevenueEntry>> _revenueEntriesController =
      StreamController<List<RevenueEntry>>.broadcast();
  final StreamController<List<PendingPayment>> _pendingPaymentsController =
      StreamController<List<PendingPayment>>.broadcast();

  // ---------------- revenue entries ----------------

  Future<String> upsertRevenueEntry(
    RevenueEntry entry, {
    String syncStatus = 'pending',
    bool pendingDelete = false,
    int? lastSyncedAt,
  }) async {
    final db = await _databaseService.database;
    await db.insert(
      'revenue_entries',
      _revenueEntryToRow(
        entry,
        syncStatus: syncStatus,
        pendingDelete: pendingDelete,
        lastSyncedAt: lastSyncedAt,
      ),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _emitRevenueEntries();
    return entry.id;
  }

  Future<void> updateRevenueEntry(
    String entryId,
    Map<String, dynamic> data, {
    String syncStatus = 'pending',
    bool? pendingDelete,
    int? lastSyncedAt,
  }) async {
    final db = await _databaseService.database;
    final row = _revenueEntryUpdateToRow(data)
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
      'revenue_entries',
      row,
      where: 'id = ?',
      whereArgs: [entryId],
    );
    await _emitRevenueEntries();
  }

  Future<void> softDeleteRevenueEntry(String entryId) async {
    await updateRevenueEntry(entryId, {
      'isDeleted': true,
      'updatedAt': DateTime.now(),
    }, pendingDelete: true);
  }

  Future<RevenueEntry?> getRevenueEntry(String entryId) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      'revenue_entries',
      where: 'id = ? AND isActive = 1',
      whereArgs: [entryId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _revenueEntryFromRow(rows.first);
  }

  /// Streams active (non-deleted) revenue entries, most recent first.
  Stream<List<RevenueEntry>> watchRevenueEntries() {
    Future<void>.microtask(_emitRevenueEntries);
    return _revenueEntriesController.stream;
  }

  Future<void> markRevenueEntrySynced(
    String entryId, {
    DateTime? syncedAt,
  }) async {
    final db = await _databaseService.database;
    await db.update(
      'revenue_entries',
      {
        'syncStatus': 'synced',
        'pendingDelete': 0,
        'lastSyncedAt': _dateTimeToMillis(syncedAt ?? DateTime.now()),
      },
      where: 'id = ?',
      whereArgs: [entryId],
    );
    await _emitRevenueEntries();
  }

  // ---------------- pending payments ----------------

  Future<String> upsertPendingPayment(
    PendingPayment payment, {
    String syncStatus = 'pending',
    bool pendingDelete = false,
    int? lastSyncedAt,
  }) async {
    final db = await _databaseService.database;
    await db.insert(
      'pending_payments',
      _pendingPaymentToRow(
        payment,
        syncStatus: syncStatus,
        pendingDelete: pendingDelete,
        lastSyncedAt: lastSyncedAt,
      ),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _emitPendingPayments();
    return payment.id;
  }

  Future<void> updatePendingPayment(
    String paymentId,
    Map<String, dynamic> data, {
    String syncStatus = 'pending',
    bool? pendingDelete,
    int? lastSyncedAt,
  }) async {
    final db = await _databaseService.database;
    final row = _pendingPaymentUpdateToRow(data)
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
      'pending_payments',
      row,
      where: 'id = ?',
      whereArgs: [paymentId],
    );
    await _emitPendingPayments();
  }

  Future<PendingPayment?> getPendingPayment(String paymentId) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      'pending_payments',
      where: 'id = ? AND isActive = 1',
      whereArgs: [paymentId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _pendingPaymentFromRow(rows.first);
  }

  /// Streams still-unpaid pending payments, most recent first.
  Stream<List<PendingPayment>> watchPendingPayments() {
    Future<void>.microtask(_emitPendingPayments);
    return _pendingPaymentsController.stream;
  }

  Future<void> markPendingPaymentSynced(
    String paymentId, {
    DateTime? syncedAt,
  }) async {
    final db = await _databaseService.database;
    await db.update(
      'pending_payments',
      {
        'syncStatus': 'synced',
        'pendingDelete': 0,
        'lastSyncedAt': _dateTimeToMillis(syncedAt ?? DateTime.now()),
      },
      where: 'id = ?',
      whereArgs: [paymentId],
    );
    await _emitPendingPayments();
  }

  // ---------------- internal: emit ----------------

  Future<void> _emitRevenueEntries() async {
    if (_revenueEntriesController.isClosed) return;

    final db = await _databaseService.database;
    final rows = await db.query(
      'revenue_entries',
      where: 'isActive = 1 AND isDeleted = 0',
      orderBy: 'date DESC',
    );
    if (!_revenueEntriesController.isClosed) {
      _revenueEntriesController.add(rows.map(_revenueEntryFromRow).toList());
    }
  }

  Future<void> _emitPendingPayments() async {
    if (_pendingPaymentsController.isClosed) return;

    final db = await _databaseService.database;
    final rows = await db.query(
      'pending_payments',
      where: 'isActive = 1 AND isPaid = 0',
      orderBy: 'date DESC',
    );
    if (!_pendingPaymentsController.isClosed) {
      _pendingPaymentsController.add(
        rows.map(_pendingPaymentFromRow).toList(),
      );
    }
  }

  // ---------------- internal: row <-> model ----------------

  Map<String, dynamic> _revenueEntryToRow(
    RevenueEntry entry, {
    required String syncStatus,
    required bool pendingDelete,
    int? lastSyncedAt,
  }) {
    return {
      'id': entry.id,
      'date': _dateTimeToMillis(entry.date),
      'description': entry.description,
      'amount': entry.amount,
      'type': entry.type.value,
      'kind': entry.kind.value,
      'payer': entry.payer,
      'patientId': entry.patientId,
      'visitId': entry.visitId,
      'isDeleted': entry.isDeleted ? 1 : 0,
      'isActive': pendingDelete ? 0 : 1,
      'createdAt': _dateTimeToMillis(entry.createdAt),
      'updatedAt': _dateTimeToMillis(entry.updatedAt),
      'syncStatus': syncStatus,
      'pendingDelete': pendingDelete ? 1 : 0,
      'lastSyncedAt': lastSyncedAt,
    };
  }

  Map<String, dynamic> _revenueEntryUpdateToRow(Map<String, dynamic> data) {
    final row = <String, dynamic>{};
    for (final entry in data.entries) {
      switch (entry.key) {
        case 'date':
        case 'createdAt':
        case 'updatedAt':
          if (entry.value is DateTime) {
            row[entry.key] = _dateTimeToMillis(entry.value as DateTime);
          } else if (entry.value is int) {
            row[entry.key] = entry.value;
          }
          break;
        case 'amount':
          row[entry.key] = (entry.value as num).toDouble();
          break;
        case 'isDeleted':
        case 'isActive':
          if (entry.value is bool) {
            row[entry.key] = entry.value as bool ? 1 : 0;
          } else if (entry.value is int) {
            row[entry.key] = entry.value;
          }
          break;
        case 'description':
        case 'payer':
        case 'patientId':
        case 'visitId':
          row[entry.key] = entry.value;
          break;
        case 'type':
          row[entry.key] = entry.value is RevenueType
              ? (entry.value as RevenueType).value
              : entry.value;
          break;
        case 'kind':
          row[entry.key] = entry.value is TransactionKind
              ? (entry.value as TransactionKind).value
              : entry.value;
          break;
      }
    }
    return row;
  }

  RevenueEntry _revenueEntryFromRow(Map<String, Object?> row) {
    return RevenueEntry(
      id: row['id'] as String,
      date: _millisToDateTime(row['date']),
      description: row['description'] as String? ?? '',
      amount: (row['amount'] as num?)?.toDouble() ?? 0,
      type: RevenueType.fromValue(row['type'] as String?),
      kind: TransactionKind.fromValue(row['kind'] as String?),
      payer: row['payer'] as String?,
      patientId: row['patientId'] as String?,
      visitId: row['visitId'] as String?,
      isDeleted: row['isDeleted'] == 1,
      createdAt: _millisToDateTime(row['createdAt']),
      updatedAt: _millisToDateTime(row['updatedAt']),
    );
  }

  Map<String, dynamic> _pendingPaymentToRow(
    PendingPayment payment, {
    required String syncStatus,
    required bool pendingDelete,
    int? lastSyncedAt,
  }) {
    return {
      'id': payment.id,
      'date': _dateTimeToMillis(payment.date),
      'description': payment.description,
      'amount': payment.amount,
      'isPaid': payment.isPaid ? 1 : 0,
      'payer': payment.payer,
      'patientId': payment.patientId,
      'visitId': payment.visitId,
      'notes': payment.notes,
      'isActive': pendingDelete ? 0 : 1,
      'createdAt': _dateTimeToMillis(payment.createdAt),
      'updatedAt': _dateTimeToMillis(payment.updatedAt),
      'syncStatus': syncStatus,
      'pendingDelete': pendingDelete ? 1 : 0,
      'lastSyncedAt': lastSyncedAt,
    };
  }

  Map<String, dynamic> _pendingPaymentUpdateToRow(Map<String, dynamic> data) {
    final row = <String, dynamic>{};
    for (final entry in data.entries) {
      switch (entry.key) {
        case 'date':
        case 'createdAt':
        case 'updatedAt':
          if (entry.value is DateTime) {
            row[entry.key] = _dateTimeToMillis(entry.value as DateTime);
          } else if (entry.value is int) {
            row[entry.key] = entry.value;
          }
          break;
        case 'amount':
          row[entry.key] = (entry.value as num).toDouble();
          break;
        case 'isPaid':
        case 'isActive':
          if (entry.value is bool) {
            row[entry.key] = entry.value as bool ? 1 : 0;
          } else if (entry.value is int) {
            row[entry.key] = entry.value;
          }
          break;
        case 'description':
        case 'payer':
        case 'patientId':
        case 'visitId':
        case 'notes':
          row[entry.key] = entry.value;
          break;
      }
    }
    return row;
  }

  PendingPayment _pendingPaymentFromRow(Map<String, Object?> row) {
    return PendingPayment(
      id: row['id'] as String,
      date: _millisToDateTime(row['date']),
      description: row['description'] as String? ?? '',
      amount: (row['amount'] as num?)?.toDouble() ?? 0,
      isPaid: row['isPaid'] == 1,
      payer: row['payer'] as String?,
      patientId: row['patientId'] as String?,
      visitId: row['visitId'] as String?,
      notes: row['notes'] as String?,
      createdAt: _millisToDateTime(row['createdAt']),
      updatedAt: _millisToDateTime(row['updatedAt']),
    );
  }

  /// Fetches the pending payment linked to [visitId], if one exists —
  /// regardless of whether it's already been marked paid. Used by
  /// `RevenueRepository.getPendingPaymentForVisit` so
  /// `VisitRepository.updateStatus` can tell whether a visitation
  /// already has a pending payment before creating another one.
  Future<PendingPayment?> getPendingPaymentForVisit(String visitId) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      'pending_payments',
      where: 'visitId = ? AND isActive = 1',
      whereArgs: [visitId],
      orderBy: 'createdAt DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _pendingPaymentFromRow(rows.first);
  }

  int _dateTimeToMillis(DateTime value) => value.millisecondsSinceEpoch;

  DateTime _millisToDateTime(Object? value) {
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return DateTime.now();
  }
}