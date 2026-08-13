import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:doctor_management_app/core/services/field_cipher.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/services/patient_local_service.dart';
import 'package:doctor_management_app/features/appointments/data/services/visits_local_service.dart';
import 'package:doctor_management_app/features/inventory/data/services/inventory_local_service.dart';
import 'package:doctor_management_app/features/revenue/data/services/revenue_local_service.dart';
import 'package:doctor_management_app/core/database/local_database.dart';

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

  Future<void> start() async {
    if (_isStarted) return;
    _isStarted = true;

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (dynamic result) {
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
      },
    );

    final doctorId = _currentDoctorId;
    if (doctorId != null) {
      _startLiveSubscriptions(doctorId);
    }

    unawaited(synchronize());
  }

  Future<void> stop() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _stopLiveSubscriptions();
    _isStarted = false;
    // Phase 19: reset the sync-in-progress flag so the next doctor's
    // first synchronize() call is never silently dropped.
    _isSyncing = false;
  }

  void _startLiveSubscriptions(String doctorId) {
    if (_subscribedDoctorId == doctorId && _liveSubscriptions.isNotEmpty) {
      return;
    }
    _stopLiveSubscriptions();
    _subscribedDoctorId = doctorId;

    for (final collection in _collections) {
      final sub = _firestore
          .collection(collection)
          .where('doctorId', isEqualTo: doctorId)
          .snapshots()
          .listen((snapshot) async {
        for (final change in snapshot.docChanges) {
          try {
            final doc = change.doc;
            if (change.type == DocumentChangeType.removed) {
              await _applyRemoteDeletion(collection, doc.id, doctorId);
            } else {
              final data = doc.data();
              if (data == null) continue;
              await _upsertDownloadedRow(collection, doc.id, data, doctorId);
            }
          } catch (e, st) {
            // Swallow individual doc handling errors so the listener continues.
            debugPrint('Live sync doc update failed in $collection: $e\n$st');
          }
        }
      });
      _liveSubscriptions.add(sub);
    }

    for (final firestoreCollection in _visitFirestoreToType.keys) {
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
  String? get _currentDoctorId => FirebaseAuth.instance.currentUser?.uid;

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
      final uploadedIds = <String>[];
      var currentBatch = _firestore.batch();
      var batchCount = 0;

      Future<void> commitCurrentBatch() async {
        if (batchCount == 0) return;
        await currentBatch.commit();
        await _markRowsSynced(collection, uploadedIds.toList());
        uploadedIds.clear();
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
        uploadedIds.add(id);
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

  /// Uploads pending rows from the `visits` SQLite table, routing each row
  /// to the correct Firestore collection based on its `visitType`:
  ///   `'clinic'`  →  `appointments`
  ///   `'home'`    →  `visitations`
  ///
  /// Soft-deletes are broadcast to **both** collections so a document is
  /// cleaned up even if its type changed between creation and deletion.
  Future<void> _uploadPendingVisits(LocalDatabaseExecutor db, String doctorId) async {
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
    final uploadedIds = <String>[];
    var currentBatch = _firestore.batch();
    var batchCount = 0;


    Future<void> commitCurrentBatch() async {
      if (batchCount == 0) return;
      await currentBatch.commit();
      await _markRowsSynced('visits', uploadedIds.toList());
      uploadedIds.clear();
      currentBatch = _firestore.batch();
      batchCount = 0;
    }

    for (final row in rows) {
      final id = row['id'] as String;
      // Phase 18/19: skip rows belonging to a different doctor.
      final rowDoctorId = row['doctorId'] as String?;
      if (rowDoctorId != null && rowDoctorId != doctorId) continue;

      final visitType = row['visitType'] as String? ?? 'clinic';
      final targetCollection =
          visitType == 'home' ? 'visitations' : 'appointments';
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
      uploadedIds.add(id);

      if (batchCount >= maxBatchSize) {
        await commitCurrentBatch();
      }
    }

    await commitCurrentBatch();
  }

  Future<void> _downloadChangedRows(String doctorId) async {
    // ── non-visit collections ────────────────────────────────────────────────
    for (final collection in _collections) {
      final lastSyncTime = await _lastSyncTime(collection);
      Query<Map<String, dynamic>> query = _firestore
          .collection(collection)
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
        await _upsertDownloadedRow(collection, doc.id, data, doctorId);
      }

      if (newestSyncTime > lastSyncTime) {
        await _setLastSyncTime(collection, newestSyncTime);
      }
    }

    // ── visit Firestore collections → visits SQLite table ────────────────────
    for (final firestoreCollection in _visitFirestoreToType.keys) {
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
          'gender': row['gender'] as String? ?? '',
          'dateOfBirth': _timestampFromMillis(row['dateOfBirth']),
          'diagnosis': FieldCipher.encrypt(row['diagnosis'] as String?),
          'notes': FieldCipher.encrypt(row['notes'] as String?),
          'packageBalance': (row['packageBalance'] as num?)?.toDouble() ?? 0,
          'isArchived': row['isArchived'] == 1,
          'isActive': row['isActive'] == 1,
          'createdAt': _timestampFromMillis(row['createdAt']),
          'updatedAt': FieldValue.serverTimestamp(),
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
          'treatmentType': row['treatmentType'] as String?,
          'therapistNotes': row['therapistNotes'] == null
              ? null
              : FieldCipher.encrypt(row['therapistNotes'] as String?),
          'reminderStatus': row['reminderStatus'] as String?,
          'calendarEventId': row['calendarEventId'] as String?,
          'createdAt': _timestampFromMillis(row['createdAt']),
          'updatedAt': FieldValue.serverTimestamp(),
        };
      case 'revenue_entries':
        return {
          'doctorId': doctorId,
          'date': _timestampFromMillis(row['date']),
          'description': FieldCipher.encrypt(row['description'] as String?),
          'amount': FieldCipher.encrypt(((row['amount'] as num?)?.toDouble() ?? 0).toString()),
          'type': row['type'] as String? ?? 'miscellaneous',
          'kind': row['kind'] as String? ?? 'income',
          'payer': row['payer'] == null
              ? null
              : FieldCipher.encrypt(row['payer'] as String?),
          'patientId': row['patientId'] as String?,
          'visitId': row['visitId'] as String?,
          'isDeleted': row['isDeleted'] == 1,
          'createdAt': _timestampFromMillis(row['createdAt']),
          'updatedAt': FieldValue.serverTimestamp(),
        };
      case 'pending_payments':
        return {
          'doctorId': doctorId,
          'date': _timestampFromMillis(row['date']),
          'description': FieldCipher.encrypt(row['description'] as String?),
          'amount': FieldCipher.encrypt(((row['amount'] as num?)?.toDouble() ?? 0).toString()),
          'isPaid': row['isPaid'] == 1,
          'payer': row['payer'] == null
              ? null
              : FieldCipher.encrypt(row['payer'] as String?),
          'patientId': row['patientId'] as String?,
          'visitId': row['visitId'] as String?,
          'notes': row['notes'] == null
              ? null
              : FieldCipher.encrypt(row['notes'] as String?),
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
          'unitPrice': (row['unitPrice'] as num?)?.toDouble(),
          'supplierName': row['supplierName'] as String?,
          'batchNumber': row['batchNumber'] as String?,
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
          'isActive': row['isActive'] == 1,
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
      // recent as the local copy.  This prevents an older batch download from
      // clobbering a fresher live-listener write.
      final localUpdatedAt = (local['updatedAt'] as num?)?.toInt() ?? 0;
      final remoteUpdatedAt = _timestampToMillis(data['updatedAt']);
      if (remoteUpdatedAt > 0 && localUpdatedAt > remoteUpdatedAt) {
        // Local is newer — keep it.
        return;
      }
    }
    await db.insert(
      table,
      _sqliteRowFor(firestoreCollection, id, data, doctorId),
      conflictAlgorithm: LocalConflictAlgorithm.replace,
    );

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
          'treatmentType': data['treatmentType'] as String?,
          'therapistNotes': data['therapistNotes'] == null
              ? null
              : FieldCipher.decrypt(data['therapistNotes'] as String?),
          'reminderStatus': data['reminderStatus'] as String?,
          'calendarEventId': data['calendarEventId'] as String?,
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
          'description': FieldCipher.decrypt(data['description'] as String? ?? ''),
          'amount': data['amount'] is String
              ? (double.tryParse(FieldCipher.decrypt(data['amount'] as String)) ?? 0)
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
          'description': FieldCipher.decrypt(data['description'] as String? ?? ''),
          'amount': data['amount'] is String
              ? (double.tryParse(FieldCipher.decrypt(data['amount'] as String)) ?? 0)
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
          'reorderThreshold':
              (data['reorderThreshold'] as num?)?.toInt() ?? 10,
          'unitPrice': (data['unitPrice'] as num?)?.toDouble(),
          'supplierName': data['supplierName'] as String?,
          'batchNumber': data['batchNumber'] as String?,
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
          'isActive': (data['isActive'] as bool? ?? true) ? 1 : 0,
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

  Future<void> _markRowsSynced(String collection, List<String> ids) async {
    if (ids.isEmpty) return;

    final db = await _databaseService.localDatabase;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final id in ids) {
      await db.update(
        collection,
        {'syncStatus': 'synced', 'pendingDelete': 0, 'lastSyncedAt': now},
        where: 'id = ?',
        whereArgs: [id],
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
    final updatedIsDeleted = await db.update(
      table,
      {
        'isDeleted': 1,
        'isActive': 0,
        'syncStatus': 'synced',
        'pendingDelete': 0,
        'lastSyncedAt': now,
      },
      where: 'id = ? AND doctorId = ?',
      whereArgs: [id, doctorId],
    );
    if (updatedIsDeleted > 0) {
      _notifyTableChanged(table);
      return;
    }

    final updatedIsArchived = await db.update(
      table,
      {
        'isArchived': 1,
        'isActive': 0,
        'syncStatus': 'synced',
        'pendingDelete': 0,
        'lastSyncedAt': now,
      },
      where: 'id = ? AND doctorId = ?',
      whereArgs: [id, doctorId],
    );
    if (updatedIsArchived > 0) {
      _notifyTableChanged(table);
      return;
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
      default:
        break;
    }
  }
}