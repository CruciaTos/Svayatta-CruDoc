import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:doctor_management_app/features/radiology/imaging/rad_pixels.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/image_filters.dart';

/// How a pane turns pixel values into screen colours: the window
/// (centre and width, in the image's own value units), invert, gamma and
/// colour map.
class RadDisplay {
  const RadDisplay({
    required this.center,
    required this.width,
    this.invert = false,
    this.gamma = 1,
    this.colormap = 'gray',
  });

  final double center;
  final double width;
  final bool invert;
  final double gamma;
  final String colormap;

  double get low => center - width / 2;
}

/// Steps in the lookup table across the window. The output is 8-bit, so
/// 1024 steps leave room for the gamma curve without banding.
const radLutSize = 1024;

/// Packed RGBA words (host byte order, so a byte view reads R, G, B, A)
/// for [radLutSize] steps from the bottom to the top of the window.
Uint32List buildDisplayLut(RadDisplay d) {
  final cmap = d.colormap == 'gray' ? null : colormapLut(d.colormap);
  final out = Uint32List(radLutSize);
  final little = Endian.host == Endian.little;
  for (var i = 0; i < radLutSize; i++) {
    var t = i / (radLutSize - 1);
    if (d.invert) t = 1 - t;
    if (d.gamma != 1) t = math.pow(t, 1 / d.gamma).toDouble();
    final g = (t * 255).round().clamp(0, 255);
    var r = g, gg = g, b = g;
    if (cmap != null) {
      r = cmap[g * 3];
      gg = cmap[g * 3 + 1];
      b = cmap[g * 3 + 2];
    }
    out[i] = little
        ? (0xFF << 24) | (b << 16) | (gg << 8) | r
        : (r << 24) | (gg << 16) | (b << 8) | 0xFF;
  }
  return out;
}

/// One rendered frame: RGBA bytes [width] × [height]. [step] > 1 means
/// every step-th pixel (a quick preview while dragging).
class RadRgba {
  const RadRgba(this.bytes, this.width, this.height, this.step);
  final Uint8List bytes;
  final int width;
  final int height;
  final int step;
}

/// Renders grayscale [values] (or the colour picture in [px]) through
/// the display settings.
RadRgba renderDisplay(RadPixels px, Float32List values, RadDisplay d, {int step = 1}) {
  final w = px.width, h = px.height;
  final ow = (w + step - 1) ~/ step, oh = (h + step - 1) ~/ step;
  final rgba = px.rgba;
  if (rgba != null) return _renderColour(rgba, w, h, ow, oh, d, step);

  final lut = buildDisplayLut(d);
  final out = Uint32List(ow * oh);
  final lo = d.low;
  final k = (radLutSize - 1) / (d.width <= 0 ? 1 : d.width);
  const top = radLutSize - 1;
  var o = 0;
  for (var y = 0; y < h; y += step) {
    final row = y * w;
    for (var x = 0; x < w; x += step) {
      final f = (values[row + x] - lo) * k;
      // NaN fails both comparisons and lands on the first step.
      out[o++] = lut[f > 0 ? (f < top ? f.toInt() : top) : 0];
    }
  }
  return RadRgba(out.buffer.asUint8List(), ow, oh, step);
}

/// Colour pictures keep their colours: the window acts as brightness and
/// contrast on each channel (values are 0–255).
RadRgba _renderColour(Uint8List rgba, int w, int h, int ow, int oh, RadDisplay d, int step) {
  final table = Uint8List(256);
  final width = d.width <= 0 ? 1.0 : d.width;
  for (var v = 0; v < 256; v++) {
    var t = ((v - d.low) / width).clamp(0.0, 1.0);
    if (d.invert) t = 1 - t;
    if (d.gamma != 1) t = math.pow(t, 1 / d.gamma).toDouble();
    table[v] = (t * 255).round();
  }
  final out = Uint8List(ow * oh * 4);
  var o = 0;
  for (var y = 0; y < h; y += step) {
    for (var x = 0; x < w; x += step) {
      final i = (y * w + x) * 4;
      out[o] = table[rgba[i]];
      out[o + 1] = table[rgba[i + 1]];
      out[o + 2] = table[rgba[i + 2]];
      out[o + 3] = 255;
      o += 4;
    }
  }
  return RadRgba(out, ow, oh, step);
}

/// Uploads RGBA bytes as a GPU image.
Future<ui.Image> radImageFromRgba(RadRgba r) {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(r.bytes, r.width, r.height, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// The preview step that keeps a render under ~600k pixels.
int radPreviewStep(int width, int height) {
  final n = width * height;
  if (n <= 600000) return 1;
  return math.sqrt(n / 600000).ceil();
}

/// A window preset, stored relative to the image's 0.5–99.5 percentile
/// range so it suits any image (a 12-bit IOPA and an 8-bit photo alike).
class RadWindowPreset {
  const RadWindowPreset(this.name, this.center, this.width, {this.custom = false});

  final String name;

  /// 0 = the low percentile, 1 = the high percentile.
  final double center;

  /// As a fraction of the percentile range.
  final double width;
  final bool custom;

  /// Centre and width in the image's value units.
  (double, double) resolve(RadPixels px) {
    final range = (px.highPct - px.lowPct).abs();
    final r = range <= 0 ? 1.0 : range;
    return (px.lowPct + center * r, math.max(width * r, r * 0.01));
  }

  /// The current window as a preset of [px].
  static RadWindowPreset fromWindow(String name, RadPixels px, double center, double width) {
    final range = (px.highPct - px.lowPct).abs();
    final r = range <= 0 ? 1.0 : range;
    return RadWindowPreset(name, (center - px.lowPct) / r, width / r, custom: true);
  }

  Map<String, dynamic> toJson() => {'name': name, 'c': center, 'w': width};

  static RadWindowPreset? fromJson(Object? j) {
    if (j is! Map) return null;
    final c = j['c'], w = j['w'], name = j['name'];
    if (c is! num || w is! num || name is! String) return null;
    return RadWindowPreset(name, c.toDouble(), w.toDouble(), custom: true);
  }
}

/// Presets every image offers ("Default" is the file's own window).
const radBuiltInPresets = [
  RadWindowPreset('Bone', 0.62, 0.75),
  RadWindowPreset('Soft tissue', 0.35, 0.6),
  RadWindowPreset('High contrast', 0.5, 0.5),
  RadWindowPreset('Low dose', 0.5, 1.3),
];
