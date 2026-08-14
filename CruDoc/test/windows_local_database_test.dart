import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart' as sqflite_common;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;

import 'package:doctor_management_app/core/database/local_database.dart';
import 'package:doctor_management_app/core/database/windows_local_database.dart';

void main() {
  setUpAll(() {
    sqflite_ffi.sqfliteFfiInit();
  });

  test('WindowsDatabase supports CRUD and transactions through the LocalDatabase abstraction', () async {
    final dbPath = '${Directory.systemTemp.path}/crudoc_windows_local_db_${DateTime.now().microsecondsSinceEpoch}.db';

    final database = await sqflite_ffi.databaseFactoryFfi.openDatabase(
      dbPath,
      options: sqflite_common.OpenDatabaseOptions(version: 1),
    );
    addTearDown(() async {
      await database.close();
      final file = File(dbPath);
      if (await file.exists()) {
        await file.delete();
      }
    });

    final localDb = WindowsDatabase(database);

    await localDb.execute('''
      CREATE TABLE items (
        id TEXT PRIMARY KEY,
        value TEXT NOT NULL DEFAULT '',
        count INTEGER NOT NULL DEFAULT 0
      )
    ''');

    final insertedId = await localDb.insert(
      'items',
      {'id': 'item-1', 'value': 'alpha', 'count': 1},
      conflictAlgorithm: LocalConflictAlgorithm.replace,
    );
    expect(insertedId, 1);

    final readBack = await localDb.query(
      'items',
      columns: ['id', 'value', 'count'],
      where: 'id = ?',
      whereArgs: ['item-1'],
      limit: 1,
    );
    expect(readBack, [
      {'id': 'item-1', 'value': 'alpha', 'count': 1},
    ]);

    final updatedRows = await localDb.update(
      'items',
      {'value': 'beta', 'count': 2},
      where: 'id = ?',
      whereArgs: ['item-1'],
    );
    expect(updatedRows, 1);

    final deletedRows = await localDb.delete('items', where: 'id = ?', whereArgs: ['item-1']);
    expect(deletedRows, 1);

    await localDb.transaction((txn) async {
      await txn.insert('items', {'id': 'item-2', 'value': 'gamma', 'count': 3});
      await txn.insert('items', {'id': 'item-3', 'value': 'delta', 'count': 4});
      final count = await txn.rawQuery('SELECT COUNT(*) as count FROM items');
      expect(count.first['count'], 2);
    });

    final finalRows = await localDb.query('items', orderBy: 'id');
    expect(finalRows.length, 2);
    expect(finalRows.map((row) => row['id']).toList(), ['item-2', 'item-3']);
  });

  test('Parent row update with child foreign keys on DELETE RESTRICT works without FK constraint violation', () async {
    final dbPath = '${Directory.systemTemp.path}/crudoc_fk_test_${DateTime.now().microsecondsSinceEpoch}.db';

    final database = await sqflite_ffi.databaseFactoryFfi.openDatabase(
      dbPath,
      options: sqflite_common.OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
    addTearDown(() async {
      await database.close();
      final file = File(dbPath);
      if (await file.exists()) {
        await file.delete();
      }
    });

    final localDb = WindowsDatabase(database);

    await localDb.execute('''
      CREATE TABLE parents (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL
      )
    ''');
    await localDb.execute('''
      CREATE TABLE children (
        id TEXT PRIMARY KEY,
        parentId TEXT NOT NULL,
        FOREIGN KEY (parentId) REFERENCES parents (id) ON DELETE RESTRICT
      )
    ''');

    // Insert parent and child
    await localDb.insert('parents', {'id': 'p1', 'name': 'Parent Initial'});
    await localDb.insert('children', {'id': 'c1', 'parentId': 'p1'});

    // Updating existing parent via update() works cleanly while maintaining child FK
    final count = await localDb.update('parents', {'name': 'Parent Updated'}, where: 'id = ?', whereArgs: ['p1']);
    expect(count, 1);

    final parent = await localDb.query('parents', where: 'id = ?', whereArgs: ['p1']);
    expect(parent.first['name'], 'Parent Updated');
  });
}
