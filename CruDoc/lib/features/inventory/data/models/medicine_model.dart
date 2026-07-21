import 'package:cloud_firestore/cloud_firestore.dart';

/// Core Medicine data model.
///
/// Represents a single medicine document stored in the `medicines`
/// Firestore collection and mirrored in the local `medicines` SQLite
/// table. Kept as a plain, hand-written model (no freezed/json_serializable)
/// to match [Patient] and the rest of the app's current simplicity.
class MedicineModel {
  final String id;
  final String doctorId;
  final String name;
  final String category;
  final String unit;
  final int currentStock;
  final int reorderThreshold;
  final double? unitPrice;
  final String? supplierName;
  final String? batchNumber;
  final DateTime? expiryDate;

  /// Dedup flags so the low-stock/expiry alert only fires once per crossing
  /// instead of refiring on every rebuild.
  final DateTime? lowStockNotifiedAt;
  final DateTime? expiryNotifiedAt;

  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MedicineModel({
    required this.id,
    this.doctorId = '',
    required this.name,
    this.category = '',
    required this.unit,
    this.currentStock = 0,
    this.reorderThreshold = 10,
    this.unitPrice,
    this.supplierName,
    this.batchNumber,
    this.expiryDate,
    this.lowStockNotifiedAt,
    this.expiryNotifiedAt,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  /// True once stock has dropped to (or below) the doctor-configured
  /// reorder threshold.
  bool get isLowStock => currentStock <= reorderThreshold;

  /// True when this medicine has a known expiry date within the next
  /// 30 days (including already-expired stock).
  bool get isExpiringSoon =>
      expiryDate != null && expiryDate!.difference(DateTime.now()).inDays <= 30;

  factory MedicineModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return MedicineModel.fromJson(data, id: doc.id);
  }

  /// Builds a [MedicineModel] from a raw map (Firestore payload or a
  /// SQLite-shaped map with matching keys).
  factory MedicineModel.fromJson(Map<String, dynamic> map, {String? id}) {
    return MedicineModel(
      id: id ?? map['id'] as String? ?? '',
      doctorId: map['doctorId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      category: map['category'] as String? ?? '',
      unit: map['unit'] as String? ?? '',
      currentStock: (map['currentStock'] as num?)?.toInt() ?? 0,
      reorderThreshold: (map['reorderThreshold'] as num?)?.toInt() ?? 10,
      unitPrice: (map['unitPrice'] as num?)?.toDouble(),
      supplierName: map['supplierName'] as String?,
      batchNumber: map['batchNumber'] as String?,
      expiryDate: _toDate(map['expiryDate']),
      lowStockNotifiedAt: _toDate(map['lowStockNotifiedAt']),
      expiryNotifiedAt: _toDate(map['expiryNotifiedAt']),
      isActive: map['isActive'] as bool? ?? true,
      createdAt: _toDate(map['createdAt']) ?? DateTime.now(),
      updatedAt: _toDate(map['updatedAt']) ?? DateTime.now(),
    );
  }

  /// Converts this [MedicineModel] into a Firestore-writable map. The
  /// document id is not included, since it is the document key.
  Map<String, dynamic> toJson() {
    return {
      'doctorId': doctorId,
      'name': name,
      'category': category,
      'unit': unit,
      'currentStock': currentStock,
      'reorderThreshold': reorderThreshold,
      'unitPrice': unitPrice,
      'supplierName': supplierName,
      'batchNumber': batchNumber,
      'expiryDate': expiryDate != null ? Timestamp.fromDate(expiryDate!) : null,
      'lowStockNotifiedAt': lowStockNotifiedAt != null
          ? Timestamp.fromDate(lowStockNotifiedAt!)
          : null,
      'expiryNotifiedAt': expiryNotifiedAt != null
          ? Timestamp.fromDate(expiryNotifiedAt!)
          : null,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  MedicineModel copyWith({
    String? doctorId,
    String? name,
    String? category,
    String? unit,
    int? currentStock,
    int? reorderThreshold,
    double? unitPrice,
    String? supplierName,
    String? batchNumber,
    DateTime? expiryDate,
    bool clearExpiryDate = false,
    DateTime? lowStockNotifiedAt,
    bool clearLowStockNotifiedAt = false,
    DateTime? expiryNotifiedAt,
    bool clearExpiryNotifiedAt = false,
    bool? isActive,
    DateTime? updatedAt,
  }) {
    return MedicineModel(
      id: id,
      doctorId: doctorId ?? this.doctorId,
      name: name ?? this.name,
      category: category ?? this.category,
      unit: unit ?? this.unit,
      currentStock: currentStock ?? this.currentStock,
      reorderThreshold: reorderThreshold ?? this.reorderThreshold,
      unitPrice: unitPrice ?? this.unitPrice,
      supplierName: supplierName ?? this.supplierName,
      batchNumber: batchNumber ?? this.batchNumber,
      expiryDate: clearExpiryDate ? null : (expiryDate ?? this.expiryDate),
      lowStockNotifiedAt: clearLowStockNotifiedAt
          ? null
          : (lowStockNotifiedAt ?? this.lowStockNotifiedAt),
      expiryNotifiedAt: clearExpiryNotifiedAt
          ? null
          : (expiryNotifiedAt ?? this.expiryNotifiedAt),
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return null;
  }
}
