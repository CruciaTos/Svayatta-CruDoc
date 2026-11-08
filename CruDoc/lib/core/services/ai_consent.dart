import 'package:shared_preferences/shared_preferences.dart';

/// The doctor's choice about sending data to the cloud AI. Stored per device.
class AiConsent {
  static const _key = 'ai.consent.v1'; // 'yes' | 'no' | unset
  static bool? _cached;

  static Future<bool?> read() async {
    if (_cached != null) return _cached;
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_key);
    return _cached = v == null ? null : v == 'yes';
  }

  static Future<void> set(bool granted) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, granted ? 'yes' : 'no');
    _cached = granted;
  }

  /// True only when the doctor said yes.
  static Future<bool> get granted async => (await read()) == true;
}

class AiConsentRequired implements Exception {
  const AiConsentRequired();
  @override
  String toString() =>
      'AI is off. Turn it on in Settings > AI assistance to use this.';
}

