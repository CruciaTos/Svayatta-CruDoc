import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/local_database.dart';
import 'local_database_service.dart';

/// What is being uploaded. Each value maps to one `MedicalStorageService`
/// upload method (see `StorageSyncQueue`).
enum UploadKind {
  patientAvatar,
  prescriptionPdf,
  invoicePdf,
  treatmentPlanPdf,
  clinicalXray,
  clinicalPhoto,
  clinicalLab,
  voiceDictation,
  brandingLogo,
  brandingSignature,
  inventoryReceipt,
  sterilizationStrip,
  databaseBackup,
  revenueCsv,
  imagingOriginal,
  imagingPreview;

  /// Kinds stored under a patient, which need a `patientId`.
  bool get isPatientScoped => switch (this) {
    patientAvatar ||
    prescriptionPdf ||
    invoicePdf ||
    treatmentPlanPdf ||
    clinicalXray ||
    clinicalPhoto ||
    clinicalLab ||
    voiceDictation ||
    imagingOriginal ||
    imagingPreview => true,
    _ => false,
  };
}

enum UploadStatus { pending, uploading, done, failed, cancelled }

/// Where to record the uploaded file's storage path once it lands.
///
/// With no [handler], the queue patches [field] on the Firestore document
/// `[collectionPath]/[docId]`. That is only right for a document that
/// already exists in Firestore and has no local copy.
///
/// Anything kept in the local database must use a [handler] instead: it
/// updates the local record, which then syncs on its own. Patching Firestore
/// directly would leave the local record without the path, and a document
/// that hasn't synced yet doesn't exist to patch.
class UploadLink {
  const UploadLink(
    this.collectionPath,
    this.docId,
    this.field, {
    this.handler,
    this.args = const {},
  });

  /// A link that only runs a registered handler.
  const UploadLink.viaHandler(
    String this.handler, {
    this.docId = '',
    this.field = '',
    this.args = const {},
  }) : collectionPath = '';

  final String collectionPath;
  final String docId;
  final String field;

  /// Name given to `StorageSyncQueue.registerLinkHandler`. Persisted, so it
  /// still resolves after an app restart.
  final String? handler;

  /// JSON-encodable extras for the handler (persisted with the row).
  final Map<String, Object?> args;
}

/// One queued file. Immutable; the queue replaces the row on every change.
class PendingUpload {
  const PendingUpload({
    required this.id,
    required this.doctorId,
    required this.kind,
    required this.localPath,
    required this.contentType,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.patientId,
    this.compress = false,
    this.link,
    this.replacePath,
    this.deleteLocalAfter = false,
    this.attempts = 0,
    this.lastError,
    this.resultPath,
  });

  final String id;
  final String doctorId;
  final String? patientId;
  final UploadKind kind;

  /// Where the staged copy lives, relative to the store's staging root.
  final String localPath;
  final String contentType;
  final bool compress;
  final UploadLink? link;

  /// Storage path of an older version to delete once this one is uploaded.
  final String? replacePath;

  /// Sensitive files (voice): also drop the staged copy if the upload is
  /// abandoned, instead of keeping it for a manual retry.
  final bool deleteLocalAfter;

  final UploadStatus status;
  final int attempts;
  final String? lastError;

  /// Set as soon as the file is in the bucket, before it is linked. A retry
  /// then skips the upload and only finishes linking.
  final String? resultPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isUploaded => resultPath != null && resultPath!.isNotEmpty;

