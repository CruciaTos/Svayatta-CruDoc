import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';

/// Wraps [child] with a reactive watcher (not a polling job) for the
/// low-stock and expiring-soon medicine lists.
///
/// When a medicine *newly* enters either list — compared against the
/// previous snapshot, not just "list is non-empty" — and its
/// `lowStockNotifiedAt` / `expiryNotifiedAt` dedup flag is still unset,
/// this shows an in-app snackbar and stamps that flag via
/// [InventoryRepository.markLowStockNotified] /
/// [InventoryRepository.markExpiryNotified] so the alert doesn't refire on
/// every rebuild.
///
/// Mount this once, above [BottomNavBar] and the tab [PageView], so it
/// keeps listening regardless of which tab is active.
class InventoryAlertListener extends ConsumerStatefulWidget {
  const InventoryAlertListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<InventoryAlertListener> createState() =>
      _InventoryAlertListenerState();
}

class _InventoryAlertListenerState
    extends ConsumerState<InventoryAlertListener> {
  Set<String> _previousLowStockIds = {};
  Set<String> _previousExpiringIds = {};
  bool _isFirstLowStockEmission = true;
  bool _isFirstExpiringEmission = true;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<MedicineModel>>>(lowStockMedicinesProvider, (
      previous,
      next,
    ) {
      next.when(
        data: (medicines) {
          final isFirst = _isFirstLowStockEmission;
          _isFirstLowStockEmission = false;
          _handleNewAlerts(
            medicines: medicines,
            previousIds: _previousLowStockIds,
            skip: isFirst,
            alreadyNotified: (m) => m.lowStockNotifiedAt != null,
            message: (m) =>
                '${m.name} is low on stock (${m.currentStock} ${m.unit} left).',
            markNotified: (m) =>
                ref.read(inventoryRepositoryProvider).markLowStockNotified(m.id),
          );
          _previousLowStockIds = medicines.map((m) => m.id).toSet();
        },
        loading: () {},
        error: (_, __) {},
      );
    });

    ref.listen<AsyncValue<List<MedicineModel>>>(expiringMedicinesProvider, (
      previous,
      next,
    ) {
      next.when(
        data: (medicines) {
          final isFirst = _isFirstExpiringEmission;
          _isFirstExpiringEmission = false;
          _handleNewAlerts(
            medicines: medicines,
            previousIds: _previousExpiringIds,
            skip: isFirst,
            alreadyNotified: (m) => m.expiryNotifiedAt != null,
            message: (m) => '${m.name} is expiring soon.',
            markNotified: (m) =>
                ref.read(inventoryRepositoryProvider).markExpiryNotified(m.id),
          );
          _previousExpiringIds = medicines.map((m) => m.id).toSet();
        },
        loading: () {},
        error: (_, __) {},
      );
    });

    return widget.child;
  }

  void _handleNewAlerts({
    required List<MedicineModel> medicines,
    required Set<String> previousIds,
    required bool skip,
    required bool Function(MedicineModel) alreadyNotified,
    required String Function(MedicineModel) message,
    required Future<void> Function(MedicineModel) markNotified,
  }) {
    // Don't spam alerts for everything that's already low/expiring the
    // first time this listener mounts (e.g. app restart) — only alert on
    // medicines that newly cross the threshold while the app is open.
    if (skip) return;

    final newlyEntered = medicines.where(
      (m) => !previousIds.contains(m.id) && !alreadyNotified(m),
    );

    for (final medicine in newlyEntered) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            message(medicine),
            style: const TextStyle(fontFamily: AppColors.bodyFontFamily),
          ),
          backgroundColor: AppColors.charcoalGray,
          behavior: SnackBarBehavior.floating,
        ),
      );
      markNotified(medicine);
    }
  }
}
