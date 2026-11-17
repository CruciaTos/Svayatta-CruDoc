import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:doctor_management_app/core/services/firestore_sync_service.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/appointments/data/services/visits_local_service.dart';
import 'package:doctor_management_app/features/patients/data/services/patient_local_service.dart';
import 'package:doctor_management_app/features/revenue/data/services/revenue_local_service.dart';

/// One-time Firestore-to-SQLite bootstrap for existing cloud data.
///
/// Runs once per collection after the local database is available and before
/// incremental sync starts. Completion is guarded in `sync_state`.
class InitialFirestoreMigrationService {
  InitialFirestoreMigrationService._();

  static final InitialFirestoreMigrationService instance =
      InitialFirestoreMigrationService._();

  final LocalDatabaseService _databaseService = LocalDatabaseService.instance;

  static const List<String> _collections = [
    'patients',
    'appointments', // VisitType.clinic  → visits SQLite table
    'visitations', // VisitType.home    → visits SQLite table
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

  /// Whether [runIfNeeded] still has a collection to pull from the cloud.
  ///
  /// Local reads only. False means [runIfNeeded] would return without touching
  /// the network, so startup can simply await it.
  Future<bool> hasWorkToDo() async {
    final doctorId = ClinicSession.instance.tenantId;
    if (doctorId == null || doctorId.isEmpty) return false;
    for (final collection in _collections) {
      if (!FirestoreSyncService.canReadCollection(collection)) continue;
      if (!await _hasCompletedInitialMigration(collection)) return true;
    }
    return false;
  }

  /// Tells the screens reading [collection] from SQLite that rows landed. The
  /// migration writes straight to the database, so without this a screen that
  /// is already open (startup no longer waits for it) would keep showing the
  /// emptiness it first read.
  void _notifyChanged(String collection) {
    if (_visitFirestoreToType.containsKey(collection)) {
      VisitLocalService.instance.notifyVisitsChanged();
      return;
    }
    switch (collection) {
      case 'patients':
        PatientLocalService.instance.notifyPatientsChanged();
        break;
      case 'revenue_entries':
        RevenueLocalService.instance.notifyRevenueEntriesChanged();
        break;
      case 'pending_payments':
        RevenueLocalService.instance.notifyPendingPaymentsChanged();
        break;
    }
  }

  Future<void> runIfNeeded() async {
    final doctorId = ClinicSession.instance.tenantId;
    if (doctorId == null || doctorId.isEmpty) {
      // Not signed in yet — nothing to migrate, and querying without a
      // doctorId would either fail the security rules or (worse, if rules
      // are ever loosened) pull every doctor's data. Bail out; this is
      // re-invoked once the doctor signs in (see main.dart).
      return;
    }

    await _databaseService.ensureLocalDataMatchesSignedInDoctor(
      LocalDatabaseService.scopeFor(
        doctorId,
        FirebaseAuth.instance.currentUser?.uid ?? doctorId,
      ),
    );

    for (final collection in _collections) {
      // The rules refuse collections this person can't read.
      if (!FirestoreSyncService.canReadCollection(collection)) continue;
      if (await _hasCompletedInitialMigration(collection)) continue;
      try {
        await _migrateCollection(collection, doctorId);
        _notifyChanged(collection);
      } catch (e, st) {
        // Keep the guard unset so the next launch can retry. Startup should not
        // be blocked just because Firestore is temporarily unavailable.
        debugPrint('Initial migration failed for $collection: $e\n$st');
      }
    }
  }

  Future<void> _migrateCollection(String collection, String doctorId) async {
    // The first pull is the sync service's paged catch-up from cursor 0:
    // scoped to this clinic (and narrowed to a scoped doctor's own patients,
    // or the rules refuse it), from the server only, a page at a time with
    // the cursor saved after each page, so an interrupted run resumes
    // instead of starting over. Rows land with the same mapping and the
    // same "a pending local edit wins" rule as every later sync.
    await FirestoreSyncService.instance.catchUpCollection(collection, doctorId);
    await _markInitialMigrationComplete(collection);
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

  Future<void> _markInitialMigrationComplete(String collection) async {
    final db = await _databaseService.localDatabase;
    final now = DateTime.now().millisecondsSinceEpoch;
    // The catch-up already saved the cursor (and lastSyncTime); only the
    // completion flag changes here.
    final updated = await db.update(
      'sync_state',
      {'hasCompletedInitialMigration': 1, 'updatedAt': now},
      where: 'collectionName = ?',
      whereArgs: [collection],
    );
    if (updated > 0) return;

    await db.insert('sync_state', {
      'collectionName': collection,
      'lastSyncTime': 0,
      'hasCompletedInitialMigration': 1,
      'updatedAt': now,
    });
  }
}
