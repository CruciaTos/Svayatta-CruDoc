import 'package:cloud_firestore/cloud_firestore.dart';

/// Where a UPI checkout for a plan stands. Mirrors `PlanPaymentStatus` in
/// functions/src/plan-payments.ts, which is the only writer.
enum PlanPaymentStatus {
  /// Asking the gateway for a payment page.
  starting,

  /// The payment page is open; waiting for the bank to confirm.
  pending,

  /// Verified: the plan is active.
  paid,
  failed,
  expired,
  cancelled,

  /// The gateway reported a payment CruDoc couldn't match up (wrong amount,
  /// a reused bank reference, ...). Held for a person to check, never
  /// unlocked or refused on its own.
  review;

  static PlanPaymentStatus parse(Object? raw) => PlanPaymentStatus.values
      .firstWhere((s) => s.name == raw, orElse: () => PlanPaymentStatus.pending);

  bool get isOpen => this == starting || this == pending;
}

/// A checkout the `planPayments` function just opened.
class PlanCheckout {
  final String orderId;
  final Uri checkoutUrl;
  final int amountPaise;
  final List<String> modules;

  /// How many people are paying ahead on the gateway (it takes one at a time).
  final int? queuePosition;

  const PlanCheckout({
    required this.orderId,
    required this.checkoutUrl,
    required this.amountPaise,
    required this.modules,
    this.queuePosition,
  });

  factory PlanCheckout.fromMap(Map<String, dynamic> data) => PlanCheckout(
    orderId: data['orderId'] as String,
    checkoutUrl: Uri.parse(data['checkoutUrl'] as String),
    amountPaise: (data['amountPaise'] as num).toInt(),
    modules: List<String>.from(data['modules'] as List? ?? const []),
    queuePosition: (data['queuePosition'] as num?)?.toInt(),
  );
}

/// `plan_payments/{orderId}` as the app reads it.
class PlanPayment {
  final String orderId;
  final PlanPaymentStatus status;
  final int amountPaise;
  final String? utr;
  final String? transactionId;
  final DateTime? validUntil;

  const PlanPayment({
    required this.orderId,
    required this.status,
    required this.amountPaise,
    this.utr,
    this.transactionId,
    this.validUntil,
  });

  factory PlanPayment.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return PlanPayment(
      orderId: doc.id,
      status: PlanPaymentStatus.parse(d['status']),
      amountPaise: (d['amountPaise'] as num?)?.toInt() ?? 0,
      utr: d['utr'] as String?,
      transactionId: d['transactionId'] as String?,
      validUntil: (d['validUntil'] as Timestamp?)?.toDate(),
    );
  }
}
