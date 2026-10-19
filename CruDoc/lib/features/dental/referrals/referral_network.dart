import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/core/services/callable_client.dart';
import 'package:doctor_management_app/core/services/demo_session_service.dart';
import 'package:doctor_management_app/core/services/encryption_key_manager.dart';
import 'package:doctor_management_app/core/services/field_cipher.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_models.dart';

// Referrals between doctors who both use CruDoc. The server side, and the
// reasoning behind who can see what, is functions/src/referrals.ts.

/// A file attached to a referral another doctor can open.
class SharedFile {
  const SharedFile({
    required this.name,
    required this.size,
    required this.contentType,
  });

  final String name;
  final int size;
  final String contentType;

  factory SharedFile.fromMap(Map<String, dynamic> m) => SharedFile(
    name: m['name'] as String? ?? '',
    size: (m['size'] as num?)?.toInt() ?? 0,
    contentType: m['contentType'] as String? ?? '',
  );
}

/// One referral sent from one doctor to another (`referral_shares/{id}`),
/// with its text decrypted. Written only by the server.
class ReferralShare {
  const ReferralShare({
    required this.id,
    required this.senderUid,
    required this.senderName,
    required this.senderSpecialty,
    required this.senderClinicName,
    required this.recipientUid,
    required this.recipientName,
    required this.recipientSpecialty,
    required this.localReferralId,
    required this.status,
    required this.urgency,
    required this.teeth,
    required this.patientName,
    required this.patientPhone,
    required this.patientGender,
    required this.patientAge,
    required this.reason,
    required this.findings,
    required this.question,
    required this.reply,
    required this.attachments,
    required this.history,
    required this.createdAt,
  });

  final String id;
  final String senderUid;
  final String senderName;
  final String senderSpecialty;
  final String senderClinicName;
  final String recipientUid;
  final String recipientName;
  final String recipientSpecialty;

  /// The sender's own referral record this was sent from.
  final String localReferralId;
  final ReferralStatus status;
  final ReferralUrgency urgency;
  final List<String> teeth;
  final String patientName;
  final String patientPhone;
  final String patientGender;
  final int? patientAge;
  final String reason;
  final String findings;
  final String question;
  final String reply;
  final List<SharedFile> attachments;
  final List<ReferralHistoryItem> history;
  final DateTime createdAt;

  factory ReferralShare.fromMap(String id, Map<String, dynamic> d) {
    final key = EncryptionKeyManager.shareKey(id);
    String text(Object? v) => FieldCipher.decryptWith(v as String?, key);
    String plain(String k) => d[k] is String ? d[k] as String : '';
    final patient = d['patient'] is Map
        ? Map<String, dynamic>.from(d['patient'] as Map)
        : const <String, dynamic>{};
    final created = d['createdAt'];
    final history = [
      for (final h in d['history'] as List? ?? const [])
        if (h is Map)
          ReferralHistoryItem(
            status: h['status'] as String? ?? '',
            at: DateTime.fromMillisecondsSinceEpoch(
              (h['at'] as num?)?.toInt() ?? 0,
            ),
            note: text(h['note']),
          ),
    ];
    return ReferralShare(
      id: id,
      senderUid: plain('senderUid'),
      senderName: plain('senderName'),
      senderSpecialty: plain('senderSpecialty'),
      senderClinicName: plain('senderClinicName'),
      recipientUid: plain('recipientUid'),
      recipientName: plain('recipientName'),
      recipientSpecialty: plain('recipientSpecialty'),
      localReferralId: plain('localReferralId'),
      status: ReferralStatus.fromName(plain('status')),
      urgency: ReferralUrgency.fromName(plain('urgency')),
      teeth: [for (final t in d['teeth'] as List? ?? const []) '$t'],
      patientName: text(patient['name']),
      patientPhone: text(patient['phone']),
      patientGender: patient['gender'] as String? ?? '',
      patientAge: (patient['age'] as num?)?.toInt(),
      reason: text(d['reason']),
      findings: text(d['findings']),
      question: text(d['question']),
      reply: text(d['reply']),
      attachments: [
        for (final a in d['attachments'] as List? ?? const [])
          if (a is Map) SharedFile.fromMap(Map<String, dynamic>.from(a)),
      ],
      history: history,
      // Just written, the server timestamp isn't back yet: the first
      // history entry was stamped at the same moment.
      createdAt: created is Timestamp
          ? created.toDate()
          : (history.isEmpty
                ? DateTime.fromMillisecondsSinceEpoch(0)
                : history.first.at),
    );
  }
}

/// A doctor on CruDoc: from a contact match or a directory search.
class CruDocDoctor {
  const CruDocDoctor({
    required this.uid,
    required this.name,
    this.specialty = '',
    this.clinicName = '',
    this.city = '',
    this.handle = '',
  });

  final String uid;
  final String name;
  final String specialty;
  final String clinicName;
  final String city;
  final String handle;

