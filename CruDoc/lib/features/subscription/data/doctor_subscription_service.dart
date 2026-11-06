import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:crudoc_shared/subscription/feature_catalog.dart';
import 'package:crudoc_shared/subscription/upgrade_request_model.dart';
import 'package:doctor_management_app/core/services/callable_client.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/onboarding/data/loyalty_card.dart';
import 'package:doctor_management_app/features/subscription/data/plan_payment.dart';

export 'package:crudoc_shared/subscription/feature_catalog.dart';
export 'package:doctor_management_app/features/subscription/data/plan_payment.dart';

/// Information about a doctor's subscription status.
class DoctorSubscriptionInfo {
  final String planName;
  final String doctorStatus;
  final DateTime? expiresDate;
  final bool isExpired;
  final int? daysRemaining;
  final List<String> enabledModules;
  final bool isCancelled;

  const DoctorSubscriptionInfo({
    required this.planName,
    required this.doctorStatus,
    this.expiresDate,
    required this.isExpired,
    this.daysRemaining,
    required this.enabledModules,
    this.isCancelled = false,
  });

  bool isModuleUnlocked(String moduleKey) {
    if (DoctorFeatureGuard.isBaseModule(moduleKey)) return true;
    if (isExpired) return false;
    return enabledModules.contains(moduleKey.toLowerCase());
  }

  /// The paid modules this doctor can still buy: not a base module and not
  /// switched on right now. Once the plan has expired nothing paid is on, so
  /// every paid module is offered again. The More plan card and the billing
  /// screen both read this, so they can never disagree.
  List<FeaturePricingItem> get purchasableModules => [
    for (final item in featureCatalog)
      if (!item.isBaseModule && !isModuleUnlocked(item.moduleKey)) item,
  ];

  /// The paid modules that are switched on right now. Every payment rewrites
  /// the doctor's whole module list on the server (`writePaidPlan` sets
  /// `enabledModules` to the base modules plus what was paid for), so these
  /// must go into each checkout or they would switch off.
  List<FeaturePricingItem> get ownedPaidModules => [
    for (final item in featureCatalog)
      if (!item.isBaseModule && isModuleUnlocked(item.moduleKey)) item,
  ];

  /// When the plan runs out, in a line: "Valid until 12 Nov 2026 · 30 days
  /// left", or "Expired on 12 Oct 2026".
  String get validityLine {
    final date = expiresDate;
    if (date == null) return 'Standard account configuration';
    final day = DateFormat('dd MMM yyyy').format(date);
    return isExpired
        ? 'Expired on $day'
        : 'Valid until $day · ${daysRemaining ?? 0} days left';
  }
}

