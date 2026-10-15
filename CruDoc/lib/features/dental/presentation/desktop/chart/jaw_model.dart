import 'dart:math' as math;
import 'dart:typed_data';

import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_anatomy.dart';

/// A small 3D vector for building the jaw model.
class V3 {
  const V3(this.x, this.y, this.z);
  final double x, y, z;

  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double k) => V3(x * k, y * k, z * k);
  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);
  V3 get unit {
    final l = length;
    return l == 0 ? this : V3(x / l, y / l, z / l);
  }
}

enum MeshMaterial { crown, root, implant, bone }

/// One drawable piece: a tooth's crown, its roots or implant, or a jaw
/// bone.
class MeshPart {
  MeshPart({
    required this.positions,
    required this.normals,
    required this.triangles,
    required this.material,
    required this.lower,
    this.tooth,
    this.occlusion,
    this.fade,
    this.neck,
  });

  /// x, y, z per vertex (millimetres, model space).
  final Float64List positions;
  final Float64List normals;

  /// Three vertex indices per triangle, wound outward.
  final Int32List triangles;
  final MeshMaterial material;

  /// Part of the lower jaw (moves when the mouth opens).
  final bool lower;

  /// FDI number; null for bone.
  final String? tooth;

  /// How open each vertex is to the light: 1, less in the grooves of
  /// the biting surface and where neighbouring teeth touch.
  final Float32List? occlusion;

  /// How much of the bone shows at each vertex; it fades out where the
  /// model stops (above the upper jaw, the edges of the palate).
  final Float32List? fade;

  /// Roots: 1 down to 2 mm below the neck, 0 from 5 mm. That's where the
  /// bone fades in over the root, so the root takes on its colour
  /// there.
  final Float32List? neck;

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => triangles.length ~/ 3;
}

/// Where a tooth sits: its biting-edge centre, the long axis (towards the
/// root), and the buccal (outward) and mesiodistal directions.
class ToothFrame {
  const ToothFrame({
    required this.spec,
    required this.base,
    required this.axis,
    required this.outward,
    required this.tangent,
    required this.mesial,
  });

  final ToothSpec spec;
  final V3 base;
  final V3 axis;
  final V3 outward;
  final V3 tangent;

  /// Along the arch towards the midline ([tangent] or its opposite).
  final V3 mesial;

  /// A point on the crown's outer face, where a callout points.
  V3 get anchor =>
      base + axis * (spec.crown * 0.35) + outward * (spec.bl * 0.52);

  ToothFrame _moved(V3 by) => ToothFrame(
    spec: spec,
    base: base - by,
    axis: axis,
    outward: outward,
    tangent: tangent,
    mesial: mesial,
  );
}

/// Both jaws as meshes, centred on the teeth: crowns shaped tooth by
/// tooth (cusps, ridges, the curved neck line), their roots, and the
/// upper and lower jaw bones they sit in.
class JawModel {
  JawModel._(this.parts, this.frames, this.hingeY, this.hingeZ)
    : triangleCount = parts.fold(0, (n, p) => n + p.triangleCount),
      maxVertices = parts.fold(0, (n, p) => math.max(n, p.vertexCount)),
      teeth = frames.keys.toList() {
    toothIds = {for (var i = 0; i < teeth.length; i++) teeth[i]: i};
  }

  final List<MeshPart> parts;
  final Map<String, ToothFrame> frames;

  /// The axis the lower jaw turns on when the mouth opens.
  final double hingeY;
  final double hingeZ;

  /// Sizes for the renderer's buffers.
  final int triangleCount;
  final int maxVertices;

  /// Every tooth, and its index in [teeth].
  final List<String> teeth;
  late final Map<String, int> toothIds;

  static final Map<bool, JawModel> _cache = {};

  static JawModel of({required bool child}) =>
      _cache.putIfAbsent(child, () => _build(child));

  static const double _gapHalf = 0.5;

  /// How far a tooth's crown tips towards the lip or cheek.
  static double _lean(ToothSpec spec) => switch (spec.kind) {
    ToothKind.centralIncisor ||
    ToothKind.lateralIncisor => spec.upper ? 0.3 : 0.16,
    ToothKind.canine => 0.14,
    ToothKind.premolar => 0.05,
    ToothKind.molar => -0.04,
  };

  static JawModel _build(bool child) {
    final (upperRow, lowerRow) = ToothSpec.arches(child: child);
    final scale = child ? 0.78 : 1.0;
    final upperArch = _Arch(31 * scale, 40 * scale);
    final lowerArch = _Arch(28.5 * scale, 37 * scale);
    final frames = <String, ToothFrame>{};
    final parts = <MeshPart>[];

    // Place each side from the midline outwards.
    List<(ToothSpec, double)> placeSide(List<String> side) {
      var s = 0.0;
      final out = <(ToothSpec, double)>[];
      for (final n in side) {
        final spec = ToothSpec.of(n);
        out.add((spec, s + spec.md / 2));
        s += spec.md + 0.25;
      }
      return out;
    }

    _Row placeArch(List<String> row, _Arch arch, bool upper) {
      final half = row.length ~/ 2;
      // The row runs patient's right (left of screen) to patient's left.
      final right = row.sublist(0, half).reversed.toList();
      final left = row.sublist(half);
      final placed = <(ToothSpec, double)>[
        for (final (spec, s) in placeSide(right)) (spec, -s),
        for (final (spec, s) in placeSide(left)) (spec, s),
      ];
      for (final (spec, s) in placed) {
        final p = arch.point(s);
        final t = arch.tangent(s);
        final outward = V3(-t.z, 0, t.x);
        final vertical = V3(0, upper ? 1 : -1, 0);
        final axis = (vertical - outward * _lean(spec)).unit;
        final out2 = (outward - axis * outward.dot(axis)).unit;
        final tangent = axis.cross(out2).unit;
        final frame = ToothFrame(
          spec: spec,
          base: V3(p.x, upper ? _gapHalf : -_gapHalf, p.z),
          axis: axis,
          outward: out2,
          tangent: tangent,
          // The arch runs to the patient's left, so the midline is
          // behind it on that side and ahead of it on the right.
          mesial: tangent * (tangent.dot(t) * s > 0 ? -1 : 1),
        );
        frames[spec.number] = frame;
        parts.addAll(_tooth(frame, lower: !upper));
      }
      return _Row(placed);
    }

    final upper = placeArch(upperRow, upperArch, true);
    final lower = placeArch(lowerRow, lowerArch, false);

    // Centre the model on the teeth.
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    var minZ = double.infinity, maxZ = -double.infinity;
    for (final part in parts) {
      final p = part.positions;
      for (var i = 0; i < p.length; i += 3) {
        minX = math.min(minX, p[i]);
        maxX = math.max(maxX, p[i]);
        minY = math.min(minY, p[i + 1]);
        maxY = math.max(maxY, p[i + 1]);
        minZ = math.min(minZ, p[i + 2]);
        maxZ = math.max(maxZ, p[i + 2]);
      }
    }
    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;
    final cz = (minZ + maxZ) / 2;

    // The bones the teeth sit in.
    parts
      ..add(_maxilla(upperArch, upper, scale))
      ..add(_palate(upperArch, upper, scale))
      ..add(_mandible(lowerArch, lower, scale, child: child));

    for (final part in parts) {
      final p = part.positions;
      for (var i = 0; i < p.length; i += 3) {
        p[i] -= cx;
        p[i + 1] -= cy;
        p[i + 2] -= cz;
      }
    }
    final shift = V3(cx, cy, cz);
    final centred = {
      for (final e in frames.entries) e.key: e.value._moved(shift),
    };
    return JawModel._(parts, centred, 3 - cy, minZ - 16 - cz);
  }