  factory CruDocDoctor.fromMap(Map<String, dynamic> m) => CruDocDoctor(
    uid: m['uid'] as String? ?? '',
    name: (m['name'] ?? m['displayName']) as String? ?? '',
    specialty: m['specialty'] as String? ?? '',
    clinicName: m['clinicName'] as String? ?? '',
    city: m['city'] as String? ?? '',
    handle: m['handle'] as String? ?? '',
  );
}

/// The signed-in doctor's own directory listing (`doctor_directory/{uid}`).
class DirectoryCard {
  const DirectoryCard({
    this.listed = false,
    this.handle = '',
    this.displayName = '',
    this.specialty = '',
    this.city = '',
    this.clinicName = '',
  });

  final bool listed;
  final String handle;
  final String displayName;
  final String specialty;
  final String city;
  final String clinicName;

  factory DirectoryCard.fromMap(Map<String, dynamic> m) => DirectoryCard(
    listed: m['listed'] == true,
    handle: m['handle'] as String? ?? '',
    displayName: m['displayName'] as String? ?? '',
    specialty: m['specialty'] as String? ?? '',
    city: m['city'] as String? ?? '',
    clinicName: m['clinicName'] as String? ?? '',
  );
}

/// What a step does to a referral another doctor sent or received.
enum ShareStep { accept, seen, complete, decline, reply, withdraw }

/// A referral action the server refused, with a message to show.
class ReferralNetworkException implements Exception {
  const ReferralNetworkException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Content types the server and storage.rules accept for an attachment.
const kShareableTypes = {
  '.pdf': 'application/pdf',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.dcm': 'application/dicom',
};

/// Largest file one referral may carry (storage.rules says the same).
const int kMaxShareBytes = 15 * 1024 * 1024;

/// The `referralNetwork` Cloud Function: one method per action. Every
/// method throws [ReferralNetworkException].
class ReferralNetworkApi {
  ReferralNetworkApi({CallableClient? client})
    : _client = client ?? CallableClient();

  static final ReferralNetworkApi instance = ReferralNetworkApi();

  /// Works on Windows too, where the Functions plugin doesn't exist.
  final CallableClient _client;

  /// A new share id; the attachments are uploaded under it before sending.
  static String newShareId() =>
      FirebaseFirestore.instance.collection('referral_shares').doc().id;

  /// Which of [contacts] are doctors on CruDoc, keyed by contact id.
  /// Contacts without a phone or email are not sent.
  Future<Map<String, CruDocDoctor>> matchContacts({
    required String clinicId,
    required List<ReferralContact> contacts,
  }) async {
    final out = <String, CruDocDoctor>{};
    final askable = [
      for (final c in contacts)
        if (c.phone.trim().isNotEmpty || c.email.trim().isNotEmpty) c,
    ];
    for (var i = 0; i < askable.length; i += 500) {
      final chunk = askable.sublist(
        i,
        i + 500 < askable.length ? i + 500 : askable.length,
      );
      final data = await _call('matchContacts', {
        'clinicId': clinicId,
        'contacts': [
          for (final c in chunk)
            {'id': c.id, 'phone': c.phone.trim(), 'email': c.email.trim()},
        ],
      });
      for (final m in data['matches'] as List? ?? const []) {
        if (m is! Map) continue;
        final map = Map<String, dynamic>.from(m);
        final id = map['id'];
        if (id is String) out[id] = CruDocDoctor.fromMap(map);
      }
    }
    return out;
  }

  Future<void> saveDirectoryProfile({
    required bool listed,
    required String handle,
    required String displayName,
    required String specialty,
    required String city,
    required String clinicName,
  }) => _call('saveDirectoryProfile', {
    'listed': listed,
    'handle': handle,
    'displayName': displayName,
    'specialty': specialty,
    'city': city,
    'clinicName': clinicName,
  });

