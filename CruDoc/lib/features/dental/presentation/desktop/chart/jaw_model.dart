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

enum MeshMaterial { crown, root, gum, implant }

/// One drawable piece: a tooth's crown, its roots or implant, or a gum.
class MeshPart {
  MeshPart({
    required this.positions,
    required this.normals,
    required this.triangles,
    required this.material,
    required this.lower,
    this.tooth,
  });

  /// x, y, z per vertex (millimetres, model space).
  final Float64List positions;
  final Float64List normals;

  /// Three vertex indices per triangle, wound outward.
  final Int32List triangles;
  final MeshMaterial material;

  /// Part of the lower jaw (moves when the mouth opens).
  final bool lower;

  /// FDI number; null for gums.
  final String? tooth;

  int get vertexCount => positions.length ~/ 3;
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
  });

  final ToothSpec spec;
  final V3 base;
  final V3 axis;
  final V3 outward;
  final V3 tangent;

  /// A point on the crown's outer face, where a callout points.
  V3 get anchor => base + axis * (spec.crown * 0.35) + outward * (spec.bl * 0.52);
}

/// Both jaws as meshes, centred on the origin.
class JawModel {
  JawModel._(this.parts, this.frames, this.hingeY, this.hingeZ);

  final List<MeshPart> parts;
  final Map<String, ToothFrame> frames;

  /// The axis the lower jaw turns on when the mouth opens.
  final double hingeY;
  final double hingeZ;

  static final Map<bool, JawModel> _cache = {};

  static JawModel of({required bool child}) =>
      _cache.putIfAbsent(child, () => _build(child));

  static const double _gapHalf = 0.5;

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

    void placeArch(List<String> row, _Arch arch, bool upper) {
      final half = row.length ~/ 2;
      // The row runs patient's right (left of screen) to patient's left.
      final right = row.sublist(0, half).reversed.toList();
      final left = row.sublist(half);
      final placed = <(ToothSpec, double)>[
        for (final (spec, s) in placeSide(right)) (spec, -s),
        for (final (spec, s) in placeSide(left)) (spec, s),
      ];
      final contacts = <double>[];
      for (final (spec, s) in placed) {
        contacts
          ..add(s - spec.md / 2 - 0.12)
          ..add(s + spec.md / 2 + 0.12);
        final p = arch.point(s);
        final t = arch.tangent(s);
        final outward = V3(-t.z, 0, t.x);
        final lean = switch (spec.kind) {
          ToothKind.centralIncisor || ToothKind.lateralIncisor => upper ? 0.3 : 0.16,
          ToothKind.canine => 0.14,
          ToothKind.premolar => 0.05,
          ToothKind.molar => -0.04,
        };
        final vertical = V3(0, upper ? 1 : -1, 0);
        final axis = (vertical - outward * lean).unit;
        final out2 = (outward - axis * outward.dot(axis)).unit;
        final base = V3(p.x, upper ? _gapHalf : -_gapHalf, p.z);
        final frame = ToothFrame(
          spec: spec,
          base: base,
          axis: axis,
          outward: out2,
          tangent: axis.cross(out2).unit,
        );
        frames[spec.number] = frame;
        parts.add(_crown(frame, lower: !upper));
        parts.add(_roots(frame, lower: !upper));
        parts.add(_implant(frame, lower: !upper));
      }
      parts.add(_gum(arch, placed, contacts, upper: upper));
    }

    placeArch(upperRow, upperArch, true);
    placeArch(lowerRow, lowerArch, false);