  // --------------------------------------------------------------- teeth

  /// A tooth's crown, root and implant. The crown and root are one
  /// surface (smooth across the neck) split in two so the root can be
  /// left out; the implant closes the crown and replaces the root.
  static List<MeshPart> _tooth(ToothFrame f, {required bool lower}) {
    final s = f.spec;
    final r = _Recipe.of(s);
    final n = r.segs;
    final a = s.md / 2, b = s.bl / 2;
    final right = f.mesial.cross(f.outward).dot(f.axis) > 0;
    final mb = _MeshBuilder(right: right);

    // Round the outline: superellipse directions, and cos θ (1 at the
    // mesial side, -1 distal) for the neck line.
    final um = Float64List(n), ub = Float64List(n), cs = Float64List(n);
    final e = 2 / r.exp;
    for (var j = 0; j < n; j++) {
      final th = 2 * math.pi * j / n;
      final c = math.cos(th), sn = math.sin(th);
      um[j] = c.sign * math.pow(c.abs(), e);
      ub[j] = sn.sign * math.pow(sn.abs(), e);
      cs[j] = c;
    }
    V3 put(double m, double bb, double h) =>
        f.base + f.axis * h + f.mesial * m + f.outward * bb;
    // The crown's outline at t: 0 the biting rim, 1 the neck.
    (double, double) outline(int j, double t) {
      final y = ub[j];
      final half = y >= 0 ? b * _curve(r.bKeys, t) : b * _curve(r.lKeys, t);
      final m =
          a * _curve(r.mKeys, t) * um[j] * (1 - r.taper * math.max(0.0, -y));
      var bb = half * y + _curve(r.shift, t);
      for (final g in r.relief) {
        final face = (y * g.side - 0.3) / 0.7;
        if (face <= 0) continue;
        final d = (m / a - g.m) / g.width;
        bb -=
            g.side *
            g.depth *
            math.exp(-d * d) *
            math.min(1.0, face) *
            (1 - _smooth(0, g.until, t));
      }
      return (m, bb);
    }

    // The neck line rises towards the neighbouring teeth.
    double neckH(int j) => s.crown - r.cej * cs[j] * cs[j];

    // The biting rim, at the depth the biting surface has there.
    final rimM = Float64List(n), rimB = Float64List(n), rimH = Float64List(n);
    for (var j = 0; j < n; j++) {
      final (m, bb) = outline(j, 0);
      rimM[j] = m;
      rimB[j] = bb;
      rimH[j] = r.depth(m, bb);
    }

    // Rings out from the middle of the biting surface to the rim, then
    // down the sides to the neck.
    final c0 = _curve(r.shift, 0);
    final rings = <List<int>>[];
    final centreDepth = r.depth(0, c0);
    final centre = mb.add(put(0, c0, centreDepth), ao: _aoTop(centreDepth));
    for (final rho in _tableRho) {
      final ring = <int>[];
      for (var j = 0; j < n; j++) {
        final m = rimM[j] * rho;
        final bb = c0 + (rimB[j] - c0) * rho;
        final d = r.depth(m, bb);
        ring.add(mb.add(put(m, bb, d), ao: _aoTop(d)));
      }
      rings.add(ring);
    }
    rings.add([
      for (var j = 0; j < n; j++)
        mb.add(
          put(rimM[j], rimB[j], rimH[j]),
          ao: _aoTop(rimH[j]) * _aoSide(cs[j], 0),
        ),
    ]);
    for (final t in _wallT) {
      final ring = <int>[];
      for (var j = 0; j < n; j++) {
        final (m, bb) = outline(j, t);
        final h = rimH[j] + (neckH(j) - rimH[j]) * t;
        ring.add(
          mb.add(put(m, bb, h), ao: _aoSide(cs[j], t), neck: t >= 1 ? 1 : 0),
        );
      }
      rings.add(ring);
    }
    mb.fan(centre, rings.first);
    for (var i = 0; i + 1 < rings.length; i++) {
      mb.strip(rings[i], rings[i + 1]);
    }
    final crownTris = mb.triangleCount;

    // The root, on from the neck.
    final neck = rings.last;
    final neckM = Float64List(n), neckB = Float64List(n);
    for (var j = 0; j < n; j++) {
      final (m, bb) = outline(j, 1);
      neckM[j] = m;
      neckB[j] = bb;
    }
    final nc = _curve(r.shift, 1);
    final bend = _bend(s);
    if (s.roots <= 1) {
      var prev = neck;
      for (final tau in _rootT) {
        final k = 1 - 0.12 * tau - 0.8 * math.pow(tau, 2.6);
        final flat = _smooth(0, 0.3, tau);
        final dm = -bend * tau * tau;
        final ring = <int>[];
        for (var j = 0; j < n; j++) {
          final h = neckH(j) + (s.crown - neckH(j)) * flat + s.root * tau;
          ring.add(
            mb.add(
              put(neckM[j] * k + dm, nc + (neckB[j] - nc) * k, h),
              ao: 0.86 + 0.14 * tau,
              neck: 1 - _smooth(2, 5, h - neckH(j)),
            ),
          );
        }
        mb.strip(prev, ring);
        prev = ring;
      }
      mb.cap(prev, mb.add(put(-bend, nc, s.crown + s.root)));
    } else {
      // A shared trunk, closed underneath, then two or three roots.
      final trunk = _trunk(s);
      var prev = neck;
      for (final tau in const [0.4, 0.75, 1.0]) {
        final k = 1 - 0.12 * tau;
        final flat = _smooth(0, 1, tau);
        final ring = <int>[];
        for (var j = 0; j < n; j++) {
          final h = neckH(j) + (s.crown - neckH(j)) * flat + trunk * tau;
          ring.add(
            mb.add(
              put(neckM[j] * k, nc + (neckB[j] - nc) * k, h),
              ao: 0.86,
              neck: 1 - _smooth(2, 5, h - neckH(j)),
            ),
          );
        }
        mb.strip(prev, ring);
        prev = ring;
      }
      mb.cap(
        prev,
        mb.add(
          put(0, nc, s.crown + trunk + 1.4),
          ao: 0.6,
          neck: 1 - _smooth(2, 5, trunk + 1.4),
        ),
      );
      final am = a * _curve(r.mKeys, 1);
      final ab = b * _curve(r.bKeys, 1);
      for (final root in _roots(s)) {
        final top = s.crown + trunk - 1.4;
        final tip = s.crown + s.root * root.length;
        var ring = <int>[];
        for (final tau in _subRootT) {
          final k = 1 - 0.1 * tau - 0.82 * math.pow(tau, 2.4);
          final spread = math.pow(tau, 1.3).toDouble();
          final cm =
              root.m * am + root.splayM * spread - bend * 0.7 * tau * tau;
          final cb = nc + root.b * ab + root.splayB * spread;
          final h = top + (tip - top) * tau;
          final next = <int>[];
          for (var j = 0; j < _subRootSegs; j++) {
            final th = 2 * math.pi * j / _subRootSegs;
            next.add(
              mb.add(
                put(
                  cm + root.halfM * am * k * 1.1 * math.cos(th),
                  cb + root.halfB * ab * k * 1.1 * math.sin(th),
                  h,
                ),
                ao: 0.8 + 0.2 * _smooth(0, 0.4, tau),
                neck: 1 - _smooth(2, 5, h - s.crown),
              ),
            );
          }
          if (ring.isNotEmpty) mb.strip(ring, next);
          ring = next;
        }
        final cm = root.m * am + root.splayM - bend * 0.7;
        final cb = nc + root.b * ab + root.splayB;
        mb.cap(ring, mb.add(put(cm, cb, tip)));
      }
    }
    final (crown, root) = mb.split(crownTris, lower: lower, tooth: s.number);

    // An implant: a cap closing the crown at the neck and a threaded
    // titanium post in place of the root.
    final ib = _MeshBuilder(right: right);
    final cap = [
      for (var j = 0; j < n; j++) ib.add(put(neckM[j], neckB[j], neckH(j))),
    ];
    final h0 = s.crown - r.cej * 0.5;
    ib.cap(cap, ib.add(put(0, nc, h0)));
    final radius = s.md * 0.2;
    final length = s.root * 0.85;
    const threads = 14;
    var post = <int>[];
    for (var i = 0; i <= threads; i++) {
      final k = (1 - 0.18 * i / threads) * (i.isOdd ? 1.0 : 0.86);
      final h = h0 + length * i / threads;
      final ring = [
        for (var j = 0; j < 12; j++)
          ib.add(
            put(
              radius * k * math.cos(2 * math.pi * j / 12),
              nc + radius * k * math.sin(2 * math.pi * j / 12),
              h,
            ),
          ),
      ];
      if (post.isNotEmpty) ib.strip(post, ring);
      post = ring;
    }
    ib.cap(post, ib.add(put(0, nc, h0 + length + radius * 0.4)));
    final implant = ib.finish(
      MeshMaterial.implant,
      lower: lower,
      tooth: s.number,
    );
    return [crown, root, implant];
  }

