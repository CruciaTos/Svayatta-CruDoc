import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/services/field_cipher.dart';

/// Status of a dental procedure log entry.
enum DentalProcedureStatus {
  planned,
  inProgress,
  completed;

  static DentalProcedureStatus fromString(String? val) {
    if (val == null) return DentalProcedureStatus.completed;
    final lower = val.toLowerCase().trim();
    if (lower == 'planned') return DentalProcedureStatus.planned;
    if (lower == 'inprogress' || lower == 'in_progress') {
      return DentalProcedureStatus.inProgress;
    }
    return DentalProcedureStatus.completed;
  }

  String get code {
    switch (this) {
      case DentalProcedureStatus.planned:
        return 'planned';
      case DentalProcedureStatus.inProgress:
        return 'inProgress';
      case DentalProcedureStatus.completed:
        return 'completed';
    }
  }

  String get label {
    switch (this) {
      case DentalProcedureStatus.planned:
        return 'Planned';
      case DentalProcedureStatus.inProgress:
        return 'In Progress';
      case DentalProcedureStatus.completed:
        return 'Completed';
    }
  }
}

/// Patient-linked Dental Procedure Log model.
///
/// Records a single procedure performed for a patient (optionally linked to a visit,
/// catalog entry, or zero/one/many teeth).
/// Plain hand-written model. [notes] and [materials] are encrypted via [FieldCipher].
class DentalProcedureLogModel {
  final String id;
  final String doctorId;
  final String patientId;
  final String? visitId;
  final String? procedureCatalogId;
  final String procedureName;
  final List<String> toothNumbers;
  final String notationSystem;
  final String status;
  final String notes;
  final String? materials;
  final DateTime performedAt;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Sync triad fields
  final String syncStatus;
  final bool pendingDelete;
  final DateTime? lastSyncedAt;

  const DentalProcedureLogModel({
    required this.id,
    required this.doctorId,
    required this.patientId,
    this.visitId,
    this.procedureCatalogId,
    required this.procedureName,
    this.toothNumbers = const [],
    this.notationSystem = 'fdi',
    this.status = 'completed',
    this.notes = '',
    this.materials,
    required this.performedAt,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 'synced',
    this.pendingDelete = false,
    this.lastSyncedAt,
  });

