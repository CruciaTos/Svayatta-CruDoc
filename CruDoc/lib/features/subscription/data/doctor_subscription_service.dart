import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crudoc_shared/subscription/feature_catalog.dart';
import 'package:crudoc_shared/subscription/upgrade_request_model.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/onboarding/data/loyalty_card.dart';

export 'package:crudoc_shared/subscription/feature_catalog.dart';

/// Information about a doctor's subscription status.
class DoctorSubscriptionInfo {
  final String planName;
  final String doctorStatus;
  final DateTime? expiresDate;
  final bool isExpired;
  final int? daysRemaining;
  final List<String> enabledModules;

  const DoctorSubscriptionInfo({
    required this.planName,
    required this.doctorStatus,
    this.expiresDate,
    required this.isExpired,
    this.daysRemaining,
    required this.enabledModules,
  });

  bool isModuleUnlocked(String moduleKey) {
    if (DoctorFeatureGuard.isBaseModule(moduleKey)) return true;
    if (isExpired) return false;
    return enabledModules.contains(moduleKey.toLowerCase());
  }
}

/// Service handling doctor subscription state, feature upgrade requests,
/// and automated in-app payment activation.
class DoctorSubscriptionService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  DoctorSubscriptionService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');

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
      final planName = (data['subscriptionPlan'] as String?) ?? 'Starter';
      final status = (data['status'] as String?) ?? 'active';
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
      );
    });
  }

  /// Processes the in-app (simulated) payment and activates the selected
  /// features for 1 month (30 days).
  ///
  /// The actual entitlement write is done by the `activateDoctorFeatures`
  /// Cloud Function running with admin privileges — the client never writes
  /// its own `enabledModules`/`expiresDate`, so features cannot be unlocked
  /// by tampering with Firestore directly. The server also computes the
  /// expiry, so the plan length can't be forged.
  Future<({bool success, String transactionId, DateTime newExpiryDate})>
  processPaymentAndActivateFeatures({
    required List<String> selectedModules,
    required double amountPaid,
    required String paymentMethod,
    String? transactionReference,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No doctor logged in');
    }

    final HttpsCallableResult result;
    try {
      result = await _functions.httpsCallable('activateDoctorFeatures').call({
        'selectedModules': selectedModules,
        'amount': amountPaid,
        'paymentMethod': paymentMethod,
        'transactionReference': transactionReference,
      });
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? 'Activation failed. Please try again.');
    }

    final data = Map<String, dynamic>.from(result.data as Map);
    final transactionId = (data['transactionId'] as String?) ?? '';
    final validUntilRaw = data['validUntil'] as String?;
    final newExpiresDate =
        DateTime.tryParse(validUntilRaw ?? '') ??
        DateTime.now().add(const Duration(days: 30));

    // A paid month earns a loyalty stamp (one per calendar month). This
    // writes to the doctor's own loyalty subcollection, so it stays on the
    // client.
    try {
      await LoyaltyService.stampThisMonth();
    } catch (_) {}

    return (
      success: true,
      transactionId: transactionId,
      newExpiryDate: newExpiresDate,
    );
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
}
