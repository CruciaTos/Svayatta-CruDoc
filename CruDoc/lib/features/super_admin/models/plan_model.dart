import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for subscription plan definitions that Super Admin can edit.
class PlanModel {
  final String id;
  final String name;
  final double monthlyPrice;
  final double annualPrice;
  final double storageLimitGB;
  final int patientLimit;
  final int staffSlots;
  final int ocrLimitPerMonth;
  final int appointmentLimitPerMonth;
  final int onlineSessionsPerMonth;
  final bool customDomain;
  final bool whiteLabel;
  final List<String> includedModules;
  final String description;
  final bool isActive;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  PlanModel({
    required this.id,
    required this.name,
    required this.monthlyPrice,
    required this.annualPrice,
    required this.storageLimitGB,
    required this.patientLimit,
    required this.staffSlots,
    required this.ocrLimitPerMonth,
    required this.appointmentLimitPerMonth,
    required this.onlineSessionsPerMonth,
    required this.customDomain,
    required this.whiteLabel,
    required this.includedModules,
    this.description = '',
    this.isActive = true,
    this.sortOrder = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory PlanModel.fromJson(Map<String, dynamic> json, String id) {
    return PlanModel(
      id: id,
      name: json['name'] as String? ?? '',
      monthlyPrice: (json['monthlyPrice'] as num?)?.toDouble() ?? 0.0,
      annualPrice: (json['annualPrice'] as num?)?.toDouble() ?? 0.0,
      storageLimitGB: (json['storageLimitGB'] as num?)?.toDouble() ?? 0.0,
      patientLimit: json['patientLimit'] as int? ?? 0,
      staffSlots: json['staffSlots'] as int? ?? 0,
      ocrLimitPerMonth: json['ocrLimitPerMonth'] as int? ?? 0,
      appointmentLimitPerMonth: json['appointmentLimitPerMonth'] as int? ?? 0,
      onlineSessionsPerMonth: json['onlineSessionsPerMonth'] as int? ?? 0,
      customDomain: json['customDomain'] as bool? ?? false,
      whiteLabel: json['whiteLabel'] as bool? ?? false,
      includedModules: (json['includedModules'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      description: json['description'] as String? ?? '',
      isActive: json['isActive'] as bool? ?? true,
      sortOrder: json['sortOrder'] as int? ?? 0,
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'monthlyPrice': monthlyPrice,
      'annualPrice': annualPrice,
      'storageLimitGB': storageLimitGB,
      'patientLimit': patientLimit,
      'staffSlots': staffSlots,
      'ocrLimitPerMonth': ocrLimitPerMonth,
      'appointmentLimitPerMonth': appointmentLimitPerMonth,
      'onlineSessionsPerMonth': onlineSessionsPerMonth,
      'customDomain': customDomain,
      'whiteLabel': whiteLabel,
      'includedModules': includedModules,
      'description': description,
      'isActive': isActive,
      'sortOrder': sortOrder,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  PlanModel copyWith({
    String? id,
    String? name,
    double? monthlyPrice,
    double? annualPrice,
    double? storageLimitGB,
    int? patientLimit,
    int? staffSlots,
    int? ocrLimitPerMonth,
    int? appointmentLimitPerMonth,
    int? onlineSessionsPerMonth,
    bool? customDomain,
    bool? whiteLabel,
    List<String>? includedModules,
    String? description,
    bool? isActive,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PlanModel(
      id: id ?? this.id,
      name: name ?? this.name,
      monthlyPrice: monthlyPrice ?? this.monthlyPrice,
      annualPrice: annualPrice ?? this.annualPrice,
      storageLimitGB: storageLimitGB ?? this.storageLimitGB,
      patientLimit: patientLimit ?? this.patientLimit,
      staffSlots: staffSlots ?? this.staffSlots,
      ocrLimitPerMonth: ocrLimitPerMonth ?? this.ocrLimitPerMonth,
      appointmentLimitPerMonth: appointmentLimitPerMonth ?? this.appointmentLimitPerMonth,
      onlineSessionsPerMonth: onlineSessionsPerMonth ?? this.onlineSessionsPerMonth,
      customDomain: customDomain ?? this.customDomain,
      whiteLabel: whiteLabel ?? this.whiteLabel,
      includedModules: includedModules ?? this.includedModules,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'PlanModel(id: $id, name: $name, price: \$$monthlyPrice/mo)';
}