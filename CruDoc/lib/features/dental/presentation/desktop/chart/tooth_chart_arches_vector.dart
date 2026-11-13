import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_anatomy.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_art.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_2d.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_model_shapes.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The vector odontogram (drawn from the 3D model's outlines): kept for milk
/// teeth, which the odontogram pictures do not cover.
///
/// Odontogram view: both dental arches as if the mouth were opened flat, as
/// a line drawing: every tooth is its outline from the 3D model (grown to
/// nearly touch its neighbours) with its fissures and number inside, filled
/// solid in the finding's colour when something was found.
///
/// Upper arch on top with front teeth at the top of the screen; lower arch
/// below with front teeth at the bottom, a clear gap between them. The
/// patient's right side is on the left of the screen.
class ToothChartArchesVector extends StatefulWidget {
  const ToothChartArchesVector({
    super.key,
    required this.data,
    required this.child,
    required this.selected,
    required this.onSelect,
    this.onOpen,
    this.layer = ChartLayer.dental,
    this.numbering = ToothNumbering.fdi,
  });

  final ToothChartData data;
  final bool child;
  final String? selected;
  final ValueChanged<String> onSelect;
  final ValueChanged<String>? onOpen;
  final ChartLayer layer;
  final ToothNumbering numbering;

  @override
  State<ToothChartArchesVector> createState() => _ToothChartArchesVectorState();
}

class _ToothChartArchesVectorState extends State<ToothChartArchesVector> {
  @override
  Widget build(BuildContext context) {
    // If perio or endo layer, fall back to row chart as per brief
    if (widget.layer == ChartLayer.perio || widget.layer == ChartLayer.endo) {
      return ToothChart2D(
        data: widget.data,
        child: widget.child,
        selected: widget.selected,
        onSelect: widget.onSelect,
        onOpen: widget.onOpen,
        layer: widget.layer,
        numbering: widget.numbering,
      );
    }

    final c = context.cru;
    final selTooth = widget.selected;
    final selVisual = selTooth != null ? widget.data.of(selTooth) : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final layout = _ArchLayout.of(w, child: widget.child);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: layout.height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final hit = layout.hitTest(d.localPosition);
                  if (hit != null) {
                    widget.onSelect(hit);
                  }
                },
                child: CustomPaint(
                  size: Size(w, layout.height),
                  painter: _ArchesPainter(
                    layout: layout,
                    data: widget.data,
                    layer: widget.layer,
                    selected: widget.selected,
                    numbering: widget.numbering,
                    colors: c,
                  ),
                ),
              ),
            ),
            if (selTooth != null && selVisual != null) ...[
              const SizedBox(height: CruSpace.s12),
              ArchSelectedToothBar(
                fdi: selTooth,
                visual: selVisual,
                layer: widget.layer,
                numbering: widget.numbering,
                onOpen: () => (widget.onOpen ?? widget.onSelect)(selTooth),
              ),
            ],
          ],
        );
      },
    );
  }
}

class ArchSelectedToothBar extends StatelessWidget {
  const ArchSelectedToothBar({
    super.key,
    required this.fdi,
    required this.visual,
    required this.layer,
    required this.numbering,
    required this.onOpen,
  });

  final String fdi;
  final ToothVisual visual;
  final ChartLayer layer;
  final ToothNumbering numbering;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final numStr = toothLabel(fdi, numbering);
    final detail = visual.detail(layer) ?? 'Healthy';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s16,
        vertical: CruSpace.s10,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(CruRadius.panel),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${DentalChart.name(fdi)} ($numStr)',
                  style: CruType.subhead.w600.tint(c.label),
                ),
                const SizedBox(height: CruSpace.s2),
                Text(
                  detail,
                  style: CruType.caption.tint(c.label2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          CruCapsuleButton(label: 'Open', onPressed: onOpen),
        ],
      ),
    );
  }
}

class _ArchSlot {
  const _ArchSlot({
    required this.number,
    required this.center,
    required this.outline,
    required this.grooves,
    required this.rim,
    required this.label,
    required this.fontSize,
    required this.upper,
  });

  final String number;
  final Offset center;
  final Path outline;

