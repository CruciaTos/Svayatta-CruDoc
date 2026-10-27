import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/database/local_database.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/core/services/local_storage_manager.dart';
import 'package:doctor_management_app/core/services/medical_storage_service.dart';
import 'package:doctor_management_app/core/services/storage_sync_queue.dart';
import 'package:doctor_management_app/features/files/data/file_fingerprint.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/file_offer_model.dart';
import 'package:doctor_management_app/features/files/data/file_previews.dart';
import 'package:doctor_management_app/features/files/data/file_types.dart';
import 'package:doctor_management_app/features/files/data/files_cloud_sync.dart';

/// A file chosen or dropped for adding: a path on this device, or bytes
/// (web, where pickers give no path).
@immutable
class FileSource {
  const FileSource({
    required this.name,
    required this.sizeBytes,
    this.path,
    this.bytes,
  });

  final String name;
  final int sizeBytes;
  final String? path;
  final Uint8List? bytes;

  /// The content type, or null when the Files screen doesn't take it.
  String? get contentType => PatientFileTypes.contentTypeFor(name);

  /// Why it can't be added, or null when it can.
  String? get problem {
    final type = contentType;
    if (type == null) return 'This file type is not supported';
    final limit = PatientFileTypes.maxBytesFor(type);
    if (sizeBytes > limit) {
      return 'Over ${PatientFileTypes.sizeLabel(limit)}';
    }
    return null;
  }

