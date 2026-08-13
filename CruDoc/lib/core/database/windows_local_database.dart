import 'package:sqflite_common/sqlite_api.dart' as sqflite_common;

import 'local_database.dart';

/// [LocalDatabase] adapter around the `sqflite_common_ffi` backend used on
/// Windows.
///
/// This keeps the Windows implementation isolated behind the existing
/// [LocalDatabase] abstraction. The rest of CruDoc continues to call the same
/// query/insert/update/delete/execute/rawQuery/transaction API as the SQLCipher
/// path, without branching on platform or importing a backend-specific package.
class WindowsDatabase extends _WindowsExecutor implements LocalDatabase {
  WindowsDatabase(this._db) : super(_db);

  final sqflite_common.Database _db;

  @override
  Future<T> transaction<T>(
    Future<T> Function(LocalDatabaseTransaction txn) action,
  ) {
    return _db.transaction<T>((txn) => action(_WindowsTransaction(txn)));
  }

  @override
  Future<void> close() => _db.close();
}

/// Adapts a single FFI transaction handle to [LocalDatabaseTransaction].
class _WindowsTransaction extends _WindowsExecutor
    implements LocalDatabaseTransaction {
  _WindowsTransaction(super.executor);
}

abstract class _WindowsExecutor implements LocalDatabaseExecutor {
  _WindowsExecutor(this._executor);

  final sqflite_common.DatabaseExecutor _executor;

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  }) {
    return _executor.query(
      table,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
    );
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    LocalConflictAlgorithm? conflictAlgorithm,
  }) {
    return _executor.insert(
      table,
      values,
      conflictAlgorithm: _toWindowsConflictAlgorithm(conflictAlgorithm),
    );
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) {
    return _executor.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
    );
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) {
    return _executor.delete(table, where: where, whereArgs: whereArgs);
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) {
    return _executor.execute(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) {
    return _executor.rawQuery(sql, arguments);
  }
}

sqflite_common.ConflictAlgorithm? _toWindowsConflictAlgorithm(
  LocalConflictAlgorithm? algorithm,
) {
  switch (algorithm) {
    case null:
      return null;
    case LocalConflictAlgorithm.rollback:
      return sqflite_common.ConflictAlgorithm.rollback;
    case LocalConflictAlgorithm.abort:
      return sqflite_common.ConflictAlgorithm.abort;
    case LocalConflictAlgorithm.fail:
      return sqflite_common.ConflictAlgorithm.fail;
    case LocalConflictAlgorithm.ignore:
      return sqflite_common.ConflictAlgorithm.ignore;
    case LocalConflictAlgorithm.replace:
      return sqflite_common.ConflictAlgorithm.replace;
  }
}
