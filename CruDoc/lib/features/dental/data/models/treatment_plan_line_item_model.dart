import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Status of a treatment plan line item.
enum TreatmentPlanItemStatus {
  proposed,
  accepted,
  declined,
  invoiced;

  static TreatmentPlanItemStatus fromString(String? val) {
    if (val == null) return TreatmentPlanItemStatus.proposed;
    final lower = val.toLowerCase().trim();
    if (lower == 'accepted') return TreatmentPlanItemStatus.accepted;
    if (lower == 'declined') return TreatmentPlanItemStatus.declined;
    if (lower == 'invoiced') return TreatmentPlanItemStatus.invoiced;
    return TreatmentPlanItemStatus.proposed;
  }

  String get code {
    switch (this) {
      case TreatmentPlanItemStatus.proposed:
        return 'proposed';
      case TreatmentPlanItemStatus.accepted:
        return 'accepted';
      case TreatmentPlanItemStatus.declined:
        return 'declined';
      case TreatmentPlanItemStatus.invoiced:
        return 'invoiced';
    }
  }

  String get label {
    switch (this) {
      case TreatmentPlanItemStatus.proposed:
        return 'Proposed';
      case TreatmentPlanItemStatus.accepted:
        return 'Accepted';
      case TreatmentPlanItemStatus.declined:
        return 'Declined';
      case TreatmentPlanItemStatus.invoiced:
        return 'Invoiced';
    }
  }
}

/// Line item for a dental treatment plan or estimate/quote.
///
/// Plain hand-written model conforming to data contract 0.3(e).
/// Stored in SQLite table `treatment_plan_line_items` and Firestore `treatment_plan_line_items/{id}`.
class TreatmentPlanLineItemModel {
  final String id;
  final String doctorId;
  final String patientId;
  final String treatmentPlanId;
  final String? procedureCatalogId;
  final String procedureName;
  final List<String> toothNumbers;
  final double estimatedPrice;
  final int sequence;
  final String status;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Sync triad fields
  final String syncStatus;
  final bool pendingDelete;
  final DateTime? lastSyncedAt;

  const TreatmentPlanLineItemModel({
    required this.id,
    required this.doctorId,
    required this.patientId,
    required this.treatmentPlanId,
    this.procedureCatalogId,
    required this.procedureName,
    this.toothNumbers = const [],
    this.estimatedPrice = 0.0,
    this.sequence = 0,
    this.status = 'proposed',
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 'synced',
    this.pendingDelete = false,
    this.lastSyncedAt,
  });

  factory TreatmentPlanLineItemModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return TreatmentPlanLineItemModel.fromJson(data, id: doc.id);
  }

  factory TreatmentPlanLineItemModel.fromJson(
    Map<String, dynamic> map, {
    String? id,
  }) {
    List<String> parseTeeth(dynamic val) {
      if (val is List) {
        return val.map((e) => e.toString()).toList();
      } else if (val is String && val.isNotEmpty) {
        try {
          final decoded = jsonDecode(val);
          if (decoded is List) {
            return decoded.map((e) => e.toString()).toList();
          }
        } catch (_) {}
      }
      return const [];
    }

    DateTime parseDateTime(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val is String) {
        return DateTime.tryParse(val) ?? DateTime.now();
      }
      return DateTime.now();
    }

    DateTime? parseNullableDateTime(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    double parseDouble(dynamic val) {
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val) ?? 0.0;
      return 0.0;
    }

    int parseInt(dynamic val) {
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val) ?? 0;
      return 0;
    }

    return TreatmentPlanLineItemModel(
      id: id ?? map['id']?.toString() ?? '',
      doctorId: map['doctorId']?.toString() ?? '',
      patientId: map['patientId']?.toString() ?? '',
      treatmentPlanId: map['treatmentPlanId']?.toString() ?? '',
      procedureCatalogId: map['procedureCatalogId']?.toString(),
      procedureName: map['procedureName']?.toString() ?? '',
      toothNumbers: parseTeeth(map['toothNumbers']),
      estimatedPrice: parseDouble(map['estimatedPrice']),
      sequence: parseInt(map['sequence']),
      status: map['status']?.toString() ?? 'proposed',
      isDeleted: map['isDeleted'] == 1 || map['isDeleted'] == true,
      createdAt: parseDateTime(map['createdAt']),
      updatedAt: parseDateTime(map['updatedAt']),
      syncStatus: map['syncStatus']?.toString() ?? 'synced',
      pendingDelete: map['pendingDelete'] == 1 || map['pendingDelete'] == true,
      lastSyncedAt: parseNullableDateTime(map['lastSyncedAt']),
    );
  }

  factory TreatmentPlanLineItemModel.fromMap(Map<String, dynamic> map) {
    return TreatmentPlanLineItemModel.fromJson(map);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'doctorId': doctorId,
      'patientId': patientId,
      'treatmentPlanId': treatmentPlanId,
      'procedureCatalogId': procedureCatalogId,
      'procedureName': procedureName,
      'toothNumbers': toothNumbers,
      'estimatedPrice': estimatedPrice,
      'sequence': sequence,
      'status': status,
      'isDeleted': isDeleted,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'syncStatus': syncStatus,
      'pendingDelete': pendingDelete,
      'lastSyncedAt': lastSyncedAt != null ? Timestamp.fromDate(lastSyncedAt!) : null,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'doctorId': doctorId,
      'patientId': patientId,
      'treatmentPlanId': treatmentPlanId,
      'procedureCatalogId': procedureCatalogId,
      'procedureName': procedureName,
      'toothNumbers': jsonEncode(toothNumbers),
      'estimatedPrice': estimatedPrice,
      'sequence': sequence,
      'status': status,
      'isDeleted': isDeleted ? 1 : 0,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'syncStatus': syncStatus,
      'pendingDelete': pendingDelete ? 1 : 0,
      'lastSyncedAt': lastSyncedAt?.millisecondsSinceEpoch,
    };
  }

  TreatmentPlanLineItemModel copyWith({
    String? id,
    String? doctorId,
    String? patientId,
    String? treatmentPlanId,
    String? procedureCatalogId,
    String? procedureName,
    List<String>? toothNumbers,
    double? estimatedPrice,
    int? sequence,
    String? status,
    bool? isDeleted,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
    bool? pendingDelete,
    DateTime? lastSyncedAt,
  }) {
    return TreatmentPlanLineItemModel(
      id: id ?? this.id,
      doctorId: doctorId ?? this.doctorId,
      patientId: patientId ?? this.patientId,
      treatmentPlanId: treatmentPlanId ?? this.treatmentPlanId,
      procedureCatalogId: procedureCatalogId ?? this.procedureCatalogId,
      procedureName: procedureName ?? this.procedureName,
      toothNumbers: toothNumbers ?? this.toothNumbers,
      estimatedPrice: estimatedPrice ?? this.estimatedPrice,
      sequence: sequence ?? this.sequence,
      status: status ?? this.status,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      pendingDelete: pendingDelete ?? this.pendingDelete,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TreatmentPlanLineItemModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