/// Service handling doctor subscription state, feature upgrade requests,
/// and paying for plans by UPI.
class DoctorSubscriptionService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final CallableClient _functions;

  DoctorSubscriptionService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    CallableClient? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       // CallableClient, not the cloud_functions plugin: the plugin has no
       // Windows implementation, so checkout would fail on the desktop app.
       _functions = functions ?? CallableClient();

  static const List<FeaturePricingItem> availableFeatures = featureCatalog;

  /// Watches real-time subscription details for the current doctor.
  Stream<DoctorSubscriptionInfo> watchSubscriptionInfo() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value(
        const DoctorSubscriptionInfo(
          planName: 'Starter',
          doctorStatus: 'active',
          isExpired: false,
          enabledModules: DoctorFeatureGuard.defaultModules,
        ),
      );
    }

    return _firestore.collection('users').doc(user.uid).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) {
        return const DoctorSubscriptionInfo(
          planName: 'Starter',
          doctorStatus: 'active',
          isExpired: false,
          enabledModules: DoctorFeatureGuard.defaultModules,
        );
      }

      final data = doc.data()!;
      var planName = (data['subscriptionPlan'] as String?) ?? 'Starter';
      final status = (data['status'] as String?) ?? 'active';
      // Paying for a trial leaves subscriptionPlan as "Trial" (the Super
      // Admin owns that field); status "active" says it is paid now.
      if (status.toLowerCase() == 'active' &&
          planName.toLowerCase() == 'trial') {
        planName = 'Paid';
      }
      final isCancelled = (data['subscriptionCancelled'] as bool?) ?? false;
      final modulesRaw =
          (data['enabledModules'] as List<dynamic>?)
              ?.map((e) => e.toString().toLowerCase())
              .toList() ??
          DoctorFeatureGuard.defaultModules;

      DateTime? expiresDate;
      final rawExpires = data['expiresDate'];
      if (rawExpires is Timestamp) {
        expiresDate = rawExpires.toDate();
      } else if (rawExpires is String) {
        expiresDate = DateTime.tryParse(rawExpires);
      }

      final now = DateTime.now();
      bool isExpired = false;
      int? daysRemaining;

      if (expiresDate != null) {
        final diff = expiresDate.difference(now);
        daysRemaining = diff.inDays;
        isExpired = expiresDate.isBefore(now);
      } else if (status.toLowerCase() == 'expired') {
        isExpired = true;
        daysRemaining = 0;
      }

      return DoctorSubscriptionInfo(
        planName: planName,
        doctorStatus: status,
        expiresDate: expiresDate,
        isExpired: isExpired,
        daysRemaining: daysRemaining,
        enabledModules: modulesRaw,
        isCancelled: isCancelled,
      );
    });
  }

  /// Opens a UPI checkout for [modules] through CruDoc's payment gateway.
  ///
  /// The `planPayments` function prices the modules itself and returns the
  /// payment page to open; nothing is unlocked here. The plan is activated on
  /// the server once the bank confirms the payment, and [watchPlanPayment]
  /// reports it.
  Future<PlanCheckout> startPlanCheckout(List<String> modules) async {
    if (_auth.currentUser == null) {
      throw StateError('No doctor logged in');
    }
    try {
      final result = await _functions.call('planPayments', {
        'action': 'start',
        'modules': modules,
      });
      return PlanCheckout.fromMap(Map<String, dynamic>.from(result as Map));
    } on CallableException catch (e) {
      throw StateError(
        e.message.isNotEmpty ? e.message : 'Could not open the payment page.',
      );
    }
  }

  /// Gives up on an open checkout and frees the gateway for the next person.
  /// If the money was already sent, the plan is still activated.
  Future<void> cancelPlanCheckout(String orderId) async {
    try {
      await _functions.call('planPayments', {
        'action': 'cancel',
        'orderId': orderId,
      });
    } on CallableException catch (e) {
      throw StateError(
        e.message.isNotEmpty ? e.message : 'Could not cancel the payment.',
      );
    }
  }

  /// Completes a test checkout (one started with `mock: true`) as if the
  /// bank had confirmed it. The server refuses this outside the dev project.
  Future<void> completeMockPayment(String orderId) async {
    try {
      await _functions.call('planPayments', {
        'action': 'mockPay',
        'orderId': orderId,
      });
    } on CallableException catch (e) {
      throw StateError(
        e.message.isNotEmpty ? e.message : 'Could not complete the payment.',
      );
    }
  }

  /// The checkout [orderId] as the server updates it.
  Stream<PlanPayment> watchPlanPayment(String orderId) => _firestore
      .collection('plan_payments')
      .doc(orderId)
      .snapshots()
      .where((doc) => doc.exists)
      .map(PlanPayment.fromSnapshot);

  /// A paid month earns a loyalty stamp (one per calendar month). This writes
  /// to the doctor's own loyalty subcollection, so it stays on the client.
  Future<void> stampPaidMonth() async {
    try {
      await LoyaltyService.stampThisMonth();
    } catch (_) {}
  }

  /// Streams the current doctor's submitted upgrade requests.
  Stream<List<UpgradeRequest>> watchMyUpgradeRequests() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('upgrade_requests')
        .where('doctorId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => UpgradeRequest.fromFirestore(doc))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  /// Submits an upgrade request to Firestore (for optional manual approval).
  Future<String> submitUpgradeRequest({
    required List<String> requestedModules,
    required double totalMonthlyPrice,
    required String currentPlan,
    String? doctorNameOverride,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No doctor logged in');
    }

    final doctorName =
        doctorNameOverride ??
        user.displayName ??
        user.email?.split('@').first ??
        'Doctor';

    final docRef = _firestore.collection('upgrade_requests').doc();
    final request = UpgradeRequest(
      id: docRef.id,
      doctorId: user.uid,
      doctorName: doctorName,
      doctorEmail: user.email ?? '',
      requestedModules: requestedModules,
      totalMonthlyPrice: totalMonthlyPrice,
      currentPlan: currentPlan,
      status: UpgradeRequestStatus.pending,
      createdAt: DateTime.now(),
    );

    await docRef.set(request.toMap());
    return docRef.id;
  }

  /// Cancels or resumes the doctor's subscription.
  Future<void> setCancelled(bool cancelled) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('No doctor logged in');
    }
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'subscriptionCancelled': cancelled,
      'subscriptionCancelledAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
