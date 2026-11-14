import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show listEquals;

/// Result status of an autoclave sterilization cycle.
enum SterilizationResult {
  pass,
  fail,
  incomplete;

  static SterilizationResult fromString(String? val) {
    if (val == null) return SterilizationResult.pass;
    final lower = val.toLowerCase().trim();
    if (lower == 'fail') return SterilizationResult.fail;
    if (lower == 'incomplete') return SterilizationResult.incomplete;
    return SterilizationResult.pass;
  }

  String get code => name;

  String get label {
    switch (this) {
      case SterilizationResult.pass:
        return 'Pass';
      case SterilizationResult.fail:
        return 'Fail';
      case SterilizationResult.incomplete:
        return 'Incomplete';
    }
  }
}

/// Clinic-level Sterilization Log model for autoclave compliance records.
///
/// Explicitly NOT patient-linked (sole scope key is [doctorId]).
/// Analogue: [MedicineModel] (doctor-owned reference data).
/// [result] is 'pass' or 'fail' (older rows may say 'incomplete').
class SterilizationLogModel {
  final String id;
  final String doctorId;
  final DateTime cycleDate;
  final String operatorName;
  final String loadDescription;
  final String result;
  final String notes;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Manual-log fields (all optional so older rows still read).
  final String autoclaveName;
  final int cycleNumber;
  final String program;
  final int? temperatureC;
  final int? pressureKpa;
  final int? holdMinutes;

  /// not_used | pass | fail
  final String chemicalIndicator;

  /// not_used | pass | fail | pending
  final String biologicalIndicator;

  /// Why the result differs from the indicators.
  final String overrideReason;
  final String createdBy;
  final DateTime? editedAt;
  final String editedBy;

  /// Dated notes added after the day of the cycle.
  final String correctionNote;

  /// Sync triad fields
  final String syncStatus;
  final bool pendingDelete;
  final DateTime? lastSyncedAt;

  const SterilizationLogModel({
    required this.id,
    required this.doctorId,
    required this.cycleDate,
    required this.operatorName,
    this.loadDescription = '',
    this.result = 'pass',
    this.notes = '',
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
    this.autoclaveName = '',
    this.cycleNumber = 0,
    this.program = '',
    this.temperatureC,
    this.pressureKpa,
    this.holdMinutes,
    this.chemicalIndicator = 'not_used',
    this.biologicalIndicator = 'not_used',
    this.overrideReason = '',
    this.createdBy = '',
    this.editedAt,
    this.editedBy = '',
    this.correctionNote = '',
    this.syncStatus = 'synced',
    this.pendingDelete = false,
    this.lastSyncedAt,
  });

  /// Passed, but the spore test has not come back yet.
  bool get biPending =>
      biologicalIndicator == 'pending' &&
      SterilizationResult.fromString(result) == SterilizationResult.pass;

