import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'geometry.dart';

/// An 8-bit grey picture, row-major, no padding.
class GrayImage {
  GrayImage(this.width, this.height, this.data)
    : assert(data.length >= width * height);

  final int width;
  final int height;
  final Uint8List data;

  int at(int x, int y) => data[y * width + x];

  /// Bilinear sample at a continuous position (pixel centres at i + 0.5).
  double sample(double x, double y) {
    final fx = (x - 0.5).clamp(0.0, width - 1.0);
    final fy = (y - 0.5).clamp(0.0, height - 1.0);
    final x0 = fx.floor(), y0 = fy.floor();
    final x1 = math.min(x0 + 1, width - 1), y1 = math.min(y0 + 1, height - 1);
    final ax = fx - x0, ay = fy - y0;
    final r0 = y0 * width, r1 = y1 * width;
    final top = data[r0 + x0] + (data[r0 + x1] - data[r0 + x0]) * ax;
    final bottom = data[r1 + x0] + (data[r1 + x1] - data[r1 + x0]) * ax;
    return top + (bottom - top) * ay;
  }
}

/// Anything the scanner can look at: a live camera frame or a still photo.
///
/// Every coordinate is "upright": as the person sees the page on screen,
/// whatever way the sensor stores it.
abstract class PixelSource {
  int get width;
  int get height;

  /// Grey value of one upright pixel.
  int lumaAt(int x, int y);

  /// Bilinear grey value at a continuous upright position.
  double luma(double x, double y);

  /// A [factor]× smaller box-averaged grey copy, used for detection.
  GrayImage downsample(int factor);

  /// A shape found in [downsample]'s copy, in full-resolution coordinates.
  Quad fromSmall(Quad q, int factor);

  /// RGB pixels of the page: output pixel (x, y) shows the source point
  /// `toSource(x + 0.5, y + 0.5)`.
  Uint8List warp(Homography toSource, int outWidth, int outHeight);
}

/// One camera frame in the sensor's own layout: a full-resolution Y plane
/// and quarter-resolution chroma. Covers Android YUV_420_888 (three
/// planes), iOS NV12 (two) and NV21 (one).
class YuvFrame implements PixelSource {
  YuvFrame({
    required this.sensorWidth,
    required this.sensorHeight,
    required this.rotation,
    required this.y,
    required this.yRowStride,
    required this.u,
    required this.uOffset,
    required this.uRowStride,
    required this.uPixelStride,
    required this.v,
    required this.vOffset,
    required this.vRowStride,
    required this.vPixelStride,
    this.fullRange = true,
  }) : assert(rotation % 90 == 0);

  final int sensorWidth;
  final int sensorHeight;

  /// Clockwise turn (0, 90, 180, 270) that makes the sensor image upright.
  final int rotation;

  final Uint8List y;
  final int yRowStride;
  final Uint8List u;
  final int uOffset;
  final int uRowStride;
  final int uPixelStride;
  final Uint8List v;
  final int vOffset;
  final int vRowStride;
  final int vPixelStride;

  /// False for iOS "video range" (Y 16–235).
  final bool fullRange;

  bool get _swap => rotation % 180 != 0;

  @override
  int get width => _swap ? sensorHeight : sensorWidth;
  @override
  int get height => _swap ? sensorWidth : sensorHeight;

  /// Upright pixel -> sensor pixel index (integer form).
  int _sx(int x, int y) => switch (rotation) {
    90 => y,
    180 => sensorWidth - 1 - x,
    270 => sensorWidth - 1 - y,
    _ => x,
  };
  int _sy(int x, int y) => switch (rotation) {
    90 => sensorHeight - 1 - x,
    180 => sensorHeight - 1 - y,
    270 => x,
    _ => y,
  };

  @override
  int lumaAt(int x, int y) => this.y[_sy(x, y) * yRowStride + _sx(x, y)];

  @override
  Quad fromSmall(Quad q, int factor) {
    final f = math.max(1, factor);
    // Rows/columns the box average dropped sit on the far sensor edge;
    // where rotation flips an axis they shift the upright origin.
    final dropW = (sensorWidth - f * (sensorWidth ~/ f)).toDouble();
    final dropH = (sensorHeight - f * (sensorHeight ~/ f)).toDouble();
    final (ox, oy) = switch (rotation) {
      90 => (dropH, 0.0),
      180 => (dropW, dropH),
      270 => (0.0, dropW),
      _ => (0.0, 0.0),
    };
    Pt m(Pt p) => Pt(p.x * f + ox, p.y * f + oy);
    return Quad(m(q.tl), m(q.tr), m(q.br), m(q.bl));
  }

