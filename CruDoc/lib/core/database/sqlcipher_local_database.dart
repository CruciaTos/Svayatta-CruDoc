import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import 'local_database.dart';

/// [LocalDatabase] adapter around the existing `sqflite_sqlcipher` backend
/// used on Android/iOS.
///
/// This is a thin wrapper only: it does not open, encrypt, or recover the
/// database itself. `LocalDatabaseService` still owns that lifecycle
/// exactly as before — per-doctor file naming, passphrase handling via
/// `flutter_secure_storage`, and corruption recovery are all unchanged.
/// `SqlCipherDatabase` simply adapts an already-open
/// `sqflite_sqlcipher.Database` to the [LocalDatabase] contract, so
/// repositories and local services no longer need to import
/// `sqflite_sqlcipher` themselves.
class SqlCipherDatabase extends _SqlCipherExecutor implements LocalDatabase {
  SqlCipherDatabase(this._db) : super(_db);

  final sqlcipher.Database _db;

  @override
  Future<T> transaction<T>(
    Future<T> Function(LocalDatabaseTransaction txn) action,
  ) {
    return _db.transaction<T>((txn) => action(_SqlCipherTransaction(txn)));
  }

  @override
  Future<void> close() => _db.close();
}

/// Adapts a single `sqflite_sqlcipher` transaction handle to
/// [LocalDatabaseTransaction].
class _SqlCipherTransaction extends _SqlCipherExecutor
    implements LocalDatabaseTransaction {
  _SqlCipherTransaction(super.executor);
}

/// Shared implementation of [LocalDatabaseExecutor] for both a top-level
/// connection and a transaction. `sqflite_sqlcipher`'s `Database` and
/// `Transaction` both implement its own `DatabaseExecutor` interface, so a
/// single wrapper covers both cases — it just delegates every call
/// straight through to the underlying executor.
abstract class _SqlCipherExecutor implements LocalDatabaseExecutor {
  _SqlCipherExecutor(this._executor);

  final sqlcipher.DatabaseExecutor _executor;

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
      conflictAlgorithm: _toSqlCipherConflictAlgorithm(conflictAlgorithm),
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

sqlcipher.ConflictAlgorithm? _toSqlCipherConflictAlgorithm(
  LocalConflictAlgorithm? algorithm,
) {
  switch (algorithm) {
    case null:
      return null;
    case LocalConflictAlgorithm.rollback:
      return sqlcipher.ConflictAlgorithm.rollback;
    case LocalConflictAlgorithm.abort:
      return sqlcipher.ConflictAlgorithm.abort;
    case LocalConflictAlgorithm.fail:
      return sqlcipher.ConflictAlgorithm.fail;
    case LocalConflictAlgorithm.ignore:
      return sqlcipher.ConflictAlgorithm.ignore;
    case LocalConflictAlgorithm.replace:
      return sqlcipher.ConflictAlgorithm.replace;
  }
}
