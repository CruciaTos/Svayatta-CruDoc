import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'package:doctor_management_app/core/services/medical_storage_service.dart';
import 'package:doctor_management_app/core/services/storage_sync_queue.dart';
import 'package:doctor_management_app/features/inventory/data/repo/inventory_repository.dart';

/// Sends a supplier receipt photo to Cloud Storage in the background and
/// records its path on the medicine (`receiptStoragePath`).
abstract final class InventoryReceiptSync {
  static const linkHandler = 'inventory.receiptStoragePath';

  /// Call once at startup, before the queue runs.
  static void register() =>
      StorageSyncQueue.instance.registerLinkHandler(linkHandler, _record);

  /// Queues [image] as the receipt for [medicineId]. [replacePath] is the
  /// receipt it supersedes, deleted once the new one is safely linked.
  /// Never throws.
  static Future<void> enqueueReceipt({
    required String medicineId,
    required XFile image,
    String? replacePath,
  }) async {
    if (medicineId.isEmpty) return;
    try {
      final type = image.mimeType ?? contentTypeForPath(image.name);
      if (type == null || !isUploadableContentType(type)) return;
      await StorageSyncQueue.instance.cancelByLink(linkHandler, medicineId);
      await StorageSyncQueue.instance.enqueue(
        kind: UploadKind.inventoryReceipt,
        bytes: await image.readAsBytes(),
        contentType: type,
        // Photos are compressed by the service; a PDF is stored as it is.
        compress: true,
        replacePath: replacePath,
        link: UploadLink.viaHandler(linkHandler, docId: medicineId),
      );
    } catch (e) {
      debugPrint('[InventoryReceiptSync] could not queue receipt: $e');
    }
  }

  static Future<void> _record(UploadLinkContext ctx) async {
    final repository = InventoryRepository();
    final medicine = await repository.getMedicine(ctx.link.docId);
    if (medicine == null || !medicine.isActive) {
      // Deleted while the upload was waiting.
      try {
        await MedicalStorageService.instance.delete(ctx.storagePath);
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') rethrow;
      }
      return;
    }
    await repository.updateMedicine(medicine.id, {
      'receiptStoragePath': ctx.storagePath,
    });
  }
}
