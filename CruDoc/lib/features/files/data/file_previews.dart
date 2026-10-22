import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:printing/printing.dart';

import 'package:doctor_management_app/core/imaging/progressive_jpeg.dart';
import 'package:doctor_management_app/features/files/data/file_types.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/imaging/rad_preview.dart';

/// What a file shows before (or instead of) its full contents: a small
/// JPEG for lists and the viewer's first frame and, for pictures, a
/// progressive JPEG the viewer sharpens chunk by chunk as it downloads.
@immutable
class FilePreviews {
  const FilePreviews({required this.thumb, this.view});

  /// Base64 JPEG, about [thumbEdge] px on its long edge.
  final String thumb;

  /// Progressive JPEG to view from; null when the original already is one.
  final Uint8List? view;

  static const int thumbEdge = 160;

  /// Longest edge of a view: sharp at the viewer's zoom on any phone,
  /// and a texture every GPU takes.
  static const int viewEdge = 4096;

  /// Whether [contentType] gets previews at all.
  static bool canPreview(String contentType) =>
      PatientFileTypes.isViewableImage(contentType) ||
      contentType == 'application/pdf' ||
      contentType == PatientFileTypes.dicom;

  /// Previews of [bytes], or null when it can't be read. Never throws.
  static Future<FilePreviews?> make(Uint8List bytes, String contentType) async {
    try {
      if (PatientFileTypes.isViewableImage(contentType)) {
        return await _picture(bytes);
      }
      if (contentType == 'application/pdf') return await _pdf(bytes);
      if (contentType == PatientFileTypes.dicom) return await _dicom(bytes);
    } catch (e) {
      debugPrint('[Files] no preview: $e');
    }
    return null;
  }

  static Future<FilePreviews> _picture(Uint8List bytes) async {
    final (rgba, w, h) = await decodeRgba(bytes, maxEdge: viewEdge);
    final keepOriginal = isProgressiveJpeg(bytes) && math.max(w, h) <= viewEdge;
    return Isolate.run(
      () => FilePreviews(
        thumb: base64Encode(_thumbJpeg(rgba, w, h)),
        view: keepOriginal ? null : encodeProgressiveJpeg(rgba, w, h),
      ),
    );
  }

  static Future<FilePreviews?> _pdf(Uint8List bytes) async {
    // About 24 dpi: an A4 page is ~200 px tall before shrinking.
    await for (final page in Printing.raster(
      bytes,
      pages: const [0],
      dpi: 24,
    )) {
      final pixels = page.pixels;
      final (w, h) = (page.width, page.height);
      return FilePreviews(
        thumb: await Isolate.run(() => base64Encode(_thumbJpeg(pixels, w, h))),
      );
    }
    return null;
  }

  static Future<FilePreviews?> _dicom(Uint8List bytes) async {
    final jpeg = await radPreviewJpeg(bytes, RadFileKind.dicom);
    if (jpeg == null) return null;
    final (rgba, w, h) = await decodeRgba(jpeg);
    return FilePreviews(
      thumb: await Isolate.run(() => base64Encode(_thumbJpeg(rgba, w, h))),
    );
  }

  /// Decodes [bytes] with the engine (EXIF rotation applied), at most
  /// [maxEdge] px on the long edge, as premultiplied RGBA.
  static Future<(Uint8List, int, int)> decodeRgba(
    Uint8List bytes, {
    int? maxEdge,
  }) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (w, h) {
        final longest = math.max(w, h);
        if (maxEdge == null || longest <= maxEdge) {
          return const ui.TargetImageSize();
        }
        return ui.TargetImageSize(width: (w * maxEdge / longest).round());
      },
    );
    try {
      final image = (await codec.getNextFrame()).image;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) throw StateError('No pixels');
        return (data.buffer.asUint8List(), image.width, image.height);
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  /// A JPEG of premultiplied [rgba] shrunk to [thumbEdge], flattened onto
  /// white. Box-averaged, so text and edges stay smooth.
  static Uint8List _thumbJpeg(Uint8List rgba, int w, int h) {
    final scale = math.min(1.0, thumbEdge / math.max(w, h));
    final tw = math.max(1, (w * scale).round());
    final th = math.max(1, (h * scale).round());
    final out = Uint8List(tw * th * 3);
    for (var ty = 0; ty < th; ty++) {
      final y0 = ty * h ~/ th;
      final y1 = math.max(y0 + 1, (ty + 1) * h ~/ th);
      for (var tx = 0; tx < tw; tx++) {
        final x0 = tx * w ~/ tw;
        final x1 = math.max(x0 + 1, (tx + 1) * w ~/ tw);
        var r = 0, g = 0, b = 0;
        for (var y = y0; y < y1; y++) {
          var i = (y * w + x0) * 4;
          for (var x = x0; x < x1; x++, i += 4) {
            final cover = 255 - rgba[i + 3];
            r += math.min(255, rgba[i] + cover);
            g += math.min(255, rgba[i + 1] + cover);
            b += math.min(255, rgba[i + 2] + cover);
          }
        }
        final n = (y1 - y0) * (x1 - x0);
        final o = (ty * tw + tx) * 3;
        out[o] = r ~/ n;
        out[o + 1] = g ~/ n;
        out[o + 2] = b ~/ n;
      }
    }
    final image = img.Image.fromBytes(
      width: tw,
      height: th,
      bytes: out.buffer,
      numChannels: 3,
    );
    return img.encodeJpg(image, quality: 70);
  }
}

/// Whether [bytes] are a progressive JPEG (SOF2 before any scan),
/// which the engine can draw from any prefix.
bool isProgressiveJpeg(Uint8List bytes) => jpegIsProgressive(bytes) ?? false;

/// Like [isProgressiveJpeg] for the start of a download: null while the
/// header hasn't fully arrived.
bool? jpegIsProgressive(Uint8List bytes) {
  if (bytes.length < 4) return null;
  if (bytes[0] != 0xFF || bytes[1] != 0xD8) return false;
  var i = 2;
  while (i + 3 < bytes.length) {
    if (bytes[i] != 0xFF) return false;
    final marker = bytes[i + 1];
    if (marker == 0xFF) {
      i++;
      continue;
    }
    if (marker == 0xC2) return true;
    if (marker == 0xDA ||
        (marker >= 0xC0 &&
            marker <= 0xCF &&
            marker != 0xC4 &&
            marker != 0xC8 &&
            marker != 0xCC)) {
      return false;
    }
    i += 2 + ((bytes[i + 2] << 8) | bytes[i + 3]);
  }
  return null;
}
