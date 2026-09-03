import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:doctor_management_app/core/database/local_database.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_case_sheet.dart';

/// SQLite DAO for homeopathic case sheets, strictly scoped to the active doctor.
class HomeopathyLocalService {
  factory HomeopathyLocalService({LocalDatabaseService? databaseService}) {
    if (databaseService != null) {
      return HomeopathyLocalService._(databaseService);
    }
    return instance;
  }

  HomeopathyLocalService._(this._databaseService);

  static final HomeopathyLocalService instance =
      HomeopathyLocalService._(LocalDatabaseService.instance);

  final LocalDatabaseService _databaseService;
  final StreamController<void> _changeController =
      StreamController<void>.broadcast();

  Stream<void> get changes => _changeController.stream;

  String get _currentDoctorId => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> notifyChanges() async {
    if (!_changeController.isClosed) {
      _changeController.add(null);
    }
  }

  Future<String> upsertCaseSheet(
    HomeopathyCaseSheet caseSheet, {
    String syncStatus = 'pending',
    bool pendingDelete = false,
    int? lastSyncedAt,
  }) async {
    final db = await _databaseService.localDatabase;
    final row = Map<String, dynamic>.from(caseSheet.toMap());
    row['syncStatus'] = syncStatus;
    row['pendingDelete'] = pendingDelete ? 1 : 0;
    if (lastSyncedAt != null) {
      row['lastSyncedAt'] = lastSyncedAt;
    }

    final count = await db.update(
      'homeopathy_case_sheets',
      row,
      where: 'id = ?',
      whereArgs: [caseSheet.id],
    );

    if (count == 0) {
      await db.insert(
        'homeopathy_case_sheets',
        row,
        conflictAlgorithm: LocalConflictAlgorithm.replace,
      );
    }

    await notifyChanges();
    return caseSheet.id;
  }

  Future<HomeopathyCaseSheet?> getCaseSheetForPatient(String patientId) async {
    final doctorId = _currentDoctorId;
    final db = await _databaseService.localDatabase;

    final rows = await db.query(
      'homeopathy_case_sheets',
      where: 'patientId = ? AND (doctorId = ? OR doctorId = "") AND pendingDelete = 0',
      whereArgs: [patientId, doctorId],
      orderBy: 'updatedAt DESC',
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return HomeopathyCaseSheet.fromMap(rows.first);
  }

  Future<List<HomeopathyCaseSheet>> getAllCaseSheetsForPatient(
      String patientId) async {
    final doctorId = _currentDoctorId;
    final db = await _databaseService.localDatabase;

    final rows = await db.query(
      'homeopathy_case_sheets',
      where: 'patientId = ? AND (doctorId = ? OR doctorId = "") AND pendingDelete = 0',
      whereArgs: [patientId, doctorId],
      orderBy: 'caseDate DESC, updatedAt DESC',
    );

    return rows.map((r) => HomeopathyCaseSheet.fromMap(r)).toList();
  }

  Future<void> deleteCaseSheet(String id) async {
    final db = await _databaseService.localDatabase;
    await db.update(
      'homeopathy_case_sheets',
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
