import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/core/database/local_database.dart';
import 'package:doctor_management_app/core/pdf/models/pdf_document_models.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/core/services/medical_storage_service.dart';
import 'package:doctor_management_app/core/services/storage_sync_queue.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';

/// Copies each generated invoice / prescription PDF to Cloud Storage in the
/// background, and remembers where it went.
///
/// Invoices and prescriptions have no record of their own in the app yet, so
/// the `generated_documents` table is what ties a document number to its
/// cloud file. Opening the same document again replaces the earlier upload
/// rather than adding a second copy. (Local to this device for now: it is
/// not part of the Firestore sync.)
abstract final class GeneratedDocumentSync {
  static const linkHandler = 'documents.pdfStoragePath';
  static const _table = 'generated_documents';

  /// Call once at startup, before the queue runs.
  static void register() =>
      StorageSyncQueue.instance.registerLinkHandler(linkHandler, _record);

  /// Queues [bytes], the PDF for [data]. Does nothing for document types
  /// that are not stored, or when there is no patient to file it under.
  /// Never throws.
  static Future<void> enqueue({
    required PdfMedicalDocumentData data,
    required Uint8List bytes,
  }) async {
    final kind = switch (data.type) {
      PdfMedicalDocumentType.invoice => UploadKind.invoicePdf,
      PdfMedicalDocumentType.prescription => UploadKind.prescriptionPdf,
      PdfMedicalDocumentType.report => null,
    };
    final patientId = data.patient.patientId;
    if (kind == null || patientId == null || patientId.isEmpty) return;
    final doctorId = ClinicSession.instance.tenantId;
    if (doctorId == null || doctorId.isEmpty || doctorId == kLocalDoctorId) {
      return;
    }

    try {
      final id = '$doctorId:${data.type.name}:${data.documentNumber}';
      // A copy of this document still on its way is superseded by this one.
      await StorageSyncQueue.instance.cancelByLink(linkHandler, id);
      await StorageSyncQueue.instance.enqueue(
        kind: kind,
        patientId: patientId,
        bytes: bytes,
        contentType: 'application/pdf',
        replacePath: await _storedPath(id),
        link: UploadLink.viaHandler(
          linkHandler,
          docId: id,
          args: {'type': data.type.name, 'number': data.documentNumber},
        ),
      );
    } catch (e) {
      debugPrint('[GeneratedDocumentSync] could not queue PDF: $e');
    }
  }

  /// Where the cloud copy of a document is, or null when there is none.
  static Future<String?> storagePathFor({
    required PdfMedicalDocumentType type,
    required String documentNumber,
  }) async {
    final doctorId = ClinicSession.instance.tenantId;
    if (doctorId == null) return null;
    return _storedPath('$doctorId:${type.name}:$documentNumber');
  }

  static Future<String?> _storedPath(String id) async {
    if (kIsWeb) return null;
    final db = await LocalDatabaseService.instance.localDatabase;
    final rows = await db.query(
      _table,
      columns: ['storagePath'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final path = rows.first['storagePath'] as String?;
    return path == null || path.isEmpty ? null : path;
  }

  static Future<void> _record(UploadLinkContext ctx) async {
    // No local database on web; the file is uploaded but not indexed.
    if (kIsWeb) return;
    final db = await LocalDatabaseService.instance.localDatabase;
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await db.query(
      _table,
      columns: ['createdAt'],
      where: 'id = ?',
      whereArgs: [ctx.link.docId],
      limit: 1,
    );
    await db.insert(_table, {
      'id': ctx.link.docId,
      'doctorId': ctx.doctorId,
      'patientId': ctx.patientId ?? '',
      'type': ctx.link.args['type'] as String? ?? '',
      'documentNumber': ctx.link.args['number'] as String? ?? '',
      'storagePath': ctx.storagePath,
      'createdAt': existing.isEmpty
          ? now
          : (existing.first['createdAt'] as num?)?.toInt() ?? now,
      'updatedAt': now,
    }, conflictAlgorithm: LocalConflictAlgorithm.replace);
  }

  /// Removes the cloud copy of a document that no longer exists.
  static Future<void> deleteFor({
    required PdfMedicalDocumentType type,
    required String documentNumber,
  }) async {
    final path = await storagePathFor(
      type: type,
      documentNumber: documentNumber,
    );
    if (path == null) return;
    try {
      await MedicalStorageService.instance.delete(path);
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }
}
