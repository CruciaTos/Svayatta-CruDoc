import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/files/lan/lan_device_model.dart';

void main() {
  group('LanDevice Model & Serialization', () {
    test('serializes and deserializes to/from Firestore map', () {
      final now = DateTime.utc(2026, 10, 27, 12, 0, 0);

      final device = LanDevice(
        id: 'dev_1234567890ab',
        clinicId: 'clinic_test',
        uid: 'user_doc_1',
        name: 'Reception PC',
        platform: 'windows',
        certPem: '-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----',
        certSha256: 'a' * 64,
        ips: ['192.168.1.15'],
        port: 47811,
        lanUpdatedAt: now,
        lastSeenAt: now,
        createdAt: now,
      );

      final map = device.toFirestore();
      expect(map['uid'], 'user_doc_1');
      expect(map['name'], 'Reception PC');
      expect(map['platform'], 'windows');
      expect(map['certSha256'], 'a' * 64);
      expect((map['lan'] as Map)['port'], 47811);
      expect((map['lan'] as Map)['ips'], ['192.168.1.15']);

      final restored = LanDevice.fromFirestore(
        id: 'dev_1234567890ab',
        clinicId: 'clinic_test',
        data: {
          'uid': 'user_doc_1',
          'name': 'Reception PC',
          'platform': 'windows',
          'certPem': '-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----',
          'certSha256': 'a' * 64,
          'lan': {
            'ips': ['192.168.1.15'],
            'port': 47811,
            'updatedAt': Timestamp.fromDate(now),
          },
          'lastSeenAt': Timestamp.fromDate(now),
          'createdAt': Timestamp.fromDate(now),
        },
      );

      expect(restored.id, 'dev_1234567890ab');
      expect(restored.clinicId, 'clinic_test');
      expect(restored.name, 'Reception PC');
      expect(restored.port, 47811);
      expect(restored.ips, ['192.168.1.15']);
      expect(restored.hasLanEndpoint, isTrue);
    });

    test('handles missing or malformed lan section gracefully', () {
      final restored = LanDevice.fromFirestore(
        id: 'dev_empty',
        clinicId: 'c1',
        data: {
          'uid': 'u1',
          'name': 'Dr Phone',
          'platform': 'android',
          'certPem': 'cert',
          'certSha256': 'b' * 64,
        },
      );

      expect(restored.ips, isEmpty);
      expect(restored.port, 0);
      expect(restored.hasLanEndpoint, isFalse);
    });
  });
}