  static Future<FileSource?> fromPath(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      return FileSource(
        name: p.basename(path),
        sizeBytes: await f.length(),
        path: path,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Raised for something the person did that can't be done (moving a folder
/// into itself, deleting someone else's file).
class FilesException implements Exception {
  const FilesException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The Files screen's records, kept in the local database (`patient_files`
/// and `file_folders`) and synced by [FilesCloudSync]. File contents live
/// in the app's support folder under `patient_files/<clinic>/<file id>/`
/// and in Cloud Storage under `patient-files/`.
///
/// Everything read here is limited to what the signed-in person may see:
/// their own folders and files, and folders shared with them.
class FilesRepository {
  FilesRepository._();

  static final FilesRepository instance = FilesRepository._();

  static const _files = 'patient_files';
  static const _folders = 'file_folders';
  static const linkHandler = 'files.storagePath';
  static const viewLinkHandler = 'files.viewPath';

  /// A picture's progressive view on this device, next to its original.
  static const _viewName = 'view.jpg';
  static const Uuid _uuid = Uuid();

  final LocalDatabaseService _db = LocalDatabaseService.instance;

  static final StreamController<void> _changes =
      StreamController<void>.broadcast();

  /// Fires after any change, local or synced.
  static Stream<void> get changes => _changes.stream;

  static void notifyChanged() {
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Call once at startup, before the upload queue runs.
  static void register() {
    StorageSyncQueue.instance.registerLinkHandler(
      linkHandler,
      (ctx) => instance._recordUpload(ctx),
    );
    StorageSyncQueue.instance.registerLinkHandler(
      viewLinkHandler,
      (ctx) => instance._recordView(ctx),
    );
    LocalStorageManager.instance.registerSource(_FilesLocalSource());
  }

  /// The clinic.
  String get doctorId => ClinicSession.instance.tenantId ?? '';

  /// The signed-in person (the clinic owner in a solo practice).
  String get uid =>
      _authUid() ?? ClinicSession.instance.access?.uid ?? doctorId;

  static String? _authUid() {
    if (Firebase.apps.isEmpty) return null;
    return FirebaseAuth.instance.currentUser?.uid;
  }

  bool get _isAdmin => ClinicSession.instance.access?.isAdmin ?? true;

  void _changed() {
    notifyChanged();
    FilesCloudSync.instance.kick();
  }

  // ───────────────────────────── Reading ─────────────────────────────

  /// Every folder this person may see.
  Future<List<FileFolder>> folders() async {
    FilesCloudSync.instance.ensureStarted();
    final db = await _db.localDatabase;
    final rows = await db.query(
      _folders,
      where: 'doctorId = ? AND isDeleted = 0',
      whereArgs: [doctorId],
      orderBy: 'name COLLATE NOCASE',
    );
    final me = uid;
    return [
      for (final f in rows.map(FileFolder.fromLocalMap))
        if (filesVisibleTo(f.visibleTo, me)) f,
    ];
  }

  /// Every file this person may see, newest first. [patientId] limits it
  /// to one patient; [limit] to the newest few.
  Future<List<PatientFile>> files({String? patientId, int? limit}) async {
    _backfillPreviews();
    FilesCloudSync.instance.ensureStarted();
    final db = await _db.localDatabase;
    final rows = await db.query(
      _files,
      where: patientId == null
          ? 'doctorId = ? AND isDeleted = 0'
          : 'doctorId = ? AND patientId = ? AND isDeleted = 0',
      whereArgs: patientId == null ? [doctorId] : [doctorId, patientId],
      orderBy: 'createdAt DESC',
    );
    final me = uid;
    final out = <PatientFile>[];
    for (final r in rows) {
      final f = PatientFile.fromLocalMap(r);
      if (!filesVisibleTo(f.visibleTo, me)) continue;
      out.add(f);
      if (limit != null && out.length >= limit) break;
    }
    return out;
  }

  Future<PatientFile?> file(String id) async {
    final db = await _db.localDatabase;
    final rows = await db.query(
      _files,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : PatientFile.fromLocalMap(rows.first);
  }

  Future<FileFolder?> folder(String id) async {
    if (id.isEmpty) return null;
    final db = await _db.localDatabase;
    final rows = await db.query(
      _folders,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : FileFolder.fromLocalMap(rows.first);
  }

  /// Whether this person may rename, move or delete [ownerUid]'s item in
  /// the folder tree under [rootId]: their own things, anything in a
  /// top-level folder they own, and (clinic admins) anything they can see.
  bool canManage(String ownerUid, String rootId, List<FileFolder> folders) {
    final me = uid;
    if (ownerUid == me || _isAdmin) return true;
    if (rootId.isEmpty) return false;
    for (final f in folders) {
      if (f.id == rootId) return f.ownerUid == me;
    }
    return false;
  }

  // ───────────────────────────── Folders ─────────────────────────────

  static String cleanName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// A new folder inside [parentId] ('' for top level). Top-level folders
  /// start private; inner ones follow their top-level folder.
  Future<FileFolder> createFolder(String name, {String parentId = ''}) async {
    final clean = cleanName(name);
    if (clean.isEmpty) throw const FilesException('Give the folder a name.');
    final now = DateTime.now();
    final id = _uuid.v4();
    final me = uid;
    final parent = await folder(parentId);
    if (parentId.isNotEmpty && (parent == null || parent.isDeleted)) {
      throw const FilesException('That folder no longer exists.');
    }
    final root = parent == null ? null : await folder(parent.rootId);
    final f = FileFolder(
      id: id,
      doctorId: doctorId,
      ownerUid: me,
      parentId: parent?.id ?? '',
      rootId: root?.id ?? id,
      name: clean,
      sharing: root?.sharing ?? FolderSharing.private,
      visibleTo: root?.visibleTo ?? [me],
      createdAt: now,
      updatedAt: now,
    );
    await _putFolder(f);
    _changed();
    return f;
  }

  Future<void> renameFolder(String id, String name) async {
    final clean = cleanName(name);
    if (clean.isEmpty) throw const FilesException('Give the folder a name.');
    final f = await folder(id);
    if (f == null) return;
    await _putFolder(f.copyWith(name: clean, updatedAt: DateTime.now()));
    _changed();
  }

  /// Shares a top-level folder. Everything in it follows.
  Future<void> shareFolder(
    String id,
    FolderSharing sharing, {
    Iterable<String> people = const [],
  }) async {
    final f = await folder(id);
    if (f == null) return;
    if (!f.isTopLevel) {
      throw const FilesException(
        'Only top-level folders are shared. This one follows the folder it is in.',
      );
    }
    final visibleTo = FileFolder.visibilityFor(f.ownerUid, sharing, people);
    await _putFolder(
      f.copyWith(
        sharing: sharing,
        visibleTo: visibleTo,
        updatedAt: DateTime.now(),
      ),
    );
    await _restampSubtree(f.id, rootId: f.id, visibleTo: visibleTo);
    _changed();
  }

  /// Throws when something under [folderId] belongs to someone this person
  /// may not change (the rules would refuse the write, and it would never
  /// sync).
  Future<void> _requireManagesSubtree(String folderId, String verb) async {
    final all = await folders();
    final ids = await _subtreeIds(folderId);
    final db = await _db.localDatabase;
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      _files,
      columns: ['ownerUid', 'rootId'],
      where: 'folderId IN ($placeholders) AND isDeleted = 0',
      whereArgs: ids,
    );
    final owners = [
      for (final f in all)
        if (ids.contains(f.id)) (f.ownerUid, f.rootId),
      for (final r in rows)
        (r['ownerUid'] as String? ?? '', r['rootId'] as String? ?? ''),
    ];
    for (final (owner, root) in owners) {
      if (!canManage(owner, root, all)) {
        throw FilesException(
          'Someone else added things to this folder, so only the person '
          'who shared it can $verb it.',
        );
      }
    }
  }

  /// Moves a folder (and everything in it) into [parentId] ('' for the
  /// top level, where it becomes private to its owner).
  Future<void> moveFolder(String id, String parentId) async {
    final f = await folder(id);
    if (f == null || f.parentId == parentId) return;
    await _requireManagesSubtree(id, 'move');
    final all = await folders();
    if (parentId.isNotEmpty) {
      // Not into itself or anything inside it.
      var cursor = parentId;
      while (cursor.isNotEmpty) {
        if (cursor == id) {
          throw const FilesException("A folder can't be moved into itself.");
        }
        cursor = all
            .firstWhere(
              (x) => x.id == cursor,
              orElse: () => f.copyWith(parentId: ''),
            )
            .parentId;
      }
    }
    final parent = await folder(parentId);
    final root = parent == null ? null : await folder(parent.rootId);
    final now = DateTime.now();
    final moved = root == null
        ? f.copyWith(
            parentId: '',
            rootId: f.id,
            sharing: FolderSharing.private,
            visibleTo: [f.ownerUid],
            updatedAt: now,
          )
        : f.copyWith(
            parentId: parentId,
            rootId: root.id,
            sharing: root.sharing,
            visibleTo: root.visibleTo,
            updatedAt: now,
          );
    await _putFolder(moved);
    await _restampSubtree(
      f.id,
      rootId: moved.rootId,
      visibleTo: moved.visibleTo,
      sharing: moved.sharing,
    );
    _changed();
  }

  /// Deletes a folder, its folders and their files.
  Future<void> deleteFolder(String id) async {
    final f = await folder(id);
    if (f == null) return;
    await _requireManagesSubtree(id, 'delete');
    final ids = await _subtreeIds(id);
    final now = DateTime.now();
    final db = await _db.localDatabase;
    final placeholders = List.filled(ids.length, '?').join(',');
    final fileRows = await db.query(
      _files,
      where: 'folderId IN ($placeholders) AND isDeleted = 0',
      whereArgs: ids,
    );
    for (final r in fileRows) {
      await _deleteFileRow(PatientFile.fromLocalMap(r), now);
    }
    for (final folderId in ids) {
      final sub = await folder(folderId);
      if (sub == null) continue;
      await _putFolder(sub.copyWith(isDeleted: true, updatedAt: now));
    }
    _changed();
  }

  /// How many folders and files deleting [id] removes.
  Future<({int folders, int files})> folderContents(String id) async {
    final ids = await _subtreeIds(id);
    final db = await _db.localDatabase;
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      _files,
      columns: ['id'],
      where: 'folderId IN ($placeholders) AND isDeleted = 0',
      whereArgs: ids,
    );
    return (folders: ids.length - 1, files: rows.length);
  }

  /// [id] and every folder inside it.
  Future<List<String>> _subtreeIds(String id) async {
    final all = await folders();
    final out = <String>[id];
    for (var i = 0; i < out.length; i++) {
      for (final f in all) {
        if (f.parentId == out[i] && !out.contains(f.id)) out.add(f.id);
      }
    }
    return out;
  }

  /// Gives every folder and file under [folderId] its new top-level folder
  /// and visibility.
  Future<void> _restampSubtree(
    String folderId, {
    required String rootId,
    required List<String> visibleTo,
    FolderSharing? sharing,
  }) async {
    final ids = await _subtreeIds(folderId);
    final now = DateTime.now();
    for (final id in ids.skip(1)) {
      final sub = await folder(id);
      if (sub == null) continue;
      await _putFolder(
        sub.copyWith(
          rootId: rootId,
          visibleTo: visibleTo,
          sharing: sharing ?? sub.sharing,
          updatedAt: now,
        ),
      );
    }
    final db = await _db.localDatabase;
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      _files,
      where: 'folderId IN ($placeholders) AND isDeleted = 0',
      whereArgs: ids,
    );
    for (final r in rows) {
      final f = PatientFile.fromLocalMap(r);
      await _putFile(
        f.copyWith(rootId: rootId, visibleTo: visibleTo, updatedAt: now),
      );
    }
  }

  Future<void> _putFolder(FileFolder f) async {
    final db = await _db.localDatabase;
    await db.insert(_folders, {
      ...f.toLocalMap(),
      'syncStatus': 'pending',
    }, conflictAlgorithm: LocalConflictAlgorithm.replace);
  }

  // ───────────────────────────── Files ─────────────────────────────

  /// Adds [sources] for [patientId] into [folderId] ('' for no folder).
  /// Each is copied into the app's files folder and queued for upload.
  /// Sources with a [FileSource.problem] are skipped. Returns how many were
  /// added.
  Future<int> addFiles(
    List<FileSource> sources, {
    required String patientId,
    String folderId = '',
  }) async => (await addFilesWithIds(
    sources,
    patientId: patientId,
    folderId: folderId,
  )).length;

  /// [addFiles], returning the new files' ids in the order added.
  Future<List<String>> addFilesWithIds(
    List<FileSource> sources, {
    required String patientId,
    String folderId = '',
  }) async {
    if (patientId.trim().isEmpty) {
      throw const FilesException('Choose the patient these files are for.');
    }
    final dir = await _clinicDir();
    final parent = await folder(folderId);
    if (folderId.isNotEmpty && (parent == null || parent.isDeleted)) {
      throw const FilesException('That folder no longer exists.');
    }
    final me = uid;
    final added = <String>[];
    for (final s in sources) {
      final type = s.contentType;
      if (type == null || s.problem != null) continue;
      final id = _uuid.v4();
      final name = _diskName(s.name);
      final rel = p.join(id, name);
      final dest = File(p.join(dir.path, rel));
      await dest.parent.create(recursive: true);
      final Uint8List bytes;
      if (s.path != null) {
        await File(s.path!).copy(dest.path);
        bytes = await dest.readAsBytes();
      } else if (s.bytes != null) {
        bytes = s.bytes!;
        await dest.writeAsBytes(bytes, flush: true);
      } else {
        continue;
      }
      final sha256 = await computeFileSha256(dest.path);
      final now = DateTime.now();
      final f = PatientFile(
        id: id,
        doctorId: doctorId,
        ownerUid: me,
        patientId: patientId,
        folderId: parent?.id ?? '',
        rootId: parent?.rootId ?? '',
        name: s.name.trim().isEmpty ? name : s.name.trim(),
        contentType: type,
        sizeBytes: bytes.lengthInBytes,
        visibleTo: parent?.visibleTo ?? [me],
        createdAt: now,
        updatedAt: now,
        localPath: rel,
        sha256: sha256,
      );
      await _putFile(f);
      final queued = await StorageSyncQueue.instance.enqueue(
        kind: UploadKind.patientFile,
        patientId: patientId,
        bytes: bytes,
        contentType: type,
        link: UploadLink.viaHandler(
          linkHandler,
          docId: id,
          args: {'sha256': sha256},
        ),
      );
      if (queued == null) {
        // Signed out or refused by the queue: keep it here, say so.
        await _putFile(f.copyWith(cloudStatus: FileCloudStatus.localOnly));
      } else if (FilePreviews.canPreview(type)) {
        unawaited(_makePreviews(id, bytes));
      }
      added.add(id);
    }
    _changed();
    return added;
  }

  /// Creates a new local and synced file record for a file received from a colleague.
  /// Points to the existing shared cloud blob when ready.
  Future<String> createReceivedFile({
    required FileOffer offer,
    String? localFilePath,
  }) async {
    final now = DateTime.now();
    final newId = const Uuid().v4();
    final clinicId = doctorId;
    final me = uid;

    String relPath = '';
    if (localFilePath != null) {
      try {
        final dir = await _clinicDir();
        final name = _diskName(offer.name);
        final rel = p.join(newId, name);
        final dest = File(p.join(dir.path, rel));
        await dest.parent.create(recursive: true);
        final srcFile = File(localFilePath);
        if (await srcFile.exists()) {
          await srcFile.copy(dest.path);
          relPath = rel;
        }
      } catch (_) {}
    }

    String storagePath = '';
    String viewPath = '';
    if (offer.sha256.isNotEmpty && clinicId.isNotEmpty) {
      try {
        final blobSnap = await FirebaseFirestore.instance
            .collection('clinics')
            .doc(clinicId)
            .collection('blobs')
            .doc(offer.sha256)
            .get();
        if (blobSnap.exists && blobSnap.data()?['state'] == 'ready') {
          storagePath = MedicalStorageService.blobOriginalPath(clinicId, offer.sha256);
          if (blobSnap.data()?['hasView'] == true) {
            viewPath = MedicalStorageService.blobViewPath(clinicId, offer.sha256);
          }
        }
      } catch (_) {}
    }

    final f = PatientFile(
      id: newId,
      doctorId: clinicId,
      ownerUid: me,
      patientId: offer.patientId,
      folderId: '',
      rootId: '',
      name: offer.name,
      contentType: offer.contentType,
      sizeBytes: offer.sizeBytes,
      visibleTo: [me],
      createdAt: now,
      updatedAt: now,
      localPath: relPath,
      thumb: offer.thumb,
      sha256: offer.sha256,
      storagePath: storagePath,
      viewPath: viewPath,
      receivedFromUid: offer.from,
      receivedFromName: offer.fromDoctorName,
    );

    await _putFile(f);
    _changed();
    return newId;
  }

  /// Scans local records that have a sha256 but no storagePath, and links
  /// them once the shared cloud blob has been finalized.
  Future<void> linkWhenReadyCheck() async {
    final clinic = doctorId;
    final me = uid;
    if (clinic.isEmpty || me.isEmpty) return;

    final db = await _db.localDatabase;
    final rows = await db.query(
      _files,
      where: "doctorId = ? AND ownerUid = ? AND isDeleted = 0 AND sha256 != '' AND storagePath = ''",
      whereArgs: [clinic, me],
    );
    if (rows.isEmpty) return;
    // Files already in the upload queue (waiting, uploading or failed): this
    // runs every time Files opens, and must not queue a second full copy.
    final queued = {
      for (final l in await StorageSyncQueue.instance.openLinks(linkHandler))
        l.docId,
    };

    for (final r in rows) {
      final f = PatientFile.fromLocalMap(r);
      try {
        final blobSnap = await FirebaseFirestore.instance
            .collection('clinics')
            .doc(clinic)
            .collection('blobs')
            .doc(f.sha256)
            .get();
        if (blobSnap.exists && blobSnap.data()?['state'] == 'ready') {
          final originalPath = MedicalStorageService.blobOriginalPath(clinic, f.sha256);
          final viewPath = (blobSnap.data()?['hasView'] == true)
              ? MedicalStorageService.blobViewPath(clinic, f.sha256)
              : '';
          await _patchFile(f.id, {
            'storagePath': originalPath,
            if (viewPath.isNotEmpty) 'viewPath': viewPath,
          });
        } else if (f.receivedFromUid.isNotEmpty &&
                   f.localPath.isNotEmpty &&
                   !queued.contains(f.id) &&
                   DateTime.now().difference(f.createdAt).inHours >= 2) {
          // Task N7: 2-hour delay passed; sender did not upload to cloud, recipient uploads now
          final diskFile = await localCopy(f);
          if (await diskFile.exists()) {
            final bytes = await diskFile.readAsBytes();
            await StorageSyncQueue.instance.enqueue(
              kind: UploadKind.patientFile,
              patientId: f.patientId,
              bytes: bytes,
              contentType: f.contentType,
              link: UploadLink.viaHandler(
                linkHandler,
                docId: f.id,
                args: {'sha256': f.sha256},
              ),
            );
          }
        }
      } catch (_) {}
    }
  }

  Future<void> renameFile(String id, String name) async {
    final clean = cleanName(name);
    if (clean.isEmpty) throw const FilesException('Give the file a name.');
    final f = await file(id);
    if (f == null) return;
    // Keep the extension: it is what opens the file on another computer.
    final ext = p.extension(f.name);
    final named =
        ext.isNotEmpty && p.extension(clean).toLowerCase() != ext.toLowerCase()
        ? '$clean$ext'
        : clean;
    await _putFile(f.copyWith(name: named, updatedAt: DateTime.now()));
    _changed();
  }

  /// Moves files into [folderId] ('' for no folder, private to the owner).
  Future<void> moveFiles(Iterable<String> ids, String folderId) async {
    final target = await folder(folderId);
    if (folderId.isNotEmpty && (target == null || target.isDeleted)) {
      throw const FilesException('That folder no longer exists.');
    }
    final now = DateTime.now();
    for (final id in ids) {
      final f = await file(id);
      if (f == null || f.folderId == folderId) continue;
      await _putFile(
        f.copyWith(
          folderId: target?.id ?? '',
          rootId: target?.rootId ?? '',
          visibleTo: target?.visibleTo ?? [f.ownerUid],
          updatedAt: now,
        ),
      );
    }
    _changed();
  }

  /// Assigns a file to another patient.
  Future<void> changePatient(String id, String patientId) async {
    if (patientId.trim().isEmpty) return;
    final f = await file(id);
    if (f == null || f.patientId == patientId) return;
    await _putFile(f.copyWith(patientId: patientId, updatedAt: DateTime.now()));
    _changed();
  }

  Future<void> deleteFile(String id) async {
    final f = await file(id);
    if (f == null) return;
    await _deleteFileRow(f, DateTime.now());
    _changed();
  }

  Future<void> _deleteFileRow(PatientFile f, DateTime now) async {
    await _putFile(f.copyWith(isDeleted: true, updatedAt: now));
    await StorageSyncQueue.instance.cancelByLink(linkHandler, f.id);
    await _removeLocalCopy(f);
    await StorageSyncQueue.instance.cancelByLink(viewLinkHandler, f.id);
    if (f.storagePath.isNotEmpty) {
      unawaited(_deleteObject(f.storagePath));
    }
    if (f.viewPath.isNotEmpty) unawaited(_deleteObject(f.viewPath));
  }

  Future<void> _deleteObject(String path) async {
    if (path.startsWith('clinic-blobs/')) {
      // Shared blob: do NOT delete from bucket directly.
      // Firestore cloud function cleanUpBlobs manages lifecycle based on refCount.
      return;
    }
    try {
      await MedicalStorageService.instance.delete(path);
    } catch (e) {
      // Offline, or already gone. The record is what hides it.
      debugPrint('[Files] could not delete $path: $e');
    }
  }

  Future<void> _putFile(PatientFile f) async {
    final db = await _db.localDatabase;
    await db.insert(_files, {
      ...f.toLocalMap(),
      'syncStatus': 'pending',
    }, conflictAlgorithm: LocalConflictAlgorithm.replace);
  }

  // ─────────────────────────── File contents ───────────────────────────

  Future<Directory> _clinicDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'patient_files', doctorId));
  }

  /// A name safe on every desktop file system, keeping the extension.
  static String _diskName(String name) {
    var n = name.trim().replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    if (n.isEmpty || n == '.' || n == '..') n = 'file';
    if (n.length > 120) {
      final ext = p.extension(n);
      n = '${n.substring(0, 120 - ext.length)}$ext';
    }
    return n;
  }

  /// This device's copy of [f], downloading it first when needed. Throws
  /// [FilesException] when it isn't here and can't be fetched.
  Future<File> localCopy(PatientFile f) async {
    final dir = await _clinicDir();
    if (f.localPath.isNotEmpty) {
      final existing = File(p.join(dir.path, f.localPath));
      if (await existing.exists()) {
        await LocalStorageManager.touch(existing);
        return existing;
      }
    }
    if (f.storagePath.isEmpty) {
      throw FilesException(
        f.ownerUid == uid
            ? 'This file is not on this device.'
            : 'This file has not finished uploading from the computer it was added on.',
      );
    }
    final rel = p.join(f.id, _diskName(f.name));
    final dest = File(p.join(dir.path, rel));
    await dest.parent.create(recursive: true);
    try {
      await MedicalStorageService.instance.downloadToFile(f.storagePath, dest);
      if (f.sha256.isNotEmpty) {
        final downloadedHash = await computeFileSha256(dest.path);
        if (downloadedHash.toLowerCase() != f.sha256.toLowerCase()) {
          throw const FilesException('File damaged, trying again.');
        }
      }
    } catch (e) {
      if (await dest.exists()) await dest.delete();
      if (e is FilesException) rethrow;
      throw const FilesException(
        "Couldn't download this file. Check the connection and try again.",
      );
    }
    // Device-only: not a change to sync.
    final db = await _db.localDatabase;
    await db.update(
      _files,
      {'localPath': rel},
      where: 'id = ?',
      whereArgs: [f.id],
    );
    return dest;
  }

  /// The copy on this device, if there is one (thumbnails; never downloads).
  Future<File?> existingLocalCopy(PatientFile f) async {
    if (f.localPath.isEmpty) return null;
    final file = File(p.join((await _clinicDir()).path, f.localPath));
    return await file.exists() ? file : null;
  }

  Future<void> _removeLocalCopy(PatientFile f) async {
    try {
      final dir = Directory(p.join((await _clinicDir()).path, f.id));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  /// Records where an upload landed; drops it when the file was deleted
  /// while it waited.
  Future<void> _recordUpload(UploadLinkContext ctx) async {
    final f = await file(ctx.link.docId);
    if (f == null || f.isDeleted) {
      await _deleteObject(ctx.storagePath);
      return;
    }
    await _patchFile(f.id, {'storagePath': ctx.storagePath});
    _changed();
  }

  Future<void> _recordView(UploadLinkContext ctx) async {
    final f = await file(ctx.link.docId);
    if (f == null || f.isDeleted) {
      await _deleteObject(ctx.storagePath);
      return;
    }
    await _patchFile(f.id, {'viewPath': ctx.storagePath});
    _changed();
  }

  /// Sets [values] on one record and queues it to sync, without
  /// rewriting the other columns (an upload landing at the same time
  /// keeps its path).
  Future<void> _patchFile(String id, Map<String, Object?> values) async {
    final db = await _db.localDatabase;
    await db.update(
      _files,
      {
        ...values,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'syncStatus': 'pending',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ───────────────────────────── Previews ─────────────────────────────

  /// Makes [id]'s thumbnail and, for a picture, queues its progressive
  /// view. [bytes] is the original.
  Future<void> _makePreviews(String id, Uint8List bytes) async {
    final f = await file(id);
    if (f == null || f.isDeleted) return;
    final previews = await FilePreviews.make(bytes, f.contentType);
    if (previews == null) return;
    final latest = await file(id);
    if (latest == null || latest.isDeleted) return;
    if (latest.thumb.isEmpty) await _patchFile(id, {'thumb': previews.thumb});
    final view = previews.view;
    if (view != null && latest.viewPath.isEmpty && !await _viewPending(id)) {
      await StorageSyncQueue.instance.enqueue(
        kind: UploadKind.patientFileView,
        patientId: latest.patientId,
        bytes: view,
        contentType: 'image/jpeg',
        link: UploadLink.viaHandler(
          viewLinkHandler,
          docId: id,
          args: {'sha256': latest.sha256},
        ),
      );
    }
    _changed();
  }

  Future<bool> _viewPending(String id) async =>
      (await StorageSyncQueue.instance.openLinks(
        viewLinkHandler,
      )).any((l) => l.docId == id);

  static bool _backfillStarted = false;

  /// Once a session: previews for this person's files added before
  /// previews existed, from the copies on this device.
  void _backfillPreviews() {
    if (_backfillStarted || doctorId.isEmpty) return;
    _backfillStarted = true;
    unawaited(() async {
      final db = await _db.localDatabase;
      final rows = await db.query(
        _files,
        where:
            "doctorId = ? AND ownerUid = ? AND isDeleted = 0 "
            "AND localPath != '' AND thumb = ''",
        whereArgs: [doctorId, uid],
      );
      for (final r in rows) {
        final f = PatientFile.fromLocalMap(r);
        if (!FilePreviews.canPreview(f.contentType)) continue;
        await ensurePreviews(f);
      }
    }());
  }

  /// Makes previews [f] is missing, when this device has its original and
  /// this person added it (the record is theirs to change).
  Future<void> ensurePreviews(PatientFile f) async {
    if (f.ownerUid != uid || !FilePreviews.canPreview(f.contentType)) return;
    final picture = PatientFileTypes.isViewableImage(f.contentType);
    if (f.thumb.isNotEmpty && (!picture || f.viewPath.isNotEmpty)) return;
    if (picture && f.thumb.isNotEmpty && await _viewPending(f.id)) return;
    final local = await existingLocalCopy(f);
    if (local == null) return;
    try {
      await _makePreviews(f.id, await local.readAsBytes());
    } catch (e) {
      debugPrint('[Files] previews for ${f.id}: $e');
    }
  }

  /// The complete progressive view on this device, if there is one.
  Future<File?> existingViewCopy(PatientFile f) async {
    if (f.viewPath.isEmpty) return null;
    final file = File(p.join((await _clinicDir()).path, f.id, _viewName));
    return await file.exists() ? file : null;
  }

  /// Downloads [f]'s picture for the viewer, calling [onBytes] with the
  /// bytes so far as they arrive, and returns the finished file. Reads the
  /// progressive view when there is one (it draws from any prefix), else
  /// the original, which is then kept as this device's copy.
  Future<File> streamPicture(
    PatientFile f, {
    required void Function(Uint8List soFar, int? total) onBytes,
  }) async {
    final useView = f.viewPath.isNotEmpty;
    final source = useView ? f.viewPath : f.storagePath;
    if (source.isEmpty) return localCopy(f);
    final rel = useView
        ? p.join(f.id, _viewName)
        : p.join(f.id, _diskName(f.name));
    final dest = File(p.join((await _clinicDir()).path, rel));
    await dest.parent.create(recursive: true);
    final part = File('${dest.path}.part');
    try {
      await MedicalStorageService.instance.streamToFile(
        source,
        part,
        onBytes: onBytes,
      );
      if (!useView && f.sha256.isNotEmpty) {
        final downloadedHash = await computeFileSha256(part.path);
        if (downloadedHash.toLowerCase() != f.sha256.toLowerCase()) {
          throw const FilesException('File damaged, trying again.');
        }
      }
      if (await dest.exists()) await dest.delete();
      await part.rename(dest.path);
    } catch (e) {
      debugPrint('[Files] streaming ${f.id} failed, downloading: $e');
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
      return localCopy(f);
    }
    if (!useView) {
      // Device-only: not a change to sync.
      final db = await _db.localDatabase;
      await db.update(
        _files,
        {'localPath': rel},
        where: 'id = ?',
        whereArgs: [f.id],
      );
      unawaited(ensurePreviews(f.copyWith(localPath: rel)));
    }
    return dest;
  }

  // ─────────────────────── Space on this device ───────────────────────

  /// This device's copies of files whose contents are in the cloud, for
  /// [LocalStorageManager]. Removing one only forgets the local copy: the
  /// record stays, and [localCopy] downloads it again when it is opened.
  Future<List<LocalAsset>> localCopiesInCloud() async {
    final clinic = doctorId;
    if (clinic.isEmpty) return const [];
    final dir = await _clinicDir();
    final db = await _db.localDatabase;
    final rows = await db.query(
      _files,
      columns: ['id', 'localPath', 'storagePath'],
      where:
          "doctorId = ? AND isDeleted = 0 AND localPath != '' "
          "AND storagePath != ''",
      whereArgs: [clinic],
    );
    final out = <LocalAsset>[];
    for (final r in rows) {
      final id = r['id'] as String;
      final rel = r['localPath'] as String;
      final storagePath = r['storagePath'] as String;
      final file = File(p.join(dir.path, rel));
      if (!await file.exists()) continue;
      out.add(
        LocalAsset(
          file: file,
          bytes: await file.length(),
          lastUsed: await LocalStorageManager.lastUsedOf(file),
          storagePath: storagePath,
          isStillSafe: () => _copyIsInCloud(id, rel, storagePath),
          onRemoved: () => _forgetLocalCopy(id, rel, file),
        ),
      );
    }
    // Progressive views: copies of what is in the cloud, always safe to drop.
    final views = await db.query(
      _files,
      columns: ['id', 'viewPath'],
      where: "doctorId = ? AND isDeleted = 0 AND viewPath != ''",
      whereArgs: [clinic],
    );
    for (final r in views) {
      final file = File(p.join(dir.path, r['id'] as String, _viewName));
      if (!await file.exists()) continue;
      out.add(
        LocalAsset(
          file: file,
          bytes: await file.length(),
          lastUsed: await LocalStorageManager.lastUsedOf(file),
          storagePath: r['viewPath'] as String,
          isStillSafe: () async => true,
          onRemoved: () async => notifyChanged(),
        ),
      );
    }
    return out;
  }

  /// The record has reached the cloud with this path and nothing for the
  /// file is still on its way up.
  Future<bool> _copyIsInCloud(String id, String rel, String storagePath) async {
    final db = await _db.localDatabase;
    final rows = await db.query(
      _files,
      columns: ['syncStatus', 'storagePath', 'localPath', 'isDeleted'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final r = rows.first;
    if (r['syncStatus'] != 'synced' ||
        r['storagePath'] != storagePath ||
        r['localPath'] != rel ||
        r['isDeleted'] == 1) {
      return false;
    }
    final open = await StorageSyncQueue.instance.openLinks(linkHandler);
    return !open.any((l) => l.docId == id);
  }

  Future<void> _forgetLocalCopy(String id, String rel, File file) async {
    // Device-only: not a change to sync.
    final db = await _db.localDatabase;
    await db.update(
      _files,
      {'localPath': ''},
      where: 'id = ? AND localPath = ?',
      whereArgs: [id, rel],
    );
    try {
      final parent = file.parent;
      if (await parent.exists() && await parent.list().isEmpty) {
        await parent.delete();
      }
    } catch (_) {}
    notifyChanged();
  }

  // ─────────────────────────── Sync support ───────────────────────────

  Future<List<Map<String, Object?>>> pendingRows(String table) async {
    final db = await _db.localDatabase;
    return db.query(
      table,
      where: 'doctorId = ? AND syncStatus = ?',
      whereArgs: [doctorId, 'pending'],
    );
  }

  Future<void> markSynced(String table, String id, int updatedAt) async {
    final db = await _db.localDatabase;
    // Only when it hasn't changed again since it was read.
    await db.update(
      table,
      {
        'syncStatus': 'synced',
        'lastSyncedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ? AND updatedAt = ?',
      whereArgs: [id, updatedAt],
    );
  }

  /// Applies a folder or file another device saved. A local edit that
  /// hasn't been sent yet wins.
  Future<void> applyRemote(String table, Map<String, Object?> row) async {
    final db = await _db.localDatabase;
    final id = row['id'] as String;
    final existing = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (existing.isNotEmpty && existing.first['syncStatus'] == 'pending') {
      return;
    }
    final merged = <String, Object?>{
      ...row,
      if (table == _files && existing.isNotEmpty) ...{
        'localPath': existing.first['localPath'] ?? '',
        'cloudStatus': existing.first['cloudStatus'] ?? '',
      },
      'syncStatus': 'synced',
      'lastSyncedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await db.insert(
      table,
      merged,
      conflictAlgorithm: LocalConflictAlgorithm.replace,
    );
    if (table == _files && row['isDeleted'] == 1 && existing.isNotEmpty) {
      await _removeLocalCopy(PatientFile.fromLocalMap(existing.first));
    }
  }

  /// Forgets synced records that are no longer shared with this person
  /// (or were removed elsewhere). Their local copies go too.
  Future<void> forgetAllBut(String table, Set<String> keep) async {
    final db = await _db.localDatabase;
    final rows = await db.query(
      table,
      where: 'doctorId = ? AND syncStatus = ?',
      whereArgs: [doctorId, 'synced'],
    );
    for (final r in rows) {
      final id = r['id'] as String;
      if (keep.contains(id)) continue;
      await forget(table, id);
    }
  }

  Future<void> forget(String table, String id) async {
    final db = await _db.localDatabase;
    final rows = await db.query(
      table,
      where: 'id = ? AND syncStatus = ?',
      whereArgs: [id, 'synced'],
      limit: 1,
    );
    if (rows.isEmpty) return;
    if (table == _files) {
      await _removeLocalCopy(PatientFile.fromLocalMap(rows.first));
    }
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }
}

/// The Files screen's copies, for [LocalStorageManager].
class _FilesLocalSource implements LocalAssetSource {
  @override
  String get name => 'files';

  @override
  Future<List<LocalAsset>> assets() =>
      FilesRepository.instance.localCopiesInCloud();
}
