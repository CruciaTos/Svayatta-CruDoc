import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/core/services/demo_session_service.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/features/tutorial/presentation/tutorial_target.dart';

/// The phone's floating mic, like Wispr Flow's bubble: it hovers at the
/// screen's edge over every page. Hold it to talk, tap it to talk until a
/// pause, drag it anywhere and it settles against the nearest side, where
/// it stays next time. The island shows what was heard.
class VoiceBubble extends ConsumerStatefulWidget {
  const VoiceBubble({
    super.key,
    required this.listening,
    required this.level,
    required this.onTalkStart,
    required this.onTalkEnd,
    required this.onTap,
  });

  final bool listening;
  final ValueListenable<double> level;
  final VoidCallback onTalkStart;
  final VoidCallback onTalkEnd;
  final VoidCallback onTap;

  @override
  ConsumerState<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends ConsumerState<VoiceBubble> {
  static const _size = 54.0;
  static const _edge = 10.0;
  static const _rightKey = 'voice_bubble_right';
  static const _yKey = 'voice_bubble_y';

  /// A finger kept still this long is a hold (talk), not a tap.
  static const _holdAfter = Duration(milliseconds: 220);

  /// Moving further than this before the hold starts is a drag.
  static const _slop = 8.0;

  /// Which side it rests on, and how far down, as a share of the room
  /// it has, so it stays in place across screen sizes.
  bool _right = true;
  double _y = 0.62;

  /// While dragging: where it is, free of the edges.
  Offset? _drag;
  Offset? _downAt;
  Timer? _hold;
  bool _talking = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _right = prefs.getBool(_rightKey) ?? _right;
        _y = prefs.getDouble(_yKey) ?? _y;
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rightKey, _right);
      await prefs.setDouble(_yKey, _y);
    } catch (_) {}
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  /// Top and bottom it can rest between: under the island, above the
  /// tab bar (or the keyboard, when it's up).
  (double, double) _range(BuildContext context, double height) {
    final pad = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final top = pad.top + 56;
    final bottom = math.max(
      MobileMetrics.navHeight + MobileMetrics.navBottom(context) + 12,
      keyboard + _edge,
    );
    return (top, math.max(top, height - bottom - _size));
  }

  void _down(PointerDownEvent e) {
    _downAt = e.position;
    _hold?.cancel();
    _hold = Timer(_holdAfter, () {
      if (_drag != null) return;
      _talking = true;
      MobileHaptics.commit();
      widget.onTalkStart();
      setState(() {});
    });
  }

  void _move(PointerMoveEvent e, Offset rested) {
    if (_talking) return;
    if (_drag == null) {
      if ((e.position - _downAt!).distance < _slop) return;
      _hold?.cancel();
      _drag = rested;
    }
    setState(() => _drag = _drag! + e.delta);
  }

  void _up(Size screen, (double, double) range) {
    _hold?.cancel();
    if (_talking) {
      _talking = false;
      widget.onTalkEnd();
      setState(() {});
      return;
    }
    final drag = _drag;
    if (drag != null) {
      // Settles against the nearer side, where it was let go.
      final (top, bottom) = range;
      setState(() {
        _right = drag.dx + _size / 2 > screen.width / 2;
        _y = bottom <= top
            ? 0
            : ((drag.dy - top) / (bottom - top)).clamp(0.0, 1.0);
        _drag = null;
      });
      MobileHaptics.tap();
      unawaited(_save());
      return;
    }
    MobileHaptics.tap();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn =
        ref.watch(authStateProvider).value != null ||
        DemoSessionService.isDemoMode;
    if (!signedIn) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, box) {
        final screen = box.biggest;
        final range = _range(context, screen.height);
        final (top, bottom) = range;
        final rested = Offset(
          _right ? screen.width - _size - _edge : _edge,
          top + (bottom - top) * _y,
        );
        final at = _drag ?? rested;
        final lit = widget.listening || _talking;
        return Stack(
          children: [
            AnimatedPositioned(
              // Follows the finger exactly; glides when it settles.
              duration: _drag != null
                  ? Duration.zero
                  : const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              left: at.dx,
              top: at.dy,
              child: Listener(
                onPointerDown: _down,
                onPointerMove: (e) => _move(e, rested),
                onPointerUp: (_) => _up(screen, range),
                onPointerCancel: (_) => _up(screen, range),
                child: Semantics(
                  button: true,
                  label: 'Voice: hold to talk, drag to move',
                  child: TutorialAnchor(
                    target: TutorialTarget.voiceBubble,
                    // The bubble's own corner.
                    radius: 18,
                    child: AnimatedScale(
                      scale: lit ? 1.12 : (_drag != null ? 1.06 : 1),
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: _size,
                        height: _size,
                        decoration: BoxDecoration(
                          color: lit
                              ? CruBrand.ink500
                              : const Color(0xFF2C2C2E).withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.28),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: _Bars(level: widget.level, live: lit),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Five bars: a still waveform at rest, moving with the voice while
/// listening.
class _Bars extends StatelessWidget {
  const _Bars({required this.level, required this.live});

  final ValueListenable<double> level;
  final bool live;

  static const _shape = [0.45, 0.8, 1.0, 0.7, 0.5];
  static const _height = 22.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: ValueListenableBuilder<double>(
        valueListenable: level,
        builder: (context, v, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _shape.length; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                width: 3,
                height:
                    6 +
                    (_height - 6) *
                        _shape[i] *
                        (live ? 0.35 + 0.65 * v : 0.7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