  /// Occlusal fissures, in the same space as [outline] (painted clipped to it).
  final Path grooves;

  /// The thin band along the upper-left inside edge, catching the light.
  final Path rim;

  /// Where the tooth's number is centred: the middle of the tooth.
  final Offset label;
  final double fontSize;
  final bool upper;
}

/// Gap between the two arches.
const double _archGap = 26;

/// Wanted gap between neighbouring teeth, in logical pixels.
const double _toothGap = 1.5;

/// Largest a tooth is blown up from its model size to fill the arch.
const double _maxGrow = 1.7;

class _ArchLayout {
  _ArchLayout._({
    required this.width,
    required this.height,
    required this.scale,
    required this.slots,
    required this.upperCenter,
    required this.lowerCenter,
    required this.gapMid,
    required this.upperTop,
    required this.lowerBottom,
  });

  final double width;
  final double height;
  final double scale;
  final List<_ArchSlot> slots;

  /// The middle of each arch's opening (where "Upper" / "Lower" sit).
  final Offset upperCenter;
  final Offset lowerCenter;

  /// The y of the middle of the gap between the arches.
  final double gapMid;
  final double upperTop;
  final double lowerBottom;

  /// Number style: also used to size the numbers here.
  static TextStyle numberStyle() => CruType.micro.w600.tabular;

  String? hitTest(Offset pos) {
    for (final s in slots) {
      if (s.outline.contains(pos)) return s.number;
    }
    // Close to a tooth counts too (small targets, thin gaps).
    String? best;
    var bestD = 16.0;
    for (final s in slots) {
      final d = (s.center - pos).distance;
      if (d < bestD) {
        bestD = d;
        best = s.number;
      }
    }
    return best;
  }

  /// Milk teeth stand where the adult tooth of their position does (the
  /// second milk molar where the first adult molar is).
  static int _shapeKey(String tooth) {
    if (tooth.length != 2) return 11;
    final q = tooth.codeUnitAt(0) - 48;
    final t = tooth.codeUnitAt(1) - 48;
    if (q >= 5) return (q - 4) * 10 + (t == 5 ? 6 : t);
    return q * 10 + t;
  }

  static final Map<bool, Map<String, List<Offset>>> _packedCache = {};

  // Layouts are worked out once per width (the packing is not cheap).
  static final Map<(double, bool), _ArchLayout> _cache = {};

  factory _ArchLayout.of(double width, {required bool child}) {
    final key = (width, child);
    final hit = _cache[key];
    if (hit != null) return hit;
    if (_cache.length > 24) _cache.clear();
    return _cache[key] = _build(width, child);
  }

  static Offset _mid(List<Offset> pts) {
    var r = Rect.fromPoints(pts.first, pts.first);
    for (final p in pts) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r.center;
  }

  static List<Offset> _grow(List<Offset> pts, Offset o, double f) => [
    for (final p in pts) o + (p - o) * f,
  ];

