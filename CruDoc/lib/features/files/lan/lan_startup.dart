import 'package:shared_preferences/shared_preferences.dart';

/// Lets screens start nearby sharing after the doctor agrees (Apple devices).
/// `main.dart` sets [starter] each time a clinic opens.
class LanStartup {
  static Future<void> Function()? starter;

  /// Apple devices ask the doctor first; everywhere else it is on already.
  static const askedKey = 'crudoc.lan.askedApple';

  static Future<bool> hasAsked() async =>
      (await SharedPreferences.getInstance()).getBool(askedKey) ?? false;

  static Future<void> markAsked() async =>
      (await SharedPreferences.getInstance()).setBool(askedKey, true);
}

