import 'dart:math' as math;
import 'dart:typed_data';

import 'detector.dart';
import 'geometry.dart';
import 'pixels.dart';

/// The four corners once the person has set one by hand, kept stuck to the
/// page while the camera stays live.
///
/// The page is followed as one flat sheet, not corner by corner: some two
/// dozen well-marked spots on it (print, edges, the corners themselves) are
/// found again in each frame, one movement is fitted to all of them, and all
/// four corners take that movement. So the outline never changes shape by
/// itself, a covered or plain corner rides along with the rest, and an odd
/// mismatch is outvoted. Spots are compared with a key frame rather than
/// with the frame before, so small errors do not add up. All positions are
/// in the frame's pixels.
class CornerTracker {
  CornerTracker(Quad start, {required bool sure, PixelSource? frame})
    : points = start.corners.toList(),
      placed = List.filled(4, sure),
      sensed = List.filled(4, false) {
    if (frame != null) {
      final levels = _previous = _Levels.of(frame);
      _rekey(levels);
    }
  }

  final List<Pt> points;

  /// Corners known to be meant: found by the scanner or set by finger. The
  /// others are only stand-ins until set.
  final List<bool> placed;

  /// Corners sitting on a corner sensed in the picture.
  final List<bool> sensed;

  /// The corner under the finger: it goes where the finger goes, or onto a
  /// corner sensed close to there.
  int? get held => _held;
  int? _held;
  Pt _wanted = const Pt(0, 0);
  double _pull = 0;

  _Levels? _previous;
  _Key? _key;

  /// How the key frame has moved to give this one.
  _Pose _pose = _Pose.still;
  int _lost = 0;
  int _count = 0;

  static const _lostFrames = 8;
  static const _spots = 28;

  /// Spots used to find the rough movement since the last frame.
  static const _scouts = 8;

  Quad get quad => Quad(points[0], points[1], points[2], points[3]);

  /// All four are meant, so the page may be captured on its own.
  bool get complete => placed.every((p) => p);

  /// Corner [i] goes to [at].
  void set(int i, Pt at) {
    points[i] = at;
    placed[i] = true;
    sensed[i] = false;
    _pin(i);
  }

  /// Corner [i] is under the finger at [at]. A corner sensed within [pull]
  /// of there draws it on like a magnet.
  void hold(PixelSource frame, int i, Pt at, double pull) {
    if (_held != i) sensed[i] = false;
    _held = i;
    _wanted = at;
    _pull = pull;
    placed[i] = true;
    _attract(frame);
  }

  /// The finger has let go.
  void release() {
    _held = null;
    _pull = 0;
  }

  /// Settles corner [i] onto a corner sensed within [reach] in [frame].
  bool snap(PixelSource frame, int i, double reach) {
    final corner = _sense(frame, i, points[i], reach);
    if (corner == null) return false;
    points[i] = corner;
    sensed[i] = true;
    _pin(i);
    return true;
  }

  /// Eases every corner [share] of the way to where [toward] has it.
  void lean(Quad toward, double share) {
    final to = toward.corners;
    for (var i = 0; i < 4; i++) {
      points[i] = points[i] + (to[i] - points[i]) * share;
      _pin(i);
    }
  }

  /// Moves the corners with the page. False once the page has been out of
  /// reach for a while (put away, or swapped).
  bool follow(PixelSource frame) {
    final now = _Levels.of(frame);
    final before = _previous;
    _previous = now;
    if (before == null || !before.fits(now)) {
      _rekey(now);
      return true;
    }
    final key = _key;
    if (key == null || key.spots.isEmpty) {
      // Nothing to hold on to yet: look again from here.
      _rekey(now);
      return ++_lost < _lostFrames;
    }
    final long = math.max(frame.width, frame.height).toDouble();

    // Roughly how far things went since the last frame, so that a quick
    // movement of the phone is not lost.
    final moves = <Pt>[];
    for (final spot in key.spots.take(_scouts)) {
      final at = _pose.apply(spot.at);
      final s = _match(
        before.coarse,
        now.coarseSums,
        at.x ~/ before.coarseFactor,
        at.y ~/ before.coarseFactor,
        const Pt(0, 0),
        half: 6,
        search: 14,
      );
      if (s != null) moves.add(s * before.coarseFactor.toDouble());
    }
    final rough = _middle(moves);

    // Each spot, looked for where that says it should be.
    final from = <Pt>[], to = <Pt>[];
    final f = now.fineFactor.toDouble();
    for (final spot in key.spots) {
      final expected = _pose.apply(spot.at) + rough;
      final s = _match(
        key.levels.fine,
        now.fineSums,
        spot.x,
        spot.y,
        (expected - spot.at) * (1 / f),
        half: 8,
        search: 5,
      );
      if (s == null) continue;
      from.add(spot.at);
      to.add(spot.at + s * f);
    }
    final fit = _Pose.fit(from, to, 0.004 * long);
    if (fit != null) {
      _pose = fit.pose;
      _lost = 0;
    } else {
      if (++_lost >= _lostFrames) return false;
      if (moves.isNotEmpty) _pose = _pose.moved(rough);
    }

    final width = frame.width.toDouble(), height = frame.height.toDouble();
    for (var i = 0; i < 4; i++) {
      if (i == _held && !sensed[i]) continue;
      final p = _pose.apply(key.corners[i]);
      points[i] = Pt(p.x.clamp(0.0, width), p.y.clamp(0.0, height));
    }

    // Now and then, ease a sensed corner onto the corner itself: too little
    // at a time to be seen moving.
    final turn = _count++;
    final i = turn % 4;
    if (turn.isEven && i != _held && sensed[i]) {
      final corner = _sense(frame, i, points[i], 0.008 * long);
      if (corner != null && corner.distanceTo(points[i]) < 0.006 * long) {
        points[i] = points[i] + (corner - points[i]) * 0.3;
        _pin(i);
      }
    }
    // The page moves under a still finger: look again around it.
    _attract(frame);

    // Compare with a fresh key frame once the view has changed a lot.
    if (fit != null && (fit.share < 0.6 || _pose.strain > 0.07)) _rekey(now);
    return true;
  }

