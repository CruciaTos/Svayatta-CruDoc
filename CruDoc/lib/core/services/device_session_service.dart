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

  /// Returns the current device's local session token.
  Future<String?> getLocalSessionToken() async {
    if (_localSessionToken != null) return _localSessionToken;
    final prefs = await SharedPreferences.getInstance();
    _localSessionToken = prefs.getString(_sessionKey);
    return _localSessionToken;
  }

  /// Registers a new active session upon successful doctor login.
  /// Generates a fresh unique session token, persists it locally, and
  /// updates Firestore `users/{doctorId}`.
  Future<String> registerNewSession(String doctorId) async {
    final newToken = _uuid.v4();
    _localSessionToken = newToken;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, newToken);

    try {
      await FirebaseFirestore.instance.collection('users').doc(doctorId).update({
        'currentSessionToken': newToken,
        'lastLoginDeviceAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('DeviceSessionService: Failed to update currentSessionToken in Firestore: $e');
    }

    return newToken;
  }

  /// Starts listening for session changes on `users/{doctorId}`.
  /// If `allowMultiDevice` is `false` and another device logs in (changing `currentSessionToken`),
  /// this device is automatically signed out with [onForcedLogout].
  void startSessionMonitoring(
    String doctorId, {
    required void Function(String reason) onForcedLogout,
  }) async {
    stopSessionMonitoring();

    final localToken = await getLocalSessionToken();

    if (localToken == null || localToken.isEmpty) {
      debugPrint('DeviceSessionService: No local session token found for $doctorId');
      return;
    }

    _sessionSub = FirebaseFirestore.instance
        .collection('users')
        .doc(doctorId)
        .snapshots()
        .listen(
      (snapshot) async {
        if (!snapshot.exists) return;
        final data = snapshot.data();
        if (data == null) return;

        final allowMultiDevice = data['allowMultiDevice'] as bool? ?? false;
        final remoteToken = data['currentSessionToken'] as String?;

        // If multi-device login is NOT allowed and another token is registered in Firestore
        if (!allowMultiDevice &&
            remoteToken != null &&
            remoteToken.isNotEmpty &&
            remoteToken != localToken) {
          debugPrint('DeviceSessionService: Session invalidated by newer login on another device.');

          stopSessionMonitoring();

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
