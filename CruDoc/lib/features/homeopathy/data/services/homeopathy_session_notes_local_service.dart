import 'dart:async';
import 'package:doctor_management_app/core/database/local_database.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_session_note.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';

/// SQLite DAO for homeopathy session (follow-up visit) notes, strictly
/// scoped to the active doctor. Each row is one visit — never overwritten —
/// so a patient's rows ordered by [sessionDate] are their session history.
class HomeopathySessionNotesLocalService {
  factory HomeopathySessionNotesLocalService({
    LocalDatabaseService? databaseService,
  }) {
    if (databaseService != null) {
      return HomeopathySessionNotesLocalService._(databaseService);
    }
    return instance;
  }

  HomeopathySessionNotesLocalService._(this._databaseService);

  static final HomeopathySessionNotesLocalService instance =
      HomeopathySessionNotesLocalService._(LocalDatabaseService.instance);

  final LocalDatabaseService _databaseService;
  final StreamController<void> _changeController =
      StreamController<void>.broadcast();

  Stream<void> get changes => _changeController.stream;

  String get _currentDoctorId => ClinicSession.instance.tenantId ?? '';

  Future<void> notifyChanges() async {
    if (!_changeController.isClosed) {
      _changeController.add(null);
    }
  }

  Future<String> upsertSessionNote(
    HomeopathySessionNote note, {
    String syncStatus = 'pending',
    bool pendingDelete = false,
    int? lastSyncedAt,
  }) async {
    final db = await _databaseService.localDatabase;
    final row = Map<String, dynamic>.from(note.toLocalMap());
    row['syncStatus'] = syncStatus;
    row['pendingDelete'] = pendingDelete ? 1 : 0;
    if (lastSyncedAt != null) {
      row['lastSyncedAt'] = lastSyncedAt;
    }

    final count = await db.update(
      'homeopathy_session_notes',
      row,
      where: 'id = ?',
      whereArgs: [note.id],
    );

    if (count == 0) {
      await db.insert(
        'homeopathy_session_notes',
        row,
        conflictAlgorithm: LocalConflictAlgorithm.replace,
      );
    }

    await notifyChanges();
    return note.id;
  }

  /// Every session note for this patient, most recent visit first — the
  /// session history shown on the patient's homeopathy timeline.
  Future<List<HomeopathySessionNote>> getSessionHistory(
    String patientId,
  ) async {
    final doctorId = _currentDoctorId;
    final db = await _databaseService.localDatabase;

    final rows = await db.query(
      'homeopathy_session_notes',
      where:
          'patientId = ? AND (doctorId = ? OR doctorId = "") AND pendingDelete = 0',
      whereArgs: [patientId, doctorId],
      orderBy: 'sessionDate DESC, createdAt DESC',
    );

    return rows.map((r) => HomeopathySessionNote.fromMap(r)).toList();
  }

  Future<HomeopathySessionNote?> getSessionNote(String id) async {
    final db = await _databaseService.localDatabase;
    final rows = await db.query(
      'homeopathy_session_notes',
      where: 'id = ? AND pendingDelete = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return HomeopathySessionNote.fromMap(rows.first);
  }

  Future<void> deleteSessionNote(String id) async {
    final db = await _databaseService.localDatabase;
    await db.update(
      'homeopathy_session_notes',
      {
        'pendingDelete': 1,
        'syncStatus': 'pending',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await notifyChanges();
  }
}
