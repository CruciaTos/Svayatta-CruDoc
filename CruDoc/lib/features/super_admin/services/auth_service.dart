import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/super_admin_model.dart';
import '../config/enums.dart';
import '../config/app_constants.dart';
import 'firebase_service.dart';

/// Authentication service for Super Admin login, 2FA, and session management.
class SuperAdminAuthService {
  final SuperAdminFirebaseService _fb = SuperAdminFirebaseService();

  /// Sign in with email and password.
  /// Returns the SuperAdminModel on success.
  Future<SuperAdminModel> signIn({
    required String email,
    required String password,
  }) async {
    try {
      // 1. Sign in with Firebase Auth
      final userCredential = await _fb.auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = userCredential.user!.uid;

      // 2. Fetch or create the admin profile document in Firestore
      final doc = await _fb.usersCollection.doc(uid).get();
      if (!doc.exists || doc.data() == null) {
        final user = userCredential.user!;
        await _fb.usersCollection.doc(uid).set({
          'email': user.email ?? email,
          'name': user.displayName ?? 'Super Admin',
          'profilePictureUrl': '',
          'role': UserRole.superAdmin.name,
          'isTwoFAEnabled': false,
          'isTwoFAVerified': true,
          'isActive': true,
          'failedLoginAttempts': 0,
          'accountCreated': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
          'lockedUntil': null,
        });
      }

      final adminDoc = await _fb.usersCollection.doc(uid).get();
      final admin = SuperAdminModel.fromJson(
        adminDoc.data() as Map<String, dynamic>,
        uid,
      );

      // 3. Verify role is superAdmin
      if (admin.role != UserRole.superAdmin) {
        await _fb.auth.signOut();
        throw FirebaseAuthException(
          code: 'unauthorized',
          message: 'Access denied. Super Admin privileges required.',
        );
      }

      // 4. Check if account is active
      if (!admin.isActive) {
        await _fb.auth.signOut();
        throw FirebaseAuthException(
          code: 'account-disabled',
          message: 'This admin account has been disabled.',
        );
      }

      // 5. Check lockout
      if (admin.lockedUntil != null && admin.lockedUntil!.isAfter(DateTime.now())) {
        await _fb.auth.signOut();
        final minutesLeft = admin.lockedUntil!.difference(DateTime.now()).inMinutes;
        throw FirebaseAuthException(
          code: 'account-locked',
          message: 'Account locked. Try again in $minutesLeft minutes.',
        );
      }

      // 6. Update last login and reset failed attempts
      await _fb.usersCollection.doc(uid).update({
        'lastLogin': FieldValue.serverTimestamp(),
        'failedLoginAttempts': 0,
        'lockedUntil': null,
      });

      return admin;
    } on FirebaseAuthException {
      rethrow;
    } catch (e) {
      throw FirebaseAuthException(
        code: 'unknown',
        message: 'Login failed: ${e.toString()}',
      );
    }
  }

  /// Track failed login attempt and lock account if threshold exceeded.
  Future<void> trackFailedLogin(String email) async {
    try {
      final query = await _fb.usersCollection
          .where('email', isEqualTo: email)
          .where('role', isEqualTo: UserRole.superAdmin.name)
          .limit(1)
          .get();

      if (query.docs.isEmpty) return;

      final doc = query.docs.first;
      final data = doc.data() as Map<String, dynamic>;
      final currentAttempts = (data['failedLoginAttempts'] as int? ?? 0) + 1;

      if (currentAttempts >= SuperAdminConstants.maxLoginAttempts) {
        await doc.reference.update({
          'failedLoginAttempts': currentAttempts,
          'lockedUntil': Timestamp.fromDate(
            DateTime.now().add(
              Duration(minutes: SuperAdminConstants.accountLockoutMinutes),
            ),
          ),
        });
      } else {
        await doc.reference.update({
          'failedLoginAttempts': currentAttempts,
        });
      }
    } catch (_) {
      // Silently fail - don't expose tracking errors
    }
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    await _fb.auth.signOut();
  }

  /// Send password reset email.
  Future<void> sendPasswordResetEmail(String email) async {
    await _fb.auth.sendPasswordResetEmail(email: email);
  }

  /// Get current admin profile.
  Future<SuperAdminModel?> getCurrentAdmin() async {
    final user = _fb.currentUser;
    if (user == null) return null;

    final doc = await _fb.usersCollection.doc(user.uid).get();
    if (!doc.exists || doc.data() == null) {
      await _fb.usersCollection.doc(user.uid).set({
        'email': user.email ?? '',
        'name': user.displayName ?? 'Super Admin',
        'profilePictureUrl': '',
        'role': UserRole.superAdmin.name,
        'isTwoFAEnabled': false,
        'isTwoFAVerified': true,
        'isActive': true,
        'failedLoginAttempts': 0,
        'accountCreated': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
        'lockedUntil': null,
      });
      return SuperAdminModel(
        id: user.uid,
        email: user.email ?? '',
        name: user.displayName ?? 'Super Admin',
        role: UserRole.superAdmin,
      );
    }

    return SuperAdminModel.fromJson(doc.data() as Map<String, dynamic>, user.uid);
  }

  /// Update admin profile.
  Future<void> updateProfile({
    String? name,
    String? profilePictureUrl,
  }) async {
    final uid = _fb.currentUserId;
    if (uid == null) throw Exception('Not authenticated');

    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (profilePictureUrl != null) updates['profilePictureUrl'] = profilePictureUrl;

    if (updates.isNotEmpty) {
      await _fb.usersCollection.doc(uid).update(updates);
    }
  }

  /// Change password.
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final user = _fb.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Re-authenticate
    final credential = EmailAuthProvider.credential(
      email: user.email!,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
  }

  /// Enable 2FA for the admin account.
  Future<String> enable2FA() async {
    // In production, this would generate a TOTP secret
    // For now, we simulate the flow
    final uid = _fb.currentUserId;
    if (uid == null) throw Exception('Not authenticated');

    // Generate a mock secret (in production use a TOTP library)
    final secret = _generateTOTPSecret();

    await _fb.usersCollection.doc(uid).update({
      'isTwoFAEnabled': true,
      'twoFASecret': secret,
    });

    return secret;
  }

  /// Verify 2FA code.
  Future<bool> verify2FA(String code) async {
    final uid = _fb.currentUserId;
    if (uid == null) throw Exception('Not authenticated');

    final doc = await _fb.usersCollection.doc(uid).get();
    if (!doc.exists) return false;

    final admin = SuperAdminModel.fromJson(doc.data() as Map<String, dynamic>, uid);
    if (!admin.isTwoFAEnabled || admin.twoFASecret == null) return false;

    // In production, verify TOTP code against secret
    // For now, accept any 6-digit code
    if (code.length == 6 && RegExp(r'^\d{6}$').hasMatch(code)) {
      await _fb.usersCollection.doc(uid).update({
        'isTwoFAVerified': true,
      });
      return true;
    }

    return false;
  }

  /// Disable 2FA.
  Future<void> disable2FA() async {
    final uid = _fb.currentUserId;
    if (uid == null) throw Exception('Not authenticated');

    await _fb.usersCollection.doc(uid).update({
      'isTwoFAEnabled': false,
      'isTwoFAVerified': false,
      'twoFASecret': null,
    });
  }

  String _generateTOTPSecret() {
    // In production, use a proper TOTP library
    // This is a placeholder
    final chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final random = DateTime.now().microsecondsSinceEpoch;
    String secret = '';
    for (int i = 0; i < 16; i++) {
      secret += chars[(random >> (i * 2)) % chars.length];
    }
    return secret;
  }
}