  /// Uploads [paths] for [shareId] and returns the names they were stored
  /// under (one per file, made unique).
  Future<List<String>> uploadAttachments({
    required String uid,
    required String shareId,
    required List<String> paths,
  }) async {
    final names = <String>[];
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) {
        throw ReferralNetworkException(
          '"${p.basename(path)}" is no longer on this device.',
        );
      }
      final ext = p.extension(path).toLowerCase();
      final type = kShareableTypes[ext];
      if (type == null) {
        throw ReferralNetworkException(
          '"${p.basename(path)}" can\'t be sent in CruDoc: attach PDFs, '
          'photos or DICOM files.',
        );
      }
      if (file.lengthSync() > kMaxShareBytes) {
        throw ReferralNetworkException(
          '"${p.basename(path)}" is larger than 15 MB.',
        );
      }
      var name = p.basename(path).replaceAll(RegExp(r'[/\\]'), '_');
      if (name.length > 100) name = name.substring(name.length - 100);
      var n = 2;
      final base = p.basenameWithoutExtension(name);
      while (names.contains(name)) {
        name = '$base ($n)$ext';
        n++;
      }
      try {
        await FirebaseStorage.instance
            .ref('referral_uploads/$uid/$shareId/$name')
            .putFile(file, SettableMetadata(contentType: type));
      } on FirebaseException {
        throw ReferralNetworkException(
          'Couldn\'t upload "$name". Check the connection and try again.',
        );
      }
      names.add(name);
    }
    return names;
  }

  /// Sends [referral] for [patientName] to [recipientUid]; returns the share id.
  Future<String> send({
    required String clinicId,
    required String shareId,
    required String recipientUid,
    required DentalReferral referral,
    required String patientName,
    required String patientPhone,
    required String patientGender,
    required int? patientAge,
    required List<String> attachmentNames,
  }) async {
    final data = await _call('send', {
      'clinicId': clinicId,
      'shareId': shareId,
      'recipientUid': recipientUid,
      'consent': true,
      'patientId': referral.patientId,
      'localReferralId': referral.id,
      'patient': {
        'name': patientName,
        'phone': patientPhone,
        'gender': patientGender,
        'age': patientAge,
      },
      'reason': referral.reason,
      'findings': referral.findings,
      'question': referral.question,
      'urgency': referral.urgency.name,
      'teeth': referral.teeth,
      'attachments': [
        for (final n in attachmentNames) {'name': n},
      ],
    });
    return data['shareId'] as String? ?? shareId;
  }

  Future<ReferralStatus> update(
    String shareId,
    ShareStep step, {
    String note = '',
    String reply = '',
  }) async {
    final data = await _call('update', {
      'shareId': shareId,
      'step': step.name,
      if (note.isNotEmpty) 'note': note,
      if (reply.isNotEmpty) 'reply': reply,
    });
    return ReferralStatus.fromName(data['status'] as String?);
  }

  /// A link to one attached file, valid for a few minutes.
  Future<Uri> attachmentUrl(String shareId, String name) async {
    final data = await _call('attachmentUrl', {
      'shareId': shareId,
      'name': name,
    });
    return Uri.parse(data['url'] as String);
  }

  Future<Map<String, dynamic>> _call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    try {
      final raw = await _client.call('referralNetwork', {
        'action': action,
        ...data,
      });
      return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    } on CallableException catch (e) {
      debugPrint('[referralNetwork] $action failed: ${e.code} ${e.message}');
      throw ReferralNetworkException(_messageFor(e.code, e.message));
    } on ReferralNetworkException {
      rethrow;
    } catch (e) {
      debugPrint('[referralNetwork] $action failed: $e');
      throw const ReferralNetworkException(
        "Couldn't reach CruDoc. Check the connection and try again.",
      );
    }
  }

  static String _messageFor(String code, String message) => switch (code) {
    'resource-exhausted' ||
    'already-exists' ||
    'failed-precondition' ||
    'invalid-argument' ||
    'permission-denied' ||
    'not-found' => message.isEmpty ? "That didn't work. Try again." : message,
    'unauthenticated' => 'Sign in again to continue.',
    _ => "Couldn't reach CruDoc. Check the connection and try again.",
  };
}

Stream<List<ReferralShare>> _shares(String field, String uid) =>
    FirebaseFirestore.instance
        .collection('referral_shares')
        .where(field, isEqualTo: uid)
        .snapshots()
        .map(
          (snap) => [
            for (final d in snap.docs) ReferralShare.fromMap(d.id, d.data()),
          ],
        );

/// Referrals other doctors sent the signed-in doctor.
final incomingSharesProvider = StreamProvider<List<ReferralShare>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null || DemoSessionService.isDemoMode) {
    return Stream.value(const []);
  }
  return _shares('recipientUid', uid);
});

/// Referrals the signed-in doctor sent to other doctors in CruDoc.
final outgoingSharesProvider = StreamProvider<List<ReferralShare>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null || DemoSessionService.isDemoMode) {
    return Stream.value(const []);
  }
  return _shares('senderUid', uid);
});

/// The signed-in doctor's directory listing, or null before they make one.
final myDirectoryCardProvider = StreamProvider<DirectoryCard?>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null || DemoSessionService.isDemoMode) return Stream.value(null);
  return FirebaseFirestore.instance
      .collection('doctor_directory')
      .doc(uid)
      .snapshots()
      .map((s) => s.exists ? DirectoryCard.fromMap(s.data()!) : null);
});

/// Listed doctors matching every word of [query] (at least two letters).
Future<List<CruDocDoctor>> searchDirectory(
  String query, {
  String? selfUid,
}) async {
  final words = [
    for (final w in query.toLowerCase().split(RegExp(r'[^a-z0-9._]+')))
      if (w.length >= 2) w.length > 15 ? w.substring(0, 15) : w,
  ];
  if (words.isEmpty) return const [];
  final snap = await FirebaseFirestore.instance
      .collection('doctor_directory')
      .where('listed', isEqualTo: true)
      .where('searchTokens', arrayContains: words.first)
      .limit(25)
      .get();
  return [
    for (final d in snap.docs)
      if (d.id != selfUid &&
          words.every(
            (w) => (d.data()['searchTokens'] as List? ?? const []).contains(w),
          ))
        CruDocDoctor.fromMap({...d.data(), 'uid': d.id}),
  ];
}
