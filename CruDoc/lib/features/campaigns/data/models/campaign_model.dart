import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'campaign_enums.dart';

/// Core model representing a clinical or informational patient campaign.
class CampaignModel {
  final String id;
  final String doctorId;
  final String title;
  final String message;
  final CampaignCategory category;
  final CampaignChannel channels;
  final AudienceType audienceType;
  final Map<String, dynamic> targetFilters;
  final List<String> selectedPatientIds;
  final String? mediaUrl;
  final CampaignStatus status;
  final DateTime? scheduledAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int totalRecipients;
  final int emailsSent;
  final int emailsFailed;
  final int whatsAppSent;
  final int whatsAppFailed;
  final Map<String, dynamic> metadata;

  const CampaignModel({
    required this.id,
    required this.doctorId,
    required this.title,
    required this.message,
    this.category = CampaignCategory.generalAnnouncement,
    this.channels = CampaignChannel.both,
    this.audienceType = AudienceType.all,
    this.targetFilters = const {},
    this.selectedPatientIds = const [],
    this.mediaUrl,
    this.status = CampaignStatus.draft,
    this.scheduledAt,
    required this.createdAt,
    required this.updatedAt,
    this.totalRecipients = 0,
    this.emailsSent = 0,
    this.emailsFailed = 0,
    this.whatsAppSent = 0,
    this.whatsAppFailed = 0,
    this.metadata = const {},
  });

  /// Total successful dispatches across enabled channels.
  int get totalSent => emailsSent + whatsAppSent;

  /// Total failed dispatches across enabled channels.
  int get totalFailed => emailsFailed + whatsAppFailed;

  /// Calculates the delivery success rate percentage (0.0 to 100.0).
  double get successRate {
    final totalAttempts = totalSent + totalFailed;
    if (totalAttempts == 0) {
      if (totalRecipients > 0 && status == CampaignStatus.completed) return 100.0;
      return 0.0;
    }
    return (totalSent / totalAttempts) * 100.0;
  }

  /// Formatted date of creation for UI cards.
  String get formattedCreatedAt {
    return DateFormat('MMM dd, yyyy • hh:mm a').format(createdAt);
  }

  /// Formatted scheduled date for UI cards if scheduled.
  String? get formattedScheduledAt {
    if (scheduledAt == null) return null;
    return DateFormat('MMM dd, yyyy • hh:mm a').format(scheduledAt!);
  }

  /// Factory constructor to parse from Firestore snapshot.
  factory CampaignModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return CampaignModel.fromMap(data, id: doc.id);
  }

  /// Factory constructor to parse from a Map.
  factory CampaignModel.fromMap(Map<String, dynamic> map, {required String id}) {
    DateTime parseDate(dynamic val, DateTime fallback) {
      if (val is Timestamp) return val.toDate();
      if (val is String) {
        final parsed = DateTime.tryParse(val);
        if (parsed != null) return parsed;
      }
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return fallback;
    }

    DateTime? parseNullableDate(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    return CampaignModel(
      id: id,
      doctorId: map['doctorId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      message: map['message'] as String? ?? '',
      category: CampaignCategory.fromString(map['category'] as String?),
      channels: CampaignChannel.fromString(map['channels'] as String?),
      audienceType: AudienceType.fromString(map['audienceType'] as String?),
      targetFilters: map['targetFilters'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(map['targetFilters'] as Map)
          : {},
      selectedPatientIds: (map['selectedPatientIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      mediaUrl: map['mediaUrl'] as String?,
      status: CampaignStatus.fromString(map['status'] as String?),
      scheduledAt: parseNullableDate(map['scheduledAt']),
      createdAt: parseDate(map['createdAt'], DateTime.now()),
      updatedAt: parseDate(map['updatedAt'], DateTime.now()),
      totalRecipients: (map['totalRecipients'] as num?)?.toInt() ?? 0,
      emailsSent: (map['emailsSent'] as num?)?.toInt() ?? 0,
      emailsFailed: (map['emailsFailed'] as num?)?.toInt() ?? 0,
      whatsAppSent: (map['whatsAppSent'] as num?)?.toInt() ?? 0,
      whatsAppFailed: (map['whatsAppFailed'] as num?)?.toInt() ?? 0,
      metadata: map['metadata'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : {},
    );
  }

  /// Converts this campaign instance to a Firestore-friendly Map.
  Map<String, dynamic> toMap() {
    return {
      'doctorId': doctorId,
      'title': title,
      'message': message,
      'category': category.name,
      'channels': channels.name,
      'audienceType': audienceType.name,
      'targetFilters': targetFilters,
      'selectedPatientIds': selectedPatientIds,
      'mediaUrl': mediaUrl,
      'status': status.name,
      'scheduledAt': scheduledAt != null ? Timestamp.fromDate(scheduledAt!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'totalRecipients': totalRecipients,
      'emailsSent': emailsSent,
      'emailsFailed': emailsFailed,
      'whatsAppSent': whatsAppSent,
      'whatsAppFailed': whatsAppFailed,
      'metadata': metadata,
    };
  }

  CampaignModel copyWith({
    String? id,
    String? doctorId,
    String? title,
    String? message,
    CampaignCategory? category,
    CampaignChannel? channels,
    AudienceType? audienceType,
    Map<String, dynamic>? targetFilters,
    List<String>? selectedPatientIds,
    String? mediaUrl,
    CampaignStatus? status,
    DateTime? scheduledAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? totalRecipients,
    int? emailsSent,
    int? emailsFailed,
    int? whatsAppSent,
    int? whatsAppFailed,
    Map<String, dynamic>? metadata,
  }) {
    return CampaignModel(
      id: id ?? this.id,
      doctorId: doctorId ?? this.doctorId,
      title: title ?? this.title,
      message: message ?? this.message,
      category: category ?? this.category,
      channels: channels ?? this.channels,
      audienceType: audienceType ?? this.audienceType,
      targetFilters: targetFilters ?? this.targetFilters,
      selectedPatientIds: selectedPatientIds ?? this.selectedPatientIds,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      status: status ?? this.status,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      totalRecipients: totalRecipients ?? this.totalRecipients,
      emailsSent: emailsSent ?? this.emailsSent,
      emailsFailed: emailsFailed ?? this.emailsFailed,
      whatsAppSent: whatsAppSent ?? this.whatsAppSent,
      whatsAppFailed: whatsAppFailed ?? this.whatsAppFailed,
      metadata: metadata ?? this.metadata,
    );
  }
}