  /// Rings across the biting surface (fractions of the rim) and down the
  /// sides (0 rim, 1 neck), and along a root (0 neck, 1 tip).
  static const _tableRho = [0.22, 0.45, 0.66, 0.84];
  static const _wallT = [
    0.04,
    0.1,
    0.18,
    0.28,
    0.4,
    0.53,
    0.66,
    0.78,
    0.89,
    1.0,
  ];
  static const _rootT = [0.08, 0.22, 0.38, 0.54, 0.69, 0.81, 0.9, 0.96];
  static const _subRootT = [0.0, 0.16, 0.34, 0.52, 0.68, 0.81, 0.9, 0.96];
  static const _subRootSegs = 12;

  /// Darker in the grooves and pits of the biting surface.
  static double _aoTop(double depth) => 1 - 0.4 * _smooth(0.45, 1.9, depth);

  /// Darker where the tooth touches its neighbours and towards the
  /// neck.
  static double _aoSide(double c, double t) {
    final p = c * c * c * c;
    return 1 -
        0.42 * p * _smooth(0, 0.2, t) * (1 - 0.5 * _smooth(0.45, 1, t)) -
        0.08 * _smooth(0.82, 1, t);
  }

  /// How far the root tip bends back (distally), mm.
  static double _bend(ToothSpec s) => switch (s.kind) {
    ToothKind.centralIncisor => 0.4,
    ToothKind.lateralIncisor => 0.9,
    ToothKind.canine => 1.0,
    ToothKind.premolar => 0.8,
    ToothKind.molar => 1.0,
  };

  /// The root trunk of a multi-rooted tooth, from the neck to where the
  /// roots part.
  static double _trunk(ToothSpec s) {
    if (s.primary) return 1.6;
    if (s.kind == ToothKind.premolar) return 6;
    return s.upper ? 4 : 3.4;
  }

  static List<_Root> _roots(ToothSpec s) {
    // Milk molars' roots flare wide around the tooth growing below.
    final flare = s.primary ? 1.8 : 1.0;
    if (s.kind == ToothKind.premolar) {
      return const [
        _Root(0, 0.42, 0.72, 0.42, 1, 0, 0.9),
        _Root(0, -0.42, 0.7, 0.4, 0.95, 0, -0.9),
      ];
    }
    if (s.upper) {
      return [
        _Root(0.42, 0.42, 0.42, 0.38, 1, 0.6 * flare, 1.3 * flare),
        _Root(-0.42, 0.42, 0.38, 0.34, 0.93, -0.9 * flare, 1.1 * flare),
        _Root(0, -0.45, 0.48, 0.42, 1.05, 0, -2.2 * flare),
      ];
    }
    return [
      _Root(0.46, 0, 0.4, 0.8, 1, 0.7 * flare, 0),
      _Root(-0.48, 0, 0.38, 0.76, 0.93, -0.9 * flare, 0),
    ];
  }

  // ---------------------------------------------------------------- bone

  /// The lower jaw: the body round the lower teeth, the chin, and each
  /// ramus rising to its condyle and coronoid process.
  static MeshPart _mandible(
    _Arch arch,
    _Row row,
    double k, {
    required bool child,
  }) {
    final end = row.end;
    // The ramus starts behind the last tooth (a child's leaves room for
    // the first permanent molar). The outline below is drawn for an adult
    // jaw with the ramus at 70 mm along the arch.
    final ra = math.max(end + 5 * k, (child ? 58 : 70) * k);
    double toArch(double u) => u <= 70 ? u * ra / 70 : ra + (u - 70) * k;
    double fromArch(double u) => u <= ra ? u * 70 / ra : 70 + (u - ra) / k;
    double crest(double u) {
      u = u.abs();
      final c = -(_gapHalf + row.crest(math.min(u, end)));
      if (u <= end) return c;
      // Behind the last tooth the ridge rises into the ramus.
      return c + (-3.5 * k - c) * _smooth(end, ra + k, u);
    }

    // The right half (u ≥ 0): along the lower border, up the back of
    // the ramus, round the condyle, through the notch and over the
    // coronoid process, then forward along the teeth.
    final back = _spline([
      for (final (u, v) in const [
        (0.0, -35.5),
        (12.0, -35.0),
        (25.0, -34.0),
        (40.0, -32.6),
        (55.0, -31.2),
        (68.0, -30.0),
        (78.0, -29.3),
        (85.0, -29.6),
        (91.0, -28.6),
        (95.2, -26.0),
        (97.6, -21.5),
        (98.6, -14.0),
        (99.1, -5.0),
        (99.4, 4.0),
        (99.8, 11.0),
        (101.2, 15.5),
        (102.6, 19.6),
        (102.5, 23.5),
        (100.6, 26.1),
        (97.1, 26.9),
        (94.1, 25.5),
        (92.9, 22.0),
        (93.2, 18.4),
        (92.1, 15.0),
        (89.6, 11.6),
        (86.1, 9.6),
        (82.6, 10.0),
        (79.6, 12.6),
        (77.1, 16.6),
        (75.5, 20.6),
        (74.3, 23.1),
        (73.1, 22.9),
        (72.1, 20.1),
        (71.3, 15.0),
        (70.8, 9.0),
        (70.4, 3.0),
        (70.2, -1.0),
      ])
        (toArch(u), v * k),
    ], 3);
    final half = <(double, double)>[
      ...back,
      for (var u = ra; u > 0.6 * k; u -= 1.2 * k) (u, crest(u)),
      (0, crest(0)),
    ];
    final outline = [
      ...half,
      for (var i = half.length - 2; i >= 1; i--) (-half[i].$1, half[i].$2),
    ];

    double thickness(double u, double v) {
      final uu = u.abs();
      final big = fromArch(uu), up = v / k;
      final below = math.max(0.0, crest(uu) - v) / k;
      final ridge = row.depth(math.min(uu, end)) / k + 2.6;
      final body = _curve(const [
        (0, 14.5),
        (10, 13.5),
        (20, 11.8),
        (32, 11.2),
        (45, 12.6),
        (60, 13),
        (68, 11.5),
        (76, 9),
      ], big);
      var t = ridge + (body - ridge) * _smooth(1, 12, below);
      // The ramus is a thin plate: a little thicker at the angle, thin
      // at the coronoid, wide at the condyle.
      var ramus = 7 + 1.6 * _smooth(-12, -24, up);
      ramus += (5.2 - ramus) * _smooth(8, 16, up) * (1 - _smooth(84, 91, big));
      ramus += (9 - ramus) * _smooth(88, 94, big) * _smooth(4, 12, up);
      ramus += (18 - ramus) * _smooth(91, 96, big) * _smooth(14, 19.5, up);
      t += (ramus - t) * _smooth(66, 77, big);
      return t * k;
    }

    double mid(double u, double v, double inside) {
      final uu = u.abs();
      final big = fromArch(uu), up = v / k;
      final below = math.max(0.0, crest(uu) - v) / k;
      // Along the roots, then the chin forward, the body bulging
      // inward under the molars, and the rami flaring out.
      var w = -row.lean(math.min(uu, end)) * below;
      final front = 1 - _smooth(4, 18, big);
      w += front * (4 * _smooth(-20, -29, up) - 2.5 * _smooth(-31, -36, up));
      w -=
          1.2 *
          _smooth(30, 45, big) *
          _smooth(-14, -26, up) *
          (1 - _smooth(62, 74, big));
      w += 5.5 * _smooth(62, 98, big);
      return w * k;
    }

    return _plate(
      outline: outline,
      place: (u, v, w) {
        final p = arch.point(u), nn = arch.normal(u);
        return V3(p.x + nn.x * w, v, p.z + nn.z * w);
      },
      thickness: thickness,
      mid: mid,
      // Full thickness right up to the ridge, so it wraps round the
      // teeth's necks instead of cutting through them.
      round: (u, v, t) {
        final uu = u.abs();
        final near =
            (1 - _smooth(4 * k, 8 * k, crest(uu) - v)) *
            (1 - _smooth(end, end + 4 * k, uu));
        final r = (t / 2).clamp(0.8, 4.5);
        return r + (0.7 * k - r) * near;
      },
      // The ridge fades in below the necks, so the teeth rise out of it.
      // Clear for the first grid step, where the ridge closes over.
      fade: (u, v, inside) {
        final uu = u.abs();
        final ridge = math.max(
          _smooth(1.6 * k, 3 * k, inside),
          _smooth(3 * k, 5 * k, crest(uu) - v),
        );
        return ridge + (1 - ridge) * _smooth(end, end + 4 * k, uu);
      },
      step: 1.6 * k,
      lower: true,
    );
  }

