import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_model_shapes.dart';

import 'tooth_dims.dart';
import 'vector_occlusal.dart';

/// What a hint line is drawn as.
enum GrooveKind {
  /// A carved developmental groove (dark taper with a light lip).
  groove,

  /// A soft light ridge (mamelon, buccal ridge).
  ridge,

  /// A very faint line down a root.
  rootLine,

  /// A tiny pit (the path is a single point).
  pit,
}

/// A hint line on a tooth, with a relative depth of 0 to 1.
class Groove {
  const Groove(this.path, this.weight, [this.kind = GrooveKind.groove]);
  final Path path;
  final double weight;
  final GrooveKind kind;

  Groove transformed(Float64List m) => Groove(path.transform(m), weight, kind);
}

// ============================================================ curve helpers

/// A smooth open or closed curve through [p] as cubic Béziers whose handles
/// follow the chord direction (no overshoot, no bumps).
Path vtSmooth(List<Offset> p, {bool closed = false, double tension = 1.0}) {
  final n = p.length;
  final path = Path()..moveTo(p[0].dx, p[0].dy);
  if (n == 2 && !closed) return path..lineTo(p[1].dx, p[1].dy);
  Offset dir(int i) {
    final a = closed ? p[(i - 1 + n) % n] : p[math.max(0, i - 1)];
    final b = closed ? p[(i + 1) % n] : p[math.min(n - 1, i + 1)];
    final d = b - a;
    final l = d.distance;
    return l == 0 ? Offset.zero : d / l;
  }

  final segs = closed ? n : n - 1;
  for (var i = 0; i < segs; i++) {
    final a = p[i];
    final b = p[(i + 1) % n];
    final len = (b - a).distance;
    final c1 = a + dir(i) * (len / 3 * tension);
    final c2 = b - dir((i + 1) % n) * (len / 3 * tension);
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, b.dx, b.dy);
  }
  if (closed) path.close();
  return path;
}

List<Offset> vtFlatten(Path path, {double step = 0.12}) {
  final out = <Offset>[];
  for (final m in path.computeMetrics()) {
    final n = math.max(2, (m.length / step).ceil());
    for (var i = 0; i <= n; i++) {
      out.add(m.getTangentForOffset(m.length * i / n)!.position);
    }
  }
  return out;
}

