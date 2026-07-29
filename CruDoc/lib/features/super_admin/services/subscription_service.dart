import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/subscription_model.dart';
import '../models/plan_model.dart';
import '../config/enums.dart';
import 'firebase_service.dart';

/// Service for managing subscriptions and plans.
class SuperAdminSubscriptionService {
  final SuperAdminFirebaseService _fb = SuperAdminFirebaseService();

  // --------------- Plans ---------------

  /// Get all subscription plans.
  Future<List<PlanModel>> getAllPlans() async {
    try {
      final snapshot = await _fb.plansCollection
          .orderBy('sortOrder')
          .get();
      return snapshot.docs.map((doc) {
        return PlanModel.fromJson(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    } catch (e) {
      throw Exception('Failed to fetch plans: ${e.toString()}');
    }
  }

  /// Update a plan definition.
  Future<void> updatePlan(String planId, Map<String, dynamic> updates) async {
    try {
      updates['updatedAt'] = FieldValue.serverTimestamp();
      updates['updatedBy'] = _fb.currentUserEmail;
      await _fb.plansCollection.doc(planId).update(updates);
    } catch (e) {
      throw Exception('Failed to update plan: ${e.toString()}');
    }
  }

  // --------------- Doctor Subscriptions ---------------

  /// Get subscription for a specific doctor.
  Future<SubscriptionModel?> getDoctorSubscription(String doctorId) async {
    try {
      final doc = await _fb.subscriptionsCollection.doc(doctorId).get();
      if (!doc.exists) return null;
      return SubscriptionModel.fromJson(doc.data() as Map<String, dynamic>, doc.id);
    } catch (e) {
      throw Exception('Failed to fetch subscription: ${e.toString()}');
    }
  }

  /// Upgrade a doctor's plan immediately.
  Future<void> upgradePlan({
    required String doctorId,
    required SubscriptionPlan newPlan,
    String? reason,
  }) async {
    try {
      final currentSub = await getDoctorSubscription(doctorId);
      if (currentSub == null) {
        throw Exception('No subscription found for this doctor');
      }

      final oldPlan = currentSub.plan;
      final now = Timestamp.now();

      // Update subscription document
      await _fb.subscriptionsCollection.doc(doctorId).update({
        'plan': newPlan.name,
        'lastModified': now,
        'modifiedBy': _fb.currentUserEmail,
        'history': FieldValue.arrayUnion([
          {
            'oldPlan': oldPlan.name,
            'newPlan': newPlan.name,
            'changedAt': now,
            'changedBy': _fb.currentUserEmail,
            'reason': reason ?? 'Plan upgrade by admin',
          }
        ]),
      });

      // Update doctor's storage limit based on new plan
      await _fb.usersCollection.doc(doctorId).update({
        'subscriptionPlan': newPlan.name,
        'storageLimitGB': newPlan.storageLimitGB,
      });

      // Add new modules available in the upgraded plan
      final newModules = newPlan.includedModules
          .where((m) => !currentSub.plan.includedModules.contains(m))
          .toList();
      if (newModules.isNotEmpty) {
        await _fb.doctorSettingsCollection.doc(doctorId).update({
          'enabledModules': FieldValue.arrayUnion(newModules),
        });
        await _fb.usersCollection.doc(doctorId).update({
          'enabledModules': FieldValue.arrayUnion(newModules),
        });
      }
    } catch (e) {
      throw Exception('Failed to upgrade plan: ${e.toString()}');
    }
  }

  /// Downgrade a doctor's plan.
  Future<void> downgradePlan({
    required String doctorId,
    required SubscriptionPlan newPlan,
    String? reason,
  }) async {
    try {
      final currentSub = await getDoctorSubscription(doctorId);
      if (currentSub == null) {
        throw Exception('No subscription found for this doctor');
      }

      final oldPlan = currentSub.plan;
      final now = Timestamp.now();

      // Update subscription document
      await _fb.subscriptionsCollection.doc(doctorId).update({
        'plan': newPlan.name,
        'lastModified': now,
        'modifiedBy': _fb.currentUserEmail,
        'history': FieldValue.arrayUnion([
          {
            'oldPlan': oldPlan.name,
            'newPlan': newPlan.name,
            'changedAt': now,
            'changedBy': _fb.currentUserEmail,
            'reason': reason ?? 'Plan downgrade by admin',
          }
        ]),
      });

      // Update doctor's storage limit
      await _fb.usersCollection.doc(doctorId).update({
        'subscriptionPlan': newPlan.name,
        'storageLimitGB': newPlan.storageLimitGB,
      });

      // Remove modules not available in downgraded plan
      final modulesToRemove = oldPlan.includedModules
          .where((m) => !newPlan.includedModules.contains(m))
          .toList();
      if (modulesToRemove.isNotEmpty) {
        await _fb.doctorSettingsCollection.doc(doctorId).update({
          'enabledModules': FieldValue.arrayRemove(modulesToRemove),
        });
        await _fb.usersCollection.doc(doctorId).update({
          'enabledModules': FieldValue.arrayRemove(modulesToRemove),
        });
      }
    } catch (e) {
      throw Exception('Failed to downgrade plan: ${e.toString()}');
    }
  }

  /// Extend a doctor's trial period.
  Future<void> extendTrial({
    required String doctorId,
    required int additionalDays,
    String? reason,
  }) async {
    try {
      final sub = await getDoctorSubscription(doctorId);
      final now = DateTime.now();
      final newTrialEnd = sub?.trialEndDate != null && sub!.trialEndDate!.isAfter(now)
          ? sub.trialEndDate!.add(Duration(days: additionalDays))
          : now.add(Duration(days: additionalDays));

      await _fb.subscriptionsCollection.doc(doctorId).update({
        'isTrial': true,
        'trialEndDate': Timestamp.fromDate(newTrialEnd),
        'lastModified': Timestamp.now(),
        'modifiedBy': _fb.currentUserEmail,
      });
    } catch (e) {
      throw Exception('Failed to extend trial: ${e.toString()}');
    }
  }

  /// Cancel a doctor's subscription.
  Future<void> cancelSubscription(String doctorId, {String? reason}) async {
    try {
      await _fb.subscriptionsCollection.doc(doctorId).update({
        'autoRenew': false,
        'lastModified': Timestamp.now(),
        'modifiedBy': _fb.currentUserEmail,
        'cancellationReason': reason,
        'cancelledAt': Timestamp.now(),
      });
    } catch (e) {
      throw Exception('Failed to cancel subscription: ${e.toString()}');
    }
  }

  /// Get subscription statistics.
  Future<Map<String, int>> getSubscriptionStats() async {
    try {
      final snapshot = await _fb.usersCollection
          .where('role', isEqualTo: 'doctor')
          .where('isDeleted', isEqualTo: false)
          .get();

      final stats = <String, int>{};
      for (final plan in SubscriptionPlan.values) {
        stats[plan.name] = 0;
      }

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final plan = data['subscriptionPlan'] as String? ?? 'starter';
        stats[plan] = (stats[plan] ?? 0) + 1;
      }

      return stats;
    } catch (e) {
      return {};
    }
  }
}