  static double _segDist(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
    final ap = p - a;
    final t = l2 == 0
        ? 0.0
        : ((ap.dx * ab.dx + ap.dy * ab.dy) / l2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  /// True when the two outlines are at least [gap] apart.
  static bool _clear(List<Offset> a, List<Offset> b, double gap) {
    final pa = Path()..addPolygon(a, true);
    final pb = Path()..addPolygon(b, true);
    for (final p in a) {
      if (pb.contains(p)) return false;
    }
    for (final p in b) {
      if (pa.contains(p)) return false;
    }
    double near(List<Offset> pts, List<Offset> poly) {
      var m = double.infinity;
      for (final p in pts) {
        for (var i = 0; i < poly.length; i++) {
          m = math.min(m, _segDist(p, poly[i], poly[(i + 1) % poly.length]));
        }
      }
      return m;
    }

    return near(a, b) >= gap && near(b, a) >= gap;
  }

  /// The largest factor both teeth can be grown by (about their own
  /// middles) and still keep [gap] between them.
  static double _pairFactor(List<Offset> a, List<Offset> b, double gap) {
    final ca = _mid(a), cb = _mid(b);
    bool ok(double f) => _clear(_grow(a, ca, f), _grow(b, cb, f), gap);
    const lo0 = 0.6;
    if (!ok(lo0)) return lo0;
    if (ok(_maxGrow)) return _maxGrow;
    var lo = lo0, hi = _maxGrow;
    for (var i = 0; i < 10; i++) {
      final m = (lo + hi) / 2;
      if (ok(m)) {
        lo = m;
      } else {
        hi = m;
      }
    }
    return lo;
  }

  /// Every tooth grown as far as its two neighbours in the arch allow.
  static Map<String, List<Offset>> _packed(
    Map<String, List<Offset>> mm,
    List<List<String>> arches,
    double gap,
  ) {
    final out = <String, List<Offset>>{};
    for (final list in arches) {
      final f = {for (final t in list) t: _maxGrow};
      for (var i = 0; i + 1 < list.length; i++) {
        final a = list[i], b = list[i + 1];
        final fp = _pairFactor(mm[a]!, mm[b]!, gap);
        f[a] = math.min(f[a]!, fp);
        f[b] = math.min(f[b]!, fp);
      }
      // Then let each tooth take what its neighbours (as grown) still leave.
      List<Offset> shape(String t) => _grow(mm[t]!, _mid(mm[t]!), f[t]!);
      for (var sweep = 0; sweep < 2; sweep++) {
        for (var i = 0; i < list.length; i++) {
          final t = list[i];
          final others = [
            if (i > 0) shape(list[i - 1]),
            if (i + 1 < list.length) shape(list[i + 1]),
          ];
          final c = _mid(mm[t]!);
          bool ok(double g) =>
              others.every((o) => _clear(_grow(mm[t]!, c, g), o, gap));
          if (ok(_maxGrow)) {
            f[t] = _maxGrow;
            continue;
          }
          var lo = f[t]!, hi = _maxGrow;
          for (var k = 0; k < 9; k++) {
            final m = (lo + hi) / 2;
            if (ok(m)) {
              lo = m;
            } else {
              hi = m;
            }
          }
          f[t] = lo;
        }
      }
      for (final t in list) {
        out[t] = shape(t);
      }
    }
    return out;
  }

  /// Fissure pattern for a tooth as a filled shape: each groove is a smooth
  /// curve that tapers towards its ends. [at] maps (s, t) in -1..1 (s
  /// towards the distal end, t towards the cheek) to the screen.
  static Path _grooves(
    int digit,
    bool upper,
    Offset Function(double s, double t) at, {
    double width = 1.3,
  }) {
    final out = Path();

    // A smooth curve through the points (Catmull-Rom as Béziers), widened
    // into a thin leaf: thin at both ends, [width] across the middle.
    void groove(List<(double, double)> pts, {double k = 1}) {
      final p = [for (final (s, t) in pts) at(s * k, t)];
      final c = Path()..moveTo(p.first.dx, p.first.dy);
      for (var i = 0; i + 1 < p.length; i++) {
        final p0 = p[i > 0 ? i - 1 : i];
        final p1 = p[i], p2 = p[i + 1];
        final p3 = p[i + 2 < p.length ? i + 2 : i + 1];
        final a = p1 + (p2 - p0) / 6;
        final b = p2 - (p3 - p1) / 6;
        c.cubicTo(a.dx, a.dy, b.dx, b.dy, p2.dx, p2.dy);
      }
      for (final m in c.computeMetrics()) {
        const n = 16;
        final left = <Offset>[], right = <Offset>[];
        for (var i = 0; i <= n; i++) {
          final u = i / n;
          final tg = m.getTangentForOffset(m.length * u);
          if (tg == null) continue;
          final nrm = Offset(-tg.vector.dy, tg.vector.dx);
          final w = width * (0.3 + 0.7 * math.sin(math.pi * u)) / 2;
          left.add(tg.position + nrm * w);
          right.add(tg.position - nrm * w);
        }
        out.addPolygon([...left, ...right.reversed], true);
      }
    }

    switch (digit) {
      case 1:
      case 2:
        // Incisors: a soft arc parallel to the biting edge, and a faint
        // short curve on the tongue side.
        final w = digit == 1 ? 0.64 : 0.54;
        groove([(-w, 0.42), (-w / 2, 0.64), (w / 2, 0.64), (w, 0.42)]);
        groove([(-0.3, -0.5), (0, -0.62), (0.3, -0.5)], k: 0.9);
      case 3:
        // Canine: two soft arcs sweeping from the cusp tip to the corners.
        groove([(0.02, 0.5), (-0.25, 0.38), (-0.46, 0.1), (-0.56, -0.24)]);
        groove([(0.02, 0.5), (0.25, 0.38), (0.46, 0.1), (0.56, -0.24)]);
      case 4:
      case 5:
        // Premolars: a central groove bowed towards the tongue, ending in
        // small Y hooks at the mesial and distal pits.
        groove([
          (-0.56, 0.1),
          (-0.32, -0.04),
          (0, -0.14),
          (0.32, -0.04),
          (0.56, 0.1),
        ]);
        groove([(-0.56, 0.1), (-0.68, 0.3), (-0.72, 0.52)]);
        groove([(-0.56, 0.1), (-0.7, -0.08), (-0.78, -0.3)]);
        groove([(0.56, 0.1), (0.68, 0.3), (0.72, 0.52)]);
        groove([(0.56, 0.1), (0.7, -0.08), (0.78, -0.3)]);
        if (!upper && digit == 5) {
          groove([(0, -0.14), (0.04, -0.36), (-0.04, -0.6)]);
        }
      default:
        // Molars: a little smaller towards the back of the mouth.
        final k = digit == 6 ? 1.0 : (digit == 7 ? 0.94 : 0.88);
        if (upper) {
          // Wavy central groove, a buccal groove, a distal-oblique groove
          // (the oblique ridge between them stays unbroken) and pit hooks.
          groove([
            (-0.78, 0.1),
            (-0.5, -0.08),
            (-0.2, 0.1),
            (0.1, -0.05),
            (0.4, 0.08),
            (0.72, -0.1),
          ], k: k);
          groove([
            (-0.2, 0.1),
            (-0.26, 0.38),
            (-0.16, 0.6),
            (-0.22, 0.8),
          ], k: k);
          groove([
            (0.4, 0.08),
            (0.55, -0.22),
            (0.66, -0.48),
            (0.8, -0.7),
          ], k: k);
          groove([(-0.78, 0.1), (-0.74, 0.3), (-0.62, 0.42)], k: k);
          groove([(0.72, -0.1), (0.66, -0.3), (0.52, -0.4)], k: k);
        } else {
          // Zig-zag central groove, two buccal grooves and one lingual
          // groove curving out, and pit hooks.
          groove([
            (-0.82, 0),
            (-0.52, 0.12),
            (-0.2, -0.1),
            (0.15, 0.1),
            (0.46, -0.08),
            (0.82, 0.04),
          ], k: k);
          groove([
            (-0.2, -0.1),
            (-0.3, 0.2),
            (-0.24, 0.48),
            (-0.34, 0.72),
          ], k: k);
          groove([(0.15, 0.1), (0.22, 0.34), (0.13, 0.54), (0.2, 0.74)], k: k);
          groove([(-0.04, 0.0), (-0.02, -0.3), (0.06, -0.5), (0, -0.74)], k: k);
          groove([(-0.82, 0), (-0.74, -0.24), (-0.6, -0.36)], k: k);
          groove([(0.82, 0.04), (0.72, 0.28), (0.56, 0.38)], k: k);
        }
    }
    return out;
  }

  static _ArchLayout _build(double width, bool child) {
    const edgePad = 12.0;
    const top = 10.0;
    final childScale = child ? 0.82 : 1.0;
    final (upperTeeth, lowerTeeth) = ToothSpec.arches(child: child);

    // Outlines in millimetres, y down on screen.
    final mm = <String, List<Offset>>{};
    for (final upper in [true, false]) {
      for (final t in upper ? upperTeeth : lowerTeeth) {
        final shape = toothArchShapes[_shapeKey(t)];
        if (shape == null) continue;
        final c = Offset(
          shape.center.dx,
          upper ? -shape.center.dy : shape.center.dy,
        );
        mm[t] = [
          for (final p in shape.outline)
            c + Offset(p.dx, upper ? -p.dy : p.dy) * childScale,
        ];
      }
    }
    final arches = [
      upperTeeth.where(mm.containsKey).toList(),
      lowerTeeth.where(mm.containsKey).toList(),
    ];

    double halfOf(Map<String, List<Offset>> m) {
      var h = 0.0;
      for (final pts in m.values) {
        for (final p in pts) {
          h = math.max(h, p.dx.abs());
        }
      }
      return h;
    }

    // Grow the teeth until they nearly touch, then fit the chart to its box.
    final room = math.min(width, 560.0) / 2 - edgePad;
    // The packing is in millimetres, the same at any width: worked out once.
    final big = _packedCache[child] ??= _packed(mm, arches, _toothGap / 5.5);
    final scale = (room / halfOf(big)).clamp(2.2, 7.0);
    final midX = width / 2;

    // One arch, in its own space (x from the middle, y from 0).
    ({List<_ArchSlot> slots, Rect bounds, Offset centre}) arch(
      List<String> list,
      bool upper,
    ) {
      final paths = <String, Path>{
        for (final t in list)
          t: Path()..addPolygon([for (final p in big[t]!) p * scale], true),
      };
      final centers = {for (final t in list) t: _mid(big[t]!) * scale};
      var cy = 0.0;
      for (final t in list) {
        cy += centers[t]!.dy;
      }
      final centre = Offset(0, cy / list.length);

      final slots = <_ArchSlot>[];
      var bounds = Rect.zero;
      for (var i = 0; i < list.length; i++) {
        final t = list[i];
        // Along the arch here (left to right on screen).
        final prev = centers[list[i > 0 ? i - 1 : i]]!;
        final next = centers[list[i + 1 < list.length ? i + 1 : i]]!;
        var tan = next - prev;
        if (tan.distance < 1e-6) tan = const Offset(1, 0);
        tan = tan / tan.distance;
        if (tan.dx < 0) tan = -tan;
        final q = t.codeUnitAt(0) - 48;
        final screenLeft = q == 1 || q == 4 || q == 5 || q == 8;
        final u = screenLeft ? -tan : tan; // towards the distal end
        final v = upper ? Offset(tan.dy, -tan.dx) : Offset(-tan.dy, tan.dx);

        var minU = double.infinity, maxU = -double.infinity;
        var minV = double.infinity, maxV = -double.infinity;
        for (final p in big[t]!) {
          final w = p * scale;
          final pu = w.dx * u.dx + w.dy * u.dy;
          final pv = w.dx * v.dx + w.dy * v.dy;
          minU = math.min(minU, pu);
          maxU = math.max(maxU, pu);
          minV = math.min(minV, pv);
          maxV = math.max(maxV, pv);
        }
        final mu = (minU + maxU) / 2, mv = (minV + maxV) / 2;
        final hu = (maxU - minU) / 2 * 0.88, hv = (maxV - minV) / 2 * 0.88;
        Offset at(double s, double tt) =>
            u * (mu + s * hu) + v * (mv + tt * hv);

        final b = paths[t]!.getBounds();
        bounds = i == 0 ? b : bounds.expandToInclude(b);
        slots.add(
          _ArchSlot(
            number: t,
            center: centers[t]!,
            outline: paths[t]!,
            grooves: _grooves(_shapeKey(t) % 10, upper, at),
            rim: Path.combine(
              PathOperation.difference,
              paths[t]!,
              paths[t]!.shift(const Offset(1.6, 1.6)),
            ),
            label: b.center,
            fontSize: (math.min(b.width, b.height) * 0.5).clamp(8.0, 13.0),
            upper: upper,
          ),
        );
      }
      return (slots: slots, bounds: bounds, centre: centre);
    }

    final up = arch(arches[0], true);
    final low = arch(arches[1], false);

    // Stack: the upper arch, a gap, the lower arch.
    final upShift = Offset(midX, top - up.bounds.top);
    final upBottom = top + up.bounds.height;
    final lowShift = Offset(midX, upBottom + _archGap - low.bounds.top);
    final lowBottom = upBottom + _archGap + low.bounds.height;

    final slots = <_ArchSlot>[];
    for (final (list, shift) in [(up.slots, upShift), (low.slots, lowShift)]) {
      for (final s in list) {
        slots.add(
          _ArchSlot(
            number: s.number,
            center: s.center + shift,
            outline: s.outline.shift(shift),
            grooves: s.grooves.shift(shift),
            rim: s.rim.shift(shift),
            label: s.label + shift,
            fontSize: s.fontSize,
            upper: s.upper,
          ),
        );
      }
    }
    return _ArchLayout._(
      width: width,
      height: lowBottom + top,
      scale: scale,
      slots: slots,
      upperCenter: up.centre + upShift,
      lowerCenter: low.centre + lowShift,
      gapMid: upBottom + _archGap / 2,
      upperTop: top,
      lowerBottom: lowBottom,
    );
  }
}

/// What the odontogram laid out for a chart [width] pixels wide, for
/// tests: each tooth's outline, its number's box and the gap between arches.
@visibleForTesting
({List<(String, Path, Rect)> teeth, double gap, double height}) archChartLayout(
  double width, {
  bool child = false,
}) {
  final l = _ArchLayout.of(width, child: child);
  final style = _ArchLayout.numberStyle();
  Rect box(_ArchSlot s) {
    final tp = TextPainter(
      text: TextSpan(
        text: toothLabel(s.number, ToothNumbering.fdi),
        style: style.copyWith(fontSize: s.fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return Rect.fromCenter(center: s.label, width: tp.width, height: tp.height);
  }

  Rect bounds(bool upper) => l.slots
      .where((s) => s.upper == upper)
      .map((s) => s.outline.getBounds())
      .reduce((a, b) => a.expandToInclude(b));
  return (
    teeth: [for (final s in l.slots) (s.number, s.outline, box(s))],
    gap: bounds(false).top - bounds(true).bottom,
    height: l.height,
  );
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Color _darker(Color c, double k) {
  final h = HSLColor.fromColor(c);
  return h.withLightness((h.lightness * k).clamp(0.0, 1.0)).toColor();
}

Color _lighter(Color c, double t) {
  final h = HSLColor.fromColor(c);
  return h.withLightness(h.lightness + (1 - h.lightness) * t).toColor();
}

class _ArchesPainter extends CustomPainter {
  _ArchesPainter({
    required this.layout,
    required this.data,
    required this.layer,
    required this.selected,
    required this.numbering,
    required this.colors,
  });

  final _ArchLayout layout;
  final ToothChartData data;
  final ChartLayer layer;
  final String? selected;
  final ToothNumbering numbering;
  final CruColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors;

    // Midline ticks, above the upper arch and below the lower one.
    final mid = size.width / 2;
    final tick = Paint()
      ..color = c.separator
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(mid, layout.upperTop - 8),
      Offset(mid, layout.upperTop - 2),
      tick,
    );
    canvas.drawLine(
      Offset(mid, layout.lowerBottom + 2),
      Offset(mid, layout.lowerBottom + 8),
      tick,
    );

    final arch = CruType.groupLabel.tint(c.label3);
    _label(canvas, 'Upper', layout.upperCenter, arch);
    _label(canvas, 'Lower', layout.lowerCenter, arch);
    // Patient's right and left, in the gap between the arches.
    final side = CruType.micro.w600.tint(c.label3);
    _label(canvas, 'R', Offset(10, layout.gapMid), side);
    _label(canvas, 'L', Offset(size.width - 10, layout.gapMid), side);

    // Ivory-white to light-grey enamel with grey lines in both themes (a tooth
    // is tooth-coloured on a dark card too).
    final base = c.enamel;
    final lineColor = c.label3;
    final texts = <(_ArchSlot, Color, Color)>[];

    // Soft contact shadows first, so a neighbour's never lies over a tooth.
    final shadow = c.toothShadow.withValues(alpha: c.isEvening ? 0.6 : 0.22);
    for (final slot in layout.slots) {
      if (data.of(slot.number).look(layer).missing) continue;
      canvas.drawPath(
        slot.outline.shift(const Offset(0, 1.5)),
        Paint()
          ..color = shadow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.3),
      );
    }

    for (final slot in layout.slots) {
      final look = data.of(slot.number).look(layer);
      if (look.missing) {
        // Dashed outline only: no fill; its number stays, faded.
        dashPath(
          canvas,
          slot.outline,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = lineColor.withValues(alpha: 0.7),
          dash: 3,
          gap: 2.5,
        );
        texts.add((slot, c.label3.withValues(alpha: 0.55), c.surface));
        continue;
      }

      // What was found, the same colours the row chart and its legend use:
      // solid fill, a darker outline of the same colour.
      var fill = base;
      var edge = lineColor;
      var groove = lineColor.withValues(alpha: 0.8);
      var dashed = false;
      Color? found;
      if (look.decay.isNotEmpty) {
        found = c.caries;
        edge = _darker(found, 0.62);
      } else if (look.filled.isNotEmpty || look.capped || look.rootCanal) {
        found = c.restoration;
        edge = _darker(found, 0.62);
      } else if (look.planned.isNotEmpty) {
        found = c.accentTint;
        edge = c.accent;
        dashed = true;
      }
      if (found != null) {
        fill = found;
        groove = found.computeLuminance() > 0.45
            ? _darker(found, 0.7)
            : _lighter(found, 0.5);
      }

      // Lit from the top left: lighter there, a darker rim at the lower right.
      final box = slot.outline.getBounds();
      canvas.drawPath(
        slot.outline,
        Paint()
          ..shader = ui.Gradient.radial(
            box.topLeft + Offset(box.width * 0.3, box.height * 0.28),
            math.max(box.width, box.height) * 0.95,
            found == null
                ? [
                    c.toothGloss,
                    fill,
                    c.isEvening ? c.enamelMid : c.enamelShade,
                  ]
                : [_lighter(fill, 0.3), fill, _darker(fill, 0.8)],
            const [0, 0.5, 1],
          ),
      );
      canvas.save();
      canvas.clipPath(slot.outline);
      canvas.drawPath(
        slot.rim,
        Paint()..color = c.toothGloss.withValues(alpha: 0.55),
      );
      // Carved fissures: a dark line with a light edge on the side away from
      // the light.
      final gloss = found == null
          ? c.toothGloss.withValues(alpha: 0.95)
          : _lighter(fill, 0.6).withValues(alpha: 0.7);
      for (final (off, col) in [
        (const Offset(0.8, 0.8), gloss),
        (Offset.zero, groove),
      ]) {
        canvas.drawPath(slot.grooves.shift(off), Paint()..color = col);
      }
      canvas.restore();
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = found != null ? 1.2 : 1
        ..color = edge;
      if (dashed) {
        dashPath(canvas, slot.outline, stroke, dash: 3, gap: 2.5);
      } else {
        canvas.drawPath(slot.outline, stroke);
      }

      // Number colour with the best contrast on this fill.
      var text = c.label;
      for (final cand in [c.surface, c.canvas, c.onAccent, c.toothGloss]) {
        if (_contrast(cand, fill) > _contrast(text, fill)) text = cand;
      }
      if (found == null && slot.number == selected) text = c.accent;
      texts.add((slot, text, fill));
    }

    // Selection ring on top of the neighbours.
    for (final slot in layout.slots) {
      if (slot.number == selected) {
        ToothArt.ring(canvas, slot.outline, c, selected: true, k: layout.scale);
      }
    }

    // Numbers inside the teeth, with a halo so they read over the fissures.
    final b = _ArchLayout.numberStyle();
    for (final (slot, color, halo) in texts) {
      final weight = slot.number == selected ? FontWeight.w700 : b.fontWeight;
      final text = toothLabel(slot.number, numbering);
      _label(
        canvas,
        text,
        slot.label,
        TextStyle(
          fontFamily: b.fontFamily,
          fontSize: slot.fontSize,
          fontWeight: weight,
          fontFeatures: b.fontFeatures,
          height: b.height,
          letterSpacing: b.letterSpacing,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = 2.0
            ..color = halo,
        ),
      );
      _label(
        canvas,
        text,
        slot.label,
        b.copyWith(fontSize: slot.fontSize, fontWeight: weight, color: color),
      );
    }
  }

  void _label(Canvas canvas, String text, Offset center, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ArchesPainter old) => true;
}
