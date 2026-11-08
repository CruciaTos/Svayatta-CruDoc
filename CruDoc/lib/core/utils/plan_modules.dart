import 'package:doctor_management_app/core/utils/app_notice.dart';
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'doctor_feature_guard.dart';

/// The modules in the signed-in clinic's plan, kept current, for the
/// actions that open from anywhere (booking a visit, a home visit, AI call
/// forwarding) and can't wait for a stream. The list is the one Super Admin
/// sets (`users/{uid}.enabledModules`, see [DoctorFeatureGuard]); a module
/// that isn't in it is locked.
class PlanModules {
  PlanModules._();
  static final PlanModules instance = PlanModules._();

  /// Null until the plan has loaded for the signed-in person.
  final ValueNotifier<List<String>?> modules = ValueNotifier(null);

  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<String>>? _planSub;

  /// Follows whoever is signed in. Called once at app start.
  void start() {
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      _planSub?.cancel();
      _planSub = null;
      modules.value = null;
      if (user == null) return;
      _planSub = DoctorFeatureGuard.watchEnabledModules(user).listen(
        (list) => modules.value = list,
      );
    });
  }

  /// Whether [module] is in the plan. False while the plan is loading.
  bool isOn(String module) =>
      DoctorFeatureGuard.isEnabled(modules.value ?? const [], module);

  /// For an action that needs [module]: true if it's in the plan, otherwise
  /// says so and returns false.
  bool require(BuildContext context, String module, String feature) {
    if (isOn(module)) return true;
    ScaffoldMessenger.maybeOf(context)?.showIsland(
      SnackBar(
        content: Text(
          "$feature isn't in your plan. Add it in Subscription & Billing.",
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return false;
  }
}
