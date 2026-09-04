import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/database/local_database.dart';
import '../../../../core/services/local_database_service.dart';
import '../models/dental_procedure_catalog_model.dart';
import '../models/tooth_chart_entry_model.dart';
import '../models/dental_procedure_log_model.dart';
import '../models/sterilization_log_model.dart';
import '../models/treatment_plan_line_item_model.dart';

/// Local-first Data Repository for Dental Specialization features.
///
/// Handles SQLite caching, sync status updates, and optional Firestore sync.
class DentalRepository {
  final LocalDatabaseService _localDbService;
  final FirebaseFirestore? _firestore;

  DentalRepository({
    LocalDatabaseService? localDbService,
    FirebaseFirestore? firestore,
  })  : _localDbService = localDbService ?? LocalDatabaseService.instance,
        _firestore = firestore;

  FirebaseFirestore? get firestore => _firestore;

  // ---------------------------------------------------------------------------
  // DENTAL PROCEDURE CATALOG
  // ---------------------------------------------------------------------------

  Future<List<DentalProcedureCatalogModel>> getProcedureCatalog(
    String doctorId, {
    bool includeArchived = false,
  }) async {
    final db = await _localDbService.localDatabase;
    final whereClause = includeArchived
        ? 'doctorId = ? AND isDeleted = 0'
        : 'doctorId = ? AND isDeleted = 0 AND isActive = 1';
    final rows = await db.query(
      'dental_procedure_catalog',
      where: whereClause,
      whereArgs: [doctorId],
      orderBy: 'name ASC',
    );
    return rows.map((r) => DentalProcedureCatalogModel.fromMap(r)).toList();
  }

  Future<void> saveCatalogItem(DentalProcedureCatalogModel item) async {
    final db = await _localDbService.localDatabase;
    await db.insert(
      'dental_procedure_catalog',
      item.toMap(),
      conflictAlgorithm: LocalConflictAlgorithm.replace,
    );
  }

  Future<void> archiveCatalogItem(String id) async {
    final db = await _localDbService.localDatabase;
    await db.update(
      'dental_procedure_catalog',
      {
        'isActive': 0,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'syncStatus': 'pending',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> restoreCatalogItem(String id) async {
    final db = await _localDbService.localDatabase;
    await db.update(
      'dental_procedure_catalog',
      {
        'isActive': 1,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'syncStatus': 'pending',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------------------
  // TOOTH CHART ENTRIES
  // ---------------------------------------------------------------------------

  Future<List<ToothChartEntryModel>> getToothChartForPatient(String patientId) async {
    final db = await _localDbService.localDatabase;
    final rows = await db.query(
      'tooth_chart_entries',
      where: 'patientId = ? AND isDeleted = 0',
      whereArgs: [patientId],
      orderBy: 'recordedAt DESC',
    );
    return rows.map((r) => ToothChartEntryModel.fromMap(r)).toList();
  }

  Future<List<ToothChartEntryModel>> getHistoryForTooth(
    String patientId,
    String toothNumber,
  ) async {
    final db = await _localDbService.localDatabase;
    final rows = await db.query(
      'tooth_chart_entries',
      where: 'patientId = ? AND toothNumber = ? AND isDeleted = 0',
      whereArgs: [patientId, toothNumber],
      orderBy: 'recordedAt DESC',
    );
    return rows.map((r) => ToothChartEntryModel.fromMap(r)).toList();
  }

  Future<void> saveToothChartEntry(ToothChartEntryModel entry) async {
    final db = await _localDbService.localDatabase;
    await db.insert(
      'tooth_chart_entries',
      entry.toMap(),
      conflictAlgorithm: LocalConflictAlgorithm.replace,
    );
  }

  // ---------------------------------------------------------------------------
  // PROCEDURE LOG ENTRIES
  // ---------------------------------------------------------------------------

  Future<List<DentalProcedureLogModel>> getProcedureLogsForPatient(String patientId) async {
    final db = await _localDbService.localDatabase;
    final rows = await db.query(
      'procedure_log_entries',
      where: 'patientId = ? AND isDeleted = 0',
      whereArgs: [patientId],
      orderBy: 'performedAt DESC',
    );
    return rows.map((r) => DentalProcedureLogModel.fromMap(r)).toList();
  }

  Future<List<DentalProcedureLogModel>> getProcedureLogsForVisit(String visitId) async {
    final db = await _localDbService.localDatabase;
    final rows = await db.query(
      'procedure_log_entries',
      where: 'visitId = ? AND isDeleted = 0',
      whereArgs: [visitId],
      orderBy: 'performedAt DESC',
    );
    return rows.map((r) => DentalProcedureLogModel.fromMap(r)).toList();
  }

  Future<void> saveProcedureLog(DentalProcedureLogModel log) async {
    final db = await _localDbService.localDatabase;
    await db.insert(
      'procedure_log_entries',
      log.toMap(),
      conflictAlgorithm: LocalConflictAlgorithm.replace,
    );
  }

  Future<void> deleteProcedureLog(String id) async {
    final db = await _localDbService.localDatabase;
    await db.update(
      'procedure_log_entries',
      {
        'isDeleted': 1,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'syncStatus': 'pending',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------------------
  // TREATMENT PLAN LINE ITEMS
  // ---------------------------------------------------------------------------

  Future<List<TreatmentPlanLineItemModel>> getTreatmentPlanLineItems(
    String patientId, {
    String? treatmentPlanId,
  }) async {
    final db = await _localDbService.localDatabase;
    final whereArgs = <dynamic>[patientId];
    var whereClause = 'patientId = ? AND isDeleted = 0';

    if (treatmentPlanId != null && treatmentPlanId.isNotEmpty) {
      whereClause += ' AND treatmentPlanId = ?';
      whereArgs.add(treatmentPlanId);
    }

    final rows = await db.query(
      'treatment_plan_line_items',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'sequence ASC, createdAt ASC',
    );
    return rows.map((r) => TreatmentPlanLineItemModel.fromMap(r)).toList();
  }

  Future<void> saveTreatmentPlanLineItem(TreatmentPlanLineItemModel item) async {
    final db = await _localDbService.localDatabase;
    await db.insert(
      'treatment_plan_line_items',
      item.toMap(),
      conflictAlgorithm: LocalConflictAlgorithm.replace,
    );
  }

  Future<void> updateTreatmentPlanLineItemStatus(String id, String newStatus) async {
    final db = await _localDbService.localDatabase;
    await db.update(
      'treatment_plan_line_items',
      {
        'status': newStatus,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'syncStatus': 'pending',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteTreatmentPlanLineItem(String id) async {
    final db = await _localDbService.localDatabase;
    await db.update(
      'treatment_plan_line_items',
      {
        'isDeleted': 1,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'syncStatus': 'pending',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------------------
  // STERILIZATION LOG ENTRIES
  // ---------------------------------------------------------------------------

  Future<List<SterilizationLogModel>> getSterilizationLogs(String doctorId) async {
    final db = await _localDbService.localDatabase;
    final rows = await db.query(
      'sterilization_log_entries',
      where: 'doctorId = ? AND isDeleted = 0',
      whereArgs: [doctorId],
      orderBy: 'cycleDate DESC',
    );
    return rows.map((r) => SterilizationLogModel.fromMap(r)).toList();
  }

  Future<void> saveSterilizationLog(SterilizationLogModel log) async {
    final db = await _localDbService.localDatabase;
    await db.insert(
      'sterilization_log_entries',
      log.toMap(),
      conflictAlgorithm: LocalConflictAlgorithm.replace,
    );
  }
}