  /// The upper jaw round the upper teeth: the ridge holding them, the
  /// tuberosity behind the last molar, fading out above the roots (lower
  /// at the front, under the nose).
  static MeshPart _maxilla(_Arch arch, _Row row, double k) {
    final end = row.end;
    final c = _gapHalf + row.crest(end);
    final top = 48 * k;
    // Round the tuberosity, then up and forward towards the cheekbone.
    final tail = _spline([
      (end + 0.2 * k, c),
      (end + 1.8 * k, c + 0.4 * k),
      (end + 4.0 * k, c + 1.6 * k),
      (end + 6.0 * k, c + 3.6 * k),
      (end + 7.2 * k, c + 7.0 * k),
      (end + 7.0 * k, c + 12.0 * k),
      (end + 4.5 * k, c + 19.0 * k),
      (end - 1.0 * k, c + 25.0 * k),
      (end - 9.0 * k, c + 30.0 * k),
      (end - 18.0 * k, top),
    ], 3);
    final outline = <(double, double)>[
      for (final (u, v) in tail.reversed) (-u, v),
      for (var u = -end + 0.5 * k; u < end - 0.4 * k; u += k)
        (u, _gapHalf + row.crest(u)),
      ...tail,
    ];
    double crest(double u) => _gapHalf + row.crest(math.min(u.abs(), end));

    return _plate(
      outline: outline,
      place: (u, v, w) {
        final p = arch.point(u), nn = arch.normal(u);
        return V3(p.x + nn.x * w, v, p.z + nn.z * w);
      },
      // Thicker going up, but thin at the front, where the arch bends
      // too tightly for a thick plate to follow.
      thickness: (u, v) {
        final uu = u.abs();
        final above = math.max(0.0, v - crest(uu)) / k;
        final ridge = row.depth(math.min(uu, end)) / k + 3;
        final most = 9 + 12 * _smooth(4, 26, uu / k);
        return math.min(most, ridge + 0.42 * math.max(0.0, above - 1.5)) * k;
      },
      // Along the roots up to their tips, then straight up.
      mid: (u, v, inside) {
        final uu = u.abs();
        final above = math.min(14.0, math.max(0.0, v - crest(uu)) / k);
        return -row.lean(math.min(uu, end)) * above * k;
      },
      // As the lower jaw: full thickness up to the ridge, which fades in
      // above the necks.
      round: (u, v, t) {
        final uu = u.abs();
        final near =
            (1 - _smooth(4 * k, 8 * k, v - crest(uu))) *
            (1 - _smooth(end, end + 3 * k, uu));
        final r = (t / 2).clamp(0.8, 4.5);
        return r + (0.7 * k - r) * near;
      },
      fade: (u, v, inside) {
        final uu = u.abs();
        final ridge = math.max(
          _smooth(1.6 * k, 3 * k, inside),
          _smooth(3 * k, 5 * k, v - crest(uu)),
        );
        // Lower over the front teeth, where the nose begins.
        final side = _smooth(6, 24, uu / k);
        final top = 1 - _smooth((23 + 8 * side) * k, (33 + 12 * side) * k, v);
        return (ridge + (1 - ridge) * _smooth(end, end + 3 * k, uu)) * top;
      },
      step: 1.6 * k,
      lower: false,
    );
  }

  /// The roof of the mouth inside the upper arch, fading into the ridge.
  static MeshPart _palate(_Arch arch, _Row row, double k) {
    final end = row.end - 2 * k;
    final outline = <(double, double)>[];
    for (var s = -end; s <= end; s += 1.5 * k) {
      final p = arch.point(s), nn = arch.normal(s);
      final inset = row.depth(s) / 2 + k;
      outline.add((p.x - nn.x * inset, p.z - nn.z * inset));
    }
    return _plate(
      outline: outline,
      place: (x, z, y) => V3(x, y, z),
      thickness: (x, z) => 2.4 * k,
      mid: (x, z, inside) => (13 + 7 * _smooth(0, 11, inside / k)) * k,
      fade: (x, z, inside) => _smooth(0.5, 5, inside / k),
      step: 1.8 * k,
      reach: 12 * k,
      lower: false,
    );
  }

