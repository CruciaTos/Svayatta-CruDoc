import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/core/services/medical_storage_service.dart';
import 'package:doctor_management_app/core/services/storage_sync_queue.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/services/consultation_note_local_service.dart';
import 'package:doctor_management_app/features/scribe/scribe_config.dart';

/// Sends a scribe recording to Cloud Storage in the background and records
/// its path on the note (`audioStoragePath`) once it lands.
abstract final class ScribeAudioSync {
  static const linkHandler = 'scribe.audioStoragePath';

  /// Call once at startup, before the queue runs.
  static void register() =>
      StorageSyncQueue.instance.registerLinkHandler(linkHandler, _record);

  /// Queues the recording at [localPath] for [note]. The note must already
  /// be saved. The queue keeps its own copy, so the caller can delete the
  /// recording straight away. Never throws.
  static Future<void> enqueueRecording({
    required ConsultationNote note,
    required String? localPath,
  }) async {
    if (!kUploadScribeAudio || kIsWeb || localPath == null) return;
    final doctorId = FirebaseAuth.instance.currentUser?.uid;
    if (doctorId == null || doctorId.isEmpty || doctorId == kLocalDoctorId) {
      return;
    }
    try {
      final type = contentTypeForPath(localPath);
      if (type == null) return;
      await StorageSyncQueue.instance.enqueue(
        kind: UploadKind.voiceDictation,
        patientId: note.patientId,
        bytes: await File(localPath).readAsBytes(),
        contentType: type,
        link: UploadLink.viaHandler(linkHandler, docId: note.id),
        // Patient voice: don't keep a copy on the device if the upload is
        // abandoned.
        deleteLocalAfter: true,
      );
    } catch (e) {
      debugPrint('[ScribeAudioSync] could not queue recording: $e');
    }
  }

  /// Stops any upload still on its way for [noteId].
  static Future<void> cancelFor(String noteId) =>
      StorageSyncQueue.instance.cancelByLink(linkHandler, noteId);

  static Future<void> _record(UploadLinkContext ctx) async {
    final service = ConsultationNoteLocalService();
    final note = await service.getNote(ctx.link.docId);
    if (note == null || note.status != ConsultationNoteStatus.draft) {
      // Confirmed or discarded (or deleted) while the upload was waiting:
      // the recording is no longer wanted, so remove it straight away.
      try {
        await MedicalStorageService.instance.delete(ctx.storagePath);
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') rethrow;
      }
      return;
    }
    await service.updateNoteFields(note.id, {
      'audioStoragePath': ctx.storagePath,
    });
  }
}
