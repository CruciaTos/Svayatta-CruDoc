import 'package:shared_preferences/shared_preferences.dart';

/// Thin `shared_preferences` wrapper for the local-only state that
/// makes throttling and "don't nag" behavior possible without any
/// server-side flag (design principle #6). Every method matches the
/// contract already relied on by `update_controller.dart`.
class UpdatePreferences {
  UpdatePreferences();

  static const String _kLastCheckedAtKey = 'crudoc.update.last_checked_at';
  static const String _kSkippedVersionKey = 'crudoc.update.skipped_version';
  static const String _kLastNotifiedVersionKey = 'crudoc.update.last_notified_version';

  /// When the last startup/manual check completed, or null if
  /// [checkForUpdate] has never run on this device.
  Future<DateTime?> getLastCheckedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_kLastCheckedAtKey);
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> setLastCheckedAt(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastCheckedAtKey, time.millisecondsSinceEpoch);
  }

  /// The version the user chose to "Skip", if any. [checkForUpdate]
  /// silently treats a matching release as up to date until a *newer*
  /// version is published.
  Future<String?> getSkippedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSkippedVersionKey);
  }

  Future<void> setSkippedVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSkippedVersionKey, version);
  }

  /// The version most recently shown to the user via the dialog/banner
  /// — stamped on "Later" so the persisted state reflects what was
  /// actually surfaced, ready for a future cross-restart cooldown
  /// refinement (see `UpdateController.remindLater`'s doc comment).
  Future<void> setLastNotifiedVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastNotifiedVersionKey, version);
  }

  Future<String?> getLastNotifiedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLastNotifiedVersionKey);
  }
}
