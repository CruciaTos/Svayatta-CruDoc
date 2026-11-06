import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// One smaller number beside the hero ("Waiting 2").
class HeroStat {
  const HeroStat(this.label, this.value, {this.color, this.detail, this.onTap});
  final String label;
  final String value;

  /// Tints the value (amber for waiting, green for money in).
  final Color? color;

  /// Quiet note after the value ("~12m").
  final String? detail;
  final VoidCallback? onTap;
}

/// A part of the tick bar: [count] ticks' worth in [color].
class HeroBarPart {
  const HeroBarPart(this.count, this.color);
  final num count;
  final Color color;
}

/// A glance card with one big number and the rest small beside it, plus
/// an optional tick bar showing how the hero number splits up.
class HeroStatCard extends StatelessWidget {
  const HeroStatCard({
    super.key,
    required this.label,
    required this.value,
    this.suffix,
    this.caption,
    this.stats = const [],
    this.bar,
    this.barTotal,
    this.onTap,
    this.semanticLabel,
    this.minHeight,
  });

  /// Makes the numbers' area (above the tick bar) at least this tall; the
  /// hero and the stats spread out to fill it, text keeps its size.
  final double? minHeight;

  final String label;
  final String value;

  /// Quieter text after the value ("/12").
  final String? suffix;
  final String? caption;
  final List<HeroStat> stats;

  /// Filled parts of the tick bar; the rest of [barTotal] stays faint.
  final List<HeroBarPart>? bar;
  final num? barTotal;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final card = DecoratedBox(
      decoration: ShapeDecoration(
        color: c.surface,
        shape: cruShape(CruRadius.card, side: BorderSide(color: c.cardBorder)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s20,
          vertical: CruSpace.s18,
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 560;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minHeight ?? 0),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: wide ? 3 : 5, child: _hero(context)),
                        if (stats.isNotEmpty) ...[
                          const SizedBox(width: CruSpace.s16),
                          Container(width: 1, color: c.separator),
                          const SizedBox(width: CruSpace.s16),
                          Expanded(
                            flex: wide ? 4 : 5,
                            child: wide
                                ? _statsRow(context)
                                : _statsColumn(context),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (bar != null) ...[
                  const SizedBox(height: CruSpace.s16),
                  SizedBox(
                    height: 26,
                    child: CustomPaint(
                      painter: _TickBarPainter(
                        parts: bar!,
                        total: barTotal ?? 0,
                        empty: c.label.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
    return Semantics(
      container: true,
      label: semanticLabel,
      child: onTap == null
          ? card
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: card,
            ),
    );
  }

  Widget _hero(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label.toUpperCase(),
          style: CruType.micro.w600.tint(c.label2).copyWith(letterSpacing: 0.8),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: CruSpace.s6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: value, style: CruType.hero.tint(c.label)),
                if (suffix != null)
                  TextSpan(
                    text: suffix,
                    style: CruType.title2.w500.tabular.tint(c.label3),
                  ),
              ],
            ),
            maxLines: 1,
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: CruSpace.s6),
          Text(
            caption!,
            style: CruType.caption.tabular.tint(c.label2),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  /// Phone: label left, value right, one row each.
  Widget _statsColumn(BuildContext context) {
    final c = context.cru;
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final s in stats)
          _tap(
            s,
            Padding(
              padding: const EdgeInsets.symmetric(vertical: CruSpace.s4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      s.label,
                      style: CruType.caption.tint(c.label2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (s.detail != null) ...[
                    Text(
                      s.detail!,
                      style: CruType.micro.tabular.tint(c.label3),
                    ),
                    const SizedBox(width: CruSpace.s6),
                  ],
                  Text(
                    s.value,
                    style: CruType.title2.tabular.tint(s.color ?? c.label),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Wide: value over label, side by side.
  Widget _statsRow(BuildContext context) {
    final c = context.cru;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final s in stats)
          Expanded(
            child: _tap(
              s,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: s.value,
                          style: CruType.title.tabular.tint(s.color ?? c.label),
                        ),
                        if (s.detail != null)
                          TextSpan(
                            text: '  ${s.detail}',
                            style: CruType.micro.tabular.tint(c.label3),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: CruSpace.s2),
                  Text(
                    s.label,
                    style: CruType.caption.tint(c.label2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _tap(HeroStat s, Widget child) => s.onTap == null
      ? child
      : GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: s.onTap,
          child: child,
        );
}

/// Thin vertical ticks across the width, like a barcode: the first ones
/// coloured by part, the rest faint.
class _TickBarPainter extends CustomPainter {
  _TickBarPainter({
    required this.parts,
    required this.total,
    required this.empty,
  });

  final List<HeroBarPart> parts;
  final num total;
  final Color empty;

  static const double _tick = 2.5;
  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final n = ((size.width + _gap) / (_tick + _gap)).floor();
    if (n <= 0) return;
    final step = n > 1 ? (size.width - _tick) / (n - 1) : 0.0;
    final filledTotal = parts.fold<num>(0, (a, p) => a + p.count);
    final denom = math.max(total, filledTotal).toDouble();

    // How many ticks each part gets; at least one when it has any.
    final counts = <int>[];
    for (final p in parts) {
      if (denom <= 0 || p.count <= 0) {
        counts.add(0);
      } else {
        counts.add(math.max(1, (p.count / denom * n).round()));
      }
    }

    final paint = Paint()
      ..strokeWidth = _tick
      ..strokeCap = StrokeCap.round;
    var i = 0;
    for (var k = 0; k < parts.length; k++) {
      paint.color = parts[k].color;
      for (var j = 0; j < counts[k] && i < n; j++, i++) {
        _line(canvas, size, i * step, paint, full: true);
      }
    }
    paint.color = empty;
    for (; i < n; i++) {
      _line(canvas, size, i * step, paint, full: false);
    }
  }

  void _line(
    Canvas canvas,
    Size size,
    double x0,
    Paint p, {
    required bool full,
  }) {
    final x = x0 + _tick / 2;
    final inset = full ? _tick / 2 : size.height * 0.22;
    canvas.drawLine(Offset(x, inset), Offset(x, size.height - inset), p);
  }

  @override
  bool shouldRepaint(_TickBarPainter old) =>
      old.total != total || old.empty != empty || old.parts != parts;
}
