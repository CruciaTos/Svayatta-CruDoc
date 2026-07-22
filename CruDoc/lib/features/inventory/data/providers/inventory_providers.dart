import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/data/repo/inventory_repository.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => InventoryRepository(),
);

/// Streams every active medicine for the current doctor.
final medicinesStreamProvider = StreamProvider<List<MedicineModel>>(
  (ref) => ref.watch(inventoryRepositoryProvider).watchMedicines(),
);

/// Streams the most recent stock transactions across every medicine,
/// newest first. Feeds the dashboard's "Recent Activity" card.
final recentStockTransactionsProvider =
    StreamProvider<List<StockTransactionModel>>(
      (ref) => ref.watch(inventoryRepositoryProvider).watchRecentTransactions(),
    );

/// Medicines whose `currentStock` has crossed at/under their configured
/// `reorderThreshold`.
final lowStockMedicinesProvider = Provider<AsyncValue<List<MedicineModel>>>((
  ref,
) {
  final medicinesAsync = ref.watch(medicinesStreamProvider);
  return medicinesAsync.whenData(
    (medicines) => medicines.where((m) => m.isLowStock).toList(),
  );
});

/// Medicines within 30 days of (or past) their expiry date.
final expiringMedicinesProvider = Provider<AsyncValue<List<MedicineModel>>>((
  ref,
) {
  final medicinesAsync = ref.watch(medicinesStreamProvider);
  return medicinesAsync.whenData(
    (medicines) => medicines.where((m) => m.isExpiringSoon).toList(),
  );
});

/// Family provider for a single medicine's transaction history, newest
/// first.
final medicineTransactionsProvider =
    FutureProvider.family<List<StockTransactionModel>, String>((
      ref,
      medicineId,
    ) {
      return ref
          .watch(inventoryRepositoryProvider)
          .getTransactionsForMedicine(medicineId);
    });
