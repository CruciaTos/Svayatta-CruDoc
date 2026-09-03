import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/database/local_database.dart';
import '../../../../core/services/local_database_service.dart';
import '../../../../core/services/firestore_sync_service.dart';
import '../models/medical_document.dart';

/// SQLite-backed medical documents data source with local-first offline support.
class MedicalDocumentLocalService {
  MedicalDocumentLocalService._(this._databaseService);

  static final MedicalDocumentLocalService instance = MedicalDocumentLocalService._(
    LocalDatabaseService.instance,
  );

  final LocalDatabaseService _databaseService;
  final StreamController<void> _documentsChangedController =
      StreamController<void>.broadcast();

  String get _currentDoctorId => FirebaseAuth.instance.currentUser?.uid ?? '';

  Stream<void> get onDocumentsChanged => _documentsChangedController.stream;

  Future<void> notifyDocumentsChanged() async {
    if (!_documentsChangedController.isClosed) {
      _documentsChangedController.add(null);
    }
  }

  Future<void> saveDocument(MedicalDocument doc) async {
    final db = await _databaseService.localDatabase;
    final now = DateTime.now();
    final toSave = doc.copyWith(
      syncStatus: 'pending',
      updatedAt: now,
    );

    await db.insert(
      'medical_documents',
      toSave.toLocalMap(),
      conflictAlgorithm: LocalConflictAlgorithm.replace,
    );

    notifyDocumentsChanged();
    FirestoreSyncService.instance.triggerPostWriteSync();
  }

  Future<List<MedicalDocument>> getDocumentsForPatient(String patientId) async {
    final db = await _databaseService.localDatabase;
    final doctorId = _currentDoctorId;
    final rows = await db.query(
      'medical_documents',
      where: 'patientId = ? AND doctorId = ? AND isDeleted = 0',
      whereArgs: [patientId, doctorId],
      orderBy: 'createdAt DESC',
    );
    return rows.map((r) => MedicalDocument.fromLocalMap(r)).toList();
  }

  Future<void> softDeleteDocument(String documentId) async {
    final db = await _databaseService.localDatabase;
    final doctorId = _currentDoctorId;
    await db.update(
      'medical_documents',
      {
        'isDeleted': 1,
        'syncStatus': 'pending',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ? AND doctorId = ?',
      whereArgs: [documentId, doctorId],
    );

    notifyDocumentsChanged();
    FirestoreSyncService.instance.triggerPostWriteSync();
  }
}
