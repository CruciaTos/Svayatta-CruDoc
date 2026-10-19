import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// System notifications for this device, and its push registration.
///
/// Pushes (Firebase Cloud Messaging) reach Android and iOS even when the app
/// is closed: the server sends them to every token in
/// `users/{uid}/device_tokens`. Windows and macOS have no such push, so
/// while the app runs they show the same news as a native notification,
/// raised from a Firestore listener ([show]).
///
/// Never throws: a missing permission or plugin only means no notification.
class PushNotifications {
  PushNotifications._();

  static final PushNotifications instance = PushNotifications._();

  /// Android channel for referrals; the server sends pushes to it too.
  static const referralChannel = AndroidNotificationChannel(
    'referrals',
    'Referrals',
    description: 'Referrals other doctors send you, and their replies',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;
  StreamSubscription<String>? _tokenSub;
  final List<StreamSubscription<RemoteMessage>> _openSubs = [];
  String? _registeredUid;

  /// Runs when a notification (local or push) is tapped.
  VoidCallback? onOpen;

  static bool get _hasPush => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<bool> _init() => _ready ??= _doInit();

  Future<bool> _doInit() async {
    if (kIsWeb || Platform.isLinux) return false;
    try {
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: darwin,
          macOS: darwin,
          windows: WindowsInitializationSettings(
            appName: 'CruDoc',
            appUserModelId: 'Svayatta.CruDoc.Desktop',
            guid: '6f1d6c1e-5a43-4c8e-9b7e-2f6a1d3c9e41',
          ),
        ),
        onDidReceiveNotificationResponse: (_) => onOpen?.call(),
      );
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(referralChannel);
      await android?.requestNotificationsPermission();
      return true;
    } catch (e) {
      debugPrint('[PushNotifications] init failed: $e');
      return false;
    }
  }

  /// Shows a notification now, on any platform the plugin supports.
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!await _init()) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            referralChannel.id,
            referralChannel.name,
            channelDescription: referralChannel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
          macOS: const DarwinNotificationDetails(),
          windows: const WindowsNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('[PushNotifications] show failed: $e');
    }
  }

  /// Registers this device for pushes to [uid] (Android and iOS only). Asks
  /// for permission the first time. Safe to call again.
  Future<void> register(String uid) async {
    await _init();
    if (!_hasPush || _registeredUid == uid) return;
    try {
      final fm = FirebaseMessaging.instance;
      final settings = await fm.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await fm.getToken();
      if (token == null) return;
      await _saveToken(uid, token);
      _registeredUid = uid;
      await _tokenSub?.cancel();
      _tokenSub = fm.onTokenRefresh.listen((t) => _saveToken(uid, t));
      if (_openSubs.isEmpty) {
        _openSubs.add(
          FirebaseMessaging.onMessageOpenedApp.listen((_) => onOpen?.call()),
        );
        // Opened from a push while the app was closed.
        if (await fm.getInitialMessage() != null) onOpen?.call();
      }
    } catch (e) {
      debugPrint('[PushNotifications] register failed: $e');
    }
  }

  /// Stops pushes to this device for the signed-in person. Call before
  /// signing out, while the rules still let them delete their own token.
  Future<void> forgetThisDevice() async {
    _registeredUid = null;
    await _tokenSub?.cancel();
    _tokenSub = null;
    if (!_hasPush) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _tokenRef(uid, token).delete();
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('[PushNotifications] forget failed: $e');
    }
  }

  DocumentReference<Map<String, dynamic>> _tokenRef(String uid, String token) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('device_tokens')
          // Tokens are long and may hold characters ids shouldn't.
          .doc(sha256.convert(utf8.encode(token)).toString().substring(0, 40));

  Future<void> _saveToken(String uid, String token) =>
      _tokenRef(uid, token).set({
        'token': token,
        'platform': Platform.operatingSystem,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
