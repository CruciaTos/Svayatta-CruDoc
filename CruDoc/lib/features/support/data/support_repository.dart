import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/core/utils/device_info_helper.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/support/data/support_ticket.dart';

/// Tickets go straight to Firestore (`support_tickets`), not through the
/// offline sync: the Super Admin answers them there, so raising one needs
/// a connection.
class SupportRepository {
  SupportRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _tickets =>
      _db.collection('support_tickets');

  /// The signed-in person's tickets, newest first. Equality filter only,
  /// sorted here, so it needs no composite index.
  Stream<List<SupportTicket>> watchMine(String uid) => _tickets
      .where('doctorId', isEqualTo: uid)
      .snapshots()
      .map(
        (snap) =>
            snap.docs.map(SupportTicket.fromDoc).toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );

  /// Raises a ticket. Returns its id.
  Future<String> create({
    required SupportCategory category,
    required String subject,
    required String description,
    required String doctorName,
    String? clinicName,
    String? phone,
    bool blocking = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in to contact CruDoc.');
    final ref = _tickets.doc();
    await ref.set({
      'doctorId': user.uid,
      'doctorName': doctorName,
      'doctorEmail': user.email ?? '',
      'doctorPhone': ?(phone == null || phone.isEmpty ? null : phone),
      'clinicName': ?clinicName,
      'clinicId': ?ClinicSession.instance.tenantId,
      'subject': subject,
      'description': description,
      'category': category.name,
      'priority': blocking ? 'high' : 'medium',
      'status': SupportStatus.open.name,
      if (category == SupportCategory.featureRequest)
        'approval': SupportApproval.pending.name,
      'messages': const <Map<String, dynamic>>[],
      'isArchived': false,
      'adminUnread': true,
      'doctorUnread': false,
      'platform': DeviceInfoHelper.getPlatformKey(),
      'appVersion': await DeviceInfoHelper.getAppVersion(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Adds the doctor's reply. Replying on a resolved ticket reopens it.
  Future<void> reply(
    SupportTicket ticket, {
    required String content,
    required String senderName,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in to contact CruDoc.');
    final message = SupportMessage(
      senderId: user.uid,
      senderName: senderName,
      fromDoctor: true,
      content: content,
      timestamp: DateTime.now(),
    );
    await _tickets.doc(ticket.id).update({
      'messages': FieldValue.arrayUnion([message.toMap()]),
      if (ticket.status == SupportStatus.resolved)
        'status': SupportStatus.open.name,
      'adminUnread': true,
      'doctorUnread': false,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
  }

  /// The doctor has seen the CruDoc team's latest reply.
  Future<void> markRead(SupportTicket ticket) async {
    if (!ticket.doctorUnread) return;
    try {
      await _tickets.doc(ticket.id).update({'doctorUnread': false});
    } catch (e) {
      debugPrint('Support: could not mark ${ticket.id} read: $e');
    }
  }

  /// The doctor no longer needs this ticket.
  Future<void> withdraw(SupportTicket ticket) => _tickets
      .doc(ticket.id)
      .update({
        'status': SupportStatus.closed.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}

final supportRepositoryProvider = Provider<SupportRepository>(
  (ref) => SupportRepository(),
);

/// The signed-in person's tickets, live.
final myTicketsProvider = StreamProvider<List<SupportTicket>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(supportRepositoryProvider).watchMine(uid);
});

/// Tickets with a reply the doctor hasn't opened.
final unreadTicketCountProvider = Provider<int>((ref) {
  final tickets = ref.watch(myTicketsProvider).value ?? const [];
  return tickets.where((t) => t.doctorUnread).length;
});

/// Name, clinic and phone stamped on a new ticket, so the Super Admin
/// knows who wrote without looking them up.
({String name, String? clinic, String? phone}) supportSender(WidgetRef ref) {
  final user = ref.read(authStateProvider).value;
  final profile = ref.read(doctorProfileProvider).value;
  final identity = ref.read(doctorIdentityProvider);
  final phone = (profile?['phone'] ?? profile?['phoneNumber']) as String?;
  return (
    name:
        identity.fullName ??
        user?.displayName ??
        user?.email ??
        'CruDoc user',
    clinic: identity.clinicName,
    phone: phone ?? user?.phoneNumber,
  );
}
