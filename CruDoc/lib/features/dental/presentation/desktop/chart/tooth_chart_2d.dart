import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_anatomy.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_art.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Which rows the chart draws.
enum ChartRows {
  /// Every tooth from the cheek side (with its roots) and from above.
  full,

  /// Biting surfaces only: a compact map of the mouth.
  occlusal,
}

/// Both arches as realistic teeth, as the dentist faces the patient: the
/// upper teeth from the cheek side (roots up) and from below, then the
/// lower teeth from above and from the cheek side. Hover names a tooth,
/// click picks it, double-click (or Enter) opens it; arrow keys move
/// between teeth.
class ToothChart2D extends StatefulWidget {
  const ToothChart2D({
    super.key,
    required this.data,
    required this.child,
    required this.selected,
    required this.onSelect,
    this.onOpen,
    this.layer = ChartLayer.dental,
    this.rows = ChartRows.full,
    this.maxScale,
    this.numbering = ToothNumbering.fdi,
  });

  final ToothChartData data;

  /// Milk teeth instead of the adult set.
  final bool child;
  final String? selected;

  /// Click on a tooth.
  final ValueChanged<String> onSelect;

  /// Double-click or Enter on a tooth. Without it a click acts at once
  /// and Enter picks the tooth.
  final ValueChanged<String>? onOpen;
  final ChartLayer layer;
  final ChartRows rows;

  /// Largest scale in pixels per millimetre.
  final double? maxScale;

  /// How tooth numbers are shown (ids stay FDI).
  final ToothNumbering numbering;

  @override
  State<ToothChart2D> createState() => _ToothChart2DState();
}

class _ToothChart2DState extends State<ToothChart2D> {
  final FocusNode _focus = FocusNode(debugLabel: 'tooth chart');
  String? _hover;
  bool _focused = false;
  _Layout? _layout;

