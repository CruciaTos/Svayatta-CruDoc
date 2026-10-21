import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:doctor_management_app/core/services/demo_session_service.dart';
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

  // --------------- Getters ---------------

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // --------------- Google Sign-In ---------------

  /// Triggers the native Google Sign-In flow and authenticates with Firebase.
  /// Returns the [UserCredential] on success; throws on cancellation or error.
  Future<UserCredential> signInWithGoogle() async {
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
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
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
  _ => e.message ?? 'Could not confirm the number. Try again.',
};

/// Custom exception so callers can distinguish "user cancelled" from real errors.
class FirebaseAuthCancelledException implements Exception {
  final String message;
  const FirebaseAuthCancelledException(this.message);

  @override
  String toString() => 'FirebaseAuthCancelledException: $message';
}
