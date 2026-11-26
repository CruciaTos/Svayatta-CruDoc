import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'detector.dart';
import 'geometry.dart';
import 'merge.dart';
import 'pixels.dart';
import 'quality.dart';

/// What a page is cut from, kept while the camera is open so its corners
/// can be moved afterwards.
class PageSource {
  const PageSource({this.frame, this.photo, this.quad, this.quarterTurns = 0})
    : assert(frame != null || photo != null);

  /// The camera frame, for a page scanned live.
  final PixelSource? frame;

  /// The file's bytes, for an imported photo (decoded again when needed).
  final Uint8List? photo;

  /// The page's corners in the picture's pixels; null when the whole
  /// picture was kept or no page was found.
  final Quad? quad;
  final int quarterTurns;

  PageSource withQuad(Quad quad) => PageSource(
    frame: frame,
    photo: photo,
    quad: quad,
    quarterTurns: quarterTurns,
  );
}

/// A [PageSource] opened up for correcting by hand: the picture to show,
/// and the same pixels to sense corners in.
class EditablePicture {
  const EditablePicture(this.frame, this.rgba, this.width, this.height);

  final PixelSource frame;

  /// For the screen, [width]×[height]; may be smaller than [frame].
  final Uint8List rgba;
  final int width;
  final int height;
}

/// A finished page, encoded, ready to keep.
class CapturedPage {
  const CapturedPage({
    required this.jpeg,
    required this.thumb,
    required this.width,
    required this.height,
    this.sharpness,
    this.source,
    this.redo = false,
  });

  final PageSource? source;

  /// A new cut of the page saved just before, to take its place.
  final bool redo;

  CapturedPage withSource(PageSource source, {bool redo = false}) =>
      CapturedPage(
        jpeg: jpeg,
        thumb: thumb,
        width: width,
        height: height,
        sharpness: sharpness,
        source: source,
        redo: redo,
      );

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

  /// The page [at] is on, as if someone pointed at it; null when no page
  /// edges can be made out around that spot.
  static Quad? pageAt(PixelSource src, Pt at) {
    // The usual small copy first, then a finer one for faint or small pages.
    final f = detectFactor(src);
    for (final factor in [f, math.max(1, f * 2 ~/ 3)]) {
      final det = DocumentDetector.detect(
        src.downsample(factor),
        around: at * (1 / factor),
      );
      if (det.found) {
        return finalCorners(src, src.fromSmall(det.quad!, factor), factor);
      }
      if (factor == 1) break;
    }
    return null;
  }

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
  /// With no [quad], the whole frame is kept. [more] are other frames of the
  /// same page with their own corners, averaged in to remove grain.
  static CapturedPage render(
    PixelSource src,
    Quad? quad, {
    int quarterTurns = 0,
    List<(PixelSource, Quad)> more = const [],
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
    Uint8List? cut(PixelSource from, Quad along) {
      final toSource = Homography.fromPoints([
        const Pt(0, 0),
        Pt(ow.toDouble(), 0),
        Pt(ow.toDouble(), oh.toDouble()),
        Pt(0, oh.toDouble()),
      ], along.corners);
      return toSource == null ? null : from.warp(toSource, ow, oh);
    }

    final sharpest = cut(src, q) ?? Uint8List(ow * oh * 3);
    final rgb = more.isEmpty
        ? sharpest
        : mergeFrames(
            sharpest,
            [for (final (frame, along) in more) ?cut(frame, along)],
            ow,
            oh,
          );
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
    final src = decodePhoto(bytes);
    if (src == null) return null;
    final f = detectFactor(src);
    final det = DocumentDetector.detect(src.downsample(f));
    Quad? quad;
    if (det.found && det.support >= 0.6) {
      quad = finalCorners(src, src.fromSmall(det.quad!, f), f);
    }
    return render(src, quad).withSource(PageSource(photo: bytes, quad: quad));
  }

  /// An imported photo, upright. Capped at 3000 px: plenty for detection
  /// and the kept page, and keeps the warp quick.
  static RgbSource? decodePhoto(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    var photo = img.bakeOrientation(decoded);
    if (math.max(photo.width, photo.height) > 3000) photo = _fit(photo, 3000);
    return RgbSource.fromImage(photo);
  }

  /// [source] ready for correcting its corners by hand.
  static EditablePicture? editable(PageSource source) {
    final frame = source.frame ?? decodePhoto(source.photo!);
    if (frame == null) return null;
    final k = math.min(1.0, 1920 / math.max(frame.width, frame.height));
    final w = math.max(1, (frame.width * k).round());
    final h = math.max(1, (frame.height * k).round());
    final fw = frame.width.toDouble(), fh = frame.height.toDouble();
    final rgb = frame.warp(
      Homography.fromPoints(
        [
          const Pt(0, 0),
          Pt(w.toDouble(), 0),
          Pt(w.toDouble(), h.toDouble()),
          Pt(0, h.toDouble()),
        ],
        [const Pt(0, 0), Pt(fw, 0), Pt(fw, fh), Pt(0, fh)],
      )!,
      w,
      h,
    );
    final rgba = Uint8List(w * h * 4);
    for (var i = 0, j = 0; j < rgba.length; i += 3, j += 4) {
      rgba[j] = rgb[i];
      rgba[j + 1] = rgb[i + 1];
      rgba[j + 2] = rgb[i + 2];
      rgba[j + 3] = 255;
    }
    return EditablePicture(frame, rgba, w, h);
  }

  /// The page cut out along the corners in [source], exactly where they
  /// were put.
  static CapturedPage? fromSource(PageSource source) {
    final frame = source.frame ?? decodePhoto(source.photo!);
    if (frame == null) return null;
    return render(
      frame,
      source.quad,
      quarterTurns: source.quarterTurns,
    ).withSource(source);
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
