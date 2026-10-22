import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:doctor_management_app/core/services/field_cipher.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/services/patient_local_service.dart';
import 'package:doctor_management_app/features/appointments/data/services/visits_local_service.dart';
import 'package:doctor_management_app/features/inventory/data/services/inventory_local_service.dart';
import 'package:doctor_management_app/features/revenue/data/services/revenue_local_service.dart';
import 'package:doctor_management_app/features/queue/data/services/queue_local_service.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_repository.dart';
import 'package:doctor_management_app/core/database/local_database.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/clinic/clinic_access.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';

/// Background Firestore sync for the local-first SQLite data layer.
///
/// Phase 3 keeps this intentionally simple:
/// - upload pending SQLite rows in Firestore batches
/// - download rows changed since each collection's last sync time
/// - retry by leaving rows pending on failure
/// - trigger on startup, connectivity regained, and post-write calls
class FirestoreSyncService {
  FirestoreSyncService._();

  static final FirestoreSyncService instance = FirestoreSyncService._();

  final LocalDatabaseService _databaseService = LocalDatabaseService.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<dynamic>? _connectivitySubscription;

  bool _isSyncing = false;
  bool _isStarted = false;

  /// Non-visit collections where the Firestore collection name matches
  /// the SQLite table name 1-to-1.
  static const List<String> _collections = [
    'patients',
    'revenue_entries',
    'pending_payments',
    'medicines',
    'stock_transactions',
    'walk_in_queue',
    'dental_records',
    'radiology_docs',
  ];

  /// Visit-specific Firestore collections.
  ///
  /// Both map into the single `visits` SQLite table.
  /// Key = Firestore collection name; value = the `visitType` value that
  /// every document in that collection carries.
  ///
  /// On **upload**: a pending `visits` row is routed to `appointments`
  ///   when its `visitType` is `'clinic'`, or `visitations` when `'home'`.
  /// On **download**: the collection name tells us which `visitType` to
  ///   stamp on the incoming SQLite row — the stored field is the fallback.
  static const Map<String, String> _visitFirestoreToType = {
    'appointments': 'clinic',
    'visitations': 'home',
  };

  final List<StreamSubscription> _liveSubscriptions = [];
  String? _subscribedDoctorId;

  /// Permission needed to read each synced collection (firestore.rules).
  static const Map<String, ClinicPermission> _readPermission = {
    'patients': ClinicPermission.patientsView,
    'revenue_entries': ClinicPermission.revenue,
    'pending_payments': ClinicPermission.billing,
    'medicines': ClinicPermission.inventory,
    'stock_transactions': ClinicPermission.inventory,
    'walk_in_queue': ClinicPermission.schedule,
    'dental_records': ClinicPermission.clinicalView,
    'radiology_docs': ClinicPermission.clinicalView,
    'appointments': ClinicPermission.schedule,
    'visitations': ClinicPermission.schedule,
  };

  /// Whether the signed-in person may read [collection]. Collections they
  /// can't read are neither listened to nor pulled (the rules would refuse
  /// them); their own pending writes are still pushed.
  static bool canReadCollection(String collection) {
    final access = ClinicSession.instance.access;
    if (access == null) return true;
    final perm = _readPermission[collection];
    return perm == null || access.can(perm);
  }

  StreamSubscription<ClinicAccess?>? _accessSubscription;
  String? _accessKey;

  /// Every Firestore collection this service caches locally.
  static Iterable<String> get _allSyncedCollections =>
      [..._collections, ..._visitFirestoreToType.keys];

  /// The SQLite table a collection lands in. Both visit collections share
  /// one table, and they are gated by the same permission.
  static String _tableFor(String collection) =>
      _visitFirestoreToType.containsKey(collection) ? 'visits' : collection;

  /// Which local tables and sync watermarks a person with [access] may no
  /// longer hold data for.
  ///
  /// Pure so the decision can be tested on its own: the deletion around it
  /// is glue. A null [access] purges nothing — the session is still
  /// resolving, and wiping the cache on every sign-in would be worse than
  /// waiting for the real answer.
  @visibleForTesting
  static ({Set<String> tables, Set<String> watermarks}) purgeTargetsFor(
    ClinicAccess? access,
  ) {
    if (access == null) {
      return (tables: <String>{}, watermarks: <String>{});
    }
    final tables = <String>{};
    final watermarks = <String>{};
    for (final collection in _allSyncedCollections) {
      final perm = _readPermission[collection];
      if (perm != null && !access.can(perm)) {
        tables.add(_tableFor(collection));
        // The watermark is keyed by collection for the visit collections and
        // by table name elsewhere, so clear both spellings.
        watermarks.add(collection);
        watermarks.add(_tableFor(collection));
      }
    }
    return (tables: tables, watermarks: watermarks);
  }

  /// Deletes locally cached rows for collections the signed-in person may no
  /// longer read, so losing a permission does not leave patient data sitting
  /// on the device where it stays readable offline.
  ///
  /// Pending local edits in those tables go too. Having lost read access,
  /// this device can no longer push them — the rules refuse the write — so
  /// keeping them would only leave records behind on disk. Watermarks are
  /// reset as well, so if the permission comes back the collection is
  /// downloaded again from scratch rather than resuming from a watermark
  /// that no longer matches an emptied table.
  Future<void> _purgeUnreadableCollections() async {
    final targets = purgeTargetsFor(ClinicSession.instance.access);
    if (targets.tables.isEmpty) return;

    try {
      final db = await _databaseService.localDatabase;
      for (final table in targets.tables) {
        await db.delete(table);
      }
      for (final name in targets.watermarks) {
        await db.delete(
          'sync_state',
          where: 'collectionName = ?',
          whereArgs: [name],
        );
      }
    } catch (e) {
      debugPrint('Purge after a permission change failed: $e');
    }
  }

  static String _keyFor(ClinicAccess? a) => a == null
      ? ''
      // kind and clinicalAccessScope decide whether queries narrow to the
      // doctor's assigned patients, so a change to either has to restart
      // the listeners just like a change of role or permissions.
      : '${a.clinicId}|${a.roleId}|${a.kind.value}|${a.clinicalAccessScope}|'
            '${(a.perms.map((p) => p.key).toList()..sort()).join(',')}';

