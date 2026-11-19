import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:doctor_management_app/core/services/encryption_key_manager.dart';
import 'package:doctor_management_app/core/services/field_cipher.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/core/services/sync_row_mapper.dart';
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

  /// Documents per page when catching up or comparing ids.
  static const int _pageSize = 300;

  /// How far behind the saved cursor each catch-up and live listener
  /// starts. A server timestamp is assigned before its write becomes
  /// visible, so a write stamped just before the cursor can show up after a
  /// later one; the overlap re-reads that stretch, and versions already held
  /// are skipped.
  static const Duration _cursorOverlap = Duration(minutes: 10);

  /// How often every server id is compared with this device's rows even
  /// when the counts agree: catches what a count can't (a delete and an
  /// add that cancel out, documents without a usable updatedAt).
  static const Duration _fullReconcileEvery = Duration(days: 7);

  /// The same for a doctor narrowed to assigned patients, where a swapped
  /// assignment leaves the count unchanged. Replaces the reconcile that ran
  /// on every snapshot of the old unbounded listener.
  static const Duration _scopedReconcileEvery = Duration(hours: 6);

  /// Count checks run on launch, reconnect and access change (post-write
  /// syncs skip them), at most this often, and at least hourly.
  static const Duration _countCheckMinGap = Duration(minutes: 15);
  static const Duration _countCheckMaxGap = Duration(hours: 1);

  /// Pages smaller than this are decrypted here: spawning a worker isolate
  /// costs more than they do.
  static const int _workerMinDocs = 16;

  /// One live listener per collection, attached once it has caught up.
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _liveByCollection = {};
  String? _subscribedDoctorId;

  /// Collections whose catch-up finished in this session.
  final Set<String> _caughtUpThisSession = {};

  /// Serializes writes into each table (catch-up pages, live snapshots,
  /// reconciles), so an older answer is never written over a newer one.
  final Map<String, Future<void>> _tableLocks = {};

  /// Collections to compare id by id on the next pass, and those whose rows
  /// must be rewritten even when the version matches (see
  /// [_noteAccessShape]).
  final Set<String> _forceReconcile = {};
  final Set<String> _forceRewrite = {};
  String? _pendingAccessShape;

  /// Bumped by [stop]: a catch-up, reconcile or live snapshot started under
  /// an older generation (or another doctor) stops before writing rows or
  /// moving a cursor into whichever database is open now.
  int _generation = 0;

  bool _countCheckDue = true;
  DateTime? _lastCountCheckRun;
  bool _syncAgain = false;
  bool _decryptWorkerFailed = false;

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
  static Iterable<String> get _allSyncedCollections => [
    ..._collections,
    ..._visitFirestoreToType.keys,
  ];

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
      // Downloaded from scratch if the permission comes back.
      _caughtUpThisSession.removeAll(targets.watermarks);
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
    _countCheckDue = true;
    _lastCountCheckRun = null;

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      dynamic result,
    ) {
      try {
        if (result is ConnectivityResult) {
          if (result != ConnectivityResult.none) _syncAfterReconnect();
          return;
        }
        if (result is List<ConnectivityResult>) {
          if (result.any((r) => r != ConnectivityResult.none)) {
            _syncAfterReconnect();
          }
          return;
        }
        // Unknown payload shape — conservatively attempt synchronization.
        _syncAfterReconnect();
      } catch (_) {
        // Swallow listener errors to avoid crashing the subscription.
      }
    });

    await _scrubClinicalFields();
    // Live listeners attach inside synchronize(), once each collection has
    // caught up: listening to a collection never downloaded here would pull
    // all of it at once.

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
        _purgeUnreadableCollections().then((_) => _scrubClinicalFields()).then((
          _,
        ) {
          _countCheckDue = true;
          _lastCountCheckRun = null;
          return synchronize();
        }),
      );
    });

    unawaited(synchronize());
  }

  void _syncAfterReconnect() {
    _countCheckDue = true;
    unawaited(synchronize());
  }

  Future<void> stop() async {
    _generation++;
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
    _syncAgain = false;
    _caughtUpThisSession.clear();
    _forceReconcile.clear();
    _forceRewrite.clear();
    _pendingAccessShape = null;
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
  ) => scopedQueryFor(_firestore, collection, doctorId);

  /// [_scopedQuery] for other services that read the same collections
  /// (InitialFirestoreMigrationService), so they narrow the same way.
  static Query<Map<String, dynamic>> scopedQueryFor(
    FirebaseFirestore firestore,
    String collection,
    String doctorId,
  ) {
    final query = firestore
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

  /// Whether a patient upload leaves out notes and conditions.
  ///
  /// Someone without clinical access never holds the real values (see
  /// ClinicSession.holdsClinicalFields), so sending theirs would blank the
  /// patient's on the server; the upload is a merge, so leaving them out
  /// keeps the server's. Except a patient's first upload: the front desk
  /// enters the condition when registering someone.
  @visibleForTesting
  static bool omitsClinicalFields(
    Map<String, Object?> row,
    bool holdsClinicalFields,
  ) => !holdsClinicalFields && row['lastSyncedAt'] != null;

  /// Blanks notes and conditions already on this device when the signed-in
  /// person may not hold them, keeping a new patient's that hasn't gone up.
  Future<void> _scrubClinicalFields() async {
    if (ClinicSession.instance.holdsClinicalFields) return;
    try {
      final db = await _databaseService.localDatabase;
      final changed = await db.update(
        'patients',
        {'diagnosis': '[]', 'notes': ''},
        where:
            "lastSyncedAt IS NOT NULL AND (notes != '' OR diagnosis != '[]')",
      );
      if (changed > 0) _notifyTableChanged('patients');
    } catch (e) {
      debugPrint('Clearing clinical fields from this device failed: $e');
    }
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

  /// Applies [rowsToDropAfterScopedAnswer] to [collection]'s table, given
  /// every id the server holds for this doctor. Returns how many rows went.
  Future<int> _reconcileScopedCollection(
    String collection,
    String doctorId,
    Set<String> serverIds, {
    required int syncedBefore,
  }) async {
    final table = _tableFor(collection);
    final db = await _databaseService.localDatabase;
    final local = await db.query(
      table,
      columns: ['id', 'syncStatus'],
      // Only rows that came from (or reached) the server before the ids
      // were read.
      where: 'doctorId = ? AND lastSyncedAt IS NOT NULL AND lastSyncedAt < ?',
      whereArgs: [doctorId, syncedBefore],
    );
    final drop = rowsToDropAfterScopedAnswer(
      localRows: local,
      serverIds: serverIds,
    );
    if (drop.isEmpty) return 0;
    return _dropSyncedRows(table, drop);
  }

  /// Deletes the synced rows among [ids] from [table] (rows waiting to
  /// upload stay), one change notification for all. A row something else
  /// still points at (a patient with visits) is kept, not fatal.
  Future<int> _dropSyncedRows(String table, Set<String> ids) async {
    final db = await _databaseService.localDatabase;
    var dropped = 0;
    for (final id in ids) {
      try {
        dropped += await db.delete(
          table,
          where: 'id = ? AND syncStatus = ?',
          whereArgs: [id, 'synced'],
        );
      } catch (e) {
        debugPrint('[FirestoreSync] could not drop $table/$id: $e');
      }
    }
    if (dropped > 0) _notifyTableChanged(table);
    return dropped;
  }

  /// Attaches a live listener to every readable collection that has caught
  /// up and has none yet. Each listens only to documents changed since its
  /// cursor (less [_cursorOverlap]), not to the whole collection: everything
  /// older is already in SQLite.
  Future<void> _attachLiveListeners(String doctorId) async {
    // Not before start() (a write can sync during the first pull), and never
    // for a session that has since stopped or switched.
    if (!_isStarted || _currentDoctorId != doctorId) return;
    if (_subscribedDoctorId != doctorId) {
      _stopLiveSubscriptions();
      _subscribedDoctorId = doctorId;
    }
    for (final collection in _allSyncedCollections) {
      if (!canReadCollection(collection)) continue;
      if (_liveByCollection.containsKey(collection)) continue;
      // Only after a catch-up finished in this session: a cursor left
      // mid-collection by an interrupted first pull, or one months old,
      // would make the listener the unbounded download that catch-up pages
      // through. The next successful catch-up attaches it.
      if (!_caughtUpThisSession.contains(collection)) continue;
      final cursor = await _readCursor(collection);
      // Stopped, re-scoped or attached elsewhere while reading the cursor.
      if (!_isStarted ||
          _subscribedDoctorId != doctorId ||
          _liveByCollection.containsKey(collection) ||
          !canReadCollection(collection)) {
        continue;
      }
      // Caught up with nothing on the server: only what's written from now.
      final fromMs = cursor.ms > 0
          ? _overlapStart(cursor.ms)
          : _overlapStart(DateTime.now().millisecondsSinceEpoch);
      _liveByCollection[collection] = _listen(collection, doctorId, fromMs);
    }
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> _listen(
    String collection,
    String doctorId,
    int fromMs,
  ) {
    // Decided when the listener starts; a role or scope change restarts
    // every listener (see the access subscription in start()).
    final narrowed = _narrowsToAssignment(
      collection,
      ClinicSession.instance.access,
    );
    final table = _tableFor(collection);
    final generation = _generation;
    final query = _scopedQuery(collection, doctorId).where(
      'updatedAt',
      isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(fromMs),
    );
    late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> sub;
    sub = query.snapshots().listen(
      (snapshot) => unawaited(
        _locked(
          table,
          () => _onLiveSnapshot(
            collection,
            doctorId,
            narrowed,
            snapshot,
            generation,
          ),
        ),
      ),
      onError: (Object e) {
        debugPrint('Live listener on $collection: $e');
        // The stream has ended; the next sync pass attaches a new one.
        if (identical(_liveByCollection[collection], sub)) {
          _liveByCollection.remove(collection);
        }
      },
    );
    return sub;
  }

  Future<void> _onLiveSnapshot(
    String collection,
    String doctorId,
    bool narrowed,
    QuerySnapshot<Map<String, dynamic>> snapshot,
    int generation,
  ) async {
    bool current() =>
        _generation == generation && _subscribedDoctorId == doctorId;
    if (!current()) return;
    final changed = <DocumentSnapshot<Map<String, dynamic>>>[];
    final removed = <String>[];
    for (final change in snapshot.docChanges) {
      if (change.type == DocumentChangeType.removed) {
        // This device's own write still waiting for the server: its
        // serverTimestamp placeholder fails the updatedAt filter locally, so
        // the document leaves the query until the write is acknowledged and
        // it comes back. Not a delete.
        if (snapshot.metadata.hasPendingWrites ||
            change.doc.metadata.hasPendingWrites) {
          continue;
        }
        removed.add(change.doc.id);
      } else {
        changed.add(change.doc);
      }
    }
    try {
      for (var i = 0; i < changed.length; i += _pageSize) {
        await _applyDocs(
          collection,
          doctorId,
          changed.sublist(i, math.min(i + _pageSize, changed.length)),
          stillCurrent: current,
        );
      }
    } catch (e, st) {
      // The cursor stays put, so the next catch-up fetches these again.
      debugPrint('Live sync update failed in $collection: $e\n$st');
      return;
    }
    for (final id in removed) {
      if (!current()) return;
      try {
        await _applyLiveRemoval(collection, doctorId, narrowed, id, current);
      } catch (e, st) {
        // Swallow per-doc errors so the listener stays alive.
        debugPrint('Live sync removal failed in $collection: $e\n$st');
      }
    }
    // Only from a server answer, and only after its rows committed.
    if (snapshot.metadata.isFromCache) return;
    final newest = _newestOf(changed);
    if (newest == null || !current()) return;
    try {
      await _saveCursor(collection, newest.ms, newest.id);
    } catch (e) {
      debugPrint('[FirestoreSync] saving the $collection cursor failed: $e');
    }
  }

  /// A document left a live query. Under the updatedAt filter that is
  /// normally a delete; a narrowed query also loses a patient (and their
  /// records) reassigned to someone else, and a visit used to leave its old
  /// date window. Looked up on the server to tell which.
  Future<void> _applyLiveRemoval(
    String collection,
    String doctorId,
    bool narrowed,
    String id,
    bool Function() stillCurrent,
  ) async {
    final table = _tableFor(collection);
    // An edit made here and not yet uploaded wins; the upload settles it.
    if (await _isPendingLocally(table, id, doctorId)) return;
    DocumentSnapshot<Map<String, dynamic>>? fetched;
    try {
      fetched = await _firestore
          .collection(collection)
          .doc(id)
          .get(const GetOptions(source: Source.server));
    } on FirebaseException catch (e) {
      if (!(narrowed && e.code == 'permission-denied')) {
        // Couldn't ask (offline, a blip): never delete on a guess. The next
        // reconcile settles it.
        return;
      }
      // Refused: no longer this doctor's to read.
      fetched = null;
    }
    if (!stillCurrent()) return;
    final doc = fetched;
    final data = doc?.data();
    if (doc != null &&
        doc.exists &&
        data != null &&
        (!narrowed ||
            Patient.assignedFromStored(
              data['assignedDoctorUids'],
            ).contains(ClinicSession.instance.access?.uid))) {
      // Still there (and still this doctor's): keep it, with its new data.
      await _applyDocs(collection, doctorId, [doc], stillCurrent: stillCurrent);
    } else if (narrowed) {
      // Leaving a narrowed query usually means "no longer yours", not
      // "deleted": it comes off the device rather than being archived on it.
      await _dropSyncedRows(table, {id});
    } else {
      await _applyRemoteDeletion(collection, id, doctorId, sqliteTable: table);
    }
  }

  Future<bool> _isPendingLocally(
    String table,
    String id,
    String doctorId,
  ) async {
    final db = await _databaseService.localDatabase;
    final rows = await db.query(
      table,
      columns: ['syncStatus'],
      where: 'id = ? AND doctorId = ?',
      whereArgs: [id, doctorId],
      limit: 1,
    );
    return rows.isNotEmpty && rows.first['syncStatus'] == 'pending';
  }

  void _stopLiveSubscriptions() {
    for (final sub in _liveByCollection.values) {
      sub.cancel();
    }
    _liveByCollection.clear();
    _subscribedDoctorId = null;
  }

  /// Runs [body] after every earlier write into [table] has finished.
  Future<T> _locked<T>(String table, Future<T> Function() body) {
    final previous = _tableLocks[table] ?? Future<void>.value();
    final done = Completer<void>();
    _tableLocks[table] = done.future;
    return previous.then((_) => body()).whenComplete(done.complete);
  }

  static int _overlapStart(int cursorMs) {
    final start = cursorMs - _cursorOverlap.inMilliseconds;
    return start < 0 ? 0 : start;
  }

  Future<void> triggerPostWriteSync() => synchronize();

  /// The signed-in doctor's UID, or `null` if nobody is signed in.
  ///
  /// Every Firestore read/write in this service is scoped to this value —
  /// without it, sync would pull or push every doctor's data.
  String? get _currentDoctorId => ClinicSession.instance.tenantId;

  Future<void> synchronize() async {
    if (_isSyncing) {
      // Run once more when the current pass ends, so a write or an access
      // change made meanwhile is not left waiting for the next trigger.
      _syncAgain = true;
      return;
    }
    final doctorId = _currentDoctorId;
    if (doctorId == null) return; // nothing to sync without a signed-in doctor
    _isSyncing = true;

    try {
      do {
        _syncAgain = false;
        try {
          await _uploadPendingRows(doctorId);
          await _downloadChangedRows(doctorId);
        } catch (e, st) {
          // Leave pending rows untouched; the next startup/connectivity/write
          // trigger retries the same simple sync pass.
          debugPrint('Sync pass failed: $e\n$st');
        }
        try {
          // Collections that caught up in this session listen; the rest wait
          // for their next successful catch-up (reconnect retries it).
          await _attachLiveListeners(doctorId);
        } catch (e) {
          debugPrint('Attaching live listeners failed: $e');
        }
      } while (_syncAgain && _isSyncing && _currentDoctorId == doctorId);
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

  /// Brings every readable collection up to date: the documents changed
  /// since each one's cursor, then — on launch, reconnect and access change —
  /// the delete safety net ([_verifyCollection]).
  Future<void> _downloadChangedRows(String doctorId) async {
    final now = DateTime.now();
    final last = _lastCountCheckRun;
    final sinceLast = last == null ? null : now.difference(last);
    final checkCounts =
        sinceLast == null ||
        sinceLast >= _countCheckMaxGap ||
        (_countCheckDue && sinceLast >= _countCheckMinGap);
    if (checkCounts) {
      _countCheckDue = false;
      _lastCountCheckRun = now;
    }
    await _noteAccessShape();

    for (final collection in _allSyncedCollections) {
      if (!canReadCollection(collection)) continue;
      try {
        await catchUpCollection(collection, doctorId);
        if (checkCounts || _forceReconcile.contains(collection)) {
          await _verifyCollection(collection, doctorId);
        }
      } on _SessionChanged {
        // Signed out or switched mid-pass: write nothing more.
        return;
      } on FirebaseException catch (e) {
        if (e.code == 'unavailable') {
          // Offline: every other collection would fail the same way.
          _countCheckDue = true;
          _lastCountCheckRun = null;
          rethrow;
        }
        // Refused or failed for this collection only; the rest carry on.
        debugPrint('[FirestoreSync] syncing $collection failed: $e');
      } catch (e, st) {
        debugPrint('[FirestoreSync] syncing $collection failed: $e\n$st');
      }
    }

    _forceReconcile.removeWhere((c) => !canReadCollection(c));
    final shape = _pendingAccessShape;
    if (shape != null && _forceReconcile.isEmpty) {
      await _writeMeta(_accessShapeKey, shape);
      _pendingAccessShape = null;
    }
  }

  /// Downloads [collection]'s documents changed since its cursor, a page at
  /// a time in (updatedAt, document id) order, and saves the cursor after
  /// each page's rows have committed — an interrupted run resumes from the
  /// last saved page. A first run is simply cursor 0.
  ///
  /// Public for InitialFirestoreMigrationService, whose first pull is this.
  Future<void> catchUpCollection(String collection, String doctorId) async {
    final watch = Stopwatch()..start();
    final table = _tableFor(collection);
    final current = _sessionGuard(doctorId);
    final cursor = await _readCursor(collection);
    _ensureCurrent(current);
    var query = _scopedQuery(collection, doctorId);
    if (cursor.ms > 0) {
      query = query.where(
        'updatedAt',
        isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(
          _overlapStart(cursor.ms),
        ),
      );
    }
    query = query
        .orderBy('updatedAt')
        .orderBy(FieldPath.documentId)
        .limit(_pageSize);

    var pages = 0;
    var docs = 0;
    QueryDocumentSnapshot<Map<String, dynamic>>? last;
    while (true) {
      // From the server only: a cache answer can be partial, and a cursor
      // moved past documents it left out would never fetch them.
      final page = await (last == null ? query : query.startAfterDocument(last))
          .get(const GetOptions(source: Source.server));
      _ensureCurrent(current);
      pages++;
      docs += page.docs.length;
      await _locked(table, () async {
        _ensureCurrent(current);
        await _applyDocs(
          collection,
          doctorId,
          page.docs,
          stillCurrent: current,
        );
      });
      final newest = _newestOf(page.docs);
      _ensureCurrent(current);
      if (newest != null) await _saveCursor(collection, newest.ms, newest.id);
      if (page.docs.length < _pageSize) break;
      last = page.docs.last;
    }
    _caughtUpThisSession.add(collection);
    debugPrint(
      '[FirestoreSync] catch-up $collection: $pages pages, $docs docs, '
      '${watch.elapsedMilliseconds} ms',
    );
  }

  /// The delete safety net. A listener filtered on updatedAt never hears of
  /// an older document being deleted, so compare the server's count for the
  /// same query with the rows this device believes the server holds; on a
  /// mismatch, or when the periodic comparison is due, compare every id.
  /// A count that fails (offline, refused) is skipped silently.
  Future<void> _verifyCollection(String collection, String doctorId) async {
    final current = _sessionGuard(doctorId);
    final cursor = await _readCursor(collection);
    final narrowed = _narrowsToAssignment(
      collection,
      ClinicSession.instance.access,
    );
    final every = narrowed ? _scopedReconcileEvery : _fullReconcileEvery;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final due =
        _forceReconcile.contains(collection) ||
        (cursor.lastCountCheckAt > 0 &&
            nowMs - cursor.lastCountCheckAt >= every.inMilliseconds);
    if (!due) {
      int? server;
      try {
        server = (await _scopedQuery(collection, doctorId).count().get()).count;
      } catch (_) {
        return;
      }
      if (server == null) return;
      final local = await _localServerHeldCount(collection, doctorId);
      _ensureCurrent(current);
      if (server == local) {
        // First check on this device: start the periodic clock now rather
        // than comparing every id straight away.
        if (cursor.lastCountCheckAt <= 0) {
          await _setLastCountCheckAt(collection, nowMs);
        }
        return;
      }
      // The last reconcile already left exactly this mismatch: running it
      // again would re-read the whole collection for nothing.
      if (await _readMeta(_mismatchKey(collection)) == '$server:$local') {
        return;
      }
      debugPrint(
        '[FirestoreSync] $collection: server holds $server, this device '
        'expects $local; comparing ids',
      );
    }
    await _reconcileIds(collection, doctorId);
  }

  /// Rows of [collection] the server should still hold: ones it sent or
  /// accepted (lastSyncedAt set, whether or not edited here since), minus
  /// those known to be gone from it. Soft-deleted rows (isDeleted,
  /// isArchived) still count: their documents are still there. A row that
  /// never synced (no lastSyncedAt) is never counted — nor, below, touched.
  Future<int> _localServerHeldCount(String collection, String doctorId) async {
    final db = await _databaseService.localDatabase;
    final visitType = _visitFirestoreToType[collection];
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM ${_tableFor(collection)} '
      'WHERE doctorId = ? AND remoteGone = 0 AND lastSyncedAt IS NOT NULL'
      '${visitType == null ? '' : ' AND visitType = ?'}',
      [doctorId, ?visitType],
    );
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  /// Compares every server id of [collection] with this device: downloads
  /// whatever is missing or out of date, and treats synced rows the server
  /// no longer returns as removed there (dropped instead, for a doctor
  /// narrowed to their own patients). Rows waiting to upload are never
  /// touched.
  Future<void> _reconcileIds(String collection, String doctorId) async {
    final watch = Stopwatch()..start();
    // Rows synced after this (a live update, this device's own upload) may
    // be missing from pages already read; they are left out of the removal
    // step below.
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    final table = _tableFor(collection);
    final narrowed = _narrowsToAssignment(
      collection,
      ClinicSession.instance.access,
    );
    final rewrite = _forceRewrite.contains(collection);
    final current = _sessionGuard(doctorId);
    final query = _scopedQuery(
      collection,
      doctorId,
    ).orderBy(FieldPath.documentId).limit(_pageSize);
    final serverIds = <String>{};
    var pages = 0;
    QueryDocumentSnapshot<Map<String, dynamic>>? last;
    while (true) {
      final page = await (last == null ? query : query.startAfterDocument(last))
          .get(const GetOptions(source: Source.server));
      _ensureCurrent(current);
      pages++;
      for (final d in page.docs) {
        serverIds.add(d.id);
      }
      await _locked(table, () async {
        _ensureCurrent(current);
        await _applyDocs(
          collection,
          doctorId,
          page.docs,
          rewrite: rewrite,
          stillCurrent: current,
        );
      });
      if (page.docs.length < _pageSize) break;
      last = page.docs.last;
    }

    // Every page arrived, so serverIds is the complete answer.
    final gone = await _locked(table, () async {
      _ensureCurrent(current);
      if (narrowed) {
        return _reconcileScopedCollection(
          collection,
          doctorId,
          serverIds,
          syncedBefore: startedAt,
        );
      }
      final db = await _databaseService.localDatabase;
      final visitType = _visitFirestoreToType[collection];
      final local = await db.query(
        table,
        columns: ['id'],
        where:
            "doctorId = ? AND syncStatus = 'synced' AND remoteGone = 0 "
            'AND lastSyncedAt IS NOT NULL AND lastSyncedAt < ?'
            '${visitType == null ? '' : ' AND visitType = ?'}',
        whereArgs: [doctorId, startedAt, ?visitType],
      );
      var removed = 0;
      for (final row in local) {
        final id = row['id']! as String;
        if (serverIds.contains(id)) continue;
        final changed = await _applyRemoteDeletion(
          collection,
          id,
          doctorId,
          sqliteTable: table,
          notify: false,
        );
        if (changed) removed++;
      }
      if (removed > 0) _notifyTableChanged(table);
      return removed;
    });

    _ensureCurrent(current);
    _forceReconcile.remove(collection);
    _forceRewrite.remove(collection);
    // A mismatch the reconcile could not fix (a document that never lands
    // here) is remembered, so the count check does not page the whole
    // collection again until either count moves or the periodic run is due.
    final local = await _localServerHeldCount(collection, doctorId);
    _ensureCurrent(current);
    await _writeMeta(
      _mismatchKey(collection),
      local == serverIds.length ? '' : '${serverIds.length}:$local',
    );
    await _setLastCountCheckAt(
      collection,
      DateTime.now().millisecondsSinceEpoch,
    );
    debugPrint(
      '[FirestoreSync] id reconcile $collection: $pages pages, '
      '${serverIds.length} on the server, $gone removed here, '
      '${watch.elapsedMilliseconds} ms',
    );
  }

  static const String _accessShapeKey = 'sync.accessShape';

  static String _mismatchKey(String collection) =>
      'sync.reconcileMismatch.$collection';

  /// Whether the session that called this is still the one signed in: the
  /// same [stop] generation and the same doctor.
  bool Function() _sessionGuard(String doctorId) {
    final generation = _generation;
    return () => _generation == generation && _currentDoctorId == doctorId;
  }

  static void _ensureCurrent(bool Function() current) {
    if (!current()) throw const _SessionChanged();
  }

  /// Notices a change, since the last pass and across restarts, in what this
  /// person's rows hold or which rows they get: clinical fields becoming
  /// readable, or a collection narrowed to (or widened from) assigned
  /// patients. The delta catch-up never re-sends a version the device
  /// already has, and the old unbounded listeners did, so such a change is
  /// now settled by comparing every id — rewriting patients, so their
  /// clinical fields fill in.
  Future<void> _noteAccessShape() async {
    final access = ClinicSession.instance.access;
    final holds = ClinicSession.instance.holdsClinicalFields;
    final narrowed = [
      for (final c in _assignmentScopedCollections)
        if (_narrowsToAssignment(c, access)) c,
    ]..sort();
    final shape = '${holds ? 1 : 0}|${narrowed.join(',')}';
    final stored = await _readMeta(_accessShapeKey);
    if (stored == shape) {
      _pendingAccessShape = null;
      return;
    }
    if (stored == null) {
      // First pass with this check: nothing earlier to compare with.
      await _writeMeta(_accessShapeKey, shape);
      return;
    }
    final parts = stored.split('|');
    final heldBefore = parts.first == '1';
    final narrowedBefore = parts.length > 1 && parts[1].isNotEmpty
        ? parts[1].split(',').toSet()
        : <String>{};
    if (holds && !heldBefore && canReadCollection('patients')) {
      _forceReconcile.add('patients');
      _forceRewrite.add('patients');
    }
    for (final c in _assignmentScopedCollections) {
      if (narrowedBefore.contains(c) != narrowed.contains(c) &&
          canReadCollection(c)) {
        _forceReconcile.add(c);
      }
    }
    _pendingAccessShape = shape;
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
          // An identifier from the clinic's previous software: encrypted
          // like the phone number, and not gated on clinical access, since
          // the front desk looks patients up by it after a migration.
          'oldId': FieldCipher.encrypt(row['oldId'] as String?),
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
        }..removeWhere(
          (key, _) =>
              (key == 'diagnosis' || key == 'notes') &&
              omitsClinicalFields(
                row,
                ClinicSession.instance.holdsClinicalFields,
              ),
        );
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

  /// Writes a page of downloaded documents of [collection] into SQLite.
  ///
  /// The rules of the old per-document upsert hold: a row with local changes
  /// waiting to upload is never overwritten, nor is a synced row newer than
  /// the download (a stale answer arriving after a fresher one), an
  /// un-synced stub always is, and a visit's patient is made to exist first.
  /// What changed: a row already holding this exact version is skipped
  /// (catch-up overlaps re-read a few) unless [rewrite]; decrypting runs on
  /// a worker isolate; and the page is written in one transaction with one
  /// change notification per table instead of one per document.
  ///
  /// Callers hold the table's lock ([_locked]). Returns rows written.
  Future<int> _applyDocs(
    String collection,
    String doctorId,
    List<DocumentSnapshot<Map<String, dynamic>>> docs, {
    bool rewrite = false,
    bool Function()? stillCurrent,
  }) async {
    if (docs.isEmpty) return 0;
    final table = _tableFor(collection);
    final db = await _databaseService.localDatabase;
    final existing = await _existingRows(db, table, [
      for (final d in docs) d.id,
    ]);

    final ids = <String>[];
    final data = <Map<String, Object?>>[];
    for (final doc in docs) {
      final raw = doc.data();
      if (raw == null) continue;
      final local = existing[doc.id];
      if (local != null &&
          !_remoteMayReplace(
            table,
            local,
            raw['updatedAt'],
            rewrite: rewrite,
          )) {
        continue;
      }
      ids.add(doc.id);
      data.add(_plainData(raw));
    }
    if (ids.isEmpty) return 0;

    final mapped = await _mapRows(collection, doctorId, ids, data);
    final rows = mapped.whereType<Map<String, Object?>>().toList();
    if (rows.isEmpty) return 0;

    // Foreign key safety: a visit's patient must exist before the visit.
    final parents = table == 'visits'
        ? await _missingParentPatients(db, doctorId, rows)
        : const <Map<String, Object?>>[];
    // Mapping can take a while (a worker isolate): don't write another
    // session's rows into whichever database is open now.
    if (stillCurrent != null && !stillCurrent()) return 0;

    final results = await db.writeBatch((batch) {
      for (final parent in parents) {
        batch.insert(
          'patients',
          parent,
          conflictAlgorithm: LocalConflictAlgorithm.ignore,
        );
      }
      for (final row in rows) {
        final id = row['id']! as String;
        if (existing.containsKey(id)) {
          batch.update(
            table,
            row,
            // Re-checked as it writes: an edit made on this device since the
            // read above still wins.
            where: 'id = ? AND syncStatus != ?',
            whereArgs: [id, 'pending'],
          );
        } else {
          // Ignore, not replace: a replace deletes the old row first, which
          // the visits' patient reference refuses.
          batch.insert(
            table,
            row,
            conflictAlgorithm: LocalConflictAlgorithm.ignore,
          );
        }
      }
    }, continueOnError: true);

    final failed = results.whereType<Exception>().length;
    if (failed > 0) {
      debugPrint(
        '[FirestoreSync] $failed of ${results.length} writes into $table '
        'failed; the next count check fetches them again',
      );
    }
    if (parents.isNotEmpty) _notifyTableChanged('patients');
    _notifyTableChanged(table);
    return rows.length - failed;
  }

  /// Whether a downloaded version (its `updatedAt` [remoteUpdatedAtRaw])
  /// may overwrite the [local] row of [table] it matches by id.
  static bool _remoteMayReplace(
    String table,
    Map<String, Object?> local,
    Object? remoteUpdatedAtRaw, {
    bool rewrite = false,
  }) {
    // Pending local changes win.
    if (local['syncStatus'] == 'pending') return false;
    final localUpdatedAt = (local['updatedAt'] as num?)?.toInt() ?? 0;
    final remoteUpdatedAt = _millisOf(remoteUpdatedAtRaw);
    // An un-synced stub (a visit's placeholder patient) is always replaced.
    final isStub =
        localUpdatedAt <= 0 ||
        (table == 'patients' &&
            local['isArchived'] == 1 &&
            local['firstName'] == 'Patient');
    if (isStub || remoteUpdatedAt <= 0) return true;
    // Local is newer — keep it.
    if (localUpdatedAt > remoteUpdatedAt) return false;
    // Already holds this very version.
    final remoteGone = (local['remoteGone'] as num?)?.toInt() ?? 0;
    if (!rewrite && localUpdatedAt == remoteUpdatedAt && remoteGone == 0) {
      return false;
    }
    return true;
  }

  /// The local rows of [table] among [ids], with what [_remoteMayReplace]
  /// reads. One query per 500 ids (SQLite caps bound parameters).
  Future<Map<String, Map<String, Object?>>> _existingRows(
    LocalDatabaseExecutor db,
    String table,
    List<String> ids,
  ) async {
    final found = <String, Map<String, Object?>>{};
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, math.min(i + 500, ids.length));
      final rows = await db.query(
        table,
        columns: [
          'id',
          'syncStatus',
          'updatedAt',
          'remoteGone',
          if (table == 'patients') ...['isArchived', 'firstName'],
        ],
        where: 'id IN (${List.filled(chunk.length, '?').join(',')})',
        whereArgs: chunk,
      );
      for (final r in rows) {
        found[r['id']! as String] = r;
      }
    }
    return found;
  }

  static Map<String, Object?> _plainData(Map<String, dynamic> raw) =>
      plainFirestoreValue(raw)! as Map<String, Object?>;

  /// Decrypts and maps documents into rows on a worker isolate, given the
  /// raw clinic key; on this isolate for a few documents, or if the worker
  /// can't be used.
  Future<List<Map<String, Object?>?>> _mapRows(
    String collection,
    String doctorId,
    List<String> ids,
    List<Map<String, Object?>> data,
  ) async {
    final job = syncRowJob(
      collection: collection,
      doctorId: doctorId,
      holdsClinicalFields: ClinicSession.instance.holdsClinicalFields,
      keyBytes: EncryptionKeyManager.instance.currentKey?.bytes,
      ids: ids,
      data: data,
    );
    if (!_decryptWorkerFailed && ids.length >= _workerMinDocs) {
      try {
        return await compute(mapSyncRows, job, debugLabel: 'sync-decrypt');
      } catch (e) {
        _decryptWorkerFailed = true;
        debugPrint(
          '[FirestoreSync] decrypt worker unavailable, decrypting here: $e',
        );
      }
    }
    return mapSyncRows(job);
  }

  /// Patient rows to insert ahead of the visits in [rows] whose patient
  /// this device lacks: fetched from the server, or an archived stub when
  /// that fails, so the visit still saves without showing a made-up
  /// patient in the list.
  Future<List<Map<String, Object?>>> _missingParentPatients(
    LocalDatabaseExecutor db,
    String doctorId,
    List<Map<String, Object?>> rows,
  ) async {
    final wanted = <String>{
      for (final r in rows)
        if ((r['patientId'] as String? ?? '').trim().isNotEmpty)
          r['patientId']! as String,
    };
    if (wanted.isEmpty) return const [];
    final have = await _existingRows(db, 'patients', wanted.toList());
    final missing = [
      for (final id in wanted)
        if (!have.containsKey(id)) id,
    ];
    if (missing.isEmpty) return const [];

    final found = <DocumentSnapshot<Map<String, dynamic>>>[];
    // Someone who can't read patients would only be refused.
    if (canReadCollection('patients')) {
      for (var i = 0; i < missing.length; i += 20) {
        final batch = missing.sublist(i, math.min(i + 20, missing.length));
        final docs = await Future.wait(
          batch.map((id) async {
            try {
              final doc = await _firestore
                  .collection('patients')
                  .doc(id)
                  .get(const GetOptions(source: Source.server));
              return doc.exists && doc.data() != null ? doc : null;
            } catch (e) {
              debugPrint(
                '[FirestoreSync] Could not fetch missing parent patient $id '
                'from Firestore: $e',
              );
              return null;
            }
          }),
        );
        found.addAll(docs.whereType<DocumentSnapshot<Map<String, dynamic>>>());
      }
    }

    final parents = <Map<String, Object?>>[];
    if (found.isNotEmpty) {
      final mapped = await _mapRows(
        'patients',
        doctorId,
        [for (final d in found) d.id],
        [for (final d in found) _plainData(d.data()!)],
      );
      parents.addAll(mapped.whereType<Map<String, Object?>>());
    }
    final fetched = {for (final p in parents) p['id']};
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final id in missing) {
      if (fetched.contains(id)) continue;
      // An archived minimal stub: satisfies the foreign key without showing
      // dummy data in the UI. remoteGone, as the server is not known to hold
      // it; a later download of the real patient replaces it.
      parents.add({
        'id': id,
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
        'remoteGone': 1,
      });
    }
    return parents;
  }

  /// The newest server `updatedAt` among [docs] and that document's id, the
  /// cursor they advance to. Documents without a Timestamp there (a write
  /// still pending, a legacy string) don't move it.
  static ({int ms, String id})? _newestOf(
    Iterable<DocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    ({int ms, String id})? newest;
    for (final d in docs) {
      final value = d.data()?['updatedAt'];
      if (value is! Timestamp) continue;
      final ms = value.millisecondsSinceEpoch;
      if (newest == null ||
          ms > newest.ms ||
          (ms == newest.ms && d.id.compareTo(newest.id) > 0)) {
        newest = (ms: ms, id: d.id);
      }
    }
    return newest;
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
        {
          'syncStatus': 'synced',
          'pendingDelete': 0,
          'lastSyncedAt': now,
          // A pushed delete took the document off the server; any other
          // upload put it there.
          'remoteGone': row.pendingDelete ? 1 : 0,
        },
        where: row.stamped ? 'id = ? AND updatedAt IS ?' : 'id = ?',
        whereArgs: [row.id, if (row.stamped) row.updatedAt],
      );
    }
  }

  /// [collection]'s delta cursor: the newest server `updatedAt` applied (and
  /// that document's id), plus when its ids were last compared with the
  /// server. Installs from before the cursor columns only kept
  /// `lastSyncTime`, a strict watermark; it carries over as the cursor.
  Future<({int ms, String docId, int lastCountCheckAt})> _readCursor(
    String collection,
  ) async {
    final db = await _databaseService.localDatabase;
    final rows = await db.query(
      'sync_state',
      columns: [
        'lastSyncTime',
        'cursorUpdatedAtMs',
        'cursorDocId',
        'lastCountCheckAt',
      ],
      where: 'collectionName = ?',
      whereArgs: [collection],
      limit: 1,
    );
    if (rows.isEmpty) return (ms: 0, docId: '', lastCountCheckAt: 0);
    final row = rows.first;
    final cursor = (row['cursorUpdatedAtMs'] as num?)?.toInt() ?? 0;
    final legacy = (row['lastSyncTime'] as num?)?.toInt() ?? 0;
    return (
      ms: cursor > legacy ? cursor : legacy,
      docId: row['cursorDocId'] as String? ?? '',
      lastCountCheckAt: (row['lastCountCheckAt'] as num?)?.toInt() ?? 0,
    );
  }

  /// Moves [collection]'s cursor forward to ([ms], [docId]); never back.
  /// Called only once the rows it covers have committed. `lastSyncTime`
  /// follows, for anything still reading it.
  Future<void> _saveCursor(String collection, int ms, String docId) async {
    final db = await _databaseService.localDatabase;
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = await db.update(
      'sync_state',
      {
        'cursorUpdatedAtMs': ms,
        'cursorDocId': docId,
        'lastSyncTime': ms,
        'updatedAt': now,
      },
      where:
          'collectionName = ? AND (cursorUpdatedAtMs < ? OR '
          '(cursorUpdatedAtMs = ? AND cursorDocId < ?))',
      whereArgs: [collection, ms, ms, docId],
    );
    if (updated > 0) return;
    // No row yet (or one already further on, which this leaves alone).
    await db.insert('sync_state', {
      'collectionName': collection,
      'lastSyncTime': ms,
      'cursorUpdatedAtMs': ms,
      'cursorDocId': docId,
      'hasCompletedInitialMigration': 0,
      'lastCountCheckAt': 0,
      'updatedAt': now,
    }, conflictAlgorithm: LocalConflictAlgorithm.ignore);
  }

  Future<void> _setLastCountCheckAt(String collection, int millis) async {
    final db = await _databaseService.localDatabase;
    await db.insert('sync_state', {
      'collectionName': collection,
      'lastSyncTime': 0,
      'hasCompletedInitialMigration': 0,
      'updatedAt': millis,
    }, conflictAlgorithm: LocalConflictAlgorithm.ignore);
    await db.update(
      'sync_state',
      {'lastCountCheckAt': millis},
      where: 'collectionName = ?',
      whereArgs: [collection],
    );
  }

  Future<String?> _readMeta(String key) async {
    final db = await _databaseService.localDatabase;
    final rows = await db.query(
      'app_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> _writeMeta(String key, String value) async {
    final db = await _databaseService.localDatabase;
    await db.insert('app_meta', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: LocalConflictAlgorithm.replace);
  }

  Timestamp _timestampFromMillis(Object? value) {
    final millis =
        (value as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    return Timestamp.fromMillisecondsSinceEpoch(millis);
  }

  static int _millisOf(Object? value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is num) return value.toInt();
    return 0;
  }

  /// Apply a remote deletion (Firestore remove) into the local SQLite cache.
  ///
  /// Tries to mark rows soft-deleted (set `isDeleted=1` or `isArchived=1`) and
  /// mark them `syncStatus='synced'`. If the table has no suitable soft-delete
  /// column, falls back to deleting the local row. Notifies local services
  /// after changes so UI updates (unless [notify] is false: the caller
  /// notifies once for many). Every outcome marks the row `remoteGone`, so
  /// the delete safety net stops expecting it on the server. Returns whether
  /// a row changed.
  Future<bool> _applyRemoteDeletion(
    String firestoreCollection,
    String id,
    String doctorId, {
    String? sqliteTable,
    bool notify = true,
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
        {
          'syncStatus': 'synced',
          'pendingDelete': 0,
          'lastSyncedAt': now,
          'remoteGone': 1,
        },
        where: 'id = ? AND doctorId = ?',
        whereArgs: [id, doctorId],
      );
      if (notify) _notifyTableChanged(table);
      return true;
    }
    // A pending local edit wins: its upload settles the document, and a
    // removal that was real comes back on the next reconcile.
    if (pendingRows.isNotEmpty &&
        pendingRows.first['syncStatus'] == 'pending') {
      return false;
    }
    // Re-checked as each write runs, for an edit made since the read above.
    const notPending = "id = ? AND doctorId = ? AND syncStatus != 'pending'";

    // Try marking as soft-deleted via commonly used columns.
    // Order: isDeleted, isArchived. If neither affects a row, delete it.
    final hasIsActive = table != 'dental_records' && table != 'radiology_docs';
    final isDeletedPayload = <String, Object?>{
      'isDeleted': 1,
      if (hasIsActive) 'isActive': 0,
      'syncStatus': 'synced',
      'pendingDelete': 0,
      'lastSyncedAt': now,
      'remoteGone': 1,
    };
    var updatedIsDeleted = 0;
    try {
      updatedIsDeleted = await db.update(
        table,
        isDeletedPayload,
        where: notPending,
        whereArgs: [id, doctorId],
      );
    } catch (_) {
      // This table has no isDeleted column — patients, for one. Fall through
      // to isArchived below. Before this, the error escaped to the listener,
      // which swallowed it, and a patient removed on the server stayed on
      // the device as though nothing had happened.
    }
    if (updatedIsDeleted > 0) {
      if (notify) _notifyTableChanged(table);
      return true;
    }

    if (hasIsActive) {
      const synced = {
        'syncStatus': 'synced',
        'pendingDelete': 0,
        'remoteGone': 1,
      };
      var updated = 0;
      try {
        updated = await db.update(
          table,
          {'isArchived': 1, 'isActive': 0, ...synced, 'lastSyncedAt': now},
          where: notPending,
          whereArgs: [id, doctorId],
        );
      } catch (_) {
        // No isArchived column either (medicines): isActive alone hides it.
        updated = await db.update(
          table,
          {'isActive': 0, ...synced, 'lastSyncedAt': now},
          where: notPending,
          whereArgs: [id, doctorId],
        );
      }
      if (updated > 0) {
        if (notify) _notifyTableChanged(table);
        return true;
      }
    }

    // No soft-delete column matched; remove the row entirely.
    final deleted = await db.delete(
      table,
      where: notPending,
      whereArgs: [id, doctorId],
    );
    if (deleted > 0 && notify) _notifyTableChanged(table);
    return deleted > 0;
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

/// Thrown when the session a sync step started under has ended or switched.
class _SessionChanged implements Exception {
  const _SessionChanged();
}

/// A row as it was uploaded: its id and, when its table has one, its
/// `updatedAt` then, to tell whether it changed while uploading.
class _UploadedRow {
  _UploadedRow.of(Map<String, Object?> row)
    : id = row['id'] as String,
      stamped = row.containsKey('updatedAt'),
      updatedAt = row['updatedAt'],
      pendingDelete = row['pendingDelete'] == 1;

  final String id;
  final bool pendingDelete;
  final bool stamped;
  final Object? updatedAt;
}
