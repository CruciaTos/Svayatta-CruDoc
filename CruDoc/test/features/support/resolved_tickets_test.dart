import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/support/data/resolved_tickets.dart';

void main() {
  final at = DateTime(2026, 11, 3, 10);

  test('a resolved ticket reads as news for Notifications', () {
    final t = ResolvedTicket.fromDoc('t1', {
      'status': 'resolved',
      'category': 'bug',
      'subject': 'Bill does not print',
      'resolution': 'Fixed in 2.4.1',
      'resolvedAt': Timestamp.fromDate(at),
    })!;
    expect(t.title, 'Your issue is resolved');
    expect(t.detail, '"Bill does not print" · Fixed in 2.4.1');
    expect(t.resolvedAt, at);
  });

  test('feedback, with no note', () {
    final t = ResolvedTicket.fromDoc('t2', {
      'status': 'resolved',
      'category': 'feedback',
      'subject': 'Dark mode please',
      'updatedAt': Timestamp.fromDate(at),
    })!;
    expect(t.title, 'Your feedback was looked at');
    expect(t.detail, '"Dark mode please"');
    expect(t.resolvedAt, at);
  });

  test('tickets that are not resolved are left out', () {
    for (final status in ['open', 'inProgress', 'closed']) {
      expect(ResolvedTicket.fromDoc('t', {'status': status}), isNull);
    }
  });
}
