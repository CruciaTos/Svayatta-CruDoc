import 'package:flutter/foundation.dart';
import 'package:doctor_management_app/core/database/local_database.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/features/messaging/data/models/whatsapp_notification_log.dart';

/// Local database service for persisting and querying WhatsApp dispatch audit logs.
///
/// Follows CruDoc's local-first architecture:
/// - Uses [LocalDatabaseService] and [LocalDatabase]
/// - Scoped to `doctorId` to prevent multi-tenant data leakage
/// - Parameterized SQL statements to prevent SQL injection
/// - Handles status transitions (pending -> sent / delivered / read / failed / skipped)
class WhatsAppLogLocalService {
  WhatsAppLogLocalService({LocalDatabaseService? dbService})
      : _dbService = dbService ?? LocalDatabaseService.instance;

  final LocalDatabaseService _dbService;

  static const String tableName = 'whatsapp_log';

  /// Ensures the `whatsapp_log` table and required indexes exist.
  Future<void> ensureTableCreated(LocalDatabase db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        id TEXT PRIMARY KEY,
        doctorId TEXT NOT NULL DEFAULT '',
        patientId TEXT NOT NULL DEFAULT '',
        visitId TEXT NOT NULL DEFAULT '',
        recipientPhone TEXT NOT NULL DEFAULT '',
        recipientName TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'pending',
        whatsappMessageId TEXT,
        failureReason TEXT,
        attemptCount INTEGER NOT NULL DEFAULT 1,
        isMock INTEGER NOT NULL DEFAULT 0,
        attemptedAt INTEGER NOT NULL,
        sentAt INTEGER,
        deliveredAt INTEGER,
        readAt INTEGER,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_whatsapp_log_doctor
      ON $tableName (doctorId)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_whatsapp_log_visit_id
      ON $tableName (visitId)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_whatsapp_log_doc_status
      ON $tableName (doctorId, status, attemptedAt DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_whatsapp_log_msg_id
      ON $tableName (whatsappMessageId)
    ''');
  }

  /// Inserts a new WhatsApp log entry.
  Future<void> insertLog(WhatsAppNotificationLog entry) async {
    if (kIsWeb) return;
    final db = await _dbService.localDatabase;
    await ensureTableCreated(db);

    await db.insert(
      tableName,
      entry.toMap(),
      conflictAlgorithm: LocalConflictAlgorithm.replace,
    );
  }

  /// Updates the status and delivery metadata of an existing WhatsApp log entry.
  Future<void> updateLogStatus(
    String id,
    WhatsAppNotificationStatus status, {
    String? whatsappMessageId,
    String? failureReason,
    DateTime? sentAt,
    DateTime? deliveredAt,
    DateTime? readAt,
  }) async {
    if (kIsWeb) return;
    final db = await _dbService.localDatabase;
    await ensureTableCreated(db);

    final values = <String, Object?>{
      'status': status.value,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    if (whatsappMessageId != null) values['whatsappMessageId'] = whatsappMessageId;
    if (failureReason != null) values['failureReason'] = failureReason;
    if (sentAt != null) values['sentAt'] = sentAt.millisecondsSinceEpoch;
    if (deliveredAt != null) values['deliveredAt'] = deliveredAt.millisecondsSinceEpoch;
    if (readAt != null) values['readAt'] = readAt.millisecondsSinceEpoch;

    await db.update(
      tableName,
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Looks up a log entry by its associated appointment / visit ID.
  Future<WhatsAppNotificationLog?> getLogByVisitId(String visitId, String doctorId) async {
    if (kIsWeb) return null;
    final db = await _dbService.localDatabase;
    await ensureTableCreated(db);

    final rows = await db.query(
      tableName,
      where: 'visitId = ? AND doctorId = ?',
      whereArgs: [visitId, doctorId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return WhatsAppNotificationLog.fromMap(rows.first);
  }

  /// Retrieves recent WhatsApp logs for a specific doctor.
  Future<List<WhatsAppNotificationLog>> getLogsForDoctor(String doctorId, {int limit = 50}) async {
    if (kIsWeb) return [];
    final db = await _dbService.localDatabase;
    await ensureTableCreated(db);

    final rows = await db.query(
      tableName,
      where: 'doctorId = ?',
      whereArgs: [doctorId],
      orderBy: 'attemptedAt DESC',
      limit: limit,
    );

    return rows.map((r) => WhatsAppNotificationLog.fromMap(r)).toList();
  }

  /// Reconciles stuck pending logs (e.g. after an unexpected app closure).
  Future<void> reconcilePendingLogs(String doctorId) async {
    if (kIsWeb) return;
    final db = await _dbService.localDatabase;
    await ensureTableCreated(db);

    final rows = await db.query(
      tableName,
      where: 'doctorId = ? AND status = ?',
      whereArgs: [doctorId, WhatsAppNotificationStatus.pending.value],
    );

    final now = DateTime.now();
    for (final row in rows) {
      final log = WhatsAppNotificationLog.fromMap(row);
      if (now.difference(log.attemptedAt).inMinutes >= 5) {
        if (log.whatsappMessageId != null && log.whatsappMessageId!.isNotEmpty) {
          await updateLogStatus(log.id, WhatsAppNotificationStatus.sent, sentAt: log.attemptedAt);
        } else {
          await updateLogStatus(log.id, WhatsAppNotificationStatus.failed, failureReason: 'interrupted_or_timeout');
        }
      }
    }
  }
}