Float64List _mirrorX() => Float64List.fromList([-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

Offset _mx(Offset o) => Offset(-o.dx, o.dy);

// ================================================================== roots

class _Root {
  _Root({
    required this.top,
    required this.w0,
    required this.apex,
    required this.ctrl,
    this.rcap = 0.4,
    this.a = 1.5,
    this.b = 1.0,
    this.hold = 0.0,
    this.innerSide = 0,
  });
  final int innerSide;
  static const double innerK = 0.4;
  final Offset top;
  final double w0;
  final Offset apex;
  final Offset ctrl;
  final double rcap;
  final double a;
  final double b;
  final double hold;

  Offset c(double t) {
    final u = 1 - t;
    return top * (u * u) + ctrl * (2 * u * t) + apex * (t * t);
  }

  Offset tan(double t) {
    final d = (ctrl - top) * (2 * (1 - t)) + (apex - ctrl) * (2 * t);
    return d / d.distance;
  }

  double w(double t) {
    final tt = math.max(0.0, (t - hold) / (1 - hold));
    final prof = math.pow(1 - math.pow(tt, a), b).toDouble();
    return rcap + (w0 - rcap) * prof;
  }

  double _inner(double t, int side) {
    if (innerSide != side) return 1;
    final s = ((t - hold) / 0.35).clamp(0.0, 1.0);
    final e = s * s * (3 - 2 * s);
    return 1 - (1 - innerK) * e;
  }

  double _wSide(double t, int side) => rcap + (w(t) - rcap) * _inner(t, side);

  Offset right(double t) {
    final T = tan(t);
    return c(t) + Offset(T.dy, -T.dx) * _wSide(t, 1);
  }

  Offset left(double t) {
    final T = tan(t);
    return c(t) - Offset(T.dy, -T.dx) * _wSide(t, -1);
  }

  /// First t at which the centre line is at least [y].
  double tAtY(double y) {
    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 30; i++) {
      final m = (lo + hi) / 2;
      if (c(m).dy < y) {
        lo = m;
      } else {
        hi = m;
      }
    }
    return hi;
  }

  /// A closed, self-contained outline of the root (used for hidden roots).
  Path outline({double from = 0}) {
    final pts = <Offset>[];
    for (final t in _ts(from, 0.97)) {
      pts.add(right(t));
    }
    pts.addAll(_cap());
    for (final t in _ts(from, 0.97).reversed) {
      pts.add(left(t));
    }
    return vtSmooth(pts, closed: true);
  }

  /// A round tip whose arc meets the tapering edges tangentially.
  List<Offset> _cap() {
    final c1 = c(1);
    final T = tan(1);
    final N = Offset(T.dy, -T.dx);
    final len = (apex - top).distance;
    final slope = (w(0.97) - w(1.0)) / (0.03 * len);
    final th = math.atan(math.max(0.0, slope)) * 180 / math.pi;
    final span = 180 - 2 * th;
    return [
      for (var i = 0; i <= 4; i++)
        () {
          final deg = th + span * i / 4;
          final a = deg * math.pi / 180;
          return c1 + N * (rcap * math.cos(a)) + T * (rcap * math.sin(a));
        }(),
    ];
  }

  static List<double> _ts(double from, double to) {
    const all = [0.0, 0.1, 0.2, 0.32, 0.45, 0.58, 0.7, 0.8, 0.88, 0.93, 0.97];
    return [
      from,
      for (final t in all)
        if (t > from + 0.04 && t <= to) t,
    ];
  }

  List<Offset> rightDown(double from) => [
        for (final t in _ts(from, 0.97)) right(t),
      ];
  List<Offset> leftUp(double from) => [
        for (final t in _ts(from, 0.97).reversed) left(t),
      ];
  List<Offset> cap() => _cap();
}

// ============================================================ buccal view

/// The side (cheek or lip) view of one tooth, in mm.
///
/// Frame: x is across the tooth (the mesial side is +x for teeth of the
/// patient's right, mirrored for the left), y runs from the biting edge (0)
/// down to the apex. The CEJ is a per-tooth curve, never a straight line.
class VectorBuccal {
  const VectorBuccal({
    required this.crown,
    required this.outline,
    required this.roots,
    required this.rootPaths,
    required this.backRoot,
    required this.silhouette,
    required this.pulp,
    required this.canals,
    required this.neckLeft,
    required this.neckRight,
    required this.cej,
    required this.cejPoints,
    required this.grooves,
    required this.bounds,
    this.furcationY = -1,
  });

  /// Model y of the furcation arch top, or -1 for single-rooted teeth.
  final double furcationY;

  final Path crown;

  /// The tooth's front outline (crown, trunk and front roots) without the
  /// hidden back root.
  final Path outline;

  /// Every root below the CEJ merged into one path.
  final Path roots;

  /// Each root on its own (front roots; the hidden palatal root is
  /// [backRoot]).
  final List<Path> rootPaths;
  final Path? backRoot;
  final Path silhouette;
  final Path pulp;
  final List<List<Offset>> canals;
  final Offset neckLeft;
  final Offset neckRight;
  final Path cej;
  final List<Offset> cejPoints;
  final List<Groove> grooves;
  final Rect bounds;

  VectorBuccal mirrored() {
    final m = _mirrorX();
    Offset f(Offset o) => _mx(o);
    return VectorBuccal(
      crown: crown.transform(m),
      outline: outline.transform(m),
      roots: roots.transform(m),
      rootPaths: [for (final p in rootPaths) p.transform(m)],
      backRoot: backRoot?.transform(m),
      silhouette: silhouette.transform(m),
      pulp: pulp.transform(m),
      canals: [
        for (final c in canals) [for (final o in c) f(o)],
      ],
      neckLeft: f(neckRight),
      neckRight: f(neckLeft),
      cej: cej.transform(m),
      cejPoints: [for (final o in cejPoints.reversed) f(o)],
      grooves: [for (final g in grooves) g.transformed(m)],
      bounds: Rect.fromLTRB(-bounds.right, bounds.top, -bounds.left, bounds.bottom),
      furcationY: furcationY,
    );
  }
}

class _BuccalBuilder {
  _BuccalBuilder(this.d)
      : hw = d.crownW / 2,
        c = d.cervW / 2,
        H = d.crownH;

  final ToothDims d;
  final double hw;
  final double c;
  final double H;

  bool get anterior => d.kind.index <= ToothKind.canine.index;
  bool get molar => d.kind.index >= ToothKind.m1.index;

  /// y of the CEJ at u in [-1 (distal), +1 (mesial)] of the neck width.
  double cejY(double u) {
    final au = u.abs();
    final rise = (u >= 0 ? d.cejMesial : d.cejDistal) *
        math.pow(au, d.cejSharp).toDouble();
    final dip = d.cejDip * (1 - math.exp(-math.pow(u / 0.5, 2)));
    return H - rise - dip;
  }

  // ---- biting edge, from the mesial contact to the distal contact.
  List<Offset> top() {
    final s = H / 10.0;
    switch (d.kind) {
      case ToothKind.central:
      case ToothKind.lateral:
        {
          final low = !d.upper;
          final cm = low ? H * 0.065 : H * 0.11;
          final cd = low ? H * 0.11 : H * 0.21;
          final lat = d.kind == ToothKind.lateral ? 0.12 : 0.0;
          return [
            Offset(hw, cm),
            Offset(hw * 0.965, cm * 0.42),
            Offset(hw * 0.86, cm * 0.12),
            Offset(hw * 0.58, 0.0),
            Offset(hw * 0.2, 0.0),
            Offset(-hw * 0.2, 0.03 + lat * 0.3),
            Offset(-hw * 0.52, 0.12 + lat),
            Offset(-hw * 0.8, cd * 0.3 + lat),
            Offset(-hw * 0.95, cd * 0.62),
            Offset(-hw, cd),
          ];
        }
      case ToothKind.canine:
        return _dome(
          tipU: d.upper ? 0.1 : 0.14,
          cm: (d.upper ? 2.7 : 2.2) * s * (d.primary ? 1.1 : 1),
          cd: (d.upper ? 3.7 : 3.6) * s * (d.primary ? 1.1 : 1),
          p: 1.3,
        );
      case ToothKind.pm1:
        return _dome(
          tipU: d.upper ? 0.0 : 0.06,
          cm: d.upper ? 2.2 : 2.7,
          cd: d.upper ? 2.6 : 3.0,
          p: 1.55,
        );
      case ToothKind.pm2:
        return _dome(
          tipU: 0.0,
          cm: d.upper ? 2.0 : 2.3,
          cd: d.upper ? 2.4 : 2.7,
          p: 1.75,
        );
      case ToothKind.m1:
      case ToothKind.m2:
      case ToothKind.m3:
        return _molarTop();
    }
  }

  List<Offset> _dome({
    required double tipU,
    required double cm,
    required double cd,
    required double p,
  }) {
    const fs = [1.0, 0.8, 0.56, 0.34, 0.15];
    return [
      for (final f in fs)
        Offset(hw * (tipU + f * (1 - tipU)), cm * math.pow(f, p).toDouble()),
      Offset(hw * tipU, 0),
      for (final f in fs.reversed)
        Offset(hw * (tipU - f * (1 + tipU)), cd * math.pow(f, p).toDouble()),
    ];
  }

  late final _MolarCusps cusps = _molarCusps();

  _MolarCusps _molarCusps() {
    final k = H / 7.5;
    if (d.upper) {
      return _MolarCusps(
        [1, 0.05, -1],
        [0, d.kind == ToothKind.m1 ? 0.2 : 0.55],
        [0.7 * k],
        2.0 * k,
        2.4 * k,
      );
    }
    if (d.kind == ToothKind.m1 || (d.primary && d.kind == ToothKind.m2)) {
      return _MolarCusps(
        [1, 0.3, -0.32, -1],
        [0, 0.15, 0.5],
        [0.85 * k, 0.8 * k],
        1.9 * k,
        2.4 * k,
      );
    }
    if (d.primary) {
      return _MolarCusps([1, 0.1, -1], [0, 0.5], [0.9 * k], 1.8 * k, 2.4 * k);
    }
    return _MolarCusps(
      [1, 0.02, -1],
      [d.kind == ToothKind.m3 ? 0.1 : 0.0, d.kind == ToothKind.m3 ? 0.35 : 0.12],
      [0.9 * k],
      2.0 * k,
      2.5 * k,
    );
  }

  List<Offset> _molarTop() {
    final cs = cusps;
    final out = <Offset>[Offset(hw, cs.cm)];
    const ss = [-0.8, -0.52, -0.24, 0.0, 0.24, 0.52, 0.8];
    const pw = 2.3;
    for (var i = 0; i < cs.tips.length; i++) {
      final edgeM = i == 0 ? cs.cm : cs.notch[i - 1];
      final edgeD = i == cs.tips.length - 1 ? cs.cd : cs.notch[i];
      for (final s in ss) {
        final y = cs.tips[i] +
            ((s < 0 ? edgeM : edgeD) - cs.tips[i]) *
                math.pow(s.abs(), pw).toDouble();
        final u = cs.b[i] + (cs.b[i + 1] - cs.b[i]) * (s + 1) / 2;
        out.add(Offset(hw * u, y));
      }
      if (i < cs.tips.length - 1) {
        out.add(Offset(hw * cs.b[i + 1], cs.notch[i]));
      }
    }
    out.add(Offset(-hw, cs.cd));
    return out;
  }

  /// Crown side from just below the contact down to the neck (exclusive of
  /// the contact node). [sign] +1 mesial, -1 distal.
  List<Offset> side(int sign, Offset contact, double yN) {
    final e = d.primary ? 1.5 : 1.9;
    final w = contact.dx.abs();
    return [
      for (final s in const [0.3, 0.62, 1.0])
        Offset(
          sign * (c + (w - c) * (1 - math.pow(s, e).toDouble())),
          contact.dy + s * (yN - contact.dy),
        ),
    ];
  }

  VectorBuccal build() {
    final tp = top();
    final yM = cejY(1);
    final yD = cejY(-1);
    final mSide = side(1, tp.first, yM);
    final dSide = side(-1, tp.last, yD);

    // Roots.
    final front = <_Root>[];
    _Root? back;
    final R = d.rootLen;
    final rc = d.primary ? 0.3 : 0.34;
    if (d.roots == 1) {
      final fusedA = d.fused ? 1.7 : (d.kind == ToothKind.canine ? 1.6 : 1.4);
      final top = Offset(0, H);
      final apex = Offset(-d.curve, H + R);
      front.add(_Root(
        top: top,
        w0: c * (molar ? 1.0 : 0.96),
        apex: apex,
        ctrl: Offset(-d.curve * 0.08, H + 0.7 * R),
        rcap: d.fused ? 1.0 : (d.kind == ToothKind.canine ? 0.45 : rc),
        a: fusedA,
        hold: molar ? 0.15 : 0.0,
      ));
    } else {
      const inner0 = 0.15;
      final w0 = (c - inner0) / 2;
      final w0m = d.upper ? w0 * 1.18 : w0;
      final w0d = d.upper ? w0 * 0.88 : w0;
      final cxm = c - w0m;
      final cxd = c - w0d;
      final hold = (d.trunk / R) * (d.upper ? 0.4 : 0.85);
      final fm = d.upper ? 0.8 : 0.7;
      final fd = d.upper ? 0.9 : 1.0;
      final ax1 = cxm + d.spread - d.curve * fm;
      final ax2 = -cxd - d.spread - d.curve * fd;
      final r2 = R - (d.upper ? 0.7 : 0.9);
      final ta = d.upper ? 1.25 : 1.55;
      Offset ctrl(double x0, double ax, double len) =>
          Offset(x0 + (ax - x0) * 0.25, H + 0.62 * len);
      front.add(_Root(
        top: Offset(cxm, H),
        w0: w0m,
        apex: Offset(ax1, H + R),
        ctrl: ctrl(cxm, ax1, R),
        rcap: 0.6,
        a: ta,
        b: 1.0,
        hold: hold,
        innerSide: -1,
      ));
      front.add(_Root(
        top: Offset(-cxd, H),
        w0: w0d,
        apex: Offset(ax2, H + r2),
        ctrl: ctrl(-cxd, ax2, r2),
        rcap: 0.55,
        a: ta,
        b: 1.0,
        hold: hold,
        innerSide: 1,
      ));
      if (d.roots == 3) {
        final pa = Offset(0.3 - d.curve * 0.3, H + R + 0.9);
        back = _Root(
          top: Offset(0.1, H + 0.5),
          w0: c * 0.62,
          apex: pa,
          ctrl: Offset(0.15, H + 0.55 * (R + 0.9)),
          rcap: 0.85,
          a: 2.2,
          b: 0.9,
          hold: 0.15,
        );
      }
    }

    // Silhouette outline, clockwise from the mesial contact.
    final pts = <Offset>[tp.first, ...mSide];
    final furcY = H + d.trunk;
    final archH = d.primary ? 1.2 : 1.6;
    final gapMin = d.cervW * 0.26;
    double archT(_Root a, _Root b) {
      var t = a.tAtY(furcY + archH);
      while (t < 0.9 && a.left(t).dx - b.right(t).dx < gapMin) {
        t += 0.01;
      }
      return t;
    }

    for (var i = 0; i < front.length; i++) {
      final r = front[i];
      final firstInner = i > 0;
      final lastInner = i < front.length - 1;
      final from = firstInner ? archT(front[i - 1], r) : 0.0;
      pts.addAll(r.rightDown(from));
      pts.addAll(r.cap());
      final upFrom = lastInner ? archT(r, front[i + 1]) : 0.0;
      pts.addAll(r.leftUp(upFrom));
      if (lastInner) {
        final p1 = r.left(upFrom);
        final p2 = front[i + 1].right(upFrom);
        final g = p1.dx - p2.dx;
        final xm = (p1.dx + p2.dx) / 2;
        final yb = (p1.dy + p2.dy) / 2;
        final h = math.min(g * 0.7, yb - (furcY - 0.3));
        for (final deg in const [35.0, 90.0, 145.0]) {
          final a = deg * math.pi / 180;
          pts.add(Offset(xm + g / 2 * math.cos(a), yb - h * math.sin(a)));
        }
      }
    }
    pts.addAll(dSide.reversed);
    pts.addAll(tp.reversed.skip(1).take(tp.length - 2));
    final outline = vtSmooth(pts, closed: true);

    // CEJ.
    final cejPts = [
      for (var i = 0; i <= 12; i++)
        () {
          final u = 1 - i / 6;
          return Offset(c * u, cejY(u));
        }(),
    ];
    final cej = vtSmooth(cejPts);
    final aboveClean = Path()
      ..moveTo(-40, -40)
      ..lineTo(40, -40)
      ..lineTo(40, yM)
      ..lineTo(c, yM);
    aboveClean.extendWithPath(cej, Offset.zero);
    aboveClean
      ..lineTo(-40, yD)
      ..close();

    final backPath = back?.outline(from: 0.0);
    final crown = Path.combine(PathOperation.intersect, outline, aboveClean);
    final rootsFront = Path.combine(PathOperation.difference, outline, aboveClean);
    final rootsAll = backPath == null
        ? rootsFront
        : Path.combine(PathOperation.union, rootsFront, backPath);
    final sil = backPath == null
        ? outline
        : Path.combine(PathOperation.union, outline, backPath);

    final rootPaths = <Path>[];
    for (var i = 0; i < front.length; i++) {
      rootPaths.add(front[i].outline());
    }

    // Pulp chamber and canals.
    final canals = <List<Offset>>[];
    final pulp = _pulp(front, canals);

    // Hint lines.
    final grooves = _grooves(front);

    final b = sil.getBounds();
    return VectorBuccal(
      crown: crown,
      outline: outline,
      roots: rootsAll,
      rootPaths: rootPaths,
      backRoot: backPath,
      silhouette: sil,
      pulp: pulp,
      canals: canals,
      neckLeft: Offset(-c, yD),
      neckRight: Offset(c, yM),
      cej: cej,
      cejPoints: cejPts,
      grooves: grooves,
      bounds: b,
      furcationY: front.length > 1 ? furcY - 0.3 : -1,
    );
  }

  Path _pulp(List<_Root> front, List<List<Offset>> canals) {
    if (!molar) {
      final r = front.first;
      final q = d.cervW * 0.17;
      final top = H * (anterior ? 0.26 : 0.34);
      Offset cl(double t, double wv) => r.c(t);
      final ts = [0.08, 0.22, 0.4, 0.58, 0.74, 0.86];
      final axis = [for (final t in ts) r.c(t)];
      canals.add([Offset(0, H * 0.7), Offset(0, H), ...axis]);
      final rightPts = <Offset>[
        Offset(0, top),
        Offset(q * 0.55, top + (H * 0.7 - top) * 0.3),
        Offset(q, top + (H * 0.7 - top) * 0.72),
        Offset(q * 0.75, H * 0.97),
        for (var i = 0; i < ts.length; i++)
          axis[i] + Offset(math.max(0.12, 0.42 * (1 - ts[i]) * (c / 3.5).clamp(0.5, 1.2)), 0),
      ];
      final leftPts = <Offset>[
        for (var i = ts.length - 1; i >= 0; i--)
          axis[i] - Offset(math.max(0.12, 0.42 * (1 - ts[i]) * (c / 3.5).clamp(0.5, 1.2)), 0),
        Offset(-q * 0.75, H * 0.97),
        Offset(-q, top + (H * 0.7 - top) * 0.72),
        Offset(-q * 0.55, top + (H * 0.7 - top) * 0.3),
      ];
      final tipPt = r.c(0.93);
      // ignore: unused_local_variable
      final _ = cl;
      return vtSmooth([...rightPts, tipPt, ...leftPts], closed: true);
    }
    // Molar: a chamber with horns plus a canal per root.
    final k = c / 4.0;
    final hornY = H * 0.3;
    final floorY = H + 0.7;
    final chamber = vtSmooth([
      Offset(c * 0.62, hornY + 0.2),
      Offset(c * 0.7, H * 0.62),
      Offset(c * 0.62, floorY),
      Offset(0, floorY + 0.15),
      Offset(-c * 0.62, floorY),
      Offset(-c * 0.7, H * 0.62),
      Offset(-c * 0.62, hornY + 0.2),
      Offset(-c * 0.3, hornY + 0.7),
      Offset(0, hornY + 0.9),
      Offset(c * 0.3, hornY + 0.7),
    ], closed: true);
    // ignore: unused_local_variable
    final _ = k;
    for (final r in front) {
      canals.add([
        Offset(r.top.dx * 0.9, floorY),
        for (final t in const [0.25, 0.45, 0.65, 0.84]) r.c(t),
      ]);
    }
    return chamber;
  }

  List<Groove> _grooves(List<_Root> front) {
    final g = <Groove>[];
    Path line(List<Offset> p) => vtSmooth(p);
    if (d.kind == ToothKind.central || d.kind == ToothKind.lateral) {
      for (final sgn in const [-1, 1]) {
        g.add(Groove(
          line([
            Offset(sgn * hw * 0.3, 0.5),
            Offset(sgn * hw * 0.3, H * 0.28),
            Offset(sgn * hw * 0.36, H * 0.46),
          ]),
          d.upper ? 0.3 : 0.18,
          GrooveKind.ridge,
        ));
      }
    }
    if (d.kind == ToothKind.canine ||
        d.kind == ToothKind.pm1 ||
        d.kind == ToothKind.pm2) {
      final tip = top().reduce((a, b) => a.dy < b.dy ? a : b).dx;
      g.add(Groove(
        line([
          Offset(tip, 1.0),
          Offset(tip, H * 0.5),
          Offset(tip * 0.9, H * 0.78),
        ]),
        0.4,
        GrooveKind.ridge,
      ));
    }
    if (molar) {
      final cs = cusps;
      final gEnd = H * (d.upper ? 0.5 : 0.58);
      for (var i = 0; i < cs.notch.length; i++) {
        final u = hw * cs.b[i + 1];
        g.add(Groove(
          line([
            Offset(u, cs.notch[i]),
            Offset(u + 0.02, cs.notch[i] + (gEnd - cs.notch[i]) * 0.5),
            Offset(u * 0.92, gEnd),
          ]),
          0.7 - i * 0.12,
        ));
      }
    }
    for (final r in front) {
      if (!molar || d.fused) {
        g.add(Groove(
          line([for (final t in const [0.1, 0.3, 0.5, 0.68]) r.c(t)]),
          0.18,
          GrooveKind.rootLine,
        ));
      }
    }
    return g;
  }
}

class _MolarCusps {
  _MolarCusps(this.b, this.tips, this.notch, this.cm, this.cd);
  final List<double> b;
  final List<double> tips;
  final List<double> notch;
  final double cm;
  final double cd;
}

// ============================================================ the tooth

/// One tooth, drawn from its dimensions.
class VectorTooth {
  VectorTooth._(this.fdi, this.dims, this.buccal, this.occlusal);

  final int fdi;
  final ToothDims dims;
  final VectorBuccal buccal;
  final VectorOcclusal occlusal;

  bool get upper => dims.upper;
  bool get primary => dims.primary;

  static final Map<int, VectorTooth> _cache = {};

  /// Builds (and caches) the tooth for an FDI number 11-48 or 51-85.
  static VectorTooth of(int fdi) => _cache.putIfAbsent(fdi, () {
        final d = ToothDims.of(fdi);
        var b = _BuccalBuilder(d).build();
        var o = VectorOcclusal.build(d);
        if (ToothDims.isLeft(fdi)) {
          b = b.mirrored();
          o = o.mirrored();
        }
        return VectorTooth._(fdi, d, b, o);
      });

  /// Every tooth in the chart, 11-48 then 51-85.
  static final allFdi = [
    for (final q in [1, 2, 3, 4])
      for (final n in [1, 2, 3, 4, 5, 6, 7, 8]) q * 10 + n,
    for (final q in [5, 6, 7, 8])
      for (final n in [1, 2, 3, 4, 5]) q * 10 + n,
  ];

  /// The same data in the shape the existing finding marks use.
  ToothModelShape toModelShape() {
    final b = buccal;
    final o = occlusal.outline.getBounds();
    return ToothModelShape(
      fdi: fdi,
      buccalCrown: vtFlatten(b.crown),
      buccalRoots: vtFlatten(b.roots),
      buccalPulp: vtFlatten(b.pulp),
      buccalNeckLeft: b.neckLeft,
      buccalNeckRight: b.neckRight,
      buccalCanals: b.canals,
      buccalImageBox: b.bounds,
      occlusalOutline: vtFlatten(occlusal.outline),
      occlusalImageBox: o,
    );
  }
}
