import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/feature_flag_model.dart';
import '../config/enums.dart';
import 'firebase_service.dart';

/// Service for managing feature module toggles for doctors.
class SuperAdminFeatureModuleService {
  final SuperAdminFirebaseService _fb = SuperAdminFirebaseService();

  /// Get feature flags for a specific doctor.
  Future<FeatureFlagModel?> getDoctorFeatureFlags(String doctorId) async {
    try {
      final doc = await _fb.doctorSettingsCollection.doc(doctorId).get();
      if (!doc.exists) return null;
      return FeatureFlagModel.fromJson(doc.data() as Map<String, dynamic>, doc.id);
    } catch (e) {
      throw Exception('Failed to fetch feature flags: ${e.toString()}');
    }
  }

  /// Enable a module for a specific doctor.
  Future<void> enableModule({
    required String doctorId,
    required String moduleId,
  }) async {
    try {
      // Check if module is available in doctor's plan
      final doctorDoc = await _fb.usersCollection.doc(doctorId).get();
      if (!doctorDoc.exists) throw Exception('Doctor not found');

      final planStr = (doctorDoc.data() as Map<String, dynamic>)['subscriptionPlan'] as String? ?? 'starter';
      final plan = SubscriptionPlan.values.firstWhere(
        (e) => e.name == planStr,
        orElse: () => SubscriptionPlan.starter,
      );

      if (!plan.includedModules.contains(moduleId)) {
        throw Exception('Module "$moduleId" is not available in the ${plan.label} plan');
      }

      final batch = _fb.batch();

      batch.update(_fb.doctorSettingsCollection.doc(doctorId), {
        'enabledModules': FieldValue.arrayUnion([moduleId]),
        'lastModified': FieldValue.serverTimestamp(),
        'modifiedBy': _fb.currentUserEmail,
      });

      batch.update(_fb.usersCollection.doc(doctorId), {
        'enabledModules': FieldValue.arrayUnion([moduleId]),
      });

      await batch.commit();
    } catch (e) {
      rethrow;
    }
  }

  /// Disable a module for a specific doctor.
  Future<void> disableModule({
    required String doctorId,
    required String moduleId,
  }) async {
    try {
      final batch = _fb.batch();

      batch.update(_fb.doctorSettingsCollection.doc(doctorId), {
        'enabledModules': FieldValue.arrayRemove([moduleId]),
        'lastModified': FieldValue.serverTimestamp(),
        'modifiedBy': _fb.currentUserEmail,
      });

      batch.update(_fb.usersCollection.doc(doctorId), {
        'enabledModules': FieldValue.arrayRemove([moduleId]),
      });

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to disable module: ${e.toString()}');
    }
  }

  /// Enable modules for multiple doctors at once.
  Future<void> bulkEnableModules({
    required List<String> doctorIds,
    required String moduleId,
  }) async {
    try {
      final batch = _fb.batch();
      for (final doctorId in doctorIds) {
        batch.update(_fb.doctorSettingsCollection.doc(doctorId), {
          'enabledModules': FieldValue.arrayUnion([moduleId]),
          'lastModified': FieldValue.serverTimestamp(),
          'modifiedBy': _fb.currentUserEmail,
        });
      }
      await batch.commit();
    } catch (e) {
      throw Exception('Failed to bulk enable modules: ${e.toString()}');
    }
  }

  /// Disable modules for multiple doctors at once.
  Future<void> bulkDisableModules({
    required List<String> doctorIds,
    required String moduleId,
  }) async {
    try {
      final batch = _fb.batch();
      for (final doctorId in doctorIds) {
        batch.update(_fb.doctorSettingsCollection.doc(doctorId), {
          'enabledModules': FieldValue.arrayRemove([moduleId]),
          'lastModified': FieldValue.serverTimestamp(),
          'modifiedBy': _fb.currentUserEmail,
        });
      }
      await batch.commit();
    } catch (e) {
      throw Exception('Failed to bulk disable modules: ${e.toString()}');
    }
  }

  /// Get all available feature modules.
  static List<Map<String, dynamic>> getAllModules() {
    return FeatureModule.values.map((module) {
      final planAvailability = <String, bool>{};
      for (final plan in SubscriptionPlan.values) {
        planAvailability[plan.label] = plan.includedModules.contains(module.name);
      }
      return {
        'id': module.name,
        'label': module.label,
        'planAvailability': planAvailability,
      };
    }).toList();
  }

  /// Check if a module is available in a given plan.
  bool isModuleAvailableInPlan(String moduleId, SubscriptionPlan plan) {
    return plan.includedModules.contains(moduleId);
  }
}