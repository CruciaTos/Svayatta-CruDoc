import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Phone search, the Instagram way: when a [SearchLiftField] inside this
/// widget takes focus, the page slides up until the field sits [top] px
/// from this widget's top, everything above the field fades out, and the
/// list under it grows to fill the screen. Cancel, Back, or leaving the
/// field empty brings the page back.
///
/// Wrap a phone page body that fills its height (a Column with an
/// Expanded list, or a scroll view). Outside one, search fields behave as
/// before.
class SearchLift extends StatefulWidget {
  const SearchLift({
    super.key,
    required this.child,
    this.top = CruSpace.s8,
    this.avoidKeyboard = false,
    this.handleBack = true,
  });

  final Widget child;

  /// Where the field comes to rest, from this widget's top.
  final double top;

  /// Shrink the page by the keyboard's height while lifted, for hosts
  /// whose scaffold doesn't resize for the keyboard.
  final bool avoidKeyboard;

  /// Back closes the search instead of leaving the page.
  final bool handleBack;

  static SearchLiftState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LiftScope>()?.state;

  @override
  State<SearchLift> createState() => SearchLiftState();
}

class SearchLiftState extends State<SearchLift>
    with SingleTickerProviderStateMixin {
  /// Long enough to read as one glide over a few hundred pixels.
  static const _duration = Duration(milliseconds: 320);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _duration,
  );
  late final Animation<double> animation = CurvedAnimation(
    parent: _c,
    curve: CruMotion.curve,
    reverseCurve: Curves.easeInCubic,
  );
  final _page = GlobalKey();
  bool _active = false;

  /// How far the page travels, and the field's top in page coordinates.
  double _lift = 0;
  double _line = 0;
  VoidCallback? _clear;

  bool get active => _active;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _focusChanged(
    BuildContext field,
    bool focused, {
    required bool hasQuery,
    required VoidCallback clear,
  }) {
    _clear = clear;
    if (focused) {
      _open(field);
    } else if (!hasQuery) {
      _close();
    }
  }

  void _open(BuildContext field) {
    if (_active) return;
    final box = field.findRenderObject() as RenderBox?;
    final page = _page.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || page == null || !box.attached) return;
    // In page coordinates, so a glide already under way doesn't skew it.
    final y = box.localToGlobal(Offset.zero, ancestor: page).dy;
    setState(() {
      _active = true;
      _line = y;
      _lift = math.max(0, y - widget.top);
    });
    _c.duration = CruMotion.of(context, _duration);
    _c.forward();
  }

  void _close() {
    if (!_active) return;
    setState(() => _active = false);
    _c.duration = CruMotion.of(context, _duration);
    _c.reverse();
  }

  /// Clears the query, drops the keyboard and brings the page back.
  void cancel() {
    _clear?.call();
    FocusManager.instance.primaryFocus?.unfocus();
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final inset = widget.avoidKeyboard
        ? MediaQuery.viewInsetsOf(context).bottom
        : 0.0;
    Widget body = _LiftScope(
      state: this,
      active: _active,
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, box) => AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final t = animation.value;
              final dy = _lift * t;
              final height = math.max(0.0, box.maxHeight + dy - inset * t);
              return _FadeAbove(
                line: _line - dy,
                opacity: 1 - t,
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: height,
                  maxHeight: height,
                  child: Transform.translate(
                    offset: Offset(0, -dy),
                    child: child,
                  ),
                ),
              );
            },
            child: KeyedSubtree(key: _page, child: widget.child),
          ),
        ),
      ),
    );
    if (widget.handleBack) {
      body = PopScope(
        canPop: !_active,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) cancel();
        },
        child: body,
      );
    }
    return body;
  }
}

class _LiftScope extends InheritedWidget {
  const _LiftScope({
    required this.state,
    required this.active,
    required super.child,
  });

  final SearchLiftState state;
  final bool active;

  @override
  bool updateShouldNotify(_LiftScope old) => active != old.active;
}

/// A search field that lifts the nearest [SearchLift] when focused, with
/// Cancel sliding in beside it while lifted. [onClear] empties the query.
class SearchLiftField extends StatelessWidget {
  const SearchLiftField({
    super.key,
    required this.controller,
    required this.onClear,
    required this.child,
  });

  final TextEditingController controller;
  final VoidCallback onClear;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lift = SearchLift.maybeOf(context);
    if (lift == null) return child;
    return Row(
      children: [
        Expanded(
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (focused) => lift._focusChanged(
              context,
              focused,
              hasQuery: controller.text.isNotEmpty,
              clear: onClear,
            ),
            child: child,
          ),
        ),
        AnimatedBuilder(
          animation: lift.animation,
          builder: (context, _) {
            final t = lift.animation.value;
            if (t == 0) return const SizedBox.shrink();
            return ClipRect(
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: t,
                child: Opacity(
                  opacity: t,
                  child: Padding(
                    padding: const EdgeInsets.only(left: CruSpace.s12),
                    child: CruLink(label: 'Cancel', onPressed: lift.cancel),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Fades whatever is painted above [line] to [opacity]; below it, untouched.
class _FadeAbove extends SingleChildRenderObjectWidget {
  const _FadeAbove({required this.line, required this.opacity, super.child});

  final double line;
  final double opacity;

  @override
  _RenderFadeAbove createRenderObject(BuildContext context) =>
      _RenderFadeAbove(line, opacity);

  @override
  void updateRenderObject(BuildContext context, _RenderFadeAbove r) => r
    ..line = line
    ..opacity = opacity;
}

class _RenderFadeAbove extends RenderProxyBox {
  _RenderFadeAbove(this._line, this._opacity);

  /// Soft edge so the field's shadow isn't cut in a hard line.
  static const _feather = 16.0;

  double _line;
  set line(double v) {
    if (v == _line) return;
    _line = v;
    markNeedsPaint();
  }

  double _opacity;
  set opacity(double v) {
    if (v == _opacity) return;
    final wasFaded = _faded;
    _opacity = v;
    if (wasFaded != _faded) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  bool get _faded => _opacity < 1;

  @override
  bool get alwaysNeedsCompositing => child != null && _faded;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    if (!_faded || size.height <= 0) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    final h = size.height;
    final end = (_line / h).clamp(0.0, 1.0);
    final start = ((_line - _feather) / h).clamp(0.0, 1.0);
    final dim = Colors.black.withValues(alpha: _opacity);
    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [dim, dim, Colors.black, Colors.black],
      stops: [0, start, end, 1],
    ).createShader(Offset.zero & size);
    final mask = (layer as ShaderMaskLayer?) ?? ShaderMaskLayer();
    mask
      ..shader = shader
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    layer = mask;
    context.pushLayer(mask, super.paint, offset);
  }
}
