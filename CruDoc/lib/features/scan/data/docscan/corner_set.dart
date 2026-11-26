import 'dart:math' as math;

import 'geometry.dart';

/// The four corners while the person is placing them by hand, in the
/// picture's pixels and in tl, tr, br, bl order. [pinned] marks the ones
/// they have set themselves.
class CornerSet {
  const CornerSet(
    this.points, [
    this.pinned = const [false, false, false, false],
  ]);

  factory CornerSet.of(Quad q) => CornerSet(q.corners);

  final List<Pt> points;
  final List<bool> pinned;

  Quad get quad => Quad(points[0], points[1], points[2], points[3]);

  /// A shape a page can be straightened from: convex, the right way round
  /// (not mirrored) and not collapsed.
  bool get valid => _valid(points);

  static bool _valid(List<Pt> p) {
    final q = Quad(p[0], p[1], p[2], p[3]);
    if (!q.isConvex || q.area < 64) return false;
    var twice = 0.0;
    for (var i = 0; i < 4; i++) {
      twice += p[i].cross(p[(i + 1) % 4]);
    }
    return twice > 0; // clockwise on screen, where y grows downwards
  }

  /// The corner closest to [at], if any is within [within].
  int? nearest(Pt at, {double within = double.infinity}) {
    int? best;
    var bestDistance = within;
    for (var i = 0; i < 4; i++) {
      final d = points[i].distanceTo(at);
      if (d <= bestDistance) {
        best = i;
        bestDistance = d;
      }
    }
    return best;
  }

  /// Corner [i] at [to]. The order is left alone, so a drag keeps hold of
  /// the same corner even while the shape is briefly crossed.
  CornerSet move(int i, Pt to) => CornerSet(
    [for (var k = 0; k < 4; k++) k == i ? to : points[k]],
    [for (var k = 0; k < 4; k++) k == i || pinned[k]],
  );

  /// Which corner a press at [at] means: the nearest one that leaves a
  /// sensible shape when moved there, preferring corners not yet set by
  /// hand. Failing any, simply the nearest.
  int indexFor(Pt at) {
    int? best;
    var bestCost = double.infinity;
    for (var i = 0; i < 4; i++) {
      if (!move(i, at).valid) continue;
      final cost = points[i].distanceTo(at) * (pinned[i] ? 2.5 : 1);
      if (cost < bestCost) {
        best = i;
        bestCost = cost;
      }
    }
    return best ?? nearest(at)!;
  }

  /// Makes [at] one of the corners (see [indexFor]), re-ordering them when
  /// that crosses the shape. Returns the new set and which corner [at]
  /// became.
  (CornerSet, int) place(Pt at) {
    final i = indexFor(at);
    final moved = move(i, at);
    if (moved.valid) return (moved, i);
    final sorted = moved.untangled();
    final index = sorted.points.indexWhere((p) => identical(p, at));
    return (sorted, math.max(0, index));
  }

  /// Corners re-ordered into a proper page shape when they have crossed.
  /// Unchanged when already fine, or when no order would help.
  CornerSet untangled() {
    if (valid) return this;
    final ordered = Quad.ordered(points).corners;
    if (!_valid(ordered)) return this;
    return CornerSet(ordered, [
      for (final p in ordered)
        pinned[points.indexWhere((o) => identical(o, p))],
    ]);
  }

  CornerSet scale(double sx, double sy) =>
      CornerSet([for (final p in points) Pt(p.x * sx, p.y * sy)], pinned);
}
