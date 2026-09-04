import 'package:cloud_firestore/cloud_firestore.dart';

/// Core Dental Procedure Catalog data model.
///
/// Clinic-level, doctor-owned reference data.
/// Analogue: [MedicineModel]. Kept as a plain hand-written model
/// (no freezed/json_serializable) matching the project's standard pattern.
class DentalProcedureCatalogModel {
  final String id;
  final String doctorId;
  final String code;
  final String name;
  final String category;
  final double? defaultPrice;
  final int? defaultDurationMinutes;
  final bool requiresToothSelection;
  final bool isActive;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Sync triad fields
  final String syncStatus;
  final bool pendingDelete;
  final DateTime? lastSyncedAt;

  const DentalProcedureCatalogModel({
    required this.id,
    required this.doctorId,
    required this.code,
    required this.name,
    this.category = 'general',
    this.defaultPrice,
    this.defaultDurationMinutes,
    this.requiresToothSelection = true,
    this.isActive = true,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 'synced',
    this.pendingDelete = false,
    this.lastSyncedAt,
  });

  factory DentalProcedureCatalogModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return DentalProcedureCatalogModel.fromJson(data, id: doc.id);
  }

  factory DentalProcedureCatalogModel.fromJson(
    Map<String, dynamic> map, {
    String? id,
  }) {
    return DentalProcedureCatalogModel(
      id: id ?? map['id'] as String? ?? '',
      doctorId: map['doctorId'] as String? ?? '',
      code: map['code'] as String? ?? '',
      name: map['name'] as String? ?? '',
      category: map['category'] as String? ?? 'general',
      defaultPrice: (map['defaultPrice'] as num?)?.toDouble(),
      defaultDurationMinutes: (map['defaultDurationMinutes'] as num?)?.toInt(),
      requiresToothSelection: map['requiresToothSelection'] as bool? ?? true,
      isActive: map['isActive'] as bool? ?? true,
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
      'code': code,
      'name': name,
      'category': category,
      'defaultPrice': defaultPrice,
      'defaultDurationMinutes': defaultDurationMinutes,
      'requiresToothSelection': requiresToothSelection,
      'isActive': isActive,
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
      'code': code,
      'name': name,
      'category': category,
      'defaultPrice': defaultPrice,
      'defaultDurationMinutes': defaultDurationMinutes,
      'requiresToothSelection': requiresToothSelection ? 1 : 0,
      'isActive': isActive ? 1 : 0,
      'isDeleted': isDeleted ? 1 : 0,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'syncStatus': syncStatus,
      'pendingDelete': pendingDelete ? 1 : 0,
      'lastSyncedAt': lastSyncedAt?.millisecondsSinceEpoch,
    };
  }

  factory DentalProcedureCatalogModel.fromMap(Map<String, dynamic> map) {
    return DentalProcedureCatalogModel(
      id: map['id'] as String? ?? '',
      doctorId: map['doctorId'] as String? ?? '',
      code: map['code'] as String? ?? '',
      name: map['name'] as String? ?? '',
      category: map['category'] as String? ?? 'general',
      defaultPrice: (map['defaultPrice'] as num?)?.toDouble(),
      defaultDurationMinutes: (map['defaultDurationMinutes'] as num?)?.toInt(),
      requiresToothSelection: map['requiresToothSelection'] == 1 || map['requiresToothSelection'] == true,
      isActive: map['isActive'] == 1 || map['isActive'] == true,
      isDeleted: map['isDeleted'] == 1 || map['isDeleted'] == true,
      createdAt: _toDate(map['createdAt']) ?? DateTime.now(),
      updatedAt: _toDate(map['updatedAt']) ?? DateTime.now(),
      syncStatus: map['syncStatus'] as String? ?? 'synced',
      pendingDelete: map['pendingDelete'] == 1 || map['pendingDelete'] == true,
      lastSyncedAt: _toDate(map['lastSyncedAt']),
    );
  }

  DentalProcedureCatalogModel copyWith({
    String? id,
    String? doctorId,
    String? code,
    String? name,
    String? category,
    double? defaultPrice,
    bool clearDefaultPrice = false,
    int? defaultDurationMinutes,
    bool clearDefaultDuration = false,
    bool? requiresToothSelection,
    bool? isActive,
    bool? isDeleted,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
    bool? pendingDelete,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
  }) {
    return DentalProcedureCatalogModel(
      id: id ?? this.id,
      doctorId: doctorId ?? this.doctorId,
      code: code ?? this.code,
      name: name ?? this.name,
      category: category ?? this.category,
      defaultPrice: clearDefaultPrice ? null : (defaultPrice ?? this.defaultPrice),
      defaultDurationMinutes: clearDefaultDuration
          ? null
          : (defaultDurationMinutes ?? this.defaultDurationMinutes),
      requiresToothSelection: requiresToothSelection ?? this.requiresToothSelection,
      isActive: isActive ?? this.isActive,
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
      other is DentalProcedureCatalogModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          doctorId == other.doctorId &&
          code == other.code &&
          name == other.name &&
          category == other.category &&
          defaultPrice == other.defaultPrice &&
          defaultDurationMinutes == other.defaultDurationMinutes &&
          requiresToothSelection == other.requiresToothSelection &&
          isActive == other.isActive &&
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
        code,
        name,
        category,
        defaultPrice,
        defaultDurationMinutes,
        requiresToothSelection,
        isActive,
        isDeleted,
        createdAt,
        updatedAt,
        syncStatus,
        pendingDelete,
        lastSyncedAt,
      );

  @override
  String toString() {
    return 'DentalProcedureCatalogModel(id: $id, code: $code, name: $name, category: $category, defaultPrice: $defaultPrice)';
  }
}