  void _attract(PixelSource frame) {
    final i = _held;
    if (i == null || _pull <= 0) return;
    final corner = _sense(frame, i, _wanted, _pull);
    if (corner != null) {
      points[i] = corner;
      sensed[i] = true;
    } else if (!sensed[i] || points[i].distanceTo(_wanted) > 1.3 * _pull) {
      // One blurred frame does not shake it off; moving away does.
      points[i] = _wanted;
      sensed[i] = false;
    }
    _pin(i);
  }

  /// A corner of the page near [at] that corner [i] could be.
  Pt? _sense(PixelSource frame, int i, Pt at, double reach) {
    final corner = DocumentDetector.cornerNear(
      frame,
      at,
      radius: reach,
      inward: at + Quad.inward[i] * (4 * reach),
    );
    if (corner == null) return null;
    // Two corners never share a spot.
    for (var k = 0; k < 4; k++) {
      if (k != i && points[k].distanceTo(corner) < reach / 2) return null;
    }
    return corner;
  }

  /// Corner [i] was put somewhere new: note where that is on the key frame.
  void _pin(int i) => _key?.corners[i] = _pose.invert(points[i]);

  /// Takes [levels] as the frame to compare with from now on.
  void _rekey(_Levels levels) {
    _key = _Key(levels, points.toList(), _pickSpots(levels, quad));
    _pose = _Pose.still;
  }

  /// Well-marked spots on and just around the page: ones that look different
  /// when shifted in any direction, spread over the sheet.
  static List<_Spot> _pickSpots(_Levels levels, Quad page) {
    final g = levels.fine;
    final f = levels.fineFactor;
    const half = 8;
    final long = math.max(g.width, g.height).toDouble();
    final around = page.scale(1 / f).expanded(0.015 * long);
    final found = <(double, int, int)>[];
    for (var j = 0; j <= 16; j++) {
      for (var i = 0; i <= 12; i++) {
        final p = around.blend(i / 12, j / 16);
        final x = p.x.floor(), y = p.y.floor();
        if (x < half + 1 || y < half + 1) continue;
        if (x > g.width - half - 2 || y > g.height - half - 2) continue;
        var xx = 0.0, yy = 0.0, xy = 0.0;
        for (var v = -half; v <= half; v += 2) {
          final row = (y + v) * g.width + x;
          for (var u = -half; u <= half; u += 2) {
            final dx = g.data[row + u + 1] - g.data[row + u - 1];
            final dy = g.data[row + u + g.width] - g.data[row + u - g.width];
            xx += dx * dx;
            yy += dy * dy;
            xy += dx * dy;
          }
        }
        // The weaker of the two directions (a plain edge only has one).
        final spread = math.sqrt((xx - yy) * (xx - yy) + 4 * xy * xy);
        final weakest = (xx + yy - spread) / 2;
        if (weakest > 81 * 20) found.add((weakest, x, y));
      }
    }
    found.sort((a, b) => b.$1.compareTo(a.$1));
    final spots = <_Spot>[];
    final apart = 0.035 * long;
    for (final (_, x, y) in found) {
      if (spots.length >= _spots) break;
      if (spots.any(
        (s) => (s.x - x) * (s.x - x) + (s.y - y) * (s.y - y) < apart * apart,
      )) {
        continue;
      }
      spots.add(_Spot(x, y, Pt((x + 0.5) * f, (y + 0.5) * f)));
    }
    return spots;
  }

