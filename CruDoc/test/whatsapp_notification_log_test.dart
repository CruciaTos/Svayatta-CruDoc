import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/messaging/data/models/whatsapp_notification_log.dart';

void main() {
  group('WhatsAppNotificationLog Model Tests', () {
    final now = DateTime(2026, 8, 17, 10, 0, 0);

    test('serializes and deserializes accurately with all metadata fields', () {
      final log = WhatsAppNotificationLog(
        id: 'log-123',
        doctorId: 'doctor-abc',
        patientId: 'patient-456',
        visitId: 'visit-789',
        recipientPhone: '919876543210',
        recipientName: 'Rahul Sharma',
        status: WhatsAppNotificationStatus.delivered,
        whatsappMessageId: 'wamid.HBgL123456',
        failureReason: null,
        attemptCount: 1,
        isMock: true,
        attemptedAt: now,
        sentAt: now.add(const Duration(seconds: 2)),
        deliveredAt: now.add(const Duration(seconds: 10)),
        readAt: now.add(const Duration(seconds: 30)),
        createdAt: now,
        updatedAt: now.add(const Duration(seconds: 30)),
      );

      final map = log.toMap();
      expect(map['id'], equals('log-123'));
      expect(map['doctorId'], equals('doctor-abc'));
      expect(map['patientId'], equals('patient-456'));
      expect(map['visitId'], equals('visit-789'));
      expect(map['recipientPhone'], equals('919876543210'));
      expect(map['status'], equals('delivered'));
      expect(map['whatsappMessageId'], equals('wamid.HBgL123456'));
      expect(map['isMock'], equals(1));

      final deserialized = WhatsAppNotificationLog.fromMap(map);
      expect(deserialized.id, equals(log.id));
      expect(deserialized.doctorId, equals(log.doctorId));
      expect(deserialized.status, equals(WhatsAppNotificationStatus.delivered));
      expect(deserialized.isDelivered, isTrue);
      expect(deserialized.isCompleted, isTrue);
      expect(deserialized.isMock, isTrue);
      expect(deserialized.statusDisplayLabel, equals('Delivered'));
    });

    test('status helper getters function correctly', () {
      final pendingLog = WhatsAppNotificationLog(
        id: 'log-1',
        doctorId: 'doc-1',
        patientId: 'p-1',
        visitId: 'v-1',
        recipientPhone: '919876543210',
        recipientName: 'Test',
        status: WhatsAppNotificationStatus.pending,
        attemptedAt: now,
        createdAt: now,
        updatedAt: now,
      );
      expect(pendingLog.isPending, isTrue);
      expect(pendingLog.isCompleted, isFalse);

      final skippedLog = pendingLog.copyWith(status: WhatsAppNotificationStatus.skipped);
      expect(skippedLog.isSkipped, isTrue);
      expect(skippedLog.statusDisplayLabel, contains('Skipped'));

      final failedLog = pendingLog.copyWith(
        status: WhatsAppNotificationStatus.failed,
        failureReason: 'unregistered_number',
      );
      expect(failedLog.isFailed, isTrue);
      expect(failedLog.failureReason, equals('unregistered_number'));
    });

    test('fallback to pending for unrecognized status string', () {
      expect(WhatsAppNotificationStatus.fromValue('unknown_status'), equals(WhatsAppNotificationStatus.pending));
      expect(WhatsAppNotificationStatus.fromValue(null), equals(WhatsAppNotificationStatus.pending));
      expect(WhatsAppNotificationStatus.fromValue('SENT'), equals(WhatsAppNotificationStatus.sent));
      expect(WhatsAppNotificationStatus.fromValue('read'), equals(WhatsAppNotificationStatus.read));
    });
  });
}
