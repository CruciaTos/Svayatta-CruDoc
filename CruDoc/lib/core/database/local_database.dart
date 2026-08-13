/// Minimal database abstraction for CruDoc's local-first data layer.
///
/// Repositories and per-feature local services depend on [LocalDatabase]
/// instead of importing `sqflite_sqlcipher` or `sqflite_common_ffi`
/// directly. Two implementations plug in behind this interface, selected by
/// `LocalDatabaseService` at open time — repositories and the sync services
/// never branch on platform themselves:
///
/// ```text
/// Repositories / Services
///         ↓
/// LocalDatabase abstraction
///         ↓
///   ┌─────────────┬─────────────────┐
///   SqlCipherDatabase          WindowsDatabase
///   ↓                          ↓
///   sqflite_sqlcipher          sqflite_common_ffi
///   (mobile / macOS)           (Windows)
/// ```
///
/// See `sqlcipher_local_database.dart` and `windows_local_database.dart` in
/// this directory for the two adapters.
///
/// This interface intentionally only covers the operations CruDoc actually
/// uses today (query / insert / update / delete / execute / rawQuery /
/// transactions). It is not a general-purpose ORM, and it does not attempt
/// to model connection lifecycle (opening, per-doctor file switching,
/// passphrase handling, corruption recovery) — that stays the
/// responsibility of `LocalDatabaseService`, exactly as it is today.

/// Conflict resolution strategies for [LocalDatabaseExecutor.insert] and
/// [LocalDatabaseExecutor.update]. Mirrors SQLite's own `ON CONFLICT`
/// clause (and `sqflite`'s `ConflictAlgorithm`) so callers above this layer
/// don't need to import a backend-specific package just for this enum.
enum LocalConflictAlgorithm { rollback, abort, fail, ignore, replace }

/// The read/write surface shared by a top-level [LocalDatabase] connection
/// and a [LocalDatabaseTransaction].
///
/// `sqflite_sqlcipher`'s own `Database` and `Transaction` types both
/// implement a common `DatabaseExecutor` interface today — this mirrors
/// that split so the adapter can wrap either one the same way.
abstract class LocalDatabaseExecutor {
  /// Reads rows from [table]. Only the query features CruDoc's local
  /// services actually use are exposed: column projection, a `where`
  /// clause with positional `whereArgs`, ordering, and a row limit.
  Future<List<Map<String, Object?>>> query(
    String table, {
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  });

  /// Inserts [values] into [table], returning the backend's row id.
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    LocalConflictAlgorithm? conflictAlgorithm,
  });

  /// Updates rows in [table] matching `where`/`whereArgs`.
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  });

  /// Deletes rows from [table] matching `where`/`whereArgs`. Omitting both
  /// deletes every row in the table (used by
  /// `LocalDatabaseService.wipeAllLocalData`).
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  });

  /// Runs a raw SQL statement (schema DDL, `PRAGMA`s, `ALTER TABLE`, etc.)
  /// that doesn't return rows.
  Future<void> execute(String sql, [List<Object?>? arguments]);

  /// Runs a raw SQL query (e.g. `PRAGMA table_info(...)`) and returns rows.
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]);
}

/// A single database transaction. Every operation performed through a
/// [LocalDatabaseTransaction] commits or rolls back atomically together
/// with the rest of the block passed to [LocalDatabase.transaction].
abstract class LocalDatabaseTransaction implements LocalDatabaseExecutor {}

/// A local, on-device database connection.
///
/// `LocalDatabaseService` owns exactly one [LocalDatabase] at a time (per
/// signed-in doctor, following its existing per-doctor-file lifecycle) and
/// hands it out to repositories and local services. This interface is
/// deliberately backend-agnostic: nothing in its signature names
/// `sqflite_sqlcipher`, `sqflite_common_ffi`, or any other concrete
/// package.
abstract class LocalDatabase implements LocalDatabaseExecutor {
  /// Runs [action] inside a single database transaction, matching SQLite's
  /// atomicity/rollback-on-error semantics.
  Future<T> transaction<T>(
    Future<T> Function(LocalDatabaseTransaction txn) action,
  );

  /// Closes the underlying connection. Mirrors the existing
  /// `sqflite_sqlcipher` `Database.close()` call already used by
  /// `LocalDatabaseService`.
  Future<void> close();
}