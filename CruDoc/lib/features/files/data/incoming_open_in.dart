import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/core/router/app_router.dart';
import 'package:doctor_management_app/features/files/presentation/files_actions.dart';

/// Listens for files opened in CruDoc via AirDrop or system share sheet (iOS/iPadOS).
class IncomingOpenIn {
  static bool _started = false;
  static final List<String> _pendingPaths = [];
  static Timer? _retryTimer;
  static DateTime? _retryDeadline;
  static StreamSubscription<Uri>? _sub;

  /// Starts listening for file links. iOS only; safe to call multiple times.
  static void start() {
    if (kIsWeb || !Platform.isIOS) return;
    if (_started) return;
    _started = true;

    final appLinks = AppLinks();

    // Check initial link on cold launch
    appLinks
        .getInitialLink()
        .then((uri) {
          if (uri != null) _handleUri(uri);
        })
        .catchError((e) {
          debugPrint('[IncomingOpenIn] Initial link error: $e');
        });

    // Listen for subsequent links while app is running
    _sub = appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (e) {
        debugPrint('[IncomingOpenIn] Stream error: $e');
      },
    );
  }

  static void _handleUri(Uri uri) {
    if (!uri.isScheme('file')) return;
    try {
      final filePath = uri.toFilePath();
      if (!File(filePath).existsSync()) return;
      if (!_pendingPaths.contains(filePath)) {
        _pendingPaths.add(filePath);
      }
      _scheduleFlush();
    } catch (e) {
      debugPrint('[IncomingOpenIn] Error handling uri: $e');
    }
  }

  static void _scheduleFlush() {
    _retryDeadline ??= DateTime.now().add(const Duration(minutes: 2));
    _tryFlush();
  }

  static void _tryFlush() {
    _retryTimer?.cancel();
    _retryTimer = null;

    if (_pendingPaths.isEmpty) {
      _retryDeadline = null;
      return;
    }

    if (DateTime.now().isAfter(_retryDeadline!)) {
      debugPrint(
        '[IncomingOpenIn] 2-minute deadline reached without auth or router context. Dropping pending files.',
      );
      _pendingPaths.clear();
      _retryDeadline = null;
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    final context = appRouter.routerDelegate.navigatorKey.currentContext;

    if (user != null && context != null && context.mounted) {
      final paths = List<String>.from(_pendingPaths);
      _pendingPaths.clear();
      _retryDeadline = null;
      FilesActions.addPaths(context, paths);
    } else {
      _retryTimer = Timer(const Duration(seconds: 2), _tryFlush);
    }
  }

  /// Cancels subscriptions and timers.
  static void dispose() {
    _sub?.cancel();
    _sub = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _pendingPaths.clear();
    _retryDeadline = null;
    _started = false;
  }
}
