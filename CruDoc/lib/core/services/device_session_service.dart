import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/device_session.dart';
import '../utils/device_info_helper.dart';

/// Manages active device sessions for doctors and enforces single-device
/// vs. multi-device login policy based on Super Admin access permissions,
/// with per-device tracking, remote revocation, and real-time heartbeat.
class DeviceSessionService {
  DeviceSessionService._();
  static final DeviceSessionService instance = DeviceSessionService._();

  static const String _sessionKey = 'current_device_session_token';
  final _uuid = const Uuid();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSub;
  Timer? _heartbeatTimer;

  String? _localSessionToken;
  String? _monitoredDoctorId;
  bool _isRegistering = false;

  /// Returns the doctor UID currently being monitored, if any.
  String? get monitoredDoctorId => _monitoredDoctorId;

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
    stopHeartbeat();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionKey);
    } catch (_) {}
  }

  /// Registers a new active session upon doctor login.
  /// Handles both single-device eviction and multi-device registration.
  Future<String> registerNewSession(
    String doctorId, {
    String? customDeviceName,
  }) async {
    _isRegistering = true;
    final newToken = _uuid.v4();
    _localSessionToken = newToken;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sessionKey, newToken);

      final deviceName = customDeviceName ?? await DeviceInfoHelper.getDeviceDisplayName();
      final platform = DeviceInfoHelper.getPlatformKey();
      final appVersion = await DeviceInfoHelper.getAppVersion();

      final userRef = FirebaseFirestore.instance.collection('users').doc(doctorId);
      final userSnap = await userRef.get();
      final userData = userSnap.data() ?? {};

      bool allowMultiDevice = userData['allowMultiDevice'] as bool? ?? false;
      if (allowMultiDevice) {
        final rawExpires = userData['expiresDate'];
        DateTime? expiresDate;
        if (rawExpires is Timestamp) {
          expiresDate = rawExpires.toDate();
        } else if (rawExpires is String) {
          expiresDate = DateTime.tryParse(rawExpires);
        }
        if (expiresDate != null && expiresDate.isBefore(DateTime.now())) {
          allowMultiDevice = false;
        }
      }

      final sessionsCol = userRef.collection('active_sessions');

      if (!allowMultiDevice) {
        // Enforce single-device: purge existing active sessions
        try {
          final existingSessions = await sessionsCol.where('status', isEqualTo: 'active').get();
          final batch = FirebaseFirestore.instance.batch();
          for (final doc in existingSessions.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();
        } catch (e) {
          debugPrint('DeviceSessionService: Error cleaning previous sessions: $e');
        }
      } else {
        // Check max device limit (0 or null means unlimited)
        final maxLimit = (userData['maxDeviceLimit'] as num?)?.toInt() ?? 0;
        if (maxLimit > 0) {
          try {
            final activeDocs = await sessionsCol
                .where('status', isEqualTo: 'active')
                .orderBy('lastActiveAt', descending: false)
                .get();

            if (activeDocs.docs.length >= maxLimit) {
              // Revoke/delete oldest sessions to fit within limit
              final toRemove = activeDocs.docs.length - maxLimit + 1;
              final batch = FirebaseFirestore.instance.batch();
              for (int i = 0; i < toRemove && i < activeDocs.docs.length; i++) {
                batch.delete(activeDocs.docs[i].reference);
              }
              await batch.commit();
            }
          } catch (e) {
            debugPrint('DeviceSessionService: Error enforcing maxDeviceLimit: $e');
          }
        }
      }

      // Create new active session record
      final now = DateTime.now();
      final sessionModel = DeviceSession(
        sessionId: newToken,
        doctorId: doctorId,
        deviceName: deviceName,
        platform: platform,
        appVersion: appVersion,
        createdAt: now,
        lastActiveAt: now,
        status: 'active',
        isCurrentDevice: true,
      );

      final batch = FirebaseFirestore.instance.batch();
      batch.set(sessionsCol.doc(newToken), sessionModel.toFirestore());
      batch.set(
        userRef,
        {
          'currentSessionToken': newToken,
          'lastLoginDeviceAt': FieldValue.serverTimestamp(),
          'lastLoginPlatform': platform,
          'lastLoginDeviceName': deviceName,
        },
        SetOptions(merge: true),
      );

      await batch.commit();
      _startHeartbeat(doctorId, newToken);
    } catch (e) {
      debugPrint('DeviceSessionService: Failed to register session in Firestore: $e');
    } finally {
      _isRegistering = false;
    }

    return newToken;
  }

  /// Starts monitoring session validity for [doctorId].
  /// Triggers [onForcedLogout] when session is revoked remotely or overridden.
  void startSessionMonitoring(
    String doctorId, {
    required void Function(String reason) onForcedLogout,
  }) {
    stopSessionMonitoring();
    _monitoredDoctorId = doctorId;

    // 1. Listen to user document for multi-device toggle & single-device token changes
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(doctorId)
        .snapshots()
        .listen(
      (snapshot) async {
        if (!snapshot.exists) return;
        if (_isRegistering) return;

        final data = snapshot.data();
        if (data == null) return;

        final currentLocalToken = _localSessionToken;
        if (currentLocalToken == null || currentLocalToken.isEmpty) return;

        bool allowMultiDevice = data['allowMultiDevice'] as bool? ?? false;
        if (allowMultiDevice) {
          final rawExpires = data['expiresDate'];
          DateTime? expiresDate;
          if (rawExpires is Timestamp) {
            expiresDate = rawExpires.toDate();
          } else if (rawExpires is String) {
            expiresDate = DateTime.tryParse(rawExpires);
          }
          if (expiresDate != null && expiresDate.isBefore(DateTime.now())) {
            allowMultiDevice = false; // Expired reverts to single-device
          }
        }
        final remoteToken = data['currentSessionToken'] as String?;

        // In single-device mode, a different session token means another device logged in
        if (!allowMultiDevice &&
            remoteToken != null &&
            remoteToken.isNotEmpty &&
            remoteToken != currentLocalToken) {
          debugPrint('DeviceSessionService: Session invalidated by newer login on another device.');
          await _handleForcedLogout(
            'Logged out: Your account was accessed from another device.',
            onForcedLogout,
          );
        }
      },
      onError: (error) {
        debugPrint('DeviceSessionService userSub error: $error');
      },
    );

    // 2. Listen to this specific device session doc in active_sessions
    _watchIndividualSession(doctorId, onForcedLogout);
  }

  Future<void> _watchIndividualSession(
    String doctorId,
    void Function(String reason) onForcedLogout,
  ) async {
    final token = await getLocalSessionToken();
    if (token == null || token.isEmpty) return;

    _sessionSub?.cancel();
    _sessionSub = FirebaseFirestore.instance
        .collection('users')
        .doc(doctorId)
        .collection('active_sessions')
        .doc(token)
        .snapshots()
        .listen(
      (snapshot) async {
        if (_isRegistering) return;
        if (!snapshot.exists) {
          // Session document was deleted (revoked remotely)
          debugPrint('DeviceSessionService: Session doc deleted remotely.');
          await _handleForcedLogout(
            'Your session was ended remotely.',
            onForcedLogout,
          );
          return;
        }

        final data = snapshot.data();
        if (data != null && data['status'] == 'revoked') {
          debugPrint('DeviceSessionService: Session marked as revoked.');
          await _handleForcedLogout(
            'Your session has been revoked.',
            onForcedLogout,
          );
        }
      },
      onError: (error) {
        debugPrint('DeviceSessionService sessionSub error: $error');
      },
    );

    _startHeartbeat(doctorId, token);
  }

  Future<void> _handleForcedLogout(
    String reason,
    void Function(String reason) onForcedLogout,
  ) async {
    stopSessionMonitoring();
    await clearSessionToken();

    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('DeviceSessionService: Error during forced sign out: $e');
    }

    onForcedLogout(reason);
  }

  /// Heartbeat updates lastActiveAt on Firestore every 5 minutes.
  void _startHeartbeat(String doctorId, String token) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(doctorId)
            .collection('active_sessions')
            .doc(token)
            .update({'lastActiveAt': FieldValue.serverTimestamp()});
      } catch (e) {
        debugPrint('DeviceSessionService: Heartbeat update warning: $e');
      }
    });
  }

  /// Stops heartbeat timer.
  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Stops monitoring active session changes.
  void stopSessionMonitoring() {
    _userSub?.cancel();
    _userSub = null;
    _sessionSub?.cancel();
    _sessionSub = null;
    stopHeartbeat();
    _monitoredDoctorId = null;
  }

  /// Streams the list of all active sessions for a doctor in real-time.
  Stream<List<DeviceSession>> watchActiveSessions(String doctorId) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(doctorId)
        .collection('active_sessions')
        .snapshots()
        .map((snapshot) {
      final currentToken = _localSessionToken;
      final list = snapshot.docs
          .map((doc) => DeviceSession.fromFirestore(doc, currentLocalToken: currentToken))
          .where((s) => s.isActive)
          .toList();

      list.sort((a, b) {
        // Current device first, then sorted by most recent activity
        if (a.isCurrentDevice) return -1;
        if (b.isCurrentDevice) return 1;
        return b.lastActiveAt.compareTo(a.lastActiveAt);
      });

      return list;
    });
  }

  /// Revokes a specific session remotely.
  Future<void> revokeSession(String doctorId, String sessionId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(doctorId)
          .collection('active_sessions')
          .doc(sessionId)
          .delete();
    } catch (e) {
      debugPrint('DeviceSessionService: Failed to revoke session $sessionId: $e');
      rethrow;
    }
  }

  /// Revokes all sessions except the current active device.
  Future<void> revokeAllOtherSessions(String doctorId) async {
    try {
      final token = await getLocalSessionToken();
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(doctorId)
          .collection('active_sessions')
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        if (doc.id != token) {
          batch.delete(doc.reference);
        }
      }
      await batch.commit();
    } catch (e) {
      debugPrint('DeviceSessionService: Failed to revoke all other sessions: $e');
      rethrow;
    }
  }

  /// Revokes all active sessions for a doctor (e.g. by Super Admin).
  Future<void> revokeAllSessions(String doctorId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(doctorId)
          .collection('active_sessions')
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      batch.update(
        FirebaseFirestore.instance.collection('users').doc(doctorId),
        {'currentSessionToken': FieldValue.delete()},
      );
      await batch.commit();
    } catch (e) {
      debugPrint('DeviceSessionService: Failed to revoke all sessions for $doctorId: $e');
      rethrow;
    }
  }
}
