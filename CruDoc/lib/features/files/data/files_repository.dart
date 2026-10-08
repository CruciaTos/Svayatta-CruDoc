import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/database/local_database.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/core/services/medical_storage_service.dart';
import 'package:doctor_management_app/core/services/storage_sync_queue.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
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
    var added = 0;
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
      );
      await _putFile(f);
      final queued = await StorageSyncQueue.instance.enqueue(
        kind: UploadKind.patientFile,
        patientId: patientId,
        bytes: bytes,
        contentType: type,
        link: UploadLink.viaHandler(linkHandler, docId: id),
      );
      if (queued == null) {
        // Signed out or refused by the queue: keep it here, say so.
        await _putFile(f.copyWith(cloudStatus: FileCloudStatus.localOnly));
      }
      added++;
    }
    _changed();
    return added;
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
    if (f.storagePath.isNotEmpty) {
      unawaited(_deleteObject(f.storagePath));
    }
  }

  Future<void> _deleteObject(String path) async {
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
      if (await existing.exists()) return existing;
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
    } catch (e) {
      if (await dest.exists()) await dest.delete();
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
    await _putFile(
      f.copyWith(storagePath: ctx.storagePath, updatedAt: DateTime.now()),
    );
    _changed();
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