  static Pt _middle(List<Pt> moves) {
    if (moves.isEmpty) return const Pt(0, 0);
    double median(List<double> v) => (v..sort())[v.length ~/ 2];
    return Pt(
      median([for (final m in moves) m.x]),
      median([for (final m in moves) m.y]),
    );
  }

  /// The displacement, near [guess], at which the patch around pixel
  /// ([cx], [cy]) of [a] best appears in [b]. Brightness changes are
  /// ignored. Null when the patch is plain or not to be found.
  static Pt? _match(
    GrayImage a,
    _Summed b,
    int cx,
    int cy,
    Pt guess, {
    required int half,
    required int search,
  }) {
    final size = 2 * half + 1;
    final x = cx - half, y = cy - half;
    if (x < 0 || y < 0 || x > a.width - size || y > a.height - size) {
      return null;
    }
    final n = size * size;
    final patch = Int32List(n);
    var sum = 0;
    for (var j = 0; j < size; j++) {
      final row = (y + j) * a.width + x;
      for (var i = 0; i < size; i++) {
        sum += patch[j * size + i] = a.data[row + i];
      }
    }
    final mean = sum ~/ n;
    var spread = 0;
    for (var k = 0; k < n; k++) {
      patch[k] -= mean;
      spread += patch[k].abs();
    }
    if (spread < 4 * n) return null; // nothing to hold on to

    final gx = guess.x.round(), gy = guess.y.round();
    final sums = b.sums;
    final across = b.image.width + 1;
    final data = b.image.data, width = b.image.width;

    /// How unlike the patch the place at ([dx], [dy]) is, giving up once it
    /// is past [enough]. Infinite off the picture.
    double cost(int dx, int dy, double enough) {
      final left = x + gx + dx, top = y + gy + dy;
      if (left < 0 || top < 0) return double.infinity;
      if (left > width - size || top > b.image.height - size) {
        return double.infinity;
      }
      final m =
          (sums[(top + size) * across + left + size] -
              sums[top * across + left + size] -
              sums[(top + size) * across + left] +
              sums[top * across + left]) ~/
          n;
      // Between equals, the smaller movement.
      var diff = 0.002 * spread * (dx * dx + dy * dy) / (search + 1);
      for (var j = 0; j < size; j++) {
        final row = (top + j) * width + left;
        final from = j * size;
        var line = 0;
        for (var i = 0; i < size; i++) {
          final d = data[row + i] - m - patch[from + i];
          line += d < 0 ? -d : d;
        }
        diff += line;
        if (diff >= enough) break;
      }
      return diff;
    }

    // The guess first: usually close to right, so the rest give up early.
    var best = cost(0, 0, double.infinity);
    var bx = 0, by = 0;
    for (var dy = -search; dy <= search; dy++) {
      for (var dx = -search; dx <= search; dx++) {
        if (dx == 0 && dy == 0) continue;
        final c = cost(dx, dy, best);
        if (c < best) {
          best = c;
          bx = dx;
          by = dy;
        }
      }
    }
    if (best > 0.65 * spread) return null; // not the same thing

    // Between pixels, from the neighbours' costs.
    double fraction(double low, double high) {
      if (!low.isFinite || !high.isFinite) return 0;
      final den = low - 2 * best + high;
      return den <= 1e-6 ? 0 : (0.5 * (low - high) / den).clamp(-0.5, 0.5);
    }

    double near(int dx, int dy) => dx.abs() > search || dy.abs() > search
        ? double.infinity
        : cost(dx, dy, double.infinity);
    return Pt(
      gx + bx + fraction(near(bx - 1, by), near(bx + 1, by)),
      gy + by + fraction(near(bx, by - 1), near(bx, by + 1)),
    );
  }
}

/// The movement of a flat sheet between two frames: shifted, turned, scaled
/// and a little sheared. `p -> (a p.x + b p.y + x, c p.x + d p.y + y)`.
class _Pose {
  const _Pose(this.a, this.b, this.c, this.d, this.x, this.y);

  static const still = _Pose(1, 0, 0, 1, 0, 0);

  final double a, b, c, d, x, y;

  Pt apply(Pt p) => Pt(a * p.x + b * p.y + x, c * p.x + d * p.y + y);

  Pt invert(Pt p) {
    final det = a * d - b * c;
    final u = p.x - x, v = p.y - y;
    return Pt((d * u - b * v) / det, (a * v - c * u) / det);
  }

  _Pose moved(Pt by) => _Pose(a, b, c, d, x + by.x, y + by.y);

  /// How unlike a plain shift it is (0 = only shifted).
  double get strain =>
      [(a - 1).abs(), b.abs(), c.abs(), (d - 1).abs()].reduce(math.max);

