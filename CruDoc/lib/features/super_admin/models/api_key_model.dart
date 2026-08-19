import 'package:cloud_firestore/cloud_firestore.dart';

/// Model representing an API Key.
class ApiKeyModel {
  final String id;
  final String name;
  final String maskedKey;
  final String? secretHash; // Hashed secret
  final bool isActive;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? lastUsedAt;
  final int rateLimit; // requests per minute
  final List<String> scopes;
  final String createdBy;
  final int totalRequests;

  ApiKeyModel({
    required this.id,
    required this.name,
    required this.maskedKey,
    this.secretHash,
    required this.isActive,
    required this.createdAt,
    this.expiresAt,
    this.lastUsedAt,
    this.rateLimit = 60,
    required this.scopes,
    required this.createdBy,
    this.totalRequests = 0,
  });

  factory ApiKeyModel.fromJson(Map<String, dynamic> json, String id) {
    return ApiKeyModel(
      id: id,
      name: json['name'] as String? ?? '',
      maskedKey: json['maskedKey'] as String? ?? '',
      secretHash: json['secretHash'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt: (json['expiresAt'] as Timestamp?)?.toDate(),
      lastUsedAt: (json['lastUsedAt'] as Timestamp?)?.toDate(),
      rateLimit: json['rateLimit'] as int? ?? 60,
      scopes: (json['scopes'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      createdBy: json['createdBy'] as String? ?? '',
      totalRequests: json['totalRequests'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'maskedKey': maskedKey,
      if (secretHash != null) 'secretHash': secretHash,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'lastUsedAt': lastUsedAt != null ? Timestamp.fromDate(lastUsedAt!) : null,
      'rateLimit': rateLimit,
      'scopes': scopes,
      'createdBy': createdBy,
      'totalRequests': totalRequests,
    };
  }

  ApiKeyModel copyWith({
    String? id,
    String? name,
    String? maskedKey,
    String? secretHash,
    bool? isActive,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? lastUsedAt,
    int? rateLimit,
    List<String>? scopes,
    String? createdBy,
    int? totalRequests,
  }) {
    return ApiKeyModel(
      id: id ?? this.id,
      name: name ?? this.name,
      maskedKey: maskedKey ?? this.maskedKey,
      secretHash: secretHash ?? this.secretHash,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      rateLimit: rateLimit ?? this.rateLimit,
      scopes: scopes ?? this.scopes,
      createdBy: createdBy ?? this.createdBy,
      totalRequests: totalRequests ?? this.totalRequests,
    );
  }
}

/// Model representing a request log for API usage.
class ApiLogModel {
  final String id;
  final String apiKeyId;
  final String apiKeyName;
  final String endpoint;
  final String method;
  final int statusCode;
  final int latencyMs;
  final DateTime timestamp;

  ApiLogModel({
    required this.id,
    required this.apiKeyId,
    required this.apiKeyName,
    required this.endpoint,
    required this.method,
    required this.statusCode,
    required this.latencyMs,
    required this.timestamp,
  });

  factory ApiLogModel.fromJson(Map<String, dynamic> json, String id) {
    return ApiLogModel(
      id: id,
      apiKeyId: json['apiKeyId'] as String? ?? '',
      apiKeyName: json['apiKeyName'] as String? ?? '',
      endpoint: json['endpoint'] as String? ?? '',
      method: json['method'] as String? ?? '',
      statusCode: json['statusCode'] as int? ?? 200,
      latencyMs: json['latencyMs'] as int? ?? 0,
      timestamp: (json['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'apiKeyId': apiKeyId,
      'apiKeyName': apiKeyName,
      'endpoint': endpoint,
      'method': method,
      'statusCode': statusCode,
      'latencyMs': latencyMs,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}
