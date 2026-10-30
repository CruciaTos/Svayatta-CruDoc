import 'dart:math' as math;

/// A point in image pixels. Pixel `i` covers `[i, i + 1)`, so its centre is
/// at `i + 0.5`.
class Pt {
  const Pt(this.x, this.y);

  final double x;
  final double y;

  Pt operator +(Pt o) => Pt(x + o.x, y + o.y);
  Pt operator -(Pt o) => Pt(x - o.x, y - o.y);
  Pt operator *(double k) => Pt(x * k, y * k);

  double dot(Pt o) => x * o.x + y * o.y;
  double cross(Pt o) => x * o.y - y * o.x;
  double get length => math.sqrt(x * x + y * y);
  double distanceTo(Pt o) => (this - o).length;

  Pt get unit {
    final l = length;
    return l == 0 ? const Pt(0, 0) : Pt(x / l, y / l);
  }

  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

/// An infinite line through [point] along the unit vector [dir].
class Line2 {
  const Line2(this.point, this.dir);

  final Pt point;
  final Pt dir;

  Pt get normal => Pt(-dir.y, dir.x);

  double distanceTo(Pt p) => (p - point).cross(dir).abs();

  /// The same line moved by [d] along [normal].
  Line2 shifted(double d) => Line2(point + normal * d, dir);

  /// Where this line crosses [o]; null when they are (nearly) parallel.
  Pt? intersect(Line2 o) {
    final denom = dir.cross(o.dir);
    if (denom.abs() < 1e-9) return null;
    final t = (o.point - point).cross(o.dir) / denom;
    return point + dir * t;
  }

  /// Least-squares fit (principal axis) through [pts].
  static Line2? fit(List<Pt> pts) {
    if (pts.length < 2) return null;
    var cx = 0.0, cy = 0.0;
    for (final p in pts) {
      cx += p.x;
      cy += p.y;
    }
    cx /= pts.length;
    cy /= pts.length;
    var sxx = 0.0, syy = 0.0, sxy = 0.0;
    for (final p in pts) {
      final dx = p.x - cx, dy = p.y - cy;
      sxx += dx * dx;
      syy += dy * dy;
      sxy += dx * dy;
    }
    final angle = 0.5 * math.atan2(2 * sxy, sxx - syy);
    return Line2(Pt(cx, cy), Pt(math.cos(angle), math.sin(angle)));
  }
}

/// Four corners in clockwise order on screen (y grows downwards):
/// top-left, top-right, bottom-right, bottom-left.
class Quad {
  const Quad(this.tl, this.tr, this.br, this.bl);

  final Pt tl;
  final Pt tr;
  final Pt br;
  final Pt bl;

  /// Orders any four points around their centre, starting from the corner
  /// whose outgoing edge is closest to horizontal-and-rightward, so a page
  /// held roughly upright keeps its top edge on top.
  factory Quad.ordered(List<Pt> pts) {
    assert(pts.length == 4);
    final c = Pt(
      (pts[0].x + pts[1].x + pts[2].x + pts[3].x) / 4,
      (pts[0].y + pts[1].y + pts[2].y + pts[3].y) / 4,
    );
    final sorted = [...pts]
      ..sort(
        (a, b) => math
            .atan2(a.y - c.y, a.x - c.x)
            .compareTo(math.atan2(b.y - c.y, b.x - c.x)),
      );
    var start = 0;
    var bestScore = double.infinity;
    for (var i = 0; i < 4; i++) {
      final a = sorted[i], b = sorted[(i + 1) % 4];
      // The top edge runs left to right and sits above the centre.
      final edgeAngle = math.atan2(b.y - a.y, b.x - a.x).abs();
      final mid = (a + b) * 0.5;
      final score = edgeAngle + (mid.y > c.y ? math.pi : 0);
      if (score < bestScore) {
        bestScore = score;
        start = i;
      }
    }
    return Quad(
      sorted[start],
      sorted[(start + 1) % 4],
      sorted[(start + 2) % 4],
      sorted[(start + 3) % 4],
    );
  }

  /// From `[x0, y0, x1, y1, ...]` in tl, tr, br, bl order.
  factory Quad.fromList(List<double> v) =>
      Quad(Pt(v[0], v[1]), Pt(v[2], v[3]), Pt(v[4], v[5]), Pt(v[6], v[7]));

  List<Pt> get corners => [tl, tr, br, bl];

  List<double> toList() => [tl.x, tl.y, tr.x, tr.y, br.x, br.y, bl.x, bl.y];

  Pt get centroid =>
      Pt((tl.x + tr.x + br.x + bl.x) / 4, (tl.y + tr.y + br.y + bl.y) / 4);

  /// Top, right, bottom, left.
  List<double> get sideLengths => [
    tl.distanceTo(tr),
    tr.distanceTo(br),
    br.distanceTo(bl),
    bl.distanceTo(tl),
  ];

  double get area {
    final c = corners;
    var s = 0.0;
    for (var i = 0; i < 4; i++) {
      s += c[i].cross(c[(i + 1) % 4]);
    }
    return s.abs() / 2;
  }

  /// Strictly convex with every turn the same way.
  bool get isConvex {
    final c = corners;
    var sign = 0;
    for (var i = 0; i < 4; i++) {
      final a = c[i], b = c[(i + 1) % 4], d = c[(i + 2) % 4];
      final z = (b - a).cross(d - b);
      if (z.abs() < 1e-6) return false;
      final s = z > 0 ? 1 : -1;
      if (sign == 0) {
        sign = s;
      } else if (s != sign) {
        return false;
      }
    }
    return true;
  }