  /// The movement that takes [from] to [to], ignoring pairs that disagree
  /// with the rest by more than about [tolerance]. Null when too few agree.
  /// [share] is the part that did.
  static ({_Pose pose, double share})? fit(
    List<Pt> from,
    List<Pt> to,
    double tolerance,
  ) {
    final n = from.length;
    if (n < 4) return null;
    double median(List<double> v) => (v..sort())[v.length ~/ 2];
    final mx = median([for (var i = 0; i < n; i++) to[i].x - from[i].x]);
    final my = median([for (var i = 0; i < n; i++) to[i].y - from[i].y]);
    var pose = _Pose(1, 0, 0, 1, mx, my);
    var kept = <int>[];
    // Start generous (the sheet may have turned), then tighten.
    for (final loose in const [6.0, 3.0, 1.6, 1.0]) {
      kept = [
        for (var i = 0; i < n; i++)
          if (pose.apply(from[i]).distanceTo(to[i]) <= loose * tolerance) i,
      ];
      if (kept.length < 4) return null;
      pose = _solve(from, to, kept);
    }
    if (kept.length < 0.3 * n) return null;
    return (pose: pose, share: kept.length / n);
  }

  /// Least squares over [use]; a plain shift when the points are too few or
  /// too much in a line to say more.
  static _Pose _solve(List<Pt> from, List<Pt> to, List<int> use) {
    var fx = 0.0, fy = 0.0, tx = 0.0, ty = 0.0;
    for (final i in use) {
      fx += from[i].x;
      fy += from[i].y;
      tx += to[i].x;
      ty += to[i].y;
    }
    final n = use.length;
    fx /= n;
    fy /= n;
    tx /= n;
    ty /= n;
    var xx = 0.0, xy = 0.0, yy = 0.0;
    var xu = 0.0, yu = 0.0, xv = 0.0, yv = 0.0;
    for (final i in use) {
      final px = from[i].x - fx, py = from[i].y - fy;
      final u = to[i].x - tx, v = to[i].y - ty;
      xx += px * px;
      xy += px * py;
      yy += py * py;
      xu += px * u;
      yu += py * u;
      xv += px * v;
      yv += py * v;
    }
    final det = xx * yy - xy * xy;
    if (n < 6 || det <= 0.02 * xx * yy || det < 1) {
      return _Pose(1, 0, 0, 1, tx - fx, ty - fy);
    }
    final a = (xu * yy - yu * xy) / det, b = (yu * xx - xu * xy) / det;
    final c = (xv * yy - yv * xy) / det, d = (yv * xx - xv * xy) / det;
    return _Pose(a, b, c, d, tx - a * fx - b * fy, ty - c * fx - d * fy);
  }
}

/// A spot to follow: its pixel on the key frame's finer copy, and where that
/// is in the frame.
class _Spot {
  const _Spot(this.x, this.y, this.at);
  final int x;
  final int y;
  final Pt at;
}

class _Key {
  _Key(this.levels, this.corners, this.spots);
  final _Levels levels;
  final List<Pt> corners;

  /// Strongest first.
  final List<_Spot> spots;
}

/// Two small grey copies of a frame.
class _Levels {
  _Levels(this.fine, this.fineFactor, this.coarse, this.coarseFactor);

  factory _Levels.of(PixelSource frame) {
    final f = math.max(1, math.max(frame.width, frame.height) ~/ 480);
    final fine = frame.thumbnail(f);
    // Half again, from the small copy rather than the frame.
    final w = fine.width ~/ 2, h = fine.height ~/ 2;
    final half = Uint8List(w * h);
    final s = fine.data;
    for (var y = 0; y < h; y++) {
      final r = 2 * y * fine.width;
      for (var x = 0; x < w; x++) {
        final i = r + 2 * x;
        half[y * w + x] =
            (s[i] + s[i + 1] + s[i + fine.width] + s[i + fine.width + 1]) >> 2;
      }
    }
    return _Levels(fine, f, GrayImage(w, h, half), 2 * f);
  }

  final GrayImage fine;
  final int fineFactor;
  final GrayImage coarse;
  final int coarseFactor;

  late final _Summed fineSums = _Summed(fine);
  late final _Summed coarseSums = _Summed(coarse);

  bool fits(_Levels o) =>
      fine.width == o.fine.width && fine.height == o.fine.height;
}

/// A grey picture with its running sums, so that the mean of any patch costs
/// four look-ups.
class _Summed {
  _Summed(this.image)
    : sums = Int32List((image.width + 1) * (image.height + 1)) {
    final w = image.width, across = w + 1, d = image.data;
    for (var y = 0; y < image.height; y++) {
      var row = 0;
      for (var x = 0; x < w; x++) {
        row += d[y * w + x];
        sums[(y + 1) * across + x + 1] = sums[y * across + x + 1] + row;
      }
    }
  }

  final GrayImage image;
  final Int32List sums;
}
