import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import 'demo_session_service.dart';

/// Asks the Firebase Auth server whether the signed-in account may still be
/// used, so access is decided by the backend and not by what this device
/// remembers.
///
/// Firebase keeps a saved sign-in on the device and refreshes its token only
/// about once an hour. When Super Admin deletes or suspends an account (see
/// deleteDoctor / toggleDoctorStatus in functions/src/super-admin.ts), the
/// login is turned off and its tokens revoked. This check forces a token
/// refresh on app start and whenever the app comes back to the foreground,
/// so that device is signed out at once instead of up to an hour later.
///
/// No internet is not a "no": an offline clinic keeps working, and the check
/// runs again on the next resume.
class AccountServerCheck {
  AccountServerCheck._();

  static AppLifecycleListener? _lifecycle;
  static bool _running = false;

  /// Codes that mean the server refused this account.
  static const _refusedCodes = {
    'user-disabled',
    'user-not-found',
    'user-token-expired',
    'invalid-user-token',
  };

  /// Starts checking on every resume. [onSignedOut] gets the reason to show.
  static void start({required void Function(String reason) onSignedOut}) {
    _lifecycle ??= AppLifecycleListener(
      onResume: () => unawaited(check(onSignedOut: onSignedOut)),
    );
  }

  /// Checks the current account now and signs out if the server refuses it.
  static Future<void> check({
    required void Function(String reason) onSignedOut,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _running) return;
    _running = true;
    try {
      final token = await user.getIdTokenResult(true);
      // Super Admin logins are for the Super Admin panel only; the server
      // gives them no clinic, so a saved sign-in is closed here.
      if (token.claims?['role'] == 'superAdmin') {
        DemoSessionService.endDemoSession();
        await FirebaseAuth.instance.signOut();
        onSignedOut(
          "Super Admin accounts can't be used in the clinic app. "
          'Sign in with a doctor account.',
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!_refusedCodes.contains(e.code)) {
        debugPrint('[AccountServerCheck] not checked: ${e.code}');
        return;
      }
      debugPrint('[AccountServerCheck] server refused account: ${e.code}');
      DemoSessionService.endDemoSession();
      await FirebaseAuth.instance.signOut();
      onSignedOut(
        e.code == 'user-disabled'
            ? 'This account has been turned off by Super Admin.'
            : 'This account is no longer available. Please sign in again.',
      );
    } catch (e) {
      debugPrint('[AccountServerCheck] not checked: $e');
    } finally {
      _running = false;
    }
  }
}
