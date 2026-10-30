import 'dart:math' as math;
import 'dart:typed_data';

import 'geometry.dart';
import 'pixels.dart';

/// What the detector made of one frame.
enum DetectionStatus {
  /// Four well-supported corners, the whole page in view.
  found,

  /// Nothing page-like.
  none,

  /// A page that runs off the edge of the frame.
  partial,

  /// A page, but too small to read well.
  tooSmall,
}

class Detection {
  const Detection(this.status, {this.quad, this.support = 0, this.minSide = 0});

  final DetectionStatus status;

  /// Corners in the coordinates of the image that was searched.
  final Quad? quad;

  /// Mean share of each side backed by a real edge (0–1).
  final double support;

  /// The weakest side's share.
  final double minSide;

  bool get found => status == DetectionStatus.found && quad != null;
}

/// Finds the four corners of a sheet of paper in a small grey image.
///
/// 1. Smooth, then take gradients; the noise floor is measured per frame
///    so dim and bright scenes get matching thresholds.
/// 2. Thin the edges and vote for straight lines (Hough), each pixel only
///    voting near its own gradient direction.
/// 3. Pair near-parallel lines, pair the pairs, and keep convex,
///    plausibly-angled quadrilaterals inside the frame.
/// 4. Score each by how continuously its four sides sit on a real edge with
///    one consistent light/dark polarity: text, table rules and clutter
///    break up or flip polarity, a page border does not.
/// 5. Among well-supported quads, take the largest, so a printed box inside
///    the page never wins over the page itself.
abstract final class DocumentDetector {
  static const _thetaBins = 180;
  static const _maxLines = 18;

  /// Smallest page, as a share of the frame.
  static const minAreaFraction = 0.12;

  /// [refine] off returns the raw line-intersection corners (diagnostics).
  static Detection detect(GrayImage input, {bool refine = true}) {
    final w = input.width, h = input.height;
    if (w < 32 || h < 32) return const Detection(DetectionStatus.none);
    final g = gaussian5(input);
    final grad = _Gradients.of(g);

    // Noise floor: the median gradient is set by flat areas.
    final median = grad.medianMagnitude();
    final edgeThreshold = math.max(10.0, 2.5 * median);
    final supportThreshold = math.max(8.0, 2.0 * median);

    final lines = _houghLines(grad, edgeThreshold);
    if (lines.length < 4) return const Detection(DetectionStatus.none);

    final minDim = math.min(w, h).toDouble();
    final frameArea = (w * h).toDouble();
    final pairs = <(_HLine, _HLine)>[];
    for (var i = 0; i < lines.length; i++) {
      for (var j = i + 1; j < lines.length; j++) {
        if (_angleBetween(lines[i], lines[j]) > 30) continue;
        if (_separation(lines[i], lines[j], w, h) < 0.12 * minDim) continue;
        pairs.add((lines[i], lines[j]));
      }
    }

    final scored = <_Scored>[];
    _Scored? bestPartial;
    _Scored? bestSmall;
    for (var p = 0; p < pairs.length; p++) {
      for (var q = p + 1; q < pairs.length; q++) {
        final (a, b) = pairs[p];
        final (c, d) = pairs[q];
        if (identical(a, c) ||
            identical(a, d) ||
            identical(b, c) ||
            identical(b, d)) {
          continue;
        }
        if (_angleBetween(a, c) < 40 ||
            _angleBetween(a, d) < 40 ||
            _angleBetween(b, c) < 40 ||
            _angleBetween(b, d) < 40) {
          continue;
        }
        final pts = [
          a.line.intersect(c.line),
          a.line.intersect(d.line),
          b.line.intersect(c.line),
          b.line.intersect(d.line),
        ];
        if (pts.any((p) => p == null)) continue;
        final quad = Quad.ordered(pts.cast<Pt>());
        if (!_plausibleShape(quad, minDim)) continue;
        // Far outside the frame: not even a partial page.
        if (!quad.insideRect(w.toDouble(), h.toDouble(), tolerance: minDim)) {
          continue;
        }
        final s = _score(quad, grad, supportThreshold, w, h);
        if (s == null) continue;
        final inside = quad.insideRect(
          w.toDouble(),
          h.toDouble(),
          tolerance: 0.01 * minDim,
        );
        final areaFrac = quad.area / frameArea;
        if (!inside) {
          if (s.good && (bestPartial == null || s.score > bestPartial.score)) {
            bestPartial = s;
          }
        } else if (areaFrac < minAreaFraction) {
          if (s.good && (bestSmall == null || s.score > bestSmall.score)) {
            bestSmall = s;
          }
        } else if (areaFrac <= 0.995) {
          scored.add(s);
        }
      }
    }

    if (scored.isNotEmpty) {
      final top = scored.where((s) => s.good).toList();
      if (top.isNotEmpty) {
        var bestScore = 0.0;
        for (final s in top) {
          bestScore = math.max(bestScore, s.score);
        }
        // The page, not a box printed on it: the largest quad that is
        // nearly as well supported as the best one.
        _Scored chosen = top.first;
        for (final s in top) {
          if (s.score < 0.8 * bestScore || s.minSide < 0.45) continue;
          if (chosen.score < 0.8 * bestScore ||
              s.quad.area > chosen.quad.area * 1.02 ||
              (s.quad.area >= chosen.quad.area * 0.98 &&
                  s.score > chosen.score)) {
            chosen = s;
          }
        }
        final refined = !refine
            ? chosen.quad
            : refineQuad(
                g.sample,
                chosen.quad,
                searchRadius: 2.5,
                step: 0.75,
                tangentSpacing: 1.0,
                maxShift: 2.5,
                minContrast: 4,
              );
        final quad =
            refined.insideRect(w + 1.0, h + 1.0, tolerance: 1) &&
                refined.isConvex
            ? refined
            : chosen.quad;
        return Detection(
          DetectionStatus.found,
          quad: quad,
          support: chosen.support,
          minSide: chosen.minSide,
        );
      }
    }
    if (bestPartial != null &&
        (bestSmall == null || bestPartial.score >= bestSmall.score)) {
      return Detection(
        DetectionStatus.partial,
        quad: bestPartial.quad,
        support: bestPartial.support,
        minSide: bestPartial.minSide,
      );
    }
    if (bestSmall != null) {
      return Detection(
        DetectionStatus.tooSmall,
        quad: bestSmall.quad,
        support: bestSmall.support,
        minSide: bestSmall.minSide,
      );
    }
    return const Detection(DetectionStatus.none);
  }

