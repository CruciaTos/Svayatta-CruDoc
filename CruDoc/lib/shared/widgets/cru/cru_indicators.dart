import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/theme/cru_theme.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru_card.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru_icons.dart';

/// What a status dot means. Colour always carries meaning.
enum CruDotKind {
  /// Happening now (accent).
  now,

  /// Someone is waiting (amber).
  waiting,

  /// Booked, not yet here: hollow ring.
  booked,

  /// Done (green).
  done,

  /// Resolved without being seen (cancelled / skipped): hollow, quiet.
  inactive,
}

class CruStatusDot extends StatelessWidget {
  const CruStatusDot(this.kind, {super.key, this.size = CruSize.statusDot});

  final CruDotKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final hollow = kind == CruDotKind.booked || kind == CruDotKind.inactive;
    final color = switch (kind) {
      // Evening "now" dot uses the lighter accent text for contrast.
      CruDotKind.now => c.isEvening ? c.accentText : c.accent,
      CruDotKind.waiting => c.amber,
      CruDotKind.done => c.green,
      CruDotKind.booked || CruDotKind.inactive => c.label3,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hollow ? null : color,
        border: hollow ? Border.all(color: color, width: 1.5) : null,
      ),
    );
  }
}

/// Grey initials avatar. Never coloured, so it never competes with status.
class CruMonogram extends StatelessWidget {
  const CruMonogram({
    super.key,
    required this.name,
    this.size = CruSize.monogramRow,
    this.background,
    this.foreground,
  });

  final String name;
  final double size;

  /// Defaults to track.
  final Color? background;

  /// Defaults to label2.
  final Color? foreground;

  static const _titles = {'dr', 'mr', 'mrs', 'ms', 'prof'};

  /// "KI" for Kavya Iyer, "AD" for Dr. Ananya Deshpande (titles skipped).
  static String initialsOf(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty && RegExp(r'[A-Za-z0-9]').hasMatch(p[0]))
        .where((p) => !_titles.contains(p.toLowerCase().replaceAll('.', '')))
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: background ?? c.track,
        ),
        child: Text(
          initialsOf(name),
          style: CruType.monogram(size * 0.37).copyWith(
            color: foreground ?? c.label2,
          ),
        ),
      ),
    );
  }
}

/// 30 px inset chip: quiet label + value ("BP 118/76").
class CruChip extends StatelessWidget {
  const CruChip({
    super.key,
    this.label,
    required this.value,
    this.icon,
    this.background,
    this.foreground,
  });

  final String? label;
  final String value;
  final CruIconData? icon;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final fg = foreground ?? c.label;
    return Container(
      height: CruSize.chip,
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
      decoration: ShapeDecoration(
        color: background ?? c.inset,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            CruIcon(icon!, size: 14, strokeWidth: 2.2, color: fg),
            const SizedBox(width: CruSpace.s6),
          ],
          if (label != null) ...[
            Text(label!, style: CruType.subhead.w500.tint(c.label2)),
            const SizedBox(width: CruSpace.s6),
          ],
          Text(value, style: CruType.subhead.w600.tabular.tint(fg)),
        ],
      ),
    );
  }
}

/// 26 px pill: "In consultation", "Waiting 8 min".
class CruPill extends StatelessWidget {
  const CruPill({
    super.key,
    required this.text,
    required this.background,
    required this.foreground,
    this.icon,
  });

  final String text;
  final Color background;
  final Color foreground;
  final CruIconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: CruSize.pill,
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s10),
      decoration: ShapeDecoration(
        color: background,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            CruIcon(icon!, size: 14, strokeWidth: 2.2, color: foreground),
            const SizedBox(width: CruSpace.s6),
          ],
          Text(text, style: CruType.caption.w600.tabular.tint(foreground)),
        ],
      ),
    );
  }
}

/// Category tint for [CruIconTile].
enum CruTileTone { teal, amber, neutral, accent, green }

/// 36 px icon tile (radius 10) tinted by category.
class CruIconTile extends StatelessWidget {
  const CruIconTile({super.key, required this.icon, required this.tone});

  final CruIconData icon;
  final CruTileTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final (bg, fg) = switch (tone) {
      CruTileTone.teal => (c.tealTint, c.tealText),
      CruTileTone.amber => (c.amberTint, c.amberText),
      CruTileTone.neutral => (c.inset, c.label2),
      CruTileTone.accent => (c.accentTint, c.accentText),
      CruTileTone.green => (c.greenTint, c.greenText),
    };
    return Container(
      width: CruSize.iconTile,
      height: CruSize.iconTile,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: bg,
        shape: cruShape(CruRadius.iconTile),
      ),
      child: CruIcon(icon, size: 18, strokeWidth: 1.8, color: fg),
    );
  }
}

/// Progress ring: track + accent arc, round caps, starting at 12 o'clock.
class CruProgressRing extends StatelessWidget {
  const CruProgressRing({
    super.key,
    required this.value,
    this.size = CruSize.progressRing,
    this.strokeWidth = CruSize.progressStroke,
    this.semanticLabel,
  });

  /// 0–1.
  final double value;
  final double size;
  final double strokeWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      label: semanticLabel,
      value: '${(value.clamp(0, 1) * 100).round()}%',
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: value.clamp(0.0, 1.0)),
        duration: CruMotion.of(context),
        curve: CruMotion.curve,
        builder: (context, v, _) => CustomPaint(
          size: Size.square(size),
          painter: _RingPainter(
            value: v,
            track: c.track,
            // Evening uses the lighter accent so the arc reads on dark.
            arc: c.isEvening ? c.accentText : c.accent,
            strokeWidth: strokeWidth,
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.track,
    required this.arc,
    required this.strokeWidth,
  });

  final double value;
  final Color track;
  final Color arc;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - strokeWidth) / 2,
    );
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;
    canvas.drawArc(rect, 0, math.pi * 2, false, base..color = track);
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * value,
        false,
        base
          ..color = arc
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.track != track || old.arc != arc;
}

/// A green check in a filled circle ("5 seen this morning").
class CruDoneBadge extends StatelessWidget {
  const CruDoneBadge({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.green),
      child: CruIcon(
        CruIcons.check,
        size: size * 0.8,
        strokeWidth: 2.4,
        color: CruBrand.white,
      ),
    );
  }
}

/// Keycap hint ("Ctrl K").
class CruKeycap extends StatelessWidget {
  const CruKeycap(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.keycap),
      ),
      child: Text(text, style: CruType.micro.tint(c.label2)),
    );
  }
}