  @override
  double luma(double x, double y) {
    // Continuous upright -> continuous sensor.
    final double s, t;
    switch (rotation) {
      case 90:
        s = y;
        t = sensorHeight - x;
      case 180:
        s = sensorWidth - x;
        t = sensorHeight - y;
      case 270:
        s = sensorWidth - y;
        t = x;
      default:
        s = x;
        t = y;
    }
    return _bilinearY(s, t);
  }

  double _bilinearY(double s, double t) {
    final fx = (s - 0.5).clamp(0.0, sensorWidth - 1.0);
    final fy = (t - 0.5).clamp(0.0, sensorHeight - 1.0);
    final x0 = fx.floor(), y0 = fy.floor();
    final x1 = math.min(x0 + 1, sensorWidth - 1);
    final y1 = math.min(y0 + 1, sensorHeight - 1);
    final ax = fx - x0, ay = fy - y0;
    final r0 = y0 * yRowStride, r1 = y1 * yRowStride;
    final p = y;
    final top = p[r0 + x0] + (p[r0 + x1] - p[r0 + x0]) * ax;
    final bottom = p[r1 + x0] + (p[r1 + x1] - p[r1 + x0]) * ax;
    return top + (bottom - top) * ay;
  }

  @override
  GrayImage downsample(int factor) {
    final f = math.max(1, factor);
    final sw = sensorWidth ~/ f, sh = sensorHeight ~/ f;
    final small = Uint8List(sw * sh);
    final acc = Int32List(sw);
    final area = f * f;
    for (var sy = 0; sy < sh; sy++) {
      acc.fillRange(0, sw, 0);
      for (var r = 0; r < f; r++) {
        final row = (sy * f + r) * yRowStride;
        var i = row;
        for (var sx = 0; sx < sw; sx++) {
          var sum = 0;
          for (var k = 0; k < f; k++) {
            sum += y[i++];
          }
          acc[sx] += sum;
        }
      }
      final o = sy * sw;
      for (var sx = 0; sx < sw; sx++) {
        small[o + sx] = acc[sx] ~/ area;
      }
    }
    return rotateGray(GrayImage(sw, sh, small), rotation);
  }

  @override
  Uint8List warp(Homography toSource, int outWidth, int outHeight) {
    final out = Uint8List(outWidth * outHeight * 3);
    final m = toSource.matrix;
    final yScale = fullRange ? 1.0 : 255 / 219;
    final yOff = fullRange ? 0.0 : 16.0;
    final cScale = fullRange ? 1.0 : 255 / 224;
    final maxS = sensorWidth - 1.0, maxT = sensorHeight - 1.0;
    final cw = (sensorWidth + 1) >> 1, ch = (sensorHeight + 1) >> 1;
    var o = 0;
    for (var oy = 0; oy < outHeight; oy++) {
      final py = oy + 0.5;
      for (var ox = 0; ox < outWidth; ox++) {
        final px = ox + 0.5;
        final w = m[6] * px + m[7] * py + m[8];
        final ux = (m[0] * px + m[1] * py + m[2]) / w;
        final uy = (m[3] * px + m[4] * py + m[5]) / w;
        final double s, t;
        switch (rotation) {
          case 90:
            s = uy;
            t = sensorHeight - ux;
          case 180:
            s = sensorWidth - ux;
            t = sensorHeight - uy;
          case 270:
            s = sensorWidth - uy;
            t = ux;
          default:
            s = ux;
            t = uy;
        }
        // Luma, bilinear.
        final fx = (s - 0.5).clamp(0.0, maxS);
        final fy = (t - 0.5).clamp(0.0, maxT);
        final x0 = fx.floor(), y0 = fy.floor();
        final x1 = x0 < sensorWidth - 1 ? x0 + 1 : x0;
        final y1 = y0 < sensorHeight - 1 ? y0 + 1 : y0;
        final ax = fx - x0, ay = fy - y0;
        final r0 = y0 * yRowStride, r1 = y1 * yRowStride;
        final top = y[r0 + x0] + (y[r0 + x1] - y[r0 + x0]) * ax;
        final bottom = y[r1 + x0] + (y[r1 + x1] - y[r1 + x0]) * ax;
        final lum = (top + (bottom - top) * ay - yOff) * yScale;
        // Chroma, nearest (it is quarter resolution and colour matters
        // far less than the text).
        final cx = math.min(fx.round() >> 1, cw - 1);
        final cy = math.min(fy.round() >> 1, ch - 1);
        final uu =
            (u[uOffset + cy * uRowStride + cx * uPixelStride] - 128) * cScale;
        final vv =
            (v[vOffset + cy * vRowStride + cx * vPixelStride] - 128) * cScale;
        out[o++] = _clamp8(lum + 1.402 * vv);
        out[o++] = _clamp8(lum - 0.344136 * uu - 0.714136 * vv);
        out[o++] = _clamp8(lum + 1.772 * uu);
      }
    }
    return out;
  }
}

