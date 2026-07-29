import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for feature flag toggles per doctor.
class FeatureFlagModel {
  final String doctorId;
  final List<String> enabledModules;
  final DateTime lastModified;
  final String? modifiedBy;

  FeatureFlagModel({
    required this.doctorId,
    required this.enabledModules,
    DateTime? lastModified,
    this.modifiedBy,
  }) : lastModified = lastModified ?? DateTime.now();

  factory FeatureFlagModel.fromJson(Map<String, dynamic> json, String doctorId) {
    return FeatureFlagModel(
      doctorId: doctorId,
      enabledModules: (json['enabledModules'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      lastModified: (json['lastModified'] as Timestamp?)?.toDate() ?? DateTime.now(),
      modifiedBy: json['modifiedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabledModules': enabledModules,
      'lastModified': Timestamp.fromDate(lastModified),
      'modifiedBy': modifiedBy,
    };
  }

  bool isModuleEnabled(String moduleId) => enabledModules.contains(moduleId);

  FeatureFlagModel copyWith({
    String? doctorId,
    List<String>? enabledModules,
    DateTime? lastModified,
    String? modifiedBy,
  }) {
    return FeatureFlagModel(
      doctorId: doctorId ?? this.doctorId,
      enabledModules: enabledModules ?? this.enabledModules,
      lastModified: lastModified ?? this.lastModified,
      modifiedBy: modifiedBy ?? this.modifiedBy,
    );
  }
}

/// Model for platform-wide feature toggles.
class PlatformFeatureFlag {
  final String id;
  final String name;
  final String description;
  final bool isEnabled;
  final bool isBeta;
  final DateTime createdAt;
  final DateTime updatedAt;

  PlatformFeatureFlag({
    required this.id,
    required this.name,
    this.description = '',
    this.isEnabled = false,
    this.isBeta = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory PlatformFeatureFlag.fromJson(Map<String, dynamic> json, String id) {
    return PlatformFeatureFlag(
      id: id,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      isEnabled: json['isEnabled'] as bool? ?? false,
      isBeta: json['isBeta'] as bool? ?? false,
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'isEnabled': isEnabled,
      'isBeta': isBeta,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}