  PendingUpload copyWith({
    UploadStatus? status,
    int? attempts,
    String? lastError,
    bool clearLastError = false,
    String? resultPath,
    DateTime? updatedAt,
  }) => PendingUpload(
    id: id,
    doctorId: doctorId,
    patientId: patientId,
    kind: kind,
    localPath: localPath,
    contentType: contentType,
    compress: compress,
    link: link,
    replacePath: replacePath,
    deleteLocalAfter: deleteLocalAfter,
    status: status ?? this.status,
    attempts: attempts ?? this.attempts,
    lastError: clearLastError ? null : (lastError ?? this.lastError),
    resultPath: resultPath ?? this.resultPath,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'doctorId': doctorId,
    'patientId': patientId,
    'kind': kind.name,
    'localPath': localPath,
    'contentType': contentType,
    'compress': compress ? 1 : 0,
    'linkCollection': link?.collectionPath,
    'linkDocId': link?.docId,
    'linkField': link?.field,
    'linkHandler': link?.handler,
    'linkArgs': (link?.args.isNotEmpty ?? false)
        ? jsonEncode(link!.args)
        : null,
    'replacePath': replacePath,
    'deleteLocalAfter': deleteLocalAfter ? 1 : 0,
    'status': status.name,
    'attempts': attempts,
    'lastError': lastError,
    'resultPath': resultPath,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  /// Null when the row's kind or status is not one this build knows (e.g.
  /// written by a newer version), so callers skip it instead of crashing.
  static PendingUpload? fromMap(Map<String, Object?> m) {
    final kind = UploadKind.values.asNameMap()[m['kind']];
    final status = UploadStatus.values.asNameMap()[m['status']];
    if (kind == null || status == null) return null;

    UploadLink? link;
    final handler = m['linkHandler'] as String?;
    final collection = m['linkCollection'] as String?;
    if (handler != null || (collection != null && collection.isNotEmpty)) {
      var args = <String, Object?>{};
      final raw = m['linkArgs'] as String?;
      if (raw != null && raw.isNotEmpty) {
        try {
          args = Map<String, Object?>.from(jsonDecode(raw) as Map);
        } catch (_) {
          // Damaged extras: the handler gets none rather than the row being lost.
        }
      }
      link = UploadLink(
        collection ?? '',
        m['linkDocId'] as String? ?? '',
        m['linkField'] as String? ?? '',
        handler: handler,
        args: args,
      );
    }

    return PendingUpload(
      id: m['id'] as String,
      doctorId: m['doctorId'] as String? ?? '',
      patientId: m['patientId'] as String?,
      kind: kind,
      localPath: m['localPath'] as String? ?? '',
      contentType: m['contentType'] as String? ?? '',
      compress: (m['compress'] as num?) == 1,
      link: link,
      replacePath: m['replacePath'] as String?,
      deleteLocalAfter: (m['deleteLocalAfter'] as num?) == 1,
      status: status,
      attempts: (m['attempts'] as num?)?.toInt() ?? 0,
      lastError: m['lastError'] as String?,
      resultPath: m['resultPath'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (m['createdAt'] as num?)?.toInt() ?? 0,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (m['updatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

/// Where queued rows and their staged bytes are kept.
abstract class UploadStore {
  /// Writes [bytes] to staging and records [upload] (whose `localPath` the
  /// store fills in). Fails without leaving either half behind.
  Future<PendingUpload> stage(PendingUpload upload, Uint8List bytes);

  Future<void> save(PendingUpload upload);
  Future<PendingUpload?> get(String id);

  /// Rows for [doctorId] whose status is one of [statuses], oldest first.
  Future<List<PendingUpload>> list(String doctorId, Set<UploadStatus> statuses);

  Future<int> count(String doctorId, Set<UploadStatus> statuses);

  /// Staged bytes, or null when the file has gone missing.
  Future<Uint8List?> readBytes(PendingUpload upload);
  Future<void> deleteBytes(PendingUpload upload);

  /// Drops finished (done / cancelled) rows last touched before [cutoff].
  Future<void> purgeFinishedBefore(DateTime cutoff);

  /// Removes staged files that no row refers to (a crash between writing the
  /// file and inserting the row).
  Future<void> sweepOrphanedBytes();
}

/// Rows in the encrypted local database, bytes in the app support folder.
/// Survives restarts; native platforms only.
class SqliteUploadStore implements UploadStore {
  SqliteUploadStore({LocalDatabaseService? database})
    : _database = database ?? LocalDatabaseService.instance;

  final LocalDatabaseService _database;
  static const _table = 'pending_uploads';

  Future<LocalDatabase> get _db => _database.localDatabase;

  Future<Directory> _root() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'pending_uploads'));
  }

  Future<File> _file(String relativePath) async =>
      File(p.join((await _root()).path, relativePath));

  @override
  Future<PendingUpload> stage(PendingUpload upload, Uint8List bytes) async {
    final relative = p.join(upload.doctorId, upload.id);
    final file = await _file(relative);
    await file.parent.create(recursive: true);
    // Write beside the target and rename, so a crash never leaves a
    // half-written file that looks complete.
    final temp = File('${file.path}.part');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);

    final staged = PendingUpload(
      id: upload.id,
      doctorId: upload.doctorId,
      patientId: upload.patientId,
      kind: upload.kind,
      localPath: relative,
      contentType: upload.contentType,
      compress: upload.compress,
      link: upload.link,
      replacePath: upload.replacePath,
      deleteLocalAfter: upload.deleteLocalAfter,
      status: upload.status,
      createdAt: upload.createdAt,
      updatedAt: upload.updatedAt,
    );
    try {
      await save(staged);
    } catch (_) {
      await file.delete().catchError((_) => file);
      rethrow;
    }
    return staged;
  }

  @override
  Future<void> save(PendingUpload upload) async {
    final db = await _db;
    await db.insert(
      _table,
      upload.toMap(),
      conflictAlgorithm: LocalConflictAlgorithm.replace,
    );
  }

  @override
  Future<PendingUpload?> get(String id) async {
    final db = await _db;
    final rows = await db.query(
      _table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : PendingUpload.fromMap(rows.first);
  }

  String _in(Set<UploadStatus> statuses) =>
      List.filled(statuses.length, '?').join(', ');

  @override
  Future<List<PendingUpload>> list(
    String doctorId,
    Set<UploadStatus> statuses,
  ) async {
    final db = await _db;
    final rows = await db.query(
      _table,
      where: 'doctorId = ? AND status IN (${_in(statuses)})',
      whereArgs: [doctorId, ...statuses.map((s) => s.name)],
      orderBy: 'createdAt ASC',
    );
    return [for (final r in rows) ?PendingUpload.fromMap(r)];
  }

  @override
  Future<int> count(String doctorId, Set<UploadStatus> statuses) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM $_table '
      'WHERE doctorId = ? AND status IN (${_in(statuses)})',
      [doctorId, ...statuses.map((s) => s.name)],
    );
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<Uint8List?> readBytes(PendingUpload upload) async {
    final file = await _file(upload.localPath);
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<void> deleteBytes(PendingUpload upload) async {
    try {
      final file = await _file(upload.localPath);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('[UploadStore] Could not delete staged file: $e');
    }
  }

  @override
  Future<void> purgeFinishedBefore(DateTime cutoff) async {
    final db = await _db;
    await db.delete(
      _table,
      where: "status IN ('done', 'cancelled') AND updatedAt < ?",
      whereArgs: [cutoff.millisecondsSinceEpoch],
    );
  }

  @override
  Future<void> sweepOrphanedBytes() async {
    try {
      final root = await _root();
      if (!await root.exists()) return;
      final db = await _db;
      final known = {
        for (final r in await db.query(_table, columns: ['localPath']))
          r['localPath'] as String,
      };
      final dayAgo = DateTime.now().subtract(const Duration(days: 1));
      await for (final entity in root.list(recursive: true)) {
        if (entity is! File) continue;
        final relative = p.relative(entity.path, from: root.path);
        if (known.contains(relative)) continue;
        // Recent files may belong to an enqueue still in flight.
        if ((await entity.lastModified()).isAfter(dayAgo)) continue;
        await entity.delete();
      }
    } catch (e) {
      debugPrint('[UploadStore] Orphan sweep failed: $e');
    }
  }
}

/// Rows and bytes held in memory. Used on web, which has no local database
/// or file system, and in tests. Nothing survives a restart.
class MemoryUploadStore implements UploadStore {
  final Map<String, PendingUpload> _rows = {};
  final Map<String, Uint8List> _bytes = {};

  @override
  Future<PendingUpload> stage(PendingUpload upload, Uint8List bytes) async {
    _bytes[upload.id] = bytes;
    _rows[upload.id] = upload;
    return upload;
  }

  @override
  Future<void> save(PendingUpload upload) async => _rows[upload.id] = upload;

  @override
  Future<PendingUpload?> get(String id) async => _rows[id];

  @override
  Future<List<PendingUpload>> list(
    String doctorId,
    Set<UploadStatus> statuses,
  ) async =>
      _rows.values
          .where((r) => r.doctorId == doctorId && statuses.contains(r.status))
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<int> count(String doctorId, Set<UploadStatus> statuses) async =>
      (await list(doctorId, statuses)).length;

  @override
  Future<Uint8List?> readBytes(PendingUpload upload) async => _bytes[upload.id];

  @override
  Future<void> deleteBytes(PendingUpload upload) async =>
      _bytes.remove(upload.id);

  @override
  Future<void> purgeFinishedBefore(DateTime cutoff) async {
    _rows.removeWhere(
      (_, r) =>
          (r.status == UploadStatus.done ||
              r.status == UploadStatus.cancelled) &&
          r.updatedAt.isBefore(cutoff),
    );
  }

  @override
  Future<void> sweepOrphanedBytes() async {}
}
