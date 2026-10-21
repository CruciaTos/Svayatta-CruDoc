import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/services/local_storage_manager.dart';
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
    LocalStorageManager.instance.registerSource(_RadiologyLocalSource());
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
  }) => _enqueue(study: study, studyDir: studyDir, save: ctrl.saveStudy);

  /// Queues the images that never reached the cloud: those of studies
  /// imported before uploading existed, or of a study that only has a
  /// patient now. Images were otherwise queued only at import, so these
  /// stayed on the one computer for good. Run at sign-in; cheap when
  /// there's nothing to do.
  ///
  /// A study with no patient is left alone: its uploads are patient-scoped
  /// (storage rules), so it goes up once a patient is attached.
  static Future<int> catchUp() async {
    if (kIsWeb) return 0;
    final doctorId = ClinicSession.instance.tenantId;
    if (doctorId == null || doctorId.isEmpty) return 0;
    final access = ClinicSession.instance.access;
    if (access != null && !access.can(ClinicPermission.clinicalEdit)) {
      return 0; // The storage rules would refuse the uploads.
    }
    var queued = 0;
    try {
      final repo = RadiologyRepository();
      final open = {
        for (final l in await StorageSyncQueue.instance.openLinks(linkHandler))
          '${l.docId}|${l.args['imageId']}',
      };
      for (final study in await repo.studies(doctorId)) {
        if (study.patientId.isEmpty) continue;
        final waiting = {
          for (final i in study.images)
            if (i.storagePath.isEmpty &&
                i.cloudStatus.isEmpty &&
                !open.contains('${study.id}|${i.id}'))
              i.id,
        };
        if (waiting.isEmpty) continue;
        final summary = await _enqueue(
          study: study,
          studyDir: (await repo.studyDir(doctorId, study.id)).path,
          save: (s) => repo.saveStudy(doctorId, s),
          only: waiting,
        );
        queued += summary.queued;
      }
      if (queued > 0) {
        debugPrint('[RadiologyCloudSync] caught up: queued $queued image(s)');
      }
    } catch (e) {
      debugPrint('[RadiologyCloudSync] catch-up failed: $e');
    }
    return queued;
  }

  /// Queues the images of [study] (or just those in [only]) and saves the
  /// local-only marks with [save].
  static Future<RadCloudSyncSummary> _enqueue({
    required RadStudy study,
    required String studyDir,
    required Future<void> Function(RadStudy) save,
    Set<String>? only,
  }) async {
    if (kIsWeb || study.patientId.isEmpty) return const RadCloudSyncSummary();
    var queued = 0;
    var tooLarge = 0;
    var unsupported = 0;
    final marked = <String, String>{};

    try {
      for (final image in study.images) {
        if (only != null && !only.contains(image.id)) continue;
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
        // Onto the latest copy: an upload that finished meanwhile has
        // written its path into the study, which a stale copy would undo.
        final latest = await RadiologyRepository().study(study.id) ?? study;
        await save(
          latest.copyWith(
            images: [
              for (final i in latest.images)
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

/// Study files on this device, for [LocalStorageManager]: originals the
/// cloud also has (the viewer fetches them again when opened, and shows
/// the small cloud preview meanwhile), and the preview and viewing-file
/// caches, which are always fetched again on demand.
class _RadiologyLocalSource implements LocalAssetSource {
  static const _caches = ['.previews', '.views'];

  @override
  String get name => 'radiology';

  @override
  Future<List<LocalAsset>> assets() async {
    final doctorId = ClinicSession.instance.tenantId;
    if (kIsWeb || doctorId == null || doctorId.isEmpty) return const [];
    final repo = RadiologyRepository();
    final out = <LocalAsset>[];
    for (final study in await repo.studies(doctorId)) {
      final dir = await repo.studyDir(doctorId, study.id);
      if (!await dir.exists()) continue;
      for (final cache in _caches) {
        final cacheDir = Directory(p.join(dir.path, cache));
        if (!await cacheDir.exists()) continue;
        await for (final e in cacheDir.list(recursive: true)) {
          if (e is! File) continue;
          out.add(
            LocalAsset(
              file: e,
              bytes: await e.length(),
              lastUsed: await LocalStorageManager.lastUsedOf(e),
              isCache: true,
              isStillSafe: () async => true,
            ),
          );
        }
      }
      for (final image in study.images) {
        if (image.storagePath.isEmpty) continue;
        final file = File(p.join(dir.path, image.path));
        if (!await file.exists()) continue;
        out.add(
          LocalAsset(
            file: file,
            bytes: await file.length(),
            lastUsed: await LocalStorageManager.lastUsedOf(file),
            storagePath: image.storagePath,
            isStillSafe: () =>
                _originalInCloud(repo, study.id, image.id, image.storagePath),
          ),
        );
      }
    }
    return out;
  }

  /// The study record has reached the cloud still pointing at this upload,
  /// and nothing for the image is on its way up.
  static Future<bool> _originalInCloud(
    RadiologyRepository repo,
    String studyId,
    String imageId,
    String storagePath,
  ) async {
    if (await repo.isSynced(studyId) != true) return false;
    final latest = await repo.study(studyId);
    final image = latest?.images.where((i) => i.id == imageId).firstOrNull;
    if (image == null || image.storagePath != storagePath) return false;
    final open = await StorageSyncQueue.instance.openLinks(
      RadiologyCloudSync.linkHandler,
    );
    return !open.any(
      (l) => l.docId == studyId && l.args['imageId'] == imageId,
    );
  }
}
