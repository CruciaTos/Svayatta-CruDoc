import 'package:shared_preferences/shared_preferences.dart';

/// The doctor's appearance choice. Auto follows the clinic day: Evening
/// from the evening session until morning, Day otherwise.
enum AppearanceMode {
  auto('Auto'),
  day('Day'),
  evening('Evening');

  const AppearanceMode(this.label);
  final String label;

  static AppearanceMode fromName(String? name) => AppearanceMode.values
      .firstWhere((m) => m.name == name, orElse: () => AppearanceMode.auto);
}

/// `shared_preferences` storage for [AppearanceMode] (device-local, like
/// the other desktop preferences).
class AppearancePreferences {
  static const String _key = 'crudoc.settings.appearance_mode';

  Future<AppearanceMode> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    return AppearanceMode.fromName(prefs.getString(_key));
  }

  Future<void> setMode(AppearanceMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}
