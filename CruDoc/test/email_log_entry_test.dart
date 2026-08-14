import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/messaging/data/models/email_log_entry.dart';

void main() {
  group('EmailLogEntry', () {
    test('serializes and deserializes correctly', () {
      final now = DateTime(2026, 8, 14, 18, 30);
      final entry = EmailLogEntry(
        id: 'log_123',
        doctorId: 'doc_456',
        patientId: 'pat_789',
        visitId: 'vis_101',
        recipientEmail: 'patient@example.com',
        recipientName: 'Rohan Gupta',
        subject: 'Appointment Confirmation',
        status: EmailLogStatus.sent,
        gmailMessageId: 'gmail_msg_001',
        gmailThreadId: 'gmail_thr_001',
        senderEmail: 'doctor@gmail.com',
        attemptedAt: now,
        sentAt: now,
        createdAt: now,
      );

      final map = entry.toMap();
      final restored = EmailLogEntry.fromMap(map);

      expect(restored.id, entry.id);
      expect(restored.doctorId, entry.doctorId);
      expect(restored.patientId, entry.patientId);
      expect(restored.visitId, entry.visitId);
      expect(restored.recipientEmail, entry.recipientEmail);
      expect(restored.recipientName, entry.recipientName);
      expect(restored.status, EmailLogStatus.sent);
      expect(restored.isSent, isTrue);
      expect(restored.isPending, isFalse);
      expect(restored.isFailed, isFalse);
      expect(restored.gmailMessageId, 'gmail_msg_001');
      expect(restored.senderEmail, 'doctor@gmail.com');
    });

    test('handles fallback to pending for unknown status strings', () {
      final map = {
        'id': 'log_unknown',
        'doctorId': 'doc_1',
        'recipientEmail': 'p@example.com',
        'subject': 'Sub',
        'status': 'unknown_status_string',
        'senderEmail': 'd@example.com',
        'attemptedAt': 123456789,
        'createdAt': 123456789,
      };

      final entry = EmailLogEntry.fromMap(map);
      expect(entry.status, EmailLogStatus.pending);
      expect(entry.isPending, isTrue);
    });
  });
}
