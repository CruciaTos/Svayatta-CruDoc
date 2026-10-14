import 'dart:async';

import 'package:doctor_management_app/core/database/local_database.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';

/// Local SQLite service for the [ConsultationNote] entity.
///
/// Follows the same pattern as [VisitLocalService] and [PatientLocalService]:
/// reads/writes go through [LocalDatabaseService.localDatabase], with timestamps
/// stored as milliseconds-since-epoch integers.
///
/// Note: PHI fields (transcript, chiefComplaint, symptoms, etc.) are stored
/// in their encrypted form by [ConsultationNoteRepository] before being handed
/// to this service — this layer treats them as opaque strings.
class ConsultationNoteLocalService {
  /// Where a row stands against the clinic's Firestore copy. Drafts stay
  /// [syncLocal] — only confirmed session notes leave the device.
  static const syncLocal = 'local';
  static const syncPending = 'pending';
  static const syncSynced = 'synced';

  static final StreamController<void> _changes =
      StreamController<void>.broadcast();

  /// Fires whenever a note is written, so session history lists refresh.
  static Stream<void> get changes => _changes.stream;

  static void notifyChanged() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> upsertNote(
    ConsultationNote note, {
    String syncStatus = syncLocal,
  }) async {
    final db = await LocalDatabaseService.instance.localDatabase;
    final map = {...note.toLocalMap(), 'syncStatus': syncStatus};
    await db.insert(
      'consultation_notes',
      map,
      conflictAlgorithm: LocalConflictAlgorithm.replace,
    );
    notifyChanged();
  }

  Future<void> setSyncStatus(String noteId, String syncStatus) async {
    final db = await LocalDatabaseService.instance.localDatabase;
    await db.update(
      'consultation_notes',
      {'syncStatus': syncStatus},
      where: 'id = ?',
      whereArgs: [noteId],
    );
  }

  /// The patient's confirmed session notes, newest session first.
  Future<List<ConsultationNote>> getSessionHistory(String patientId) async {
    final db = await LocalDatabaseService.instance.localDatabase;
    final rows = await db.query(
      'consultation_notes',
      where: "patientId = ? AND status = 'confirmed'",
      whereArgs: [patientId],
      orderBy: 'createdAt DESC',
    );
    return rows
        .map((r) => ConsultationNote.fromMap(r, id: r['id'] as String))
        .toList();
  }

  /// Confirmed notes written while offline (or whose upload failed).
  Future<List<ConsultationNote>> getPendingUploads() async {
    final db = await LocalDatabaseService.instance.localDatabase;
    final rows = await db.query(
      'consultation_notes',
      where: "status = 'confirmed' AND syncStatus = ?",
      whereArgs: [syncPending],
    );
    return rows
        .map((r) => ConsultationNote.fromMap(r, id: r['id'] as String))
        .toList();
  }

  /// When the local copy of [noteId] last changed, or null if there is none.
  Future<({int updatedAt, String syncStatus})?> localStamp(
    String noteId,
  ) async {
    final db = await LocalDatabaseService.instance.localDatabase;
    final rows = await db.query(
      'consultation_notes',
      columns: ['updatedAt', 'createdAt', 'syncStatus'],
      where: 'id = ?',
      whereArgs: [noteId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return (
      updatedAt: (r['updatedAt'] as int?) ?? (r['createdAt'] as int?) ?? 0,
      syncStatus: r['syncStatus'] as String? ?? syncLocal,
    );
  }

  Future<void> updateNoteFields(
    String noteId,
    Map<String, dynamic> fields,
  ) async {
    final db = await LocalDatabaseService.instance.localDatabase;
    final updated = {
      ...fields,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await db.update(
      'consultation_notes',
      updated,
      where: 'id = ?',
      whereArgs: [noteId],
    );
    notifyChanged();
  }

  Future<ConsultationNote?> getNote(String noteId) async {
    final db = await LocalDatabaseService.instance.localDatabase;
    final rows = await db.query(
      'consultation_notes',
      where: 'id = ?',
      whereArgs: [noteId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ConsultationNote.fromMap(rows.first, id: rows.first['id'] as String);
  }

  /// Streams all notes for a given visit, newest first.
  Stream<List<ConsultationNote>> watchNotesForVisit(String visitId) {
    // SQLite doesn't natively emit change events — this stream emits once on
    // subscription. The scribe flow always re-opens the review screen after a
    // write, so a single emission on subscription is sufficient for the UI.
    final controller = StreamController<List<ConsultationNote>>();

    Future<void> emit() async {
      final db = await LocalDatabaseService.instance.localDatabase;
      final rows = await db.query(
        'consultation_notes',
        where: 'visitId = ?',
        whereArgs: [visitId],
        orderBy: 'createdAt DESC',
      );
      final notes = rows
          .map((r) => ConsultationNote.fromMap(r, id: r['id'] as String))
          .toList();
      if (!controller.isClosed) controller.add(notes);
    }

    emit();
    return controller.stream;
  }

  /// Returns the most recent draft note for a visit, or null.
  Future<ConsultationNote?> getDraftForVisit(String visitId) async {
    final db = await LocalDatabaseService.instance.localDatabase;
    final rows = await db.query(
      'consultation_notes',
      where: "visitId = ? AND status = 'draft'",
      whereArgs: [visitId],
      orderBy: 'createdAt DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ConsultationNote.fromMap(rows.first, id: rows.first['id'] as String);
  }
}