  Future<void> start() async {
    if (_isStarted) return;
    _isStarted = true;

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      dynamic result,
    ) {
      try {
        if (result is ConnectivityResult) {
          if (result != ConnectivityResult.none) unawaited(synchronize());
          return;
        }
        if (result is List<ConnectivityResult>) {
          if (result.any((r) => r != ConnectivityResult.none)) {
            unawaited(synchronize());
          }
          return;
        }
        // Unknown payload shape — conservatively attempt synchronization.
        unawaited(synchronize());
      } catch (_) {
        // Swallow listener errors to avoid crashing the subscription.
      }
    });

    final doctorId = _currentDoctorId;
    if (doctorId != null) {
      _startLiveSubscriptions(doctorId);
    }

    // A role change in the same clinic changes what may be read: listen
    // again with the new set.
    _accessKey = _keyFor(ClinicSession.instance.access);
    _accessSubscription = ClinicSession.instance.stream.listen((access) {
      final key = _keyFor(access);
      if (access == null || key == _accessKey) return;
      _accessKey = key;
      final id = _currentDoctorId;
      if (id == null) return;
      _stopLiveSubscriptions();
      // Drop what this person may no longer read before listening again, so
      // a demotion takes effect on this device and not just on the server.
      unawaited(
        _purgeUnreadableCollections().then((_) {
          _startLiveSubscriptions(id);
          return synchronize();
        }),
      );
    });

    unawaited(synchronize());
  }

  Future<void> stop() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    await _accessSubscription?.cancel();
    _accessSubscription = null;
    _accessKey = null;
    _stopLiveSubscriptions();
    _isStarted = false;
    // Phase 19: reset the sync-in-progress flag so the next doctor's
    // first synchronize() call is never silently dropped.
    _isSyncing = false;
  }

  /// The tenant query for [collection], narrowed to the signed-in person's
  /// own patients when the clinic scopes its doctors that way.
  ///
  /// Patients carry the assignment, and clinical records carry a copy of
  /// their patient's (kept current by Cloud Functions). The narrowing is
  /// required rather than cosmetic: a rule for a query is satisfied from the
  /// query's own filters, so an unnarrowed read is refused outright. See
  /// `patientScopeAllowsList` / `clinicalScopeAllowsList` in firestore.rules.
  Query<Map<String, dynamic>> _scopedQuery(
    String collection,
    String doctorId,
  ) {
    final query = _firestore
        .collection(collection)
        .where('doctorId', isEqualTo: doctorId);
    final access = ClinicSession.instance.access;
    if (_narrowsToAssignment(collection, access)) {
      return query.where('assignedDoctorUids', arrayContains: access!.uid);
    }
    return query;
  }

  /// Synced collections that a scoped doctor reads only for their own
  /// patients: the patients themselves and the clinical records synced here.
  static const Set<String> _assignmentScopedCollections = {
    'patients',
    'dental_records',
    'radiology_docs',
  };

  static bool _narrowsToAssignment(String collection, ClinicAccess? access) =>
      access != null &&
      access.scopedToAssignedPatients &&
      _assignmentScopedCollections.contains(collection);

  /// Which locally cached rows to drop after a fresh server answer to a
  /// collection that is narrowed to the signed-in doctor's own patients.
  ///
  /// [serverIds] is the complete result the server just returned, so a local
  /// row missing from it is one this doctor can no longer reach — a patient
  /// reassigned to someone else, perhaps while this device was off — and its
  /// details should not stay on the device. Rows with unsent local changes
  /// are kept: they are this device's own work and have not reached the
  /// server yet. Only call this for an answer that came from the server, not
  /// from the offline cache, which may be partial.
  @visibleForTesting
  static Set<String> rowsToDropAfterScopedAnswer({
    required Iterable<Map<String, Object?>> localRows,
    required Set<String> serverIds,
  }) {
    // Only rows the server once had: a row still waiting to go up (one the
    // rules refused included) was never there to lose.
    return {
      for (final row in localRows)
        if (!serverIds.contains(row['id']) && row['syncStatus'] == 'synced')
          row['id']! as String,
    };
  }

  /// The assignment to send with a patient row, if any.
  ///
  /// Only a row this device created and has never uploaded (no lastSyncedAt)
  /// carries one, and only when it is exactly the signed-in person — the one
  /// non-empty value the rules let a client set. Anything else is left out:
  /// sending a stale or foreign assignment on an edit would be refused and
  /// leave the edit stuck unsent.
  @visibleForTesting
  static Map<String, dynamic> firstUploadAssignment(
    Map<String, Object?> row,
    String? currentUid,
  ) {
    if (row['lastSyncedAt'] != null || currentUid == null) return const {};
    final uids = Patient.assignedFromStored(row['assignedDoctorUids']);
    if (uids.length == 1 && uids.first == currentUid) {
      return {'assignedDoctorUids': uids};
    }
    return const {};
  }

  /// Applies [rowsToDropAfterScopedAnswer] to [collection]'s table.
  Future<void> _reconcileScopedCollection(
    String collection,
    String doctorId,
    Set<String> serverIds,
  ) async {
    final table = _tableFor(collection);
    final db = await _databaseService.localDatabase;
    final local = await db.query(
      table,
      columns: ['id', 'syncStatus'],
      where: 'doctorId = ?',
      whereArgs: [doctorId],
    );
    final drop = rowsToDropAfterScopedAnswer(
      localRows: local,
      serverIds: serverIds,
    );
    if (drop.isEmpty) return;
    for (final id in drop) {
      await db.delete(table, where: 'id = ?', whereArgs: [id]);
    }
    _notifyTableChanged(table);
  }

  void _startLiveSubscriptions(String doctorId) {
    if (_subscribedDoctorId == doctorId && _liveSubscriptions.isNotEmpty) {
      return;
    }
    _stopLiveSubscriptions();
    _subscribedDoctorId = doctorId;

    for (final collection in _collections) {
      if (!canReadCollection(collection)) continue;
      // Decided when the listener starts; a role or scope change restarts
      // every listener (see the access subscription in start()).
      final narrowed = _narrowsToAssignment(
        collection,
        ClinicSession.instance.access,
      );
      final sub = _scopedQuery(collection, doctorId)
          .snapshots()
          .listen((snapshot) async {
            for (final change in snapshot.docChanges) {
              try {
                final doc = change.doc;
                if (change.type == DocumentChangeType.removed) {
                  if (narrowed) {
                    // Leaving a narrowed query usually means "no longer
                    // yours", not "deleted": the reconcile below takes it off
                    // the device rather than archiving a copy on it.
                    continue;
                  }
                  await _applyRemoteDeletion(collection, doc.id, doctorId);
                } else {
                  final data = doc.data();
                  if (data == null) continue;
                  await _upsertDownloadedRow(
                    collection,
                    doc.id,
                    data,
                    doctorId,
                  );
                }
              } catch (e, st) {
                // Swallow individual doc handling errors so the listener continues.
                debugPrint(
                  'Live sync doc update failed in $collection: $e\n$st',
                );
              }
            }
            // A server answer to a narrowed query is the complete list of
            // what this doctor may hold. Anything else cached locally — a
            // patient reassigned while this device was off, which no change
            // event would ever report — comes off the device now. A cache
            // answer can be partial, so it is never used for this.
            if (narrowed && !snapshot.metadata.isFromCache) {
              try {
                await _reconcileScopedCollection(
                  collection,
                  doctorId,
                  {for (final d in snapshot.docs) d.id},
                );
              } catch (e) {
                debugPrint('Scoped reconcile of $collection failed: $e');
              }
            }
          });
      _liveSubscriptions.add(sub);
    }

    for (final firestoreCollection in _visitFirestoreToType.keys) {
      if (!canReadCollection(firestoreCollection)) continue;
      final sub = _firestore
          .collection(firestoreCollection)
          .where('doctorId', isEqualTo: doctorId)
          .snapshots()
          .listen((snapshot) async {
            for (final change in snapshot.docChanges) {
              try {
                final doc = change.doc;
                if (change.type == DocumentChangeType.removed) {
                  await _applyRemoteDeletion(
                    firestoreCollection,
                    doc.id,
                    doctorId,
                    sqliteTable: 'visits',
                  );
                } else {
                  final data = doc.data();
                  if (data == null) continue;
                  await _upsertDownloadedRow(
                    firestoreCollection,
                    doc.id,
                    data,
                    doctorId,
                    sqliteTable: 'visits',
                  );
                }
              } catch (e, st) {
                // Swallow per-doc errors so listener stays alive.
                debugPrint('Live sync doc update failed in visits: $e\n$st');
              }
            }
          });
      _liveSubscriptions.add(sub);
    }
  }

  void _stopLiveSubscriptions() {
    for (final sub in _liveSubscriptions) {
      sub.cancel();
    }
    _liveSubscriptions.clear();
    _subscribedDoctorId = null;
  }

  Future<void> triggerPostWriteSync() => synchronize();

  /// The signed-in doctor's UID, or `null` if nobody is signed in.
  ///
  /// Every Firestore read/write in this service is scoped to this value —
  /// without it, sync would pull or push every doctor's data.
  String? get _currentDoctorId => ClinicSession.instance.tenantId;

  Future<void> synchronize() async {
    if (_isSyncing) return;
    final doctorId = _currentDoctorId;
    if (doctorId == null) return; // nothing to sync without a signed-in doctor
    _isSyncing = true;

    try {
      _startLiveSubscriptions(doctorId);
      await _uploadPendingRows(doctorId);
      await _downloadChangedRows(doctorId);
    } catch (e, st) {
      // Leave pending rows untouched; the next startup/connectivity/write trigger
      // retries the same simple sync pass.
      debugPrint('Sync pass failed: $e\n$st');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _uploadPendingRows(String doctorId) async {
    final db = await _databaseService.localDatabase;

    // ── non-visit collections (SQLite table == Firestore collection) ────────
    for (final collection in _collections) {
      final rows = await db.query(
        collection,
        where: 'syncStatus = ?',
        whereArgs: ['pending'],
      );
      if (rows.isEmpty) continue;

      // Firestore limits batches to 500 operations; use a safe chunk size
      // so very large pending queues still make progress instead of failing
      // permanently.
      const int maxBatchSize = 400;
      final uploaded = <_UploadedRow>[];
      final batchRows = <Map<String, Object?>>[];
      var currentBatch = _firestore.batch();
      var batchCount = 0;

      Future<void> commitCurrentBatch() async {
        if (batchCount == 0) return;
        try {
          await currentBatch.commit();
          await _markRowsSynced(collection, uploaded.toList());
        } on FirebaseException catch (e) {
          if (e.code != 'permission-denied') rethrow;
          // One row the rules refuse fails the whole batch, and with it every
          // other row of the table on every pass. Send them one at a time.
          await _uploadRowsOneByOne(collection, batchRows.toList(), doctorId);
        }
        uploaded.clear();
        batchRows.clear();
        currentBatch = _firestore.batch();
        batchCount = 0;
      }

      for (final row in rows) {
        final id = row['id'] as String;
        // Phase 18/19: skip rows that belong to a different doctor.
        // The per-doctor DB file makes this an edge case, but guard
        // defensively so a stale row can never be uploaded under the
        // wrong account.
        final rowDoctorId = row['doctorId'] as String?;
        if (rowDoctorId != null && rowDoctorId != doctorId) continue;
        if (_refusedThisRun.contains('$collection/$id')) continue;

        final ref = _firestore.collection(collection).doc(id);
        final pendingDelete = row['pendingDelete'] == 1;

        if (pendingDelete) {
          currentBatch.delete(ref);
        } else {
          currentBatch.set(
            ref,
            _firestoreDataFor(collection, row, doctorId),
            SetOptions(merge: true),
          );
        }
        uploaded.add(_UploadedRow.of(row));
        batchRows.add(row);
        batchCount++;

        if (batchCount >= maxBatchSize) {
          await commitCurrentBatch();
        }
      }

      await commitCurrentBatch();
    }

    // ── visits table → appointments / visitations Firestore collections ──────
    await _uploadPendingVisits(db, doctorId);
  }

  /// Rows the rules refused on their own this run, as "collection/id".
  /// They stay pending on this device (so nothing drops them) and are tried
  /// again, one by one, the next time the app starts.
  final Set<String> _refusedThisRun = {};

  /// Uploads [rows] of [collection] one by one after their batch was
  /// refused. A row the rules refuse on its own (a clinic-wide radiology
  /// phrase a scoped doctor may not write, a record whose patient they
  /// cannot reach) is skipped for the rest of this run.
  Future<void> _uploadRowsOneByOne(
    String collection,
    List<Map<String, Object?>> rows,
    String doctorId,
  ) async {
    var refused = 0;
    for (final row in rows) {
      final id = row['id'] as String;
      final ref = _firestore.collection(collection).doc(id);
      try {
        if (row['pendingDelete'] == 1) {
          await ref.delete();
        } else {
          await ref.set(
            _firestoreDataFor(collection, row, doctorId),
            SetOptions(merge: true),
          );
        }
        await _markRowsSynced(collection, [_UploadedRow.of(row)]);
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
        refused++;
        _refusedThisRun.add('$collection/$id');
      }
    }
    if (refused > 0) {
      debugPrint(
        'Sync: $refused of ${rows.length} $collection rows refused by the '
        'rules; kept on this device, tried again next start.',
      );
    }
  }

  /// Uploads pending rows from the `visits` SQLite table, routing each row
  /// to the correct Firestore collection based on its `visitType`:
  ///   `'clinic'`  →  `appointments`
  ///   `'home'`    →  `visitations`
  ///
  /// Soft-deletes are broadcast to **both** collections so a document is
  /// cleaned up even if its type changed between creation and deletion.
  Future<void> _uploadPendingVisits(
    LocalDatabaseExecutor db,
    String doctorId,
  ) async {
    final rows = await db.query(
      'visits',
      where: 'syncStatus = ?',
      whereArgs: ['pending'],
    );
    if (rows.isEmpty) return;

    // Chunk visit uploads too. Because deletes need to touch both
    // collections, each operation may count as 2 writes but Firestore's batch
    // limit is per operation, so keep chunk sizes conservative.
    const int maxBatchSize = 400;
    final uploaded = <_UploadedRow>[];
    var currentBatch = _firestore.batch();
    var batchCount = 0;

    Future<void> commitCurrentBatch() async {
      if (batchCount == 0) return;
      await currentBatch.commit();
      await _markRowsSynced('visits', uploaded.toList());
      uploaded.clear();
      currentBatch = _firestore.batch();
      batchCount = 0;
    }

    for (final row in rows) {
      final id = row['id'] as String;
      // Phase 18/19: skip rows belonging to a different doctor.
      final rowDoctorId = row['doctorId'] as String?;
      if (rowDoctorId != null && rowDoctorId != doctorId) continue;

      final visitType = row['visitType'] as String? ?? 'clinic';
      final targetCollection = visitType == 'home'
          ? 'visitations'
          : 'appointments';
      final pendingDelete = row['pendingDelete'] == 1;

      if (pendingDelete) {
        currentBatch.delete(_firestore.collection('appointments').doc(id));
        currentBatch.delete(_firestore.collection('visitations').doc(id));
        // Count as two ops conservatively
        batchCount += 2;
      } else {
        final ref = _firestore.collection(targetCollection).doc(id);
        currentBatch.set(
          ref,
          _firestoreDataFor(targetCollection, row, doctorId),
          SetOptions(merge: true),
        );
        batchCount++;
      }
      uploaded.add(_UploadedRow.of(row));

      if (batchCount >= maxBatchSize) {
        await commitCurrentBatch();
      }
    }

    await commitCurrentBatch();
  }

  Future<void> _downloadChangedRows(String doctorId) async {
    // ── non-visit collections ────────────────────────────────────────────────
    for (final collection in _collections) {
      if (!canReadCollection(collection)) continue;
      final lastSyncTime = await _lastSyncTime(collection);
      Query<Map<String, dynamic>> query = _scopedQuery(collection, doctorId);
      if (lastSyncTime > 0) {
        query = query.where(
          'updatedAt',
          isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(lastSyncTime),
        );
      }
      final snapshot = await query.get();

      var newestSyncTime = lastSyncTime;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final updatedAtMillis = _timestampToMillis(data['updatedAt']);
        if (updatedAtMillis > newestSyncTime) {
          newestSyncTime = updatedAtMillis;
        }
        await _upsertDownloadedRow(collection, doc.id, data, doctorId);
      }

      if (newestSyncTime > lastSyncTime) {
        await _setLastSyncTime(collection, newestSyncTime);
      }
    }

    // ── visit Firestore collections → visits SQLite table ────────────────────
    for (final firestoreCollection in _visitFirestoreToType.keys) {
      if (!canReadCollection(firestoreCollection)) continue;
      final lastSyncTime = await _lastSyncTime(firestoreCollection);
      Query<Map<String, dynamic>> query = _firestore
          .collection(firestoreCollection)
          .where('doctorId', isEqualTo: doctorId);
      if (lastSyncTime > 0) {
        query = query.where(
          'updatedAt',
          isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(lastSyncTime),
        );
      }
      final snapshot = await query.get();

      var newestSyncTime = lastSyncTime;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final updatedAtMillis = _timestampToMillis(data['updatedAt']);
        if (updatedAtMillis > newestSyncTime) {
          newestSyncTime = updatedAtMillis;
        }
        await _upsertDownloadedRow(
          firestoreCollection,
          doc.id,
          data,
          doctorId,
          sqliteTable: 'visits',
        );
      }

      if (newestSyncTime > lastSyncTime) {
        await _setLastSyncTime(firestoreCollection, newestSyncTime);
      }
    }
  }

  Map<String, dynamic> _firestoreDataFor(
    String collection,
    Map<String, Object?> row,
    String doctorId,
  ) {
    switch (collection) {
      case 'patients':
        return {
          'doctorId': doctorId,
          'firstName': FieldCipher.encrypt(row['firstName'] as String?),
          'lastName': FieldCipher.encrypt(row['lastName'] as String?),
          'phone': FieldCipher.encrypt(row['phone'] as String?),
          'email': row['email'] as String? ?? '',
          'gender': row['gender'] as String? ?? '',
          'dateOfBirth': _timestampFromMillis(row['dateOfBirth']),
          'diagnosis': FieldCipher.encrypt(row['diagnosis'] as String?),
          'notes': FieldCipher.encrypt(row['notes'] as String?),
          'packageBalance': (row['packageBalance'] as num?)?.toDouble() ?? 0,
          'isArchived': row['isArchived'] == 1,
          'isActive': row['isActive'] == 1,
          'createdAt': _timestampFromMillis(row['createdAt']),
          'updatedAt': FieldValue.serverTimestamp(),
          // The assignment belongs to the server once a patient exists there
          // (only assignPatient changes it, and the rules refuse a client
          // that tries), so it goes up only with a patient's very first
          // upload — a doctor's own new patient, assigned to themselves.
          ...firstUploadAssignment(row, ClinicSession.instance.access?.uid),
        };
      // appointments (VisitType.clinic) and visitations (VisitType.home) share
      // the same document shape. visitType is stored in the document so the
      // collection a document lives in can always be verified, and mapsLink is
      // now included so the map preview survives a full re-download.
      case 'appointments':
      case 'visitations':
        return {
          'doctorId': doctorId,
          'patientId': row['patientId'] as String? ?? '',
          'scheduledStart': _timestampFromMillis(row['scheduledStart']),
          'durationMinutes': (row['durationMinutes'] as num?)?.toInt() ?? 30,
          'address': FieldCipher.encrypt(row['address'] as String?),
          'latitude': (row['latitude'] as num?)?.toDouble(),
          'longitude': (row['longitude'] as num?)?.toDouble(),
          'mapsLink': row['mapsLink'] as String?,
          'visitType': row['visitType'] as String? ?? 'clinic',
          'status': row['status'] as String? ?? 'scheduled',
          'isPaid': row['isPaid'] == 1,
          'amountCharged': (row['amountCharged'] as num?)?.toDouble(),
          'isDeleted': row['isDeleted'] == 1,
          'isActive': row['isActive'] == 1,
          'invoiceId': row['invoiceId'] as String?,
          'packageId': row['packageId'] as String?,
          'groupId': row['groupId'] as String?,
          'treatmentType': row['treatmentType'] as String?,
          'therapistNotes': row['therapistNotes'] == null
              ? null
              : FieldCipher.encrypt(row['therapistNotes'] as String?),
          'reminderStatus': row['reminderStatus'] as String?,
          'calendarEventId': row['calendarEventId'] as String?,
          'attendingDoctorUid': row['attendingDoctorUid'] as String? ?? '',
          'createdByUid': row['createdByUid'] as String? ?? '',
          'createdAt': _timestampFromMillis(row['createdAt']),
          'updatedAt': FieldValue.serverTimestamp(),
        };
      case 'revenue_entries':
        return {
          'doctorId': doctorId,
          'date': _timestampFromMillis(row['date']),
          'description': FieldCipher.encrypt(row['description'] as String?),
          'amount': FieldCipher.encrypt(
            ((row['amount'] as num?)?.toDouble() ?? 0).toString(),
          ),
          'type': row['type'] as String? ?? 'miscellaneous',
          'kind': row['kind'] as String? ?? 'income',
          'payer': row['payer'] == null
              ? null
              : FieldCipher.encrypt(row['payer'] as String?),
          'patientId': row['patientId'] as String?,
          'visitId': row['visitId'] as String?,
          'isDeleted': row['isDeleted'] == 1,
          'attendingDoctorUid': row['attendingDoctorUid'] as String? ?? '',
          'createdByUid': row['createdByUid'] as String? ?? '',
          'createdAt': _timestampFromMillis(row['createdAt']),
          'updatedAt': FieldValue.serverTimestamp(),
        };
      case 'pending_payments':
        return {
          'doctorId': doctorId,
          'date': _timestampFromMillis(row['date']),
          'description': FieldCipher.encrypt(row['description'] as String?),
          'amount': FieldCipher.encrypt(
            ((row['amount'] as num?)?.toDouble() ?? 0).toString(),
          ),
          'isPaid': row['isPaid'] == 1,
          'payer': row['payer'] == null
              ? null
              : FieldCipher.encrypt(row['payer'] as String?),
          'patientId': row['patientId'] as String?,
          'visitId': row['visitId'] as String?,
          'notes': row['notes'] == null
              ? null
              : FieldCipher.encrypt(row['notes'] as String?),
          'attendingDoctorUid': row['attendingDoctorUid'] as String? ?? '',
          'createdByUid': row['createdByUid'] as String? ?? '',
          'createdAt': _timestampFromMillis(row['createdAt']),
          'updatedAt': FieldValue.serverTimestamp(),
        };
      case 'medicines':
        return {
          'doctorId': doctorId,
          'name': row['name'] as String? ?? '',
          'category': row['category'] as String? ?? '',
          'unit': row['unit'] as String? ?? '',
          'currentStock': (row['currentStock'] as num?)?.toInt() ?? 0,
          'reorderThreshold': (row['reorderThreshold'] as num?)?.toInt() ?? 10,
          'goodStockLevel': (row['goodStockLevel'] as num?)?.toInt(),
          'unitPrice': (row['unitPrice'] as num?)?.toDouble(),
          'supplierName': row['supplierName'] as String?,
          'batchNumber': row['batchNumber'] as String?,
          'receiptStoragePath': row['receiptStoragePath'] as String?,
          'expiryDate': row['expiryDate'] == null
              ? null
              : _timestampFromMillis(row['expiryDate']),
          'lowStockNotifiedAt': row['lowStockNotifiedAt'] == null
              ? null
              : _timestampFromMillis(row['lowStockNotifiedAt']),
          'expiryNotifiedAt': row['expiryNotifiedAt'] == null
              ? null
              : _timestampFromMillis(row['expiryNotifiedAt']),
          'isActive': row['isActive'] == 1,
          'createdAt': _timestampFromMillis(row['createdAt']),
          'updatedAt': FieldValue.serverTimestamp(),
        };
      case 'stock_transactions':
        return {
          'medicineId': row['medicineId'] as String? ?? '',
          'doctorId': doctorId,
          'type': row['type'] as String? ?? 'restock',
          'quantity': (row['quantity'] as num?)?.toInt() ?? 0,
          'resultingStock': (row['resultingStock'] as num?)?.toInt() ?? 0,
          'note': row['note'] as String?,
          'linkedVisitId': row['linkedVisitId'] as String?,
          'batchNumber': row['batchNumber'] as String?,
          'expiryDate': row['expiryDate'] == null
              ? null
              : _timestampFromMillis(row['expiryDate']),
          'unitCost': (row['unitCost'] as num?)?.toDouble(),
          'supplierName': row['supplierName'] as String?,
          'billKey': row['billKey'] as String?,
          'groupId': row['groupId'] as String?,
          'isActive': row['isActive'] == 1,
          'createdAt': _timestampFromMillis(row['createdAt']),
          'updatedAt': FieldValue.serverTimestamp(),
        };
      case 'walk_in_queue':
        return {
          'doctorId': doctorId,
          'patientId': row['patientId'] as String?,
          'walkInName': row['walkInName'] as String?,
          'walkInPhone': row['walkInPhone'] as String?,
          'tokenNumber': (row['tokenNumber'] as num?)?.toInt() ?? 0,
          'queueDate': row['queueDate'] as String? ?? '',
          'status': row['status'] as String? ?? 'waiting',
          'priority': row['priority'] as String? ?? 'normal',
          'reason': row['reason'] as String?,
          'checkedInAt': _timestampFromMillis(row['checkedInAt']),
          'calledAt': row['calledAt'] == null
              ? null
              : _timestampFromMillis(row['calledAt']),
          'consultationStartedAt': row['consultationStartedAt'] == null
              ? null
              : _timestampFromMillis(row['consultationStartedAt']),
          'completedAt': row['completedAt'] == null
              ? null
              : _timestampFromMillis(row['completedAt']),
          'linkedVisitId': row['linkedVisitId'] as String?,
          'groupId': row['groupId'] as String?,
          'isDeleted': row['isDeleted'] == 1,
          'attendingDoctorUid': row['attendingDoctorUid'] as String? ?? '',
          'createdByUid': row['createdByUid'] as String? ?? '',
          'createdAt': _timestampFromMillis(row['createdAt']),
          'updatedAt': FieldValue.serverTimestamp(),
        };
      case 'dental_records':
        return {
          'doctorId': doctorId,
          'patientId': row['patientId'] as String? ?? '',
          'kind': row['kind'] as String? ?? '',
          'data': FieldCipher.encrypt(row['data'] as String?),
          'recordedAt': _timestampFromMillis(row['recordedAt']),
          'isDeleted': row['isDeleted'] == 1,
          'createdAt': _timestampFromMillis(row['createdAt']),
          'updatedAt': FieldValue.serverTimestamp(),
        };
      case 'radiology_docs':
        return {
          'doctorId': doctorId,
          'kind': row['kind'] as String? ?? '',
          'patientId': row['patientId'] as String? ?? '',
          'data': FieldCipher.encrypt(row['data'] as String?),
          'isDeleted': row['isDeleted'] == 1,
          'createdAt': _timestampFromMillis(row['createdAt']),
          'updatedAt': FieldValue.serverTimestamp(),
        };
      default:
        throw ArgumentError('Unsupported sync collection: $collection');
    }
  }

  /// Inserts or replaces a downloaded Firestore document into SQLite.
  ///
  /// [firestoreCollection] drives the data mapping (which fields to extract
  /// and how to coerce types). [sqliteTable] is the actual table to write to;
  /// when omitted it defaults to [firestoreCollection]. Pass `sqliteTable:
  /// 'visits'` when downloading from `appointments` or `visitations` so both
  /// Firestore collections land in the single `visits` SQLite table.
  String _decryptDiagnosisForSqlite(dynamic rawDiagnosis) {
    if (rawDiagnosis == null) return '';
    if (rawDiagnosis is String) {
      return FieldCipher.decrypt(rawDiagnosis);
    }
    if (rawDiagnosis is List) {
      final decryptedList = rawDiagnosis
          .map((d) => FieldCipher.decrypt(d.toString()))
          .where((d) => d.isNotEmpty)
          .toList();
      return Patient.diagnosisToStored(decryptedList);
    }
    return rawDiagnosis.toString();
  }

  Future<void> _ensurePatientExists(String patientId, String doctorId) async {
    if (patientId.trim().isEmpty) return;
    final db = await _databaseService.localDatabase;
    final existing = await db.query(
      'patients',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [patientId],
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    try {
      final doc = await _firestore.collection('patients').doc(patientId).get();
      if (doc.exists && doc.data() != null) {
        final patientRow = _sqliteRowFor(
          'patients',
          doc.id,
          doc.data()!,
          doctorId,
        );
        await db.insert(
          'patients',
          patientRow,
          conflictAlgorithm: LocalConflictAlgorithm.replace,
        );
        unawaited(PatientLocalService.instance.notifyPatientsChanged());
        return;
      }
    } catch (e) {
      debugPrint(
        '[FirestoreSync] Could not fetch missing parent patient $patientId from Firestore: $e',
      );
    }

    // Fallback: If patient document cannot be fetched from Firestore, create an archived minimal stub
    // to satisfy the SQLite foreign key constraint without displaying dummy data in the UI.
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await db.insert('patients', {
        'id': patientId,
        'doctorId': doctorId,
        'firstName': 'Patient',
        'lastName': '',
        'phone': '',
        'email': '',
        'gender': '',
        'dateOfBirth': now,
        'diagnosis': '[]',
        'notes': '',
        'packageBalance': 0.0,
        'isArchived': 1,
        'isActive': 1,
        'createdAt': now,
        'updatedAt': 0,
        'syncStatus': 'synced',
        'pendingDelete': 0,
        'lastSyncedAt': 0,
      }, conflictAlgorithm: LocalConflictAlgorithm.ignore);
    } catch (_) {}
  }

  Future<void> _upsertDownloadedRow(
    String firestoreCollection,
    String id,
    Map<String, dynamic> data,
    String doctorId, {
    String? sqliteTable,
  }) async {
    final db = await _databaseService.localDatabase;
    final table = sqliteTable ?? firestoreCollection;
    // Preserve any locally-pending edits: if a local row exists and has
    // `syncStatus = 'pending'`, do not overwrite it with the remote copy.
    // Phase 16: additionally, if the local row is already 'synced' but
    // locally newer than the remote document (e.g. a stale batch download
    // arriving after a live-listener write), keep the newer local copy.
    final existing = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final local = existing.first;
      if (local['syncStatus'] == 'pending') {
        // Pending local changes win — do nothing.
        return;
      }
      // For synced rows, only overwrite if the remote data is at least as
      // recent as the local copy. This prevents an older batch download from
      // clobbering a fresher live-listener write.
      // Exception: If local row is an un-synced stub (updatedAt <= 0), always overwrite.
      final localUpdatedAt = (local['updatedAt'] as num?)?.toInt() ?? 0;
      final remoteUpdatedAt = _timestampToMillis(data['updatedAt']);
      final isStub =
          localUpdatedAt <= 0 ||
          (table == 'patients' &&
              local['isArchived'] == 1 &&
              local['firstName'] == 'Patient');
      if (!isStub && remoteUpdatedAt > 0 && localUpdatedAt > remoteUpdatedAt) {
        // Local is newer — keep it.
        return;
      }
    }
    final row = _sqliteRowFor(firestoreCollection, id, data, doctorId);

    // Foreign key safety: ensure parent patient exists locally before writing to visits
    if (table == 'visits') {
      final patientId = row['patientId'] as String?;
      if (patientId != null && patientId.isNotEmpty) {
        await _ensurePatientExists(patientId, doctorId);
      }
    }

    if (existing.isNotEmpty) {
      await db.update(table, row, where: 'id = ?', whereArgs: [id]);
    } else {
      await db.insert(
        table,
        row,
        conflictAlgorithm: LocalConflictAlgorithm.replace,
      );
    }

    if (table == 'patients') {
      unawaited(PatientLocalService.instance.notifyPatientsChanged());
    } else if (table == 'visits') {
      unawaited(VisitLocalService.instance.notifyVisitsChanged());
    } else if (table == 'medicines') {
      unawaited(InventoryLocalService.instance.notifyMedicinesChanged());
    } else if (table == 'stock_transactions') {
      unawaited(InventoryLocalService.instance.notifyTransactionsChanged());
    } else if (table == 'revenue_entries') {
      unawaited(RevenueLocalService.instance.notifyRevenueEntriesChanged());
    } else if (table == 'pending_payments') {
      unawaited(RevenueLocalService.instance.notifyPendingPaymentsChanged());
    } else if (table == 'dental_records') {
      DentalRecordsRepository.notifyRecordsChanged();
    } else if (table == 'radiology_docs') {
      RadiologyRepository.notifyDocsChanged();
    }
  }

  Map<String, dynamic> _sqliteRowFor(
    String collection,
    String id,
    Map<String, dynamic> data,
    String doctorId,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    switch (collection) {
      case 'patients':
        return {
          'id': id,
          'doctorId': doctorId,
          'firstName': FieldCipher.decrypt(data['firstName'] as String? ?? ''),
          'lastName': FieldCipher.decrypt(data['lastName'] as String? ?? ''),
          'phone': FieldCipher.decrypt(data['phone'] as String? ?? ''),
          'email': data['email'] as String? ?? '',
          'gender': data['gender'] as String? ?? '',
          'dateOfBirth': _timestampToMillis(data['dateOfBirth'], fallback: now),
          'diagnosis': _decryptDiagnosisForSqlite(data['diagnosis']),
          'notes': FieldCipher.decrypt(data['notes'] as String? ?? ''),
          'packageBalance': (data['packageBalance'] as num?)?.toDouble() ?? 0,
          'isArchived': (data['isArchived'] as bool? ?? false) ? 1 : 0,
          'isActive': (data['isActive'] as bool? ?? true) ? 1 : 0,
          'createdAt': _timestampToMillis(data['createdAt'], fallback: now),
          'updatedAt': _timestampToMillis(data['updatedAt'], fallback: now),
          'syncStatus': 'synced',
          'pendingDelete': 0,
          'lastSyncedAt': now,
          // Without this the device always believed every patient was
          // unassigned, whatever the server said.
          'assignedDoctorUids': Patient.assignedToStored(
            Patient.assignedFromStored(data['assignedDoctorUids']),
          ),
        };
      // appointments → visits table with visitType = 'clinic'
      // visitations  → visits table with visitType = 'home'
      // visitType is authoritative from the collection name, not the document
      // field, so a misfiled document is corrected on download.
      case 'appointments':
      case 'visitations':
        return {
          'id': id,
          'doctorId': doctorId,
          'patientId': data['patientId'] as String? ?? '',
          'scheduledStart': _timestampToMillis(
            data['scheduledStart'],
            fallback: now,
          ),
          'durationMinutes': (data['durationMinutes'] as num?)?.toInt() ?? 30,
          'address': FieldCipher.decrypt(data['address'] as String? ?? ''),
          'latitude': (data['latitude'] as num?)?.toDouble(),
          'longitude': (data['longitude'] as num?)?.toDouble(),
          'mapsLink': data['mapsLink'] as String?,
          // Derive visitType from which collection this document came from,
          // overriding whatever the document field says.
          'visitType': _visitFirestoreToType[collection]!,
          'status': data['status'] as String? ?? 'scheduled',
          'isPaid': (data['isPaid'] as bool? ?? false) ? 1 : 0,
          'amountCharged': (data['amountCharged'] as num?)?.toDouble(),
          'isDeleted': (data['isDeleted'] as bool? ?? false) ? 1 : 0,
          'isActive': (data['isActive'] as bool? ?? true) ? 1 : 0,
          'invoiceId': data['invoiceId'] as String?,
          'packageId': data['packageId'] as String?,
          'groupId': data['groupId'] as String?,
          'treatmentType': data['treatmentType'] as String?,
          'therapistNotes': data['therapistNotes'] == null
              ? null
              : FieldCipher.decrypt(data['therapistNotes'] as String?),
          'reminderStatus': data['reminderStatus'] as String?,
          'calendarEventId': data['calendarEventId'] as String?,
          'attendingDoctorUid': data['attendingDoctorUid'] as String? ?? '',
          'createdByUid': data['createdByUid'] as String? ?? '',
          'createdAt': _timestampToMillis(data['createdAt'], fallback: now),
          'updatedAt': _timestampToMillis(data['updatedAt'], fallback: now),
          'syncStatus': 'synced',
          'pendingDelete': 0,
          'lastSyncedAt': now,
        };
      case 'revenue_entries':
        return {
          'id': id,
          'doctorId': doctorId,
          'date': _timestampToMillis(data['date'], fallback: now),
          'description': FieldCipher.decrypt(
            data['description'] as String? ?? '',
          ),
          'amount': data['amount'] is String
              ? (double.tryParse(
                      FieldCipher.decrypt(data['amount'] as String),
                    ) ??
                    0)
              : ((data['amount'] as num?)?.toDouble() ?? 0),
          'type': data['type'] as String? ?? 'miscellaneous',
          'kind': data['kind'] as String? ?? 'income',
          'payer': data['payer'] == null
              ? null
              : FieldCipher.decrypt(data['payer'] as String?),
          'patientId': data['patientId'] as String?,
          'visitId': data['visitId'] as String?,
          'isDeleted': (data['isDeleted'] as bool? ?? false) ? 1 : 0,
          'isActive': 1,
          'attendingDoctorUid': data['attendingDoctorUid'] as String? ?? '',
          'createdByUid': data['createdByUid'] as String? ?? '',
          'createdAt': _timestampToMillis(data['createdAt'], fallback: now),
          'updatedAt': _timestampToMillis(data['updatedAt'], fallback: now),
          'syncStatus': 'synced',
          'pendingDelete': 0,
          'lastSyncedAt': now,
        };
      case 'pending_payments':
        return {
          'id': id,
          'doctorId': doctorId,
          'date': _timestampToMillis(data['date'], fallback: now),
          'description': FieldCipher.decrypt(
            data['description'] as String? ?? '',
          ),
          'amount': data['amount'] is String
              ? (double.tryParse(
                      FieldCipher.decrypt(data['amount'] as String),
                    ) ??
                    0)
              : ((data['amount'] as num?)?.toDouble() ?? 0),
          'isPaid': (data['isPaid'] as bool? ?? false) ? 1 : 0,
          'payer': data['payer'] == null
              ? null
              : FieldCipher.decrypt(data['payer'] as String?),
          'patientId': data['patientId'] as String?,
          'visitId': data['visitId'] as String?,
          'notes': data['notes'] == null
              ? null
              : FieldCipher.decrypt(data['notes'] as String?),
          'isActive': 1,
          'attendingDoctorUid': data['attendingDoctorUid'] as String? ?? '',
          'createdByUid': data['createdByUid'] as String? ?? '',
          'createdAt': _timestampToMillis(data['createdAt'], fallback: now),
          'updatedAt': _timestampToMillis(data['updatedAt'], fallback: now),
          'syncStatus': 'synced',
          'pendingDelete': 0,
          'lastSyncedAt': now,
        };
      case 'medicines':
        return {
          'id': id,
          'doctorId': doctorId,
          'name': data['name'] as String? ?? '',
          'category': data['category'] as String? ?? '',
          'unit': data['unit'] as String? ?? '',
          'currentStock': (data['currentStock'] as num?)?.toInt() ?? 0,
          'reorderThreshold': (data['reorderThreshold'] as num?)?.toInt() ?? 10,
          'goodStockLevel': (data['goodStockLevel'] as num?)?.toInt(),
          'unitPrice': (data['unitPrice'] as num?)?.toDouble(),
          'supplierName': data['supplierName'] as String?,
          'batchNumber': data['batchNumber'] as String?,
          'receiptStoragePath': data['receiptStoragePath'] as String?,
          'expiryDate': data['expiryDate'] == null
              ? null
              : _timestampToMillis(data['expiryDate'], fallback: now),
          'lowStockNotifiedAt': data['lowStockNotifiedAt'] == null
              ? null
              : _timestampToMillis(data['lowStockNotifiedAt'], fallback: now),
          'expiryNotifiedAt': data['expiryNotifiedAt'] == null
              ? null
              : _timestampToMillis(data['expiryNotifiedAt'], fallback: now),
          'isActive': (data['isActive'] as bool? ?? true) ? 1 : 0,
          'createdAt': _timestampToMillis(data['createdAt'], fallback: now),
          'updatedAt': _timestampToMillis(data['updatedAt'], fallback: now),
          'syncStatus': 'synced',
          'pendingDelete': 0,
          'lastSyncedAt': now,
        };
      case 'stock_transactions':
        return {
          'id': id,
          'medicineId': data['medicineId'] as String? ?? '',
          'doctorId': doctorId,
          'type': data['type'] as String? ?? 'restock',
          'quantity': (data['quantity'] as num?)?.toInt() ?? 0,
          'resultingStock': (data['resultingStock'] as num?)?.toInt() ?? 0,
          'note': data['note'] as String?,
          'linkedVisitId': data['linkedVisitId'] as String?,
          'batchNumber': data['batchNumber'] as String?,
          'expiryDate': data['expiryDate'] == null
              ? null
              : _timestampToMillis(data['expiryDate'], fallback: now),
          'unitCost': (data['unitCost'] as num?)?.toDouble(),
          'supplierName': data['supplierName'] as String?,
          'billKey': data['billKey'] as String?,
          'groupId': data['groupId'] as String?,
          'isActive': (data['isActive'] as bool? ?? true) ? 1 : 0,
          'createdAt': _timestampToMillis(data['createdAt'], fallback: now),
          'updatedAt': _timestampToMillis(data['updatedAt'], fallback: now),
          'syncStatus': 'synced',
          'pendingDelete': 0,
          'lastSyncedAt': now,
        };
      case 'walk_in_queue':
        return {
          'id': id,
          'doctorId': doctorId,
          'patientId': data['patientId'] as String?,
          'walkInName': data['walkInName'] as String?,
          'walkInPhone': data['walkInPhone'] as String?,
          'tokenNumber': (data['tokenNumber'] as num?)?.toInt() ?? 0,
          'queueDate': data['queueDate'] as String? ?? '',
          'status': data['status'] as String? ?? 'waiting',
          'priority': data['priority'] as String? ?? 'normal',
          'reason': data['reason'] as String?,
          'checkedInAt': _timestampToMillis(data['checkedInAt'], fallback: now),
          'calledAt': data['calledAt'] == null
              ? null
              : _timestampToMillis(data['calledAt'], fallback: now),
          'consultationStartedAt': data['consultationStartedAt'] == null
              ? null
              : _timestampToMillis(
                  data['consultationStartedAt'],
                  fallback: now,
                ),
          'completedAt': data['completedAt'] == null
              ? null
              : _timestampToMillis(data['completedAt'], fallback: now),
          'linkedVisitId': data['linkedVisitId'] as String?,
          'groupId': data['groupId'] as String?,
          'isDeleted': (data['isDeleted'] as bool? ?? false) ? 1 : 0,
          'attendingDoctorUid': data['attendingDoctorUid'] as String? ?? '',
          'createdByUid': data['createdByUid'] as String? ?? '',
          'createdAt': _timestampToMillis(data['createdAt'], fallback: now),
          'updatedAt': _timestampToMillis(data['updatedAt'], fallback: now),
          'syncStatus': 'synced',
          'pendingDelete': 0,
          'lastSyncedAt': now,
        };
      case 'dental_records':
        return {
          'id': id,
          'doctorId': doctorId,
          'patientId': data['patientId'] as String? ?? '',
          'kind': data['kind'] as String? ?? '',
          'data': FieldCipher.decrypt(data['data'] as String? ?? '{}'),
          'recordedAt': _timestampToMillis(data['recordedAt'], fallback: now),
          'isDeleted': (data['isDeleted'] as bool? ?? false) ? 1 : 0,
          'createdAt': _timestampToMillis(data['createdAt'], fallback: now),
          'updatedAt': _timestampToMillis(data['updatedAt'], fallback: now),
          'syncStatus': 'synced',
          'pendingDelete': 0,
          'lastSyncedAt': now,
        };
      case 'radiology_docs':
        return {
          'id': id,
          'doctorId': doctorId,
          'kind': data['kind'] as String? ?? '',
          'patientId': data['patientId'] as String? ?? '',
          'data': FieldCipher.decrypt(data['data'] as String? ?? '{}'),
          'isDeleted': (data['isDeleted'] as bool? ?? false) ? 1 : 0,
          'createdAt': _timestampToMillis(data['createdAt'], fallback: now),
          'updatedAt': _timestampToMillis(data['updatedAt'], fallback: now),
          'syncStatus': 'synced',
          'pendingDelete': 0,
          'lastSyncedAt': now,
        };
      default:
        throw ArgumentError('Unsupported sync collection: $collection');
    }
  }

  /// Marks the uploaded [rows] synced, except any changed while they were
  /// uploading: those stay pending and go up on the next pass. Otherwise
  /// the change would never be uploaded, and the server's copy (stamped
  /// later) would come back and overwrite it.
  Future<void> _markRowsSynced(
    String collection,
    List<_UploadedRow> rows,
  ) async {
    if (rows.isEmpty) return;

    final db = await _databaseService.localDatabase;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final row in rows) {
      await db.update(
        collection,
        {'syncStatus': 'synced', 'pendingDelete': 0, 'lastSyncedAt': now},
        where: row.stamped ? 'id = ? AND updatedAt IS ?' : 'id = ?',
        whereArgs: [row.id, if (row.stamped) row.updatedAt],
      );
    }
  }

  Future<int> _lastSyncTime(String collection) async {
    final db = await _databaseService.localDatabase;
    final rows = await db.query(
      'sync_state',
      columns: ['lastSyncTime'],
      where: 'collectionName = ?',
      whereArgs: [collection],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['lastSyncTime'] as num?)?.toInt() ?? 0;
  }

  Future<void> _setLastSyncTime(String collection, int millis) async {
    final db = await _databaseService.localDatabase;
    final updated = await db.update(
      'sync_state',
      {
        'lastSyncTime': millis,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'collectionName = ?',
      whereArgs: [collection],
    );
    if (updated > 0) return;

    await db.insert('sync_state', {
      'collectionName': collection,
      'lastSyncTime': millis,
      'hasCompletedInitialMigration': 0,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Timestamp _timestampFromMillis(Object? value) {
    final millis =
        (value as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    return Timestamp.fromMillisecondsSinceEpoch(millis);
  }

  int _timestampToMillis(Object? value, {int? fallback}) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is num) return value.toInt();
    return fallback ?? 0;
  }

  /// Apply a remote deletion (Firestore remove) into the local SQLite cache.
  ///
  /// Tries to mark rows soft-deleted (set `isDeleted=1` or `isArchived=1`) and
  /// mark them `syncStatus='synced'`. If the table has no suitable soft-delete
  /// column, falls back to deleting the local row. Notifies local services
  /// after changes so UI updates.
  Future<void> _applyRemoteDeletion(
    String firestoreCollection,
    String id,
    String doctorId, {
    String? sqliteTable,
  }) async {
    final db = await _databaseService.localDatabase;
    final table = sqliteTable ?? firestoreCollection;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Phase 17: if the local row has a pending local delete already
    // queued, the upload loop will push it to Firestore on the next
    // sync pass.  Do not clear syncStatus or pendingDelete here — just
    // let the upload complete normally.  The row will transition to
    // 'synced' once the upload succeeds.
    final pendingRows = await db.query(
      table,
      columns: ['syncStatus', 'pendingDelete'],
      where: 'id = ? AND doctorId = ?',
      whereArgs: [id, doctorId],
      limit: 1,
    );
    if (pendingRows.isNotEmpty &&
        pendingRows.first['syncStatus'] == 'pending' &&
        pendingRows.first['pendingDelete'] == 1) {
      // Local delete is already pending upload — the remote removal is
      // the expected echo.  Mark it synced so the upload loop won't
      // re-upload the deleted document.
      await db.update(
        table,
        {'syncStatus': 'synced', 'pendingDelete': 0, 'lastSyncedAt': now},
        where: 'id = ? AND doctorId = ?',
        whereArgs: [id, doctorId],
      );
      _notifyTableChanged(table);
      return;
    }

    // Try marking as soft-deleted via commonly used columns.
    // Order: isDeleted, isArchived. If neither affects a row, delete it.
    final hasIsActive = table != 'dental_records' && table != 'radiology_docs';
    final isDeletedPayload = <String, Object?>{
      'isDeleted': 1,
      if (hasIsActive) 'isActive': 0,
      'syncStatus': 'synced',
      'pendingDelete': 0,
      'lastSyncedAt': now,
    };
    var updatedIsDeleted = 0;
    try {
      updatedIsDeleted = await db.update(
        table,
        isDeletedPayload,
        where: 'id = ? AND doctorId = ?',
        whereArgs: [id, doctorId],
      );
    } catch (_) {
      // This table has no isDeleted column — patients, for one. Fall through
      // to isArchived below. Before this, the error escaped to the listener,
      // which swallowed it, and a patient removed on the server stayed on
      // the device as though nothing had happened.
    }
    if (updatedIsDeleted > 0) {
      _notifyTableChanged(table);
      return;
    }

    if (hasIsActive) {
      const synced = {'syncStatus': 'synced', 'pendingDelete': 0};
      var updated = 0;
      try {
        updated = await db.update(
          table,
          {'isArchived': 1, 'isActive': 0, ...synced, 'lastSyncedAt': now},
          where: 'id = ? AND doctorId = ?',
          whereArgs: [id, doctorId],
        );
      } catch (_) {
        // No isArchived column either (medicines): isActive alone hides it.
        updated = await db.update(
          table,
          {'isActive': 0, ...synced, 'lastSyncedAt': now},
          where: 'id = ? AND doctorId = ?',
          whereArgs: [id, doctorId],
        );
      }
      if (updated > 0) {
        _notifyTableChanged(table);
        return;
      }
    }

    // No soft-delete column matched; remove the row entirely.
    final deleted = await db.delete(
      table,
      where: 'id = ? AND doctorId = ?',
      whereArgs: [id, doctorId],
    );
    if (deleted > 0) {
      _notifyTableChanged(table);
    }
  }

  void _notifyTableChanged(String table) {
    switch (table) {
      case 'patients':
        unawaited(PatientLocalService.instance.notifyPatientsChanged());
        break;
      case 'visits':
        unawaited(VisitLocalService.instance.notifyVisitsChanged());
        break;
      case 'medicines':
        unawaited(InventoryLocalService.instance.notifyMedicinesChanged());
        break;
      case 'stock_transactions':
        unawaited(InventoryLocalService.instance.notifyTransactionsChanged());
        break;
      case 'revenue_entries':
        unawaited(RevenueLocalService.instance.notifyRevenueEntriesChanged());
        break;
      case 'pending_payments':
        unawaited(RevenueLocalService.instance.notifyPendingPaymentsChanged());
        break;
      case 'walk_in_queue':
        unawaited(QueueLocalService.instance.notifyQueueChanged());
        break;
      case 'dental_records':
        DentalRecordsRepository.notifyRecordsChanged();
        break;
      case 'radiology_docs':
        RadiologyRepository.notifyDocsChanged();
        break;
      default:
        break;
    }
  }
}

/// A row as it was uploaded: its id and, when its table has one, its
/// `updatedAt` then, to tell whether it changed while uploading.
class _UploadedRow {
  _UploadedRow.of(Map<String, Object?> row)
    : id = row['id'] as String,
      stamped = row.containsKey('updatedAt'),
      updatedAt = row['updatedAt'];

  final String id;
  final bool stamped;
  final Object? updatedAt;
}
