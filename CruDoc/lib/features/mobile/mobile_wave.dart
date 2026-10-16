import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One page swapping for another as waves around a card that stays on
/// screen (see [mobileWaveChildren]). Over one run of [t] (0 → 1) the
/// [leaving] page goes first, its items fading out one after another
/// nearest the card first, each pushed away from it; the card glides from
/// where it was ([from]) to its new place; then the arriving page ripples
/// in the same way, nearest first, each settling in towards the card.
class MobileWave extends InheritedWidget {
  const MobileWave({
    super.key,
    required this.t,
    this.leaving = false,
    this.from,
    required super.child,
  });

  final Animation<double> t;
  final bool leaving;

  /// The card's rect before the switch, in global coordinates; null for
  /// no glide.
  final Rect? from;

  static MobileWave? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MobileWave>();

  @override
  bool updateShouldNotify(MobileWave old) =>
      old.t != t || old.leaving != leaving || old.from != from;
}

/// Wraps [children] so each plays its step of the waves out from the
/// child at [origin] (the card).
List<Widget> mobileWaveChildren(List<Widget> children, {required int origin}) =>
    [
      for (var i = 0; i < children.length; i++)
        _WaveItem(distance: i - origin, child: children[i]),
    ];

/// How far an item drifts as it comes and goes.
const double _kDrift = 18;

class _WaveItem extends StatelessWidget {
  const _WaveItem({required this.distance, required this.child});

  final int distance;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final w = MobileWave.maybeOf(context);
    final d = distance;
    if (w == null || d == 0) return child;
    final n = d.abs() - 1;
    // On a 1 s run each step lasts ~220 ms, ~60 ms behind the last.
    final start = w.leaving
        ? math.min(n * 0.06, 0.2)
        : 0.42 + math.min(n * 0.06, 0.36);
    final step = CurvedAnimation(
      parent: w.t,
      curve: Interval(start, start + 0.22, curve: Curves.easeInOutCubic),
    );
    return AnimatedBuilder(
      animation: step,
      builder: (context, child) {
        // 0 = hidden, 1 = in place.
        final shown = w.leaving ? 1 - step.value : step.value;
        // Pushed away from the card going, drifting in towards it coming.
        final away = w.leaving ? step.value : 0.0;
        final towards = w.leaving ? 0.0 : 1 - step.value;
        return Opacity(
          opacity: shown,
          child: Transform.translate(
            offset: Offset(0, d.sign * _kDrift * (away - towards)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// The card that stays on screen. On the arriving page it glides from
/// [MobileWave.from] to its own place (both places are the same width, so
/// it only moves up or down); on the leaving page it is already gone, so
/// only one card shows.
class MobileWaveCard extends StatefulWidget {
  const MobileWaveCard({super.key, required this.child});

  final Widget child;

  @override
  State<MobileWaveCard> createState() => _MobileWaveCardState();
}

class _MobileWaveCardState extends State<MobileWaveCard> {
  @override
  Widget build(BuildContext context) {
    final w = MobileWave.maybeOf(context);
    final t = w?.t ?? kAlwaysCompleteAnimation;
    final glide = CurvedAnimation(
      parent: t,
      curve: const Interval(0.12, 0.62, curve: Curves.easeInOutCubic),
    );
    final self = context;
    // The same Opacity and Transform throughout, so the card keeps its
    // state between pages.
    return AnimatedBuilder(
      animation: glide,
      builder: (context, child) {
        final from = w?.from;
        var dy = 0.0;
        // Only while gliding: reading the card's place at any other time
        // (e.g. a rebuild during layout after a page closes) is unsafe.
        if (w != null &&
            !w.leaving &&
            from != null &&
            w.t.isAnimating &&
            glide.value < 1) {
          try {
            final box = self.findRenderObject() as RenderBox?;
            if (box != null && box.hasSize && box.attached) {
              dy = from.top - box.localToGlobal(Offset.zero).dy;
            }
          } catch (_) {}
        }
        return Opacity(
          opacity: w != null && w.leaving ? 0 : 1,
          child: Transform.translate(
            offset: Offset(0, dy * (1 - glide.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// A widget's rect on screen, or null before it is laid out.
Rect? mobileGlobalRect(GlobalKey key) {
  final box = key.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize || !box.attached) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