  /// Angles 40–140°, no sliver sides, opposite sides within 2.5× of each
  /// other: what a flat page looks like from any sane camera angle.
  static bool _plausibleShape(Quad q, double minDim) {
    if (!q.isConvex) return false;
    for (final a in q.interiorAngles) {
      if (a < 40 || a > 140) return false;
    }
    final s = q.sideLengths;
    for (final l in s) {
      if (l < 0.1 * minDim) return false;
    }
    if (math.min(s[0], s[2]) < 0.4 * math.max(s[0], s[2])) return false;
    if (math.min(s[1], s[3]) < 0.4 * math.max(s[1], s[3])) return false;
    return true;
  }

  static _Scored? _score(
    Quad quad,
    _Gradients grad,
    double threshold,
    int w,
    int h,
  ) {
    final c = quad.corners;
    final centre = quad.centroid;
    final sides = <double>[];
    final polarity = <int>[];
    for (var i = 0; i < 4; i++) {
      final a = c[i], b = c[(i + 1) % 4];
      final len = a.distanceTo(b);
      final dir = (b - a).unit;
      var n = Pt(-dir.y, dir.x);
      if (n.dot(centre - a) < 0) n = n * -1; // inward
      final samples = math.max(12, len ~/ 2);
      var seen = 0, hit = 0, signSum = 0;
      for (var k = 0; k < samples; k++) {
        final t = 0.06 + 0.88 * (k + 0.5) / samples;
        final p = a + (b - a) * t;
        if (p.x < 1 || p.y < 1 || p.x > w - 2 || p.y > h - 2) continue;
        seen++;
        var best = 0.0;
        for (final off in const [-1.5, -0.75, 0.0, 0.75, 1.5]) {
          final qx = (p.x + n.x * off).floor(), qy = (p.y + n.y * off).floor();
          if (qx < 1 || qy < 1 || qx >= w - 1 || qy >= h - 1) continue;
          final i2 = qy * w + qx;
          final gx = grad.gx[i2], gy = grad.gy[i2];
          final proj = gx * n.x + gy * n.y;
          final mag = math.sqrt(gx * gx + gy * gy);
          if (proj.abs() > best.abs() && proj.abs() >= 0.75 * mag) best = proj;
        }
        if (best.abs() >= threshold) {
          hit++;
          signSum += best > 0 ? 1 : -1;
        }
      }
      // Mostly off-frame sides count as unsupported.
      if (seen < samples * 0.5) {
        sides.add(seen == 0 ? 0 : 0.5 * hit / samples);
        polarity.add(signSum >= 0 ? 1 : -1);
        continue;
      }
      final coverage = hit / seen;
      final consistency = hit == 0 ? 0.0 : signSum.abs() / hit;
      sides.add(coverage * (0.55 + 0.45 * consistency));
      polarity.add(signSum >= 0 ? 1 : -1);
    }
    final mean = sides.reduce((a, b) => a + b) / 4;
    final minSide = sides.reduce(math.min);
    // Gentle preference for right angles (a page seen almost square-on).
    var dev = 0.0;
    for (final a in quad.interiorAngles) {
      dev = math.max(dev, (a - 90).abs());
    }
    final score = (0.6 * mean + 0.4 * minSide) * (1 - 0.25 * dev / 50);
    return _Scored(quad, score, mean, minSide, polarity);
  }

