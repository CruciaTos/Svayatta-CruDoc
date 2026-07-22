import 'dart:async';

import 'package:doctor_management_app/core/errors/inventory_exceptions.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:sqflite/sqflite.dart';

/// Cap for [InventoryLocalService.watchRecentTransactions] — enough to
/// feed the dashboard's activity card after it's merged with patient/
/// visit/revenue activity and truncated further.
const int kRecentTransactionsLimit = 50;

/// SQLite-backed inventory data source.
///
/// Mirrors [PatientLocalService]: repositories read/write SQLite directly
/// for instant, offline-first UI updates, while [FirestoreSyncService]
/// picks up `syncStatus = 'pending'` rows in the background.
class InventoryLocalService {
  factory InventoryLocalService({LocalDatabaseService? databaseService}) {
    if (databaseService != null) {
      return InventoryLocalService._(databaseService);
    }
    return instance;
  }

  InventoryLocalService._(this._databaseService);

  static final InventoryLocalService instance = InventoryLocalService._(
    LocalDatabaseService.instance,
  );

  InventoryLocalService.withDatabase(this._databaseService);

  final LocalDatabaseService _databaseService;
  final StreamController<List<MedicineModel>> _medicinesController =
      StreamController<List<MedicineModel>>.broadcast();
  // Backs [watchRecentTransactions] — unlike [getTransactionsForMedicine],
  // this spans every medicine, most recent first, for the dashboard's
  // "Recent Activity" feed.
  final StreamController<List<StockTransactionModel>>
  _recentTransactionsController =
      StreamController<List<StockTransactionModel>>.broadcast();

  // ---------------------------------------------------------------------
  // Medicines CRUD
  // ---------------------------------------------------------------------

  Future<String> upsertMedicine(
    MedicineModel medicine, {
    String syncStatus = 'pending',
    bool pendingDelete = false,
    int? lastSyncedAt,
  }) async {
    final db = await _databaseService.database;
    await db.insert(
      'medicines',
      _medicineToRow(
        medicine,
        syncStatus: syncStatus,
        pendingDelete: pendingDelete,
        lastSyncedAt: lastSyncedAt,
      ),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _emitMedicines();
    return medicine.id;
  }

  Future<void> updateMedicine(
    String medicineId,
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

    await db.update(
      'medicines',
      row,
      where: 'id = ?',
      whereArgs: [medicineId],
    );
    await _emitMedicines();
  }

  Future<void> softDeleteMedicine(String medicineId) async {
    await updateMedicine(medicineId, {
      'isActive': false,
      'updatedAt': DateTime.now(),
    }, pendingDelete: true);
  }

  Future<MedicineModel?> getMedicine(String medicineId) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      'medicines',
      where: 'id = ? AND isActive = 1',
      whereArgs: [medicineId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _medicineFromRow(rows.first);
  }

  Stream<List<MedicineModel>> watchMedicines() {
    Future<void>.microtask(_emitMedicines);
    return _medicinesController.stream;
  }

  /// Streams the most recent stock transactions across every medicine,
  /// newest first, capped at [kRecentTransactionsLimit]. Powers the
  /// dashboard's "Recent Activity" card — [getTransactionsForMedicine]
  /// only covers a single medicine, which isn't enough for a feed that
  /// spans the whole inventory.
  Stream<List<StockTransactionModel>> watchRecentTransactions() {
    Future<void>.microtask(_emitRecentTransactions);
    return _recentTransactionsController.stream;
  }

  // ---------------------------------------------------------------------
  // Stock transactions
  // ---------------------------------------------------------------------

  /// Inserts [transaction] and atomically updates the parent medicine's
  /// `currentStock` in the same DB transaction, recalculating
  /// `resultingStock` from the medicine's *current* value read inside the
  /// transaction (not whatever the caller stamped on the model), so
  /// concurrent writes can't desync the audit trail.
  Future<StockTransactionModel> recordTransaction(
    StockTransactionModel transaction,
  ) async {
    final db = await _databaseService.database;
    final now = DateTime.now();

    late final StockTransactionModel recorded;

    await db.transaction((txn) async {
      final medicineRows = await txn.query(
        'medicines',
        where: 'id = ? AND isActive = 1',
        whereArgs: [transaction.medicineId],
        limit: 1,
      );
      if (medicineRows.isEmpty) {
        throw MedicineNotFoundException(
          'Medicine ${transaction.medicineId} was not found.',
        );
      }

      final currentStock =
          (medicineRows.first['currentStock'] as num?)?.toInt() ?? 0;
      final delta = _signedQuantity(transaction.type, transaction.quantity);
      final newStock = currentStock + delta;

      if (newStock < 0) {
        throw InsufficientStockException(
          'Not enough stock: only $currentStock unit(s) available.',
        );
      }

      recorded = StockTransactionModel(
        id: transaction.id,
        medicineId: transaction.medicineId,
        doctorId: transaction.doctorId,
        type: transaction.type,
        quantity: transaction.quantity,
        resultingStock: newStock,
        note: transaction.note,
        linkedVisitId: transaction.linkedVisitId,
        createdAt: transaction.createdAt,
      );

      await txn.insert(
        'stock_transactions',
        _transactionToRow(recorded),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.update(
        'medicines',
        {
          'currentStock': newStock,
          'syncStatus': 'pending',
          'updatedAt': _dateTimeToMillis(now),
        },
        where: 'id = ?',
        whereArgs: [transaction.medicineId],
      );
    });

    await _emitMedicines();
    await _emitRecentTransactions();
    return recorded;
  }

  Future<List<StockTransactionModel>> getTransactionsForMedicine(
    String medicineId,
  ) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      'stock_transactions',
      where: 'medicineId = ? AND isActive = 1',
      whereArgs: [medicineId],
      orderBy: 'createdAt DESC',
    );
    return rows.map(_transactionFromRow).toList();
  }

