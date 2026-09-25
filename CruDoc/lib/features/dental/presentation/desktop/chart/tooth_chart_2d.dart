import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_anatomy.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Both arches as a row of anatomical teeth (crowns and roots, to scale),
/// as the dentist faces the patient. Hover names a tooth, click selects
/// it, double-click (or Enter) opens it; arrow keys move between teeth.
class ToothChart2D extends StatefulWidget {
  const ToothChart2D({
    super.key,
    required this.data,
    required this.child,
    required this.mode,
    required this.selected,
    required this.onSelect,
    this.onOpen,
  });

  final ToothChartData data;

  /// Milk teeth instead of the adult set.
  final bool child;
  final ChartMode mode;
  final String? selected;
  final ValueChanged<String> onSelect;

  /// Double-click or Enter on a tooth.
  final ValueChanged<String>? onOpen;

  @override
  State<ToothChart2D> createState() => _ToothChart2DState();
}

class _ToothChart2DState extends State<ToothChart2D> {
  final FocusNode _focus = FocusNode(debugLabel: 'tooth chart 2D');
  String? _hover;
  bool _focused = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e, _Layout layout) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = e.logicalKey;
    final (upper, lower) = ToothSpec.arches(child: widget.child);
    final sel = widget.selected;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      if (sel != null) widget.onOpen?.call(sel);
      return KeyEventResult.handled;
    }
    String? next;
    if (sel == null || (!upper.contains(sel) && !lower.contains(sel))) {
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        next = upper.first;
      }
    } else {
      final row = upper.contains(sel) ? upper : lower;
      final other = upper.contains(sel) ? lower : upper;
      final i = row.indexOf(sel);
      if (key == LogicalKeyboardKey.arrowLeft && i > 0) next = row[i - 1];
      if (key == LogicalKeyboardKey.arrowRight && i < row.length - 1) {
        next = row[i + 1];
      }
      if ((key == LogicalKeyboardKey.arrowDown && row == upper) ||
          (key == LogicalKeyboardKey.arrowUp && row == lower)) {
        // The tooth in the other arch nearest across.
        final x = layout.slot(sel)!.cx;
        next = other.reduce((a, b) =>
            (layout.slot(a)!.cx - x).abs() <= (layout.slot(b)!.cx - x).abs()
                ? a
                : b);
      }
    }
    if (next == null) return KeyEventResult.ignored;
    widget.onSelect(next);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _Layout.of(constraints.maxWidth, child: widget.child);
        final hovered = _hover == null ? null : layout.slot(_hover!);
        return Focus(
          focusNode: _focus,
          onFocusChange: (f) => setState(() => _focused = f),
          onKeyEvent: (node, e) => _onKey(node, e, layout),
          child: Semantics(
            label: 'Tooth chart. Arrow keys move between teeth, Enter '
                'opens the selected tooth.',
            child: SizedBox(
              height: layout.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ChartPainter(
                        layout: layout,
                        data: widget.data,
                        mode: widget.mode,
                        selected: widget.selected,
                        hover: _hover,
                        focused: _focused,
                        colors: c,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: MouseRegion(
                      cursor: _hover == null
                          ? MouseCursor.defer
                          : SystemMouseCursors.click,
                      onHover: (e) {
                        final hit = layout.hitTest(e.localPosition);
                        if (hit != _hover) setState(() => _hover = hit);
                      },
                      onExit: (_) => setState(() => _hover = null),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) {
                          final hit = layout.hitTest(d.localPosition);
                          _focus.requestFocus();
                          if (hit != null) widget.onSelect(hit);
                        },
                        onDoubleTapDown: (d) {
                          final hit = layout.hitTest(d.localPosition);
                          if (hit != null) {
                            widget.onSelect(hit);
                            widget.onOpen?.call(hit);
                          }
                        },
                      ),
                    ),
                  ),
                  if (hovered != null)
                    _HoverLabel(
                      slot: hovered,
                      width: constraints.maxWidth,
                      visual: widget.data.of(hovered.number),
                      mode: widget.mode,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Where each tooth sits: scale (px per mm), the bite line and a slot
/// per tooth.
class _Layout {
  _Layout._(this.k, this.height, this.slots, this.labelTop, this.labelBottom);

  factory _Layout.of(double width, {required bool child}) {
    const pad = 8.0;
    const gapMm = 0.45;
    const labelH = 24.0;
    const bite = 12.0;
    final (upper, lower) = ToothSpec.arches(child: child);
    double rowMm(List<String> row) =>
        row.fold<double>(0, (s, n) => s + ToothSpec.of(n).md) +
        gapMm * (row.length - 1);
    final widest = math.max(rowMm(upper), rowMm(lower));
    final k = math.min((width - pad * 2) / widest, child ? 7.5 : 5.6);
    double longest(List<String> row) => row
        .map((n) => ToothSpec.of(n).crown + ToothSpec.of(n).root)
        .reduce(math.max);
    final upperOcc = labelH + longest(upper) * k;
    final lowerOcc = upperOcc + bite;
    final height = lowerOcc + longest(lower) * k + labelH;
    final slots = <_Slot>[];
    void place(List<String> row, double occ, bool isUpper) {
      var x = (width - rowMm(row) * k) / 2;
      for (final n in row) {
        final s = ToothSpec.of(n);
        final w = s.md * k;
        final len = (s.crown + s.root) * k;
        slots.add(_Slot(
          number: n,
          spec: s,
          cx: x + w / 2,
          occ: occ,
          upper: isUpper,
          hit: isUpper
              ? Rect.fromLTRB(x - gapMm * k / 2, occ - len, x + w + gapMm * k / 2, occ + bite / 2)
              : Rect.fromLTRB(x - gapMm * k / 2, occ - bite / 2, x + w + gapMm * k / 2, occ + len),
        ));
        x += w + gapMm * k;
      }
    }

    place(upper, upperOcc, true);
    place(lower, lowerOcc, false);
    return _Layout._(k, height, slots, labelH / 2, height - labelH / 2);
  }

  final double k;
  final double height;
  final List<_Slot> slots;

  /// Centre lines of the number labels above and below the teeth.
  final double labelTop;
  final double labelBottom;

  _Slot? slot(String n) {
    for (final s in slots) {
      if (s.number == n) return s;
    }
    return null;
  }

  String? hitTest(Offset p) {
    for (final s in slots) {
      if (s.hit.contains(p)) return s.number;
    }
    // The number labels select their tooth too.
    for (final s in slots) {
      final y = s.upper ? labelTop : labelBottom;
      if ((p.dy - y).abs() < 12 && (p.dx - s.cx).abs() < s.hit.width / 2) {
        return s.number;
      }
    }
    return null;
  }
}

class _Slot {
  const _Slot({
    required this.number,
    required this.spec,
    required this.cx,
    required this.occ,
    required this.upper,
    required this.hit,
  });

  final String number;
  final ToothSpec spec;
  final double cx;

  /// The biting edge's y.
  final double occ;
  final bool upper;
  final Rect hit;
}

/// Outlines of one tooth, drawn biting edge up at y = 0 with the roots
/// going down (upper teeth are flipped when painted).
class _ToothPaths {
  _ToothPaths(ToothSpec s, double k) {
    final mw = s.md * k / 2;
    final ch = s.crown * k;
    final rl = s.root * k;
    final cw = mw *
        switch (s.kind) {
          ToothKind.centralIncisor => 0.7,
          ToothKind.lateralIncisor => 0.68,
          ToothKind.canine => 0.66,
          ToothKind.premolar => 0.7,
          ToothKind.molar => 0.8,
        };
    final occlusal = switch (s.kind) {
      ToothKind.centralIncisor || ToothKind.lateralIncisor => [
          Offset(-mw * 0.95, ch * 0.09),
          Offset(-mw * 0.5, ch * 0.01),
          Offset(0, 0),
          Offset(mw * 0.5, ch * 0.01),
          Offset(mw * 0.95, ch * 0.06),
        ],
      ToothKind.canine => [
          Offset(-mw * 0.9, ch * 0.3),
          Offset(-mw * 0.42, ch * 0.12),
          Offset(0, 0),
          Offset(mw * 0.42, ch * 0.13),
          Offset(mw * 0.9, ch * 0.32),
        ],
      ToothKind.premolar => [
          Offset(-mw * 0.9, ch * 0.22),
          Offset(-mw * 0.48, ch * 0.05),
          Offset(0, 0),
          Offset(mw * 0.48, ch * 0.05),
          Offset(mw * 0.9, ch * 0.22),
        ],
      ToothKind.molar => [
          Offset(-mw * 0.93, ch * 0.18),
          Offset(-mw * 0.5, ch * 0.01),
          Offset(-mw * 0.04, ch * 0.11),
          Offset(mw * 0.42, 0),
          Offset(mw * 0.9, ch * 0.17),
        ],
    };
    crown = _smooth([
      Offset(-cw, ch),
      Offset(-mw * 0.97, ch * 0.62),
      Offset(-mw, ch * 0.34),
      ...occlusal,
      Offset(mw, ch * 0.34),
      Offset(mw * 0.97, ch * 0.62),
      Offset(cw, ch),
      Offset(cw * 0.45, ch * 1.07),
      Offset(0, ch * 1.09),
      Offset(-cw * 0.45, ch * 1.07),
    ]);

    // Roots: one tapering root, or two (three for upper molars: the
    // palatal one shows faintly between them).
    final top = ch * 0.92;
    if (s.roots == 1) {
      roots = [
        _smooth([
          Offset(-cw * 0.98, top),
          Offset(-cw * 0.86, ch + rl * 0.35),
          Offset(-cw * 0.55, ch + rl * 0.76),
          Offset(-cw * 0.14, ch + rl * 0.985),
          Offset(0, ch + rl),
          Offset(cw * 0.14, ch + rl * 0.985),
          Offset(cw * 0.55, ch + rl * 0.76),
          Offset(cw * 0.86, ch + rl * 0.35),
          Offset(cw * 0.98, top),
          Offset(0, ch * 0.8),
        ]),
      ];
      canals = [
        [Offset(0, ch * 0.55), Offset(0, ch + rl * 0.5), Offset(0, ch + rl * 0.94)],
      ];
      apexes = [Offset(0, ch + rl)];
    } else {
      final splay = s.kind == ToothKind.molar ? 1.0 : 0.6;
      final l = -cw * 0.52 * splay;
      final r = cw * 0.52 * splay;
      Path rootAt(double ax, double lean) => _smooth([
            Offset(ax - cw * 0.5, top),
            Offset(ax - cw * 0.46 + lean * 0.3, ch + rl * 0.45),
            Offset(ax - cw * 0.22 + lean, ch + rl * 0.9),
            Offset(ax + lean, ch + rl),
            Offset(ax + cw * 0.2 + lean, ch + rl * 0.9),
            Offset(ax + cw * 0.34 + lean * 0.3, ch + rl * 0.45),
            Offset(ax + cw * 0.42, top),
          ]);
      roots = [
        if (s.roots == 3) rootAt(0, 0),
        rootAt(l, -cw * 0.12 * splay),
        rootAt(r, cw * 0.12 * splay),
      ];
      canals = [
        [Offset(l * 0.6, ch * 0.6), Offset(l - cw * 0.05, ch + rl * 0.5), Offset(l - cw * 0.12 * splay, ch + rl * 0.93)],
        [Offset(r * 0.6, ch * 0.6), Offset(r + cw * 0.05, ch + rl * 0.5), Offset(r + cw * 0.12 * splay, ch + rl * 0.93)],
      ];
      apexes = [
        Offset(l - cw * 0.12 * splay, ch + rl),
        Offset(r + cw * 0.12 * splay, ch + rl),
      ];
    }

    implant = Path()
      ..moveTo(-cw * 0.78, top)
      ..lineTo(-cw * 0.62, ch + rl * 0.86)
      ..quadraticBezierTo(0, ch + rl * 1.02, cw * 0.62, ch + rl * 0.86)
      ..lineTo(cw * 0.78, top)
      ..close();
    implantThreads = [
      for (var i = 1; i <= 7; i++)
        () {
          final y = top + (ch + rl * 0.84 - top) * i / 8;
          final t = (y - top) / (ch + rl * 0.86 - top);
          final half = cw * (0.78 - 0.16 * t);
          return (Offset(-half, y), Offset(half, y + rl * 0.03));
        }(),
    ];

    final crownMid = ch * (s.kind == ToothKind.molar || s.kind == ToothKind.premolar ? 0.3 : 0.32);
    decay = Rect.fromCenter(
      center: Offset(-mw * 0.18, crownMid),
      width: mw * 0.62,
      height: ch * 0.2,
    );
    filling = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(0, crownMid), width: mw * 0.95, height: ch * 0.26),
      Radius.circular(mw * 0.25),
    );
    crack = [
      Offset(-mw * 0.55, ch * 0.08),
      Offset(-mw * 0.2, ch * 0.24),
      Offset(-mw * 0.35, ch * 0.34),
      Offset(mw * 0.05, ch * 0.5),
    ];
    this.ch = ch;
    this.rl = rl;
  }

  late final Path crown;
  late final List<Path> roots;
  late final List<List<Offset>> canals;
  late final List<Offset> apexes;
  late final Path implant;
  late final List<(Offset, Offset)> implantThreads;
  late final Rect decay;
  late final RRect filling;
  late final List<Offset> crack;
  late final double ch;
  late final double rl;

  /// A smooth closed outline through [p] (Catmull-Rom).
  static Path _smooth(List<Offset> p) {
    final path = Path()..moveTo(p[0].dx, p[0].dy);
    final n = p.length;
    for (var i = 0; i < n; i++) {
      final p0 = p[(i - 1 + n) % n];
      final p1 = p[i];
      final p2 = p[(i + 1) % n];
      final p3 = p[(i + 2) % n];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path..close();
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.layout,
    required this.data,
    required this.mode,
    required this.selected,
    required this.hover,
    required this.focused,
    required this.colors,
  });

  final _Layout layout;
  final ToothChartData data;
  final ChartMode mode;
  final String? selected;
  final String? hover;
  final bool focused;
  final CruColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors;
    // The bite line.
    final upperOcc = layout.slots.first.occ;
    final lowerOcc = layout.slots.last.occ;
    final midY = (upperOcc + lowerOcc) / 2;
    canvas.drawLine(
      Offset(8, midY),
      Offset(size.width - 8, midY),
      Paint()
        ..color = c.separator
        ..strokeWidth = 1,
    );
    // Midline between the central incisors.
    canvas.drawLine(
      Offset(size.width / 2, upperOcc - 6),
      Offset(size.width / 2, lowerOcc + 6),
      Paint()
        ..color = c.separator
        ..strokeWidth = 1,
    );

    for (final slot in layout.slots) {
      final v = data.of(slot.number);
      final dim = mode == ChartMode.plan && !v.isPlanned;
      canvas.save();
      canvas.translate(slot.cx, slot.occ);
      if (slot.upper) canvas.scale(1, -1);
      if (slot.number == hover && slot.number != selected) {
        // Lift the hovered tooth towards the bite.
        canvas.translate(0, -2);
      }
      if (dim) {
        canvas.saveLayer(null, Paint()..color = const Color(0x66000000));
      }
      _paintTooth(canvas, slot, v);
      if (dim) canvas.restore();
      canvas.restore();
    }

    for (final slot in layout.slots) {
      _paintNumber(canvas, slot);
    }
  }

  void _paintTooth(Canvas canvas, _Slot slot, ToothVisual v) {
    final c = colors;
    final p = _ToothPaths(slot.spec, layout.k);
    final bounds = Rect.fromLTRB(-slot.spec.md * layout.k / 2, 0,
        slot.spec.md * layout.k / 2, p.ch + p.rl);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = c.enamelEdge
      ..isAntiAlias = true;
    final isSel = slot.number == selected;
    final isHover = slot.number == hover;

    if (v.missing) {
      // A ghost of the tooth that was there.
      final ghost = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = c.label3;
      for (final r in p.roots) {
        _dashed(canvas, r, ghost);
      }
      _dashed(canvas, p.crown, ghost);
      if (v.implant) _paintImplant(canvas, p);
      _paintRings(canvas, p, isSel, isHover, v);
      return;
    }

    final faded = v.state == ToothState.notErupted;
    if (faded) {
      canvas.saveLayer(null, Paint()..color = const Color(0x80000000));
    }

    // Roots.
    if (v.implant) {
      _paintImplant(canvas, p);
    } else {
      final rootFill = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, p.ch),
          Offset(0, p.ch + p.rl),
          [c.toothRoot, Color.lerp(c.toothRoot, c.enamelShade, 0.55)!],
        );
      for (var i = 0; i < p.roots.length; i++) {
        final r = p.roots[i];
        final back = slot.spec.roots == 3 && i == 0;
        canvas.drawPath(
          r,
          back
              ? (Paint()..color = Color.lerp(c.toothRoot, c.enamelShade, 0.7)!)
              : rootFill,
        );
        canvas.drawPath(r, edge);
      }
      if (v.rootCanal) {
        final canal = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, layout.k * 0.32)
          ..strokeCap = StrokeCap.round
          ..color = c.greenText;
        for (final line in p.canals) {
          final path = Path()..moveTo(line[0].dx, line[0].dy);
          path.quadraticBezierTo(
              line[1].dx, line[1].dy, line[2].dx, line[2].dy);
          canvas.drawPath(path, canal);
        }
      }
    }

    // Crown: enamel, lit from the left.
    final crownRect = Rect.fromLTRB(bounds.left, 0, bounds.right, p.ch);
    canvas.drawPath(
      p.crown,
      Paint()
        ..shader = ui.Gradient.linear(
          crownRect.topCenter,
          crownRect.bottomCenter,
          [c.enamel, c.enamel, c.enamelShade],
          [0, 0.45, 1],
        ),
    );
    canvas.drawPath(
      p.crown,
      Paint()
        ..shader = ui.Gradient.linear(
          crownRect.centerLeft,
          crownRect.centerRight,
          [
            const Color(0x00FFFFFF),
            Colors.white.withValues(alpha: colors.isEvening ? 0.12 : 0.55),
            const Color(0x00FFFFFF),
            Colors.black.withValues(alpha: 0.07),
          ],
          [0, 0.3, 0.6, 1],
        ),
    );
    if (v.capped) {
      canvas.drawPath(
        p.crown,
        Paint()..color = c.greenTint.withValues(alpha: 0.85),
      );
    } else if (v.treatment == ToothTreatment.scaling) {
      canvas.drawPath(
        p.crown,
        Paint()..color = c.greenTint.withValues(alpha: 0.5),
      );
    }
    canvas.drawPath(p.crown, edge);
    if (v.capped) {
      canvas.drawPath(
        p.crown,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = c.greenText,
      );
    }

    // What was found.
    if (v.filled) {
      canvas.drawRRect(
        p.filling,
        Paint()..color = c.greenText.withValues(alpha: 0.35),
      );
      canvas.drawRRect(
        p.filling,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = c.greenText,
      );
    }
    if (v.decay) {
      canvas.drawOval(p.decay, Paint()..color = c.amberText.withValues(alpha: 0.35));
      canvas.drawOval(
        p.decay.deflate(p.decay.shortestSide * 0.22),
        Paint()..color = c.amberText.withValues(alpha: 0.85),
      );
    }
    if (v.fractured) {
      final crack = Path()..addPolygon(p.crack, false);
      canvas.drawPath(
        crack,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round
          ..color = c.amberText,
      );
    }
    if (v.condition == ToothCondition.impacted && v.treatment == null) {
      canvas.drawPath(
        p.crown,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = c.amberText,
      );
    }
    if (faded) canvas.restore();
    _paintRings(canvas, p, isSel, isHover, v);
  }

  /// Plan, hover and selection outlines.
  void _paintRings(
    Canvas canvas,
    _ToothPaths p,
    bool isSel,
    bool isHover,
    ToothVisual v,
  ) {
    final c = colors;
    if (v.isPlanned && mode == ChartMode.plan) {
      canvas.drawPath(p.crown, Paint()..color = c.accentTint.withValues(alpha: 0.7));
      _dashed(
        canvas,
        p.crown,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = c.accentText,
      );
    }
    if (isSel || isHover) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSel ? 2.2 : 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = isSel ? c.accent : c.accentText.withValues(alpha: 0.55);
      canvas.drawPath(p.crown, ring);
      for (final r in p.roots) {
        canvas.drawPath(r, ring);
      }
    }
  }

  void _paintImplant(Canvas canvas, _ToothPaths p) {
    final c = colors;
    canvas.drawPath(
      p.implant,
      Paint()
        ..shader = ui.Gradient.linear(
          p.implant.getBounds().centerLeft,
          p.implant.getBounds().centerRight,
          [c.implantMetal, Color.lerp(c.implantMetal, Colors.white, 0.45)!, c.implantMetal],
          [0, 0.4, 1],
        ),
    );
    final thread = Paint()
      ..strokeWidth = 1
      ..color = Color.lerp(c.implantMetal, Colors.black, 0.35)!;
    for (final (a, b) in p.implantThreads) {
      canvas.drawLine(a, b, thread);
    }
  }

  void _paintNumber(Canvas canvas, _Slot slot) {
    final c = colors;
    final v = data.of(slot.number);
    final isSel = slot.number == selected;
    final y = slot.upper ? layout.labelTop : layout.labelBottom;
    final Color fg;
    if (isSel) {
      fg = c.onAccent;
    } else if (mode == ChartMode.plan && v.isPlanned) {
      fg = c.accentText;
    } else {
      fg = switch (v.state) {
        ToothState.needsCare => c.amberText,
        ToothState.treated => c.greenText,
        ToothState.missing || ToothState.notErupted => c.label3,
        ToothState.healthy => c.label2,
      };
    }
    final tp = TextPainter(
      text: TextSpan(
        text: slot.number,
        style: CruType.caption.w600.tabular.tint(fg),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final center = Offset(slot.cx, y);
    if (isSel) {
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: tp.width + 12, height: 20),
        const Radius.circular(10),
      );
      canvas.drawRRect(r, Paint()..color = c.accent);
    } else if (focused && selected == null && slot.number == layout.slots.first.number) {
      // Where the arrow keys start.
      canvas.drawCircle(center, 11, Paint()
        ..style = PaintingStyle.stroke
        ..color = c.accentText.withValues(alpha: 0.5));
    }
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    // A dot marks work planned on this tooth (findings view).
    if (!isSel && mode == ChartMode.findings && v.isPlanned) {
      canvas.drawCircle(
        center + Offset(tp.width / 2 + 5, -tp.height / 2 + 2),
        2.5,
        Paint()..color = c.accent,
      );
    }
  }

  static void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 4, m.length)), paint);
        d += 7;
      }
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.layout.k != layout.k ||
      old.layout.slots.length != layout.slots.length ||
      old.data != data ||
      old.mode != mode ||
      old.selected != selected ||
      old.hover != hover ||
      old.focused != focused ||
      old.colors != colors;
}

