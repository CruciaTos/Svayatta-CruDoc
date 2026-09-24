import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/dicom/dicom_file.dart';

/// One decoded 2D image ready to display: grayscale values (DICOM
/// modality values, or 0–255 / 0–65535 for pictures) and, for colour
/// pictures, RGBA bytes.
class RadPixels {
  const RadPixels({
    required this.width,
    required this.height,
    required this.values,
    this.rgba,
    required this.minValue,
    required this.maxValue,
    required this.lowPct,
    required this.highPct,
    this.windowCenter,
    this.windowWidth,
    this.invert = false,
    this.pixelSpacingMm,
    this.frames = 1,
  });

  final int width;
  final int height;

  /// Grayscale value per pixel, row by row (luminance for colour).
  final Float32List values;

  /// RGBA bytes for a colour picture; null for grayscale.
  final Uint8List? rgba;
  final double minValue;
  final double maxValue;

  /// The 0.5th and 99.5th percentile values: a good default window.
  final double lowPct;
  final double highPct;

  /// Window from the DICOM file, if it has one.
  final double? windowCenter;
  final double? windowWidth;

  /// MONOCHROME1: low values are white.
  final bool invert;

  /// Millimetres per pixel from the file.
  final double? pixelSpacingMm;
  final int frames;

  bool get isColor => rgba != null;

  double valueAt(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return double.nan;
    return values[y * width + x];
  }

  /// Default window (centre, width): the file's, else the percentiles.
  (double, double) get defaultWindow {
    if (windowCenter != null && windowWidth != null && windowWidth! > 0) {
      return (windowCenter!, windowWidth!);
    }
    final w = (highPct - lowPct).abs();
    return ((highPct + lowPct) / 2, w <= 0 ? 1 : w);
  }
}

/// The image can't be shown yet (e.g. JPEG 2000 DICOM).
class RadUnsupportedImage implements Exception {
  RadUnsupportedImage(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// Decodes [file] off the UI thread.
Future<RadPixels> loadRadPixels(File file, RadFileKind kind, {int frame = 0}) {
  final path = file.path;
  return Isolate.run(() => decodeRadPixels(File(path).readAsBytesSync(), kind, frame: frame));
}

/// Decodes bytes (call from an isolate for big images).
RadPixels decodeRadPixels(Uint8List bytes, RadFileKind kind, {int frame = 0}) {
  if (kind == RadFileKind.dicom) return _fromDicom(bytes, frame);
  return _fromRaster(bytes);
}

RadPixels _fromDicom(Uint8List bytes, int frame) {
  final d = DicomFile.parse(bytes);
  if (!d.hasPixels) throw RadUnsupportedImage('This DICOM file has no image');
  if (d.isCompressed) {
    throw RadUnsupportedImage(
        '${DicomSyntax.name(d.transferSyntax)} DICOM images are not supported yet');
  }
  final w = d.columns, h = d.rows;
  final f = frame.clamp(0, (d.frames - 1).clamp(0, 1 << 30));
  if (d.isColor) {
    final rgba = d.frameRgba(f);
    final values = Float32List(w * h);
    for (var i = 0; i < values.length; i++) {
      values[i] = 0.299 * rgba[i * 4] + 0.587 * rgba[i * 4 + 1] + 0.114 * rgba[i * 4 + 2];
    }
    return _withStats(values, w, h, rgba: rgba, spacing: d.pixelSpacingMm, frames: d.frames);
  }
  final values = d.frameValues(f);
  return _withStats(
    values,
    w,
    h,
    center: d.numbers(DicomTag.windowCenter)?.first,
    width: d.numbers(DicomTag.windowWidth)?.first,
    invert: d.monochrome1,
    spacing: d.pixelSpacingMm,
    frames: d.frames,
  );
}

RadPixels _fromRaster(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) throw RadUnsupportedImage('This picture format is not supported');
  final w = image.width, h = image.height;
  final values = Float32List(w * h);
  final colour = image.numChannels >= 3 && _looksColour(image);
  Uint8List? rgba;
  if (colour) {
    rgba = image
        .convert(format: img.Format.uint8, numChannels: 4, alpha: 255)
        .getBytes(order: img.ChannelOrder.rgba);
  }
  var i = 0;
  for (final p in image) {
    values[i++] = image.numChannels >= 3
        ? (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).toDouble()
        : p.r.toDouble();
  }
  return _withStats(values, w, h, rgba: rgba);
}

bool _looksColour(img.Image image) {
  final step = (image.width * image.height ~/ 4000).clamp(1, 1 << 30);
  var n = 0;
  for (final p in image) {
    if (n++ % step != 0) continue;
    if ((p.r - p.g).abs() > 12 || (p.g - p.b).abs() > 12) return true;
  }
  return false;
}

RadPixels _withStats(
  Float32List values,
  int w,
  int h, {
  Uint8List? rgba,
  double? center,
  double? width,
  bool invert = false,
  double? spacing,
  int frames = 1,
}) {
  var mn = double.infinity, mx = -double.infinity;
  for (final v in values) {
    if (v < mn) mn = v;
    if (v > mx) mx = v;
  }
  if (!mn.isFinite) {
    mn = 0;
    mx = 1;
  }
  // Percentiles from a 1024-bin histogram.
  const bins = 1024;
  final hist = Int32List(bins);
  final range = (mx - mn) == 0 ? 1.0 : (mx - mn);
  for (final v in values) {
    hist[(((v - mn) / range) * (bins - 1)).round()]++;
  }
  double pct(double q) {
    final target = values.length * q;
    var acc = 0;
    for (var b = 0; b < bins; b++) {
      acc += hist[b];
      if (acc >= target) return mn + range * b / (bins - 1);
    }
    return mx;
  }

  return RadPixels(
    width: w,
    height: h,
    values: values,
    rgba: rgba,
    minValue: mn,
    maxValue: mx,
    lowPct: pct(0.005),
    highPct: pct(0.995),
    windowCenter: center,
    windowWidth: width,
    invert: invert,
    pixelSpacingMm: spacing,
    frames: frames,
  );
}
