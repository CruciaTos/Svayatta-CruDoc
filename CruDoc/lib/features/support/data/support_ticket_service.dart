import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:doctor_management_app/core/utils/device_info_helper.dart';

/// What the person is sending.
enum SupportTicketKind {
  bug('bug', 'Bug'),
  feedback('feedback', 'Feedback');

  const SupportTicketKind(this.key, this.label);

  /// Stored in `support_tickets/{id}.category` (the Super Admin's
  /// TicketCategory names).
  final String key;
  final String label;
}

/// How a send ended.
enum SupportTicketOutcome {
  /// The server has it.
  sent,

  /// No connection yet: Firestore keeps it and sends it when back online.
  queued,
}

/// Who is sending, read from the session by the caller.
class SupportTicketSender {
  const SupportTicketSender({
    this.name,
    this.clinicId,
    this.clinicName,
    this.role,
  });

  final String? name;
  final String? clinicId;
  final String? clinicName;
  final String? role;
}

/// Bug reports and feedback from inside the app, for the CruDoc team.
///
/// One document per report in `support_tickets`. The rules let the sender
/// create and read their own and let only the Super Admin read them all
/// (see firestore.rules). The field names are the Super Admin console's
/// (`SupportTicketModel` in CrudocSuper-admin), so a report shows there as
/// any other ticket:
///
/// - `doctorId`: the sender's uid (the rules require it to match)
/// - `doctorName`, `doctorEmail`, `doctorPhone`: the sender
/// - `category`: `bug` or `feedback`
/// - `subject`: the first line, shortened; `description`: all of it
///   (at most [maxMessage] characters)
/// - `priority`: `medium`; `status`: `open`; `isArchived`: false
/// - `createdAt`, `updatedAt`: server time
///
/// Extra context for the team: `clinicId`, `clinicName`, `role`,
/// `platform` (android, ios, windows, web, ...), `device`, `appVersion`.
class SupportTicketService {
  SupportTicketService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestoreOverride = firestore,
      _authOverride = auth;

  // Looked up on first use, so a subclass in tests needs no Firebase.
  final FirebaseFirestore? _firestoreOverride;
  final FirebaseAuth? _authOverride;
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  static const collection = 'support_tickets';
  static const maxMessage = 4000;

  /// How long to wait for the server before calling it queued.
  static const serverWait = Duration(seconds: 12);

  static const maxSubject = 80;

  /// The ticket's title: the first line of [message], cut at a word near
  /// [maxSubject] characters.
  static String subjectOf(String message) {
    final first = message.trim().split('\n').first.trim();
    if (first.length <= maxSubject) return first;
    var cut = first.substring(0, maxSubject);
    final space = cut.lastIndexOf(' ');
    if (space > maxSubject ~/ 2) cut = cut.substring(0, space);
    return '${cut.trimRight()}…';
  }

  /// The document for one report. Kept apart from [submit] so it can be
  /// checked without Firebase.
  static Map<String, Object?> buildTicket({
    required String uid,
    required SupportTicketKind kind,
    required String message,
    String? email,
    String? phone,
    SupportTicketSender sender = const SupportTicketSender(),
    required String platform,
    required String device,
    required String appVersion,
    Object? now,
  }) {
    String? clean(String? s) {
      final t = s?.trim();
      return t == null || t.isEmpty ? null : t;
    }

    final text = message.trim();
    final at = now ?? FieldValue.serverTimestamp();
    return {
      'doctorId': uid,
      'doctorName': clean(sender.name) ?? clean(email) ?? 'Unknown',
      'doctorEmail': clean(email) ?? '',
      'doctorPhone': clean(phone),
      'category': kind.key,
      'subject': subjectOf(text),
      'description': text,
      'priority': 'medium',
      'status': 'open',
      'isArchived': false,
      'createdAt': at,
      'updatedAt': at,
      'clinicId': clean(sender.clinicId),
      'clinicName': clean(sender.clinicName),
      'role': clean(sender.role),
      'platform': platform,
      'device': device,
      'appVersion': appVersion,
    };
  }

  /// Sends one report. Throws [StateError] when signed out or the message is
  /// empty or too long, and the Firestore error if the server refuses it.
  Future<SupportTicketOutcome> submit({
    required SupportTicketKind kind,
    required String message,
    SupportTicketSender sender = const SupportTicketSender(),
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in to send a report.');
    final text = message.trim();
    if (text.isEmpty) throw StateError('Write a few words first.');
    if (text.length > maxMessage) {
      throw StateError('Keep it under $maxMessage characters.');
    }

    final ref = _firestore.collection(collection).doc();
    final write = ref.set(
      buildTicket(
        uid: user.uid,
        kind: kind,
        message: text,
        email: user.email,
        phone: user.phoneNumber,
        sender: sender,
        platform: DeviceInfoHelper.getPlatformKey(),
        device: await DeviceInfoHelper.getDeviceDisplayName(),
        appVersion: await DeviceInfoHelper.getAppVersion(),
      ),
    );
    try {
      await write.timeout(serverWait);
      return SupportTicketOutcome.sent;
    } on TimeoutException {
      // Still in Firestore's queue; it goes out when the connection is back.
      unawaited(write.catchError((Object _) {}));
      return SupportTicketOutcome.queued;
    }
  }
}
