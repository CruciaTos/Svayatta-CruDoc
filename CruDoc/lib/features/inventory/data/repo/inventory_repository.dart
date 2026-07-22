import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/errors/inventory_exceptions.dart';
import 'package:doctor_management_app/core/services/firestore_sync_service.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/data/services/inventory_local_service.dart';

/// Clean API the presentation layer talks to for anything inventory-related.
///
/// Reads and writes go through SQLite. Writes are marked pending locally and
/// the central sync engine is triggered in the background. Mirrors
/// [PatientRepository]'s offline-first pattern.
class InventoryRepository {
  InventoryRepository({
    InventoryLocalService? localService,
    FirestoreSyncService? syncService,
  }) : _localService = localService ?? InventoryLocalService(),
       _syncService = syncService ?? FirestoreSyncService.instance;

  final InventoryLocalService _localService;
  final FirestoreSyncService _syncService;

  /// Creates a new medicine and returns the newly assigned id.
  Future<String> createMedicine(MedicineModel medicine) async {
    _validate(medicine);

    final now = DateTime.now();
    final id = medicine.id.trim().isEmpty ? const Uuid().v4() : medicine.id;
    final medicineWithId = MedicineModel(
      id: id,
      doctorId: medicine.doctorId,
      name: medicine.name.trim(),
      category: medicine.category.trim(),
      unit: medicine.unit.trim(),
      currentStock: medicine.currentStock,
      reorderThreshold: medicine.reorderThreshold,
      unitPrice: medicine.unitPrice,
      supplierName: medicine.supplierName,
      batchNumber: medicine.batchNumber,
      expiryDate: medicine.expiryDate,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );

    await _localService.upsertMedicine(medicineWithId);
    unawaited(_syncService.triggerPostWriteSync());
    return id;
  }

  /// Updates an existing medicine's fields.
  Future<void> updateMedicine(
    String medicineId,
    Map<String, dynamic> data,
  ) async {
    if (data.containsKey('name')) {
      final name = data['name'] as String? ?? '';
      if (name.trim().isEmpty) {
        throw const MedicineValidationException(
          'Medicine name cannot be empty.',
        );
      }
    }
    if (data.containsKey('reorderThreshold')) {
      final threshold = (data['reorderThreshold'] as num?) ?? 0;
      if (threshold < 0) {
        throw const MedicineValidationException(
          'Reorder threshold cannot be negative.',
        );
      }
    }

    final localData = Map<String, dynamic>.from(data)
      ..['updatedAt'] = DateTime.now();

    await _localService.updateMedicine(medicineId, localData);
    unawaited(_syncService.triggerPostWriteSync());
  }

  /// Soft-deletes a medicine locally, then mirrors the delete to Firestore.
  Future<void> deleteMedicine(String medicineId) async {
    await _localService.softDeleteMedicine(medicineId);
    unawaited(_syncService.triggerPostWriteSync());
  }

  /// Fetches a single medicine by id.
  Future<MedicineModel?> getMedicine(String medicineId) {
    return _localService.getMedicine(medicineId);
  }

  /// Streams the live list of active medicines.
  Stream<List<MedicineModel>> watchMedicines() {
    return _localService.watchMedicines();
  }

  /// Records a restock/dispense/adjustment/write-off transaction and
  /// applies it to the medicine's current stock atomically.
  Future<StockTransactionModel> recordTransaction({
    required String medicineId,
    required StockTransactionType type,
    required int quantity,
    String? note,
    String? linkedVisitId,
    String doctorId = '',
  }) async {
    if (quantity <= 0) {
      throw const MedicineValidationException('Quantity must be positive.');
    }

    final transaction = StockTransactionModel(
      id: const Uuid().v4(),
      medicineId: medicineId,
      doctorId: doctorId,
      type: type,
      quantity: quantity,
      resultingStock: 0, // recalculated inside the local service's txn
      note: note,
      linkedVisitId: linkedVisitId,
      createdAt: DateTime.now(),
    );

    final recorded = await _localService.recordTransaction(transaction);
    unawaited(_syncService.triggerPostWriteSync());
    return recorded;
  }

  /// Streams the full transaction history for a single medicine, newest
  /// first.
  Future<List<StockTransactionModel>> getTransactionsForMedicine(
    String medicineId,
  ) {
    return _localService.getTransactionsForMedicine(medicineId);
  }

  /// Streams the most recent stock transactions across every medicine,
  /// newest first. Powers the dashboard's "Recent Activity" card.
  Stream<List<StockTransactionModel>> watchRecentTransactions() {
    return _localService.watchRecentTransactions();
  }

  /// Stamps `lowStockNotifiedAt` on a medicine so the low-stock alert
  /// doesn't refire on every rebuild. Does not trigger a new sync-worthy
  /// "pending" bump beyond the normal update path.
  Future<void> markLowStockNotified(String medicineId) {
    return updateMedicine(medicineId, {
      'lowStockNotifiedAt': DateTime.now(),
    });
  }

  /// Stamps `expiryNotifiedAt` on a medicine so the expiry alert doesn't
  /// refire on every rebuild.
  Future<void> markExpiryNotified(String medicineId) {
    return updateMedicine(medicineId, {'expiryNotifiedAt': DateTime.now()});
  }

  void _validate(MedicineModel medicine) {
    if (medicine.name.trim().isEmpty) {
      throw const MedicineValidationException('Medicine name cannot be empty.');
    }
    if (medicine.unit.trim().isEmpty) {
      throw const MedicineValidationException('Unit cannot be empty.');
    }
    if (medicine.reorderThreshold < 0) {
      throw const MedicineValidationException(
        'Reorder threshold cannot be negative.',
      );
    }
    if (medicine.currentStock < 0) {
      throw const MedicineValidationException(
        'Current stock cannot be negative.',
      );
    }
  }
}
