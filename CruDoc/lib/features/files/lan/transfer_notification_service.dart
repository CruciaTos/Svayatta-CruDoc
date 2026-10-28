import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Manages active transfer notifications, satisfying Android foreground service visibility requirements (Task N9).
class TransferNotificationService {
  TransferNotificationService._();
  static final TransferNotificationService instance =
      TransferNotificationService._();

  static const _channelId = 'crudoc_lan_transfers';
  static const _channelName = 'Nearby File Transfers';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized || !Platform.isAndroid) return;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description:
              'Shows progress for direct Wi-Fi file transfers with colleagues.',
          importance: Importance.low,
        ),
      );
      _initialized = true;
    } catch (e) {
      debugPrint('[TransferNotificationService] init error: $e');
    }
  }

  /// Shows or updates progress on the notification.
  Future<void> showProgress({
    required int id,
    required String title,
    required String subtitle,
    required int progressPercent,
  }) async {
    if (!Platform.isAndroid) return;
    await _init();

    try {
      await _plugin.show(
        id: id,
        title: title,
        body: subtitle,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Direct Wi-Fi file transfers',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            onlyAlertOnce: true,
            showProgress: true,
            maxProgress: 100,
            progress: progressPercent,
          ),
        ),
      );
    } catch (_) {}
  }

  /// Clears the transfer notification upon completion or cancel.
  Future<void> clear(int id) async {
    if (!Platform.isAndroid) return;
    await _plugin.cancel(id: id);
  }
}
