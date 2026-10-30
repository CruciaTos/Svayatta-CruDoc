import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:image_picker/image_picker.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/inventory/presentation/desktop_add_edit_medicine_dialog.dart';
import 'package:doctor_management_app/features/inventory/presentation/desktop_bill_review_dialog.dart';
import 'package:doctor_management_app/features/inventory/presentation/medicine_detail_screen.dart';
import 'package:doctor_management_app/features/inventory/presentation/stock_adjustment_dialog.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_style.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/patient_dialogs.dart';
import 'package:doctor_management_app/features/scan/data/scan_capture.dart';
import 'package:doctor_management_app/features/scan/presentation/scan_bill_page.dart';
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
    // Phones: the document camera, then the AI reads the bill. The desktop
    // reader below runs a local tool (tool/paddle_ocr_test) that a phone
    // does not have.
    if (ScanCapture.hasCamera) return _scanBillOnPhone(context, ref);
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
                    "Scan a supplier's bill",
                    style: CruType.headline.tint(c.label),
                  ),
                ),
                const SizedBox(height: CruSpace.s4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Every medicine on it is read and listed for you to check '
                    'before it goes into the inventory.',
                    style: CruType.caption.tint(c.label2),
                  ),
                ),
                const SizedBox(height: CruSpace.s16),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: CruSpace.s8,
                  ),
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: CruSpace.s8,
                  ),
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
                    'Pick a photo or scan of the bill',
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

      // A supplier's bill: every medicine on it, reviewed, then added.
      final repository = ref.read(inventoryRepositoryProvider);
      final outcome = await showDesktopBillReviewDialog(
        context,
        image: image,
        repository: repository,
      );
      if (outcome == null || !context.mounted) return;
      if (outcome.addByHand) {
        await showDesktopAddEditMedicineDialog(context, repository: repository);
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_billSummary(outcome))));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open camera or image: $e')),
      );
    }
  }

  /// Scans the bill's pages (gallery photos can be added from the camera
  /// screen too) and opens the same bill review as the Scan quick action.
  static Future<void> _scanBillOnPhone(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final List<ScannedPage> pages;
    try {
      pages = await ScanCapture.capture(context);
    } on ScanCaptureException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (pages.isEmpty || !context.mounted) return;
    final profile = ref.read(doctorProfileProvider).value;
    final modules =
        (profile?['enabledModules'] as List?)
            ?.map((m) => m.toString().toLowerCase())
            .toList() ??
        const <String>[];
    final revenue =
        DoctorFeatureGuard.isEnabled(modules, 'revenue') &&
        ref.read(clinicCanProvider(ClinicPermission.revenue));
    await pushMobile(context, ScanBillPage(pages: pages, revenue: revenue));
  }

  /// "Added 4 new items and restocked 2 from the bill."
  static String _billSummary(BillReviewOutcome o) {
    String items(int n, String one) => '$n ${n == 1 ? one : '${one}s'}';
    final parts = [
      if (o.added > 0) 'added ${items(o.added, 'new item')}',
      if (o.restocked > 0) 'restocked ${items(o.restocked, 'item')}',
    ];
    if (parts.isEmpty) return 'Nothing added from the bill.';
    final text = '${parts.join(' and ')} from the bill.';
    return text[0].toUpperCase() + text.substring(1);
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
