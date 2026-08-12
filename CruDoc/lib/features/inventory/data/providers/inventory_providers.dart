import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/data/repo/inventory_repository.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => InventoryRepository(),
);

/// Returns `true` on desktop platforms (Windows, macOS, Linux) and web.
/// Mobile platforms (Android, iOS) return `false`.
bool get _isDesktop {
  if (kIsWeb) return true;
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;
}

/// Streams every active medicine for the current doctor.
///
/// On desktop (Windows/macOS/Linux/web), we return the Firestore stream
/// directly — matching the revenue screen, which prevents the provider
/// from getting stuck in an `AsyncLoading` state.
///
/// On mobile, we keep the original auth gating: return an empty stream
/// while auth is loading or no user is signed in.
final medicinesStreamProvider = StreamProvider<List<MedicineModel>>((ref) {
  ref.watch(authStateProvider); // rebuild on auth changes

  final repository = ref.watch(inventoryRepositoryProvider);

  if (_isDesktop) {
    return repository.watchMedicines();
  }

  final authState = ref.watch(authStateProvider);
  final user = authState.value;

  if (authState.isLoading || user == null) {
    return Stream<List<MedicineModel>>.value(const <MedicineModel>[]);
  }

  return repository.watchMedicines();
});

/// Streams the most recent stock transactions across every medicine,
/// newest first. Feeds the dashboard's "Recent Activity" card.
///
/// Same device-specific behavior as [medicinesStreamProvider].
final recentStockTransactionsProvider =
    StreamProvider<List<StockTransactionModel>>((ref) {
      ref.watch(authStateProvider); // rebuild on auth changes

      final repository = ref.watch(inventoryRepositoryProvider);

      if (_isDesktop) {
        return repository.watchRecentTransactions();
      }

      final authState = ref.watch(authStateProvider);
      final user = authState.value;

      if (authState.isLoading || user == null) {
        return Stream<List<StockTransactionModel>>.value(
          const <StockTransactionModel>[],
        );
      }

      return repository.watchRecentTransactions();
    });

/// Medicines whose `currentStock` has crossed at/under their configured
/// `reorderThreshold`.
final lowStockMedicinesProvider = Provider<AsyncValue<List<MedicineModel>>>(
  (ref) {
    final medicinesAsync = ref.watch(medicinesStreamProvider);
    return medicinesAsync.whenData(
      (medicines) => medicines.where((m) => m.isLowStock).toList(),
    );
  },
);

/// Medicines within 30 days of (or past) their expiry date.
final expiringMedicinesProvider = Provider<AsyncValue<List<MedicineModel>>>(
  (ref) {
    final medicinesAsync = ref.watch(medicinesStreamProvider);
    return medicinesAsync.whenData(
      (medicines) => medicines.where((m) => m.isExpiringSoon).toList(),
    );
  },
);

/// Family provider for a single medicine's transaction history, newest
/// first.
final medicineTransactionsProvider =
    FutureProvider.family<List<StockTransactionModel>, String>(
      (ref, medicineId) {
        return ref
            .watch(inventoryRepositoryProvider)
            .getTransactionsForMedicine(medicineId);
      },
    );