  static double _angleBetween(_HLine a, _HLine b) {
    var d = (a.thetaDeg - b.thetaDeg).abs() % 180;
    if (d > 90) d = 180 - d;
    return d;
  }

  /// Distance between two near-parallel lines, measured at the frame centre.
  static double _separation(_HLine a, _HLine b, int w, int h) {
    final c = Pt(w / 2, h / 2);
    final nb = b.line.normal;
    final pb = c - nb * (c - b.line.point).dot(nb);
    return a.line.distanceTo(pb);
  }

  static List<_HLine> _houghLines(_Gradients grad, double edgeThreshold) {
    final w = grad.w, h = grad.h;
    final maxRho = (math.sqrt(w * w + h * h)).ceil();
    final rhoBins = 2 * maxRho + 1;
    final acc = Int32List(_thetaBins * rhoBins);
    final cosT = Float64List(_thetaBins), sinT = Float64List(_thetaBins);
    for (var t = 0; t < _thetaBins; t++) {
      cosT[t] = math.cos(t * math.pi / 180);
      sinT[t] = math.sin(t * math.pi / 180);
    }
    final gx = grad.gx, gy = grad.gy, mag = grad.mag;
    final edgeX = <double>[], edgeY = <double>[], edgePhi = <double>[];
    // Full gradient direction (dark -> light), to keep one polarity.
    final edgeCos = <double>[], edgeSin = <double>[];
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final m = mag[i];
        if (m < edgeThreshold) continue;
        // Non-maximum suppression along the gradient (thin edges).
        final ax = gx[i].abs(), ay = gy[i].abs();
        final double m1, m2;
        if (ax > 2.4142 * ay) {
          m1 = mag[i - 1];
          m2 = mag[i + 1];
        } else if (ay > 2.4142 * ax) {
          m1 = mag[i - w];
          m2 = mag[i + w];
        } else if ((gx[i] > 0) == (gy[i] > 0)) {
          m1 = mag[i - w - 1];
          m2 = mag[i + w + 1];
        } else {
          m1 = mag[i - w + 1];
          m2 = mag[i + w - 1];
        }
        if (m < m1 || m < m2) continue;
        final full = math.atan2(gy[i], gx[i]);
        var phi = full * 180 / math.pi;
        if (phi < 0) phi += 180;
        if (phi >= 180) phi -= 180;
        final base = phi.round();
        final px = x + 0.5, py = y + 0.5;
        edgeX.add(px);
        edgeY.add(py);
        edgePhi.add(phi);
        edgeCos.add(math.cos(full));
        edgeSin.add(math.sin(full));
        for (var k = -4; k <= 4; k++) {
          var t = base + k;
          if (t < 0) t += 180;
          if (t >= 180) t -= 180;
          final rho = (px * cosT[t] + py * sinT[t]).round();
          acc[t * rhoBins + rho + maxRho]++;
        }
      }
    }

    final minVotes = (0.12 * math.min(w, h)).round();
    final peaks = <int>[];
    for (var i = 0; i < acc.length; i++) {
      if (acc[i] >= minVotes) peaks.add(i);
    }
    peaks.sort((a, b) => acc[b].compareTo(acc[a]));
    // Edge pixels bucketed by direction, so a refit only visits the ones
    // that could lie on the line.
    final byAngle = List.generate(_thetaBins, (_) => <int>[]);
    for (var e = 0; e < edgePhi.length; e++) {
      byAngle[edgePhi[e].round() % _thetaBins].add(e);
    }
    final chosen = <_HLine>[];
    var tried = 0;
    for (final idx in peaks) {
      if (chosen.length >= _maxLines || tried >= 160) break;
      final t = idx ~/ rhoBins;
      final rho = (idx % rhoBins - maxRho).toDouble();
      // Cheap first: the same accumulator neighbourhood as a chosen line.
      if (chosen.any(
        (c) =>
            _thetaDiff(c.thetaDeg, t.toDouble()) <= 2 &&
            (c.rho - rho).abs() <= 3,
      )) {
        continue;
      }
      tried++;
      final n = Pt(cosT[t], sinT[t]);
      var line = Line2(n * rho, Pt(-n.y, n.x));
      var theta = t.toDouble();
      // The accumulator is quantised (1°, 1 px); refit on the edge pixels
      // along the line, tightening the band each pass.
      // Which way the line's gradient points (paper lighter or darker than
      // what is beside it); an aligned edge of the other polarity, such as
      // a book lying next to the page, is another object.
      Pt? polarity;
      for (final band in const [3.0, 2.0, 1.25]) {
        final near = <int>[];
        var sx = 0.0, sy = 0.0;
        final px = line.point.x, py = line.point.y;
        final dx = line.dir.x, dy = line.dir.y;
        final centre = theta.round();
        for (var k = -12; k <= 12; k++) {
          for (final e in byAngle[(centre + k) % _thetaBins]) {
            if (((edgeX[e] - px) * dy - (edgeY[e] - py) * dx).abs() > band) {
              continue;
            }
            near.add(e);
            sx += edgeCos[e];
            sy += edgeSin[e];
          }
        }
        polarity ??= Pt(sx, sy);
        final pts = <Pt>[
          for (final e in near)
            if (edgeCos[e] * polarity.x + edgeSin[e] * polarity.y > 0)
              Pt(edgeX[e], edgeY[e]),
        ];
        if (pts.length < minVotes * 0.6) break;
        final fit = Line2.fit(pts);
        if (fit == null) break;
        line = fit;
        var a = math.atan2(fit.normal.y, fit.normal.x) * 180 / math.pi;
        if (a < 0) a += 180;
        if (a >= 180) a -= 180;
        theta = a;
      }
      if (chosen.any((c) => _sameLine(c.line, c.thetaDeg, line, theta, w, h))) {
        continue;
      }
      final nr = Pt(
        math.cos(theta * math.pi / 180),
        math.sin(theta * math.pi / 180),
      );
      chosen.add(_HLine(theta, nr.dot(line.point), acc[idx], line));
    }
    return chosen;
  }
}

