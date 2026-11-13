import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_anatomy.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_art.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_2d.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_model_shapes.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Odontogram in its "3D" style: both arches seen from the biting surface,
/// every tooth the top-view picture rendered from the 3D tooth model (crowns
/// only, mirrored for the left side), placed on a smooth symmetric arch
/// curve with a hair gap between neighbours. Findings tint the tooth and
/// colour its outline.
///
/// Same inputs and behaviour as the flat `ToothChartArches`. Currently
/// switched off by `kOdontogram3dEnabled`.
class ToothChartArches3d extends StatefulWidget {
  const ToothChartArches3d({
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
  State<ToothChartArches3d> createState() => _ToothChartArches3dState();
}

/// The crown-only arch pictures (tooth in its arch pose, seen from above,
/// 28 mm square), one per right-side tooth; left teeth mirror them.
class _ArchPictures extends ChangeNotifier {
  _ArchPictures._();
  static final instance = _ArchPictures._();

  final Map<int, ui.Image> _images = {};
  bool _started = false;
  Future<void>? _loading;

  ui.Image? of(int shapeKey) {
    final q = shapeKey ~/ 10, t = shapeKey % 10;
    return _images[(q == 2 ? 1 : (q == 3 ? 4 : q)) * 10 + t];
  }

  Future<void> ensureLoaded() {
    if (_started) return _loading ?? Future.value();
    _started = true;
    return _loading = () async {
      for (final q in const [1, 4]) {
        for (var t = 1; t <= 8; t++) {
          try {
            final data = await rootBundle.load(
              'assets/images/teeth/$q${t}_m_arch.webp',
            );
            final codec = await ui.instantiateImageCodec(
              data.buffer.asUint8List(),
            );
            _images[q * 10 + t] = (await codec.getNextFrame()).image;
            codec.dispose();
          } catch (_) {}
        }
      }
      notifyListeners();
    }();
  }
}

/// Loads the arch pictures (for tests that render off the real clock).
@visibleForTesting
Future<void> loadArchPictures3d() => _ArchPictures.instance.ensureLoaded();

class _ToothChartArches3dState extends State<ToothChartArches3d> {
  @override
  void initState() {
    super.initState();
    _ArchPictures.instance.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
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
        final layout = _Layout3d.of(w, child: widget.child);

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
                  if (hit != null) widget.onSelect(hit);
                },
                child: ListenableBuilder(
                  listenable: _ArchPictures.instance,
                  builder: (context, _) => CustomPaint(
                    size: Size(w, layout.height),
                    painter: _Painter3d(
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
            ),
            if (selTooth != null && selVisual != null) ...[
              const SizedBox(height: CruSpace.s12),
              _SelectedBar(
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

class _SelectedBar extends StatelessWidget {
  const _SelectedBar({
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

class _Slot3d {
  const _Slot3d({
    required this.number,
    required this.key,
    required this.center,
    required this.outline,
    required this.imageRect,
    required this.mirror,
    required this.pts,
  });

  final String number;
  final int key;
  final Offset center;
  final Path outline;
  final List<Offset> pts;

  /// Where the tooth's picture goes.
  final Rect imageRect;
  final bool mirror;

  _Slot3d shifted(Offset d) => _Slot3d(
    number: number,
    key: key,
    center: center + d,
    outline: outline.shift(d),
    imageRect: imageRect.shift(d),
    mirror: mirror,
    pts: [for (final p in pts) p + d],
  );
}

const double _gap3d = 26;

class _Layout3d {
  _Layout3d._({
    required this.height,
    required this.scale,
    required this.slots,
    required this.upperCenter,
    required this.lowerCenter,
    required this.gapMid,
    required this.upperTop,
    required this.lowerBottom,
  });

  final double height;
  final double scale;
  final List<_Slot3d> slots;
  final Offset upperCenter;
  final Offset lowerCenter;
  final double gapMid;
  final double upperTop;
  final double lowerBottom;

  static final Map<(double, bool), _Layout3d> _cache = {};

  factory _Layout3d.of(double width, {required bool child}) {
    final key = (width, child);
    final hit = _cache[key];
    if (hit != null) return hit;
    if (_cache.length > 24) _cache.clear();
    return _cache[key] = _build(width, child);
  }

  /// Milk teeth stand where the adult tooth of their position does.
  static int _shapeKey(String tooth) {
    if (tooth.length != 2) return 11;
    final q = tooth.codeUnitAt(0) - 48;
    final t = tooth.codeUnitAt(1) - 48;
    if (q >= 5) return (q - 4) * 10 + (t == 5 ? 6 : t);
    return q * 10 + t;
  }

  String? hitTest(Offset pos) {
    for (final s in slots) {
      if (s.outline.contains(pos)) return s.number;
    }
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

  static double _segDist(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
    final t = l2 == 0
        ? 0.0
        : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / l2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  /// Distance between two outlines in mm, 0 when they overlap.
  static double _polyDist(_Slot3d a, _Slot3d b) {
    for (final p in a.pts) {
      if (b.outline.contains(p)) return 0;
    }
    for (final p in b.pts) {
      if (a.outline.contains(p)) return 0;
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

    return math.min(near(a.pts, b.pts), near(b.pts, a.pts));
  }

  /// Places the teeth of one arch on a smooth symmetric curve: the curve
  /// runs through the mirror-averaged tooth centres; from the midline out,
  /// every tooth is slid along it until its outline just clears the
  /// previous one. The right side's positions are mirrored onto the left,
  /// so both sides match exactly. Pictures only move, never turn.
  static List<_Slot3d> _spread(List<_Slot3d> list) {
    const gap = 0.25; // mm
    final right = [for (final t in list.reversed) if (!t.mirror) t];
    final left = [for (final t in list) if (t.mirror) t];
    if (right.isEmpty) return list;

    // Mirror-averaged centres, midline outwards, x as distance from it.
    final n = math.max(right.length, left.length);
    final ctrl = <Offset>[];
    for (var k = 0; k < n; k++) {
      final pts = [
        if (k < right.length) Offset(-right[k].center.dx, right[k].center.dy),
        if (k < left.length) Offset(left[k].center.dx, left[k].center.dy),
      ];
      var sum = Offset.zero;
      for (final q in pts) {
        sum += q;
      }
      ctrl.add(sum / pts.length.toDouble());
    }
    final q = <Offset>[
      Offset(-ctrl.first.dx, ctrl.first.dy),
      Offset(0, ctrl.first.dy),
      ...ctrl,
      ctrl.last + (ctrl.last - ctrl[math.max(0, ctrl.length - 2)]) * 1.5,
      ctrl.last + (ctrl.last - ctrl[math.max(0, ctrl.length - 2)]) * 3,
    ];
    // Catmull-Rom through q[1..], sampled finely, with arc length.
    final curve = <Offset>[];
    for (var i = 1; i + 2 < q.length; i++) {
      final p0 = q[i - 1], p1 = q[i], p2 = q[i + 1], p3 = q[i + 2];
      for (var j = 0; j < 40; j++) {
        final t = j / 40, t2 = t * t, t3 = t2 * t;
        curve.add(
          (p1 * 2 +
                  (p2 - p0) * t +
                  (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 +
                  (p1 * 3 - p0 - p2 * 3 + p3) * t3) *
              0.5,
        );
      }
    }
    curve.add(q[q.length - 2]);
    final arc = <double>[0];
    for (var i = 1; i < curve.length; i++) {
      arc.add(arc.last + (curve[i] - curve[i - 1]).distance);
    }
    Offset at(double s) {
      if (s >= arc.last) return curve.last;
      var lo = 0, hi = arc.length - 1;
      while (hi - lo > 1) {
        final m = (lo + hi) ~/ 2;
        if (arc[m] <= s) {
          lo = m;
        } else {
          hi = m;
        }
      }
      final f = (s - arc[lo]) / (arc[hi] - arc[lo]);
      return Offset.lerp(curve[lo], curve[hi], f)!;
    }

    // One side's teeth placed at arc positions; [sign] is -1 for screen-left.
    List<double> positions(List<_Slot3d> side, double sign) {
      final out = <double>[];
      _Slot3d put(_Slot3d t, double s) {
        final c = at(s);
        return t.shifted(Offset(sign * c.dx, c.dy) - t.center);
      }

      _Slot3d? prev;
      var s = 0.0;
      for (var k = 0; k < side.length; k++) {
        bool clear(double v) {
          final t = put(side[k], v);
          if (prev == null) {
            final mirrored = _Slot3d(
              number: t.number,
              key: t.key,
              center: Offset(-t.center.dx, t.center.dy),
              pts: [for (final p in t.pts) Offset(-p.dx, p.dy)],
              outline: Path()
                ..addPolygon([for (final p in t.pts) Offset(-p.dx, p.dy)], true),
              imageRect: t.imageRect,
              mirror: t.mirror,
            );
            return _polyDist(t, mirrored) >= gap * 2;
          }
          return _polyDist(t, prev) >= gap;
        }

        var lo = s;
        while (!clear(lo) && lo < arc.last) {
          lo += 0.05;
        }
        var hi = lo, bot = math.max(s, lo - 0.05);
        // Bisection between the last overlapping and first clear position.
        if (clear(bot)) {
          hi = bot;
        } else {
          for (var i = 0; i < 12; i++) {
            final m = (bot + hi) / 2;
            if (clear(m)) {
              hi = m;
            } else {
              bot = m;
            }
          }
        }
        s = hi;
        out.add(s);
        prev = put(side[k], s);
      }
      return out;
    }

    final sr = positions(right, -1);
    // The left side takes the right side's arc positions (exact mirror).
    final placed = <String, _Slot3d>{};
    for (var k = 0; k < right.length; k++) {
      final c = at(sr[k]);
      placed[right[k].number] = right[k].shifted(
        Offset(-c.dx, c.dy) - right[k].center,
      );
    }
    for (var k = 0; k < left.length; k++) {
      final c = at(sr[math.min(k, sr.length - 1)]);
      placed[left[k].number] = left[k].shifted(
        Offset(c.dx, c.dy) - left[k].center,
      );
    }
    return [for (final t in list) placed[t.number]!];
  }

  static _Layout3d _build(double width, bool child) {
    const edgePad = 12.0;
    const top = 10.0;
    final childScale = child ? 0.82 : 1.0;
    final (upperTeeth, lowerTeeth) = ToothSpec.arches(child: child);

    // Raw (millimetre) slots of one arch, y down on screen. The outline and
    // picture box are in the picture's own frame (no flip); only the
    // tooth's place in the arch is flipped for the upper arch.
    List<_Slot3d> raw(List<String> list, bool upper) {
      final out = <_Slot3d>[];
      for (final t in list) {
        final shape = toothArchShapes[_shapeKey(t)];
        if (shape == null) continue;
        final c = Offset(
          shape.center.dx,
          upper ? -shape.center.dy : shape.center.dy,
        );
        final b = shape.imageBox;
        final pts = [for (final p in shape.outline) c + p * childScale];
        out.add(
          _Slot3d(
            number: t,
            key: _shapeKey(t),
            center: c,
            pts: pts,
            outline: Path()..addPolygon(pts, true),
            imageRect: Rect.fromCenter(
              center: c + b.center * childScale,
              width: b.width * childScale,
              height: b.height * childScale,
            ),
            mirror: shape.mirror,
          ),
        );
      }
      return out;
    }

    final upRaw = _spread(raw(upperTeeth, true));
    final lowRaw = _spread(raw(lowerTeeth, false));

    var half = 1.0;
    for (final s in [...upRaw, ...lowRaw]) {
      final b = s.outline.getBounds();
      half = math.max(half, math.max(b.left.abs(), b.right.abs()));
    }
    final room = math.min(width, 560.0) / 2 - edgePad;
    final scale = (room / half).clamp(2.2, 7.0);

    Rect boundsOf(List<_Slot3d> l) => l
        .map((s) => s.outline.getBounds())
        .reduce((a, b) => a.expandToInclude(b));
    final k = Matrix4.diagonal3Values(scale, scale, 1).storage;
    List<_Slot3d> scaled(List<_Slot3d> l) => [
      for (final s in l)
        _Slot3d(
          number: s.number,
          key: s.key,
          center: s.center * scale,
          outline: s.outline.transform(k),
          imageRect: Rect.fromLTRB(
            s.imageRect.left * scale,
            s.imageRect.top * scale,
            s.imageRect.right * scale,
            s.imageRect.bottom * scale,
          ),
          mirror: s.mirror,
          pts: [for (final p in s.pts) p * scale],
        ),
    ];
    final up = scaled(upRaw), low = scaled(lowRaw);
    final ub = boundsOf(up), lb = boundsOf(low);

    final midX = width / 2;
    final upShift = Offset(midX, top - ub.top);
    final upBottom = top + ub.height;
    final lowShift = Offset(midX, upBottom + _gap3d - lb.top);
    final lowBottom = upBottom + _gap3d + lb.height;

    Offset avg(List<_Slot3d> l) {
      var y = 0.0;
      for (final s in l) {
        y += s.center.dy;
      }
      return Offset(0, y / l.length);
    }

    return _Layout3d._(
      height: lowBottom + top,
      scale: scale,
      slots: [
        for (final s in up) s.shifted(upShift),
        for (final s in low) s.shifted(lowShift),
      ],
      upperCenter: avg(up) + upShift,
      lowerCenter: avg(low) + lowShift,
      gapMid: upBottom + _gap3d / 2,
      upperTop: top,
      lowerBottom: lowBottom,
    );
  }
}

Color _darker3(Color c, double k) {
  final h = HSLColor.fromColor(c);
  return h.withLightness((h.lightness * k).clamp(0.0, 1.0)).toColor();
}

class _Painter3d extends CustomPainter {
  _Painter3d({
    required this.layout,
    required this.data,
    required this.layer,
    required this.selected,
    required this.numbering,
    required this.colors,
  });

  final _Layout3d layout;
  final ToothChartData data;
  final ChartLayer layer;
  final String? selected;
  final ToothNumbering numbering;
  final CruColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors;

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
    final side = CruType.micro.w600.tint(c.label3);
    _label(canvas, 'R', Offset(10, layout.gapMid), side);
    _label(canvas, 'L', Offset(size.width - 10, layout.gapMid), side);

    final lineColor = c.label3;
    final texts = <(_Slot3d, Color, Color)>[];
    final tex = _ArchPictures.instance;

    // Soft contact shadows first (subtle, same in both themes).
    for (final s in layout.slots) {
      if (data.of(s.number).look(layer).missing) continue;
      canvas.drawPath(
        s.outline.shift(const Offset(0, 1.5)),
        Paint()
          ..color = const Color(0x22000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
      );
    }

    for (final s in layout.slots) {
      final look = data.of(s.number).look(layer);
      if (look.missing) {
        dashPath(
          canvas,
          s.outline,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = lineColor.withValues(alpha: 0.7),
          dash: 3,
          gap: 2.5,
        );
        texts.add((s, c.label3.withValues(alpha: 0.55), c.surface));
        continue;
      }

      // The tooth's own picture (as-is in both themes).
      final img = tex.of(s.key);
      if (img != null) {
        canvas.save();
        if (s.mirror) {
          canvas.translate(s.imageRect.center.dx * 2, 0);
          canvas.scale(-1, 1);
        }
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          s.imageRect,
          Paint()..filterQuality = FilterQuality.medium,
        );
        canvas.restore();
      } else {
        canvas.drawPath(s.outline, Paint()..color = c.enamel);
      }

      // Findings: a soft tint inside the outline and a coloured outline.
      Color? found;
      var dashed = false;
      var edge = lineColor;
      if (look.decay.isNotEmpty) {
        found = c.caries;
        edge = _darker3(found, 0.75);
      } else if (look.filled.isNotEmpty || look.capped || look.rootCanal) {
        found = c.restoration;
        edge = _darker3(found, 0.75);
      } else if (look.planned.isNotEmpty) {
        found = c.accentTint;
        edge = c.accent;
        dashed = true;
      }
      if (found != null) {
        canvas.save();
        canvas.clipPath(s.outline);
        canvas.drawPath(
          s.outline,
          Paint()..color = found.withValues(alpha: dashed ? 0.35 : 0.5),
        );
        canvas.restore();
        final stroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 1.6
          ..color = edge;
        if (dashed) {
          dashPath(canvas, s.outline, stroke, dash: 3, gap: 2.5);
        } else {
          canvas.drawPath(s.outline, stroke);
        }
      }
      texts.add((s, const Color(0xFF2B2B2B), const Color(0xCCFFFFFF)));
    }

    for (final s in layout.slots) {
      if (s.number == selected) {
        ToothArt.ring(canvas, s.outline, c, selected: true, k: layout.scale);
      }
    }

    // Numbers on the teeth, with a light halo so they read over the pictures.
    final b = CruType.micro.w600.tabular;
    for (final (s, color, halo) in texts) {
      final box = s.outline.getBounds();
      final fs = (math.min(box.width, box.height) * 0.42).clamp(8.0, 12.0);
      final weight = s.number == selected ? FontWeight.w700 : b.fontWeight;
      final text = toothLabel(s.number, numbering);
      _label(
        canvas,
        text,
        box.center,
        TextStyle(
          fontFamily: b.fontFamily,
          fontSize: fs,
          fontWeight: weight,
          fontFeatures: b.fontFeatures,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = 2.4
            ..color = halo,
        ),
      );
      _label(
        canvas,
        text,
        box.center,
        b.copyWith(fontSize: fs, fontWeight: weight, color: color),
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
  bool shouldRepaint(covariant _Painter3d old) => true;
}
