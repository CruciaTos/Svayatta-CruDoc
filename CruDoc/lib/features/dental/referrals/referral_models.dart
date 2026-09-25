import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';

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
  declined('Declined');

  const ReferralStatus(this.label);
  final String label;

  bool get isOpen => this != completed && this != declined;

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
          (json['at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
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
  });

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

  factory DentalReferral.fromRecord(DentalRecord r) {
    final rawHistory = r.data['history'] as List? ?? const [];
    final hist = rawHistory
        .map((h) => ReferralHistoryItem.fromJson(Map<String, dynamic>.from(h as Map)))
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
    );
  }

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
  final records = ref.watch(clinicRecordsProvider(RecKind.referralContact)).value ??
      const <DentalRecord>[];
  return records.map(ReferralContact.fromRecord).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
});

/// Provider for all referrals clinic-wide.
final allReferralsProvider = Provider<List<DentalReferral>>((ref) {
  final records = ref.watch(clinicRecordsProvider(RecKind.referral)).value ??
      const <DentalRecord>[];
  return records.map(DentalReferral.fromRecord).toList()
    ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
});
