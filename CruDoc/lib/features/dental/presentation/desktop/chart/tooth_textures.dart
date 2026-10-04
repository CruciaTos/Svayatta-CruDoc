import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One tooth's real surface: crown and root from the cheek side, and the
/// biting surface.
class ToothTexture {
  const ToothTexture({
    required this.crown,
    required this.root,
    required this.occlusal,
  });

  final ui.Image crown;
  final ui.Image root;
  final ui.Image occlusal;
}

/// Surface textures for the drawn 2.5D chart teeth (BoneBox™ Dental by
/// iso-form, used with permission; made by
/// tool/teeth/make_tooth_textures.py). The chart draws each tooth's shape
/// and size itself and fills it with these. Milk teeth borrow the adult
/// tooth in the same place (their molars the first molar).
///
/// Decoded once, on first use; listeners hear when they're ready.
class ToothTextures extends ChangeNotifier {
  ToothTextures._();

  static final instance = ToothTextures._();

  final Map<String, ToothTexture> _teeth = {};
  bool _started = false;

  /// Goes up when textures arrive, so painters know to redraw.
  int version = 0;

  ToothTexture? of(String tooth) => _teeth[_adult(tooth)];

  /// The adult tooth whose texture stands in for [tooth] (FDI).
  static String _adult(String tooth) {
    if (tooth.length != 2) return tooth;
    final q = tooth.codeUnitAt(0) - 48;
    if (q < 5 || q > 8) return tooth;
    final t = tooth.codeUnitAt(1) - 48;
    return '${q - 4}${t >= 4 ? 6 : t}';
  }

  /// Starts loading (once). Safe to call from build.
  void ensureLoaded() {
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    for (final q in const [1, 2, 3, 4]) {
      for (var t = 1; t <= 8; t++) {
        final n = '$q$t';
        final crown = await _decode('${n}_tex_crown');
        final root = await _decode('${n}_tex_root');
        final occlusal = await _decode('${n}_tex_occlusal');
        if (crown != null && root != null && occlusal != null) {
          _teeth[n] = ToothTexture(
            crown: crown,
            root: root,
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
      // A missing texture leaves that tooth painted.
      return null;
    }
  }
}
