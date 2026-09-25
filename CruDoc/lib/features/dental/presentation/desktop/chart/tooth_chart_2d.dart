import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_anatomy.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_render.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Both arches as the dentist faces the patient, drawn in 2.5D: lit,
/// rounded crowns on a gentle smile curve, the back teeth a little
/// smaller and turned away, tucked behind their neighbours, the roots
/// fading out. Hover names a tooth, click selects it, double-click (or
/// Enter) opens it; arrow keys move between teeth.
class ToothChart2D extends StatefulWidget {
  const ToothChart2D({
    super.key,
    required this.data,
    required this.child,
    required this.mode,
    required this.selected,
    required this.onSelect,
    this.onOpen,
    this.numbering = ToothNumbering.fdi,
  });

  final ToothChartData data;

  /// Milk teeth instead of the adult set.
  final bool child;
  final ChartMode mode;
  final String? selected;
  final ValueChanged<String> onSelect;

  /// How tooth numbers are shown; storage stays FDI regardless.
  final ToothNumbering numbering;

  /// Double-click or Enter on a tooth.
  final ValueChanged<String>? onOpen;

  @override
  State<ToothChart2D> createState() => _ToothChart2DState();
}

class _ToothChart2DState extends State<ToothChart2D> {
  final FocusNode _focus = FocusNode(debugLabel: 'tooth chart 2D');
  String? _hover;
  bool _focused = false;
  _Layout? _layout;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Rebuilt only when the width or the set of teeth changes.
  _Layout _layoutFor(double width) {
    final l = _layout;
    if (l != null && l.width == width && l.child == widget.child) return l;
    return _layout = _Layout.of(width, child: widget.child);
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
        next = other.reduce(
          (a, b) =>
              (layout.slot(a)!.cx - x).abs() <= (layout.slot(b)!.cx - x).abs()
              ? a
              : b,
        );
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
        final layout = _layoutFor(constraints.maxWidth);
        final hovered = _hover == null ? null : layout.slot(_hover!);
        return Focus(
          focusNode: _focus,
          onFocusChange: (f) => setState(() => _focused = f),
          onKeyEvent: (node, e) => _onKey(node, e, layout),
          child: Semantics(
            label:
                'Tooth chart. Arrow keys move between teeth, Enter '
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
                        numbering: widget.numbering,
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

/// Share of each root the chart shows before it fades out.
const _rootShown = 0.55;

/// Where each tooth sits: scale (px per mm), the smile curve and a slot
/// per tooth, back teeth first (the order they are painted in).
class _Layout {
  _Layout._({
    required this.width,
    required this.child,
    required this.k,
    required this.height,
    required this.slots,
    required this.labelTop,
    required this.labelBottom,
    required this.biteY,
    required this.bite,
  });

  factory _Layout.of(double width, {required bool child}) {
    const pad = 10.0;
    const labelH = 26.0;
    const midGapMm = 0.5;
    final (upper, lower) = ToothSpec.arches(child: child);

    // One half of a row, from the midline out: how far along the arch
    // each tooth is (0 at the midline, 1 at the back), how much it is
    // scaled and turned, and where its centre falls (mm from midline).
    List<_Place> half(Iterable<String> fromMid) {
      final teeth = fromMid.map(ToothSpec.of).toList();
      final total = teeth.fold<double>(0, (s, t) => s + t.md);
      var along = 0.0;
      var x = midGapMm / 2;
      final out = <_Place>[];
      for (var i = 0; i < teeth.length; i++) {
        final t = teeth[i];
        final u = (along + t.md / 2) / total;
        final scale = 1 - 0.12 * u;
        final w = t.md * scale * (1 - 0.24 * math.pow(u, 1.3));
        // Front teeth sit apart; the back ones tuck behind.
        if (i > 0) x += (0.45 - 1.1 * u) * scale;
        out.add(_Place(t, u, scale, w, x + w / 2));
        x += w;
        along += t.md;
      }
      return out;
    }

    final n = upper.length ~/ 2;
    final rows = [
      for (final row in [upper, lower])
        (left: half(row.sublist(0, n).reversed), right: half(row.sublist(n))),
    ];
    double extent(List<_Place> h) => h.last.x + h.last.w / 2;
    final halfMm = rows
        .map((r) => math.max(extent(r.left), extent(r.right)))
        .reduce(math.max);
    final k = math.min((width - pad * 2) / (halfMm * 2), child ? 8.4 : 6.4);

    final smile = 2.2 * k;
    final bite = math.max(12.0, 2.4 * k);
    double len(_Place p) =>
        (p.spec.crown + p.spec.root * _rootShown) * p.scale * k;
    double rise(_Place p) => smile * p.u * p.u;

    final upperPlaces = [...rows[0].left, ...rows[0].right];
    final lowerPlaces = [...rows[1].left, ...rows[1].right];
    final upperOcc =
        labelH + 2 + upperPlaces.map((p) => len(p) + rise(p)).reduce(math.max);
    final lowerOcc = upperOcc + bite;
    final height =
        lowerOcc +
        lowerPlaces.map((p) => len(p) - rise(p)).reduce(math.max) +
        labelH +
        2;

    final mid = width / 2;
    final slots = <_Slot>[];
    void place(List<_Place> h, {required bool isUpper, required bool left}) {
      for (final p in h) {
        final cx = left ? mid - p.x * k : mid + p.x * k;
        final occ = (isUpper ? upperOcc : lowerOcc) - rise(p);
        final half = p.w * k / 2;
        final l = len(p);
        slots.add(
          _Slot(
            number: p.spec.number,
            spec: p.spec,
            shape: ToothShape(p.spec, k),
            cx: cx,
            occ: occ,
            upper: isUpper,
            u: p.u,
            sx: p.w / p.spec.md,
            sy: p.scale,
            hit: isUpper
                ? Rect.fromLTRB(cx - half, occ - l, cx + half, occ + bite / 2)
                : Rect.fromLTRB(cx - half, occ - bite / 2, cx + half, occ + l),
          ),
        );
      }
    }

    place(rows[0].left, isUpper: true, left: true);
    place(rows[0].right, isUpper: true, left: false);
    place(rows[1].left, isUpper: false, left: true);
    place(rows[1].right, isUpper: false, left: false);
    slots.sort((a, b) => b.u.compareTo(a.u));
    return _Layout._(
      width: width,
      child: child,
      k: k,
      height: height,
      slots: slots,
      labelTop: labelH / 2,
      labelBottom: height - labelH / 2,
      biteY: upperOcc + bite / 2,
      bite: bite,
    );
  }

  final double width;
  final bool child;
  final double k;
  final double height;

  /// Back teeth first.
  final List<_Slot> slots;

  /// Centre lines of the number labels above and below the teeth.
  final double labelTop;
  final double labelBottom;

  /// Middle of the gap between the arches at the midline, and its height.
  final double biteY;
  final double bite;

  _Slot? slot(String n) {
    for (final s in slots) {
      if (s.number == n) return s;
    }
    return null;
  }

  String? hitTest(Offset p) {
    // Front teeth first: they overlap the ones behind.
    for (final s in slots.reversed) {
      if (s.hit.contains(p)) return s.number;
    }
    // The number labels select their tooth too.
    for (final s in slots.reversed) {
      final y = s.upper ? labelTop : labelBottom;
      if ((p.dy - y).abs() < 12 && (p.dx - s.cx).abs() < s.hit.width / 2) {
        return s.number;
      }
    }
    return null;
  }
}

class _Place {
  const _Place(this.spec, this.u, this.scale, this.w, this.x);

  final ToothSpec spec;
  final double u;
  final double scale;

  /// Width on screen and centre from the midline, in mm.
  final double w;
  final double x;
}

class _Slot {
  const _Slot({
    required this.number,
    required this.spec,
    required this.shape,
    required this.cx,
    required this.occ,
    required this.upper,
    required this.u,
    required this.sx,
    required this.sy,
    required this.hit,
  });

  final String number;
  final ToothSpec spec;
  final ToothShape shape;
  final double cx;

  /// The biting edge's y.
  final double occ;
  final bool upper;

  /// Along the arch: 0 at the midline, 1 at the back.
  final double u;

  /// Width and height scale (perspective and turn).
  final double sx;
  final double sy;
  final Rect hit;
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
    required this.numbering,
  });

  final _Layout layout;
  final ToothChartData data;
  final ChartMode mode;
  final String? selected;
  final String? hover;
  final bool focused;
  final CruColors colors;
  final ToothNumbering numbering;

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors;
    // A soft stage behind the arches, so white enamel reads on white.
    final stageW = size.width * 0.92;
    final stageH = layout.height * 0.95;
    canvas.save();
    canvas.translate(size.width / 2, layout.biteY);
    canvas.scale(1, stageH / stageW);
    canvas.drawCircle(
      Offset.zero,
      stageW / 2,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          stageW / 2,
          [
            c.stage,
            c.stage.withValues(alpha: 0.6),
            c.stage.withValues(alpha: 0),
          ],
          [0, 0.55, 1],
        ),
    );
    canvas.restore();
    // Midline, in the gap between the arches.
    canvas.drawLine(
      Offset(size.width / 2, layout.biteY - layout.bite * 0.3),
      Offset(size.width / 2, layout.biteY + layout.bite * 0.3),
      Paint()
        ..color = c.separator
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );

    // Back to front; the hovered and the picked tooth on top.
    for (final slot in layout.slots) {
      if (slot.number == selected || slot.number == hover) continue;
      _paintSlot(canvas, slot);
    }
    for (final n in {hover, selected}) {
      final slot = n == null ? null : layout.slot(n);
      if (slot != null) _paintSlot(canvas, slot);
    }

    for (final slot in layout.slots) {
      _paintNumber(canvas, slot);
    }
  }

