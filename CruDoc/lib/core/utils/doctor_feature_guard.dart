import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Helper utility for real-time doctor feature locking.
class DoctorFeatureGuard {
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

  /// Listens to real-time updates for enabled modules of current logged-in doctor.
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
      final modulesList = (data['enabledModules'] as List<dynamic>?)
          ?.map((e) => e.toString().toLowerCase())
          .toList();
      return modulesList ?? defaultModules;
    });
  }

  /// Maps mobile shell tab index to feature module key.
  static String getModuleKeyForTab(int tabIndex) {
    switch (tabIndex) {
      case 0:
        return 'dashboard';
      case 1:
        return 'revenue'; // Invoices tab
      case 2:
        return 'patients'; // Patient Records tab
      case 3:
        return 'inventory'; // Inventory tab
      case 4:
        return 'revenue'; // Revenue Analytics tab
      case 5:
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
        return 'Invoices';
      case 2:
        return 'Patient Records';
      case 3:
        return 'Inventory Management';
      case 4:
        return 'Revenue & Financials';
      case 5:
        return 'Appointments & Events';
      default:
        return 'Feature';
    }
  }

  /// Checks if a module is enabled in the active modules list.
  static bool isEnabled(List<String> enabledModules, String moduleKey) {
    return enabledModules.contains(moduleKey.toLowerCase());
  }
}
