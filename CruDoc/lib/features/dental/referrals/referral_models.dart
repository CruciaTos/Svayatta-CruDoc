import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_network.dart';

/// Direction of referral.
enum ReferralDirection {
  out('Sent', 'I\'m referring'),
  inbound('Received', 'Referred to me');

  const ReferralDirection(this.label, this.formLabel);
  final String label;
  final String formLabel;

  static ReferralDirection fromName(String? n) =>
      n == 'in' ? ReferralDirection.inbound : ReferralDirection.out;
  String get wireName => this == ReferralDirection.inbound ? 'in' : 'out';
}

/// Urgency level of referral.
enum ReferralUrgency {
  routine('Routine'),
  soon('Soon'),
  urgent('Urgent');

  const ReferralUrgency(this.label);
  final String label;

  static ReferralUrgency fromName(String? n) =>
      values.firstWhere((u) => u.name == n, orElse: () => routine);
}

/// Referral lifecycle status.
enum ReferralStatus {
  draft('Draft'),
  sent('Sent'),
  acknowledged('Acknowledged'),
  seen('Seen'),
  completed('Completed'),
  declined('Declined'),

  /// The referring doctor took back a referral sent in CruDoc.
  withdrawn('Withdrawn');

  const ReferralStatus(this.label);
  final String label;

  bool get isOpen => this != completed && this != declined && this != withdrawn;

  static ReferralStatus fromName(String? n) =>
      values.firstWhere((s) => s.name == n, orElse: () => draft);
}

/// One event in the referral's status history.
class ReferralHistoryItem {
  const ReferralHistoryItem({
    required this.status,
    required this.at,
    this.note = '',
  });

  final String status;
  final DateTime at;
  final String note;