    // Centre the model on its bounding box.
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
      for (final e in frames.entries)
        e.key: ToothFrame(
          spec: e.value.spec,
          base: e.value.base - shift,
          axis: e.value.axis,
          outward: e.value.outward,
          tangent: e.value.tangent,
        ),
    };
    return JawModel._(parts, centred, 3 - cy, minZ - 14 - cz);
  }

  // -------------------------------------------------------------- crowns

  static MeshPart _crown(ToothFrame f, {required bool lower}) {
    final s = f.spec;
    final (occA, occB, cejA, cejB, exp, depth) = switch (s.kind) {
      ToothKind.centralIncisor || ToothKind.lateralIncisor =>
        (0.92, 0.22, 0.7, 0.78, 2.4, 0.3),
      ToothKind.canine => (0.45, 0.5, 0.66, 0.8, 2.3, 2.2),
      ToothKind.premolar => (0.7, 0.72, 0.72, 0.82, 2.6, 2.0),
      ToothKind.molar => (0.82, 0.8, 0.82, 0.85, 3.0, 1.7),
    };
    final d = depth * (s.primary ? 0.7 : 1.0);
    double key(List<(double, double)> k, double t) {
      if (t <= k.first.$1) return k.first.$2;
      for (var i = 1; i < k.length; i++) {
        if (t <= k[i].$1) {
          final (t0, v0) = k[i - 1];
          final (t1, v1) = k[i];
          final u = (t - t0) / (t1 - t0);
          final sm = u * u * (3 - 2 * u);
          return v0 + (v1 - v0) * sm;
        }
      }
      return k.last.$2;
    }

    final aKeys = [
      (0.0, occA),
      (0.15, occA + (1 - occA) * 0.7),
      (0.3, 1.0),
      (0.5, 0.97),
      (0.8, (1 + cejA) / 2),
      (1.0, cejA),
      (1.12, cejA * 0.96),
    ];
    final bKeys = [
      (0.0, occB),
      (0.15, occB + (1 - occB) * 0.6),
      (0.4, 1.0),
      (0.7, 0.95),
      (1.0, cejB),
      (1.12, cejB * 0.95),
    ];
    double cusp(double th) => switch (s.kind) {
          ToothKind.molar => (1 - math.cos(4 * th)) / 2,
          ToothKind.premolar => (1 - math.cos(2 * th)) / 2,
          ToothKind.canine => 0.0,
          _ => 0.5,
        };
    const hs = [0.0, 0.06, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.0, 1.12];
    final rings = [
      for (var i = 0; i < hs.length; i++)
        _Ring(
          h: hs[i] * s.crown,
          a: s.md / 2 * key(aKeys, hs[i]),
          b: s.bl / 2 * key(bKeys, hs[i]),
          exponent: exp,
          lift: i == 0
              ? (th) => s.kind == ToothKind.canine ? d * 0.75 : d * (1 - cusp(th))
              : i == 1
                  ? (th) => s.kind == ToothKind.canine ? d * 0.3 : d * 0.35 * (1 - cusp(th))
                  : null,
        ),
    ];
    final top = switch (s.kind) {
      ToothKind.molar || ToothKind.premolar => d * 1.15,
      ToothKind.canine => 0.0,
      _ => 0.12,
    };
    return _loft(f, rings, segs: 18, topCap: top, bottomCap: null,
        material: MeshMaterial.crown, lower: lower);
  }

  // --------------------------------------------------------------- roots

  static MeshPart _roots(ToothFrame f, {required bool lower}) {
    final s = f.spec;
    final b = _MeshBuilder();
    final h0 = s.crown * 0.95;
    final cejA = s.md / 2 * 0.72;
    final cejB = s.bl / 2 * 0.82;
    final List<(double dt, double dn, double a, double b, double lean)> roots =
        switch (s.roots) {
      1 => [(0.0, 0.0, cejA * 0.95, cejB * 0.95, 0.0)],
      2 => [
          (-cejA * 0.5, 0.0, cejA * 0.48, cejB * 0.9, -0.35),
          (cejA * 0.5, 0.0, cejA * 0.48, cejB * 0.9, 0.35),
        ],
      _ => [
          (-cejA * 0.45, cejB * 0.35, cejA * 0.45, cejB * 0.45, -0.3),
          (cejA * 0.45, cejB * 0.35, cejA * 0.45, cejB * 0.45, 0.3),
          (0.0, -cejB * 0.45, cejA * 0.5, cejB * 0.5, 0.0),
        ],
    };
    const hr = [0.0, 0.25, 0.5, 0.72, 0.88, 0.97];
    for (final (dt, dn, ra, rb, lean) in roots) {
      final rings = [
        for (final t in hr)
          _Ring(
            h: h0 + s.root * t,
            a: ra * (1 - 0.82 * math.pow(t, 1.35)),
            b: rb * (1 - 0.82 * math.pow(t, 1.35)),
            exponent: 2,
            offsetT: dt * (1 + lean.abs() * t) + lean * t * ra,
            offsetN: dn * (1 + 0.3 * t),
          ),
      ];
      _loftInto(b, f, rings, segs: 10, topCap: null,
          bottomCap: h0 + s.root, bottomOffsetT: rings.last.offsetT,
          bottomOffsetN: rings.last.offsetN);
    }
    return b.finish(MeshMaterial.root, lower: lower, tooth: s.number);
  }

  /// A threaded titanium post in place of the roots.
  static MeshPart _implant(ToothFrame f, {required bool lower}) {
    final s = f.spec;
    final h0 = s.crown * 0.9;
    final r = s.md * 0.2;
    final len = s.root * 0.85;
    const n = 14;
    final rings = [
      for (var i = 0; i <= n; i++)
        _Ring(
          h: h0 + len * i / n,
          a: r * (1 - 0.18 * i / n) * (i.isOdd ? 1.0 : 0.86),
          b: r * (1 - 0.18 * i / n) * (i.isOdd ? 1.0 : 0.86),
          exponent: 2,
        ),
    ];
    return _loft(f, rings, segs: 12, topCap: h0, bottomCap: h0 + len + r * 0.4,
        material: MeshMaterial.implant, lower: lower);
  }

  // ---------------------------------------------------------------- gums

  static MeshPart _gum(
    _Arch arch,
    List<(ToothSpec, double)> placed,
    List<double> contacts, {
    required bool upper,
  }) {
    final b = _MeshBuilder();
    final sorted = [...placed]..sort((a, b) => a.$2.compareTo(b.$2));
    final first = sorted.first;
    final last = sorted.last;
    final s0 = first.$2 - first.$1.md / 2 - 2;
    final s1 = last.$2 + last.$1.md / 2 + 2;
    final stations = <double>[];
    for (var s = s0; s < s1; s += 1.1) {
      stations.add(s);
    }
    stations.add(s1);
    final l = V3(0, upper ? 1 : -1, 0);

    (double, double) localSize(double s) {
      // Crown height and half-depth, blended between neighbouring teeth
      // so the gum runs smoothly.
      (double, double) of(ToothSpec t) => (t.crown, t.bl / 2 * 0.84);
      if (s <= sorted.first.$2) return of(sorted.first.$1);
      if (s >= sorted.last.$2) return of(sorted.last.$1);
      for (var i = 0; i < sorted.length - 1; i++) {
        final (a, sa) = sorted[i];
        final (b, sb) = sorted[i + 1];
        if (s >= sa && s <= sb) {
          final u = (s - sa) / (sb - sa);
          final t = u * u * (3 - 2 * u);
          final (ca, ba) = of(a);
          final (cb, bb) = of(b);
          return (ca + (cb - ca) * t, ba + (bb - ba) * t);
        }
      }
      return of(sorted.last.$1);
    }

    double papilla(double s) {
      var d = double.infinity;
      for (final c in contacts) {
        d = math.min(d, (c - s).abs());
      }
      return 2.3 * math.max(0, 1 - d / 1.7);
    }

    final profileLen = 13;
    final rings = <List<V3>>[];
    for (final s in stations) {
      final p = arch.point(s);
      final t = arch.tangent(s);
      final n = V3(-t.z, 0, t.x);
      final (crown, bh) = localSize(s);
      final base = V3(p.x, upper ? _gapHalf : -_gapHalf, p.z);
      final cej = crown;
      final m = cej - 0.7 - papilla(s);
      // Only the margin follows the papillae; the ridge above is smooth.
      final profile = <(double, double)>[
        (bh * 1.04, m),
        (bh * 1.1 + 0.5, cej + 1.0),
        (bh * 1.12 + 0.9, cej + 3.4),
        (bh + 1.0, cej + 6.2),
        (bh * 0.55, cej + 8.2),
        (0, cej + 8.8),
        (-bh * 0.55, cej + 8.2),
        (-bh - 1.0, cej + 6.2),
        (-bh * 1.12 - 0.9, cej + 3.4),
        (-bh * 1.1 - 0.5, cej + 1.0),
        (-bh * 1.04, m),
        (-bh * 0.8, cej + 0.6),
        (bh * 0.8, cej + 0.6),
      ];
      assert(profile.length == profileLen);
      rings.add([
        for (final (pn, ph) in profile) base + n * pn + l * ph,
      ]);
    }
    final idx = <List<int>>[
      for (final ring in rings) [for (final v in ring) b.add(v)],
    ];
    // Inside reference: the middle of each profile.
    V3 inner(int k) {
      final ring = rings[k];
      var c = const V3(0, 0, 0);
      for (final v in ring) {
        c = c + v;
      }
      return c * (1 / ring.length);
    }

    for (var k = 0; k < rings.length - 1; k++) {
      final mid = (inner(k) + inner(k + 1)) * 0.5;
      for (var j = 0; j < profileLen; j++) {
        final j1 = (j + 1) % profileLen;
        b.triOutward(idx[k][j], idx[k + 1][j], idx[k + 1][j1], mid);
        b.triOutward(idx[k][j], idx[k + 1][j1], idx[k][j1], mid);
      }
    }
    // End caps.
    for (final k in [0, rings.length - 1]) {
      final c = b.add(inner(k));
      final along = k == 0
          ? arch.tangent(stations.first) * -1
          : arch.tangent(stations.last);
      final ref = inner(k) - along;
      for (var j = 0; j < profileLen; j++) {
        b.triOutward(c, idx[k][j], idx[k][(j + 1) % profileLen], ref);
      }
    }
    return b.finish(MeshMaterial.gum, lower: !upper);
  }

  // ---------------------------------------------------------------- loft

  static MeshPart _loft(
    ToothFrame f,
    List<_Ring> rings, {
    required int segs,
    required double? topCap,
    required double? bottomCap,
    required MeshMaterial material,
    required bool lower,
  }) {
    final b = _MeshBuilder();
    _loftInto(b, f, rings, segs: segs, topCap: topCap, bottomCap: bottomCap);
    return b.finish(material, lower: lower, tooth: f.spec.number);
  }

  /// Rings along the tooth's long axis joined into a tube, with optional
  /// caps (the biting surface on top, an apex at the bottom).
  static void _loftInto(
    _MeshBuilder b,
    ToothFrame f,
    List<_Ring> rings, {
    required int segs,
    required double? topCap,
    required double? bottomCap,
    double bottomOffsetT = 0,
    double bottomOffsetN = 0,
  }) {
    final idx = <List<int>>[];
    for (final r in rings) {
      final row = <int>[];
      for (var j = 0; j < segs; j++) {
        final th = 2 * math.pi * j / segs;
        final c = math.cos(th);
        final sn = math.sin(th);
        final e = 2 / r.exponent;
        final cx = c.sign * math.pow(c.abs(), e);
        final sy = sn.sign * math.pow(sn.abs(), e);
        final h = r.h + (r.lift?.call(th) ?? 0);
        row.add(b.add(f.base +
            f.axis * h +
            f.tangent * (r.a * cx + r.offsetT) +
            f.outward * (r.b * sy + r.offsetN)));
      }
      idx.add(row);
    }
    for (var i = 0; i < rings.length - 1; i++) {
      final midH = (rings[i].h + rings[i + 1].h) / 2;
      final center = f.base +
          f.axis * midH +
          f.tangent * ((rings[i].offsetT + rings[i + 1].offsetT) / 2) +
          f.outward * ((rings[i].offsetN + rings[i + 1].offsetN) / 2);
      for (var j = 0; j < segs; j++) {
        final j1 = (j + 1) % segs;
        b.triOutward(idx[i][j], idx[i + 1][j], idx[i + 1][j1], center);
        b.triOutward(idx[i][j], idx[i + 1][j1], idx[i][j1], center);
      }
    }
    if (topCap != null) {
      final r0 = rings.first;
      final c = b.add(f.base +
          f.axis * topCap +
          f.tangent * r0.offsetT +
          f.outward * r0.offsetN);
      final ref = f.base + f.axis * (rings.first.h + 3);
      for (var j = 0; j < segs; j++) {
        b.triOutward(c, idx[0][j], idx[0][(j + 1) % segs], ref);
      }
    }
    if (bottomCap != null) {
      final c = b.add(f.base +
          f.axis * bottomCap +
          f.tangent * bottomOffsetT +
          f.outward * bottomOffsetN);
      final ref = f.base + f.axis * (rings.last.h - 3);
      final last = idx.last;
      for (var j = 0; j < segs; j++) {
        b.triOutward(c, last[j], last[(j + 1) % segs], ref);
      }
    }
  }
}

