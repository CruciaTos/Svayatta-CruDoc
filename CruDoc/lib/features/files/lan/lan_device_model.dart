import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Represents a trusted device in `clinics/{clinicId}/devices/{deviceId}`.
@immutable
class LanDevice {
  const LanDevice({
    required this.id,
    required this.clinicId,
    required this.uid,
    required this.name,
    required this.platform,
    required this.certPem,
    required this.certSha256,
    this.ips = const [],
    this.port = 0,
    this.lanUpdatedAt,
    this.lastSeenAt,
    this.createdAt,
  });

  final String id;
  final String clinicId;
  final String uid;
  final String name;
  final String platform;
  final String certPem;
  final String certSha256;
  final List<String> ips;
  final int port;
  final DateTime? lanUpdatedAt;
  final DateTime? lastSeenAt;
  final DateTime? createdAt;

  factory LanDevice.fromFirestore({
    required String id,
    required String clinicId,
    required Map<String, dynamic> data,
  }) {
    final lan = data['lan'] as Map<String, dynamic>?;
    final ips = <String>[];
    if (lan != null && lan['ips'] is List) {
      for (final ip in lan['ips'] as List) {
        if (ip is String && ip.isNotEmpty) ips.add(ip);
      }
    }
    final port = lan != null && lan['port'] is num ? (lan['port'] as num).toInt() : 0;

    DateTime? parseTs(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return LanDevice(
      id: id,
      clinicId: clinicId,
      uid: data['uid'] as String? ?? '',
      name: data['name'] as String? ?? 'Colleague Device',
      platform: data['platform'] as String? ?? 'windows',
      certPem: data['certPem'] as String? ?? '',
      certSha256: data['certSha256'] as String? ?? '',
      ips: ips,
      port: port,
      lanUpdatedAt: parseTs(lan?['updatedAt']),
      lastSeenAt: parseTs(data['lastSeenAt']),
      createdAt: parseTs(data['createdAt']),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'uid': uid,
    'name': name,
    'platform': platform,
    'certPem': certPem,
    'certSha256': certSha256,
    'lan': {
      'ips': ips,
      'port': port,
      'updatedAt': lanUpdatedAt != null
          ? Timestamp.fromDate(lanUpdatedAt!)
          : FieldValue.serverTimestamp(),
    },
    'lastSeenAt': lastSeenAt != null
        ? Timestamp.fromDate(lastSeenAt!)
        : FieldValue.serverTimestamp(),
    'createdAt': createdAt != null
        ? Timestamp.fromDate(createdAt!)
        : FieldValue.serverTimestamp(),
  };

  /// Whether this device has reachable LAN addresses and port published.
  bool get hasLanEndpoint => ips.isNotEmpty && port > 0;
}
