import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One tooth's real surface: cheek-side view and biting surface.
class ToothTexture {
  const ToothTexture({
    required this.buccal,
    required this.occlusal,
    ui.Image? crown,
    ui.Image? root,
  })  : crown = crown ?? buccal,
        root = root ?? buccal;

  final ui.Image buccal;
  final ui.Image occlusal;
  final ui.Image crown;
  final ui.Image root;
}

/// Surface textures for the chart teeth rendered from the 3D tooth model.
/// Decoded once, on first use; listeners hear when they're ready.
class ToothTextures extends ChangeNotifier {
  ToothTextures._();

  static final instance = ToothTextures._();

  final Map<String, ToothTexture> _teeth = {};
  bool _started = false;

  /// Goes up when textures arrive, so painters know to redraw.
  int version = 0;

  ToothTexture? of(String tooth) => _teeth[_rightSide(adultOf(tooth))];

  /// The adult tooth whose texture stands in for [tooth] (FDI).
  static String adultOf(String tooth) {
    if (tooth.length != 2) return tooth;
    final q = tooth.codeUnitAt(0) - 48;
    if (q < 5 || q > 8) return tooth;
    final t = tooth.codeUnitAt(1) - 48;
    return '${q - 4}${t >= 4 ? 6 : t}';
  }

  /// Maps left-side teeth (quadrants 2, 3) to the corresponding right-side tooth (quadrants 1, 4).
  static String _rightSide(String tooth) {
    if (tooth.length != 2) return tooth;
    final q = tooth.codeUnitAt(0) - 48;
    final t = tooth[1];
    if (q == 2) return '1$t';
    if (q == 3) return '4$t';
    return tooth;
  }

  Future<void>? _loadFuture;

  /// Starts loading (once). Safe to call from build.
  Future<void> ensureLoaded() {
    if (_started) return _loadFuture ?? Future.value();
    _started = true;
    return _loadFuture = _load();
  }

  Future<void> _load() async {
    for (final q in const [1, 4]) {
      for (var t = 1; t <= 8; t++) {
        final n = '$q$t';
        final buccal = await _decode('${n}_m_buccal');
        final occlusal = await _decode('${n}_m_occlusal');
        if (buccal != null && occlusal != null) {
          _teeth[n] = ToothTexture(
            buccal: buccal,
            occlusal: occlusal,
          );
        }
      }
    }
    version++;
    notifyListeners();
  }

  static Future<ui.Image?> _decode(String name) async {
    try {
      final data = await rootBundle.load('assets/images/teeth/$name.webp');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }
}
