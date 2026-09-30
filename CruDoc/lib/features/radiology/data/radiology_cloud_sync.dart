import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:doctor_management_app/core/services/medical_storage_service.dart';
import 'package:doctor_management_app/core/services/storage_sync_queue.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_repository.dart';

/// What [RadiologyCloudSync.enqueueStudyImages] left on this computer only.
class RadCloudSyncSummary {
  const RadCloudSyncSummary({
    this.queued = 0,
    this.tooLarge = 0,
    this.unsupported = 0,
  });

  final int queued;
  final int tooLarge;
  final int unsupported;

  bool get hasLocalOnly => tooLarge > 0 || unsupported > 0;

  /// One line for the doctor, or null when everything is going to the cloud.
  String? get notice {
    if (!hasLocalOnly) return null;
    final total = tooLarge + unsupported;
    final why = tooLarge > 0 && unsupported > 0
        ? 'larger than 15 MB or in a format the cloud does not accept'
        : tooLarge > 0
        ? 'larger than 15 MB'
        : 'in a format the cloud does not accept';
    return '$total ${total == 1 ? 'image is' : 'images are'} $why and '
        '${total == 1 ? 'is' : 'are'} stored on this computer only.';
  }
}

/// Sends a radiology study's images to Cloud Storage in the background.
///
/// Studies live in the local database, so the uploaded path is written back
/// into the study's own image list (which then syncs like any other edit)
/// rather than patched onto a Firestore document.
abstract final class RadiologyCloudSync {
  static const linkHandler = 'radiology.imageStoragePath';

  /// Call once at startup, before the queue runs.
  static void register() =>
      StorageSyncQueue.instance.registerLinkHandler(linkHandler, _record);

  /// Queues every uploadable image of [study] (already saved) and marks the
  /// ones that can never be uploaded as local-only, so nothing is dropped
  /// unnoticed. Never throws: the local files are what the doctor works
  /// from.
  static Future<RadCloudSyncSummary> enqueueStudyImages({
    required RadiologyController ctrl,
    required RadStudy study,
    required String studyDir,
  }) async {
    if (kIsWeb || study.patientId.isEmpty) return const RadCloudSyncSummary();
    var queued = 0;
    var tooLarge = 0;
    var unsupported = 0;
    final marked = <String, String>{};

    try {
      for (final image in study.images) {
        final type = contentTypeForPath(image.path);
        if (type == null || !isUploadableContentType(type)) {
          unsupported++;
          marked[image.id] = RadCloudStatus.localOnlyType;
          continue;
        }
        final file = File(p.join(studyDir, image.path));
        if (!await file.exists()) continue;
        if (exceedsUploadLimit(await file.length())) {
          tooLarge++;
          marked[image.id] = RadCloudStatus.localOnlyTooLarge;
          continue;
        }
        final id = await StorageSyncQueue.instance.enqueue(
          kind: UploadKind.clinicalXray,
          patientId: study.patientId,
          bytes: await file.readAsBytes(),
          contentType: type,
          compress: false, // Diagnostic originals stay untouched.
          link: UploadLink.viaHandler(
            linkHandler,
            docId: study.id,
            args: {'imageId': image.id},
          ),
        );
        if (id != null) queued++;
      }

      if (marked.isNotEmpty) {
        await ctrl.saveStudy(
          study.copyWith(
            images: [
              for (final i in study.images)
                marked.containsKey(i.id)
                    ? i.copyWith(cloudStatus: marked[i.id])
                    : i,
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('[RadiologyCloudSync] could not queue images: $e');
    }
    return RadCloudSyncSummary(
      queued: queued,
      tooLarge: tooLarge,
      unsupported: unsupported,
    );
  }

  static Future<void> _record(UploadLinkContext ctx) async {
    final repo = RadiologyRepository();
    final study = await repo.study(ctx.link.docId);
    final imageId = ctx.link.args['imageId'];
    if (study == null || !study.images.any((i) => i.id == imageId)) {
      // The study (or image) was deleted while the upload was waiting.
      try {
        await MedicalStorageService.instance.delete(ctx.storagePath);
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') rethrow;
      }
      return;
    }
    await repo.saveStudy(
      ctx.doctorId,
      study.copyWith(
        images: [
          for (final i in study.images)
            i.id == imageId ? i.copyWith(storagePath: ctx.storagePath) : i,
        ],
      ),
    );
  }
}
