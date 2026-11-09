import 'dart:ui' show Rect, Size;

/// How a plane of [u] x [v] mm is fitted into a viewport of [width] x
/// [height] px. The same rule runs in the web viewer, so a poster drawn here
/// lines up pixel for pixel with the live view that replaces it.
class CbctFit {
  const CbctFit._(this.parallelScale, this.pxPerMm, this.rect);

  /// Half of the visible height in mm.
  final double parallelScale;
  final double pxPerMm;

  /// The plane's rectangle in viewport pixels, centred.
  final Rect rect;

  factory CbctFit.of({
    required double width,
    required double height,
    required double u,
    required double v,
  }) {
    final aspect = width / height;
    final scale = _max(v / 2, u / (2 * aspect));
    final px = height / (2 * scale);
    final w = u * px, h = v * px;
    return CbctFit._(
      scale,
      px,
      Rect.fromLTWH((width - w) / 2, (height - h) / 2, w, h),
    );
  }

  /// Convenience for a [Size] viewport.
  factory CbctFit.inSize(Size size, {required double u, required double v}) =>
      CbctFit.of(width: size.width, height: size.height, u: u, v: v);
}

double _max(double a, double b) => a > b ? a : b;