double _thetaDiff(double a, double b) {
  var d = (a - b).abs() % 180;
  if (d > 90) d = 180 - d;
  return d;
}

/// Two lines are one when they stay within a few pixels of each other
/// across the whole frame (not just near one point, which near-parallel
/// lines through a page corner also do).
bool _sameLine(Line2 a, double ta, Line2 b, double tb, int w, int h) {
  if (_thetaDiff(ta, tb) > 6) return false;
  final seg = _clip(a, w.toDouble(), h.toDouble());
  if (seg == null) return true;
  return b.distanceTo(seg.$1) <= 4 && b.distanceTo(seg.$2) <= 4;
}

/// The part of [l] inside the frame.
(Pt, Pt)? _clip(Line2 l, double w, double h) {
  var t0 = -1e9, t1 = 1e9;
  for (final (p, d, max) in [
    (l.point.x, l.dir.x, w),
    (l.point.y, l.dir.y, h),
  ]) {
    if (d.abs() < 1e-9) {
      if (p < 0 || p > max) return null;
      continue;
    }
    var a = (0 - p) / d, b = (max - p) / d;
    if (a > b) (a, b) = (b, a);
    t0 = math.max(t0, a);
    t1 = math.min(t1, b);
  }
  if (t0 > t1) return null;
  return (l.point + l.dir * t0, l.point + l.dir * t1);
}

