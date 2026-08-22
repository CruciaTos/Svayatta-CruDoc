import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'campaign_enums.dart';

/// Represents a single recipient's delivery status and diagnostic log in a campaign.
class CampaignRecipientLog {
  final String id;
  final String campaignId;
  final String doctorId;
  final String patientId;
  final String patientName;
  final String email;
  final String phone;
  final RecipientDeliveryStatus emailStatus;
  final RecipientDeliveryStatus whatsAppStatus;
  final String? emailMessageId;
  final String? whatsAppMessageId;
  final String? emailError;
  final String? whatsAppError;
  final DateTime dispatchedAt;
  final DateTime updatedAt;

  const CampaignRecipientLog({
    required this.id,
    required this.campaignId,
    required this.doctorId,
    required this.patientId,
    required this.patientName,
    this.email = '',
    this.phone = '',
    this.emailStatus = RecipientDeliveryStatus.queued,
    this.whatsAppStatus = RecipientDeliveryStatus.queued,
    this.emailMessageId,
    this.whatsAppMessageId,
    this.emailError,
    this.whatsAppError,
    required this.dispatchedAt,
    required this.updatedAt,
  });

  /// Overall recipient delivery state.
  bool get isSuccessful =>
      emailStatus == RecipientDeliveryStatus.sent ||
      emailStatus == RecipientDeliveryStatus.delivered ||
      whatsAppStatus == RecipientDeliveryStatus.sent ||
      whatsAppStatus == RecipientDeliveryStatus.delivered;

  bool get hasFailed =>
      emailStatus == RecipientDeliveryStatus.failed ||
      whatsAppStatus == RecipientDeliveryStatus.failed;

  String get formattedDispatchedAt {
    return DateFormat('MMM dd, hh:mm a').format(dispatchedAt);
  }

  factory CampaignRecipientLog.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return CampaignRecipientLog.fromMap(data, id: doc.id);
  }

  factory CampaignRecipientLog.fromMap(Map<String, dynamic> map,
      {required String id}) {
    DateTime parseDate(dynamic val, DateTime fallback) {
      if (val is Timestamp) return val.toDate();
      if (val is String) {
        final parsed = DateTime.tryParse(val);
        if (parsed != null) return parsed;
      }
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return fallback;
    }

    return CampaignRecipientLog(
      id: id,
      campaignId: map['campaignId'] as String? ?? '',
      doctorId: map['doctorId'] as String? ?? '',
      patientId: map['patientId'] as String? ?? '',
      patientName: map['patientName'] as String? ?? '',
      email: map['email'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      emailStatus: RecipientDeliveryStatus.fromString(map['emailStatus'] as String?),
      whatsAppStatus:
          RecipientDeliveryStatus.fromString(map['whatsAppStatus'] as String?),
      emailMessageId: map['emailMessageId'] as String?,
      whatsAppMessageId: map['whatsAppMessageId'] as String?,
      emailError: map['emailError'] as String?,
      whatsAppError: map['whatsAppError'] as String?,
      dispatchedAt: parseDate(map['dispatchedAt'], DateTime.now()),
      updatedAt: parseDate(map['updatedAt'], DateTime.now()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'campaignId': campaignId,
      'doctorId': doctorId,
      'patientId': patientId,
      'patientName': patientName,
      'email': email,
      'phone': phone,
      'emailStatus': emailStatus.name,
      'whatsAppStatus': whatsAppStatus.name,
      'emailMessageId': emailMessageId,
      'whatsAppMessageId': whatsAppMessageId,
      'emailError': emailError,
      'whatsAppError': whatsAppError,
      'dispatchedAt': Timestamp.fromDate(dispatchedAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  CampaignRecipientLog copyWith({
    String? id,
    String? campaignId,
    String? doctorId,
    String? patientId,
    String? patientName,
    String? email,
    String? phone,
    RecipientDeliveryStatus? emailStatus,
    RecipientDeliveryStatus? whatsAppStatus,
    String? emailMessageId,
    String? whatsAppMessageId,
    String? emailError,
    String? whatsAppError,
    DateTime? dispatchedAt,
    DateTime? updatedAt,
  }) {
    return CampaignRecipientLog(
      id: id ?? this.id,
      campaignId: campaignId ?? this.campaignId,
      doctorId: doctorId ?? this.doctorId,
      patientId: patientId ?? this.patientId,
      patientName: patientName ?? this.patientName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      emailStatus: emailStatus ?? this.emailStatus,
      whatsAppStatus: whatsAppStatus ?? this.whatsAppStatus,
      emailMessageId: emailMessageId ?? this.emailMessageId,
      whatsAppMessageId: whatsAppMessageId ?? this.whatsAppMessageId,
      emailError: emailError ?? this.emailError,
      whatsAppError: whatsAppError ?? this.whatsAppError,
      dispatchedAt: dispatchedAt ?? this.dispatchedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
