import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'detector.dart';
import 'geometry.dart';
import 'pixels.dart';
import 'quality.dart';

/// A finished page, encoded, ready to keep.
class CapturedPage {
  const CapturedPage({
    required this.jpeg,
    required this.thumb,
    required this.width,
    required this.height,
    this.sharpness,
  });

  final Uint8List jpeg;
  final Uint8List thumb;
  final int width;
  final int height;

  /// Measured on the straightened page; null for a blank one.
  final double? sharpness;
}

abstract final class PageRender {
  /// Kept pages: sharp enough to read small print, small enough to sync
  /// (same limits the scan feature has always used).
  static const maxLongEdge = 2000;
  static const jpegQuality = 72;
  static const thumbLongEdge = 360;

  /// Detection runs on a copy about this many pixels on its long edge.
  static const detectLongEdge = 360;

  static int detectFactor(PixelSource src) =>
      math.max(1, math.max(src.width, src.height) ~/ detectLongEdge);

  /// Corners from the small detection image, moved onto the page edge in
  /// the full-resolution picture, then pushed out a little so the edge of
  /// the paper is never cut off.
  static Quad finalCorners(PixelSource src, Quad fullResQuad, int factor) {
    final refined = refineQuad(
      src.luma,
      fullResQuad,
      searchRadius: 2.0 * factor + 2,
      step: 1.0,
      tangentSpacing: 2.0,
      maxShift: 1.5 * factor + 2,
      minContrast: 6,
      samplesPerSide: 48,
    );
    final sides = refined.sideLengths;
    final meanSide = sides.reduce((a, b) => a + b) / 4;
    // Half the blurred edge belongs to the paper: keep it, plus a hair.
    final margin = math.max(2.0, meanSide * 0.004);
    final out = refined.expanded(margin);
    return _clampInside(out, src.width.toDouble(), src.height.toDouble());
  }

  /// Straightens [quad] (full-resolution, upright) out of [src], turns it
  /// the way the phone was held ([quarterTurns] clockwise) and encodes it.
  /// With no [quad], the whole frame is kept.
  static CapturedPage render(
    PixelSource src,
    Quad? quad, {
    int quarterTurns = 0,
  }) {
    final q =
        quad ??
        Quad(
          const Pt(0, 0),
          Pt(src.width.toDouble(), 0),
          Pt(src.width.toDouble(), src.height.toDouble()),
          Pt(0, src.height.toDouble()),
        );
    final s = q.sideLengths;
    var w = math.max(s[0], s[2]);
    var h = math.max(s[1], s[3]);
    final long = math.max(w, h);
    if (long > maxLongEdge) {
      w *= maxLongEdge / long;
      h *= maxLongEdge / long;
    }
    final ow = math.max(1, w.round()), oh = math.max(1, h.round());
    final toSource = Homography.fromPoints([
      const Pt(0, 0),
      Pt(ow.toDouble(), 0),
      Pt(ow.toDouble(), oh.toDouble()),
      Pt(0, oh.toDouble()),
    ], q.corners);
    final rgb = toSource == null
        ? Uint8List(ow * oh * 3)
        : src.warp(toSource, ow, oh);
    var page = img.Image.fromBytes(
      width: ow,
      height: oh,
      bytes: rgb.buffer,
      numChannels: 3,
    );
    final turns = quarterTurns % 4;
    if (turns != 0) page = img.copyRotate(page, angle: 90 * turns);

    final check = RgbSource(
      page.width,
      page.height,
      page.getBytes(order: img.ChannelOrder.rgb),
    );
    final sharp = PageQuality.sharpness(
      check,
      Quad(
        const Pt(0, 0),
        Pt(page.width.toDouble(), 0),
        Pt(page.width.toDouble(), page.height.toDouble()),
        Pt(0, page.height.toDouble()),
      ).expanded(-math.min(page.width, page.height) * 0.02),
    );
    return CapturedPage(
      jpeg: img.encodeJpg(page, quality: jpegQuality),
      thumb: img.encodeJpg(_fit(page, thumbLongEdge), quality: 70),
      width: page.width,
      height: page.height,
      sharpness: sharp,
    );
  }

  /// A still photo (gallery import): finds the page and straightens it
  /// when it is clearly there, otherwise keeps the photo as it is.
  static CapturedPage? still(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    var photo = img.bakeOrientation(decoded);
    // Plenty for detection and the kept page; keeps the warp quick.
    final long = math.max(photo.width, photo.height);
    if (long > 3000) photo = _fit(photo, 3000);
    final src = RgbSource.fromImage(photo);
    final f = detectFactor(src);
    final det = DocumentDetector.detect(src.downsample(f));
    Quad? quad;
    if (det.found && det.support >= 0.6) {
      quad = finalCorners(src, src.fromSmall(det.quad!, f), f);
    }
    return render(src, quad);
  }

  static Quad _clampInside(Quad q, double w, double h) {
    Pt c(Pt p) => Pt(p.x.clamp(0.0, w), p.y.clamp(0.0, h));
    return Quad(c(q.tl), c(q.tr), c(q.br), c(q.bl));
  }

  static img.Image _fit(img.Image image, int longEdge) {
    final long = math.max(image.width, image.height);
    if (long <= longEdge) return image;
    final scale = longEdge / long;
    return img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }
}
