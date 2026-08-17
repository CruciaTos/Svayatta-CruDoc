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
  Future<void> upsertNote(ConsultationNote note) async {
    final db = await LocalDatabaseService.instance.localDatabase;
    final map = note.toLocalMap();
    await db.insert(
      'consultation_notes',
      map,
      conflictAlgorithm: LocalConflictAlgorithm.replace,
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

  Future<List<ConsultationNote>> getNotesForPatient(String patientId) async {
    final db = await LocalDatabaseService.instance.localDatabase;
    final rows = await db.query(
      'consultation_notes',
      where: 'patientId = ?',
      whereArgs: [patientId],
      orderBy: 'createdAt DESC',
    );
    return rows
        .map((r) => ConsultationNote.fromMap(r, id: r['id'] as String))
        .toList();
  }
}