/// A decoded still photo (gallery import), already upright.
class RgbSource implements PixelSource {
  RgbSource(this.width, this.height, this.rgb)
    : _luma = _lumaOf(rgb, width * height);

  factory RgbSource.fromImage(img.Image image) {
    final rgb = image.convert(format: img.Format.uint8, numChannels: 3);
    return RgbSource(
      rgb.width,
      rgb.height,
      rgb.getBytes(order: img.ChannelOrder.rgb),
    );
  }

  @override
  final int width;
  @override
  final int height;
  final Uint8List rgb;
  final Uint8List _luma;

  static Uint8List _lumaOf(Uint8List rgb, int n) {
    final l = Uint8List(n);
    for (var i = 0, j = 0; i < n; i++, j += 3) {
      l[i] = (rgb[j] * 77 + rgb[j + 1] * 150 + rgb[j + 2] * 29) >> 8;
    }
    return l;
  }

  late final GrayImage _gray = GrayImage(width, height, _luma);

  @override
  int lumaAt(int x, int y) => _luma[y * width + x];

  @override
  Quad fromSmall(Quad q, int factor) => q.scale(math.max(1, factor).toDouble());

  @override
  double luma(double x, double y) => _gray.sample(x, y);

  @override
  GrayImage downsample(int factor) {
    final f = math.max(1, factor);
    final sw = width ~/ f, sh = height ~/ f;
    final small = Uint8List(sw * sh);
    final area = f * f;
    for (var sy = 0; sy < sh; sy++) {
      for (var sx = 0; sx < sw; sx++) {
        var sum = 0;
        for (var r = 0; r < f; r++) {
          final row = (sy * f + r) * width + sx * f;
          for (var k = 0; k < f; k++) {
            sum += _luma[row + k];
          }
        }
        small[sy * sw + sx] = sum ~/ area;
      }
    }
    return GrayImage(sw, sh, small);
  }

  @override
  Uint8List warp(Homography toSource, int outWidth, int outHeight) {
    final out = Uint8List(outWidth * outHeight * 3);
    final m = toSource.matrix;
    final maxX = width - 1.0, maxY = height - 1.0;
    var o = 0;
    for (var oy = 0; oy < outHeight; oy++) {
      final py = oy + 0.5;
      for (var ox = 0; ox < outWidth; ox++) {
        final px = ox + 0.5;
        final w = m[6] * px + m[7] * py + m[8];
        final fx = ((m[0] * px + m[1] * py + m[2]) / w - 0.5).clamp(0.0, maxX);
        final fy = ((m[3] * px + m[4] * py + m[5]) / w - 0.5).clamp(0.0, maxY);
        final x0 = fx.floor(), y0 = fy.floor();
        final x1 = x0 < width - 1 ? x0 + 1 : x0;
        final y1 = y0 < height - 1 ? y0 + 1 : y0;
        final ax = fx - x0, ay = fy - y0;
        final i00 = (y0 * width + x0) * 3, i01 = (y0 * width + x1) * 3;
        final i10 = (y1 * width + x0) * 3, i11 = (y1 * width + x1) * 3;
        for (var c = 0; c < 3; c++) {
          final top = rgb[i00 + c] + (rgb[i01 + c] - rgb[i00 + c]) * ax;
          final bottom = rgb[i10 + c] + (rgb[i11 + c] - rgb[i10 + c]) * ax;
          out[o++] = _clamp8(top + (bottom - top) * ay);
        }
      }
    }
    return out;
  }
}

int _clamp8(double v) => v <= 0 ? 0 : (v >= 255 ? 255 : v.round());

/// [g] turned clockwise by [rotation] degrees.
GrayImage rotateGray(GrayImage g, int rotation) {
  if (rotation % 360 == 0) return g;
  final w = g.width, h = g.height, src = g.data;
  final swap = rotation % 180 != 0;
  final ow = swap ? h : w, oh = swap ? w : h;
  final out = Uint8List(ow * oh);
  for (var oy = 0; oy < oh; oy++) {
    for (var ox = 0; ox < ow; ox++) {
      final int sx, sy;
      switch (rotation) {
        case 90:
          sx = oy;
          sy = h - 1 - ox;
        case 180:
          sx = w - 1 - ox;
          sy = h - 1 - oy;
        default: // 270
          sx = w - 1 - oy;
          sy = ox;
      }
      out[oy * ow + ox] = src[sy * w + sx];
    }
  }
  return GrayImage(ow, oh, out);
}
