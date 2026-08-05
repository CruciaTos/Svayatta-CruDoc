import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/enums.dart';

/// Model for support tickets from doctors.
class SupportTicketModel {
  final String id;
  final String doctorId;
  final String doctorName;
  final String doctorEmail;
  final String subject;
  final String description;
  final TicketCategory category;
  final TicketPriority priority;
  final TicketStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? assignedTo;
  final String? assignedToName;
  final List<TicketMessage> messages;
  final List<TicketNote> internalNotes;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? resolution;
  final bool isArchived;

  SupportTicketModel({
    required this.id,
    required this.doctorId,
    required this.doctorName,
    required this.doctorEmail,
    required this.subject,
    required this.description,
    this.category = TicketCategory.bug,
    this.priority = TicketPriority.medium,
    this.status = TicketStatus.open,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.assignedTo,
    this.assignedToName,
    List<TicketMessage>? messages,
    List<TicketNote>? internalNotes,
    this.resolvedAt,
    this.resolvedBy,
    this.resolution,
    this.isArchived = false,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        messages = messages ?? [],
        internalNotes = internalNotes ?? [];

  factory SupportTicketModel.fromJson(Map<String, dynamic> json, String id) {
    return SupportTicketModel(
      id: id,
      doctorId: json['doctorId'] as String? ?? '',
      doctorName: json['doctorName'] as String? ?? '',
      doctorEmail: json['doctorEmail'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: TicketCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => TicketCategory.bug,
      ),
      priority: TicketPriority.values.firstWhere(
        (e) => e.name == json['priority'],
        orElse: () => TicketPriority.medium,
      ),
      status: TicketStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => TicketStatus.open,
      ),
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      assignedTo: json['assignedTo'] as String?,
      assignedToName: json['assignedToName'] as String?,
      messages: (json['messages'] as List<dynamic>?)
              ?.map((e) => TicketMessage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      internalNotes: (json['internalNotes'] as List<dynamic>?)
              ?.map((e) => TicketNote.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      resolvedAt: (json['resolvedAt'] as Timestamp?)?.toDate(),
      resolvedBy: json['resolvedBy'] as String?,
      resolution: json['resolution'] as String?,
      isArchived: json['isArchived'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'doctorId': doctorId,
      'doctorName': doctorName,
      'doctorEmail': doctorEmail,
      'subject': subject,
      'description': description,
      'category': category.name,
      'priority': priority.name,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'assignedTo': assignedTo,
      'assignedToName': assignedToName,
      'messages': messages.map((e) => e.toJson()).toList(),
      'internalNotes': internalNotes.map((e) => e.toJson()).toList(),
      'resolvedAt': resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
      'resolvedBy': resolvedBy,
      'resolution': resolution,
      'isArchived': isArchived,
    };
  }
}

/// A message in a support ticket conversation.
class TicketMessage {
  final String senderId;
  final String senderName;
  final String senderRole; // 'doctor' or 'admin'
  final String content;
  final DateTime timestamp;
  final List<String>? attachmentUrls;

  TicketMessage({
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.content,
    DateTime? timestamp,
    this.attachmentUrls,
  }) : timestamp = timestamp ?? DateTime.now();

  factory TicketMessage.fromJson(Map<String, dynamic> json) {
    return TicketMessage(
      senderId: json['senderId'] as String? ?? '',
      senderName: json['senderName'] as String? ?? '',
      senderRole: json['senderRole'] as String? ?? '',
      content: json['content'] as String? ?? '',
      timestamp: (json['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      attachmentUrls: (json['attachmentUrls'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'content': content,
      'timestamp': Timestamp.fromDate(timestamp),
      'attachmentUrls': attachmentUrls,
    };
  }
}

/// Internal admin-only note on a support ticket.
class TicketNote {
  final String adminId;
  final String adminName;
  final String content;
  final DateTime timestamp;

  TicketNote({
    required this.adminId,
    required this.adminName,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory TicketNote.fromJson(Map<String, dynamic> json) {
    return TicketNote(
      adminId: json['adminId'] as String? ?? '',
      adminName: json['adminName'] as String? ?? '',
      content: json['content'] as String? ?? '',
      timestamp: (json['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'adminId': adminId,
      'adminName': adminName,
      'content': content,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}