  factory DentalProcedureLogModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return DentalProcedureLogModel.fromJson(data, id: doc.id);
  }

  factory DentalProcedureLogModel.fromJson(
    Map<String, dynamic> map, {
    String? id,
  }) {
    final rawNotes = map['notes'] as String? ?? '';
    final rawMaterials = map['materials'] as String?;

    return DentalProcedureLogModel(
      id: id ?? map['id'] as String? ?? '',
      doctorId: map['doctorId'] as String? ?? '',
      patientId: map['patientId'] as String? ?? '',
      visitId: map['visitId'] as String?,
      procedureCatalogId: map['procedureCatalogId'] as String?,
      procedureName: map['procedureName'] as String? ?? '',
      toothNumbers: _parseStringList(map['toothNumbers']),
      notationSystem: map['notationSystem'] as String? ?? 'fdi',
      status: map['status'] as String? ?? 'completed',
      notes: FieldCipher.decrypt(rawNotes),
      materials: rawMaterials != null ? FieldCipher.decrypt(rawMaterials) : null,
      performedAt: _toDate(map['performedAt']) ?? DateTime.now(),
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
      'patientId': patientId,
      'visitId': visitId,
      'procedureCatalogId': procedureCatalogId,
      'procedureName': procedureName,
      'toothNumbers': toothNumbers,
      'notationSystem': notationSystem,
      'status': status,
      'notes': FieldCipher.encrypt(notes),
      'materials': materials != null ? FieldCipher.encrypt(materials!) : null,
      'performedAt': Timestamp.fromDate(performedAt),
      'isDeleted': isDeleted,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'syncStatus': syncStatus,
      'pendingDelete': pendingDelete,
      'lastSyncedAt': lastSyncedAt != null ? Timestamp.fromDate(lastSyncedAt!) : null,
    };
  }

  /// SQLite-shaped map representation (timestamps as millisecondsSinceEpoch, toothNumbers as JSON string)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'doctorId': doctorId,
      'patientId': patientId,
      'visitId': visitId,
      'procedureCatalogId': procedureCatalogId,
      'procedureName': procedureName,
      'toothNumbers': jsonEncode(toothNumbers),
      'notationSystem': notationSystem,
      'status': status,
      'notes': FieldCipher.encrypt(notes),
      'materials': materials != null ? FieldCipher.encrypt(materials!) : null,
      'performedAt': performedAt.millisecondsSinceEpoch,
      'isDeleted': isDeleted ? 1 : 0,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'syncStatus': syncStatus,
      'pendingDelete': pendingDelete ? 1 : 0,
      'lastSyncedAt': lastSyncedAt?.millisecondsSinceEpoch,
    };
  }

  factory DentalProcedureLogModel.fromMap(Map<String, dynamic> map) {
    final rawNotes = map['notes'] as String? ?? '';
    final rawMaterials = map['materials'] as String?;

    return DentalProcedureLogModel(
      id: map['id'] as String? ?? '',
      doctorId: map['doctorId'] as String? ?? '',
      patientId: map['patientId'] as String? ?? '',
      visitId: map['visitId'] as String?,
      procedureCatalogId: map['procedureCatalogId'] as String?,
      procedureName: map['procedureName'] as String? ?? '',
      toothNumbers: _parseStringList(map['toothNumbers']),
      notationSystem: map['notationSystem'] as String? ?? 'fdi',
      status: map['status'] as String? ?? 'completed',
      notes: FieldCipher.decrypt(rawNotes),
      materials: rawMaterials != null ? FieldCipher.decrypt(rawMaterials) : null,
      performedAt: _toDate(map['performedAt']) ?? DateTime.now(),
      isDeleted: map['isDeleted'] == 1 || map['isDeleted'] == true,
      createdAt: _toDate(map['createdAt']) ?? DateTime.now(),
      updatedAt: _toDate(map['updatedAt']) ?? DateTime.now(),
      syncStatus: map['syncStatus'] as String? ?? 'synced',
      pendingDelete: map['pendingDelete'] == 1 || map['pendingDelete'] == true,
      lastSyncedAt: _toDate(map['lastSyncedAt']),
    );
  }

  DentalProcedureLogModel copyWith({
    String? id,
    String? doctorId,
    String? patientId,
    String? visitId,
    bool clearVisitId = false,
    String? procedureCatalogId,
    bool clearProcedureCatalogId = false,
    String? procedureName,
    List<String>? toothNumbers,
    String? notationSystem,
    String? status,
    String? notes,
    String? materials,
    bool clearMaterials = false,
    DateTime? performedAt,
    bool? isDeleted,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
    bool? pendingDelete,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
  }) {
    return DentalProcedureLogModel(
      id: id ?? this.id,
      doctorId: doctorId ?? this.doctorId,
      patientId: patientId ?? this.patientId,
      visitId: clearVisitId ? null : (visitId ?? this.visitId),
      procedureCatalogId:
          clearProcedureCatalogId ? null : (procedureCatalogId ?? this.procedureCatalogId),
      procedureName: procedureName ?? this.procedureName,
      toothNumbers: toothNumbers ?? this.toothNumbers,
      notationSystem: notationSystem ?? this.notationSystem,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      materials: clearMaterials ? null : (materials ?? this.materials),
      performedAt: performedAt ?? this.performedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      pendingDelete: pendingDelete ?? this.pendingDelete,
      lastSyncedAt: clearLastSyncedAt ? null : (lastSyncedAt ?? this.lastSyncedAt),
    );
  }

  static List<String> _parseStringList(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is String) {
      if (raw.trim().isEmpty) return [];
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.map((e) => e.toString()).toList();
      } catch (_) {
        return raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
    }
    return [];
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
      other is DentalProcedureLogModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          doctorId == other.doctorId &&
          patientId == other.patientId &&
          visitId == other.visitId &&
          procedureCatalogId == other.procedureCatalogId &&
          procedureName == other.procedureName &&
          _listEquals(toothNumbers, other.toothNumbers) &&
          notationSystem == other.notationSystem &&
          status == other.status &&
          notes == other.notes &&
          materials == other.materials &&
          performedAt == other.performedAt &&
          isDeleted == other.isDeleted &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          syncStatus == other.syncStatus &&
          pendingDelete == other.pendingDelete &&
          lastSyncedAt == other.lastSyncedAt;

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        doctorId,
        patientId,
        visitId,
        procedureCatalogId,
        procedureName,
        Object.hashAll(toothNumbers),
        notationSystem,
        status,
        notes,
        materials,
        performedAt,
        isDeleted,
        createdAt,
        updatedAt,
        syncStatus,
        pendingDelete,
        lastSyncedAt,
      ]);

  @override
  String toString() {
    return 'DentalProcedureLogModel(id: $id, procedureName: $procedureName, teeth: $toothNumbers, status: $status)';
  }
}
