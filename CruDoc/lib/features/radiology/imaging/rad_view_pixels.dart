import 'dart:io';
import 'dart:isolate';

import 'package:crudoc_j2k/crudoc_j2k.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_view_fetch.dart';
import 'package:doctor_management_app/features/radiology/imaging/rad_pixels.dart';
import 'package:flutter/foundation.dart';

@visibleForTesting
Float32List bilinearUpscale(
  Float32List src,
  int srcW,
  int srcH,
  int dstW,
  int dstH,
) {
  if (srcW == dstW && srcH == dstH) return src;
  final dst = Float32List(dstW * dstH);
  final double xRatio = dstW > 1 ? (srcW - 1) / (dstW - 1) : 0.0;
  final double yRatio = dstH > 1 ? (srcH - 1) / (dstH - 1) : 0.0;

  for (int y = 0; y < dstH; y++) {
    final double gy = y * yRatio;
    final int y0 = gy.floor().clamp(0, srcH - 1);
    final int y1 = (y0 + 1).clamp(0, srcH - 1);
    final double fy = gy - y0;

    final int dstRow = y * dstW;
    final int srcRow0 = y0 * srcW;
    final int srcRow1 = y1 * srcW;

    for (int x = 0; x < dstW; x++) {
      final double gx = x * xRatio;
      final int x0 = gx.floor().clamp(0, srcW - 1);
      final int x1 = (x0 + 1).clamp(0, srcW - 1);
      final double fx = gx - x0;

      final double v00 = src[srcRow0 + x0];
      final double v10 = src[srcRow0 + x1];
      final double v01 = src[srcRow1 + x0];
      final double v11 = src[srcRow1 + x1];

      final double v0 = v00 * (1.0 - fx) + v10 * fx;
      final double v1 = v01 * (1.0 - fx) + v11 * fx;
      dst[dstRow + x] = v0 * (1.0 - fy) + v1 * fy;
    }
  }
  return dst;
}

/// Decodes a viewing file off the UI thread. Preview pixels are upscaled
/// (bilinear) to info.width × info.height so coordinates match the original.
Future<RadPixels> loadRadViewPixels(
  File file,
  RadViewInfo info, {
  required int frame,
  required bool full,
  double? pixelSpacingMm,
}) async {
  final path = file.path;
  final previewEnd = (frame >= 0 && frame < info.frameFiles.length)
      ? info.frameFiles[frame].previewEnd
      : 0;

  final sw = Stopwatch()..start();
  final result = await Isolate.run(() {
    Uint8List bytes = File(path).readAsBytesSync();
    if (!full) {
      final effectiveEnd = (previewEnd > 0 && previewEnd <= bytes.length)
          ? previewEnd
          : bytes.length;
      bytes = Uint8List.fromList([
        ...bytes.sublist(0, effectiveEnd),
        0xFF,
        0xD9,
      ]);
    }

    final decoded = decodeJ2k(bytes, reduce: full ? 0 : 1);
    final count = decoded.width * decoded.height;
    Float32List values = Float32List(count);
    final slope = info.slope;
    final intercept = info.intercept;
    final pixels = decoded.pixels;

    for (int i = 0; i < count; i++) {
      values[i] = pixels[i] * slope + intercept;
    }

    int finalW = decoded.width;
    int finalH = decoded.height;

    if (!full) {
      final targetW = info.width ?? decoded.width;
      final targetH = info.height ?? decoded.height;
      if (targetW != decoded.width || targetH != decoded.height) {
        values = bilinearUpscale(
          values,
          decoded.width,
          decoded.height,
          targetW,
          targetH,
        );
        finalW = targetW;
        finalH = targetH;
      }
    }

    return radPixelsWithStats(
      values,
      finalW,
      finalH,
      center: info.windowCenter,
      width: info.windowWidth,
      invert: info.photometric == 'MONOCHROME1',
      spacing: pixelSpacingMm,
      frames: info.frames,
      isPreview: !full,
    );
  });
  sw.stop();
  debugPrint(
    '[rad] ${full ? "Full" : "Preview"} decoded in ${sw.elapsedMilliseconds} ms',
  );
  return result;
}