/// The hovered tooth's name and state, above (or below) it.
class _HoverLabel extends StatelessWidget {
  const _HoverLabel({
    required this.slot,
    required this.width,
    required this.visual,
    required this.mode,
  });

  final _Slot slot;
  final double width;
  final ToothVisual visual;
  final ChartMode mode;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    const w = 220.0;
    final left =
        (slot.cx - w / 2).clamp(0.0, math.max(0.0, width - w)).toDouble();
    final detail = visual.callout(mode) ??
        (mode == ChartMode.plan ? 'Nothing planned' : 'No findings');
    final label = Container(
      width: w,
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s12,
        vertical: CruSpace.s8,
      ),
      decoration: ShapeDecoration(
        color: c.surface,
        shape: cruShape(CruRadius.control, side: BorderSide(color: c.hairline)),
        shadows: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${slot.number} · ${DentalChart.name(slot.number)}',
            style: CruType.caption.w600.tint(c.label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            detail,
            style: CruType.caption.tint(c.label2),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
    // Upper teeth: over the lower crowns; lower teeth: over the upper ones.
    const labelHeight = 44.0;
    return Positioned(
      left: left,
      top: slot.upper ? slot.occ + 18 : slot.occ - 18 - labelHeight,
      child: IgnorePointer(child: label),
    );
  }
}
