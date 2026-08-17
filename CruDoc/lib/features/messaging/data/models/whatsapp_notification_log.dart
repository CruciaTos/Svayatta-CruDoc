import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle statuses for WhatsApp appointment notifications.
enum WhatsAppNotificationStatus {
  pending,
  sent,
  delivered,
  read,
  failed,
  skipped;

  String get value => name;

  static WhatsAppNotificationStatus fromValue(String? raw) {
    return WhatsAppNotificationStatus.values.firstWhere(
      (s) => s.name.toLowerCase() == (raw ?? '').trim().toLowerCase(),
      orElse: () => WhatsAppNotificationStatus.pending,
    );
  }
}

/// Audit and tracking model for WhatsApp appointment notifications.
///
/// Ensures compliance with CruDoc's architectural and privacy rules:
/// - Stored per doctor (`doctorId`) for strict multi-tenant isolation.
/// - Links to `visitId` (appointment ID) and `patientId`.
/// - Does NOT store sensitive medical notes, diagnoses, or prescriptions.
class WhatsAppNotificationLog {
  final String id;
  final String doctorId;
  final String patientId;
  final String visitId;
  final String recipientPhone;
  final String recipientName;
  final WhatsAppNotificationStatus status;
  final String? whatsappMessageId;
  final String? failureReason;
  final int attemptCount;
  final bool isMock;
  final DateTime attemptedAt;
  final DateTime? sentAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WhatsAppNotificationLog({
    required this.id,
    required this.doctorId,
    required this.patientId,
    required this.visitId,
    required this.recipientPhone,
    required this.recipientName,
    required this.status,
    this.whatsappMessageId,
    this.failureReason,
    this.attemptCount = 1,
    this.isMock = false,
    required this.attemptedAt,
    this.sentAt,
    this.deliveredAt,
    this.readAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPending => status == WhatsAppNotificationStatus.pending;
  bool get isSent => status == WhatsAppNotificationStatus.sent;
  bool get isDelivered => status == WhatsAppNotificationStatus.delivered;
  bool get isRead => status == WhatsAppNotificationStatus.read;
  bool get isFailed => status == WhatsAppNotificationStatus.failed;
  bool get isSkipped => status == WhatsAppNotificationStatus.skipped;
  bool get isCompleted => isSent || isDelivered || isRead;

  String get statusDisplayLabel {
    switch (status) {
      case WhatsAppNotificationStatus.pending:
        return 'Sending...';
      case WhatsAppNotificationStatus.sent:
        return 'Sent to WhatsApp';
      case WhatsAppNotificationStatus.delivered:
        return 'Delivered';
      case WhatsAppNotificationStatus.read:
        return 'Read by Patient';
      case WhatsAppNotificationStatus.failed:
        return 'Delivery Failed';
      case WhatsAppNotificationStatus.skipped:
        return 'Skipped (No Mobile)';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'doctorId': doctorId,
      'patientId': patientId,
      'visitId': visitId,
      'recipientPhone': recipientPhone,
      'recipientName': recipientName,
      'status': status.value,
      'whatsappMessageId': whatsappMessageId,
      'failureReason': failureReason,
      'attemptCount': attemptCount,
      'isMock': isMock ? 1 : 0,
      'attemptedAt': attemptedAt.millisecondsSinceEpoch,
      'sentAt': sentAt?.millisecondsSinceEpoch,
      'deliveredAt': deliveredAt?.millisecondsSinceEpoch,
      'readAt': readAt?.millisecondsSinceEpoch,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory WhatsAppNotificationLog.fromMap(Map<String, dynamic> map, {String? id}) {
    return WhatsAppNotificationLog(
      id: id ?? (map['id'] as String? ?? ''),
      doctorId: map['doctorId'] as String? ?? '',
      patientId: map['patientId'] as String? ?? '',
      visitId: (map['visitId'] ?? map['appointmentId']) as String? ?? '',
      recipientPhone: map['recipientPhone'] as String? ?? '',
      recipientName: map['recipientName'] as String? ?? '',
      status: WhatsAppNotificationStatus.fromValue(map['status'] as String?),
      whatsappMessageId: map['whatsappMessageId'] as String?,
      failureReason: map['failureReason'] as String?,
      attemptCount: (map['attemptCount'] as num?)?.toInt() ?? 1,
      isMock: (map['isMock'] == 1 || map['isMock'] == true),
      attemptedAt: _parseDateTime(map['attemptedAt']),
      sentAt: map['sentAt'] != null ? _parseDateTime(map['sentAt']) : null,
      deliveredAt: map['deliveredAt'] != null ? _parseDateTime(map['deliveredAt']) : null,
      readAt: map['readAt'] != null ? _parseDateTime(map['readAt']) : null,
      createdAt: _parseDateTime(map['createdAt']),
      updatedAt: _parseDateTime(map['updatedAt']),
    );
  }

  factory WhatsAppNotificationLog.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return WhatsAppNotificationLog.fromMap(data, id: doc.id);
  }

  WhatsAppNotificationLog copyWith({
    String? id,
    String? doctorId,
    String? patientId,
    String? visitId,
    String? recipientPhone,
    String? recipientName,
    WhatsAppNotificationStatus? status,
    String? whatsappMessageId,
    String? failureReason,
    int? attemptCount,
    bool? isMock,
    DateTime? attemptedAt,
    DateTime? sentAt,
    DateTime? deliveredAt,
    DateTime? readAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WhatsAppNotificationLog(
      id: id ?? this.id,
      doctorId: doctorId ?? this.doctorId,
      patientId: patientId ?? this.patientId,
      visitId: visitId ?? this.visitId,
      recipientPhone: recipientPhone ?? this.recipientPhone,
      recipientName: recipientName ?? this.recipientName,
      status: status ?? this.status,
      whatsappMessageId: whatsappMessageId ?? this.whatsappMessageId,
      failureReason: failureReason ?? this.failureReason,
      attemptCount: attemptCount ?? this.attemptCount,
      isMock: isMock ?? this.isMock,
      attemptedAt: attemptedAt ?? this.attemptedAt,
      sentAt: sentAt ?? this.sentAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime _parseDateTime(dynamic val) {
    if (val == null) return DateTime.now();
    if (val is Timestamp) return val.toDate();
    if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
    if (val is String) {
      final parsed = DateTime.tryParse(val);
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }
}
