import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/sqlite_api.dart' as sqflite_common;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import '../database/local_database.dart';
import '../database/sqlcipher_local_database.dart';
import '../database/windows_local_database.dart';

/// Singleton SQLite database service for CruDoc's local-first data layer.
///
/// Phase 1 only creates the local schema and guarded migrations. Repositories
/// continue using their current data sources until Phase 2 wires them to these
/// tables one collection at a time.
class LocalDatabaseService extends ChangeNotifier {
  LocalDatabaseService._();

  static final LocalDatabaseService instance = LocalDatabaseService._();

  static const String _databaseNamePrefix = 'crudoc';
  static const int _databaseVersion = 1;

  static final FlutterSecureStorage _secureStorage = kIsWeb
      ? const FlutterSecureStorage()
      : const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );
  static const _dbPassphraseKey = 'crudoc_local_db_passphrase';

  sqflite_common.Database? _database;
  String? _databaseDoctorId;

  /// Set once, the first time a Windows database is opened in this process.
  /// `sqfliteFfiInit()` just points `sqflite_common_ffi` at its `sqlite3`
  /// loader — safe to call more than once, but there's no reason to redo it
  /// on every doctor switch.
  static bool _windowsFfiInitialized = false;

  Future<sqflite_common.Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError('SQLite is disabled on Web. Repositories read directly from Cloud Firestore on Web.');
    }

    final requestedDoctorId = FirebaseAuth.instance.currentUser?.uid ?? 'signed_out';
    final existing = _database;
    if (existing != null && _databaseDoctorId == requestedDoctorId) {
      return existing;
    }
    if (existing != null) {
      await existing.close();
      _database = null;
      _databaseDoctorId = null;
    }

    final fileName = _databaseFileNameForDoctor(requestedDoctorId);
    final db = Platform.isWindows
        ? await _openWindowsDatabaseWithRecovery(fileName)
        : await _openSqlCipherDatabaseWithRecovery(fileName);

    _database = db;
    _databaseDoctorId = requestedDoctorId;
    return db;
  }

  /// [LocalDatabase]-typed access to the same underlying connection as
  /// [database]. This is the entry point repositories and local services
  /// should use — it carries no `sqflite_sqlcipher` or `sqflite_common_ffi`
  /// types in its signature. Windows gets [WindowsDatabase]; every other
  /// native platform keeps the existing [SqlCipherDatabase]. Consumers on
  /// either platform see the same [LocalDatabase] contract.
  ///
  /// `FirestoreSyncService` and `InitialFirestoreMigrationService` continue
  /// to use [database] directly and are unaffected by this — both backends
  /// hand back the same `sqflite_common.Database` type those services
  /// already import (via `sqflite_sqlcipher`'s re-export of it).
  Future<LocalDatabase> get localDatabase async {
    final db = await database;
    return Platform.isWindows ? WindowsDatabase(db) : SqlCipherDatabase(db);
  }

  String _databaseFileNameForDoctor(String doctorId) {
    final safeDoctorId = doctorId.trim().isEmpty ? 'signed_out' : doctorId;
    return '${_databaseNamePrefix}_$safeDoctorId.db';
  }

  Future<sqflite_common.Database> _openSqlCipherDatabaseWithRecovery(
    String fileName,
  ) async {
    final databasesPath = await sqlcipher.getDatabasesPath();
    final dbPath = p.join(databasesPath, fileName);
    final passphrase = await _getOrCreatePassphrase();

    Future<sqflite_common.Database> open() => sqlcipher.openDatabase(
          dbPath,
          password: passphrase,
          version: _databaseVersion,
          onConfigure: (db) async {
            await SqlCipherDatabase(db).execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (db, version) async {
            await _createSchema(SqlCipherDatabase(db));
          },
          onOpen: (db) async {
            final localDb = SqlCipherDatabase(db);
            await localDb.execute('PRAGMA foreign_keys = ON');
            await _runGuardedMigrations(localDb);
          },
        );

    try {
      return await open();
    } on sqflite_common.DatabaseException catch (error) {
      if (!_isRecoverableOpenError(error)) {
        rethrow;
      }

      try {
        await sqlcipher.deleteDatabase(dbPath);
      } catch (_) {
        // Ignore cleanup failures and retry once; the next open attempt will
        // surface the real issue if the database is still not recoverable.
      }

      return open();
    }
  }

  /// Windows counterpart of [_openSqlCipherDatabaseWithRecovery]. Same
  /// recovery behavior, same schema/migration calls, same
  /// `PRAGMA foreign_keys = ON` — just opened through `sqflite_common_ffi`
  /// instead of `sqflite_sqlcipher` (which has no Windows implementation),
  /// and with no passphrase: the local cache is unencrypted at rest on
  /// Windows today. See the doc comment on [WindowsDatabase] for why that's
  /// an intentional gap, not an oversight.
  Future<sqflite_common.Database> _openWindowsDatabaseWithRecovery(
    String fileName,
  ) async {
    if (!_windowsFfiInitialized) {
      sqflite_ffi.sqfliteFfiInit();
      _windowsFfiInitialized = true;
    }

    final dbPath = await _windowsDatabasePath(fileName);

    Future<sqflite_common.Database> open() =>
        sqflite_ffi.databaseFactoryFfi.openDatabase(
          dbPath,
          options: sqflite_common.OpenDatabaseOptions(
            version: _databaseVersion,
            onConfigure: (db) async {
              await WindowsDatabase(db).execute('PRAGMA foreign_keys = ON');
            },
            onCreate: (db, version) async {
              await _createSchema(WindowsDatabase(db));
            },
            onOpen: (db) async {
              final localDb = WindowsDatabase(db);
              await localDb.execute('PRAGMA foreign_keys = ON');
              await _runGuardedMigrations(localDb);
            },
          ),
        );

    try {
      return await open();
    } on sqflite_common.DatabaseException catch (error) {
      if (!_isRecoverableOpenError(error)) {
        rethrow;
      }

      try {
        await sqflite_ffi.databaseFactoryFfi.deleteDatabase(dbPath);
      } catch (_) {
        // Ignore cleanup failures and retry once; the next open attempt will
        // surface the real issue if the database is still not recoverable.
      }

      return open();
    }
  }

  /// `databaseFactoryFfi.getDatabasesPath()` has a "lame implementation" by
  /// its own package's documentation (it's not meaningful outside
  /// mobile/desktop plugin sandboxing) — so, unlike the SQLCipher path,
  /// Windows resolves its database directory via `path_provider`, which
  /// this project already depends on and already uses for other
  /// Windows-specific paths (see `windows_update_installer.dart`).
  Future<String> _windowsDatabasePath(String fileName) async {
    final supportDir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(supportDir.path, 'databases'));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    return p.join(dbDir.path, fileName);
  }

  bool _isRecoverableOpenError(sqflite_common.DatabaseException error) {
    final message = error.toString().toLowerCase();
    return message.contains('file is not a database') ||
        message.contains('not a database') ||
        message.contains('unable to determine format version') ||
        message.contains('hmac') ||
        message.contains('open_failed');
  }

  /// Encrypts the local SQLite file at rest with a random 256-bit passphrase
  /// unique to this device install. The passphrase itself lives only in
  /// OS-backed secure storage (Android Keystore / iOS Keychain) — it never
  /// needs to sync between devices, since the local database is just a
  /// disposable cache of Firestore data, re-downloadable from scratch.
  Future<String> _getOrCreatePassphrase() async {
    final existing = await _secureStorage.read(key: _dbPassphraseKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final passphrase = base64UrlEncode(bytes);
    await _secureStorage.write(key: _dbPassphraseKey, value: passphrase);
    return passphrase;
  }

  Future<void> close() async {
    final db = _database;
    if (db == null) return;

    await db.close();
    _database = null;
    _databaseDoctorId = null;
  }

  Future<void> _createSchema(LocalDatabase db) async {
    await db.transaction((txn) async {
      await _createPatientsTable(txn);
      await _createVisitsTable(txn);
      await _createRevenueEntriesTable(txn);
      await _createPendingPaymentsTable(txn);
      await _createMedicinesTable(txn);
      await _createStockTransactionsTable(txn);
      await _createEmailLogTable(txn);
      await _createConsultationNotesTable(txn);
      await _createSyncStateTable(txn);
      await _createAppMetaTable(txn);
      await _createIndexes(txn);
    });
  }

  /// Runs idempotent migrations in the same style as CruSam: inspect the
  /// existing table shape via PRAGMA table_info, then ALTER TABLE only when a
  /// column is missing. No versioned onUpgrade ladder is used.
  Future<void> _runGuardedMigrations(LocalDatabase db) async {
    await db.transaction((txn) async {
      await _createPatientsTable(txn);
      await _createVisitsTable(txn);
      await _createRevenueEntriesTable(txn);
      await _createPendingPaymentsTable(txn);
      await _createMedicinesTable(txn);
      await _createStockTransactionsTable(txn);
      await _createEmailLogTable(txn);
      await _createConsultationNotesTable(txn);
      await _createSyncStateTable(txn);
      await _createAppMetaTable(txn);

      await _ensureColumns(txn, table: 'patients', columns: _patientsColumns);
      await _ensureColumns(txn, table: 'visits', columns: _visitsColumns);
      await _ensureColumns(
        txn,
        table: 'revenue_entries',
        columns: _revenueEntriesColumns,
      );
      await _ensureColumns(
        txn,
        table: 'pending_payments',
        columns: _pendingPaymentsColumns,
      );
      await _ensureColumns(
        txn,
        table: 'medicines',
        columns: _medicinesColumns,
      );
      await _ensureColumns(
        txn,
        table: 'stock_transactions',
        columns: _stockTransactionsColumns,
      );
      await _ensureColumns(
        txn,
        table: 'email_log',
        columns: _emailLogColumns,
      );
      await _ensureColumns(
        txn,
        table: 'consultation_notes',
        columns: _consultationNotesColumns,
      );
      await _ensureColumns(
        txn,
        table: 'sync_state',
        columns: _syncStateColumns,
      );

      await _createIndexes(txn);
    });
  }

  Future<void> _createPatientsTable(LocalDatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS patients (
        id TEXT PRIMARY KEY,
        doctorId TEXT NOT NULL DEFAULT '',
        firstName TEXT NOT NULL DEFAULT '',
        lastName TEXT NOT NULL DEFAULT '',
        phone TEXT NOT NULL DEFAULT '',
        email TEXT NOT NULL DEFAULT '',
        gender TEXT NOT NULL DEFAULT '',
        dateOfBirth INTEGER NOT NULL,
        diagnosis TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        packageBalance REAL NOT NULL DEFAULT 0,
        isArchived INTEGER NOT NULL DEFAULT 0,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        syncStatus TEXT NOT NULL DEFAULT 'synced'
          CHECK (syncStatus IN ('synced', 'pending')),
        pendingDelete INTEGER NOT NULL DEFAULT 0,
        lastSyncedAt INTEGER
      )
    ''');
  }

  Future<void> _createVisitsTable(LocalDatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS visits (
        id TEXT PRIMARY KEY,
        doctorId TEXT NOT NULL DEFAULT '',
        patientId TEXT NOT NULL,
        scheduledStart INTEGER NOT NULL,
        durationMinutes INTEGER NOT NULL DEFAULT 30,
        address TEXT NOT NULL DEFAULT '',
        latitude REAL,
        longitude REAL,
        mapsLink TEXT,
        visitType TEXT NOT NULL DEFAULT 'clinic'
          CHECK (visitType IN ('clinic', 'home')),
        status TEXT NOT NULL DEFAULT 'scheduled'
          CHECK (status IN ('scheduled', 'completed', 'cancelled', 'missed')),
        isPaid INTEGER NOT NULL DEFAULT 0,
        amountCharged REAL,
        isDeleted INTEGER NOT NULL DEFAULT 0,
        isActive INTEGER NOT NULL DEFAULT 1,
        invoiceId TEXT,
        packageId TEXT,
        treatmentType TEXT,
        therapistNotes TEXT,
        reminderStatus TEXT,
        calendarEventId TEXT,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        syncStatus TEXT NOT NULL DEFAULT 'synced'
          CHECK (syncStatus IN ('synced', 'pending')),
        pendingDelete INTEGER NOT NULL DEFAULT 0,
        lastSyncedAt INTEGER,
        FOREIGN KEY (patientId) REFERENCES patients (id) ON DELETE RESTRICT
      )
    ''');
  }

  Future<void> _createRevenueEntriesTable(LocalDatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS revenue_entries (
        id TEXT PRIMARY KEY,
        doctorId TEXT NOT NULL DEFAULT '',
        date INTEGER NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        amount REAL NOT NULL DEFAULT 0,
        type TEXT NOT NULL DEFAULT 'miscellaneous'
          CHECK (type IN ('visit', 'online', 'miscellaneous')),
        kind TEXT NOT NULL DEFAULT 'income',
        payer TEXT,
        patientId TEXT,
        visitId TEXT,
        isDeleted INTEGER NOT NULL DEFAULT 0,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        syncStatus TEXT NOT NULL DEFAULT 'synced'
          CHECK (syncStatus IN ('synced', 'pending')),
        pendingDelete INTEGER NOT NULL DEFAULT 0,
        lastSyncedAt INTEGER
      )
    ''');
  }

  Future<void> _createPendingPaymentsTable(LocalDatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_payments (
        id TEXT PRIMARY KEY,
        doctorId TEXT NOT NULL DEFAULT '',
        date INTEGER NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        amount REAL NOT NULL DEFAULT 0,
        isPaid INTEGER NOT NULL DEFAULT 0,
        payer TEXT,
        patientId TEXT,
        visitId TEXT,
        notes TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        syncStatus TEXT NOT NULL DEFAULT 'synced'
          CHECK (syncStatus IN ('synced', 'pending')),
        pendingDelete INTEGER NOT NULL DEFAULT 0,
        lastSyncedAt INTEGER
      )
    ''');
  }

  Future<void> _createMedicinesTable(LocalDatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS medicines (
        id TEXT PRIMARY KEY,
        doctorId TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL DEFAULT '',
        unit TEXT NOT NULL DEFAULT '',
        currentStock INTEGER NOT NULL DEFAULT 0,
        reorderThreshold INTEGER NOT NULL DEFAULT 10,
        unitPrice REAL,
        supplierName TEXT,
        batchNumber TEXT,
        expiryDate INTEGER,
        lowStockNotifiedAt INTEGER,
        expiryNotifiedAt INTEGER,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        syncStatus TEXT NOT NULL DEFAULT 'synced'
          CHECK (syncStatus IN ('synced', 'pending')),
        pendingDelete INTEGER NOT NULL DEFAULT 0,
        lastSyncedAt INTEGER
      )
    ''');
  }

  Future<void> _createStockTransactionsTable(LocalDatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_transactions (
        id TEXT PRIMARY KEY,
        medicineId TEXT NOT NULL,
        doctorId TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL DEFAULT 'restock'
          CHECK (type IN ('restock', 'dispense', 'adjustment', 'expired_writeoff')),
        quantity INTEGER NOT NULL DEFAULT 0,
        resultingStock INTEGER NOT NULL DEFAULT 0,
        note TEXT,
        linkedVisitId TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        syncStatus TEXT NOT NULL DEFAULT 'synced'
          CHECK (syncStatus IN ('synced', 'pending')),
        pendingDelete INTEGER NOT NULL DEFAULT 0,
        lastSyncedAt INTEGER,
        FOREIGN KEY (medicineId) REFERENCES medicines (id) ON DELETE RESTRICT
      )
    ''');
  }

  Future<void> _createSyncStateTable(LocalDatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_state (
        collectionName TEXT PRIMARY KEY,
        lastSyncTime INTEGER NOT NULL DEFAULT 0,
        hasCompletedInitialMigration INTEGER NOT NULL DEFAULT 0,
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _createAppMetaTable(LocalDatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_meta (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  static const String _cachedDoctorIdKey = 'cachedDoctorId';

  Future<String?> _getMeta(String key) async {
    final db = await localDatabase;
    final rows = await db.query(
      'app_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> _setMeta(String key, String value) async {
    final db = await localDatabase;
    await db.insert('app_meta', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: LocalConflictAlgorithm.replace);
  }

  /// Ensures the local cache on this device actually belongs to
  /// [signedInDoctorId]. If the device previously cached a *different*
  /// doctor's data (e.g. this tablet was reassigned, or someone signed out
  /// and a different account signed in), every local table is wiped before
  /// any new data is loaded — otherwise the previous doctor's patients,
  /// visits, and revenue would still be sitting in this device's cache and
  /// could even get merged back up to the new doctor's Firestore data on
  /// the next sync.
  ///
  /// Safe to call on every app start / sign-in. No-ops when the cache
  /// already belongs to this doctor or the cache is empty (first run).
  Future<void> ensureLocalDataMatchesSignedInDoctor(
    String signedInDoctorId,
  ) async {
    final cachedDoctorId = await _getMeta(_cachedDoctorIdKey);
    if (cachedDoctorId == null || cachedDoctorId.isEmpty) {
      await _setMeta(_cachedDoctorIdKey, signedInDoctorId);
      return;
    }
    if (cachedDoctorId == signedInDoctorId) return;

    await wipeAllLocalData();
    await _setMeta(_cachedDoctorIdKey, signedInDoctorId);
  }

  /// Deletes every row from every local table and resets sync watermarks,
  /// so the next sync pass rebuilds the cache from scratch for whichever
  /// doctor is now signed in. Called on doctor-switch (see above) and on
  /// sign-out.
  Future<void> wipeAllLocalData() async {
    final db = await localDatabase;
    await db.transaction((txn) async {
      for (final table in const [
        'patients',
        'visits',
        'revenue_entries',
        'pending_payments',
        'medicines',
        'stock_transactions',
        'email_log',
        'consultation_notes',
        'sync_state',
      ]) {
        await txn.delete(table);
      }
    });
  }

  Future<void> _createIndexes(LocalDatabaseExecutor db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_patients_doctor
      ON patients (doctorId)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_patients_active_created
      ON patients (isActive, isArchived, createdAt DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_patients_name_lookup
      ON patients (firstName, lastName)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_patients_phone_lookup
      ON patients (phone)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_patients_sync_pending
      ON patients (syncStatus, pendingDelete)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_patients_updated_at
      ON patients (updatedAt)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_visits_doctor
      ON visits (doctorId)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_visits_doc_deleted_start
      ON visits (doctorId, isDeleted, scheduledStart DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_visits_upcoming
      ON visits (isActive, isDeleted, status, scheduledStart)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_visits_patient_history
      ON visits (patientId, isDeleted, scheduledStart DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_visits_overlap_lookup
      ON visits (scheduledStart)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_visits_sync_pending
      ON visits (syncStatus, pendingDelete)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_visits_updated_at
      ON visits (updatedAt)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_revenue_entries_doctor
      ON revenue_entries (doctorId)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_revenue_doc_deleted_date
      ON revenue_entries (doctorId, isDeleted, date DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_revenue_entries_active_date
      ON revenue_entries (isActive, isDeleted, date DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_revenue_entries_type
      ON revenue_entries (type)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_revenue_entries_kind
      ON revenue_entries (kind)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_revenue_entries_sync_pending
      ON revenue_entries (syncStatus, pendingDelete)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_revenue_entries_updated_at
      ON revenue_entries (updatedAt)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pending_payments_doctor
      ON pending_payments (doctorId)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pending_payments_active_unpaid
      ON pending_payments (isActive, isPaid, date DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pending_payments_sync_pending
      ON pending_payments (syncStatus, pendingDelete)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pending_payments_updated_at
      ON pending_payments (updatedAt)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_medicines_active_name
      ON medicines (isActive, name)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_medicines_category
      ON medicines (category)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_medicines_sync_pending
      ON medicines (syncStatus, pendingDelete)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_medicines_updated_at
      ON medicines (updatedAt)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_stock_transactions_medicine_history
      ON stock_transactions (medicineId, createdAt DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_stock_transactions_sync_pending
      ON stock_transactions (syncStatus, pendingDelete)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_stock_transactions_updated_at
      ON stock_transactions (updatedAt)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_email_log_doctor
      ON email_log (doctorId)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_email_log_doc_status_attempt
      ON email_log (doctorId, status, attemptedAt DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_email_log_gmail_msg_id
      ON email_log (gmailMessageId)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_email_log_visit_id
      ON email_log (visitId)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_consultation_notes_visit
      ON consultation_notes (visitId, createdAt DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_consultation_notes_doctor
      ON consultation_notes (doctorId, createdAt DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_consultation_notes_status
      ON consultation_notes (visitId, status)
    ''');
  }

  Future<void> _ensureColumns(
    LocalDatabaseExecutor db, {
    required String table,
    required Map<String, String> columns,
  }) async {
    final existingColumns = await _columnNames(db, table);
    for (final entry in columns.entries) {
      if (existingColumns.contains(entry.key)) continue;
      await db.execute('ALTER TABLE $table ADD COLUMN ${entry.value}');
    }
  }

  Future<Set<String>> _columnNames(LocalDatabaseExecutor db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => row['name'] as String).toSet();
  }

  static const Map<String, String> _patientsColumns = {
    'id': 'id TEXT PRIMARY KEY',
    'doctorId': "doctorId TEXT NOT NULL DEFAULT ''",
    'firstName': "firstName TEXT NOT NULL DEFAULT ''",
    'lastName': "lastName TEXT NOT NULL DEFAULT ''",
    'phone': "phone TEXT NOT NULL DEFAULT ''",
    'email': "email TEXT NOT NULL DEFAULT ''",
    'gender': "gender TEXT NOT NULL DEFAULT ''",
    'dateOfBirth': 'dateOfBirth INTEGER NOT NULL DEFAULT 0',
    'diagnosis': "diagnosis TEXT NOT NULL DEFAULT ''",
    'notes': "notes TEXT NOT NULL DEFAULT ''",
    'packageBalance': 'packageBalance REAL NOT NULL DEFAULT 0',
    'isArchived': 'isArchived INTEGER NOT NULL DEFAULT 0',
    'isActive': 'isActive INTEGER NOT NULL DEFAULT 1',
    'createdAt': 'createdAt INTEGER NOT NULL DEFAULT 0',
    'updatedAt': 'updatedAt INTEGER NOT NULL DEFAULT 0',
    'syncStatus': "syncStatus TEXT NOT NULL DEFAULT 'synced'",
    'pendingDelete': 'pendingDelete INTEGER NOT NULL DEFAULT 0',
    'lastSyncedAt': 'lastSyncedAt INTEGER',
  };

  static const Map<String, String> _visitsColumns = {
    'id': 'id TEXT PRIMARY KEY',
    'doctorId': "doctorId TEXT NOT NULL DEFAULT ''",
    'patientId': "patientId TEXT NOT NULL DEFAULT ''",
    'scheduledStart': 'scheduledStart INTEGER NOT NULL DEFAULT 0',
    'durationMinutes': 'durationMinutes INTEGER NOT NULL DEFAULT 30',
    'address': "address TEXT NOT NULL DEFAULT ''",
    'latitude': 'latitude REAL',
    'longitude': 'longitude REAL',
    'mapsLink': 'mapsLink TEXT',
    'visitType': "visitType TEXT NOT NULL DEFAULT 'clinic'",
    'status': "status TEXT NOT NULL DEFAULT 'scheduled'",
    'isPaid': 'isPaid INTEGER NOT NULL DEFAULT 0',
    'amountCharged': 'amountCharged REAL',
    'isDeleted': 'isDeleted INTEGER NOT NULL DEFAULT 0',
    'isActive': 'isActive INTEGER NOT NULL DEFAULT 1',
    'invoiceId': 'invoiceId TEXT',
    'packageId': 'packageId TEXT',
    'treatmentType': 'treatmentType TEXT',
    'therapistNotes': 'therapistNotes TEXT',
    'reminderStatus': 'reminderStatus TEXT',
    'calendarEventId': 'calendarEventId TEXT',
    'createdAt': 'createdAt INTEGER NOT NULL DEFAULT 0',
    'updatedAt': 'updatedAt INTEGER NOT NULL DEFAULT 0',
    'syncStatus': "syncStatus TEXT NOT NULL DEFAULT 'synced'",
    'pendingDelete': 'pendingDelete INTEGER NOT NULL DEFAULT 0',
    'lastSyncedAt': 'lastSyncedAt INTEGER',
  };

  static const Map<String, String> _revenueEntriesColumns = {
    'id': 'id TEXT PRIMARY KEY',
    'doctorId': "doctorId TEXT NOT NULL DEFAULT ''",
    'date': 'date INTEGER NOT NULL DEFAULT 0',
    'description': "description TEXT NOT NULL DEFAULT ''",
    'amount': 'amount REAL NOT NULL DEFAULT 0',
    'type': "type TEXT NOT NULL DEFAULT 'miscellaneous'",
    'kind': "kind TEXT NOT NULL DEFAULT 'income'",
    'payer': 'payer TEXT',
    'patientId': 'patientId TEXT',
    'visitId': 'visitId TEXT',
    'isDeleted': 'isDeleted INTEGER NOT NULL DEFAULT 0',
    'isActive': 'isActive INTEGER NOT NULL DEFAULT 1',
    'createdAt': 'createdAt INTEGER NOT NULL DEFAULT 0',
    'updatedAt': 'updatedAt INTEGER NOT NULL DEFAULT 0',
    'syncStatus': "syncStatus TEXT NOT NULL DEFAULT 'synced'",
    'pendingDelete': 'pendingDelete INTEGER NOT NULL DEFAULT 0',
    'lastSyncedAt': 'lastSyncedAt INTEGER',
  };

  static const Map<String, String> _pendingPaymentsColumns = {
    'id': 'id TEXT PRIMARY KEY',
    'doctorId': "doctorId TEXT NOT NULL DEFAULT ''",
    'date': 'date INTEGER NOT NULL DEFAULT 0',
    'description': "description TEXT NOT NULL DEFAULT ''",
    'amount': 'amount REAL NOT NULL DEFAULT 0',
    'isPaid': 'isPaid INTEGER NOT NULL DEFAULT 0',
    'payer': 'payer TEXT',
    'patientId': 'patientId TEXT',
    'visitId': 'visitId TEXT',
    'notes': 'notes TEXT',
    'isActive': 'isActive INTEGER NOT NULL DEFAULT 1',
    'createdAt': 'createdAt INTEGER NOT NULL DEFAULT 0',
    'updatedAt': 'updatedAt INTEGER NOT NULL DEFAULT 0',
    'syncStatus': "syncStatus TEXT NOT NULL DEFAULT 'synced'",
    'pendingDelete': 'pendingDelete INTEGER NOT NULL DEFAULT 0',
    'lastSyncedAt': 'lastSyncedAt INTEGER',
  };

  static const Map<String, String> _medicinesColumns = {
    'id': 'id TEXT PRIMARY KEY',
    'doctorId': "doctorId TEXT NOT NULL DEFAULT ''",
    'name': "name TEXT NOT NULL DEFAULT ''",
    'category': "category TEXT NOT NULL DEFAULT ''",
    'unit': "unit TEXT NOT NULL DEFAULT ''",
    'currentStock': 'currentStock INTEGER NOT NULL DEFAULT 0',
    'reorderThreshold': 'reorderThreshold INTEGER NOT NULL DEFAULT 10',
    'unitPrice': 'unitPrice REAL',
    'supplierName': 'supplierName TEXT',
    'batchNumber': 'batchNumber TEXT',
    'expiryDate': 'expiryDate INTEGER',
    'lowStockNotifiedAt': 'lowStockNotifiedAt INTEGER',
    'expiryNotifiedAt': 'expiryNotifiedAt INTEGER',
    'isActive': 'isActive INTEGER NOT NULL DEFAULT 1',
    'createdAt': 'createdAt INTEGER NOT NULL DEFAULT 0',
    'updatedAt': 'updatedAt INTEGER NOT NULL DEFAULT 0',
    'syncStatus': "syncStatus TEXT NOT NULL DEFAULT 'synced'",
    'pendingDelete': 'pendingDelete INTEGER NOT NULL DEFAULT 0',
    'lastSyncedAt': 'lastSyncedAt INTEGER',
  };

  static const Map<String, String> _stockTransactionsColumns = {
    'id': 'id TEXT PRIMARY KEY',
    'medicineId': "medicineId TEXT NOT NULL DEFAULT ''",
    'doctorId': "doctorId TEXT NOT NULL DEFAULT ''",
    'type': "type TEXT NOT NULL DEFAULT 'restock'",
    'quantity': 'quantity INTEGER NOT NULL DEFAULT 0',
    'resultingStock': 'resultingStock INTEGER NOT NULL DEFAULT 0',
    'note': 'note TEXT',
    'linkedVisitId': 'linkedVisitId TEXT',
    'isActive': 'isActive INTEGER NOT NULL DEFAULT 1',
    'createdAt': 'createdAt INTEGER NOT NULL DEFAULT 0',
    'updatedAt': 'updatedAt INTEGER NOT NULL DEFAULT 0',
    'syncStatus': "syncStatus TEXT NOT NULL DEFAULT 'synced'",
    'pendingDelete': 'pendingDelete INTEGER NOT NULL DEFAULT 0',
    'lastSyncedAt': 'lastSyncedAt INTEGER',
  };

  static const Map<String, String> _syncStateColumns = {
    'collectionName': 'collectionName TEXT PRIMARY KEY',
    'lastSyncTime': 'lastSyncTime INTEGER NOT NULL DEFAULT 0',
    'hasCompletedInitialMigration':
        'hasCompletedInitialMigration INTEGER NOT NULL DEFAULT 0',
    'updatedAt': 'updatedAt INTEGER NOT NULL DEFAULT 0',
  };

  Future<void> _createConsultationNotesTable(LocalDatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS consultation_notes (
        id TEXT PRIMARY KEY,
        doctorId TEXT NOT NULL DEFAULT '',
        patientId TEXT NOT NULL DEFAULT '',
        visitId TEXT NOT NULL DEFAULT '',
        transcript TEXT NOT NULL DEFAULT '',
        chiefComplaint TEXT NOT NULL DEFAULT '',
        symptoms TEXT NOT NULL DEFAULT '[]',
        diagnosisSuggestions TEXT NOT NULL DEFAULT '[]',
        medicines TEXT NOT NULL DEFAULT '[]',
        advice TEXT NOT NULL DEFAULT '',
        followUpDate INTEGER,
        vitals TEXT NOT NULL DEFAULT '{}',
        confidenceNote TEXT NOT NULL DEFAULT '',
        consentGiven INTEGER NOT NULL DEFAULT 1,
        consentAt INTEGER,
        audioStoragePath TEXT,
        status TEXT NOT NULL DEFAULT 'draft'
          CHECK (status IN ('draft', 'confirmed', 'discarded')),
        createdAt INTEGER NOT NULL,
        confirmedAt INTEGER,
        updatedAt INTEGER
      )
    ''');
  }

  static const Map<String, String> _consultationNotesColumns = {
    'id': 'id TEXT PRIMARY KEY',
    'doctorId': "doctorId TEXT NOT NULL DEFAULT ''",
    'patientId': "patientId TEXT NOT NULL DEFAULT ''",
    'visitId': "visitId TEXT NOT NULL DEFAULT ''",
    'transcript': "transcript TEXT NOT NULL DEFAULT ''",
    'chiefComplaint': "chiefComplaint TEXT NOT NULL DEFAULT ''",
    'symptoms': "symptoms TEXT NOT NULL DEFAULT '[]'",
    'diagnosisSuggestions': "diagnosisSuggestions TEXT NOT NULL DEFAULT '[]'",
    'medicines': "medicines TEXT NOT NULL DEFAULT '[]'",
    'advice': "advice TEXT NOT NULL DEFAULT ''",
    'followUpDate': 'followUpDate INTEGER',
    'vitals': "vitals TEXT NOT NULL DEFAULT '{}'",
    'confidenceNote': "confidenceNote TEXT NOT NULL DEFAULT ''",
    'consentGiven': 'consentGiven INTEGER NOT NULL DEFAULT 1',
    'consentAt': 'consentAt INTEGER',
    'audioStoragePath': 'audioStoragePath TEXT',
    'status': "status TEXT NOT NULL DEFAULT 'draft'",
    'createdAt': 'createdAt INTEGER NOT NULL DEFAULT 0',
    'confirmedAt': 'confirmedAt INTEGER',
    'updatedAt': 'updatedAt INTEGER',
  };

  Future<void> _createEmailLogTable(LocalDatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS email_log (
        id TEXT PRIMARY KEY,
        doctorId TEXT NOT NULL DEFAULT '',
        patientId TEXT,
        visitId TEXT,
        recipientEmail TEXT NOT NULL DEFAULT '',
        recipientName TEXT,
        subject TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'pending'
          CHECK (status IN ('pending', 'sent', 'failed')),
        gmailMessageId TEXT,
        gmailThreadId TEXT,
        failureReason TEXT,
        senderEmail TEXT NOT NULL DEFAULT '',
        attemptedAt INTEGER NOT NULL,
        sentAt INTEGER,
        createdAt INTEGER NOT NULL
      )
    ''');
  }

  static const Map<String, String> _emailLogColumns = {
    'id': 'id TEXT PRIMARY KEY',
    'doctorId': "doctorId TEXT NOT NULL DEFAULT ''",
    'patientId': 'patientId TEXT',
    'visitId': 'visitId TEXT',
    'recipientEmail': "recipientEmail TEXT NOT NULL DEFAULT ''",
    'recipientName': 'recipientName TEXT',
    'subject': "subject TEXT NOT NULL DEFAULT ''",
    'status': "status TEXT NOT NULL DEFAULT 'pending'",
    'gmailMessageId': 'gmailMessageId TEXT',
    'gmailThreadId': 'gmailThreadId TEXT',
    'failureReason': 'failureReason TEXT',
    'senderEmail': "senderEmail TEXT NOT NULL DEFAULT ''",
    'attemptedAt': 'attemptedAt INTEGER NOT NULL DEFAULT 0',
    'sentAt': 'sentAt INTEGER',
    'createdAt': 'createdAt INTEGER NOT NULL DEFAULT 0',
  };
}