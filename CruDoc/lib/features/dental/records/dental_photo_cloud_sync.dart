import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/core/services/medical_storage_service.dart';
import 'package:doctor_management_app/core/services/storage_sync_queue.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';

/// Sends the clinical photos of a photo set (orthodontic `photoSet`, physio
/// `physioPhotoSet`) to Cloud Storage in the background.
///
/// The set is a [DentalRecord] whose `photos` map holds each slot's local
/// file. The cloud path of each is kept beside it in `photoStoragePaths`,
/// so the record (which syncs like any other) knows where every photo is.
/// Photos are diagnostic, so they are never compressed.
abstract final class DentalPhotoCloudSync {
  static const linkHandler = 'dentalRecord.photoStoragePath';

  /// Slot name → cloud path, inside [DentalRecord.data].
  static const pathsKey = 'photoStoragePaths';

  /// Call once at startup, before the queue runs.
  static void register() =>
      StorageSyncQueue.instance.registerLinkHandler(linkHandler, _record);

  static String _docId(String recordId, String slot) => '$recordId/$slot';

  /// The cloud path stored for [slot] of [record], if any.
  static String? pathFor(DentalRecord record, String slot) {
    final paths = record.data[pathsKey];
    final path = paths is Map ? paths[slot] : null;
    return path is String && path.isNotEmpty ? path : null;
  }

  /// Queues the photo now at [localPath] as [slot] of [record]. The record
  /// must already be saved. [replaced] is the record as it was before this
  /// photo, so the photo it replaces is deleted from the cloud once the new
  /// one is linked. Never throws.
  static Future<void> enqueuePhoto({
    required DentalRecord record,
    required String slot,
    required String localPath,
    DentalRecord? replaced,
  }) async {
    if (kIsWeb || record.patientId.isEmpty) return;
    try {
      final type = contentTypeForPath(localPath);
      final file = File(localPath);
      if (type == null ||
          !acceptsContentType(UploadKind.clinicalPhoto, type) ||
          exceedsUploadLimit(await file.length(), contentType: type)) {
        return;
      }
      final docId = _docId(record.id, slot);
      await StorageSyncQueue.instance.cancelByLink(linkHandler, docId);
      await StorageSyncQueue.instance.enqueue(
        kind: UploadKind.clinicalPhoto,
        patientId: record.patientId,
        bytes: await file.readAsBytes(),
        contentType: type,
        compress: false,
        replacePath: replaced == null ? null : pathFor(replaced, slot),
        link: UploadLink.viaHandler(linkHandler, docId: docId),
      );
    } catch (e) {
      debugPrint('[DentalPhotoCloudSync] could not queue photo: $e');
    }
  }

  /// [data] with [slot]'s cloud path forgotten. Pair with [discardSlot].
  static Map<String, dynamic> dropSlot(Map<String, dynamic> data, String slot) {
    final paths = data[pathsKey];
    if (paths is! Map || !paths.containsKey(slot)) return data;
    return {...data, pathsKey: Map<String, dynamic>.from(paths)..remove(slot)};
  }

  /// A photo was removed: stop any upload of it and delete what is already
  /// in the cloud. Never throws.
  static Future<void> discardSlot(DentalRecord record, String slot) async {
    await StorageSyncQueue.instance.cancelByLink(
      linkHandler,
      _docId(record.id, slot),
    );
    final path = pathFor(record, slot);
    if (path != null) await _deleteQuietly(path);
  }

  /// A whole set was deleted: same, for every photo in it.
  static Future<void> discardRecord(DentalRecord record) async {
    final photos = record.data['photos'];
    final slots = {
      if (photos is Map) ...photos.keys.map((k) => '$k'),
      if (record.data[pathsKey] is Map)
        ...(record.data[pathsKey] as Map).keys.map((k) => '$k'),
    };
    for (final slot in slots) {
      await discardSlot(record, slot);
    }
  }

  static Future<void> _record(UploadLinkContext ctx) async {
    final split = ctx.link.docId.indexOf('/');
    if (split < 0) return;
    final recordId = ctx.link.docId.substring(0, split);
    final slot = ctx.link.docId.substring(split + 1);

    final repository = DentalRecordsRepository();
    final record = await repository.byId(recordId);
    final photos = record?.data['photos'];
    if (record == null || photos is! Map || !photos.containsKey(slot)) {
      // The set or the photo was removed while the upload was waiting.
      await _deleteQuietly(ctx.storagePath);
      return;
    }
    final paths = record.data[pathsKey];
    await repository.save(
      ctx.doctorId,
      record.copyWith(
        data: {
          ...record.data,
          pathsKey: {
            if (paths is Map) ...Map<String, dynamic>.from(paths),
            slot: ctx.storagePath,
          },
        },
      ),
    );
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      await MedicalStorageService.instance.delete(path);
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') {
        debugPrint('[DentalPhotoCloudSync] could not delete $path: ${e.code}');
      }
    } catch (e) {
      debugPrint('[DentalPhotoCloudSync] could not delete $path: $e');
    }
  }
}