  /// A plate of bone: [outline] (closed, in (u, v)) filled and inflated
  /// to [thickness] either side of [mid], with edges rounded over
  /// [round] (half the thickness, at most 4.5 mm, unless given). [place]
  /// maps (u, v, w) to the model, w across the plate.
  static MeshPart _plate({
    required List<(double, double)> outline,
    required V3 Function(double u, double v, double w) place,
    required double Function(double u, double v) thickness,
    required double Function(double u, double v, double inside) mid,
    double Function(double u, double v, double inside)? fade,
    double Function(double u, double v, double thickness)? round,
    required double step,
    double reach = 5,
    required bool lower,
  }) {
    var u0 = double.infinity, u1 = -double.infinity;
    var v0 = double.infinity, v1 = -double.infinity;
    for (final (u, v) in outline) {
      u0 = math.min(u0, u);
      u1 = math.max(u1, u);
      v0 = math.min(v0, v);
      v1 = math.max(v1, v);
    }
    u0 -= step;
    v0 -= step;
    final nu = ((u1 - u0) / step).ceil() + 2;
    final nv = ((v1 - v0) / step).ceil() + 2;
    final count = nu * nv;
    final m = outline.length;

    // Inside: where each grid row crosses the outline.
    final inside = Uint8List(count);
    final xs = <double>[];
    for (var j = 0; j < nv; j++) {
      final v = v0 + j * step;
      xs.clear();
      for (var q = 0; q < m; q++) {
        final (au, av) = outline[q];
        final (bu, bv) = outline[(q + 1) % m];
        if ((av <= v) != (bv <= v)) {
          xs.add(au + (v - av) / (bv - av) * (bu - au));
        }
      }
      xs.sort();
      for (var q = 0; q + 1 < xs.length; q += 2) {
        final i0 = math.max(0, ((xs[q] - u0) / step).ceil());
        final i1 = math.min(nu - 1, ((xs[q + 1] - u0) / step).floor());
        for (var i = i0; i <= i1; i++) {
          inside[j * nu + i] = 1;
        }
      }
    }

    // Distance to the outline, as far in as the edges round off.
    final dist = Float64List(count)..fillRange(0, count, reach);
    for (var q = 0; q < m; q++) {
      final (au, av) = outline[q];
      final (bu, bv) = outline[(q + 1) % m];
      final du = bu - au, dv = bv - av;
      final ll = du * du + dv * dv;
      final i0 = math.max(0, ((math.min(au, bu) - reach - u0) / step).floor());
      final i1 = math.min(
        nu - 1,
        ((math.max(au, bu) + reach - u0) / step).ceil(),
      );
      final j0 = math.max(0, ((math.min(av, bv) - reach - v0) / step).floor());
      final j1 = math.min(
        nv - 1,
        ((math.max(av, bv) + reach - v0) / step).ceil(),
      );
      for (var j = j0; j <= j1; j++) {
        final pv = v0 + j * step - av;
        for (var i = i0; i <= i1; i++) {
          final pu = u0 + i * step - au;
          var t = ll == 0 ? 0.0 : (pu * du + pv * dv) / ll;
          if (t < 0) t = 0;
          if (t > 1) t = 1;
          final ex = pu - t * du, ey = pv - t * dv;
          final d = math.sqrt(ex * ex + ey * ey);
          final idx = j * nu + i;
          if (d < dist[idx]) dist[idx] = d;
        }
      }
    }
    for (var i = 0; i < count; i++) {
      if (inside[i] == 1 && dist[i] < 1e-3) dist[i] = 1e-3;
    }
    double signed(int i) => inside[i] == 1 ? dist[i] : -dist[i];

    final b = _MeshBuilder();
    // Two sheets over the inside points, either side of the middle.
    final outer = Int32List(count)..fillRange(0, count, -1);
    final inner = Int32List(count)..fillRange(0, count, -1);
    for (var j = 0; j < nv; j++) {
      for (var i = 0; i < nu; i++) {
        final idx = j * nu + i;
        if (inside[idx] == 0) continue;
        final u = u0 + i * step, v = v0 + j * step;
        final t = thickness(u, v);
        // Rounded off towards the edge; straight at the very edge so the
        // rim is clean whatever the grid does there.
        final r = round?.call(u, v, t) ?? (t / 2).clamp(0.8, 4.5);
        final x = math.min(1.0, dist[idx] / r);
        final half = t / 2 * x * (2 - x);
        final w = mid(u, v, dist[idx]);
        final f = fade?.call(u, v, dist[idx]) ?? 1.0;
        outer[idx] = b.add(place(u, v, w + half), fade: f);
        inner[idx] = b.add(place(u, v, w - half), fade: f);
      }
    }
    // Where the outline crosses the grid the sheets meet.
    int edge(int ia, int ib, double ua, double va, double ubb, double vb) {
      final sa = signed(ia), sb = signed(ib);
      final t = sa / (sa - sb);
      final u = ua + (ubb - ua) * t, v = va + (vb - va) * t;
      return b.add(place(u, v, mid(u, v, 0)), fade: fade?.call(u, v, 0) ?? 1);
    }

    final across = Int32List(count)..fillRange(0, count, -1);
    final upward = Int32List(count)..fillRange(0, count, -1);
    for (var j = 0; j < nv; j++) {
      for (var i = 0; i < nu; i++) {
        final idx = j * nu + i;
        final u = u0 + i * step, v = v0 + j * step;
        if (i + 1 < nu && inside[idx] != inside[idx + 1]) {
          across[idx] = edge(idx, idx + 1, u, v, u + step, v);
        }
        if (j + 1 < nv && inside[idx] != inside[idx + nu]) {
          upward[idx] = edge(idx, idx + nu, u, v, u, v + step);
        }
      }
    }

    // Which way the sheets face: counter-clockwise cells in (u, v) face
    // +w unless the mapping mirrors them.
    var flip = false;
    for (var idx = 0; idx < count; idx++) {
      if (inside[idx] == 0) continue;
      final u = u0 + (idx % nu) * step, v = v0 + (idx ~/ nu) * step;
      final w = mid(u, v, dist[idx]);
      final p = place(u, v, w);
      final nn = (place(u + 0.5, v, w) - p).cross(place(u, v + 0.5, w) - p);
      flip = nn.dot(place(u, v, w + 0.5) - p) < 0;
      break;
    }

    final poly = <int>[], back = <int>[];
    for (var j = 0; j + 1 < nv; j++) {
      for (var i = 0; i + 1 < nu; i++) {
        final c00 = j * nu + i, c10 = c00 + 1, c01 = c00 + nu, c11 = c01 + 1;
        if (inside[c00] + inside[c10] + inside[c01] + inside[c11] == 0) {
          continue;
        }
        poly.clear();
        back.clear();
        void corner(int c) {
          if (inside[c] == 0) return;
          poly.add(outer[c]);
          back.add(inner[c]);
        }

        void cut(int e) {
          if (e < 0) return;
          poly.add(e);
          back.add(e);
        }

        corner(c00);
        cut(across[c00]);
        corner(c10);
        cut(upward[c10]);
        corner(c11);
        cut(across[c01]);
        corner(c01);
        cut(upward[c00]);
        for (var q = 1; q + 1 < poly.length; q++) {
          if (flip) {
            b
              ..tri(poly[0], poly[q + 1], poly[q])
              ..tri(back[0], back[q], back[q + 1]);
          } else {
            b
              ..tri(poly[0], poly[q], poly[q + 1])
              ..tri(back[0], back[q + 1], back[q]);
          }
        }
      }
    }
    return b.finish(MeshMaterial.bone, lower: lower);
  }
}

/// How one crown is shaped, in the tooth's own frame: m along the arch
/// towards the midline, b outwards (lip or cheek side), h from the
/// biting surface towards the root, all in millimetres.
class _Recipe {
  const _Recipe({
    required this.exp,
    required this.mKeys,
    required this.bKeys,
    required this.lKeys,
    required this.depth,
    required this.cej,
    this.taper = 0,
    this.shift = const [(0.0, 0.0)],
    this.relief = const [],
    this.segs = 32,
  });

