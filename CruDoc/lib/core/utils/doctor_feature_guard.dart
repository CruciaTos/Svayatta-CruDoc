import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Helper utility for real-time doctor feature locking and subscription expiry.
class DoctorFeatureGuard {
  /// Base modules that remain active during subscription expiry.
  static const List<String> baseModules = [
    'dashboard',
    'patients',
    'appointments',
    'inventory',
  ];

  /// Default set of modules if unspecified.
  static const List<String> defaultModules = [
    'dashboard',
    'revenue',
    'patients',
    'appointments',
    'inventory',
    'home_visits',
    'ai_assistant',
    'ai_agentic_calling',
    'omnichannel_messaging',
    'multi_device_access',
  ];

  /// Checks if a module is a core base module.
  static bool isBaseModule(String moduleKey) {
    return baseModules.contains(moduleKey.toLowerCase());
  }

  /// Listens to real-time updates for enabled modules of current logged-in doctor.
  /// Strictly reflects what the Super Admin sets in Firestore `users/{uid}.enabledModules`.
  static Stream<List<String>> watchEnabledModules([User? user]) {
    final currentUser = user ?? FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return Stream.value(defaultModules);
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .snapshots()
        .map((doc) {
      if (!doc.exists || doc.data() == null) {
        return defaultModules;
      }
      final data = doc.data()!;
      final status = (data['status'] as String? ?? 'active').toLowerCase();

      DateTime? expiresDate;
      final rawExpires = data['expiresDate'];
      if (rawExpires is Timestamp) {
        expiresDate = rawExpires.toDate();
      } else if (rawExpires is String) {
        expiresDate = DateTime.tryParse(rawExpires);
      }

      final now = DateTime.now();
      final isExpired = (expiresDate != null && expiresDate.isBefore(now)) ||
          status == 'expired';

      // Read enabledModules list explicitly configured by Super Admin
      final rawList = data['enabledModules'] as List<dynamic>?;
      List<String> modulesList;
      if (rawList != null) {
        modulesList = rawList.map((e) => e.toString().toLowerCase()).toList();
      } else {
        modulesList = List<String>.from(defaultModules);
      }

      if (isExpired) {
        // If expired, only allow base modules that are configured in modulesList
        return modulesList.where((m) => baseModules.contains(m)).toList();
      }

      return modulesList;
    });
  }

  /// Maps mobile shell tab index to feature module key.
  static String getModuleKeyForTab(int tabIndex) {
    switch (tabIndex) {
      case 0:
        return 'dashboard';
      case 1:
        return 'patients'; // Patient Records tab
      case 2:
        return 'inventory'; // Inventory tab
      case 3:
        return 'revenue'; // Revenue Analytics tab
      case 4:
        return 'appointments'; // Events / Visitation tab
      default:
        return 'dashboard';
    }
  }

  /// Returns user-friendly title for a tab.
  static String getTabTitle(int tabIndex) {
    switch (tabIndex) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'Patient Records';
      case 2:
        return 'Inventory Management';
      case 3:
        return 'Revenue & Financials';
      case 4:
        return 'Appointments & Events';
      default:
        return 'Feature';
    }
  }

  /// Checks if a module is enabled in the active modules list.
  /// Strictly respects what the Super Admin configures in `enabledModules`.
  static bool isEnabled(List<String> enabledModules, String moduleKey) {
    return enabledModules.contains(moduleKey.toLowerCase());
  }
}