  factory SterilizationLogModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return SterilizationLogModel.fromJson(data, id: doc.id);
  }

  factory SterilizationLogModel.fromJson(
    Map<String, dynamic> map, {
    String? id,
  }) => _read(map, id: id ?? map['id'] as String? ?? '');

  factory SterilizationLogModel.fromMap(Map<String, dynamic> map) =>
      _read(map, id: map['id'] as String? ?? '');

  static SterilizationLogModel _read(
    Map<String, dynamic> map, {
    required String id,
  }) {
    bool flag(Object? v) => v == 1 || v == true;
    int? whole(Object? v) => v is num ? v.toInt() : null;
    String str(String k, [String d = '']) => map[k] as String? ?? d;
    return SterilizationLogModel(
      id: id,
      doctorId: str('doctorId'),
      cycleDate: _toDate(map['cycleDate']) ?? DateTime.now(),
      operatorName: str('operatorName'),
      loadDescription: str('loadDescription'),
      result: str('result', 'pass'),
      notes: str('notes'),
      isDeleted: flag(map['isDeleted']),
      createdAt: _toDate(map['createdAt']) ?? DateTime.now(),
      updatedAt: _toDate(map['updatedAt']) ?? DateTime.now(),
      autoclaveName: str('autoclaveName'),
      cycleNumber: whole(map['cycleNumber']) ?? 0,
      program: str('program'),
      temperatureC: whole(map['temperatureC']),
      pressureKpa: whole(map['pressureKpa']),
      holdMinutes: whole(map['holdMinutes']),
      chemicalIndicator: str('chemicalIndicator', 'not_used'),
      biologicalIndicator: str('biologicalIndicator', 'not_used'),
      overrideReason: str('overrideReason'),
      createdBy: str('createdBy'),
      editedAt: _toDate(map['editedAt']),
      editedBy: str('editedBy'),
      correctionNote: str('correctionNote'),
      syncStatus: str('syncStatus', 'synced'),
      pendingDelete: flag(map['pendingDelete']),
      lastSyncedAt: _toDate(map['lastSyncedAt']),
    );
  }

  Map<String, dynamic> _fields({required bool sql}) {
    Object? t(DateTime? d) => d == null
        ? null
        : (sql ? d.millisecondsSinceEpoch : Timestamp.fromDate(d));
    return {
      'id': id,
      'doctorId': doctorId,
      'cycleDate': t(cycleDate),
      'operatorName': operatorName,
      'loadDescription': loadDescription,
      'result': result,
      'notes': notes,
      'isDeleted': sql ? (isDeleted ? 1 : 0) : isDeleted,
      'createdAt': t(createdAt),
      'updatedAt': t(updatedAt),
      'autoclaveName': autoclaveName,
      'cycleNumber': cycleNumber,
      'program': program,
      'temperatureC': temperatureC,
      'pressureKpa': pressureKpa,
      'holdMinutes': holdMinutes,
      'chemicalIndicator': chemicalIndicator,
      'biologicalIndicator': biologicalIndicator,
      'overrideReason': overrideReason,
      'createdBy': createdBy,
      'editedAt': t(editedAt),
      'editedBy': editedBy,
      'correctionNote': correctionNote,
      'syncStatus': syncStatus,
      'pendingDelete': sql ? (pendingDelete ? 1 : 0) : pendingDelete,
      'lastSyncedAt': t(lastSyncedAt),
    };
  }

  Map<String, dynamic> toJson() => _fields(sql: false);

  /// SQLite-shaped map representation (timestamps as millisecondsSinceEpoch)
  Map<String, dynamic> toMap() => _fields(sql: true);

  SterilizationLogModel copyWith({
    String? result,
    String? notes,
    bool? isDeleted,
    DateTime? updatedAt,
    String? syncStatus,
    bool? pendingDelete,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
  }) {
    return SterilizationLogModel(
      id: id,
      doctorId: doctorId,
      cycleDate: cycleDate,
      operatorName: operatorName,
      loadDescription: loadDescription,
      result: result ?? this.result,
      notes: notes ?? this.notes,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      autoclaveName: autoclaveName,
      cycleNumber: cycleNumber,
      program: program,
      temperatureC: temperatureC,
      pressureKpa: pressureKpa,
      holdMinutes: holdMinutes,
      chemicalIndicator: chemicalIndicator,
      biologicalIndicator: biologicalIndicator,
      overrideReason: overrideReason,
      createdBy: createdBy,
      editedAt: editedAt,
      editedBy: editedBy,
      correctionNote: correctionNote,
      syncStatus: syncStatus ?? this.syncStatus,
      pendingDelete: pendingDelete ?? this.pendingDelete,
      lastSyncedAt: clearLastSyncedAt
          ? null
          : (lastSyncedAt ?? this.lastSyncedAt),
    );
  }

  static DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return null;
  }

  List<Object?> get _props => _fields(sql: true).values.toList();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SterilizationLogModel &&
          runtimeType == other.runtimeType &&
          listEquals(_props, other._props);

  @override
  int get hashCode => Object.hashAll(_props);

  @override
  String toString() {
    return 'SterilizationLogModel(id: $id, cycleDate: $cycleDate, result: $result, operator: $operatorName)';
  }
}
