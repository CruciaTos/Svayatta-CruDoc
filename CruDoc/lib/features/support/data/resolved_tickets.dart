import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/services/auth_providers.dart';

/// A bug report or feedback of this doctor's that the Super Admin resolved.
@immutable
class ResolvedTicket {
  const ResolvedTicket({
    required this.id,
    required this.subject,
    required this.resolvedAt,
    this.category = 'bug',
    this.resolution = '',
  });

  final String id;
  final String subject;
  final String category;
  final String resolution;
  final DateTime resolvedAt;

  bool get isFeedback => category == 'feedback';

  /// Same wording as the push (functions/src/support_tickets.ts).
  String get title =>
      isFeedback ? 'Your feedback was looked at' : 'Your issue is resolved';

  /// What they reported, then the Super Admin's note when there is one.
  String get detail => [
    if (subject.trim().isNotEmpty) '"${subject.trim()}"',
    if (resolution.trim().isNotEmpty) resolution.trim(),
  ].join(' · ');

  /// Null for a ticket that isn't resolved.
  static ResolvedTicket? fromDoc(String id, Map<String, dynamic> d) {
    if (d['status'] != 'resolved') return null;
    final at = d['resolvedAt'] ?? d['updatedAt'];
    return ResolvedTicket(
      id: id,
      subject: d['subject'] as String? ?? '',
      category: d['category'] as String? ?? 'bug',
      resolution: d['resolution'] as String? ?? '',
      // Just resolved and not yet back from the server: now.
      resolvedAt: at is Timestamp ? at.toDate() : DateTime.now(),
    );
  }
}

/// How long a resolved ticket stays in Notifications.
const resolvedTicketShownFor = Duration(days: 14);

/// This doctor's tickets resolved in the last [resolvedTicketShownFor],
/// newest first, for the Notifications panel and its bell's dot.
final resolvedTicketsProvider = StreamProvider<List<ResolvedTicket>>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('support_tickets')
      .where('doctorId', isEqualTo: uid)
      .snapshots()
      .map((snap) {
        final since = DateTime.now().subtract(resolvedTicketShownFor);
        final list =
            [for (final d in snap.docs) ?ResolvedTicket.fromDoc(d.id, d.data())]
                .where((t) => t.resolvedAt.isAfter(since))
                .toList()
              ..sort((a, b) => b.resolvedAt.compareTo(a.resolvedAt));
        return list;
      });
});
