import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/enums.dart';

/// Model for a doctor's subscription details.
class SubscriptionModel {
  final String doctorId;
  final SubscriptionPlan plan;
  final DateTime subscribedDate;
  final DateTime? expiresDate;
  final bool isTrial;
  final DateTime? trialEndDate;
  final String? stripeCustomerId;
  final String? stripeSubscriptionId;
  final bool autoRenew;
  final String? couponCode;
  final double? discountPercent;
  final DateTime? lastPaymentDate;
  final DateTime? nextBillingDate;
  final String? paymentMethod;
  final List<SubscriptionHistoryEntry> history;
  final DateTime lastModified;
  final String? modifiedBy;

  SubscriptionModel({
    required this.doctorId,
    required this.plan,
    DateTime? subscribedDate,
    this.expiresDate,
    this.isTrial = false,
    this.trialEndDate,
    this.stripeCustomerId,
    this.stripeSubscriptionId,
    this.autoRenew = true,
    this.couponCode,
    this.discountPercent,
    this.lastPaymentDate,
    this.nextBillingDate,
    this.paymentMethod,
    List<SubscriptionHistoryEntry>? history,
    DateTime? lastModified,
    this.modifiedBy,
  })  : subscribedDate = subscribedDate ?? DateTime.now(),
        history = history ?? [],
        lastModified = lastModified ?? DateTime.now();

  factory SubscriptionModel.fromJson(Map<String, dynamic> json, String doctorId) {
    return SubscriptionModel(
      doctorId: doctorId,
      plan: SubscriptionPlan.values.firstWhere(
        (e) => e.name == json['plan'],
        orElse: () => SubscriptionPlan.starter,
      ),
      subscribedDate: (json['subscribedDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresDate: (json['expiresDate'] as Timestamp?)?.toDate(),
      isTrial: json['isTrial'] as bool? ?? false,
      trialEndDate: (json['trialEndDate'] as Timestamp?)?.toDate(),
      stripeCustomerId: json['stripeCustomerId'] as String?,
      stripeSubscriptionId: json['stripeSubscriptionId'] as String?,
      autoRenew: json['autoRenew'] as bool? ?? true,
      couponCode: json['couponCode'] as String?,
      discountPercent: (json['discountPercent'] as num?)?.toDouble(),
      lastPaymentDate: (json['lastPaymentDate'] as Timestamp?)?.toDate(),
      nextBillingDate: (json['nextBillingDate'] as Timestamp?)?.toDate(),
      paymentMethod: json['paymentMethod'] as String?,
      history: (json['history'] as List<dynamic>?)
              ?.map((e) => SubscriptionHistoryEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      lastModified: (json['lastModified'] as Timestamp?)?.toDate() ?? DateTime.now(),
      modifiedBy: json['modifiedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'plan': plan.name,
      'subscribedDate': Timestamp.fromDate(subscribedDate),
      'expiresDate': expiresDate != null ? Timestamp.fromDate(expiresDate!) : null,
      'isTrial': isTrial,
      'trialEndDate': trialEndDate != null ? Timestamp.fromDate(trialEndDate!) : null,
      'stripeCustomerId': stripeCustomerId,
      'stripeSubscriptionId': stripeSubscriptionId,
      'autoRenew': autoRenew,
      'couponCode': couponCode,
      'discountPercent': discountPercent,
      'lastPaymentDate': lastPaymentDate != null ? Timestamp.fromDate(lastPaymentDate!) : null,
      'nextBillingDate': nextBillingDate != null ? Timestamp.fromDate(nextBillingDate!) : null,
      'paymentMethod': paymentMethod,
      'history': history.map((e) => e.toJson()).toList(),
      'lastModified': Timestamp.fromDate(lastModified),
      'modifiedBy': modifiedBy,
    };
  }

  double get effectivePrice {
    final base = plan.monthlyPrice;
    if (discountPercent != null) {
      return base * (1 - discountPercent! / 100);
    }
    return base;
  }
}

/// Entry in subscription change history.
class SubscriptionHistoryEntry {
  final SubscriptionPlan oldPlan;
  final SubscriptionPlan newPlan;
  final DateTime changedAt;
  final String changedBy;
  final String reason;

  SubscriptionHistoryEntry({
    required this.oldPlan,
    required this.newPlan,
    DateTime? changedAt,
    required this.changedBy,
    this.reason = '',
  }) : changedAt = changedAt ?? DateTime.now();

  factory SubscriptionHistoryEntry.fromJson(Map<String, dynamic> json) {
    return SubscriptionHistoryEntry(
      oldPlan: SubscriptionPlan.values.firstWhere(
        (e) => e.name == json['oldPlan'],
        orElse: () => SubscriptionPlan.starter,
      ),
      newPlan: SubscriptionPlan.values.firstWhere(
        (e) => e.name == json['newPlan'],
        orElse: () => SubscriptionPlan.starter,
      ),
      changedAt: (json['changedAt'] as Timestamp?)?.toDate(),
      changedBy: json['changedBy'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'oldPlan': oldPlan.name,
      'newPlan': newPlan.name,
      'changedAt': Timestamp.fromDate(changedAt),
      'changedBy': changedBy,
      'reason': reason,
    };
  }
}