class _HLine {
  _HLine(this.thetaDeg, this.rho, this.votes, this.line);
  final double thetaDeg;
  final double rho;
  final int votes;
  final Line2 line;
}

class _Scored {
  _Scored(this.quad, this.score, this.support, this.minSide, this.polarity);
  final Quad quad;
  final double score;
  final double support;
  final double minSide;
  final List<int> polarity;

  bool get good => support >= 0.5 && minSide >= 0.3;
}

class _Gradients {
  _Gradients(this.w, this.h, this.gx, this.gy, this.mag);

  final int w;
  final int h;
  final Float32List gx;
  final Float32List gy;
  final Float32List mag;

  static _Gradients of(GrayImage g) {
    final w = g.width, h = g.height, d = g.data;
    final gx = Float32List(w * h), gy = Float32List(w * h);
    final mag = Float32List(w * h);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final a = d[i - w - 1], b = d[i - w], c = d[i - w + 1];
        final l = d[i - 1], r = d[i + 1];
        final e = d[i + w - 1], f = d[i + w], k = d[i + w + 1];
        final vx = (c + 2 * r + k) - (a + 2 * l + e);
        final vy = (e + 2 * f + k) - (a + 2 * b + c);
        gx[i] = vx.toDouble();
        gy[i] = vy.toDouble();
        mag[i] = math.sqrt((vx * vx + vy * vy).toDouble());
      }
    }
    return _Gradients(w, h, gx, gy, mag);
  }

  double medianMagnitude() {
    final hist = Int32List(1025);
    var n = 0;
    for (var i = 0; i < mag.length; i++) {
      hist[math.min(1024, mag[i].round())]++;
      n++;
    }
    var seen = 0;
    for (var v = 0; v < hist.length; v++) {
      seen += hist[v];
      if (seen * 2 >= n) return v.toDouble();
    }
    return 0;
  }
}

/// 5-tap binomial blur (σ ≈ 1): keeps page borders, softens paper grain
/// and text so they vote less.
GrayImage gaussian5(GrayImage g) {
  final w = g.width, h = g.height, d = g.data;
  final tmp = Uint16List(w * h);
  for (var y = 0; y < h; y++) {
    final r = y * w;
    for (var x = 0; x < w; x++) {
      final x0 = x < 2 ? 0 : x - 2, x1 = x < 1 ? 0 : x - 1;
      final x3 = x >= w - 1 ? w - 1 : x + 1, x4 = x >= w - 2 ? w - 1 : x + 2;
      tmp[r + x] =
          d[r + x0] + 4 * d[r + x1] + 6 * d[r + x] + 4 * d[r + x3] + d[r + x4];
    }
  }
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final y0 = (y < 2 ? 0 : y - 2) * w, y1 = (y < 1 ? 0 : y - 1) * w;
    final y3 = (y >= h - 1 ? h - 1 : y + 1) * w;
    final y4 = (y >= h - 2 ? h - 1 : y + 2) * w;
    final r = y * w;
    for (var x = 0; x < w; x++) {
      out[r + x] =
          (tmp[y0 + x] +
              4 * tmp[y1 + x] +
              6 * tmp[r + x] +
              4 * tmp[y3 + x] +
              tmp[y4 + x] +
              128) >>
          8;
    }
  }
  return GrayImage(w, h, out);
}

