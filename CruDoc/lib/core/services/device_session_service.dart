import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Manages active device sessions for doctors and enforces single-device
/// vs. multi-device login policy based on Super Admin access permissions.
class DeviceSessionService {
  DeviceSessionService._();
  static final DeviceSessionService instance = DeviceSessionService._();

  static const String _sessionKey = 'current_device_session_token';
  final _uuid = const Uuid();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSub;
  String? _localSessionToken;
  bool _isRegistering = false;

  /// Returns the current device's local session token.
  Future<String?> getLocalSessionToken() async {
    if (_localSessionToken != null) return _localSessionToken;
    final prefs = await SharedPreferences.getInstance();
    _localSessionToken = prefs.getString(_sessionKey);
    return _localSessionToken;
  }

  /// Clears the local session token from memory and storage on sign out.
  Future<void> clearSessionToken() async {
    _localSessionToken = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionKey);
    } catch (_) {}
  }

  /// Registers a new active session upon successful doctor login.
  /// Generates a fresh unique session token, persists it locally, and
  /// updates Firestore `users/{doctorId}`.
  Future<String> registerNewSession(String doctorId) async {
    _isRegistering = true;
    final newToken = _uuid.v4();
    _localSessionToken = newToken;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sessionKey, newToken);

      await FirebaseFirestore.instance.collection('users').doc(doctorId).set({
        'currentSessionToken': newToken,
        'lastLoginDeviceAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('DeviceSessionService: Failed to update currentSessionToken in Firestore: $e');
    } finally {
      _isRegistering = false;
    }

    return newToken;
  }

  /// Starts listening for session changes on `users/{doctorId}`.
  /// If `allowMultiDevice` is `false` and another device logs in
  /// (changing `currentSessionToken`), this device is automatically
  /// signed out with [onForcedLogout].
  ///
  /// IMPORTANT: The listener reads `_localSessionToken` dynamically
  /// on every snapshot (not a captured closure variable) so that
  /// `registerNewSession()` called elsewhere always stays in sync.
  void startSessionMonitoring(
    String doctorId, {
    required void Function(String reason) onForcedLogout,
  }) {
    stopSessionMonitoring();

    _sessionSub = FirebaseFirestore.instance
        .collection('users')
        .doc(doctorId)
        .snapshots()
        .listen(
      (snapshot) async {
        if (!snapshot.exists) return;
        if (_isRegistering) return;

        final data = snapshot.data();
        if (data == null) return;

        // Read the CURRENT in-memory token — not a stale closure copy.
        // If no token has been registered yet (login still in progress),
        // skip this snapshot entirely.
        final currentLocalToken = _localSessionToken;
        if (currentLocalToken == null || currentLocalToken.isEmpty) return;

        final allowMultiDevice = data['allowMultiDevice'] as bool? ?? false;
        final remoteToken = data['currentSessionToken'] as String?;

        // Only force-logout when multi-device is disallowed AND a
        // *different* device wrote a newer token.
        if (!allowMultiDevice &&
            remoteToken != null &&
            remoteToken.isNotEmpty &&
            remoteToken != currentLocalToken) {
          debugPrint(
            'DeviceSessionService: Session invalidated by newer login on another device.',
          );

          stopSessionMonitoring();
          await clearSessionToken();

          try {
            await FirebaseAuth.instance.signOut();
          } catch (e) {
            debugPrint('DeviceSessionService: Error during forced sign out: $e');
          }

          onForcedLogout(
            'Logged out: Your account was accessed from another device.',
          );
        }
      },
      onError: (error) {
        debugPrint('DeviceSessionService error: $error');
      },
    );
  }

  /// Stops monitoring active session changes.
  void stopSessionMonitoring() {
    _sessionSub?.cancel();
    _sessionSub = null;
  }
}
