import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/services/field_cipher.dart';

/// Supported dental tooth notation systems.
enum ToothNotationSystem {
  fdi,
  universal,
  palmer;

  static ToothNotationSystem fromString(String? val) {
    if (val == null) return ToothNotationSystem.fdi;
    final lower = val.toLowerCase().trim();
    if (lower == 'universal') return ToothNotationSystem.universal;
    if (lower == 'palmer') return ToothNotationSystem.palmer;
    return ToothNotationSystem.fdi;
  }

  String get code => name;
}

/// Standard tooth surfaces.
enum ToothSurface {
  mesial,
  distal,
  occlusal,
  buccal,
  lingual,
  incisal,
  cervical;

  static ToothSurface? fromString(String? val) {
    if (val == null || val.trim().isEmpty) return null;
    final lower = val.toLowerCase().trim();
    for (final s in ToothSurface.values) {
      if (s.name == lower) return s;
    }
    return null;
  }
}

/// Standard tooth clinical conditions.
enum ToothCondition {
  caries,
  fractured,
  missing,
  unerupted,
  impacted,
  restored,
  rootCanal;

  static ToothCondition? fromString(String? val) {
    if (val == null || val.trim().isEmpty) return null;
    final lower = val.toLowerCase().trim();
    for (final c in ToothCondition.values) {
      if (c.name == lower) return c;
    }
    return null;
  }
}

/// Standard tooth treatments.
enum ToothTreatment {
  filling,
  extraction,
  crown,
  bridge,
  implant,
  scaling,
  rct;

  static ToothTreatment? fromString(String? val) {
    if (val == null || val.trim().isEmpty) return null;
    final lower = val.toLowerCase().trim();
    for (final t in ToothTreatment.values) {
      if (t.name == lower) return t;
    }
    return null;
  }
}

/// Patient-linked visual Tooth Chart (Odontogram) entry model.
///
/// One row per (patient, tooth, event) representing a chronological log.
/// Plain hand-written Dart model. Notes field is encrypted via [FieldCipher].
class ToothChartEntryModel {
  final String id;
  final String doctorId;
  final String patientId;
  final String toothNumber;
  final String notationSystem;
  final String? surface;
  final String? condition;
  final String? treatment;
  final String? procedureLogId;
  final String notes;
  final DateTime recordedAt;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Sync triad fields
  final String syncStatus;
  final bool pendingDelete;
  final DateTime? lastSyncedAt;

  const ToothChartEntryModel({
    required this.id,
    required this.doctorId,
    required this.patientId,
    required this.toothNumber,
    this.notationSystem = 'fdi',
    this.surface,
    this.condition,
    this.treatment,
    this.procedureLogId,
    this.notes = '',
    required this.recordedAt,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 'synced',
    this.pendingDelete = false,
    this.lastSyncedAt,
  });

