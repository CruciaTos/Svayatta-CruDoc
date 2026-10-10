import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/services/field_cipher.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';

/// Keeps the Files screen's folders and files in step with Firestore
/// (`file_folders`, `patient_files`).
///
/// Unlike the clinic-wide collections in `FirestoreSyncService`, these are
/// per person: each listens only to what is shared with them, with two
/// queries per collection (`visibleTo` contains their uid, or contains
/// [kFilesTeam]), which is what firestore.rules lets them list. A record
/// that stops being shared with them leaves the query and is forgotten
/// here.
///
/// Starts with the data layer on phones and Macs, and on first use where
/// that layer doesn't run in the background (Windows).
class FilesCloudSync {
  FilesCloudSync._();

  static final FilesCloudSync instance = FilesCloudSync._();

  static const _filesCollection = 'patient_files';
  static const _foldersCollection = 'file_folders';

  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _subs =
      [];

  /// `clinic|person` the listeners were started for.
  String? _key;

  /// Ids seen by each listener's latest snapshot, for forgetting records
  /// no longer shared.
  final Map<String, Set<String>> _seen = {};
  bool _pushing = false;
  bool _pushAgain = false;

  FilesRepository get _repo => FilesRepository.instance;

  bool get _available => Firebase.apps.isNotEmpty;

  /// Starts listening for the signed-in person, or restarts after they or
  /// their clinic changed. Cheap to call often.
  void ensureStarted() {
    if (!_available) return;
    final doctorId = ClinicSession.instance.tenantId;
    final uid = _repo.uid;
    if (doctorId == null || doctorId.isEmpty || uid.isEmpty) return;
    final access = ClinicSession.instance.access;
    if (access != null && !access.can(ClinicPermission.clinicalView)) {
      return; // The rules would refuse every read.
    }
    final key = '$doctorId|$uid';
    if (_key == key) return;
    stop();
    _key = key;
    for (final collection in [_foldersCollection, _filesCollection]) {
      for (final who in [uid, kFilesTeam]) {
        final listener = '$collection|$who';
        _subs.add(
          FirebaseFirestore.instance
              .collection(collection)
              .where('doctorId', isEqualTo: doctorId)
              .where('visibleTo', arrayContains: who)
              .snapshots()
              .listen(
                (snap) => _onSnapshot(collection, listener, snap),
                onError: (Object e) =>
                    debugPrint('[FilesCloudSync] $listener: $e'),
              ),
        );
      }
    }
    kick();
  }

