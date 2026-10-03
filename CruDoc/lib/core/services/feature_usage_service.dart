import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:doctor_management_app/core/services/demo_session_service.dart';

/// Records which features each doctor opens, for the Super Admin's Trial
/// users tab: one counter per feature at users/{uid}/feature_usage/{key}.
class FeatureUsageService {
  FeatureUsageService._();

  /// Features already logged this app session (one write per feature).
  static final Set<String> _seen = {};

  /// "Treatment plans" → "treatment_plans".
  static String keyFor(String label) =>
      label.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  static Future<void> log(String label) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || DemoSessionService.isDemoMode) return;
    final key = keyFor(label);
    if (key.isEmpty || !_seen.add(key)) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('feature_usage')
          .doc(key)
          .set({
            'moduleKey': key,
            'opens': FieldValue.increment(1),
            'lastUsedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (_) {}
  }
}