class _Ring {
  const _Ring({
    required this.h,
    required this.a,
    required this.b,
    required this.exponent,
    this.lift,
    this.offsetT = 0,
    this.offsetN = 0,
  });

  /// Distance from the biting edge along the long axis.
  final double h;
  final double a;
  final double b;
  final double exponent;

  /// Extra height by angle (cusps on the biting surface).
  final double Function(double theta)? lift;
  final double offsetT;
  final double offsetN;
}

/// The dental arch as a parabola z = d(1 - (x/w)²), walked by arc length
/// from the midline (negative on the patient's right).
class _Arch {
  _Arch(this.w, this.d) {
    var s = 0.0;
    var px = 0.0, pz = d;
    _xs.add(0);
    _ss.add(0);
    for (var x = 0.05; x <= w * 1.2; x += 0.05) {
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
}

class _MeshBuilder {
  final List<double> _p = [];
  final List<int> _t = [];

  int add(V3 v) {
    _p
      ..add(v.x)
      ..add(v.y)
      ..add(v.z);
    return _p.length ~/ 3 - 1;
  }

  V3 _v(int i) => V3(_p[i * 3], _p[i * 3 + 1], _p[i * 3 + 2]);

  /// Adds a triangle wound so its normal points away from [inside].
  void triOutward(int a, int b, int c, V3 inside) {
    final va = _v(a), vb = _v(b), vc = _v(c);
    final n = (vb - va).cross(vc - va);
    final centroid = (va + vb + vc) * (1 / 3);
    if (n.dot(centroid - inside) >= 0) {
      _t..add(a)..add(b)..add(c);
    } else {
      _t..add(a)..add(c)..add(b);
    }
  }

  MeshPart finish(MeshMaterial material, {required bool lower, String? tooth}) {
    final pos = Float64List.fromList(_p);
    final nrm = Float64List(pos.length);
    for (var i = 0; i < _t.length; i += 3) {
      final a = _t[i], b = _t[i + 1], c = _t[i + 2];
      final n = (_v(b) - _v(a)).cross(_v(c) - _v(a));
      for (final k in [a, b, c]) {
        nrm[k * 3] += n.x;
        nrm[k * 3 + 1] += n.y;
        nrm[k * 3 + 2] += n.z;
      }
    }
    for (var i = 0; i < nrm.length; i += 3) {
      final l = math.sqrt(
          nrm[i] * nrm[i] + nrm[i + 1] * nrm[i + 1] + nrm[i + 2] * nrm[i + 2]);
      if (l > 0) {
        nrm[i] /= l;
        nrm[i + 1] /= l;
        nrm[i + 2] /= l;
      }
    }
    return MeshPart(
      positions: pos,
      normals: nrm,
      triangles: Int32List.fromList(_t),
      material: material,
      lower: lower,
      tooth: tooth,
    );
  }
}