  void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _seen.clear();
    _key = null;
  }

  Future<void> _onSnapshot(
    String collection,
    String listener,
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    final table = _tableFor(collection);
    try {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.removed) continue;
        final data = change.doc.data();
        if (data == null) continue;
        await _repo.applyRemote(
          table,
          _localRow(collection, change.doc.id, data),
        );
      }
      _seen[listener] = {for (final d in snap.docs) d.id};
      // Once both queries for this collection have answered, anything
      // synced here that neither returned is no longer shared with us.
      final pair = [
        for (final k in _seen.keys)
          if (k.startsWith('$collection|')) _seen[k]!,
      ];
      if (pair.length == 2) {
        await _repo.forgetAllBut(table, {...pair[0], ...pair[1]});
      }
      FilesRepository.notifyChanged();
    } catch (e, st) {
      debugPrint('[FilesCloudSync] applying $collection failed: $e\n$st');
    }
  }

  static String _tableFor(String collection) =>
      collection == _filesCollection ? 'patient_files' : 'file_folders';

  /// Sends local changes. Folders first, top-level ones before the folders
  /// in them, then files: the rules check each against its top-level
  /// folder as already saved.
  void kick() {
    if (!_available || _key == null) return;
    unawaited(_push());
  }

  Future<void> _push() async {
    if (_pushing) {
      _pushAgain = true;
      return;
    }
    _pushing = true;
    try {
      do {
        _pushAgain = false;
        // sqflite's result list is read-only; sort a copy.
        final folders = [...await _repo.pendingRows('file_folders')];
        folders.sort((a, b) {
          final at = a['id'] == a['rootId'] ? 0 : 1;
          final bt = b['id'] == b['rootId'] ? 0 : 1;
          return at.compareTo(bt);
        });
        for (final row in folders) {
          await _send(_foldersCollection, row);
        }
        for (final row in await _repo.pendingRows('patient_files')) {
          await _send(_filesCollection, row);
        }
      } while (_pushAgain);
    } finally {
      _pushing = false;
    }
  }

  Future<void> _send(String collection, Map<String, Object?> row) async {
    final id = row['id'] as String;
    try {
      await FirebaseFirestore.instance
          .collection(collection)
          .doc(id)
          .set(_firestoreData(collection, row));
      await _repo.markSynced(
        _tableFor(collection),
        id,
        row['updatedAt'] as int? ?? 0,
      );
    } catch (e) {
      // Offline or refused: stays pending and goes with the next change.
      debugPrint('[FilesCloudSync] could not save $collection/$id: $e');
    }
  }

  /// The stored JSON list, in its stored order (the rules compare lists).
  static List<String> _list(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    final d = jsonDecode(raw);
    return d is List ? [for (final e in d) '$e'] : const [];
  }

  static Map<String, Object?> _firestoreData(
    String collection,
    Map<String, Object?> row,
  ) {
    Timestamp ts(Object? ms) =>
        Timestamp.fromMillisecondsSinceEpoch(ms as int? ?? 0);
    final common = {
      'doctorId': row['doctorId'] as String? ?? '',
      'ownerUid': row['ownerUid'] as String? ?? '',
      'rootId': row['rootId'] as String? ?? '',
      // Names can carry a patient's name: encrypted like other free text.
      'name': FieldCipher.encrypt(row['name'] as String?),
      'visibleTo': _list(row['visibleTo']),
      'isDeleted': row['isDeleted'] == 1,
      'createdAt': ts(row['createdAt']),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (collection == _foldersCollection) {
      return {
        ...common,
        'parentId': row['parentId'] as String? ?? '',
        'sharing': row['sharing'] as String? ?? 'private',
      };
    }
    return {
      ...common,
      'patientId': row['patientId'] as String? ?? '',
      'folderId': row['folderId'] as String? ?? '',
      'contentType': row['contentType'] as String? ?? '',
      'sizeBytes': (row['sizeBytes'] as num?)?.toInt() ?? 0,
      'storagePath': row['storagePath'] as String? ?? '',
    };
  }

  static Map<String, Object?> _localRow(
    String collection,
    String id,
    Map<String, dynamic> d,
  ) {
    int ms(Object? v) => v is Timestamp
        ? v.millisecondsSinceEpoch
        : DateTime.now().millisecondsSinceEpoch;
    final visibleTo = [
      for (final e in (d['visibleTo'] as List? ?? const [])) '$e',
    ];
    final common = {
      'id': id,
      'doctorId': d['doctorId'] as String? ?? '',
      'ownerUid': d['ownerUid'] as String? ?? '',
      'rootId': d['rootId'] as String? ?? '',
      'name': FieldCipher.decrypt(d['name'] as String?),
      'isDeleted': (d['isDeleted'] as bool? ?? false) ? 1 : 0,
      'createdAt': ms(d['createdAt']),
      'updatedAt': ms(d['updatedAt']),
    };
    if (collection == _foldersCollection) {
      return FileFolder.fromLocalMap({
        ...common,
        'parentId': d['parentId'] as String? ?? '',
        'sharing': d['sharing'] as String? ?? 'private',
      }).copyWith(visibleTo: visibleTo).toLocalMap();
    }
    return PatientFile.fromLocalMap({
      ...common,
      'patientId': d['patientId'] as String? ?? '',
      'folderId': d['folderId'] as String? ?? '',
      'contentType': d['contentType'] as String? ?? '',
      'sizeBytes': (d['sizeBytes'] as num?)?.toInt() ?? 0,
      'storagePath': d['storagePath'] as String? ?? '',
    }).copyWith(visibleTo: visibleTo).toLocalMap();
  }
}
