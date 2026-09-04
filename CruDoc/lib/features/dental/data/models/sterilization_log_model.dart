import 'package:cloud_firestore/cloud_firestore.dart';

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
    this.syncStatus = 'synced',
    this.pendingDelete = false,
    this.lastSyncedAt,
  });

  factory SterilizationLogModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return SterilizationLogModel.fromJson(data, id: doc.id);
  }

  factory SterilizationLogModel.fromJson(
    Map<String, dynamic> map, {
    String? id,
  }) {
    return SterilizationLogModel(
      id: id ?? map['id'] as String? ?? '',
      doctorId: map['doctorId'] as String? ?? '',
      cycleDate: _toDate(map['cycleDate']) ?? DateTime.now(),
      operatorName: map['operatorName'] as String? ?? '',
      loadDescription: map['loadDescription'] as String? ?? '',
      result: map['result'] as String? ?? 'pass',
      notes: map['notes'] as String? ?? '',
      isDeleted: map['isDeleted'] as bool? ?? false,
      createdAt: _toDate(map['createdAt']) ?? DateTime.now(),
      updatedAt: _toDate(map['updatedAt']) ?? DateTime.now(),
      syncStatus: map['syncStatus'] as String? ?? 'synced',
      pendingDelete: map['pendingDelete'] as bool? ?? false,
      lastSyncedAt: _toDate(map['lastSyncedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'doctorId': doctorId,
      'cycleDate': Timestamp.fromDate(cycleDate),
      'operatorName': operatorName,
      'loadDescription': loadDescription,
      'result': result,
      'notes': notes,
      'isDeleted': isDeleted,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'syncStatus': syncStatus,
      'pendingDelete': pendingDelete,
      'lastSyncedAt': lastSyncedAt != null ? Timestamp.fromDate(lastSyncedAt!) : null,
    };
  }

  /// SQLite-shaped map representation (timestamps as millisecondsSinceEpoch)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'doctorId': doctorId,
      'cycleDate': cycleDate.millisecondsSinceEpoch,
      'operatorName': operatorName,
      'loadDescription': loadDescription,
      'result': result,
      'notes': notes,
      'isDeleted': isDeleted ? 1 : 0,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'syncStatus': syncStatus,
      'pendingDelete': pendingDelete ? 1 : 0,
      'lastSyncedAt': lastSyncedAt?.millisecondsSinceEpoch,
    };
  }

  factory SterilizationLogModel.fromMap(Map<String, dynamic> map) {
    return SterilizationLogModel(
      id: map['id'] as String? ?? '',
      doctorId: map['doctorId'] as String? ?? '',
      cycleDate: _toDate(map['cycleDate']) ?? DateTime.now(),
      operatorName: map['operatorName'] as String? ?? '',
      loadDescription: map['loadDescription'] as String? ?? '',
      result: map['result'] as String? ?? 'pass',
      notes: map['notes'] as String? ?? '',
      isDeleted: map['isDeleted'] == 1 || map['isDeleted'] == true,
      createdAt: _toDate(map['createdAt']) ?? DateTime.now(),
      updatedAt: _toDate(map['updatedAt']) ?? DateTime.now(),
      syncStatus: map['syncStatus'] as String? ?? 'synced',
      pendingDelete: map['pendingDelete'] == 1 || map['pendingDelete'] == true,
      lastSyncedAt: _toDate(map['lastSyncedAt']),
    );
  }

  SterilizationLogModel copyWith({
    String? id,
    String? doctorId,
    DateTime? cycleDate,
    String? operatorName,
    String? loadDescription,
    String? result,
    String? notes,
    bool? isDeleted,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
    bool? pendingDelete,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
  }) {
    return SterilizationLogModel(
      id: id ?? this.id,
      doctorId: doctorId ?? this.doctorId,
      cycleDate: cycleDate ?? this.cycleDate,
      operatorName: operatorName ?? this.operatorName,
      loadDescription: loadDescription ?? this.loadDescription,
      result: result ?? this.result,
      notes: notes ?? this.notes,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      pendingDelete: pendingDelete ?? this.pendingDelete,
      lastSyncedAt: clearLastSyncedAt ? null : (lastSyncedAt ?? this.lastSyncedAt),
    );
  }

  static DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SterilizationLogModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          doctorId == other.doctorId &&
          cycleDate == other.cycleDate &&
          operatorName == other.operatorName &&
          loadDescription == other.loadDescription &&
          result == other.result &&
          notes == other.notes &&
          isDeleted == other.isDeleted &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          syncStatus == other.syncStatus &&
          pendingDelete == other.pendingDelete &&
          lastSyncedAt == other.lastSyncedAt;

  @override
  int get hashCode => Object.hash(
        id,
        doctorId,
        cycleDate,
        operatorName,
        loadDescription,
        result,
        notes,
        isDeleted,
        createdAt,
        updatedAt,
        syncStatus,
        pendingDelete,
        lastSyncedAt,
      );

  @override
  String toString() {
    return 'SterilizationLogModel(id: $id, cycleDate: $cycleDate, result: $result, operator: $operatorName)';
  }
}
