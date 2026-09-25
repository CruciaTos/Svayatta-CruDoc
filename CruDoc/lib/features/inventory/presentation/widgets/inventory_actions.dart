import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/inventory/presentation/desktop_add_edit_medicine_dialog.dart';
import 'package:doctor_management_app/features/inventory/presentation/medicine_detail_screen.dart';
import 'package:doctor_management_app/features/inventory/presentation/stock_adjustment_dialog.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/patient_dialogs.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// What the Inventory screen can do. Every write goes through the
/// existing dialogs and [InventoryRepository] (via its provider).
abstract final class InventoryActions {
  static Future<void> addItem(BuildContext context, WidgetRef ref) =>
      showDesktopAddEditMedicineDialog(
        context,
        repository: ref.read(inventoryRepositoryProvider),
      );

  static Future<void> editItem(
    BuildContext context,
    WidgetRef ref,
    MedicineModel medicine,
  ) =>
      showDesktopAddEditMedicineDialog(
        context,
        medicine: medicine,
        repository: ref.read(inventoryRepositoryProvider),
      );

  static Future<void> adjustStock(
    BuildContext context,
    WidgetRef ref,
    MedicineModel medicine,
  ) =>
      showStockAdjustmentDialog(
        context,
        medicine: medicine,
        repository: ref.read(inventoryRepositoryProvider),
      );

  /// The existing item details screen (Enter).
  static Future<void> openDetails(BuildContext context, MedicineModel m) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MedicineDetailScreen(medicine: m),
        ),
      );

  /// Confirms, then soft-deletes the item.
  static Future<void> archive(
    BuildContext context,
    WidgetRef ref,
    MedicineModel medicine,
  ) async {
    final repository = ref.read(inventoryRepositoryProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = ctx.cru;
        return PatientDialog(
          title: 'Archive ${medicine.name}?',
          body: Text(
            'It leaves the inventory list. Its stock history is kept.',
            style: CruType.text.tint(c.label2),
          ),
          cancelLabel: 'Cancel',
          confirmLabel: 'Archive',
          onConfirm: () => Navigator.of(ctx).pop(true),
        );
      },
    );
    if (confirmed != true) return;
    try {
      await repository.deleteMedicine(medicine.id);
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text("Couldn't archive ${medicine.name}. Try again.")),
      );
    }
  }
}