  /// Squareness of the outline (2 is an ellipse).
  final double exp;

  /// Outline scale from the biting rim (t 0) to the neck (t 1): along
  /// the arch, and the cheek and tongue halves.
  final List<(double, double)> mKeys;
  final List<(double, double)> bKeys;
  final List<(double, double)> lKeys;

  /// The outline's centre moved towards the cheek (mm) by t.
  final List<(double, double)> shift;

  /// The tongue half this much narrower along the arch.
  final double taper;

  /// Grooves and ridges down the sides.
  final List<_Relief> relief;

  /// Depth of the biting surface below its highest point at (m, b).
  final double Function(double m, double b) depth;

  /// How far the neck line rises where the tooth meets its neighbours.
  final double cej;

  /// Points round each ring.
  final int segs;

  static final Map<String, _Recipe> _cache = {};

  static _Recipe of(ToothSpec s) =>
      _cache.putIfAbsent(s.number, () => _build(s));

  /// Keys from heights [t] (shared by a tooth's three profiles) and
  /// [values].
  static List<(double, double)> _keys(List<double> t, List<double> values) => [
    for (var i = 0; i < t.length; i++) (t[i], values[i]),
  ];

  static _Recipe _build(ToothSpec s) {
    final a = s.md / 2, b = s.bl / 2;
    // Milk teeth: lower cusps, a flatter neck line.
    final p = s.primary ? 0.75 : 1.0;
    switch (s.kind) {
      case ToothKind.centralIncisor || ToothKind.lateralIncisor:
        final lateral = s.kind == ToothKind.lateralIncisor;
        // Where the incisal corners start to round, and by how much; the
        // distal corner is rounder.
        final corner = s.upper ? (lateral ? 0.5 : 0.7) : 0.78;
        final drop = (s.upper ? (lateral ? 2.2 : 1.5) : 1.0) * p;
        final edge = 0.14 * b;
        // The three lobes the lip side grows from.
        final lobe = (s.upper ? 0.12 : 0.08) * p;
        const t = <double>[0, 0.04, 0.1, 0.22, 0.42, 0.66, 0.84, 1];
        return _Recipe(
          exp: 2.6,
          mKeys: _keys(t, [0.93, 0.955, 0.99, 1, 0.95, 0.86, 0.77, 0.7]),
          bKeys: _keys(t, [0.14, 0.28, 0.44, 0.63, 0.83, 0.97, 1, 0.93]),
          lKeys: _keys(t, [0.12, 0.2, 0.28, 0.37, 0.5, 0.75, 0.97, 0.93]),
          relief: [
            _Relief(0.32, 1, lobe, 0.12, 0.45),
            _Relief(-0.32, 1, lobe, 0.12, 0.45),
          ],
          cej: (s.upper ? (lateral ? 2.6 : 3.0) : 2.4) * p,
          segs: 28,
          depth: (m, bb) {
            final x = (m / a).abs() / 0.93;
            var k = x <= corner ? 0.0 : (x - corner) / (1 - corner);
            if (m < 0) k *= 1.25;
            return drop * k * k + 0.3 * (bb / edge) * (bb / edge);
          },
        );
      case ToothKind.canine:
        // The cusp tip sits a little mesial; the mesial ridge is the
        // shorter, steeper one. A ridge runs down each face from the tip.
        final tip = a * 0.06;
        final edge = 0.3 * b;
        const t = <double>[0, 0.05, 0.12, 0.25, 0.45, 0.7, 0.85, 1];
        return _Recipe(
          exp: 2.0,
          mKeys: _keys(t, [0.88, 0.95, 0.985, 0.995, 0.955, 0.83, 0.77, 0.72]),
          bKeys: _keys(t, [0.3, 0.47, 0.61, 0.77, 0.92, 1, 0.985, 0.9]),
          lKeys: _keys(t, [0.26, 0.38, 0.49, 0.63, 0.84, 0.97, 0.99, 0.9]),
          relief: [
            _Relief(0.06, 1, -0.22 * p, 0.28, 0.75),
            _Relief(0.06, -1, -0.2 * p, 0.25, 0.6),
          ],
          cej: (s.upper ? 2.0 : 2.2) * p,
          segs: 28,
          depth: (m, bb) {
            final dm = m - tip;
            final slope = dm > 0 ? 0.85 : 0.7;
            return slope * (math.sqrt(dm * dm + 0.36) - 0.6) * p +
                0.2 * (bb / edge) * (bb / edge);
          },
        );
      case ToothKind.premolar:
        final first = s.position == 4;
        final List<(double, double, double)> cusps = s.upper
            ? first
                  ? const [(0.04, 0.44, 0), (0, -0.44, 0.9)]
                  : const [(0, 0.42, 0), (0, -0.42, 0.3)]
            : first
            ? const [(0, 0.3, 0), (0, -0.52, 2.4)]
            : const [(0, 0.34, 0), (0.34, -0.46, 0.75), (-0.36, -0.46, 1.15)];
        const t = <double>[0, 0.06, 0.17, 0.32, 0.5, 0.7, 0.85, 1];
        return _Recipe(
          exp: 2.5,
          mKeys: _keys(t, [0.8, 0.9, 0.975, 1, 0.95, 0.87, 0.79, 0.72]),
          bKeys: _keys(t, [0.66, 0.78, 0.9, 0.95, 0.985, 1, 0.965, 0.86]),
          lKeys: _keys(t, [0.62, 0.75, 0.87, 0.96, 1, 0.97, 0.92, 0.84]),
          taper: s.upper ? 0.08 : 0.16,
          shift: s.upper ? const [(0.0, 0.0)] : const [(0.0, -0.4), (1.0, 0.0)],
          // The buccal ridge down from the cheek-side cusp.
          relief: [_Relief(0, 1, (s.upper ? -0.2 : -0.12) * p, 0.3, 0.65)],
          cej: 1.0 * p,
          depth: _cusps(a, b, cusps, floor: 1.9 * p, p: p, ridges: 0.82),
        );
      case ToothKind.molar:
        final pos = s.position;
        // The milk second molar is shaped like the permanent first.
        final firstLike = s.primary ? pos == 5 : pos == 6;
        final milkFirst = s.primary && pos == 4;
        final third = !s.primary && pos == 8;
        final List<(double, double, double)> cusps = s.upper
            ? firstLike
                  ? const [
                      (0.48, 0.52, 0.25),
                      (-0.42, 0.55, 0.45),
                      (0.36, -0.45, 0),
                      (-0.5, -0.5, 0.95),
                    ]
                  : milkFirst
                  ? const [
                      (0.42, 0.45, 0),
                      (-0.4, 0.45, 0.6),
                      (0.2, -0.42, 0.35),
                    ]
                  : third
                  ? const [
                      (0.4, 0.5, 0.3),
                      (-0.35, 0.42, 0.9),
                      (0.26, -0.4, 0.1),
                    ]
                  : const [
                      (0.45, 0.5, 0.25),
                      (-0.4, 0.5, 0.6),
                      (0.35, -0.45, 0),
                      (-0.5, -0.45, 1.35),
                    ]
            : firstLike
            ? const [
                (0.55, 0.48, 0.3),
                (0, 0.55, 0.4),
                (-0.6, 0.35, 0.8),
                (0.5, -0.48, 0),
                (-0.35, -0.5, 0.15),
              ]
            : milkFirst
            ? const [
                (0.45, 0.45, 0),
                (-0.35, 0.45, 0.5),
                (0.4, -0.45, 0.2),
                (-0.4, -0.45, 0.6),
              ]
            : const [
                (0.45, 0.48, 0.3),
                (-0.45, 0.48, 0.45),
                (0.45, -0.48, 0),
                (-0.45, -0.48, 0.2),
              ];
        // A groove runs down each side between neighbouring cusps.
        final grooves = <_Relief>[];
        for (final side in const [1.0, -1.0]) {
          final ms = [
            for (final (m, bb, _) in cusps)
              if (bb * side > 0) m,
          ]..sort();
          for (var i = 0; i + 1 < ms.length; i++) {
            grooves.add(
              _Relief((ms[i] + ms[i + 1]) / 2, side, 0.32 * p, 0.13, 0.55),
            );
          }
        }
        const t = <double>[0, 0.06, 0.16, 0.32, 0.5, 0.7, 0.87, 1];
        return _Recipe(
          exp: 3.0,
          mKeys: _keys(t, [0.85, 0.93, 0.98, 1, 0.97, 0.91, 0.86, 0.82]),
          bKeys: _keys(t, [0.74, 0.84, 0.91, 0.96, 0.99, 1, 0.97, 0.88]),
          lKeys: _keys(t, [0.76, 0.86, 0.93, 0.98, 1, 0.975, 0.93, 0.86]),
          taper: s.upper ? 0.1 : 0.04,
          shift: s.upper ? const [(0.0, 0.0)] : const [(0.0, -0.3), (1.0, 0.0)],
          relief: grooves,
          cej: 0.7 * p,
          depth: _cusps(a, b, cusps, floor: 2.1 * p, p: p, ridges: 0.85),
        );
    }
  }

