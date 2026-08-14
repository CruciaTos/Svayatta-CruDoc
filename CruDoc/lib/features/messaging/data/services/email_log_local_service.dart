import 'package:flutter/foundation.dart';
import 'package:doctor_management_app/core/database/local_database.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/features/messaging/data/models/email_log_entry.dart';

/// Local database service for persisting and querying email dispatch audit logs.
///
/// Follows the established CruDoc architecture:
/// - Depends on [LocalDatabaseService] and [LocalDatabase]
/// - Doctor-scoped queries to prevent multi-tenant data leakage
/// - Parameterized SQL statements to prevent injection
/// - Supports crash recovery for pending email states
class EmailLogLocalService {
  EmailLogLocalService({LocalDatabaseService? dbService})
      : _dbService = dbService ?? LocalDatabaseService.instance;

  final LocalDatabaseService _dbService;

  static const String tableName = 'email_log';

  /// Ensures the `email_log` table and required indexes exist.
  Future<void> ensureTableCreated(LocalDatabase db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        id TEXT PRIMARY KEY,
        doctorId TEXT NOT NULL DEFAULT '',
        patientId TEXT,
        visitId TEXT,
        recipientEmail TEXT NOT NULL DEFAULT '',
        recipientName TEXT,
        subject TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed')),
        gmailMessageId TEXT,
        gmailThreadId TEXT,
        failureReason TEXT,
        senderEmail TEXT NOT NULL DEFAULT '',
        attemptedAt INTEGER NOT NULL,
        sentAt INTEGER,
        createdAt INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_email_log_doctor
      ON $tableName (doctorId)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_email_log_doc_status_attempt
      ON $tableName (doctorId, status, attemptedAt DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_email_log_gmail_msg_id
      ON $tableName (gmailMessageId)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_email_log_visit_id
      ON $tableName (visitId)
    ''');
  }

  /// Inserts a new email log entry (typically in `pending` state).
  Future<void> insertLog(EmailLogEntry entry) async {
    if (kIsWeb) return;
    final db = await _dbService.localDatabase;
    await ensureTableCreated(db);

    await db.insert(
      tableName,
      entry.toMap(),
      conflictAlgorithm: LocalConflictAlgorithm.replace,
    );
  }

  /// Updates the status and metadata of an existing email log entry.
  Future<void> updateLogStatus(
    String id,
    EmailLogStatus status, {
    String? gmailMessageId,
    String? gmailThreadId,
    String? failureReason,
    DateTime? sentAt,
  }) async {
    if (kIsWeb) return;
    final db = await _dbService.localDatabase;
    await ensureTableCreated(db);

    final values = <String, Object?>{
      'status': status.value,
    };
    if (gmailMessageId != null) values['gmailMessageId'] = gmailMessageId;
    if (gmailThreadId != null) values['gmailThreadId'] = gmailThreadId;
    if (failureReason != null) values['failureReason'] = failureReason;
    if (sentAt != null) values['sentAt'] = sentAt.millisecondsSinceEpoch;

    await db.update(
      tableName,
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Retrieves recent email logs for a specific doctor.
  Future<List<EmailLogEntry>> getLogsForDoctor(
    String doctorId, {
    int limit = 50,
  }) async {
    if (kIsWeb) return [];
    if (doctorId.trim().isEmpty) return [];

    final db = await _dbService.localDatabase;
    await ensureTableCreated(db);

    final maps = await db.query(
      tableName,
      where: 'doctorId = ?',
      whereArgs: [doctorId],
      orderBy: 'attemptedAt DESC',
      limit: limit,
    );

    return maps.map((m) => EmailLogEntry.fromMap(m)).toList();
  }

  /// Retrieves all `pending` email logs for crash reconciliation.
  Future<List<EmailLogEntry>> getPendingLogs(String doctorId) async {
    if (kIsWeb) return [];
    if (doctorId.trim().isEmpty) return [];

    final db = await _dbService.localDatabase;
    await ensureTableCreated(db);

    final maps = await db.query(
      tableName,
      where: 'doctorId = ? AND status = ?',
      whereArgs: [doctorId, EmailLogStatus.pending.value],
      orderBy: 'attemptedAt ASC',
    );

    return maps.map((m) => EmailLogEntry.fromMap(m)).toList();
  }

  /// Checks if an email was already logged for a given appointment visit.
  Future<EmailLogEntry?> getLogByVisitId(String visitId, String doctorId) async {
    if (kIsWeb) return null;
    if (visitId.trim().isEmpty || doctorId.trim().isEmpty) return null;

    final db = await _dbService.localDatabase;
    await ensureTableCreated(db);

    final maps = await db.query(
      tableName,
      where: 'visitId = ? AND doctorId = ?',
      whereArgs: [visitId, doctorId],
      orderBy: 'attemptedAt DESC',
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return EmailLogEntry.fromMap(maps.first);
  }

  /// Looks up a log by its Gmail Message ID (useful for idempotency verification).
  Future<EmailLogEntry?> getLogByGmailMessageId(String gmailMessageId) async {
    if (kIsWeb) return null;
    if (gmailMessageId.trim().isEmpty) return null;

    final db = await _dbService.localDatabase;
    await ensureTableCreated(db);

    final maps = await db.query(
      tableName,
      where: 'gmailMessageId = ?',
      whereArgs: [gmailMessageId],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return EmailLogEntry.fromMap(maps.first);
  }
}
