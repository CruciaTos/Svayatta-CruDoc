import 'dart:math' as math;
import 'dart:typed_data';

/// Averages several straightened pictures of the same page into one, to take
/// the sensor's grain out of it.
///
/// [base] is the sharpest; [others] are the same size, RGB. Each is first
/// nudged to line up with [base] tile by tile (straightening leaves them a
/// fraction of a pixel apart), and a pixel only counts as far as it agrees:
/// where something moved, [base] stands alone, so nothing ghosts or softens.
Uint8List mergeFrames(
  Uint8List base,
  List<Uint8List> others,
  int width,
  int height,
) {
  if (others.isEmpty || width < 32 || height < 32) return base;
  const tile = 96;
  // Differences of brightness up to this are taken for grain.
  const grain = 26;
  final across = math.max(1, (width / tile).round());
  final down = math.max(1, (height / tile).round());
  final tw = width / across, th = height / down;
  final lb = _luma(base, width * height);

  final n = width * height;
  final sum = Float32List(n * 3);
  final weight = Float32List(n);
  for (var i = 0; i < n; i++) {
    weight[i] = 1;
    final j = i * 3;
    sum[j] = base[j].toDouble();
    sum[j + 1] = base[j + 1].toDouble();
    sum[j + 2] = base[j + 2].toDouble();
  }

  for (final other in others) {
    final lo = _luma(other, n);
    final dx = Float32List(across * down), dy = Float32List(across * down);
    final lift = Float32List(across * down);
    for (var ty = 0; ty < down; ty++) {
      for (var tx = 0; tx < across; tx++) {
        final k = ty * across + tx;
        final x0 = math.max(2, (tx * tw).floor());
        final x1 = math.min(width - 3, ((tx + 1) * tw).floor());
        final y0 = math.max(2, (ty * th).floor());
        final y1 = math.min(height - 3, ((ty + 1) * th).floor());
        var u = 0.0, v = 0.0, bright = 0.0;
        // Two rounds of the small-movement solution (Lucas–Kanade).
        for (var round = 0; round < 2; round++) {
          var xx = 0.0, xy = 0.0, yy = 0.0, xr = 0.0, yr = 0.0;
          var diff = 0.0;
          var count = 0;
          final ox = u.floor(), oy = v.floor();
          final fx = u - ox, fy = v - oy;
          for (var y = y0; y < y1; y += 2) {
            for (var x = x0; x < x1; x += 2) {
              final sx = x + ox, sy = y + oy;
              if (sx < 0 || sy < 0 || sx >= width - 1 || sy >= height - 1) {
                continue;
              }
              final i = sy * width + sx;
              final top = lo[i] + (lo[i + 1] - lo[i]) * fx;
              final low =
                  lo[i + width] + (lo[i + width + 1] - lo[i + width]) * fx;
              final c = y * width + x;
              final r = top + (low - top) * fy - lb[c] - bright;
              final gx = (lb[c + 1] - lb[c - 1]) * 0.5;
              final gy = (lb[c + width] - lb[c - width]) * 0.5;
              xx += gx * gx;
              xy += gx * gy;
              yy += gy * gy;
              xr += gx * r;
              yr += gy * r;
              diff += r;
              count++;
            }
          }
          if (count == 0) break;
          bright += diff / count;
          final det = xx * yy - xy * xy;
          // A plain tile says nothing about movement (and needs none).
          if (det <= 1e-3 * (xx + yy) * (xx + yy) || xx + yy < 20 * count) {
            continue;
          }
          u = (u - (yy * xr - xy * yr) / det).clamp(-3.0, 3.0);
          v = (v - (xx * yr - xy * xr) / det).clamp(-3.0, 3.0);
        }
        dx[k] = u;
        dy[k] = v;
        lift[k] = bright;
      }
    }

    for (var y = 0; y < height; y++) {
      // The tiles' answers, blended so that no seam shows.
      final gy = (y / th - 0.5).clamp(0.0, down - 1.0);
      final j0 = gy.floor(), j1 = math.min(j0 + 1, down - 1);
      final ay = gy - j0;
      for (var x = 0; x < width; x++) {
        final gx = (x / tw - 0.5).clamp(0.0, across - 1.0);
        final i0 = gx.floor(), i1 = math.min(i0 + 1, across - 1);
        final ax = gx - i0;
        double blend(Float32List f) {
          final a = f[j0 * across + i0], b = f[j0 * across + i1];
          final c = f[j1 * across + i0], d = f[j1 * across + i1];
          final top = a + (b - a) * ax, low = c + (d - c) * ax;
          return top + (low - top) * ay;
        }

        final sx = x + blend(dx), sy = y + blend(dy);
        if (sx < 0 || sy < 0 || sx >= width - 1 || sy >= height - 1) continue;
        final ix = sx.floor(), iy = sy.floor();
        final fx = sx - ix, fy = sy - iy;
        final w00 = (1 - fx) * (1 - fy), w01 = fx * (1 - fy);
        final w10 = (1 - fx) * fy, w11 = fx * fy;
        final i = iy * width + ix;
        final seen =
            lo[i] * w00 +
            lo[i + 1] * w01 +
            lo[i + width] * w10 +
            lo[i + width + 1] * w11 -
            blend(lift);
        final c = y * width + x;
        final off = (seen - lb[c]).abs();
        if (off >= grain) continue;
        // Full weight when they agree well, fading as they part; and on the
        // edges of print, where a hair of misalignment would soften, the
        // sharpest view mostly speaks for itself.
        var w = off < grain / 2 ? 1.0 : 2 - 2 * off / grain;
        if (x > 0 && y > 0 && x < width - 1 && y < height - 1) {
          final edge =
              (lb[c + 1] - lb[c - 1]).abs() +
              (lb[c + width] - lb[c - width]).abs();
          if (edge > 30) w *= math.max(0.2, 1 - (edge - 30) / 90);
        }
        final shift = blend(lift);
        final p = i * 3, q = p + width * 3;
        for (var ch = 0; ch < 3; ch++) {
          sum[c * 3 + ch] +=
              w *
              (other[p + ch] * w00 +
                  other[p + 3 + ch] * w01 +
                  other[q + ch] * w10 +
                  other[q + 3 + ch] * w11 -
                  shift);
        }
        weight[c] += w;
      }
    }
  }

  final out = Uint8List(n * 3);
  for (var i = 0; i < n; i++) {
    final w = weight[i];
    for (var ch = 0; ch < 3; ch++) {
      final v = sum[i * 3 + ch] / w;
      out[i * 3 + ch] = v <= 0 ? 0 : (v >= 255 ? 255 : v.round());
    }
  }
  return out;
}

Uint8List _luma(Uint8List rgb, int n) {
  final out = Uint8List(n);
  for (var i = 0, j = 0; i < n; i++, j += 3) {
    out[i] = (rgb[j] * 77 + rgb[j + 1] * 150 + rgb[j + 2] * 29) >> 8;
  }
  return out;
}
