import 'package:cloud_firestore/cloud_firestore.dart';

/// What a ticket is about. Names match the Super Admin's `TicketCategory`.
enum SupportCategory {
  bug('Report a problem', 'Problem'),
  featureRequest('Request a feature', 'Feature request'),
  feedback('Share feedback', 'Feedback'),
  complaint('Raise a complaint', 'Complaint');

  const SupportCategory(this.action, this.label);

  /// "Request a feature": the button that starts one.
  final String action;

  /// "Feature request": the tag on a ticket.
  final String label;

  static SupportCategory fromName(String? raw) => SupportCategory.values
      .firstWhere((c) => c.name == raw, orElse: () => SupportCategory.feedback);
}

/// Where a ticket stands. Names match the Super Admin's `TicketStatus`.
enum SupportStatus {
  open('Waiting for CruDoc'),
  inProgress('In progress'),
  resolved('Resolved'),
  closed('Closed');

  const SupportStatus(this.label);
  final String label;

  bool get isActive =>
      this == SupportStatus.open || this == SupportStatus.inProgress;

  static SupportStatus fromName(String? raw) => SupportStatus.values
      .firstWhere((s) => s.name == raw, orElse: () => SupportStatus.open);
}

/// The CruDoc team's decision on a feature request.
enum SupportApproval {
  pending('Under review'),
  approved('Approved'),
  declined('Not planned');

  const SupportApproval(this.label);
  final String label;

  static SupportApproval? fromName(String? raw) {
    for (final a in SupportApproval.values) {
      if (a.name == raw) return a;
    }
    return null;
  }
}

/// One message on a ticket: the doctor's or the CruDoc team's.
class SupportMessage {
  const SupportMessage({
    required this.senderId,
    required this.senderName,
    required this.fromDoctor,
    required this.content,
    required this.timestamp,
  });

  final String senderId;
  final String senderName;
  final bool fromDoctor;
  final String content;
  final DateTime timestamp;

  factory SupportMessage.fromMap(Map<String, dynamic> m) => SupportMessage(
    senderId: m['senderId'] as String? ?? '',
    senderName: m['senderName'] as String? ?? '',
    fromDoctor: m['senderRole'] == 'doctor',
    content: m['content'] as String? ?? '',
    timestamp: _date(m['timestamp']) ?? DateTime.now(),
  );

  /// Firestore can't put a server timestamp inside an array, so messages
  /// carry the device's time.
  Map<String, dynamic> toMap() => {
    'senderId': senderId,
    'senderName': senderName,
    'senderRole': fromDoctor ? 'doctor' : 'admin',
    'content': content,
    'timestamp': Timestamp.fromDate(timestamp),
  };
}

/// A ticket in `support_tickets`, as the doctor who raised it sees it.
/// The Super Admin app reads and answers the same documents.
class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.doctorId,
    required this.subject,
    required this.description,
    required this.category,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.approval,
    this.approvalNote,
    this.resolution,
    this.messages = const [],
    this.doctorUnread = false,
  });

  final String id;
  final String doctorId;
  final String subject;
  final String description;
  final SupportCategory category;
  final SupportStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Feature requests only.
  final SupportApproval? approval;

  /// Why it was approved or declined, written by the CruDoc team.
  final String? approvalNote;

  /// What the CruDoc team did, when they resolved it.
  final String? resolution;
  final List<SupportMessage> messages;

  /// The CruDoc team has written something the doctor hasn't opened yet.
  final bool doctorUnread;

  factory SupportTicket.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      SupportTicket.fromMap(doc.id, doc.data() ?? const {});

  factory SupportTicket.fromMap(String id, Map<String, dynamic> m) {
    final category = SupportCategory.fromName(m['category'] as String?);
    final created = _date(m['createdAt']) ?? DateTime.now();
    return SupportTicket(
      id: id,
      doctorId: m['doctorId'] as String? ?? '',
      subject: m['subject'] as String? ?? '',
      description: m['description'] as String? ?? '',
      category: category,
      status: SupportStatus.fromName(m['status'] as String?),
      createdAt: created,
      updatedAt: _date(m['updatedAt']) ?? created,
      approval: category == SupportCategory.featureRequest
          ? SupportApproval.fromName(m['approval'] as String?) ??
                SupportApproval.pending
          : null,
      approvalNote: m['approvalNote'] as String?,
      resolution: m['resolution'] as String?,
      messages: [
        for (final e in (m['messages'] as List<dynamic>? ?? const []))
          if (e is Map) SupportMessage.fromMap(Map<String, dynamic>.from(e)),
      ],
      doctorUnread: m['doctorUnread'] as bool? ?? false,
    );
  }
}

DateTime? _date(Object? v) => switch (v) {
  Timestamp t => t.toDate(),
  DateTime d => d,
  _ => null,
};
