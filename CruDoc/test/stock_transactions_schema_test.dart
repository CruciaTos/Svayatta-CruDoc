import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';

/// firestore_sync_service.dart inserts and reads `groupId` for
/// stock_transactions. Databases created before that column existed must be
/// upgraded in place, or every live-sync doc fails with "table
/// stock_transactions has no column named groupId".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('a legacy stock_transactions table gains groupId on open', () async {
    // Without Firebase auth the service opens `crudoc_signed_out.db` under the
    // temp dir (path_provider is unavailable in unit tests).
    final dbFile = p.join(
      Directory.systemTemp.path,
      'databases',
      'crudoc_signed_out.db',
    );
    await Directory(p.dirname(dbFile)).create(recursive: true);
    await databaseFactory.deleteDatabase(dbFile);

    // A pre-groupId database: current user_version, old table shape.
    final legacy = await databaseFactory.openDatabase(
      dbFile,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) => db.execute('''
          CREATE TABLE stock_transactions (
            id TEXT PRIMARY KEY,
            medicineId TEXT NOT NULL,
            doctorId TEXT NOT NULL DEFAULT '',
            type TEXT NOT NULL DEFAULT 'restock',
            quantity INTEGER NOT NULL DEFAULT 0,
            resultingStock INTEGER NOT NULL DEFAULT 0,
            note TEXT,
            linkedVisitId TEXT,
            isActive INTEGER NOT NULL DEFAULT 1,
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL,
            syncStatus TEXT NOT NULL DEFAULT 'synced',
            pendingDelete INTEGER NOT NULL DEFAULT 0,
            lastSyncedAt INTEGER
          )
        '''),
      ),
    );
    await legacy.close();

    final db = await LocalDatabaseService.instance.localDatabase;
    final columns = (await db.rawQuery('PRAGMA table_info(stock_transactions)'))
        .map((row) => row['name'])
        .toSet();
    expect(columns, contains('groupId'));

    await LocalDatabaseService.instance.close();
    await databaseFactory.deleteDatabase(dbFile);
  });
}
