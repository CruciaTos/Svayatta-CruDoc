import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:sqflite/sqflite.dart';

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

  static const List<String> _collections = ['patients', 'visits'];

  Future<void> runIfNeeded() async {
    for (final collection in _collections) {
      if (await _hasCompletedInitialMigration(collection)) continue;
      try {
        await _migrateCollection(collection);
      } catch (_) {
        // Keep the guard unset so the next launch can retry. Startup should not
        // be blocked just because Firestore is temporarily unavailable.
      }
    }
  }

  Future<void> _migrateCollection(String collection) async {
    final snapshot = await _firestore.collection(collection).get();
    var newestUpdatedAt = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final row = _sqliteRowFor(collection, doc.id, data);
      final updatedAt = (row['updatedAt'] as num?)?.toInt() ?? 0;
      if (updatedAt > newestUpdatedAt) newestUpdatedAt = updatedAt;

      final db = await _databaseService.database;
      await db.insert(
        collection,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await _markInitialMigrationComplete(collection, newestUpdatedAt);
  }

  Future<bool> _hasCompletedInitialMigration(String collection) async {
    final db = await _databaseService.database;
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
    final db = await _databaseService.database;
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

  Map<String, dynamic> _sqliteRowFor(
    String collection,
    String id,
    Map<String, dynamic> data,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    switch (collection) {
      case 'patients':
        return {
          'id': id,
          'firstName': data['firstName'] as String? ?? '',
          'lastName': data['lastName'] as String? ?? '',
          'phone': data['phone'] as String? ?? '',
          'gender': data['gender'] as String? ?? '',
          'dateOfBirth': _timestampToMillis(data['dateOfBirth'], fallback: now),
          'diagnosis': data['diagnosis'] as String? ?? '',
          'packageBalance': (data['packageBalance'] as num?)?.toDouble() ?? 0,
          'isArchived': (data['isArchived'] as bool? ?? false) ? 1 : 0,
          'isActive': (data['isActive'] as bool? ?? true) ? 1 : 0,
          'createdAt': _timestampToMillis(data['createdAt'], fallback: now),
          'updatedAt': _timestampToMillis(data['updatedAt'], fallback: now),
          'syncStatus': 'synced',
          'pendingDelete': 0,
          'lastSyncedAt': now,
        };
      case 'visits':
        return {
          'id': id,
          'patientId': data['patientId'] as String? ?? '',
          'scheduledStart': _timestampToMillis(
            data['scheduledStart'],
            fallback: now,
          ),
          'durationMinutes': (data['durationMinutes'] as num?)?.toInt() ?? 30,
          'address': data['address'] as String? ?? '',
          'status': data['status'] as String? ?? 'scheduled',
          'isDeleted': (data['isDeleted'] as bool? ?? false) ? 1 : 0,
          'isActive': (data['isActive'] as bool? ?? true) ? 1 : 0,
          'invoiceId': data['invoiceId'] as String?,
          'packageId': data['packageId'] as String?,
          'treatmentType': data['treatmentType'] as String?,
          'therapistNotes': data['therapistNotes'] as String?,
          'reminderStatus': data['reminderStatus'] as String?,
          'calendarEventId': data['calendarEventId'] as String?,
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
