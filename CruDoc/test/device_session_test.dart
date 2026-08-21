import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:doctor_management_app/core/models/device_session.dart';
import 'package:doctor_management_app/core/utils/device_info_helper.dart';
import 'package:doctor_management_app/features/super_admin/models/doctor_model.dart';
import 'package:doctor_management_app/features/super_admin/config/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceSession Model Tests', () {
    test('serializes and deserializes accurately with all fields', () {
      final now = DateTime(2026, 8, 21, 14, 30);
      final session = DeviceSession(
        sessionId: 'session-uuid-1234',
        doctorId: 'doc-789',
        deviceName: 'Chrome on Windows',
        platform: 'web',
        appVersion: '1.0.0+1',
        createdAt: now,
        lastActiveAt: now,
        status: 'active',
        isCurrentDevice: true,
      );

      final map = session.toFirestore();
      expect(map['sessionId'], 'session-uuid-1234');
      expect(map['doctorId'], 'doc-789');
      expect(map['deviceName'], 'Chrome on Windows');
      expect(map['platform'], 'web');
      expect(map['appVersion'], '1.0.0+1');
      expect(map['status'], 'active');
      expect(map['createdAt'], isA<Timestamp>());

      final restored = DeviceSession.fromJson(
        {
          'sessionId': 'session-uuid-1234',
          'doctorId': 'doc-789',
          'deviceName': 'Chrome on Windows',
          'platform': 'web',
          'appVersion': '1.0.0+1',
          'createdAt': Timestamp.fromDate(now),
          'lastActiveAt': Timestamp.fromDate(now),
          'status': 'active',
        },
        currentLocalToken: 'session-uuid-1234',
      );

      expect(restored.sessionId, 'session-uuid-1234');
      expect(restored.doctorId, 'doc-789');
      expect(restored.deviceName, 'Chrome on Windows');
      expect(restored.platform, 'web');
      expect(restored.appVersion, '1.0.0+1');
      expect(restored.isActive, isTrue);
      expect(restored.isRevoked, isFalse);
      expect(restored.isCurrentDevice, isTrue);
    });

    test('isCurrentDevice is false when local token differs', () {
      final now = DateTime.now();
      final session = DeviceSession.fromJson(
        {
          'sessionId': 'session-uuid-1234',
          'doctorId': 'doc-789',
          'deviceName': 'Samsung Galaxy S24',
          'platform': 'android',
          'createdAt': Timestamp.fromDate(now),
          'lastActiveAt': Timestamp.fromDate(now),
          'status': 'active',
        },
        currentLocalToken: 'different-token-5678',
      );

      expect(session.isCurrentDevice, isFalse);
      expect(session.platform, 'android');
    });

    test('status getters work correctly for active and revoked', () {
      final now = DateTime.now();
      final activeSession = DeviceSession(
        sessionId: 's-1',
        doctorId: 'doc-1',
        deviceName: 'Device A',
        platform: 'ios',
        createdAt: now,
        lastActiveAt: now,
        status: 'active',
      );

      final revokedSession = DeviceSession(
        sessionId: 's-2',
        doctorId: 'doc-1',
        deviceName: 'Device B',
        platform: 'windows',
        createdAt: now,
        lastActiveAt: now,
        status: 'revoked',
      );

      expect(activeSession.isActive, isTrue);
      expect(activeSession.isRevoked, isFalse);
      expect(revokedSession.isActive, isFalse);
      expect(revokedSession.isRevoked, isTrue);
    });

    test('copyWith properly modifies fields', () {
      final now = DateTime.now();
      final session = DeviceSession(
        sessionId: 's-1',
        doctorId: 'doc-1',
        deviceName: 'Device A',
        platform: 'ios',
        createdAt: now,
        lastActiveAt: now,
        status: 'active',
      );

      final updated = session.copyWith(
        status: 'revoked',
        isCurrentDevice: true,
      );

      expect(updated.sessionId, 's-1');
      expect(updated.status, 'revoked');
      expect(updated.isCurrentDevice, isTrue);
    });
  });

  group('DoctorModel Multi-Device & Limit Tests', () {
    test('serializes and deserializes allowMultiDevice and maxDeviceLimit correctly', () {
      final doc = DoctorModel(
        id: 'doc-001',
        name: 'Dr. Priya Mehta',
        email: 'priya@example.com',
        phone: '9876543210',
        specialization: 'Cardiology',
        clinicName: 'Heart Care Clinic',
        country: 'India',
        timeZone: 'Asia/Kolkata',
        subscriptionPlan: SubscriptionPlan.professional,
        allowMultiDevice: true,
        maxDeviceLimit: 5,
      );

      final json = doc.toJson();
      expect(json['allowMultiDevice'], isTrue);
      expect(json['maxDeviceLimit'], 5);

      final restored = DoctorModel.fromJson(json, 'doc-001');
      expect(restored.allowMultiDevice, isTrue);
      expect(restored.maxDeviceLimit, 5);
      expect(restored.name, 'Dr. Priya Mehta');
    });

    test('defaults allowMultiDevice to false and maxDeviceLimit to 0', () {
      final doc = DoctorModel(
        id: 'doc-002',
        name: 'Dr. Test',
        email: 'test@example.com',
        phone: '1234567890',
        specialization: 'General',
        clinicName: 'Clinic',
        country: 'India',
        timeZone: 'Asia/Kolkata',
        subscriptionPlan: SubscriptionPlan.starter,
      );

      expect(doc.allowMultiDevice, isFalse);
      expect(doc.maxDeviceLimit, 0);
    });
  });

  group('DeviceInfoHelper Tests', () {
    test('getPlatformKey returns valid non-empty string', () {
      final key = DeviceInfoHelper.getPlatformKey();
      expect(key, isNotEmpty);
      expect(
        ['web', 'android', 'ios', 'windows', 'macos', 'linux', 'unknown'].contains(key),
        isTrue,
      );
    });

    test('getDeviceDisplayName returns meaningful name', () async {
      final name = await DeviceInfoHelper.getDeviceDisplayName();
      expect(name, isNotEmpty);
    });
  });
}
