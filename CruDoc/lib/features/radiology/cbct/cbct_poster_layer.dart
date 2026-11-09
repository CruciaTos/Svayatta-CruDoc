import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import 'package:doctor_management_app/features/radiology/cbct/cbct_fit.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The page background the web viewer paints, read from the bundled
/// `layout.json` when that file exists; null when it doesn't (or has no
/// colour). Accepts `background`, `pageBackground` or `bg` as `#rrggbb`.
Future<Color?> cbctPageBackground() async {
  try {
    final j = jsonDecode(await rootBundle.loadString('assets/cbct_viewer/layout.json'));
    if (j is! Map) return null;
    for (final key in const ['background', 'pageBackground', 'bg']) {
      final v = j[key];
      if (v is String) {
        final hex = v.replaceFirst('#', '');
        if (hex.length == 6) return Color(0xFF000000 | int.parse(hex, radix: 16));
        if (hex.length == 8) return Color(int.parse(hex, radix: 16));
      }
    }
  } on Object {
    // No layout file yet.
  }
  return null;
}

/// The four saved pictures of a scan in the viewer's 2 x 2 layout (axial
/// top left, 3D top right, coronal bottom left, sagittal bottom right),
/// drawn over the WebView while it loads so the first frame already looks
/// like the viewer. Fades away when [visible] turns false.
class CbctPosterLayer extends StatefulWidget {
  const CbctPosterLayer({
    super.key,
    required this.packDir,
    required this.meta,
    required this.visible,
    this.background,
  });

  final Directory packDir;
  final Map<String, dynamic> meta;
  final bool visible;
  final Color? background;

  @override
  State<CbctPosterLayer> createState() => _CbctPosterLayerState();
}

class _CbctPosterLayerState extends State<CbctPosterLayer> {
  final Set<String> _canvas = {};

  @override
  void initState() {
    super.initState();
    _readState();
  }

  /// A view the page has saved from its own canvas is no longer a flat
  /// plane picture; it is shown whole instead of fitted to its extents.
  void _readState() {
    try {
      final f = File(p.join(widget.packDir.path, 'state.json'));
      if (!f.existsSync()) return;
      final j = jsonDecode(f.readAsStringSync());
      final posters = j is Map ? j['posters'] : null;
      if (posters is Map) {
        posters.forEach((k, v) {
          if (v is Map && v['kind'] == 'canvas') _canvas.add('$k');
        });
      }
    } on Object {
      // Plain posters then.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final bg = widget.background ?? c.canvas;
    final g = widget.meta['geometry'] as Map<String, dynamic>;
    final dims = (g['dims'] as List).cast<num>();
    final sp = (g['spacing'] as List).cast<num>();
    final ext = [for (var i = 0; i < 3; i++) (dims[i] * sp[i]).toDouble()];
    final names = (widget.meta['posters'] as Map?)?.cast<String, dynamic>() ?? const {};

    Widget cell(String id, String key, double? u, double? v) {
      final file = names[key];
      if (file is! String) return const SizedBox.shrink();
      final image = File(p.join(widget.packDir.path, file));
      return LayoutBuilder(
        builder: (context, box) {
          Widget img() => Image.file(
            image,
            fit: BoxFit.fill,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );
          if (u == null || v == null || _canvas.contains(id)) {
            return Image.file(
              image,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            );
          }
          final fit = CbctFit.of(width: box.maxWidth, height: box.maxHeight, u: u, v: v);
          return Stack(children: [Positioned.fromRect(rect: fit.rect, child: img())]);
        },
      );
    }

    final gutter = c.label2.withValues(alpha: 0.2);
    final reduced = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: reduced
            ? const Duration(milliseconds: 80)
            : const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        child: ColoredBox(
          color: bg,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: cell('axial', 'axial', ext[0], ext[1])),
                    ColoredBox(color: gutter, child: const SizedBox(width: 1)),
                    Expanded(child: cell('3d', 'threeD', null, null)),
                  ],
                ),
              ),
              ColoredBox(color: gutter, child: const SizedBox(height: 1)),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: cell('coronal', 'coronal', ext[0], ext[2])),
                    ColoredBox(color: gutter, child: const SizedBox(width: 1)),
                    Expanded(child: cell('sagittal', 'sagittal', ext[1], ext[2])),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
