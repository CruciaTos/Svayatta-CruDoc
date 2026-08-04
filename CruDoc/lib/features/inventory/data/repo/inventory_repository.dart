import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/errors/inventory_exceptions.dart';
import 'package:doctor_management_app/core/services/firestore_sync_service.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/data/services/inventory_local_service.dart';

/// Clean API the presentation layer talks to for anything inventory-related.
class InventoryRepository {
  InventoryRepository({
    InventoryLocalService? localService,
    FirestoreSyncService? syncService,
  }) : _localService = localService ?? InventoryLocalService(),
       _syncService = syncService ?? FirestoreSyncService.instance;

  final InventoryLocalService _localService;
  final FirestoreSyncService _syncService;

  /// The signed-in doctor's UID — see PatientRepository for why this
  /// matters. Authoritative regardless of what a caller passes in below
  /// (createMedicine/recordTransaction previously trusted a caller-supplied
  /// `doctorId`, which could be left blank).
  String get _currentDoctorId {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('No signed-in doctor — cannot access inventory data.');
    }
    return uid;
  }

  /// Creates a new medicine and returns the newly assigned id.
  Future<String> createMedicine(MedicineModel medicine) async {
    _validate(medicine);

    final now = DateTime.now();
    final id = medicine.id.trim().isEmpty ? const Uuid().v4() : medicine.id;
    final medicineWithId = MedicineModel(
      id: id,
      doctorId: _currentDoctorId,
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

    if (kIsWeb) {
      await FirebaseFirestore.instance
          .collection('medicines')
          .doc(id)
          .set(medicineWithId.toJson());
      return id;
    }

    await _localService.upsertMedicine(medicineWithId);
    unawaited(_syncService.triggerPostWriteSync());
    return id;
  }

  /// Streams the live list of active medicines.
  Stream<List<MedicineModel>> watchMedicines() {
    if (kIsWeb) {
      return FirebaseFirestore.instance
          .collection('medicines')
          .where('doctorId', isEqualTo: _currentDoctorId)
          .snapshots()
          .map((snapshot) {
        final list = snapshot.docs
            .map((doc) => MedicineModel.fromJson({...doc.data(), 'id': doc.id}))
            .where((m) => m.isActive)
            .toList();
        list.sort((a, b) => a.name.compareTo(b.name));
        return list;
      });
    }
    return _localService.watchMedicines();
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

    if (kIsWeb) {
      final firestoreData = Map<String, dynamic>.from(data)
        ..['updatedAt'] = FieldValue.serverTimestamp();
      if (firestoreData.containsKey('expiryDate') && firestoreData['expiryDate'] is DateTime) {
        firestoreData['expiryDate'] = Timestamp.fromDate(firestoreData['expiryDate'] as DateTime);
      }
      if (firestoreData.containsKey('lowStockNotifiedAt') && firestoreData['lowStockNotifiedAt'] is DateTime) {
        firestoreData['lowStockNotifiedAt'] = Timestamp.fromDate(firestoreData['lowStockNotifiedAt'] as DateTime);
      }
      if (firestoreData.containsKey('expiryNotifiedAt') && firestoreData['expiryNotifiedAt'] is DateTime) {
        firestoreData['expiryNotifiedAt'] = Timestamp.fromDate(firestoreData['expiryNotifiedAt'] as DateTime);
      }
      await FirebaseFirestore.instance
          .collection('medicines')
          .doc(medicineId)
          .update(firestoreData);
      return;
    }

    final localData = Map<String, dynamic>.from(data)
      ..['updatedAt'] = DateTime.now();

    await _localService.updateMedicine(medicineId, localData);
    unawaited(_syncService.triggerPostWriteSync());
  }

  /// Soft-deletes a medicine locally, then mirrors the delete to Firestore.
  Future<void> deleteMedicine(String medicineId) async {
    if (kIsWeb) {
      await FirebaseFirestore.instance
          .collection('medicines')
          .doc(medicineId)
          .update({
        'isActive': false,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      return;
    }
    await _localService.softDeleteMedicine(medicineId);
    unawaited(_syncService.triggerPostWriteSync());
  }

  /// Fetches a single medicine by id.
  Future<MedicineModel?> getMedicine(String medicineId) async {
    if (kIsWeb) {
      final doc = await FirebaseFirestore.instance
          .collection('medicines')
          .doc(medicineId)
          .get();
      if (!doc.exists) return null;
      return MedicineModel.fromFirestore(doc);
    }
    return _localService.getMedicine(medicineId);
  }

  /// Records a restock/dispense/adjustment/write-off transaction and
  /// applies it to the medicine's current stock atomically.
  Future<StockTransactionModel> recordTransaction({
    required String medicineId,
    required StockTransactionType type,
    required int quantity,
    String? note,
    String? linkedVisitId,
  }) async {
    if (quantity <= 0) {
      throw const MedicineValidationException('Quantity must be positive.');
    }

    if (kIsWeb) {
      final now = DateTime.now();
      final txId = const Uuid().v4();
      late final StockTransactionModel recorded;

      await FirebaseFirestore.instance.runTransaction((txn) async {
        final medRef = FirebaseFirestore.instance.collection('medicines').doc(medicineId);
        final medDoc = await txn.get(medRef);
        if (!medDoc.exists) {
          throw MedicineNotFoundException('Medicine $medicineId was not found.');
        }
        final medData = medDoc.data() ?? {};
        final isActive = medData['isActive'] as bool? ?? true;
        if (!isActive) {
          throw MedicineNotFoundException('Medicine $medicineId was not found.');
        }

        final currentStock = (medData['currentStock'] as num?)?.toInt() ?? 0;
        final magnitude = quantity.abs();
        int delta;
        switch (type) {
          case StockTransactionType.restock:
            delta = magnitude;
            break;
          case StockTransactionType.dispense:
          case StockTransactionType.adjustment:
          case StockTransactionType.expiredWriteoff:
            delta = -magnitude;
            break;
        }

        final newStock = currentStock + delta;
        if (newStock < 0) {
          throw InsufficientStockException('Not enough stock: only $currentStock unit(s) available.');
        }

        recorded = StockTransactionModel(
          id: txId,
          medicineId: medicineId,
          doctorId: _currentDoctorId,
          type: type,
          quantity: quantity,
          resultingStock: newStock,
          note: note,
          linkedVisitId: linkedVisitId,
          createdAt: now,
        );

        final txRef = FirebaseFirestore.instance.collection('stock_transactions').doc(txId);
        txn.set(txRef, recorded.toJson());
        txn.update(medRef, {
          'currentStock': newStock,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      return recorded;
    }

    final transaction = StockTransactionModel(
      id: const Uuid().v4(),
      medicineId: medicineId,
      doctorId: _currentDoctorId,
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
  ) async {
    if (kIsWeb) {
      final snapshot = await FirebaseFirestore.instance
          .collection('stock_transactions')
          .where('medicineId', isEqualTo: medicineId)
          .where('doctorId', isEqualTo: _currentDoctorId)
          .orderBy('createdAt', descending: true)
          .get();
      return snapshot.docs
          .where((doc) => doc.data()['isActive'] as bool? ?? true)
          .map((doc) => StockTransactionModel.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
    }
    return _localService.getTransactionsForMedicine(medicineId);
  }

  /// Streams the most recent stock transactions across every medicine,
  /// newest first. Powers the dashboard's "Recent Activity" card.
  Stream<List<StockTransactionModel>> watchRecentTransactions() {
    if (kIsWeb) {
      return FirebaseFirestore.instance
          .collection('stock_transactions')
          .where('doctorId', isEqualTo: _currentDoctorId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs
            .map((doc) => StockTransactionModel.fromJson({...doc.data(), 'id': doc.id}))
            .toList();
      });
    }
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
