import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/subscription/data/upgrade_request_model.dart';
import 'package:doctor_management_app/features/subscription/data/doctor_subscription_service.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';

void main() {
  group('UpgradeRequest Model Tests', () {
    test('serializes and deserializes accurately with all fields', () {
      final now = DateTime.now();
      final request = UpgradeRequest(
        id: 'req-101',
        doctorId: 'doc-456',
        doctorName: 'Dr. Rajesh Sharma',
        doctorEmail: 'rajesh@example.com',
        requestedModules: ['revenue', 'ai_assistant', 'home_visits'],
        totalMonthlyPrice: 4997.0,
        currentPlan: 'starter',
        status: UpgradeRequestStatus.pending,
        createdAt: now,
      );

      final map = request.toMap();
      expect(map['doctorId'], 'doc-456');
      expect(map['doctorName'], 'Dr. Rajesh Sharma');
      expect(map['totalMonthlyPrice'], 4997.0);
      expect(map['status'], 'pending');
      expect(map['requestedModules'], ['revenue', 'ai_assistant', 'home_visits']);

      final restored = UpgradeRequest.fromMap(map, id: 'req-101');
      expect(restored.id, 'req-101');
      expect(restored.doctorId, 'doc-456');
      expect(restored.doctorName, 'Dr. Rajesh Sharma');
      expect(restored.requestedModules.length, 3);
      expect(restored.totalMonthlyPrice, 4997.0);
      expect(restored.status, UpgradeRequestStatus.pending);
    });

    test('handles fallback to pending for unknown status strings', () {
      final request = UpgradeRequest.fromMap({
        'status': 'unknown_weird_status',
        'createdAt': DateTime.now(),
      }, id: 'req-999');

      expect(request.status, UpgradeRequestStatus.pending);
    });
  });

  group('DoctorFeatureGuard Base & Expiry Tests', () {
    test('base modules are always recognized and never lockable', () {
      expect(DoctorFeatureGuard.isBaseModule('dashboard'), isTrue);
      expect(DoctorFeatureGuard.isBaseModule('patients'), isTrue);
      expect(DoctorFeatureGuard.isBaseModule('appointments'), isTrue);
      expect(DoctorFeatureGuard.isBaseModule('inventory'), isTrue);

      // Non-base / add-on modules
      expect(DoctorFeatureGuard.isBaseModule('revenue'), isFalse);
      expect(DoctorFeatureGuard.isBaseModule('home_visits'), isFalse);
      expect(DoctorFeatureGuard.isBaseModule('ai_assistant'), isFalse);
      expect(DoctorFeatureGuard.isBaseModule('omnichannel_messaging'), isFalse);
    });

    test('isEnabled strictly checks presence in enabledModules list', () {
      final configuredModules = ['dashboard', 'revenue', 'patients'];
      expect(DoctorFeatureGuard.isEnabled(configuredModules, 'dashboard'), isTrue);
      expect(DoctorFeatureGuard.isEnabled(configuredModules, 'revenue'), isTrue);
      expect(DoctorFeatureGuard.isEnabled(configuredModules, 'patients'), isTrue);

      // Disabled by admin
      expect(DoctorFeatureGuard.isEnabled(configuredModules, 'inventory'), isFalse);
      expect(DoctorFeatureGuard.isEnabled(configuredModules, 'appointments'), isFalse);
      expect(DoctorFeatureGuard.isEnabled(configuredModules, 'ai_assistant'), isFalse);
    });
  });

  group('DoctorSubscriptionInfo Logic Tests', () {
    test('isModuleUnlocked unlocks base modules even when expired', () {
      final expiredInfo = DoctorSubscriptionInfo(
        planName: 'Starter',
        doctorStatus: 'expired',
        isExpired: true,
        expiresDate: DateTime.now().subtract(const Duration(days: 5)),
        enabledModules: ['dashboard', 'patients', 'appointments', 'inventory', 'revenue'],
      );

      // Base modules stay unlocked
      expect(expiredInfo.isModuleUnlocked('dashboard'), isTrue);
      expect(expiredInfo.isModuleUnlocked('patients'), isTrue);
      expect(expiredInfo.isModuleUnlocked('appointments'), isTrue);
      expect(expiredInfo.isModuleUnlocked('inventory'), isTrue);

      // Add-on module is locked because plan is expired
      expect(expiredInfo.isModuleUnlocked('revenue'), isFalse);
      expect(expiredInfo.isModuleUnlocked('ai_assistant'), isFalse);
    });

    test('isModuleUnlocked allows add-ons when subscription is active', () {
      final activeInfo = DoctorSubscriptionInfo(
        planName: 'Professional',
        doctorStatus: 'active',
        isExpired: false,
        daysRemaining: 20,
        expiresDate: DateTime.now().add(const Duration(days: 20)),
        enabledModules: ['dashboard', 'patients', 'appointments', 'inventory', 'revenue', 'home_visits'],
      );

      expect(activeInfo.isModuleUnlocked('revenue'), isTrue);
      expect(activeInfo.isModuleUnlocked('home_visits'), isTrue);
      expect(activeInfo.isModuleUnlocked('ai_assistant'), isFalse); // not enabled
    });
  });
}
