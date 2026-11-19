import 'package:crudoc_shared/theme/cru_tokens.dart' show CruMotion;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fewer animations and less memory for phones that struggle.
///
/// Automatic by default: on when the phone reports low RAM. A person can
/// force it on or off in Settings; that choice is stored as 'on' / 'off'
/// (no value means automatic).
abstract final class LowEndMode {
  static const _key = 'perf.lowEndMode';
  static const _channel = MethodChannel('crudoc/device');

  /// Flutter's own image cache limits, put back when the mode turns off.
  static const _defaultImageBytes = 100 << 20;
  static const _defaultImageCount = 1000;
  static const _lowImageBytes = 40 << 20;
  static const _lowImageCount = 300;

  /// The effective value: the stored choice, else what the phone reports.
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  /// The stored choice: null (automatic), 'on' or 'off'.
  static final ValueNotifier<String?> mode = ValueNotifier<String?>(null);

  /// What the phone reports (low RAM), whatever the choice.
  static bool deviceIsLowEnd = false;

  static bool _listening = false;

  /// Reads the stored choice and asks the phone about its memory. Never
  /// throws: any failure leaves the mode off.
  static Future<void> init() async {
    String? stored;
    try {
      final prefs = await SharedPreferences.getInstance();
      stored = _clean(prefs.getString(_key));
    } catch (_) {}
    var low = false;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        low = await _channel.invokeMethod<bool>('isLowEnd') ?? false;
      } catch (_) {}
    }
    deviceIsLowEnd = low;
    mode.value = stored;
    if (!_listening) {
      _listening = true;
      enabled.addListener(_apply);
    }
    enabled.value = _resolve(stored);
    _apply();
  }

  /// Stores the choice (null: automatic, 'on', 'off') and applies it.
  static Future<void> setMode(String? value) async {
    final next = _clean(value);
    mode.value = next;
    enabled.value = _resolve(next);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (next == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, next);
      }
    } catch (_) {}
  }

  static String? _clean(String? v) => v == 'on' || v == 'off' ? v : null;

  static bool _resolve(String? stored) =>
      stored == null ? deviceIsLowEnd : stored == 'on';

  /// Smaller image cache, and CruMotion.of treats animations as off.
  static void _apply() {
    final on = enabled.value;
    CruMotion.forceReduced = on;
    try {
      final cache = PaintingBinding.instance.imageCache;
      cache.maximumSizeBytes = on ? _lowImageBytes : _defaultImageBytes;
      cache.maximumSize = on ? _lowImageCount : _defaultImageCount;
    } catch (_) {}
  }
}
