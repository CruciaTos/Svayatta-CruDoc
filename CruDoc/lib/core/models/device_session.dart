import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents an active device session for an authenticated doctor.
class DeviceSession {
  final String sessionId;
  final String doctorId;
  final String deviceName;
  final String platform;
  final String? appVersion;
  final DateTime createdAt;
  final DateTime lastActiveAt;
  final String status; // 'active' | 'revoked'
  final bool isCurrentDevice;

  const DeviceSession({
    required this.sessionId,
    required this.doctorId,
    required this.deviceName,
    required this.platform,
    this.appVersion,
    required this.createdAt,
    required this.lastActiveAt,
    this.status = 'active',
    this.isCurrentDevice = false,
  });

  bool get isActive => status == 'active';
  bool get isRevoked => status == 'revoked';

  factory DeviceSession.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    String? currentLocalToken,
  }) {
    final data = doc.data() ?? {};
    final id = doc.id;

    DateTime parseTimestamp(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) {
        return DateTime.tryParse(val) ?? DateTime.now();
      }
      return DateTime.now();
    }

    final createdAt = parseTimestamp(data['createdAt']);
    final lastActiveAt = parseTimestamp(data['lastActiveAt'] ?? data['createdAt']);

    return DeviceSession(
      sessionId: id,
      doctorId: data['doctorId'] as String? ?? '',
      deviceName: data['deviceName'] as String? ?? 'Unknown Device',
      platform: (data['platform'] as String? ?? 'unknown').toLowerCase(),
      appVersion: data['appVersion'] as String?,
      createdAt: createdAt,
      lastActiveAt: lastActiveAt,
      status: data['status'] as String? ?? 'active',
      isCurrentDevice: currentLocalToken != null && id == currentLocalToken,
    );
  }

  factory DeviceSession.fromJson(
    Map<String, dynamic> json, {
    String? currentLocalToken,
  }) {
    DateTime parseTimestamp(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) {
        return DateTime.tryParse(val) ?? DateTime.now();
      }
      return DateTime.now();
    }

    final id = json['sessionId'] as String? ?? '';
    return DeviceSession(
      sessionId: id,
      doctorId: json['doctorId'] as String? ?? '',
      deviceName: json['deviceName'] as String? ?? 'Unknown Device',
      platform: (json['platform'] as String? ?? 'unknown').toLowerCase(),
      appVersion: json['appVersion'] as String?,
      createdAt: parseTimestamp(json['createdAt']),
      lastActiveAt: parseTimestamp(json['lastActiveAt'] ?? json['createdAt']),
      status: json['status'] as String? ?? 'active',
      isCurrentDevice: currentLocalToken != null && id == currentLocalToken,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'sessionId': sessionId,
      'doctorId': doctorId,
      'deviceName': deviceName,
      'platform': platform,
      if (appVersion != null) 'appVersion': appVersion,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastActiveAt': Timestamp.fromDate(lastActiveAt),
      'status': status,
    };
  }

  DeviceSession copyWith({
    String? sessionId,
    String? doctorId,
    String? deviceName,
    String? platform,
    String? appVersion,
    DateTime? createdAt,
    DateTime? lastActiveAt,
    String? status,
    bool? isCurrentDevice,
  }) {
    return DeviceSession(
      sessionId: sessionId ?? this.sessionId,
      doctorId: doctorId ?? this.doctorId,
      deviceName: deviceName ?? this.deviceName,
      platform: platform ?? this.platform,
      appVersion: appVersion ?? this.appVersion,
      createdAt: createdAt ?? this.createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      status: status ?? this.status,
      isCurrentDevice: isCurrentDevice ?? this.isCurrentDevice,
    );
  }
}
