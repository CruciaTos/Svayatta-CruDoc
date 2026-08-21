import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Helper to obtain safe, human-readable device name, platform identifier,
/// and app version across Web, Android, iOS, Windows, macOS, and Linux.
class DeviceInfoHelper {
  DeviceInfoHelper._();

  /// Returns platform key (e.g. 'web', 'android', 'ios', 'windows', 'macos', 'linux').
  static String getPlatformKey() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      default:
        return 'unknown';
    }
  }

  /// Returns a clean, user-friendly device name for UI display.
  static Future<String> getDeviceDisplayName() async {
    if (kIsWeb) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.windows:
          return 'Web Browser (Windows)';
        case TargetPlatform.macOS:
          return 'Web Browser (macOS)';
        case TargetPlatform.linux:
          return 'Web Browser (Linux)';
        case TargetPlatform.android:
          return 'Web Browser (Android)';
        case TargetPlatform.iOS:
          return 'Web Browser (iOS / Safari)';
        default:
          return 'Web Browser';
      }
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android Mobile / Tablet';
      case TargetPlatform.iOS:
        return 'iPhone / iPad';
      case TargetPlatform.windows:
        return 'Windows Desktop App';
      case TargetPlatform.macOS:
        return 'macOS Desktop App';
      case TargetPlatform.linux:
        return 'Linux Desktop App';
      default:
        return 'Device';
    }
  }

  /// Returns the current app version string (e.g., "1.0.0 (1)").
  static Future<String> getAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return '1.0.0';
    }
  }
}