  /// A biting surface from its cusps ((m, b) as fractions of the half
  /// size, tip depth in mm): rounded cones meeting in grooves, marginal
  /// ridges at the mesial and distal edges, a floor to the fossae.
  static double Function(double, double) _cusps(
    double a,
    double b,
    List<(double, double, double)> cusps, {
    required double floor,
    required double p,
    required double ridges,
  }) {
    final tips = [for (final (m, bb, d) in cusps) (m * a, bb * b, d * p)];
    final rm = ridges * a, rb = 0.42 * b;
    return (m, bb) {
      var h = floor;
      for (final (cm, cb, d) in tips) {
        final dm = m - cm, db = bb - cb;
        h = _smin(
          h,
          d + 0.8 * p * (math.sqrt(dm * dm + db * db + 0.4) - 0.63),
          0.5,
        );
      }
      final over = math.max(0.0, bb.abs() - rb);
      for (final sm in [rm, -rm]) {
        final dm = m - sm;
        h = _smin(h, 0.95 * p + 0.9 * math.sqrt(dm * dm + over * over), 0.5);
      }
      return h;
    };
  }
}

/// A groove (or, with a negative depth, a ridge) running down one side of
/// a crown from the biting rim: where along the arch (a fraction of the
/// half width), which side (1 cheek, -1 tongue), how deep (mm), how wide
/// (of the half width), and how far down it goes (t).
class _Relief {
  const _Relief(this.m, this.side, this.depth, this.width, this.until);

  final double m, side, depth, width, until;
}

/// One root of a multi-rooted tooth: where it leaves the trunk and its
/// size (fractions of the neck's half size), its length (of the tooth's
/// root length), and how far its tip spreads (mm).
class _Root {
  const _Root(
    this.m,
    this.b,
    this.halfM,
    this.halfB,
    this.length,
    this.splayM,
    this.splayB,
  );

  final double m, b, halfM, halfB, length, splayM, splayB;
}

/// One arch's teeth along the arch (the patient's left half; the right
/// mirrors it), for shaping the bone around them.
class _Row {
  _Row(List<(ToothSpec, double)> placed)
    : _teeth = placed.where((p) => p.$2 > 0).toList()
        ..sort((a, b) => a.$2.compareTo(b.$2));

  final List<(ToothSpec, double)> _teeth;

  /// Where the last tooth ends, along the arch.
  double get end => _teeth.last.$2 + _teeth.last.$1.md / 2;

  double _blend(double u, double Function(ToothSpec) f) {
    u = u.abs();
    if (u <= _teeth.first.$2) return f(_teeth.first.$1);
    for (var i = 1; i < _teeth.length; i++) {
      final (b, sb) = _teeth[i];
      if (u <= sb) {
        final (a, sa) = _teeth[i - 1];
        final t = _smooth(sa, sb, u);
        return f(a) + (f(b) - f(a)) * t;
      }
    }
    return f(_teeth.last.$1);
  }

  /// Crown depth (cheek to tongue) at [u].
  double depth(double u) => _blend(u, (t) => t.bl);

  /// How the crowns lean at [u] (the roots lean the other way).
  double lean(double u) => _blend(u, JawModel._lean);

  /// How far from the biting plane the bone's edge runs at [u]: at each
  /// tooth's neck, nearer the bite between teeth.
  double crest(double u) {
    u = u.abs();
    var h = 1e9;
    for (final (t, s) in _teeth) {
      final half = t.md / 2;
      if ((u - s).abs() > half + 2) continue;
      final x = ((u - s) / half).clamp(-1.2, 1.2);
      h = _smin(h, t.crown - _Recipe.of(t).cej * x * x, 0.7);
    }
    if (h > 1e8) h = _teeth.last.$1.crown;
    return h + 0.15;
  }
}

/// The dental arch as a parabola z = d(1 - (x/w)²), walked by arc length
/// from the midline (negative on the patient's right). It carries on
/// behind the teeth, where the lower jaw rises into its rami.
class _Arch {
  _Arch(this.w, this.d) {
    var s = 0.0;
    var px = 0.0, pz = d;
    _xs.add(0);
    _ss.add(0);
    for (var x = 0.05; x <= w * 1.8; x += 0.05) {
      final z = d * (1 - (x / w) * (x / w));
      s += math.sqrt((x - px) * (x - px) + (z - pz) * (z - pz));
      _xs.add(x);
      _ss.add(s);
      px = x;
      pz = z;
    }
  }

  final double w;
  final double d;
  final List<double> _xs = [];
  final List<double> _ss = [];

  double _xAt(double s) {
    if (s <= 0) return 0;
    var lo = 0, hi = _ss.length - 1;
    if (s >= _ss[hi]) return _xs[hi];
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_ss[mid] < s) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final u = (s - _ss[lo]) / (_ss[hi] - _ss[lo]);
    return _xs[lo] + (_xs[hi] - _xs[lo]) * u;
  }

  V3 point(double s) {
    final x = _xAt(s.abs()) * (s < 0 ? -1 : 1);
    return V3(x, 0, d * (1 - (x / w) * (x / w)));
  }

  /// Along the arch, towards the patient's left.
  V3 tangent(double s) {
    final x = _xAt(s.abs()) * (s < 0 ? -1 : 1);
    final dz = -2 * d * x / (w * w);
    return V3(1, 0, dz).unit;
  }

  /// Level, out towards the lips and cheeks.
  V3 normal(double s) {
    final t = tangent(s);
    return V3(-t.z, 0, t.x);
  }
}

class _MeshBuilder {
  _MeshBuilder({this.right = true});

  /// Rings run counter-clockwise in a right-handed (mesial, outward,
  /// rootward) frame; the other side of the mouth mirrors it.
  final bool right;
  final List<double> _p = [];
  final List<double> _ao = [];
  final List<double> _fade = [];
  final List<double> _neck = [];
  final List<int> _t = [];

