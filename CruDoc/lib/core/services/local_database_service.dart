import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Singleton SQLite database service for CruDoc's local-first data layer.
///
/// Phase 1 only creates the local schema and guarded migrations. Repositories
/// continue using their current data sources until Phase 2 wires them to these
/// tables one collection at a time.
class LocalDatabaseService extends ChangeNotifier {
  LocalDatabaseService._();

  static final LocalDatabaseService instance = LocalDatabaseService._();

  static const String _databaseName = 'crudoc.db';
  static const int _databaseVersion = 1;

  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;

    final databasesPath = await getDatabasesPath();
    final dbPath = p.join(databasesPath, _databaseName);

    final db = await openDatabase(
      dbPath,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await _runGuardedMigrations(db);
      },
    );

    _database = db;
    return db;
  }

  Future<void> close() async {
    final db = _database;
    if (db == null) return;

    await db.close();
    _database = null;
  }

  Future<void> _createSchema(Database db) async {
    await db.transaction((txn) async {
      await _createPatientsTable(txn);
      await _createVisitsTable(txn);
      await _createSyncStateTable(txn);
      await _createIndexes(txn);
    });
  }

  /// Runs idempotent migrations in the same style as CruSam: inspect the
  /// existing table shape via PRAGMA table_info, then ALTER TABLE only when a
  /// column is missing. No versioned onUpgrade ladder is used.
  Future<void> _runGuardedMigrations(Database db) async {
    await db.transaction((txn) async {
      await _createPatientsTable(txn);
      await _createVisitsTable(txn);
      await _createSyncStateTable(txn);

      await _ensureColumns(txn, table: 'patients', columns: _patientsColumns);
      await _ensureColumns(txn, table: 'visits', columns: _visitsColumns);
      await _ensureColumns(
        txn,
        table: 'sync_state',
        columns: _syncStateColumns,
      );

      await _createIndexes(txn);
    });
  }

  Future<void> _createPatientsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS patients (
        id TEXT PRIMARY KEY,
        firstName TEXT NOT NULL DEFAULT '',
        lastName TEXT NOT NULL DEFAULT '',
        phone TEXT NOT NULL DEFAULT '',
        gender TEXT NOT NULL DEFAULT '',
        dateOfBirth INTEGER NOT NULL,
        diagnosis TEXT NOT NULL DEFAULT '',
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

  Future<void> _createVisitsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS visits (
        id TEXT PRIMARY KEY,
        patientId TEXT NOT NULL,
        scheduledStart INTEGER NOT NULL,
        durationMinutes INTEGER NOT NULL DEFAULT 30,
        address TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'scheduled'
          CHECK (status IN ('scheduled', 'completed', 'cancelled', 'missed')),
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

  Future<void> _createSyncStateTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_state (
        collectionName TEXT PRIMARY KEY,
        lastSyncTime INTEGER NOT NULL DEFAULT 0,
        hasCompletedInitialMigration INTEGER NOT NULL DEFAULT 0,
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _createIndexes(DatabaseExecutor db) async {
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
  }

  Future<void> _ensureColumns(
    DatabaseExecutor db, {
    required String table,
    required Map<String, String> columns,
  }) async {
    final existingColumns = await _columnNames(db, table);
    for (final entry in columns.entries) {
      if (existingColumns.contains(entry.key)) continue;
      await db.execute('ALTER TABLE $table ADD COLUMN ${entry.value}');
    }
  }

  Future<Set<String>> _columnNames(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => row['name'] as String).toSet();
  }

  static const Map<String, String> _patientsColumns = {
    'id': 'id TEXT PRIMARY KEY',
    'firstName': "firstName TEXT NOT NULL DEFAULT ''",
    'lastName': "lastName TEXT NOT NULL DEFAULT ''",
    'phone': "phone TEXT NOT NULL DEFAULT ''",
    'gender': "gender TEXT NOT NULL DEFAULT ''",
    'dateOfBirth': 'dateOfBirth INTEGER NOT NULL DEFAULT 0',
    'diagnosis': "diagnosis TEXT NOT NULL DEFAULT ''",
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
    'patientId': "patientId TEXT NOT NULL DEFAULT ''",
    'scheduledStart': 'scheduledStart INTEGER NOT NULL DEFAULT 0',
    'durationMinutes': 'durationMinutes INTEGER NOT NULL DEFAULT 30',
    'address': "address TEXT NOT NULL DEFAULT ''",
    'status': "status TEXT NOT NULL DEFAULT 'scheduled'",
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

  static const Map<String, String> _syncStateColumns = {
    'collectionName': 'collectionName TEXT PRIMARY KEY',
    'lastSyncTime': 'lastSyncTime INTEGER NOT NULL DEFAULT 0',
    'hasCompletedInitialMigration':
        'hasCompletedInitialMigration INTEGER NOT NULL DEFAULT 0',
    'updatedAt': 'updatedAt INTEGER NOT NULL DEFAULT 0',
  };
}