  /// Positive when [type] increases stock, negative when it decreases it.
  /// `adjustment` and `expired_writeoff` both decrease stock; only
  /// `restock` increases it.
  int _signedQuantity(StockTransactionType type, int quantity) {
    final magnitude = quantity.abs();
    switch (type) {
      case StockTransactionType.restock:
        return magnitude;
      case StockTransactionType.dispense:
      case StockTransactionType.adjustment:
      case StockTransactionType.expiredWriteoff:
        return -magnitude;
    }
  }

  Future<void> _emitMedicines() async {
    if (_medicinesController.isClosed) return;

    final db = await _databaseService.database;
    final rows = await db.query(
      'medicines',
      where: 'isActive = 1',
      orderBy: 'name ASC',
    );
    if (!_medicinesController.isClosed) {
      _medicinesController.add(rows.map(_medicineFromRow).toList());
    }
  }

  Future<void> _emitRecentTransactions() async {
    if (_recentTransactionsController.isClosed) return;

    final db = await _databaseService.database;
    final rows = await db.query(
      'stock_transactions',
      where: 'isActive = 1',
      orderBy: 'createdAt DESC',
      limit: kRecentTransactionsLimit,
    );
    if (!_recentTransactionsController.isClosed) {
      _recentTransactionsController.add(rows.map(_transactionFromRow).toList());
    }
  }

  // ---------------------------------------------------------------------
  // Row <-> model mapping
  // ---------------------------------------------------------------------

  Map<String, dynamic> _medicineToRow(
    MedicineModel medicine, {
    required String syncStatus,
    required bool pendingDelete,
    int? lastSyncedAt,
  }) {
    return {
      'id': medicine.id,
      'doctorId': medicine.doctorId,
      'name': medicine.name,
      'category': medicine.category,
      'unit': medicine.unit,
      'currentStock': medicine.currentStock,
      'reorderThreshold': medicine.reorderThreshold,
      'unitPrice': medicine.unitPrice,
      'supplierName': medicine.supplierName,
      'batchNumber': medicine.batchNumber,
      'expiryDate': medicine.expiryDate == null
          ? null
          : _dateTimeToMillis(medicine.expiryDate!),
      'lowStockNotifiedAt': medicine.lowStockNotifiedAt == null
          ? null
          : _dateTimeToMillis(medicine.lowStockNotifiedAt!),
      'expiryNotifiedAt': medicine.expiryNotifiedAt == null
          ? null
          : _dateTimeToMillis(medicine.expiryNotifiedAt!),
      'isActive': pendingDelete ? 0 : (medicine.isActive ? 1 : 0),
      'createdAt': _dateTimeToMillis(medicine.createdAt),
      'updatedAt': _dateTimeToMillis(medicine.updatedAt),
      'syncStatus': syncStatus,
      'pendingDelete': pendingDelete ? 1 : 0,
      'lastSyncedAt': lastSyncedAt,
    };
  }

