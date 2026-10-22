import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/tutorial/domain/tutorial_step.dart';
import 'package:doctor_management_app/features/tutorial/presentation/tutorial_card.dart';
import 'package:doctor_management_app/features/tutorial/presentation/tutorial_controller.dart';
import 'package:doctor_management_app/features/tutorial/presentation/tutorial_target.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Hosts the tour above the whole app, the voice pill and floating mic
/// included (they are drawn over the navigator, so the navigator's own
/// overlay would leave them bright and tappable). The tour is an
/// [OverlayEntry] in this host's [Overlay], inserted while it runs.
class TutorialHost extends ConsumerStatefulWidget {
  const TutorialHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TutorialHost> createState() => _TutorialHostState();
}

class _TutorialHostState extends ConsumerState<TutorialHost> {
  final GlobalKey<OverlayState> _overlay = GlobalKey(debugLabel: 'tour');
  OverlayEntry? _entry;

  @override
  void dispose() {
    _entry?.remove();
    _entry?.dispose();
    super.dispose();
  }

  void _afterFrame(VoidCallback fn) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) fn();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _insert() {
    if (_entry != null || !ref.read(tutorialControllerProvider).running) {
      return;
    }
    final overlay = _overlay.currentState;
    if (overlay == null) return;
    _entry = OverlayEntry(builder: (_) => _TutorialLayer(onGone: _remove));
    overlay.insert(_entry!);
  }

  void _remove() {
    if (ref.read(tutorialControllerProvider).running) return;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  void _toast(TutorialPlatform? platform) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final c = context.cru;
    // On the phone it sits above the floating nav.
    final bottom = platform == TutorialPlatform.mobile
        ? MobileMetrics.navHeight +
              MobileMetrics.navBottom(context) +
              CruSpace.s8
        : CruSpace.s16;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'You can take the tour again from Settings.',
            style: CruType.text.tint(c.surface),
          ),
          backgroundColor: c.label,
          behavior: SnackBarBehavior.floating,
          shape: cruShape(CruRadius.control),
          margin: EdgeInsets.fromLTRB(CruSpace.s16, 0, CruSpace.s16, bottom),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TutorialState>(tutorialControllerProvider, (prev, next) {
      if (next.running && _entry == null) _afterFrame(_insert);
      if (prev != null &&
          next.endCount != prev.endCount &&
          next.ended == TutorialEnd.skipped) {
        _afterFrame(() => _toast(prev.platform));
      }
    });
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Overlay(key: _overlay),
      ],
    );
  }
}

/// The dimmed screen with its cut-out, and the card.
class _TutorialLayer extends ConsumerStatefulWidget {
  const _TutorialLayer({required this.onGone});

  /// Called once the layer has faded out after the tour ended.
  final VoidCallback onGone;

  @override
  ConsumerState<_TutorialLayer> createState() => _TutorialLayerState();
}

