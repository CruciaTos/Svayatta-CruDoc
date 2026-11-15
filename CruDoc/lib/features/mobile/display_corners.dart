import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The phone screen's rounded-corner radius, in logical pixels, so the
/// island's grown shapes follow the display's curve instead of being cut
/// by it.
///
/// - Android 12+: the exact radius the system reports for this model.
/// - Older Android: unknown, so a safe [fallback].
/// - iOS: no API; Apple's screens are covered by [iosRadius].
class DisplayCorners {
  DisplayCorners._();

  static const _channel = MethodChannel('crudoc/display');

  /// Radius used when the phone can't report one. Larger than most real
  /// corners, so it errs on the safe side.
  static const fallback = 44.0;

  /// Android's reported radius once loaded (null until then).
  static final android = ValueNotifier<double?>(null);
  static bool _asked = false;

  /// Asks Android once. [dpr] converts pixels to logical pixels.
  static Future<void> load(double dpr) async {
    if (_asked || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _asked = true;
    try {
      final px = await _channel.invokeMethod<int>('cornerRadius');
      android.value = (px == null || px < 0) ? fallback : px / dpr;
    } catch (_) {
      android.value = fallback;
    }
  }

  /// Hides Android's status bar so the island owns the top strip. A swipe
  /// from the top shows it briefly; it hides itself again.
  static Future<void> hideStatusBar() async {
    try {
      await _channel.invokeMethod<void>('hideStatusBar');
    } catch (_) {}
  }

  static Future<void> showStatusBar() async {
    try {
      await _channel.invokeMethod<void>('showStatusBar');
    } catch (_) {}
  }

  /// iPhone display corners by safe-area top: Dynamic Island phones about
  /// 55, notch phones about 44, home-button phones square.
  static double iosRadius(double viewPaddingTop) => viewPaddingTop >= 51
      ? 55
      : viewPaddingTop >= 44
      ? 44
      : 0;

  /// The radius for this phone right now.
  static double resolve(double viewPaddingTop) =>
      switch (defaultTargetPlatform) {
        TargetPlatform.iOS => iosRadius(viewPaddingTop),
        TargetPlatform.android => android.value ?? fallback,
        _ => 0,
      };
}