  factory ReferralHistoryItem.fromJson(Map<String, dynamic> json) =>
      ReferralHistoryItem(
        status: json['status'] as String? ?? '',
        at: DateTime.fromMillisecondsSinceEpoch(
          (json['at'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        ),
        note: json['note'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'status': status,
    'at': at.millisecondsSinceEpoch,
    'note': note,
  };
}

/// External doctor, clinic or lab contact for referrals.
class ReferralContact {
  const ReferralContact({
    required this.id,
    required this.name,
    this.clinic = '',
    this.specialty = '',
    this.phone = '',
    this.email = '',
    this.city = '',
    this.notes = '',
    this.turnaroundDays,
    this.crudocUid = '',
    this.crudocName = '',
    this.crudocSpecialty = '',
    this.crudocId = '',
  });

  final String id;
  final String name;
  final String clinic;
  final String specialty;
  final String phone;
  final String email;
  final String city;
  final String notes;
  final int? turnaroundDays;

  /// The CruDoc account this contact was matched to (by phone or verified
  /// email, or picked from the directory); empty when they aren't on CruDoc.
  final String crudocUid;
  final String crudocName;
  final String crudocSpecialty;

  /// Their CruDoc ID ("K7Q9-2XMB") when they were found by it; empty
  /// otherwise (and on contacts saved before IDs were kept).
  final String crudocId;

  bool get onCruDoc => crudocUid.isNotEmpty;

  factory ReferralContact.fromRecord(DentalRecord r) => ReferralContact(
    id: r.id,
    name: r.str('name'),
    clinic: r.str('clinic'),
    specialty: r.str('specialty'),
    phone: r.str('phone'),
    email: r.str('email'),
    city: r.str('city'),
    notes: r.str('notes'),
    turnaroundDays: r.integer('turnaroundDays'),
    crudocUid: r.str('crudocUid'),
    crudocName: r.str('crudocName'),
    crudocSpecialty: r.str('crudocSpecialty'),
    crudocId: r.str('crudocId'),
  );

  Map<String, dynamic> toData() => {
    'name': name,
    'clinic': clinic,
    'specialty': specialty,
    'phone': phone,
    'email': email,
    'city': city,
    'notes': notes,
    if (turnaroundDays != null) 'turnaroundDays': turnaroundDays,
    'crudocUid': crudocUid,
    'crudocName': crudocName,
    'crudocSpecialty': crudocSpecialty,
    'crudocId': crudocId,
  };
}

/// One referral record between dentists.
class DentalReferral {
  const DentalReferral({
    required this.id,
    required this.patientId,
    required this.direction,
    required this.contactId,
    required this.contactName,
    required this.contactSpecialty,
    required this.reason,
    required this.teeth,
    required this.findings,
    required this.question,
    required this.urgency,
    required this.attachments,
    required this.status,
    required this.history,
    required this.reply,
    required this.recordedAt,
    required this.record,
    this.shareId = '',
    this.share,
  });

  /// Prefix of [record] ids made up for a referral another doctor sent
  /// that isn't filed against one of this clinic's patients yet.
  static const sharePrefix = 'share:';

  final String id;
  final String patientId;
  final ReferralDirection direction;
  final String contactId;
  final String contactName;
  final String contactSpecialty;
  final String reason;
  final List<String> teeth;
  final String findings;
  final String question;
  final ReferralUrgency urgency;
  final List<String> attachments;
  final ReferralStatus status;
  final List<ReferralHistoryItem> history;
  final String reply;
  final DateTime recordedAt;
  final DentalRecord record;

  /// Set once this referral went to (or came from) a doctor in CruDoc.
  final String shareId;

  /// That copy, live: for a referral sent in CruDoc the status, history and
  /// reply come from it, because the other doctor moves it forward.
  final ReferralShare? share;

  bool get isShared => shareId.isNotEmpty;

  /// Received in CruDoc and not yet filed against a patient of this clinic:
  /// there is no record of it here, only the other doctor's copy.
  bool get isUnfiledShare => record.id.startsWith(sharePrefix);

  factory DentalReferral.fromRecord(DentalRecord r) {
    final rawHistory = r.data['history'] as List? ?? const [];
    final hist = rawHistory
        .map(
          (h) =>
              ReferralHistoryItem.fromJson(Map<String, dynamic>.from(h as Map)),
        )
        .toList();
    final rawTeeth = r.data['teeth'] as List? ?? const [];
    final rawAttachments = r.data['attachments'] as List? ?? const [];

    return DentalReferral(
      id: r.id,
      patientId: r.patientId,
      direction: ReferralDirection.fromName(r.str('direction')),
      contactId: r.str('contactId'),
      contactName: r.str('contactName'),
      contactSpecialty: r.str('contactSpecialty'),
      reason: r.str('reason'),
      teeth: rawTeeth.map((e) => '$e').toList(),
      findings: r.str('findings'),
      question: r.str('question'),
      urgency: ReferralUrgency.fromName(r.str('urgency')),
      attachments: rawAttachments.map((e) => '$e').toList(),
      status: ReferralStatus.fromName(r.str('status')),
      history: hist,
      reply: r.str('reply'),
      recordedAt: r.recordedAt,
      record: r,
      shareId: r.str('shareId'),
    );
  }

  /// A referral another doctor sent, as this clinic sees it before it is
  /// filed against one of its patients.
  factory DentalReferral.fromShare(ReferralShare s) {
    final record = DentalRecord(
      id: '$sharePrefix${s.id}',
      patientId: '',
      kind: RecKind.referral,
      data: {
        'direction': ReferralDirection.inbound.wireName,
        'contactName': s.senderName,
        'contactSpecialty': s.senderSpecialty,
        'reason': s.reason,
        'teeth': s.teeth,
        'findings': s.findings,
        'question': s.question,
        'urgency': s.urgency.name,
        'attachments': const <String>[],
        'status': s.status.name,
        'history': [for (final h in s.history) h.toJson()],
        'reply': s.reply,
        'shareId': s.id,
      },
      recordedAt: s.createdAt,
      createdAt: s.createdAt,
      updatedAt: s.createdAt,
    );
    return DentalReferral.fromRecord(record).withShare(s);
  }

  /// This referral with the live status, history and reply of [s].
  DentalReferral withShare(ReferralShare s) => DentalReferral(
    id: id,
    patientId: patientId,
    direction: direction,
    contactId: contactId,
    contactName: contactName,
    contactSpecialty: contactSpecialty,
    reason: reason,
    teeth: teeth,
    findings: findings,
    question: question,
    urgency: urgency,
    attachments: attachments,
    status: s.status,
    history: s.history,
    reply: s.reply,
    recordedAt: recordedAt,
    record: record,
    shareId: s.id,
    share: s,
  );

  Map<String, dynamic> toData() => {
    'direction': direction.wireName,
    'contactId': contactId,
    'contactName': contactName,
    'contactSpecialty': contactSpecialty,
    'reason': reason,
    'teeth': teeth,
    'findings': findings,
    'question': question,
    'urgency': urgency.name,
    'attachments': attachments,
    'status': status.name,
    'history': history.map((h) => h.toJson()).toList(),
    'reply': reply,
  };

  DentalReferral copyWith({
    ReferralDirection? direction,
    String? contactId,
    String? contactName,
    String? contactSpecialty,
    String? reason,
    List<String>? teeth,
    String? findings,
    String? question,
    ReferralUrgency? urgency,
    List<String>? attachments,
    ReferralStatus? status,
    List<ReferralHistoryItem>? history,
    String? reply,
    DateTime? recordedAt,
  }) {
    final nextData = {
      'direction': (direction ?? this.direction).wireName,
      'contactId': contactId ?? this.contactId,
      'contactName': contactName ?? this.contactName,
      'contactSpecialty': contactSpecialty ?? this.contactSpecialty,
      'reason': reason ?? this.reason,
      'teeth': teeth ?? this.teeth,
      'findings': findings ?? this.findings,
      'question': question ?? this.question,
      'urgency': (urgency ?? this.urgency).name,
      'attachments': attachments ?? this.attachments,
      'status': (status ?? this.status).name,
      'history': (history ?? this.history).map((h) => h.toJson()).toList(),
      'reply': reply ?? this.reply,
      if (shareId.isNotEmpty) 'shareId': shareId,
    };
    final nextRecord = record.copyWith(
      data: nextData,
      recordedAt: recordedAt ?? this.recordedAt,
    );
    return DentalReferral.fromRecord(nextRecord);
  }
}

/// Provider for all referral contacts clinic-wide.
final referralContactsProvider = Provider<List<ReferralContact>>((ref) {
  final records =
      ref.watch(clinicRecordsProvider(RecKind.referralContact)).value ??
      const <DentalRecord>[];
  return records.map(ReferralContact.fromRecord).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
});

/// Provider for all referrals clinic-wide, together with the ones sent to
/// and received from other doctors in CruDoc. A share stream that failed
/// adds nothing here: [referralSharesErrorProvider] says why, so the
/// screen doesn't just look empty.
final allReferralsProvider = Provider<List<DentalReferral>>((ref) {
  final records =
      ref.watch(clinicRecordsProvider(RecKind.referral)).value ??
      const <DentalRecord>[];
  return mergeSharedReferrals(
    records.map(DentalReferral.fromRecord).toList(),
    outgoing: ref.watch(outgoingSharesProvider).value ?? const [],
    incoming: ref.watch(incomingSharesProvider).value ?? const [],
  );
});

/// Why the referrals sent to or from this doctor in CruDoc couldn't be
/// loaded (a Firestore error code and message), or null when they could.
/// Retry with `ref.invalidate` on [incomingSharesProvider] and
/// [outgoingSharesProvider].
final referralSharesErrorProvider = Provider<String?>((ref) {
  final incoming = ref.watch(incomingSharesProvider);
  final outgoing = ref.watch(outgoingSharesProvider);
  final e = incoming.error ?? outgoing.error;
  if (e == null) return null;
  if (e is FirebaseException) {
    final message = e.message ?? '';
    return message.isEmpty ? e.code : '$message (${e.code})';
  }
  return '$e';
});

/// [local] referrals with the live state of those sent in CruDoc laid over
/// them, plus every referral received in CruDoc that isn't filed here yet.
/// Newest first.
List<DentalReferral> mergeSharedReferrals(
  List<DentalReferral> local, {
  required List<ReferralShare> outgoing,
  required List<ReferralShare> incoming,
}) {
  final shares = {
    for (final s in [...outgoing, ...incoming]) s.id: s,
  };
  final filed = <String>{};
  final out = <DentalReferral>[];
  for (final r in local) {
    final s = r.isShared ? shares[r.shareId] : null;
    if (s != null) filed.add(s.id);
    out.add(s == null ? r : r.withShare(s));
  }
  for (final s in incoming) {
    if (!filed.contains(s.id)) out.add(DentalReferral.fromShare(s));
  }
  return out..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
}

/// Provider for contacts that are dental laboratories (PR2).
final labPartnersProvider = Provider<List<ReferralContact>>((ref) {
  final contacts = ref.watch(referralContactsProvider);
  return contacts
      .where(
        (c) =>
            c.specialty.toLowerCase().contains('lab') ||
            c.name.toLowerCase().contains('lab'),
      )
      .toList();
});
