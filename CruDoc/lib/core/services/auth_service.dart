import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  // --------------- Sign Out ---------------

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}

/// Custom exception so callers can distinguish "user cancelled" from real errors.
class FirebaseAuthCancelledException implements Exception {
  final String message;
  const FirebaseAuthCancelledException(this.message);

  @override
  String toString() => 'FirebaseAuthCancelledException: $message';
}