  /// Where the arrow keys are when a click opens a tooth (so moving
  /// doesn't open every tooth on the way).
  String? _cursor;

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
    final moves = widget.onOpen == null;
    final sel = (moves ? _cursor : null) ?? widget.selected;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      if (sel != null) (widget.onOpen ?? widget.onSelect)(sel);
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
    if (moves) {
      setState(() => _cursor = next);
    } else {
      widget.onSelect(next);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return LayoutBuilder(
      builder: (context, constraints) {
        final perio = widget.layer.showsPerio && widget.data.perioExam != null;
        var layout = _layout;
        if (layout == null ||
            layout.width != constraints.maxWidth ||
            layout.child != widget.child ||
            layout.rows != widget.rows ||
            layout.perio != perio ||
            layout.maxK != widget.maxScale) {
          layout = _layout = _Layout.of(
            constraints.maxWidth,
            child: widget.child,
            rows: widget.rows,
            perio: perio,
            maxK: widget.maxScale,
          );
        }
        final l = layout;
        final hovered = _hover == null ? null : l.slot(_hover!);
        final open = widget.onOpen;
        return Focus(
          focusNode: _focus,
          onFocusChange: (f) => setState(() {
            _focused = f;
            if (!f) _cursor = null;
          }),
          onKeyEvent: (node, e) => _onKey(node, e, l),
          child: Semantics(
            label: 'Tooth chart. Arrow keys move between teeth, Enter '
                'opens the selected tooth.',
            child: SizedBox(
              height: l.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _TeethPainter(
                          layout: l,
                          data: widget.data,
                          layer: widget.layer,
                          colors: c,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _OverlayPainter(
                        layout: l,
                        data: widget.data,
                        layer: widget.layer,
                        selected: widget.selected,
                        hover: _hover ?? (_focused ? _cursor : null),
                        focused: _focused,
                        numbering: widget.numbering,
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
                        final hit = l.hitTest(e.localPosition);
                        if (hit != _hover) setState(() => _hover = hit);
                      },
                      onExit: (_) => setState(() => _hover = null),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) {
                          final hit = l.hitTest(d.localPosition);
                          _focus.requestFocus();
                          if (hit != null) {
                            _cursor = hit;
                            widget.onSelect(hit);
                          }
                        },
                        onDoubleTapDown: open == null
                            ? null
                            : (d) {
                                final hit = l.hitTest(d.localPosition);
                                if (hit != null) {
                                  widget.onSelect(hit);
                                  open(hit);
                                }
                              },
                      ),
                    ),
                  ),
                  if (hovered != null && widget.rows == ChartRows.full)
                    _HoverLabel(
                      slot: hovered,
                      layout: l,
                      visual: widget.data.of(hovered.number),
                      layer: widget.layer,
                      hasPerio: widget.data.perioExam != null,
                      numbering: widget.numbering,
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

// ================================================================ layout

/// Where everything sits: the scale, each tooth's views, the number and
/// perio rows.
class _Layout {
  _Layout._({
    required this.width,
    required this.child,
    required this.rows,
    required this.perio,
    required this.maxK,
    required this.k,
    required this.height,
    required this.slots,
    required this.numberTop,
    required this.numberBottom,
    required this.perioTop,
    required this.perioBottom,
    required this.lingualUpper,
    required this.lingualLower,
    required this.biteY,
    required this.side,
  });

  factory _Layout.of(
    double width, {
    required bool child,
    required ChartRows rows,
    required bool perio,
    double? maxK,
  }) {
    final full = rows == ChartRows.full;
    final side = full ? 24.0 : 6.0;
    const gapMm = 0.35;
    final (upper, lower) = ToothSpec.arches(child: child);
    double rowMm(List<String> r) =>
        r.fold<double>(0, (s, n) => s + ToothSpec.of(n).md) + gapMm * (r.length - 1);
    final widest = math.max(rowMm(upper), rowMm(lower));
    final k = math.max(
      1.0,
      math.min((width - side * 2) / widest, maxK ?? (child ? 7.4 : 6.4)),
    );
    double longest(List<String> r) => r
        .map((n) => ToothSpec.of(n).crown + ToothSpec.of(n).root)
        .reduce(math.max);
    double deepest(List<String> r) =>
        r.map((n) => ToothSpec.of(n).bl).reduce(math.max);

    final numberH = full ? 26.0 : 20.0;
    final perioH = perio && full ? 18.0 : 0.0;
    final bite = full ? 24.0 : 12.0;
    const between = 10.0;

    var y = 0.0;
    final numberTop = y + numberH / 2;
    y += numberH;
    final perioTop = y + perioH / 2;
    y += perioH;
    var upperEdge = 0.0;
    if (full) {
      y += longest(upper) * k;
      upperEdge = y;
      y += between;
    }
    final upperOcc = y + deepest(upper) * k / 2;
    y += deepest(upper) * k;
    final lingualUpper = y + perioH / 2;
    y += perioH;
    final biteY = y + bite / 2;
    y += bite;
    final lingualLower = y + perioH / 2;
    y += perioH;
    final lowerOcc = y + deepest(lower) * k / 2;
    y += deepest(lower) * k;
    var lowerEdge = 0.0;
    if (full) {
      y += between;
      lowerEdge = y;
      y += longest(lower) * k;
    }
    final perioBottom = y + perioH / 2;
    y += perioH;
    final numberBottom = y + numberH / 2;
    y += numberH;
    final height = y;

    final slots = <_Slot>[];
    void place(List<String> row, bool isUpper) {
      var x = (width - rowMm(row) * k) / 2;
      for (final n in row) {
        final s = ToothSpec.of(n);
        final w = s.md * k;
        final cx = x + w / 2;
        slots.add(_Slot(
          number: n,
          spec: s,
          cx: cx,
          upper: isUpper,
          buccal: full
              ? BuccalShape.of(s, k: k, cx: cx, edgeY: isUpper ? upperEdge : lowerEdge)
              : null,
          occlusal: OcclusalShape.of(
            s,
            k: k,
            center: Offset(cx, isUpper ? upperOcc : lowerOcc),
          ),
          hit: isUpper
              ? Rect.fromLTRB(x - gapMm * k / 2, 0, x + w + gapMm * k / 2, biteY)
              : Rect.fromLTRB(x - gapMm * k / 2, biteY, x + w + gapMm * k / 2, height),
        ));
        x += w + gapMm * k;
      }
    }

    place(upper, true);
    place(lower, false);
    return _Layout._(
      width: width,
      child: child,
      rows: rows,
      perio: perio,
      maxK: maxK,
      k: k,
      height: height,
      slots: slots,
      numberTop: numberTop,
      numberBottom: numberBottom,
      perioTop: perioTop,
      perioBottom: perioBottom,
      lingualUpper: lingualUpper,
      lingualLower: lingualLower,
      biteY: biteY,
      side: side,
    );
  }

  final double width;
  final bool child;
  final ChartRows rows;
  final bool perio;
  final double? maxK;
  final double k;
  final double height;
  final List<_Slot> slots;
  final double numberTop;
  final double numberBottom;
  final double perioTop;
  final double perioBottom;
  final double lingualUpper;
  final double lingualLower;
  final double biteY;
  final double side;

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
    return null;
  }
}

class _Slot {
  const _Slot({
    required this.number,
    required this.spec,
    required this.cx,
    required this.upper,
    required this.buccal,
    required this.occlusal,
    required this.hit,
  });

  final String number;
  final ToothSpec spec;
  final double cx;
  final bool upper;

  /// Null on the compact (biting surfaces only) chart.
  final BuccalShape? buccal;
  final OcclusalShape occlusal;
  final Rect hit;
}

// ============================================================== painters

/// The teeth, and the perio readings on them. Repaints only when the
/// data, layer or size changes.
class _TeethPainter extends CustomPainter {
  _TeethPainter({
    required this.layout,
    required this.data,
    required this.layer,
    required this.colors,
  });

  final _Layout layout;
  final ToothChartData data;
  final ChartLayer layer;
  final CruColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors;
    final full = layout.rows == ChartRows.full;
    // The midline, and which side is the patient's right.
    final mid = size.width / 2;
    canvas.drawLine(
      Offset(mid, layout.numberTop + 12),
      Offset(mid, layout.numberBottom - 12),
      Paint()
        ..color = c.separator
        ..strokeWidth = 1,
    );
    if (full) {
      _text(canvas, 'R', Offset(layout.side / 2, layout.biteY), CruType.caption.w600.tint(c.label3));
      _text(canvas, 'L', Offset(size.width - layout.side / 2, layout.biteY), CruType.caption.w600.tint(c.label3));
    }

    for (final s in layout.slots) {
      final v = data.of(s.number);
      final look = v.look(layer);
      if (s.buccal != null) ToothArt.buccal(canvas, s.buccal!, look, c);
      ToothArt.occlusal(canvas, s.occlusal, look, c);
    }
    _bridges(canvas);
    if (layout.perio && full) _perio(canvas);
  }

  /// Connectors between neighbouring bridge units.
  void _bridges(Canvas canvas) {
    final c = colors;
    for (var i = 0; i < layout.slots.length - 1; i++) {
      final a = layout.slots[i], b = layout.slots[i + 1];
      if (a.upper != b.upper) continue;
      if (data.of(a.number).treatment != ToothTreatment.bridge ||
          data.of(b.number).treatment != ToothTreatment.bridge) {
        continue;
      }
      final k = layout.k;
      void bar(Offset from, Offset to) {
        final r = RRect.fromRectAndRadius(
          Rect.fromPoints(from, to).inflate(k * 0.9),
          Radius.circular(k),
        );
        canvas.drawRRect(r, Paint()..color = c.restoration);
        canvas.drawRRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = c.greenText.withValues(alpha: 0.75),
        );
      }

      if (a.buccal != null && b.buccal != null) {
        final y = (a.buccal!.crownRect.center.dy + b.buccal!.crownRect.center.dy) / 2;
        bar(Offset(a.buccal!.crownRect.right - k * 0.6, y), Offset(b.buccal!.crownRect.left + k * 0.6, y));
      }
      final y = a.occlusal.rect.center.dy;
      bar(Offset(a.occlusal.rect.right - k * 0.4, y), Offset(b.occlusal.rect.left + k * 0.4, y));
    }
  }

  /// Gum line, pockets, bleeding and furcations from the latest exam, and
  /// the pocket depths in rows above, between and below the teeth.
  void _perio(Canvas canvas) {
    final c = colors;
    final k = layout.k;
    for (final upper in const [true, false]) {
      final row = layout.slots.where((s) => s.upper == upper);
      var line = <Offset>[];
      final bled = <Offset>[];
      for (final s in row) {
        final v = data.of(s.number);
        final p = v.perio;
        final b = s.buccal!;
        if (p == null ||
            !v.charted ||
            v.missing ||
            v.impacted ||
            v.state == ToothState.notErupted) {
          ToothArt.gumLine(canvas, line, c);
          line = [];
          continue;
        }
        // Model order distal, middle, mesial = perio sites DB, B, MB.
        const idx = [2, 1, 0];
        final g = ToothArt.pockets(
          canvas,
          b,
          c,
          pd: [for (final i in idx) p.pd[i]],
          rec: [for (final i in idx) p.rec[i]],
          bop: [for (final i in idx) p.bop[i]],
          furcation: p.furcation,
        );
        line.addAll(g.margin);
        bled.addAll(g.bleeding);
        // Depths: cheek side above/below the teeth, tongue side by the
        // biting surfaces. Narrow teeth show only their deepest site.
        final cheekY = upper ? layout.perioTop : layout.perioBottom;
        final tongueY = upper ? layout.lingualUpper : layout.lingualLower;
        if (s.spec.md * k < 34) {
          _depth(canvas, _deepest(p.pd.take(3)), Offset(s.cx, cheekY));
          _depth(canvas, _deepest(p.pd.skip(3)), Offset(s.cx, tongueY));
        } else {
          for (var i = 0; i < 3; i++) {
            _depth(canvas, p.pd[idx[i]], Offset(b.site(i).dx, cheekY));
            final x = s.occlusal.at(const [-0.62, 0.0, 0.62][i], 0).dx;
            _depth(canvas, p.pd[3 + idx[i]], Offset(x, tongueY));
          }
        }
      }
      ToothArt.gumLine(canvas, line, c);
      ToothArt.bleeding(canvas, bled, c);
    }
  }

  static int? _deepest(Iterable<int?> pds) {
    int? out;
    for (final d in pds) {
      if (d != null && (out == null || d > out)) out = d;
    }
    return out;
  }

  void _depth(Canvas canvas, int? pd, Offset at) {
    final c = colors;
    final deep = (pd ?? 0) >= 4;
    var style = CruType.micro.tabular.tint(deep ? c.amberText : c.label3);
    if ((pd ?? 0) >= 6) style = style.w600;
    _text(canvas, pd == null ? '·' : '$pd', at, style);
  }

  @override
  bool shouldRepaint(_TeethPainter old) =>
      old.layout != layout ||
      old.data != data ||
      old.layer != layer ||
      old.colors != colors;
}

/// Hover and selection rings, and the tooth numbers.
class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.layout,
    required this.data,
    required this.layer,
    required this.selected,
    required this.hover,
    required this.focused,
    required this.numbering,
    required this.colors,
  });

  final _Layout layout;
  final ToothChartData data;
  final ChartLayer layer;
  final String? selected;
  final String? hover;
  final bool focused;
  final ToothNumbering numbering;
  final CruColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors;
    for (final s in layout.slots) {
      final isSel = s.number == selected;
      final isHover = s.number == hover;
      if (isSel || isHover) {
        if (s.buccal != null) {
          ToothArt.ring(canvas, s.buccal!.silhouette, c, selected: isSel, k: layout.k);
        }
        ToothArt.ring(canvas, s.occlusal.outline, c, selected: isSel, k: layout.k);
      }
      _number(canvas, s);
    }
  }

  void _number(Canvas canvas, _Slot s) {
    final c = colors;
    final v = data.of(s.number);
    final isSel = s.number == selected;
    final y = s.upper ? layout.numberTop : layout.numberBottom;
    final Color fg;
    if (isSel) {
      fg = c.onAccent;
    } else if (layer == ChartLayer.plan) {
      fg = v.isPlanned ? c.accentText : c.label3;
    } else {
      fg = switch (v.state) {
        ToothState.needsCare => c.amberText,
        ToothState.treated => c.greenText,
        ToothState.missing || ToothState.notErupted => c.label3,
        ToothState.healthy => c.label2,
      };
    }
    final style = (layout.rows == ChartRows.full ? CruType.caption : CruType.micro).w600.tabular.tint(fg);
    final tp = TextPainter(
      text: TextSpan(text: toothLabel(s.number, numbering), style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final center = Offset(s.cx, y);
    if (isSel) {
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: tp.width + 12, height: tp.height + 4),
        const Radius.circular(CruRadius.full),
      );
      canvas.drawRRect(r, Paint()..color = c.accent);
    } else if (focused && selected == null && s.number == layout.slots.first.number) {
      // Where the arrow keys start.
      canvas.drawCircle(
        center,
        tp.height * 0.75,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = c.accentText.withValues(alpha: 0.5),
      );
    }
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    // A dot marks planned work (when the plan isn't on show).
    if (!isSel && !layer.showsPlan && v.isPlanned) {
      canvas.drawCircle(
        center + Offset(tp.width / 2 + 5, -tp.height / 2 + 3),
        2.5,
        Paint()..color = c.accent,
      );
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.layout != layout ||
      old.data != data ||
      old.layer != layer ||
      old.selected != selected ||
      old.hover != hover ||
      old.focused != focused ||
      old.numbering != numbering ||
      old.colors != colors;
}

void _text(Canvas canvas, String text, Offset center, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}

// ================================================================= label

/// The hovered tooth's name and what the chart shows for it, over the
/// middle of the chart.
class _HoverLabel extends StatelessWidget {
  const _HoverLabel({
    required this.slot,
    required this.layout,
    required this.visual,
    required this.layer,
    required this.hasPerio,
    required this.numbering,
  });

  final _Slot slot;
  final _Layout layout;
  final ToothVisual visual;
  final ChartLayer layer;
  final bool hasPerio;
  final ToothNumbering numbering;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    const w = 240.0;
    final left = (slot.cx - w / 2)
        .clamp(0.0, math.max(0.0, layout.width - w))
        .toDouble();
    final detail = visual.detail(layer) ??
        switch (layer) {
          ChartLayer.plan => 'Nothing planned',
          ChartLayer.perio => hasPerio ? 'Not charted in the last exam' : 'No perio exam yet',
          ChartLayer.endo => 'No endo record',
          _ => DentalChart.stateLabel(visual.state),
        };
    const labelHeight = 46.0;
    final occ = slot.occlusal.rect;
    return Positioned(
      left: left,
      // Upper teeth: below their biting surfaces; lower teeth: above.
      top: slot.upper ? occ.bottom + 8 : occ.top - 8 - labelHeight,
      child: IgnorePointer(
        child: Container(
          width: w,
          height: labelHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: CruSpace.s12,
            vertical: CruSpace.s6,
          ),
          decoration: ShapeDecoration(
            color: c.surface,
            shape: cruShape(CruRadius.control, side: BorderSide(color: c.hairline)),
            shadows: c.paneShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${toothLabel(slot.number, numbering)} · ${DentalChart.name(slot.number)}',
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
        ),
      ),
    );
  }
}
