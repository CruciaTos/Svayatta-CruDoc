import 'package:flutter/foundation.dart';

/// Status of an email dispatch attempt in the audit log.
enum EmailLogStatus {
  pending,
  sent,
  failed;

  String get value => name;

  static EmailLogStatus fromValue(String? raw) {
    return EmailLogStatus.values.firstWhere(
      (s) => s.value == raw,
      orElse: () => EmailLogStatus.pending,
    );
  }
}

/// Audit log record for every email dispatch attempt.
///
/// Designed with strict medical data minimization:
/// - No clinical email body or patient notes are stored here.
/// - No attachment filenames or PHI are persisted in plain log tables.
/// - [failureReason] stores high-level error codes rather than raw backend payloads.
/// - Scoped strictly to [doctorId] for multi-tenant isolation.
@immutable
class EmailLogEntry {
  final String id;
  final String doctorId;
  final String? patientId;
  final String? visitId;
  final String recipientEmail;
  final String? recipientName;
  final String subject;
  final EmailLogStatus status;
  final String? gmailMessageId;
  final String? gmailThreadId;
  final String? failureReason;
  final String senderEmail;
  final DateTime attemptedAt;
  final DateTime? sentAt;
  final DateTime createdAt;

  const EmailLogEntry({
    required this.id,
    required this.doctorId,
    this.patientId,
    this.visitId,
    required this.recipientEmail,
    this.recipientName,
    required this.subject,
    required this.status,
    this.gmailMessageId,
    this.gmailThreadId,
    this.failureReason,
    required this.senderEmail,
    required this.attemptedAt,
    this.sentAt,
    required this.createdAt,
  });

  bool get isPending => status == EmailLogStatus.pending;
  bool get isSent => status == EmailLogStatus.sent;
  bool get isFailed => status == EmailLogStatus.failed;

  EmailLogEntry copyWith({
    String? id,
    String? doctorId,
    String? patientId,
    String? visitId,
    String? recipientEmail,
    String? recipientName,
    String? subject,
    EmailLogStatus? status,
    String? gmailMessageId,
    String? gmailThreadId,
    String? failureReason,
    String? senderEmail,
    DateTime? attemptedAt,
    DateTime? sentAt,
    DateTime? createdAt,
  }) {
    return EmailLogEntry(
      id: id ?? this.id,
      doctorId: doctorId ?? this.doctorId,
      patientId: patientId ?? this.patientId,
      visitId: visitId ?? this.visitId,
      recipientEmail: recipientEmail ?? this.recipientEmail,
      recipientName: recipientName ?? this.recipientName,
      subject: subject ?? this.subject,
      status: status ?? this.status,
      gmailMessageId: gmailMessageId ?? this.gmailMessageId,
      gmailThreadId: gmailThreadId ?? this.gmailThreadId,
      failureReason: failureReason ?? this.failureReason,
      senderEmail: senderEmail ?? this.senderEmail,
      attemptedAt: attemptedAt ?? this.attemptedAt,
      sentAt: sentAt ?? this.sentAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'doctorId': doctorId,
      'patientId': patientId,
      'visitId': visitId,
      'recipientEmail': recipientEmail,
      'recipientName': recipientName,
      'subject': subject,
      'status': status.value,
      'gmailMessageId': gmailMessageId,
      'gmailThreadId': gmailThreadId,
      'failureReason': failureReason,
      'senderEmail': senderEmail,
      'attemptedAt': attemptedAt.millisecondsSinceEpoch,
      'sentAt': sentAt?.millisecondsSinceEpoch,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory EmailLogEntry.fromMap(Map<String, dynamic> map) {
    return EmailLogEntry(
      id: (map['id'] ?? '').toString(),
      doctorId: (map['doctorId'] ?? '').toString(),
      patientId: map['patientId'] as String?,
      visitId: map['visitId'] as String?,
      recipientEmail: (map['recipientEmail'] ?? '').toString(),
      recipientName: map['recipientName'] as String?,
      subject: (map['subject'] ?? '').toString(),
      status: EmailLogStatus.fromValue(map['status'] as String?),
      gmailMessageId: map['gmailMessageId'] as String?,
      gmailThreadId: map['gmailThreadId'] as String?,
      failureReason: map['failureReason'] as String?,
      senderEmail: (map['senderEmail'] ?? '').toString(),
      attemptedAt: map['attemptedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['attemptedAt'] as int)
          : DateTime.now(),
      sentAt: map['sentAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['sentAt'] as int)
          : null,
      createdAt: map['createdAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int)
          : DateTime.now(),
    );
  }
}