/// Moves each side of [q] onto the strongest nearby edge: samples the
/// brightness profile across the side at many points, takes the steepest
/// step (sub-pixel), fits a line through those steps ignoring outliers, and
/// re-intersects the four lines. A side that cannot be found reliably, or
/// would move more than [maxShift], keeps its old line.
Quad refineQuad(
  double Function(double x, double y) luma,
  Quad q, {
  required double searchRadius,
  required double step,
  required double tangentSpacing,
  required double maxShift,
  required double minContrast,
  int samplesPerSide = 40,
}) {
  final c = q.corners;
  final centre = q.centroid;
  final lines = <Line2>[];
  for (var i = 0; i < 4; i++) {
    final a = c[i], b = c[(i + 1) % 4];
    final dir = (b - a).unit;
    var n = Pt(-dir.y, dir.x);
    if (n.dot(centre - a) < 0) n = n * -1; // inward
    final original = Line2(a, dir);
    final steps = (searchRadius / step).ceil();
    final found = <(Pt, double)>[];
    for (var k = 0; k < samplesPerSide; k++) {
      final t = 0.1 + 0.8 * (k + 0.5) / samplesPerSide;
      final p = a + (b - a) * t;
      double prof(double s) {
        var sum = 0.0;
        for (final o in const [-1.0, 0.0, 1.0]) {
          final q2 = p + n * s + dir * (o * tangentSpacing);
          sum += luma(q2.x, q2.y);
        }
        return sum / 3;
      }

      final values = <double>[];
      for (var j = -steps - 1; j <= steps + 1; j++) {
        values.add(prof(j * step));
      }
      // Derivative across the side, inward direction.
      var bestJ = 0;
      var best = 0.0;
      final d = <double>[];
      for (var j = 1; j < values.length - 1; j++) {
        d.add(values[j + 1] - values[j - 1]);
      }
      for (var j = 0; j < d.length; j++) {
        if (d[j].abs() > best.abs()) {
          best = d[j];
          bestJ = j;
        }
      }
      if (best.abs() < minContrast) continue;
      var offset = 0.0;
      if (bestJ > 0 && bestJ < d.length - 1) {
        final l = d[bestJ - 1].abs(),
            m = d[bestJ].abs(),
            r = d[bestJ + 1].abs();
        final den = l - 2 * m + r;
        if (den.abs() > 1e-6) offset = (0.5 * (l - r) / den).clamp(-0.5, 0.5);
      }
      final s = (bestJ - steps + offset) * step;
      found.add((p + n * s, best));
    }
    lines.add(
      _robustSide(found, original, a, b, maxShift, samplesPerSide) ?? original,
    );
  }
  final out = <Pt>[];
  for (var i = 0; i < 4; i++) {
    final p = lines[(i + 3) % 4].intersect(lines[i]);
    if (p == null) return q;
    out.add(p);
  }
  final refined = Quad(out[0], out[1], out[2], out[3]);
  if (!refined.isConvex || refined.maxCornerDistance(q) > maxShift * 2.5) {
    return q;
  }
  return refined;
}

Line2? _robustSide(
  List<(Pt, double)> found,
  Line2 original,
  Pt start,
  Pt end,
  double maxShift,
  int samples,
) {
  if (found.length < samples * 0.4) return null;
  // One polarity only: the page edge, not a shadow or a printed rule
  // beside it.
  final pos = found.where((f) => f.$2 > 0).toList();
  final neg = found.where((f) => f.$2 < 0).toList();
  final same = pos.length >= neg.length ? pos : neg;
  if (same.length < samples * 0.35) return null;
  var pts = [for (final f in same) f.$1];
  var line = Line2.fit(pts);
  for (var iter = 0; iter < 2 && line != null; iter++) {
    final res = [for (final p in pts) line.distanceTo(p)]..sort();
    final mad = res[res.length ~/ 2];
    final cut = math.max(0.75, 2.5 * mad);
    final kept = [
      for (final p in pts)
        if (line.distanceTo(p) <= cut) p,
    ];
    if (kept.length < samples * 0.3) return null;
    pts = kept;
    line = Line2.fit(pts);
  }
  if (line == null) return null;
  // Same orientation as before, and not wandered off to another edge.
  var dir = line.dir;
  if (dir.dot(original.dir) < 0) dir = dir * -1;
  if (dir.dot(original.dir) < math.cos(8 * math.pi / 180)) return null;
  final fitted = Line2(line.point, dir);
  // Not wandered off to another edge at either end of the side.
  if (fitted.distanceTo(start) > maxShift ||
      fitted.distanceTo(end) > maxShift) {
    return null;
  }
  return fitted;
}