class _TutorialLayerState extends ConsumerState<_TutorialLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: CruMotion.standard,
    value: 1,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _morph,
    curve: CruMotion.curve,
  );
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'Tour');

  /// Holds focus so Enter, Space and the arrows reach the tour; Tab moves
  /// between the card's buttons only (Skip, Back, Next).
  final FocusNode _root = FocusNode(
    debugLabel: 'Tour card',
    skipTraversal: true,
  );

  /// Focus before the tour took it, given back when it ends.
  FocusNode? _returnTo;
  bool _hasFocus = false;

  /// The cut-out morphs from [_from] to [_to].
  _Hole? _from;
  _Hole? _to;

  /// What [_to] is measured from (null: the welcome card).
  TutorialTarget? _target;
  bool _placed = false;
  bool _measuring = false;

  @override
  void dispose() {
    _giveBackFocus();
    _morph.dispose();
    _scope.dispose();
    _root.dispose();
    super.dispose();
  }

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  _Hole? get _hole {
    final to = _to;
    final from = _from;
    if (to == null) return null;
    if (from == null || _morph.value >= 1) return to;
    return _Hole.lerp(from, to, _curve.value);
  }

  _Hole? _measure(TutorialSpot spot) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final location = ref.read(tutorialAnchorsProvider).locate(spot.target, box);
    return location == null ? null : _Hole.around(location);
  }

  /// Follows the current step's target. A new target morphs from wherever
  /// the cut-out is; the same target moving (scroll, resize, text size)
  /// is followed directly. Returns whether anything changed.
  bool _follow(TutorialState s) {
    // While the app moves to the next step, hold the last cut-out.
    if (!s.running || s.phase == TutorialPhase.preparing) return false;
    final spot = s.spot;
    final next = spot == null ? null : _measure(spot);
    if (!_placed || spot?.target != _target) {
      _placed = true;
      _target = spot?.target;
      _morphTo(next);
      return true;
    }
    if (next == null) return false;
    final to = _to;
    if (to == null || to.isPoint) {
      _morphTo(next);
      return true;
    }
    if (to.near(next)) return false;
    if (_morph.isAnimating) {
      _to = next;
    } else {
      _from = null;
      _to = next;
    }
    return true;
  }

  void _morphTo(_Hole? next) {
    final now = _hole;
    if (next == null && now == null) {
      _from = _to = null;
      return;
    }
    // Opening from (or closing to) a point at the target's centre.
    _from = now ?? _Hole.point(next!.rect.center);
    _to = next ?? _Hole.point(now!.rect.center);
    if (_reduceMotion) {
      _morph.value = 1;
    } else {
      _morph.forward(from: 0);
    }
  }

  /// Measures after every frame while the tour is up, so the cut-out
  /// follows scrolling, resizing, rotation and text-size changes. It never
  /// schedules frames itself.
  void _keepMeasuring() {
    if (_measuring) return;
    _measuring = true;
    WidgetsBinding.instance.addPostFrameCallback(_onFrame);
  }

  void _onFrame(Duration _) {
    if (!mounted) return;
    final s = ref.read(tutorialControllerProvider);
    if (!s.visible) {
      _measuring = false;
      return;
    }
    if (_follow(s)) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback(_onFrame);
  }

  void _syncFocus(bool visible) {
    if (visible == _hasFocus) return;
    _hasFocus = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasFocus != visible) return;
      if (visible) {
        final current = FocusManager.instance.primaryFocus;
        if (current != null && !_isOurs(current)) _returnTo = current;
        _root.requestFocus();
      } else {
        _giveBackFocus();
      }
    });
  }

  bool _isOurs(FocusNode node) =>
      node == _scope || node.ancestors.contains(_scope);

  void _giveBackFocus() {
    final back = _returnTo;
    _returnTo = null;
    final primary = FocusManager.instance.primaryFocus;
    // A dialog that paused the tour has taken focus itself: leave it.
    if (primary == null || !_isOurs(primary)) return;
    if (back != null && back.context != null && back.canRequestFocus) {
      back.requestFocus();
    } else {
      primary.unfocus();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final s = ref.read(tutorialControllerProvider);
    if (!s.visible) return KeyEventResult.ignored;
    final tour = ref.read(tutorialControllerProvider.notifier);
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      tour.skip();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      tour.next();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      tour.back();
      return KeyEventResult.handled;
    }
    // On a focused button Enter and Space press that button instead.
    final onCard = FocusManager.instance.primaryFocus == _root;
    if (onCard &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.space)) {
      tour.next();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(tutorialControllerProvider);
    final tour = ref.read(tutorialControllerProvider.notifier);
    final c = context.cru;
    final visible = s.visible;
    if (visible) {
      _follow(s);
      _keepMeasuring();
    }
    _syncFocus(visible);
    final fade = _reduceMotion ? Duration.zero : CruMotion.standard;
    final step = s.step;

    final Widget card = s.showing && step != null
        ? _CardPlacement(
            key: ValueKey('${step.id}/${s.spot?.target.name}'),
            hole: s.spot == null ? null : _to?.rect,
            platform: s.platform ?? TutorialPlatform.desktop,
            child: TutorialCard(
              state: s,
              onNext: tour.next,
              onBack: tour.back,
              onSkip: tour.skip,
            ),
          )
        : const SizedBox.shrink(key: ValueKey('none'));

    return IgnorePointer(
      ignoring: !visible,
      child: BlockSemantics(
        blocking: visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: fade,
          curve: CruMotion.curve,
          // With reduced motion this fires during the build that hid the
          // layer; removing the entry has to wait for the frame to end.
          onEnd: () {
            WidgetsBinding.instance
              ..addPostFrameCallback((_) {
                if (mounted && !ref.read(tutorialControllerProvider).running) {
                  widget.onGone();
                }
              })
              ..ensureVisualUpdate();
          },
          child: FocusScope(
            node: _scope,
            child: Focus(
              focusNode: _root,
              onKeyEvent: _onKey,
              // Above the navigator there is no Material for text and ink.
              child: Material(
                type: MaterialType.transparency,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Taps on the dimmed area, and inside the cut-out, do
                    // nothing: the person is looking, not acting.
                    AbsorbPointer(
                      child: CustomPaint(
                        painter: _ScrimPainter(
                          hole: () => _hole,
                          scrim: c.scrim,
                          ring: c.accent,
                          repaint: _morph,
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: fade,
                      switchInCurve: CruMotion.curve,
                      switchOutCurve: CruMotion.curve,
                      // Cross-fade, rising 8 px into place.
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: AnimatedBuilder(
                          animation: animation,
                          builder: (context, child) => Transform.translate(
                            offset: Offset(
                              0,
                              CruSpace.s8 * (1 - animation.value),
                            ),
                            child: child,
                          ),
                          child: child,
                        ),
                      ),
                      child: card,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The cut-out: a rect and its corner radius, in the layer's coordinates.
@immutable
class _Hole {
  const _Hole(this.rect, this.radius, {this.round = false});

  /// 8 px of breathing room around the target; the radius grows with it
  /// (inner radius = outer radius − inset).
  factory _Hole.around(TutorialLocation at) {
    const pad = CruSpace.s8;
    switch (at.shape) {
      case TutorialShape.rounded:
        return _Hole(at.rect.inflate(pad), at.radius + pad);
      case TutorialShape.circle:
        final d = at.rect.shortestSide + pad * 2;
        return _Hole(
          Rect.fromCenter(center: at.rect.center, width: d, height: d),
          d / 2,
          round: true,
        );
      case TutorialShape.stadium:
        final r = at.rect.inflate(pad);
        return _Hole(r, r.shortestSide / 2);
    }
  }

  factory _Hole.point(Offset centre) =>
      _Hole(Rect.fromCenter(center: centre, width: 0, height: 0), 0);

  final Rect rect;
  final double radius;
  final bool round;

  bool get isPoint => rect.width < 1 || rect.height < 1;

  double get _r => math.min(radius, rect.shortestSide / 2);

  bool near(_Hole o) =>
      (rect.left - o.rect.left).abs() < 0.5 &&
      (rect.top - o.rect.top).abs() < 0.5 &&
      (rect.right - o.rect.right).abs() < 0.5 &&
      (rect.bottom - o.rect.bottom).abs() < 0.5 &&
      (radius - o.radius).abs() < 0.5;

  Path path([double grow = 0]) {
    final r = rect.inflate(grow);
    if (round) return Path()..addOval(r);
    return Path()..addRSuperellipse(
      RSuperellipse.fromRectAndRadius(r, Radius.circular(_r + grow)),
    );
  }

  static _Hole lerp(_Hole a, _Hole b, double t) => _Hole(
    Rect.lerp(a.rect, b.rect, t)!,
    lerpDouble(a.radius, b.radius, t)!,
    round: t < 0.5 ? a.round : b.round,
  );
}

/// The scrim with the cut-out punched through, and a 2 px Ink Blue ring
/// ("now") around it.
class _ScrimPainter extends CustomPainter {
  _ScrimPainter({
    required this.hole,
    required this.scrim,
    required this.ring,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final _Hole? Function() hole;
  final Color scrim;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Offset.zero & size;
    final fill = Paint()..color = scrim;
    final h = hole();
    if (h == null || h.isPoint) {
      canvas.drawRect(screen, fill);
      return;
    }
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(screen), h.path()),
      fill,
    );
    canvas.drawPath(
      h.path(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ring,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => true;
}

/// Places the card below its target when there's room, else above, else
/// beside it (the full-height sidebar); centred when there's no target.
/// On the phone it stays clear of the floating nav.
class _CardPlacement extends StatelessWidget {
  const _CardPlacement({
    super.key,
    required this.hole,
    required this.platform,
    required this.child,
  });

  final Rect? hole;
  final TutorialPlatform platform;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final phone = platform == TutorialPlatform.mobile;
    return CustomSingleChildLayout(
      delegate: _CardLayout(
        hole: hole,
        maxWidth: phone ? double.infinity : CruSize.tourCard,
        top: padding.top + CruSpace.s8,
        bottom: phone
            ? MobileMetrics.navBottom(context) +
                  MobileMetrics.navHeight +
                  CruSpace.s8
            : padding.bottom + CruSpace.s16,
      ),
      child: child,
    );
  }
}

class _CardLayout extends SingleChildLayoutDelegate {
  const _CardLayout({
    required this.hole,
    required this.maxWidth,
    required this.top,
    required this.bottom,
  });

  static const double _margin = CruSpace.s16;
  static const double _gap = CruSpace.s12;

  final Rect? hole;
  final double maxWidth;
  final double top;
  final double bottom;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width = math.max(
      0.0,
      math.min(maxWidth, constraints.maxWidth - _margin * 2),
    );
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: math.max(0.0, constraints.maxHeight - top - bottom),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    final h = hole;
    final centred = Offset(
      (size.width - child.width) / 2,
      (size.height - child.height) / 2,
    );
    if (h == null) return centred;
    double x(double v) {
      final max = size.width - _margin - child.width;
      return max < _margin
          ? (size.width - child.width) / 2
          : v.clamp(_margin, max);
    }

    double y(double v) {
      final max = size.height - bottom - child.height;
      return max < top ? top : v.clamp(top, max);
    }

    final alongX = x(h.center.dx - child.width / 2);
    if (h.bottom + _gap + child.height <= size.height - bottom) {
      return Offset(alongX, h.bottom + _gap);
    }
    if (h.top - _gap - child.height >= top) {
      return Offset(alongX, h.top - _gap - child.height);
    }
    final alongY = y(h.center.dy - child.height / 2);
    if (h.right + _gap + child.width <= size.width - _margin) {
      return Offset(h.right + _gap, alongY);
    }
    if (h.left - _gap - child.width >= _margin) {
      return Offset(h.left - _gap - child.width, alongY);
    }
    return Offset(alongX, y(size.height));
  }

  @override
  bool shouldRelayout(_CardLayout old) =>
      old.hole != hole ||
      old.maxWidth != maxWidth ||
      old.top != top ||
      old.bottom != bottom;
}
