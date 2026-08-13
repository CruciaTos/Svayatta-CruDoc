import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:doctor_management_app/core/services/field_cipher.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/core/database/local_database.dart';

/// One-time Firestore-to-SQLite bootstrap for existing cloud data.
///
/// Runs once per collection after the local database is available and before
/// incremental sync starts. Completion is guarded in `sync_state`.
class InitialFirestoreMigrationService {
  InitialFirestoreMigrationService._();

  static final InitialFirestoreMigrationService instance =
      InitialFirestoreMigrationService._();

  final LocalDatabaseService _databaseService = LocalDatabaseService.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const List<String> _collections = [
    'patients',
    'appointments', // VisitType.clinic  → visits SQLite table
    'visitations',  // VisitType.home    → visits SQLite table
    'revenue_entries',
    'pending_payments',
  ];

  /// The Firestore collections that map into the `visits` SQLite table.
  /// Their `visitType` value is derived from the collection name, not from
  /// the stored document field, to keep data consistent across devices.
  static const Map<String, String> _visitFirestoreToType = {
    'appointments': 'clinic',
    'visitations': 'home',
  };

  Future<void> runIfNeeded() async {
    final doctorId = FirebaseAuth.instance.currentUser?.uid;
    if (doctorId == null || doctorId.isEmpty) {
      // Not signed in yet — nothing to migrate, and querying without a
      // doctorId would either fail the security rules or (worse, if rules
      // are ever loosened) pull every doctor's data. Bail out; this is
      // re-invoked once the doctor signs in (see main.dart).
      return;
    }

    await _databaseService.ensureLocalDataMatchesSignedInDoctor(doctorId);

    for (final collection in _collections) {
      if (await _hasCompletedInitialMigration(collection)) continue;
      try {
        await _migrateCollection(collection, doctorId);
      } catch (e, st) {
        // Keep the guard unset so the next launch can retry. Startup should not
        // be blocked just because Firestore is temporarily unavailable.
        debugPrint('Initial migration failed for $collection: $e\n$st');
      }
    }
  }

  Future<void> _migrateCollection(String collection, String doctorId) async {
    // CRITICAL: scoped to this doctor only. Without this `.where(...)`,
    // this call would download every doctor's patients/visits/revenue onto
    // this device — which is exactly the cross-doctor leak this migration
    // is being patched to prevent.
    final snapshot = await _firestore
        .collection(collection)
        .where('doctorId', isEqualTo: doctorId)
        .get();
    var newestUpdatedAt = 0;

    // Visit Firestore collections (appointments, visitations) both land in
    // the `visits` SQLite table; every other collection maps 1-to-1.
    final sqliteTable = _visitFirestoreToType.containsKey(collection)
        ? 'visits'
        : collection;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final row = _sqliteRowFor(collection, doc.id, data, doctorId);
      final updatedAt = (row['updatedAt'] as num?)?.toInt() ?? 0;
      if (updatedAt > newestUpdatedAt) newestUpdatedAt = updatedAt;

      final db = await _databaseService.localDatabase;
      // If a local row exists and is locally modified (pending), preserve
      // the local change instead of overwriting it with the cloud copy.
      final existing = await db.query(
        sqliteTable,
        where: 'id = ?',
        whereArgs: [doc.id],
        limit: 1,
      );
      if (existing.isNotEmpty && (existing.first['syncStatus'] == 'pending')) {
        // Skip replacing a locally-pending row to avoid losing unsynced edits.
        continue;
      }

      await db.insert(
        sqliteTable,
        row,
        conflictAlgorithm: LocalConflictAlgorithm.replace,
      );
    }

    await _markInitialMigrationComplete(collection, newestUpdatedAt);
  }

  Future<bool> _hasCompletedInitialMigration(String collection) async {
    final db = await _databaseService.localDatabase;
    final rows = await db.query(
      'sync_state',
      columns: ['hasCompletedInitialMigration'],
      where: 'collectionName = ?',
      whereArgs: [collection],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    return rows.first['hasCompletedInitialMigration'] == 1;
  }

  Future<void> _markInitialMigrationComplete(
    String collection,
    int lastSyncTime,
  ) async {
    final db = await _databaseService.localDatabase;
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = await db.update(
      'sync_state',
      {
        'lastSyncTime': lastSyncTime,
        'hasCompletedInitialMigration': 1,
        'updatedAt': now,
      },
      where: 'collectionName = ?',
      whereArgs: [collection],
    );
    if (updated > 0) return;

    await db.insert('sync_state', {
      'collectionName': collection,
      'lastSyncTime': lastSyncTime,
      'hasCompletedInitialMigration': 1,
      'updatedAt': now,
    });
  }

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
      // visitType is set from the collection name (authoritative), not the
      // document field, so misfiled documents are self-correcting on load.
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
          'visitType': _visitFirestoreToType[collection]!,
          'status': data['status'] as String? ?? 'scheduled',
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
          'amount': (data['amount'] as num?)?.toDouble() ?? 0,
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
          'amount': (data['amount'] as num?)?.toDouble() ?? 0,
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
      default:
        throw ArgumentError('Unsupported migration collection: $collection');
    }
  }

  int _timestampToMillis(Object? value, {required int fallback}) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is num) return value.toInt();
    return fallback;
  }
}