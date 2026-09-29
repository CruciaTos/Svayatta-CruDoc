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

enum TextSizePreference {
  small('Small', 0.9),
  standard('Standard', 1.0),
  large('Large', 1.1);

  const TextSizePreference(this.label, this.scale);

  final String label;
  final double scale;

  static TextSizePreference fromName(String? name) =>
      TextSizePreference.values.firstWhere(
        (size) => size.name == name,
        orElse: () => TextSizePreference.standard,
      );
}

/// `shared_preferences` storage for [AppearanceMode] (device-local, like
/// the other desktop preferences).
class AppearancePreferences {
  static const String _key = 'crudoc.settings.appearance_mode';
  static const String _textSizeKey = 'crudoc.settings.text_size';
  static const String _dayBackgroundColorKey =
      'crudoc.settings.day_background_color';
  static const int defaultDayBackgroundColor = 0xFFEEF1F6;

  Future<AppearanceMode> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    return AppearanceMode.fromName(prefs.getString(_key));
  }

  Future<void> setMode(AppearanceMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  Future<TextSizePreference> getTextSize() async {
    final prefs = await SharedPreferences.getInstance();
    return TextSizePreference.fromName(prefs.getString(_textSizeKey));
  }

  Future<void> setTextSize(TextSizePreference size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_textSizeKey, size.name);
  }

  Future<int> getDayBackgroundColor() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_dayBackgroundColorKey) ?? defaultDayBackgroundColor;
  }

  Future<void> setDayBackgroundColor(int argb) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dayBackgroundColorKey, argb);
  }
}