  factory ToothChartEntryModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return ToothChartEntryModel.fromJson(data, id: doc.id);
  }

  factory ToothChartEntryModel.fromJson(
    Map<String, dynamic> map, {
    String? id,
  }) {
    final rawNotes = map['notes'] as String? ?? '';
    return ToothChartEntryModel(
      id: id ?? map['id'] as String? ?? '',
      doctorId: map['doctorId'] as String? ?? '',
      patientId: map['patientId'] as String? ?? '',
      toothNumber: map['toothNumber'] as String? ?? '',
      notationSystem: map['notationSystem'] as String? ?? 'fdi',
      surface: map['surface'] as String?,
      condition: map['condition'] as String?,
      treatment: map['treatment'] as String?,
      procedureLogId: map['procedureLogId'] as String?,
      notes: FieldCipher.decrypt(rawNotes),
      recordedAt: _toDate(map['recordedAt']) ?? DateTime.now(),
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
      'toothNumber': toothNumber,
      'notationSystem': notationSystem,
      'surface': surface,
      'condition': condition,
      'treatment': treatment,
      'procedureLogId': procedureLogId,
      'notes': FieldCipher.encrypt(notes),
      'recordedAt': Timestamp.fromDate(recordedAt),
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
      'patientId': patientId,
      'toothNumber': toothNumber,
      'notationSystem': notationSystem,
      'surface': surface,
      'condition': condition,
      'treatment': treatment,
      'procedureLogId': procedureLogId,
      'notes': FieldCipher.encrypt(notes),
      'recordedAt': recordedAt.millisecondsSinceEpoch,
      'isDeleted': isDeleted ? 1 : 0,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'syncStatus': syncStatus,
      'pendingDelete': pendingDelete ? 1 : 0,
      'lastSyncedAt': lastSyncedAt?.millisecondsSinceEpoch,
    };
  }

  factory ToothChartEntryModel.fromMap(Map<String, dynamic> map) {
    final rawNotes = map['notes'] as String? ?? '';
    return ToothChartEntryModel(
      id: map['id'] as String? ?? '',
      doctorId: map['doctorId'] as String? ?? '',
      patientId: map['patientId'] as String? ?? '',
      toothNumber: map['toothNumber'] as String? ?? '',
      notationSystem: map['notationSystem'] as String? ?? 'fdi',
      surface: map['surface'] as String?,
      condition: map['condition'] as String?,
      treatment: map['treatment'] as String?,
      procedureLogId: map['procedureLogId'] as String?,
      notes: FieldCipher.decrypt(rawNotes),
      recordedAt: _toDate(map['recordedAt']) ?? DateTime.now(),
      isDeleted: map['isDeleted'] == 1 || map['isDeleted'] == true,
      createdAt: _toDate(map['createdAt']) ?? DateTime.now(),
      updatedAt: _toDate(map['updatedAt']) ?? DateTime.now(),
      syncStatus: map['syncStatus'] as String? ?? 'synced',
      pendingDelete: map['pendingDelete'] == 1 || map['pendingDelete'] == true,
      lastSyncedAt: _toDate(map['lastSyncedAt']),
    );
  }

  ToothChartEntryModel copyWith({
    String? id,
    String? doctorId,
    String? patientId,
    String? toothNumber,
    String? notationSystem,
    String? surface,
    bool clearSurface = false,
    String? condition,
    bool clearCondition = false,
    String? treatment,
    bool clearTreatment = false,
    String? procedureLogId,
    bool clearProcedureLogId = false,
    String? notes,
    DateTime? recordedAt,
    bool? isDeleted,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
    bool? pendingDelete,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
  }) {
    return ToothChartEntryModel(
      id: id ?? this.id,
      doctorId: doctorId ?? this.doctorId,
      patientId: patientId ?? this.patientId,
      toothNumber: toothNumber ?? this.toothNumber,
      notationSystem: notationSystem ?? this.notationSystem,
      surface: clearSurface ? null : (surface ?? this.surface),
      condition: clearCondition ? null : (condition ?? this.condition),
      treatment: clearTreatment ? null : (treatment ?? this.treatment),
      procedureLogId: clearProcedureLogId ? null : (procedureLogId ?? this.procedureLogId),
      notes: notes ?? this.notes,
      recordedAt: recordedAt ?? this.recordedAt,
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
      other is ToothChartEntryModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          doctorId == other.doctorId &&
          patientId == other.patientId &&
          toothNumber == other.toothNumber &&
          notationSystem == other.notationSystem &&
          surface == other.surface &&
          condition == other.condition &&
          treatment == other.treatment &&
          procedureLogId == other.procedureLogId &&
          notes == other.notes &&
          recordedAt == other.recordedAt &&
          isDeleted == other.isDeleted &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          syncStatus == other.syncStatus &&
          pendingDelete == other.pendingDelete &&
          lastSyncedAt == other.lastSyncedAt;

  @override
  int get hashCode => Object.hashAll([
        id,
        doctorId,
        patientId,
        toothNumber,
        notationSystem,
        surface,
        condition,
        treatment,
        procedureLogId,
        notes,
        recordedAt,
        isDeleted,
        createdAt,
        updatedAt,
        syncStatus,
        pendingDelete,
        lastSyncedAt,
      ]);

  @override
  String toString() {
    return 'ToothChartEntryModel(id: $id, toothNumber: $toothNumber, condition: $condition, treatment: $treatment)';
  }
}
