import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Paints [painter] once into an image at [quality] of the screen's
/// resolution, then only blits it (scaled up). For the tooth artwork
/// (shading, blurs, layers), which is costly to draw: it is redrawn only
/// when [CustomPainter.shouldRepaint] says the picture changed, never for
/// scrolling, hover or a parent's animation.
class CachedPaint extends StatefulWidget {
  const CachedPaint({super.key, required this.painter, this.quality = 0.25});

  final CustomPainter painter;

  /// The image's resolution as a share of the screen's (per side).
  final double quality;

  @override
  State<CachedPaint> createState() => _CachedPaintState();
}

class _CachedPaintState extends State<CachedPaint> {
  CustomPainter? _painted;
  Size _size = Size.zero;
  double _ratio = 0;
  ui.Image? _image;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  ui.Image? _imageFor(Size size, double ratio) {
    final last = _painted;
    if (_image != null &&
        last != null &&
        size == _size &&
        ratio == _ratio &&
        last.runtimeType == widget.painter.runtimeType &&
        !widget.painter.shouldRepaint(last)) {
      return _image;
    }
    final w = (size.width * ratio).ceil();
    final h = (size.height * ratio).ceil();
    if (!size.isFinite || w <= 0 || h <= 0) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(ratio);
    widget.painter.paint(canvas, size);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();
    _image?.dispose();
    _painted = widget.painter;
    _size = size;
    _ratio = ratio;
    return _image = image;
  }

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context) * widget.quality;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final image = _imageFor(size, ratio);
        return RepaintBoundary(
          child: CustomPaint(
            size: size,
            painter: image == null ? null : _ImagePainter(image, ratio),
          ),
        );
      },
    );
  }
}

/// Blits [image], painted at [ratio] pixels per logical pixel.
class _ImagePainter extends CustomPainter {
  const _ImagePainter(this.image, this.ratio);

  final ui.Image image;
  final double ratio;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(1 / ratio);
    canvas.drawImage(
      image,
      Offset.zero,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ImagePainter old) => old.image != image;
}
