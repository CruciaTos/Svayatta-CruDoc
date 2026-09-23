import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:doctor_management_app/core/theme/cru_theme.dart';

/// Hover, press and keyboard behaviour shared by every tappable Calm
/// Clinical element: hover changes the fill, press scales to 0.98,
/// Enter/Space activate, and motion respects reduced-motion settings.
class CruPressable extends StatefulWidget {
  const CruPressable({
    super.key,
    required this.onTap,
    required this.builder,
    this.semanticLabel,
    this.tooltip,
    this.autofocus = false,
    this.focusNode,
    this.scaleOnPress = true,
  });

  final VoidCallback? onTap;

  /// Builds the content for the current hover state.
  final Widget Function(BuildContext context, bool hovered) builder;
  final String? semanticLabel;
  final String? tooltip;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool scaleOnPress;

  @override
  State<CruPressable> createState() => _CruPressableState();
}

class _CruPressableState extends State<CruPressable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    Widget child = widget.builder(context, _enabled && (_hovered || _focused));

    if (widget.scaleOnPress) {
      child = AnimatedScale(
        scale: _pressed ? CruMotion.pressScale : 1,
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        child: child,
      );
    }

    child = FocusableActionDetector(
      enabled: _enabled,
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      mouseCursor:
          _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        child: child,
      ),
    );

    if (_focused) {
      // Keyboard focus ring in the accent, drawn outside the element.
      child = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(CruRadius.control),
            side: BorderSide(
              color: c.accent,
              width: 2,
              strokeAlign: BorderSide.strokeAlignOutside,
            ),
          ),
        ),
        child: child,
      );
    }

    child = Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      child: child,
    );

    if (widget.tooltip != null) {
      child = Tooltip(message: widget.tooltip!, child: child);
    }
    if (cruIsTouchPlatform) child = CruTouchTarget(child: child);
    return child;
  }
}

/// Phones and tablets (Android, iOS): fingers, not a mouse pointer.
bool get cruIsTouchPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Smallest comfortable touch target (Material and Apple guidance).
const double kCruMinTouchTarget = 44;

/// Lets a touch just outside a small control still land on it: taps
/// within a [kCruMinTouchTarget] square around its centre hit the child.
/// Layout and painting don't change, so the design stays pixel-exact.
class CruTouchTarget extends SingleChildRenderObjectWidget {
  const CruTouchTarget({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTouchTarget();
}

class _RenderTouchTarget extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (super.hitTest(result, position: position)) return true;
    final child = this.child;
    if (child == null) return false;
    final dx = (kCruMinTouchTarget - size.width).clamp(0.0, double.infinity) / 2;
    final dy = (kCruMinTouchTarget - size.height).clamp(0.0, double.infinity) / 2;
    if (dx == 0 && dy == 0) return false;
    final area = Rect.fromLTRB(-dx, -dy, size.width + dx, size.height + dy);
    if (!area.contains(position)) return false;
    // Same approach as Material's padded tap targets: hit the centre.
    final center = child.size.center(Offset.zero);
    return result.addWithRawTransform(
      transform: MatrixUtils.forceToPoint(center),
      position: center,
      hitTest: (result, position) => child.hitTest(result, position: center),
    );
  }
}

/// Hover shade for filled buttons: ~6% darker in Day, lighter in Evening.
Color cruHoverShade(Color fill, CruColors c) => Color.lerp(
      fill,
      c.isEvening ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
      0.06,
    )!;
