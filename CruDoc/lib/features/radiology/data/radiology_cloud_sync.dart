import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:doctor_management_app/core/services/medical_storage_service.dart';
import 'package:doctor_management_app/core/services/storage_sync_queue.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_repository.dart';
import 'package:doctor_management_app/features/radiology/imaging/rad_preview.dart';

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
        ? 'too large or in a format the cloud does not accept'
        : tooLarge > 0
        ? 'too large (over 250 MB for DICOM/TIFF, 15 MB for pictures)'
        : 'in a format the cloud does not accept';
    return '$total ${total == 1 ? 'image is' : 'images are'} $why and '
        '${total == 1 ? 'is' : 'are'} stored on this computer only.';
  }
}

/// Sends a radiology study's images to Cloud Storage in the background.
///
/// Each image goes up as its own object (one DICOM instance per file), with
/// a small JPEG preview beside it. Another device then lists the study and
/// shows thumbnails from the previews, and downloads an original only when
/// it is opened (see [RadiologyController.fileOf]).
///
/// Studies live in the local database, so the uploaded paths are written
/// back into the study's own image list (which then syncs like any other
/// edit) rather than patched onto a Firestore document.
abstract final class RadiologyCloudSync {
  static const linkHandler = 'radiology.imageStoragePath';
  static const previewLinkHandler = 'radiology.imagePreviewPath';

  /// Call once at startup, before the queue runs.
  static void register() {
    StorageSyncQueue.instance.registerLinkHandler(
      linkHandler,
      (ctx) => _record(ctx, preview: false),
    );
    StorageSyncQueue.instance.registerLinkHandler(
      previewLinkHandler,
      (ctx) => _record(ctx, preview: true),
    );
  }

  /// The queue kind for an original of [contentType]: DICOM and TIFF go to
  /// `clinical/imaging` (250 MB limit), pictures and PDFs to
  /// `clinical/xrays`.
  static UploadKind kindFor(String contentType) =>
      acceptsContentType(UploadKind.imagingOriginal, contentType)
      ? UploadKind.imagingOriginal
      : UploadKind.clinicalXray;

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
        if (image.storagePath.isNotEmpty) continue; // Already uploaded.
        final type = contentTypeForPath(image.path);
        final kind = type == null ? null : kindFor(type);
        if (type == null || kind == null || !acceptsContentType(kind, type)) {
          unsupported++;
          marked[image.id] = RadCloudStatus.localOnlyType;
          continue;
        }
        final file = File(p.join(studyDir, image.path));
        if (!await file.exists()) continue;
        if (exceedsUploadLimit(await file.length(), contentType: type)) {
          tooLarge++;
          marked[image.id] = RadCloudStatus.localOnlyTooLarge;
          continue;
        }
        final bytes = await file.readAsBytes();
        final id = await StorageSyncQueue.instance.enqueue(
          kind: kind,
          patientId: study.patientId,
          bytes: bytes,
          contentType: type,
          compress: false, // Diagnostic originals stay untouched.
          link: UploadLink.viaHandler(
            linkHandler,
            docId: study.id,
            args: {'imageId': image.id},
          ),
        );
        if (id != null) queued++;
        if (image.previewPath.isEmpty && !image.compressed) {
          await _enqueuePreview(study, image, bytes);
        }
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

  static Future<void> _enqueuePreview(
    RadStudy study,
    RadImageRef image,
    Uint8List bytes,
  ) async {
    final jpeg = await radPreviewJpeg(bytes, image.kind);
    if (jpeg == null) return; // Undecodable here; the original still goes up.
    await StorageSyncQueue.instance.enqueue(
      kind: UploadKind.imagingPreview,
      patientId: study.patientId,
      bytes: jpeg,
      contentType: 'image/jpeg',
      link: UploadLink.viaHandler(
        previewLinkHandler,
        docId: study.id,
        args: {'imageId': image.id},
      ),
    );
  }

  static Future<void> _record(
    UploadLinkContext ctx, {
    required bool preview,
  }) async {
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
            i.id != imageId
                ? i
                : preview
                ? i.copyWith(previewPath: ctx.storagePath)
                : i.copyWith(storagePath: ctx.storagePath),
        ],
      ),
    );
  }
}