  Map<String, dynamic> _updateDataToRow(Map<String, dynamic> data) {
    final row = <String, dynamic>{};
    for (final entry in data.entries) {
      switch (entry.key) {
        case 'createdAt':
        case 'updatedAt':
        case 'expiryDate':
        case 'lowStockNotifiedAt':
        case 'expiryNotifiedAt':
          if (entry.value == null) {
            row[entry.key] = null;
          } else if (entry.value is DateTime) {
            row[entry.key] = _dateTimeToMillis(entry.value as DateTime);
          } else if (entry.value is int) {
            row[entry.key] = entry.value;
          }
          break;
        case 'isActive':
          if (entry.value is bool) {
            row[entry.key] = entry.value as bool ? 1 : 0;
          } else if (entry.value is int) {
            row[entry.key] = entry.value;
          }
          break;
        case 'name':
        case 'category':
        case 'unit':
        case 'supplierName':
        case 'batchNumber':
        case 'doctorId':
          row[entry.key] = entry.value;
          break;
        case 'currentStock':
        case 'reorderThreshold':
          row[entry.key] = (entry.value as num).toInt();
          break;
        case 'unitPrice':
          row[entry.key] = entry.value == null
              ? null
              : (entry.value as num).toDouble();
          break;
      }
    }
    return row;
  }

  MedicineModel _medicineFromRow(Map<String, Object?> row) {
    return MedicineModel(
      id: row['id'] as String,
      doctorId: row['doctorId'] as String? ?? '',
      name: row['name'] as String? ?? '',
      category: row['category'] as String? ?? '',
      unit: row['unit'] as String? ?? '',
      currentStock: (row['currentStock'] as num?)?.toInt() ?? 0,
      reorderThreshold: (row['reorderThreshold'] as num?)?.toInt() ?? 10,
      unitPrice: (row['unitPrice'] as num?)?.toDouble(),
      supplierName: row['supplierName'] as String?,
      batchNumber: row['batchNumber'] as String?,
      expiryDate: _millisToDateTimeOrNull(row['expiryDate']),
      lowStockNotifiedAt: _millisToDateTimeOrNull(row['lowStockNotifiedAt']),
      expiryNotifiedAt: _millisToDateTimeOrNull(row['expiryNotifiedAt']),
      isActive: row['isActive'] == 1,
      createdAt: _millisToDateTime(row['createdAt']),
      updatedAt: _millisToDateTime(row['updatedAt']),
    );
  }

  Map<String, dynamic> _transactionToRow(StockTransactionModel transaction) {
    return {
      'id': transaction.id,
      'medicineId': transaction.medicineId,
      'doctorId': transaction.doctorId,
      'type': transaction.type.stored,
      'quantity': transaction.quantity,
      'resultingStock': transaction.resultingStock,
      'note': transaction.note,
      'linkedVisitId': transaction.linkedVisitId,
      'isActive': 1,
      'createdAt': _dateTimeToMillis(transaction.createdAt),
      'updatedAt': _dateTimeToMillis(transaction.createdAt),
      'syncStatus': 'pending',
      'pendingDelete': 0,
      'lastSyncedAt': null,
    };
  }

  StockTransactionModel _transactionFromRow(Map<String, Object?> row) {
    return StockTransactionModel(
      id: row['id'] as String,
      medicineId: row['medicineId'] as String? ?? '',
      doctorId: row['doctorId'] as String? ?? '',
      type: StockTransactionType.fromStored(row['type'] as String?),
      quantity: (row['quantity'] as num?)?.toInt() ?? 0,
      resultingStock: (row['resultingStock'] as num?)?.toInt() ?? 0,
      note: row['note'] as String?,
      linkedVisitId: row['linkedVisitId'] as String?,
      createdAt: _millisToDateTime(row['createdAt']),
    );
  }

  int _dateTimeToMillis(DateTime value) => value.millisecondsSinceEpoch;

  DateTime _millisToDateTime(Object? value) {
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return DateTime.now();
  }

  DateTime? _millisToDateTimeOrNull(Object? value) {
    if (value == null) return null;
    return _millisToDateTime(value);
  }
}
