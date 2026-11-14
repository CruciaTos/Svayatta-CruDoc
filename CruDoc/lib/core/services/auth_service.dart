import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:doctor_management_app/core/services/demo_session_service.dart';
import 'package:doctor_management_app/core/services/desktop_google_oauth.dart';
import 'package:doctor_management_app/core/services/device_session_service.dart';
import 'package:doctor_management_app/core/services/push_notifications.dart';

/// Thin wrapper around [FirebaseAuth] that centralises every
/// authentication flow the app supports (Google, Phone OTP).
///
/// Consumed via [authServiceProvider] from `auth_providers.dart`.
class AuthService {
  AuthService({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
    : _auth = auth ?? FirebaseAuth.instance,
      _googleSignIn = googleSignIn ?? GoogleSignIn();

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  /// Holds the most recent Apple authorization code, required for token revocation
  /// upon account deletion.
  static String? lastAppleAuthorizationCode;

  // --------------- Getters ---------------

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // --------------- Google Sign-In ---------------

  /// Triggers the native Google Sign-In flow and authenticates with Firebase.
  /// Returns the [UserCredential] on success; throws on cancellation or error.
  Future<UserCredential> signInWithGoogle() async {
    // Windows and Linux have no google_sign_in plugin: sign in through the
    // browser, then hand Google's tokens to Firebase.
    if (DesktopGoogleOAuth.usesBrowser) {
      try {
        final tokens = await DesktopGoogleOAuth.authorize(
          scopes: const ['openid', 'email', 'profile'],
        );
        return await _auth.signInWithCredential(
          GoogleAuthProvider.credential(
            accessToken: tokens.accessToken,
            idToken: tokens.idToken,
          ),
        );
      } on DesktopGoogleOAuthException catch (e) {
        throw FirebaseAuthException(
          code: e.cancelled ? 'sign-in-cancelled' : 'google-desktop-failed',
          message: e.message,
        );
      }
    }

    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'sign-in-cancelled',
        message: 'Google sign-in was cancelled by the user.',
      );
    }

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    final OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    return _auth.signInWithCredential(credential);
  }

  // --------------- Sign in with Apple ---------------

  String _randomNonce([int length = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  /// Triggers Sign in with Apple and authenticates with Firebase.
  Future<UserCredential> signInWithApple() async {
    final raw = _randomNonce();
    final nonce = sha256.convert(utf8.encode(raw)).toString();
    final apple = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );
    lastAppleAuthorizationCode = apple.authorizationCode;
    final credential = OAuthProvider('apple.com').credential(
      idToken: apple.identityToken,
      rawNonce: raw,
      accessToken: apple.authorizationCode,
    );
    final result = await _auth.signInWithCredential(credential);
    // Apple only sends the name the first time: keep it.
    final given = apple.givenName?.trim() ?? '';
    final family = apple.familyName?.trim() ?? '';
    if ((result.user?.displayName ?? '').isEmpty &&
        (given + family).isNotEmpty) {
      await result.user?.updateDisplayName('$given $family'.trim());
    }
    return result;
  }

  // --------------- Phone OTP ---------------

  /// Starts the phone-number verification flow.
  ///
  /// [phoneNumber] must include the country code, e.g. `+919876543210`.
  /// [onCodeSent] is called with the `verificationId` once the SMS is
  /// dispatched — the caller should then show an OTP input.
  Future<void> sendOTP({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(PhoneAuthCredential credential) onAutoVerified,
    required void Function(FirebaseAuthException error) onError,
    int? forceResendingToken,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      forceResendingToken: forceResendingToken,
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Android auto-retrieval — sign in automatically.
        onAutoVerified(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        onError(e);
      },
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: (_) {
        // No-op — the OTP input stays visible until the user acts.
      },
    );
  }

  /// Completes phone authentication with the OTP entered by the user.
  Future<UserCredential> verifyOTP({
    required String verificationId,
    required String smsCode,
  }) {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return _auth.signInWithCredential(credential);
  }

  /// Adds a confirmed phone number to the signed-in account (email or
  /// Google sign-up), so clinic invites sent to that number can find it.
  Future<UserCredential> linkPhone({
    required String verificationId,
    required String smsCode,
  }) {
    return linkPhoneCredential(
      PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      ),
    );
  }

  /// [linkPhone] with a credential Android verified on its own.
  Future<UserCredential> linkPhoneCredential(AuthCredential credential) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'Sign in first.',
      );
    }
    final result = await user.linkWithCredential(credential);
    // The server reads the number from the ID token; get one that has it.
    await result.user?.getIdToken(true);
    return result;
  }

  // --------------- Sign Out ---------------

  Future<void> signOut() async {
    DemoSessionService.endDemoSession();
    await DeviceSessionService.instance.endCurrentSession();
    // Before signing out: deleting the token needs the signed-in account.
    await PushNotifications.instance.forgetThisDevice();
    if (!DesktopGoogleOAuth.usesBrowser) {
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
    }
    await _auth.signOut();
  }
}

/// What to tell someone when adding a phone number to their account fails.
String phoneLinkErrorMessage(FirebaseAuthException e) => switch (e.code) {
  'credential-already-in-use' || 'account-exists-with-different-credential' =>
    'This number already has its own CruDoc account. Sign in with that '
        'number instead, or use a different one.',
  'provider-already-linked' => 'This account already has a phone number.',
  'invalid-verification-code' => "That code isn't right. Check it and try again.",
  'session-expired' || 'code-expired' => 'The code expired. Send a new one.',
  _ => authErrorMessage(e, fallback: "Couldn't confirm the number. Try again."),
};

/// Plain sentence for a FirebaseAuth failure; the raw message is only logged.
String authErrorMessage(
  FirebaseAuthException e, {
  String fallback = "Couldn't sign in. Try again.",
}) {
  debugPrint('FirebaseAuth ${e.code}: ${e.message}');
  return switch (e.code) {
    'invalid-verification-code' => "That code isn't right. Check it and try again.",
    'session-expired' || 'code-expired' => 'The code expired. Send a new one.',
    'too-many-requests' =>
      'Too many attempts. Wait a few minutes and try again.',
    'network-request-failed' => "You're offline. Try again when connected.",
    'invalid-phone-number' => 'That phone number is not valid.',
    'invalid-email' => 'That email address is not valid.',
    'email-already-in-use' => 'An account already exists with that email.',
    'weak-password' => 'Choose a stronger password.',
    'wrong-password' ||
    'invalid-credential' ||
    'user-not-found' => 'Email or password is not right.',
    'user-disabled' => 'This account has been disabled.',
    _ => fallback,
  };
}

/// Custom exception so callers can distinguish "user cancelled" from real errors.
class FirebaseAuthCancelledException implements Exception {
  final String message;
  const FirebaseAuthCancelledException(this.message);

  @override
  String toString() => 'FirebaseAuthCancelledException: $message';
}
