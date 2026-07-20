import 'dart:async';

import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/core/utils/search_normalisation.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite-backed patient data source.
///
/// This is introduced in Phase 2 so repositories can read from SQLite while
/// Firestore remains a secondary write target until the sync engine lands.
class PatientLocalService {
  factory PatientLocalService({LocalDatabaseService? databaseService}) {
    if (databaseService != null) {
      return PatientLocalService._(databaseService);
    }
    return instance;
  }

  PatientLocalService._(this._databaseService);

  static final PatientLocalService instance = PatientLocalService._(
    LocalDatabaseService.instance,
  );

  PatientLocalService.withDatabase(this._databaseService);

  final LocalDatabaseService _databaseService;
  final StreamController<List<Patient>> _patientsController =
      StreamController<List<Patient>>.broadcast();

  Future<String> upsertPatient(
    Patient patient, {
    String syncStatus = 'pending',
    bool pendingDelete = false,
    int? lastSyncedAt,
  }) async {
    final db = await _databaseService.database;
    await db.insert(
      'patients',
      _toRow(
        patient,
        syncStatus: syncStatus,
        pendingDelete: pendingDelete,
        lastSyncedAt: lastSyncedAt,
      ),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _emitPatients();
    return patient.id;
  }

  Future<void> updatePatient(
    String patientId,
    Map<String, dynamic> data, {
    String syncStatus = 'pending',
    bool? pendingDelete,
    int? lastSyncedAt,
  }) async {
    final db = await _databaseService.database;
    final row = _updateDataToRow(data)
      ..['syncStatus'] = syncStatus
      ..['updatedAt'] = _dateTimeToMillis(
        data['updatedAt'] is DateTime
            ? data['updatedAt'] as DateTime
            : DateTime.now(),
      );

    if (pendingDelete != null) {
      row['pendingDelete'] = pendingDelete ? 1 : 0;
    }
    if (lastSyncedAt != null) {
      row['lastSyncedAt'] = lastSyncedAt;
    }

    await db.update('patients', row, where: 'id = ?', whereArgs: [patientId]);
    await _emitPatients();
  }

  Future<void> softDeletePatient(String patientId) async {
    await updatePatient(patientId, {
      'isArchived': true,
      'isActive': false,
      'updatedAt': DateTime.now(),
    }, pendingDelete: true);
  }

  Future<Patient?> getPatient(String patientId) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      'patients',
      where: 'id = ? AND isActive = 1',
      whereArgs: [patientId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Stream<List<Patient>> watchPatients() {
    Future<void>.microtask(_emitPatients);
    return _patientsController.stream;
  }

  Future<List<Patient>> searchPatients(
    String rawQuery, {
    bool includeArchived = true,
  }) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return [];

    final results = <String, Patient>{};
    if (!query.contains('/')) {
      final byId = await getPatient(query);
      if (byId != null && (includeArchived || !byId.isArchived)) {
        results[byId.id] = byId;
      }
    }

    final db = await _databaseService.database;
    final rows = await db.query(
      'patients',
      where: includeArchived
          ? 'isActive = 1'
          : 'isActive = 1 AND isArchived = 0',
      orderBy: 'createdAt DESC',
    );

    final normalizedQuery = normalizeForSearch(query);
    final normalizedPhoneQuery = normalizePhoneDigits(query);
    final canMatchPhone = normalizedPhoneQuery.length >= 1;

    for (final row in rows) {
      final patient = _fromRow(row);
      if (results.containsKey(patient.id)) continue;

      final nameMatch = normalizeForSearch(
        patient.fullName,
      ).contains(normalizedQuery);
      final phoneMatch =
          canMatchPhone &&
          normalizePhoneDigits(patient.phone).contains(normalizedPhoneQuery);

      if (nameMatch || phoneMatch) {
        results[patient.id] = patient;
      }
    }

    return results.values.toList();
  }

  Future<void> markSynced(String patientId, {DateTime? syncedAt}) async {
    final db = await _databaseService.database;
    await db.update(
      'patients',
      {
        'syncStatus': 'synced',
        'pendingDelete': 0,
        'lastSyncedAt': _dateTimeToMillis(syncedAt ?? DateTime.now()),
      },
      where: 'id = ?',
      whereArgs: [patientId],
    );
    await _emitPatients();
  }

  Future<void> _emitPatients() async {
    if (_patientsController.isClosed) return;

    final db = await _databaseService.database;
    final rows = await db.query(
      'patients',
      where: 'isActive = 1 AND isArchived = 0',
      orderBy: 'createdAt DESC',
    );
    if (!_patientsController.isClosed) {
      _patientsController.add(rows.map(_fromRow).toList());
    }
  }

  Map<String, dynamic> _toRow(
    Patient patient, {
    required String syncStatus,
    required bool pendingDelete,
    int? lastSyncedAt,
  }) {
    return {
      'id': patient.id,
      'firstName': patient.firstName,
      'lastName': patient.lastName,
      'phone': patient.phone,
      'gender': patient.gender,
      'dateOfBirth': _dateTimeToMillis(patient.dateOfBirth),
      'diagnosis': Patient.diagnosisToStored(patient.diagnosis),
      'notes': patient.notes,
      'packageBalance': patient.packageBalance,
      'isArchived': patient.isArchived ? 1 : 0,
      'isActive': pendingDelete ? 0 : 1,
      'createdAt': _dateTimeToMillis(patient.createdAt),
      'updatedAt': _dateTimeToMillis(patient.updatedAt),
      'syncStatus': syncStatus,
      'pendingDelete': pendingDelete ? 1 : 0,
      'lastSyncedAt': lastSyncedAt,
    };
  }

  Map<String, dynamic> _updateDataToRow(Map<String, dynamic> data) {
    final row = <String, dynamic>{};
    for (final entry in data.entries) {
      switch (entry.key) {
        case 'dateOfBirth':
        case 'createdAt':
        case 'updatedAt':
          if (entry.value is DateTime) {
            row[entry.key] = _dateTimeToMillis(entry.value as DateTime);
          } else if (entry.value is int) {
            row[entry.key] = entry.value;
          }
          break;
        case 'isArchived':
        case 'isActive':
          if (entry.value is bool) {
            row[entry.key] = entry.value as bool ? 1 : 0;
          } else if (entry.value is int) {
            row[entry.key] = entry.value;
          }
          break;
        case 'firstName':
        case 'lastName':
        case 'phone':
        case 'gender':
        case 'notes':
          row[entry.key] = entry.value;
          break;
        case 'diagnosis':
          row[entry.key] = entry.value is List
              ? Patient.diagnosisToStored(
                  (entry.value as List).map((e) => e.toString()).toList(),
                )
              : entry.value;
          break;
        case 'packageBalance':
          row[entry.key] = (entry.value as num).toDouble();
          break;
      }
    }
    return row;
  }

  Patient _fromRow(Map<String, Object?> row) {
    return Patient(
      id: row['id'] as String,
      firstName: row['firstName'] as String? ?? '',
      lastName: row['lastName'] as String? ?? '',
      phone: row['phone'] as String? ?? '',
      gender: row['gender'] as String? ?? '',
      dateOfBirth: _millisToDateTime(row['dateOfBirth']),
      diagnosis: Patient.diagnosisFromStored(row['diagnosis'] as String?),
      notes: row['notes'] as String? ?? '',
      packageBalance: (row['packageBalance'] as num?)?.toDouble() ?? 0,
      isArchived: row['isArchived'] == 1,
      createdAt: _millisToDateTime(row['createdAt']),
      updatedAt: _millisToDateTime(row['updatedAt']),
    );
  }

  int _dateTimeToMillis(DateTime value) => value.millisecondsSinceEpoch;

  DateTime _millisToDateTime(Object? value) {
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return DateTime.now();
  }
}