  void _paintSlot(Canvas canvas, _Slot slot) {
    final c = colors;
    final v = data.of(slot.number);
    final isSel = slot.number == selected;
    final isHover = slot.number == hover && !isSel;
    final dim = mode == ChartMode.plan && !v.isPlanned;
    final lift = isSel ? 1.06 : (isHover ? 1.035 : 1.0);
    canvas.save();
    canvas.translate(slot.cx, slot.occ);
    if (lift != 1) {
      // Rise towards the viewer: a touch bigger, nudged to the bite.
      canvas.translate(0, slot.upper ? 2 : -2);
      canvas.scale(lift);
    }
    // Mesial always faces the midline; upper teeth hang roots-up.
    canvas.scale(
      slot.spec.patientRight ? -slot.sx : slot.sx,
      slot.upper ? -slot.sy : slot.sy,
    );
    if (dim) {
      canvas.saveLayer(null, Paint()..color = const Color(0x59000000));
    }
    paintTooth(
      canvas,
      slot.shape,
      v,
      c,
      look: ToothLook(
        rootShown: _rootShown,
        fadeRoots: true,
        turn: slot.u,
        down: slot.upper ? -1 : 1,
        planMode: mode == ChartMode.plan,
      ),
    );
    if (dim) canvas.restore();
    if (isSel || isHover) {
      final crown = slot.shape.crown;
      if (isSel) {
        canvas.drawPath(
          crown,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..color = c.accent.withValues(alpha: 0.28)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
      canvas.drawPath(
        crown,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSel ? 2 : 1.4
          ..strokeJoin = StrokeJoin.round
          ..color = isSel ? c.accent : c.accentText.withValues(alpha: 0.55),
      );
    }
    canvas.restore();
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
        text: toothLabel(slot.number, numbering),
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
    } else if (focused &&
        selected == null &&
        slot.number == ToothSpec.arches(child: layout.child).$1.first) {
      // Where the arrow keys start.
      canvas.drawCircle(
        center,
        11,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = c.accentText.withValues(alpha: 0.5),
      );
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

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.layout != layout ||
      old.data != data ||
      old.mode != mode ||
      old.selected != selected ||
      old.hover != hover ||
      old.focused != focused ||
      old.colors != colors ||
      old.numbering != numbering;
}

/// The hovered tooth's name and state, above (or below) it.
class _HoverLabel extends StatelessWidget {
  const _HoverLabel({
    required this.slot,
    required this.width,
    required this.visual,
    required this.mode,
    required this.numbering,
  });

  final _Slot slot;
  final double width;
  final ToothVisual visual;
  final ChartMode mode;
  final ToothNumbering numbering;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    const w = 220.0;
    final left = (slot.cx - w / 2)
        .clamp(0.0, math.max(0.0, width - w))
        .toDouble();
    final detail =
        visual.callout(mode) ??
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