  /// Interior angle at each corner, in degrees.
  List<double> get interiorAngles {
    final c = corners;
    return [
      for (var i = 0; i < 4; i++)
        _angleDeg(c[(i + 3) % 4] - c[i], c[(i + 1) % 4] - c[i]),
    ];
  }

  /// The largest distance between matching corners.
  double maxCornerDistance(Quad o) {
    final a = corners, b = o.corners;
    var m = 0.0;
    for (var i = 0; i < 4; i++) {
      m = math.max(m, a[i].distanceTo(b[i]));
    }
    return m;
  }

  Quad scale(double sx, [double? sy]) {
    final ky = sy ?? sx;
    return Quad(
      Pt(tl.x * sx, tl.y * ky),
      Pt(tr.x * sx, tr.y * ky),
      Pt(br.x * sx, br.y * ky),
      Pt(bl.x * sx, bl.y * ky),
    );
  }

  Quad lerp(Quad o, double t) {
    Pt l(Pt a, Pt b) => a + (b - a) * t;
    return Quad(l(tl, o.tl), l(tr, o.tr), l(br, o.br), l(bl, o.bl));
  }

  bool insideRect(double w, double h, {double tolerance = 0}) => corners.every(
    (p) =>
        p.x >= -tolerance &&
        p.y >= -tolerance &&
        p.x <= w + tolerance &&
        p.y <= h + tolerance,
  );

  /// A point inside the quad: (u, v) in [0, 1]² blended between the corners
  /// (good enough for sampling; [Homography] for exact mapping).
  Pt blend(double u, double v) =>
      tl * ((1 - u) * (1 - v)) +
      tr * (u * (1 - v)) +
      br * (u * v) +
      bl * ((1 - u) * v);

  /// Each side moved outward by [margin] pixels.
  Quad expanded(double margin) {
    final c = corners;
    final centre = centroid;
    final lines = <Line2>[];
    for (var i = 0; i < 4; i++) {
      final a = c[i], b = c[(i + 1) % 4];
      var line = Line2(a, (b - a).unit);
      // Make the normal point outward.
      if (line.normal.dot(centre - a) > 0) line = Line2(a, (a - b).unit);
      lines.add(line.shifted(margin));
    }
    final out = <Pt>[];
    for (var i = 0; i < 4; i++) {
      final p = lines[(i + 3) % 4].intersect(lines[i]);
      if (p == null) return this;
      out.add(p);
    }
    return Quad(out[0], out[1], out[2], out[3]);
  }

  /// Median of each corner across [quads]: a robust consensus.
  static Quad median(List<Quad> quads) {
    double med(List<double> v) {
      v.sort();
      final n = v.length;
      return n.isOdd ? v[n ~/ 2] : (v[n ~/ 2 - 1] + v[n ~/ 2]) / 2;
    }

    final lists = quads.map((q) => q.toList()).toList();
    return Quad.fromList([
      for (var k = 0; k < 8; k++) med([for (final l in lists) l[k]]),
    ]);
  }

  @override
  String toString() => 'Quad($tl, $tr, $br, $bl)';
}

double _angleDeg(Pt a, Pt b) {
  final la = a.length, lb = b.length;
  if (la == 0 || lb == 0) return 0;
  final c = (a.dot(b) / (la * lb)).clamp(-1.0, 1.0);
  return math.acos(c) * 180 / math.pi;
}

/// A projective map between two planes: straightens a photographed page
/// exactly, where a corner-blend would bend lines of text.
class Homography {
  Homography._(this._m);

  final List<double> _m;

  /// Maps each `src[i]` onto `dst[i]`.
  static Homography? fromPoints(List<Pt> src, List<Pt> dst) {
    final a = List.generate(8, (_) => List<double>.filled(9, 0));
    for (var i = 0; i < 4; i++) {
      final x = src[i].x, y = src[i].y, u = dst[i].x, v = dst[i].y;
      a[2 * i]
        ..[0] = x
        ..[1] = y
        ..[2] = 1
        ..[6] = -u * x
        ..[7] = -u * y
        ..[8] = u;
      a[2 * i + 1]
        ..[3] = x
        ..[4] = y
        ..[5] = 1
        ..[6] = -v * x
        ..[7] = -v * y
        ..[8] = v;
    }
    // Gaussian elimination with partial pivoting.
    for (var col = 0; col < 8; col++) {
      var pivot = col;
      for (var r = col + 1; r < 8; r++) {
        if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
      }
      if (a[pivot][col].abs() < 1e-12) return null;
      final tmp = a[col];
      a[col] = a[pivot];
      a[pivot] = tmp;
      for (var r = 0; r < 8; r++) {
        if (r == col) continue;
        final f = a[r][col] / a[col][col];
        if (f == 0) continue;
        for (var k = col; k < 9; k++) {
          a[r][k] -= f * a[col][k];
        }
      }
    }
    return Homography._([for (var i = 0; i < 8; i++) a[i][8] / a[i][i], 1.0]);
  }

  Pt apply(double x, double y) {
    final m = _m;
    final w = m[6] * x + m[7] * y + m[8];
    return Pt(
      (m[0] * x + m[1] * y + m[2]) / w,
      (m[3] * x + m[4] * y + m[5]) / w,
    );
  }

  List<double> get matrix => List.unmodifiable(_m);
}