  int add(V3 v, {double ao = 1, double fade = 1, double neck = 0}) {
    _p
      ..add(v.x)
      ..add(v.y)
      ..add(v.z);
    _ao.add(ao);
    _fade.add(fade);
    _neck.add(neck);
    return _ao.length - 1;
  }

  int get triangleCount => _t.length ~/ 3;

  void tri(int a, int b, int c) => _t
    ..add(a)
    ..add(b)
    ..add(c);

  /// Joins ring [a] to the next ring out or down, [b].
  void strip(List<int> a, List<int> b) {
    final n = a.length;
    for (var j = 0; j < n; j++) {
      final j1 = (j + 1) % n;
      if (right) {
        tri(a[j], a[j1], b[j]);
        tri(a[j1], b[j1], b[j]);
      } else {
        tri(a[j], b[j], a[j1]);
        tri(a[j1], b[j], b[j1]);
      }
    }
  }

  /// Closes the first ring of a surface round its middle point [c].
  void fan(int c, List<int> ring) {
    final n = ring.length;
    for (var j = 0; j < n; j++) {
      final j1 = (j + 1) % n;
      right ? tri(c, ring[j1], ring[j]) : tri(c, ring[j], ring[j1]);
    }
  }

  /// Closes the last ring of a surface to its tip [c].
  void cap(List<int> ring, int c) {
    final n = ring.length;
    for (var j = 0; j < n; j++) {
      final j1 = (j + 1) % n;
      right ? tri(ring[j], ring[j1], c) : tri(ring[j1], ring[j], c);
    }
  }

  Float64List _normals() {
    final nrm = Float64List(_p.length);
    for (var i = 0; i < _t.length; i += 3) {
      final a = _t[i] * 3, b = _t[i + 1] * 3, c = _t[i + 2] * 3;
      final ux = _p[b] - _p[a], uy = _p[b + 1] - _p[a + 1];
      final uz = _p[b + 2] - _p[a + 2];
      final vx = _p[c] - _p[a], vy = _p[c + 1] - _p[a + 1];
      final vz = _p[c + 2] - _p[a + 2];
      final nx = uy * vz - uz * vy;
      final ny = uz * vx - ux * vz;
      final nz = ux * vy - uy * vx;
      for (final k in [a, b, c]) {
        nrm[k] += nx;
        nrm[k + 1] += ny;
        nrm[k + 2] += nz;
      }
    }
    for (var i = 0; i < nrm.length; i += 3) {
      final l = math.sqrt(
        nrm[i] * nrm[i] + nrm[i + 1] * nrm[i + 1] + nrm[i + 2] * nrm[i + 2],
      );
      if (l > 0) {
        nrm[i] /= l;
        nrm[i + 1] /= l;
        nrm[i + 2] /= l;
      }
    }
    return nrm;
  }

  MeshPart _part(
    Float64List nrm,
    int from,
    int to,
    MeshMaterial material, {
    required bool lower,
    String? tooth,
  }) {
    // Only the vertices these triangles use, renumbered.
    final map = Int32List(_ao.length)..fillRange(0, _ao.length, -1);
    final used = <int>[];
    final tris = Int32List((to - from) * 3);
    for (var i = from * 3; i < to * 3; i++) {
      final v = _t[i];
      if (map[v] < 0) {
        map[v] = used.length;
        used.add(v);
      }
      tris[i - from * 3] = map[v];
    }
    final pos = Float64List(used.length * 3);
    final out = Float64List(used.length * 3);
    final ao = Float32List(used.length);
    final fade = Float32List(used.length);
    final neck = Float32List(used.length);
    for (var k = 0; k < used.length; k++) {
      final v = used[k];
      for (var d = 0; d < 3; d++) {
        pos[k * 3 + d] = _p[v * 3 + d];
        out[k * 3 + d] = nrm[v * 3 + d];
      }
      ao[k] = _ao[v];
      fade[k] = _fade[v];
      neck[k] = _neck[v];
    }
    final bone = material == MeshMaterial.bone;
    return MeshPart(
      positions: pos,
      normals: out,
      triangles: tris,
      material: material,
      lower: lower,
      tooth: tooth,
      occlusion: bone ? null : ao,
      fade: bone ? fade : null,
      neck: material == MeshMaterial.root ? neck : null,
    );
  }

  MeshPart finish(
    MeshMaterial material, {
    required bool lower,
    String? tooth,
  }) =>
      _part(_normals(), 0, triangleCount, material, lower: lower, tooth: tooth);

  /// The crown (triangles before [at]) and the root (the rest), with
  /// normals smoothed across the neck where they meet.
  (MeshPart, MeshPart) split(int at, {required bool lower, String? tooth}) {
    final nrm = _normals();
    return (
      _part(nrm, 0, at, MeshMaterial.crown, lower: lower, tooth: tooth),
      _part(
        nrm,
        at,
        triangleCount,
        MeshMaterial.root,
        lower: lower,
        tooth: tooth,
      ),
    );
  }
}

// ------------------------------------------------------------- helpers

double _smooth(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// The smaller of [a] and [b], blended over [k] (rounds grooves).
double _smin(double a, double b, double k) {
  final h = (0.5 + 0.5 * (b - a) / k).clamp(0.0, 1.0);
  return b + (a - b) * h - k * h * (1 - h);
}

/// A smooth curve through (t, value) keys that never overshoots them.
double _curve(List<(double, double)> k, double t) {
  if (k.length == 1 || t <= k.first.$1) return k.first.$2;
  if (t >= k.last.$1) return k.last.$2;
  var i = 1;
  while (t > k[i].$1) {
    i++;
  }
  double slope(int j) {
    if (j == 0) return (k[1].$2 - k[0].$2) / (k[1].$1 - k[0].$1);
    final last = k.length - 1;
    if (j == last) {
      return (k[last].$2 - k[last - 1].$2) / (k[last].$1 - k[last - 1].$1);
    }
    final d0 = (k[j].$2 - k[j - 1].$2) / (k[j].$1 - k[j - 1].$1);
    final d1 = (k[j + 1].$2 - k[j].$2) / (k[j + 1].$1 - k[j].$1);
    if (d0 * d1 <= 0) return 0;
    return 2 / (1 / d0 + 1 / d1);
  }

  final (x0, y0) = k[i - 1];
  final (x1, y1) = k[i];
  final h = x1 - x0;
  final u = (t - x0) / h;
  final u2 = u * u, u3 = u2 * u;
  return (2 * u3 - 3 * u2 + 1) * y0 +
      (u3 - 2 * u2 + u) * h * slope(i - 1) +
      (-2 * u3 + 3 * u2) * y1 +
      (u3 - u2) * h * slope(i);
}

/// A smooth path through [points] ([per] samples between each pair).
List<(double, double)> _spline(List<(double, double)> points, int per) {
  final out = <(double, double)>[];
  final n = points.length;
  for (var i = 0; i + 1 < n; i++) {
    final p0 = points[math.max(0, i - 1)], p1 = points[i];
    final p2 = points[i + 1], p3 = points[math.min(n - 1, i + 2)];
    for (var k = 0; k < per; k++) {
      final t = k / per, t2 = t * t, t3 = t2 * t;
      double at(double a, double b, double c, double d) =>
          0.5 *
          (2 * b +
              (-a + c) * t +
              (2 * a - 5 * b + 4 * c - d) * t2 +
              (-a + 3 * b - 3 * c + d) * t3);
      out.add((at(p0.$1, p1.$1, p2.$1, p3.$1), at(p0.$2, p1.$2, p2.$2, p3.$2)));
    }
  }
  out.add(points.last);
  return out;
}
