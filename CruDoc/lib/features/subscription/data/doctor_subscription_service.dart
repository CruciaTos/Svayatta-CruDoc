import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:doctor_management_app/features/subscription/data/upgrade_request_model.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';

/// Information about a purchasable feature module.
class FeaturePricingItem {
  final String moduleKey;
  final String title;
  final String description;
  final double monthlyPriceInr;
  final bool isBaseModule;
  final String iconName;

  const FeaturePricingItem({
    required this.moduleKey,
    required this.title,
    required this.description,
    required this.monthlyPriceInr,
    this.isBaseModule = false,
    required this.iconName,
  });
}

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

  DoctorSubscriptionService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  static const List<FeaturePricingItem> availableFeatures = [
    FeaturePricingItem(
      moduleKey: 'dashboard',
      title: 'Practice Dashboard',
      description: 'Daily visit metrics, quick calendar access & notifications',
      monthlyPriceInr: 0,
      isBaseModule: true,
      iconName: 'dashboard',
    ),
    FeaturePricingItem(
      moduleKey: 'patients',
      title: 'Patient Records & EMR',
      description: 'Complete patient profiles, medical history & encounter logs',
      monthlyPriceInr: 0,
      isBaseModule: true,
      iconName: 'groups',
    ),
    FeaturePricingItem(
      moduleKey: 'appointments',
      title: 'Appointments & Calendar',
      description: 'Schedule management, multi-slot booking & calendar sheets',
      monthlyPriceInr: 0,
      isBaseModule: true,
      iconName: 'calendar',
    ),
    FeaturePricingItem(
      moduleKey: 'inventory',
      title: 'Clinic Pharmacy & Inventory',
      description: 'Stock tracking, low-stock alerts & dispense auditing',
      monthlyPriceInr: 0,
      isBaseModule: true,
      iconName: 'inventory',
    ),
    FeaturePricingItem(
      moduleKey: 'revenue',
      title: 'Revenue Analytics & Invoicing',
      description: 'Income tracking, digital receipts, billing sheets & financial summaries',
      monthlyPriceInr: 999,
      iconName: 'payments',
    ),
    FeaturePricingItem(
      moduleKey: 'home_visits',
      title: 'Home Visitations & Maps GPS',
      description: 'Home consultation tracking, geocoding & route planning',
      monthlyPriceInr: 1499,
      iconName: 'home',
    ),
    FeaturePricingItem(
      moduleKey: 'omnichannel_messaging',
      title: 'WhatsApp, SMS & Gmail Messaging',
      description: 'Automated 10-min appointment reminders & digital Rx dispatch to patients',
      monthlyPriceInr: 1999,
      iconName: 'chat',
    ),
    FeaturePricingItem(
      moduleKey: 'ai_assistant',
      title: 'AI Medical Scribe & Rx Generator',
      description: 'Voice clinical dictation, SOAP generation & instant structured prescriptions',
      monthlyPriceInr: 2499,
      iconName: 'smart_toy',
    ),
    FeaturePricingItem(
      moduleKey: 'ai_agentic_calling',
      title: 'Autonomous AI Voice Calling',
      description: 'AI phone agent to call patients for automated confirmations & follow-ups',
      monthlyPriceInr: 3999,
      iconName: 'phone',
    ),
    FeaturePricingItem(
      moduleKey: 'multi_device_access',
      title: 'Multi-Device & Receptionist Access',
      description: 'Simultaneous login across mobile, tablet, desktop & staff kiosks',
      monthlyPriceInr: 799,
      iconName: 'devices',
    ),
  ];

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
      final modulesRaw = (data['enabledModules'] as List<dynamic>?)
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

  /// Processes in-app payment and instantly activates the selected features for 1 month (30 days).
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

    final doctorId = user.uid;
    final now = DateTime.now();
    final newExpiresDate = now.add(const Duration(days: 30));
    final transactionId =
        'TXN_${DateTime.now().millisecondsSinceEpoch}_${const Uuid().v4().substring(0, 6).toUpperCase()}';

    // 1. Ensure all base modules are included in the activated list
    final fullModulesList = <String>{
      ...DoctorFeatureGuard.baseModules,
      ...selectedModules,
    }.toList();

    // 2. Update user document directly
    await _firestore.collection('users').doc(doctorId).update({
      'enabledModules': fullModulesList,
      'status': 'active',
      'expiresDate': Timestamp.fromDate(newExpiresDate),
      'lastPaymentDate': Timestamp.fromDate(now),
      'lastTransactionId': transactionId,
      'lastPaymentAmount': amountPaid,
      'lastPaymentMethod': paymentMethod,
    });

    // 3. Update doctor_settings if exists
    try {
      await _firestore.collection('doctor_settings').doc(doctorId).set({
        'doctorId': doctorId,
        'enabledModules': fullModulesList,
        'lastModified': Timestamp.fromDate(now),
      }, SetOptions(merge: true));
    } catch (_) {}

    // 4. Save payment receipt in payment_transactions collection
    await _firestore.collection('payment_transactions').doc(transactionId).set({
      'transactionId': transactionId,
      'doctorId': doctorId,
      'doctorEmail': user.email ?? '',
      'doctorName': user.displayName ?? 'Doctor',
      'amount': amountPaid,
      'currency': 'INR',
      'paymentMethod': paymentMethod,
      'transactionReference': transactionReference ?? transactionId,
      'activatedModules': fullModulesList,
      'validUntil': Timestamp.fromDate(newExpiresDate),
      'status': 'success',
      'timestamp': Timestamp.fromDate(now),
    });

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

    final doctorName = doctorNameOverride ??
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
