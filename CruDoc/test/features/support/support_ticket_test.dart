import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:doctor_management_app/features/support/data/support_ticket.dart';
import 'package:flutter_test/flutter_test.dart';

SupportTicket _ticket(Map<String, dynamic> data) =>
    SupportTicket.fromMap('t1', data);

void main() {
  group('SupportTicket', () {
    test('reads the Super Admin\'s approval and note', () {
      final t = _ticket({
        'doctorId': 'doc-1',
        'subject': 'WhatsApp lab reports',
        'category': 'featureRequest',
        'status': 'inProgress',
        'approval': 'approved',
        'approvalNote': 'Planned for March.',
        'doctorUnread': true,
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 30)),
      });
      expect(t.approval, SupportApproval.approved);
      expect(t.approvalNote, 'Planned for March.');
      expect(t.doctorUnread, isTrue);
      expect(t.status.isActive, isTrue);
    });

    test('a feature request with no decision yet is under review', () {
      final t = _ticket({'category': 'featureRequest', 'status': 'open'});
      expect(t.approval, SupportApproval.pending);
    });

    test('problems and feedback have no approval', () {
      expect(_ticket({'category': 'bug'}).approval, isNull);
      expect(_ticket({'category': 'feedback'}).approval, isNull);
    });

    test('tells the doctor\'s messages from the team\'s', () {
      final t = _ticket({
        'category': 'bug',
        'messages': [
          {'senderRole': 'admin', 'content': 'Which printer?'},
          {'senderRole': 'doctor', 'content': 'HP'},
        ],
      });
      expect(t.messages.map((m) => m.fromDoctor), [false, true]);
    });

    test('a message is written with a plain timestamp, never a server one', () {
      final m = SupportMessage(
        senderId: 'doc-1',
        senderName: 'Dr. A',
        fromDoctor: true,
        content: 'hi',
        timestamp: DateTime(2026, 1, 2),
      );
      final map = m.toMap();
      expect(map['senderRole'], 'doctor');
      expect(map['timestamp'], isA<Timestamp>());
    });

    test('category and status names match the Super Admin\'s enums', () {
      // TicketCategory / TicketStatus in CrudocSuper-admin/lib/config/enums.dart.
      expect(
        SupportCategory.values.map((c) => c.name),
        containsAll(['bug', 'featureRequest', 'feedback', 'complaint']),
      );
      expect(SupportStatus.values.map((s) => s.name), [
        'open',
        'inProgress',
        'resolved',
        'closed',
      ]);
    });
  });
}
