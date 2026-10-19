import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:image_picker/image_picker.dart';

import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/inventory/presentation/desktop_add_edit_medicine_dialog.dart';
import 'package:doctor_management_app/features/inventory/presentation/medicine_detail_screen.dart';
import 'package:doctor_management_app/features/inventory/presentation/stock_adjustment_dialog.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_style.dart';
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

  static Future<void> scanItem(BuildContext context, WidgetRef ref) async {
    final imagePicker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: context.cru.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final c = ctx.cru;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: CruSpace.s16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Scan or Photograph Item',
                    style: CruType.headline.tint(c.label),
                  ),
                ),
                const SizedBox(height: CruSpace.s4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Capture medicine strip, packaging, or bill to auto-fill details.',
                    style: CruType.caption.tint(c.label2),
                  ),
                ),
                const SizedBox(height: CruSpace.s16),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: CruSpace.s8),
                  leading: const CruSquareButton(
                    icon: InventoryIcons.camera,
                    secondary: true,
                    onPressed: null,
                    semanticLabel: 'Camera',
                  ),
                  title: Text('Take a photo', style: CruType.row.tint(c.label)),
                  subtitle: Text(
                    'Scan with device camera',
                    style: CruType.caption.tint(c.label2),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onTap: () => Navigator.pop(ctx, ImageSource.camera),
                ),
                const SizedBox(height: CruSpace.s8),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: CruSpace.s8),
                  leading: const CruSquareButton(
                    icon: CruIcons.box,
                    secondary: true,
                    onPressed: null,
                    semanticLabel: 'Gallery',
                  ),
                  title: Text(
                    'Choose from gallery',
                    style: CruType.row.tint(c.label),
                  ),
                  subtitle: Text(
                    'Pick an existing photo or bill',
                    style: CruType.caption.tint(c.label2),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null || !context.mounted) return;

    try {
      final image = await imagePicker.pickImage(
        source: source,
        imageQuality: 88,
      );
      if (image == null || !context.mounted) return;

      await showDesktopAddEditMedicineDialog(
        context,
        repository: ref.read(inventoryRepositoryProvider),
        initialReceiptImage: image,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open camera or image: $e')),
      );
    }
  }

  static Future<void> editItem(
    BuildContext context,
    WidgetRef ref,
    MedicineModel medicine,
  ) => showDesktopAddEditMedicineDialog(
    context,
    medicine: medicine,
    repository: ref.read(inventoryRepositoryProvider),
  );

  static Future<void> adjustStock(
    BuildContext context,
    WidgetRef ref,
    MedicineModel medicine,
  ) => showStockAdjustmentDialog(
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
        SnackBar(
          content: Text("Couldn't archive ${medicine.name}. Try again."),
        ),
      );
    }
  }
}
