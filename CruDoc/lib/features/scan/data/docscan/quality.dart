import 'dart:math' as math;
import 'dart:typed_data';

import 'geometry.dart';
import 'pixels.dart';

/// How the light falls on the page.
class Lighting {
  const Lighting({
    required this.paper,
    required this.glare,
    required this.evenness,
  });

  /// Brightness of the paper itself (80th percentile inside the page).
  final double paper;

  /// Share of the page burnt out to white (reflections, flash).
  final double glare;

  /// Dimmest region's paper brightness over the brightest's (1 = even,
  /// low = a shadow across the page).
  final double evenness;

  bool get tooDark => paper < 70;
  bool get badGlare => glare > 0.05;
  bool get someGlare => glare > 0.012;
  bool get shadowed => evenness < 0.6;

  /// 0–1, for ranking otherwise equal frames.
  double get score {
    var s = 1.0;
    s -= math.min(0.5, glare * 10);
    s -= math.max(0.0, 0.8 - evenness) * 0.8;
    if (paper < 110) s -= (110 - paper) / 200;
    return s.clamp(0.0, 1.0);
  }
}

abstract final class PageQuality {
  /// Lighting inside [q], measured on the small detection image.
  static Lighting lighting(GrayImage g, Quad q) {
    const n = 32, cells = 4;
    final values = <double>[];
    final cellValues = List.generate(cells * cells, (_) => <double>[]);
    var glare = 0;
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final u = 0.04 + 0.92 * (i + 0.5) / n;
        final v = 0.04 + 0.92 * (j + 0.5) / n;
        final p = q.blend(u, v);
        final l = g.sample(p.x, p.y);
        values.add(l);
        if (l >= 250) glare++;
        cellValues[(j * cells ~/ n) * cells + (i * cells ~/ n)].add(l);
      }
    }
    double p80(List<double> v) {
      v.sort();
      return v[((v.length - 1) * 0.8).round()];
    }

    var lo = double.infinity, hi = 0.0;
    for (final c in cellValues) {
      final p = p80(c);
      lo = math.min(lo, p);
      hi = math.max(hi, p);
    }
    return Lighting(
      paper: p80(values),
      glare: glare / values.length,
      evenness: hi <= 0 ? 0 : lo / hi,
    );
  }

  /// Sharpness 0–1 of the page inside [q] (full-resolution coordinates),
  /// or null when there is nothing to judge it by.
  ///
  /// Uses the re-blur test (Crété-Roffet et al., 2007): blur the picture
  /// again and see how much its pixel-to-pixel variation drops. A sharp
  /// page loses a lot, a blurred one has little left to lose. It is a ratio
  /// of the picture with itself, so contrast, exposure and the amount of
  /// writing cancel out — no fixed Laplacian threshold to tune per phone.
  ///
  /// Measured on patches across the page and along its edges, keeping
  /// only patches with something on them (writing, or the page border).
  static double? sharpness(PixelSource src, Quad q) {
    // The core plus room for the 9-tap blur and one neighbour each side.
    const core = 32, patch = core + 10, half = patch ~/ 2;
    final centres = <Pt>[];
    for (var j = 0; j < 7; j++) {
      for (var i = 0; i < 5; i++) {
        centres.add(q.blend(0.12 + 0.76 * i / 4, 0.1 + 0.8 * j / 6));
      }
    }
    // The border: always has contrast, even on a blank page.
    final c = q.corners;
    for (var k = 0; k < 4; k++) {
      for (final t in const [0.3, 0.7]) {
        centres.add(c[k] + (c[(k + 1) % 4] - c[k]) * t);
      }
    }
    final buf = Float32List(patch * patch);
    var sumD = 0.0, sumV = 0.0;
    var used = 0;
    for (final p in centres) {
      final x0 = p.x.round() - half, y0 = p.y.round() - half;
      if (x0 < 0 ||
          y0 < 0 ||
          x0 + patch > src.width ||
          y0 + patch > src.height) {
        continue;
      }
      var mean = 0.0, sq = 0.0;
      for (var y = 0; y < patch; y++) {
        for (var x = 0; x < patch; x++) {
          final l = src.lumaAt(x0 + x, y0 + y).toDouble();
          buf[y * patch + x] = l;
          mean += l;
          sq += l * l;
        }
      }
      mean /= buf.length;
      final std = math.sqrt(math.max(0, sq / buf.length - mean * mean));
      if (std < 8) continue; // blank paper or blank table
      final (d, v) = _reblur(buf, patch, core);
      sumD += d;
      sumV += v;
      used++;
    }
    if (used < 2 || sumD <= 0) return null;
    // sumV / sumD is how much variation the extra blur removed.
    return (sumV / sumD).clamp(0.0, 1.0);
  }

  /// Variation (sum of neighbour differences) of the patch core, and how
  /// much a 9-tap blur takes away, over both directions.
  static (double, double) _reblur(Float32List f, int size, int core) {
    const r = 4; // 9-tap box
    final start = (size - core) ~/ 2;
    var d = 0.0, v = 0.0;
    // Horizontal.
    for (var y = start; y < start + core; y++) {
      final row = y * size;
      double box(int x) {
        var s = 0.0;
        for (var k = -r; k <= r; k++) {
          s += f[row + x + k];
        }
        return s / (2 * r + 1);
      }

      var prevB = box(start - 1);
      for (var x = start; x < start + core; x++) {
        final b = box(x);
        final df = (f[row + x] - f[row + x - 1]).abs();
        final db = (b - prevB).abs();
        d += df;
        v += math.max(0.0, df - db);
        prevB = b;
      }
    }
    // Vertical.
    for (var x = start; x < start + core; x++) {
      double box(int y) {
        var s = 0.0;
        for (var k = -r; k <= r; k++) {
          s += f[(y + k) * size + x];
        }
        return s / (2 * r + 1);
      }

      var prevB = box(start - 1);
      for (var y = start; y < start + core; y++) {
        final b = box(y);
        final df = (f[y * size + x] - f[(y - 1) * size + x]).abs();
        final db = (b - prevB).abs();
        d += df;
        v += math.max(0.0, df - db);
        prevB = b;
      }
    }
    return (d, v);
  }

  /// A coarse, contrast-normalised thumbnail of the page: tells "same page
  /// again" from "the next page" so one sheet is never saved twice.
  static Float32List signature(GrayImage g, Quad q) {
    const nx = 12, ny = 16;
    final s = Float32List(nx * ny);
    var mean = 0.0;
    for (var j = 0; j < ny; j++) {
      for (var i = 0; i < nx; i++) {
        // Average over the cell, so it reads ink density, not one pixel.
        var l = 0.0;
        for (var b = 0; b < 3; b++) {
          for (var a = 0; a < 3; a++) {
            final p = q.blend(
              0.08 + 0.84 * (i + (a + 0.5) / 3) / nx,
              0.08 + 0.84 * (j + (b + 0.5) / 3) / ny,
            );
            l += g.sample(p.x, p.y);
          }
        }
        l /= 9;
        s[j * nx + i] = l;
        mean += l;
      }
    }
    mean /= s.length;
    var sq = 0.0;
    for (var i = 0; i < s.length; i++) {
      s[i] -= mean;
      sq += s[i] * s[i];
    }
    final std = math.sqrt(sq / s.length);
    // Blank pages: keep the absolute level so two blank sheets match.
    final k = std < 4 ? 1 / 32 : 1 / std;
    for (var i = 0; i < s.length; i++) {
      s[i] *= k;
    }
    return s;
  }

  static double signatureDistance(Float32List a, Float32List b) {
    var d = 0.0;
    for (var i = 0; i < a.length; i++) {
      d += (a[i] - b[i]).abs();
    }
    return d / a.length;
  }
}
