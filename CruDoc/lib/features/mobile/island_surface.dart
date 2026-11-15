import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// Where one island state's shape goes, and what it is made of. Carried to
/// the render object as parent data.
@immutable
class IslandShape {
  const IslandShape({
    this.width,
    this.minWidth = 0,
    this.minHeight = 0,
    required this.top,
    required this.centerX,
    required this.rTop,
    required this.rBot,
    this.stadium = false,
  });

  /// Exact width, or null to size to the child (at least [minWidth]).
  final double? width;
  final double minWidth;
  final double minHeight;
  final double top;
  final double centerX;
  final double rTop;
  final double rBot;

  /// All corner radii are half the height (the rest pill).
  final bool stadium;

  @override
  bool operator ==(Object other) =>
      other is IslandShape &&
      other.width == width &&
      other.minWidth == minWidth &&
      other.minHeight == minHeight &&
      other.top == top &&
      other.centerX == centerX &&
      other.rTop == rTop &&
      other.rBot == rBot &&
      other.stadium == stadium;

  @override
  int get hashCode => Object.hash(
    width,
    minWidth,
    minHeight,
    top,
    centerX,
    rTop,
    rBot,
    stadium,
  );
}

class _Slot {
  const _Slot(this.key, this.shape, this.child);
  final Object key;
  final IslandShape shape;
  final Widget child;
}

/// The island's single black shape. [child] is the current state's content
/// (keyed by [stateKey]); when the key changes, the shape morphs to the new
/// [shape] while the old content fades out and the new fades in. When only
/// the size changes under the same key, the shape alone eases to it.
///
/// One controller drives everything; layout is done once per change and
/// each animation frame only repaints.
class IslandSurface extends StatefulWidget {
  const IslandSurface({
    super.key,
    required this.stateKey,
    required this.shape,
    required this.superellipse,
    required this.child,
  });

  final Object stateKey;
  final IslandShape shape;

  /// Continuous corners (iOS) instead of circular ones (Android).
  final bool superellipse;
  final Widget child;

  @override
  State<IslandSurface> createState() => _IslandSurfaceState();
}

class _IslandSurfaceState extends State<IslandSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, value: 1)
    ..addStatusListener(_onStatus);
  final _roKey = GlobalKey();
  _Slot? _out;
  late _Slot _in;
  bool _reduce = false;

  @override
  void initState() {
    super.initState();
    _in = _Slot(widget.stateKey, widget.shape, widget.child);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
  }

  RenderIslandSurface? get _ro =>
      _roKey.currentContext?.findRenderObject() as RenderIslandSurface?;

  @override
  void didUpdateWidget(IslandSurface old) {
    super.didUpdateWidget(old);
    final next = _Slot(widget.stateKey, widget.shape, widget.child);
    if (widget.stateKey != old.stateKey) {
      // Snapshot what is on screen right now (mid-flight or not) before the
      // controller restarts: the new morph starts from it, never from the
      // old target.
      _ro?.freeze(resize: false);
      _out = _in;
      _in = next;
      _run(
        _reduce
            ? 160
            : widget.shape.stadium
            ? 460
            : 520,
      );
    } else {
      _in = next;
    }
  }

  void _run(int ms) {
    _c.duration = Duration(milliseconds: ms);
    _c.forward(from: 0);
  }

  void _onStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed && _out != null && mounted) {
      setState(() => _out = null);
    }
  }

  /// The render object found a new size under the same key (it has already
  /// snapshotted and holds the old visual): ease to it over 320 ms.
  void _onRetarget() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _run(_reduce ? 160 : 320);
      _ro?.release();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _slot(_Slot s) =>
      _IslandSlot(key: ValueKey(s.key), shape: s.shape, child: s.child);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: _IslandRender(
        key: _roKey,
        animation: _c,
        superellipse: widget.superellipse,
        snapShape: _reduce,
        onRetarget: _onRetarget,
        children: [if (_out != null) _slot(_out!), _slot(_in)],
      ),
    );
  }
}

class _IslandSlot extends ParentDataWidget<_IslandParentData> {
  const _IslandSlot({super.key, required this.shape, required super.child});

  final IslandShape shape;

  @override
  void applyParentData(RenderObject renderObject) {
    final pd = renderObject.parentData! as _IslandParentData;
    if (pd.shape != shape) {
      pd.shape = shape;
      renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => IslandSurface;
}

class _IslandRender extends MultiChildRenderObjectWidget {
  const _IslandRender({
    super.key,
    required this.animation,
    required this.superellipse,
    required this.snapShape,
    required this.onRetarget,
    required super.children,
  });

  final Animation<double> animation;
  final bool superellipse;
  final bool snapShape;
  final VoidCallback onRetarget;

  @override
  RenderIslandSurface createRenderObject(BuildContext context) =>
      RenderIslandSurface(
        animation: animation,
        superellipse: superellipse,
        snapShape: snapShape,
        onRetarget: onRetarget,
      );

  @override
  void updateRenderObject(BuildContext context, RenderIslandSurface ro) {
    ro
      ..animation = animation
      ..superellipse = superellipse
      ..snapShape = snapShape
      ..onRetarget = onRetarget;
  }
}

class _IslandParentData extends ContainerBoxParentData<RenderBox> {
  IslandShape? shape;
}

/// A visual state of the shape: rect plus the two corner radii.
class _Vis {
  const _Vis(this.rect, this.rTop, this.rBot);
  final Rect rect;
  final double rTop;
  final double rBot;

  static _Vis lerp(_Vis a, _Vis b, double t) => _Vis(
    Rect.lerp(a.rect, b.rect, t)!,
    lerpDouble(a.rTop, b.rTop, t)!,
    lerpDouble(a.rBot, b.rBot, t)!,
  );

  bool near(_Vis o) =>
      (rect.left - o.rect.left).abs() < 0.5 &&
      (rect.top - o.rect.top).abs() < 0.5 &&
      (rect.width - o.rect.width).abs() < 0.5 &&
      (rect.height - o.rect.height).abs() < 0.5;
}

/// Sizes to the whole overlay and draws at most two states: the outgoing
/// one (first child) and the incoming one (last child), both inside the one
/// moving black shape.
class RenderIslandSurface extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _IslandParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _IslandParentData> {
  RenderIslandSurface({
    required Animation<double> animation,
    required bool superellipse,
    required bool snapShape,
    required this.onRetarget,
  }) : _animation = animation,
       _superellipse = superellipse,
       _snap = snapShape;

  static const _curve = Cubic(0.2, 0.0, 0.0, 1.0);
  static const _fadeOut = Interval(0.0, 0.30, curve: Curves.easeIn);
  static const _fadeIn = Interval(0.15, 0.62, curve: Curves.easeOut);

  Animation<double> _animation;
  Animation<double> get animation => _animation;
  set animation(Animation<double> v) {
    if (identical(v, _animation)) return;
    if (attached) _animation.removeListener(markNeedsPaint);
    _animation = v;
    if (attached) _animation.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  bool _superellipse;
  set superellipse(bool v) {
    if (v == _superellipse) return;
    _superellipse = v;
    markNeedsPaint();
  }

  bool _snap;
  set snapShape(bool v) {
    if (v == _snap) return;
    _snap = v;
    markNeedsPaint();
  }

  VoidCallback onRetarget;

  // The shape's journey: from this visual (null at first) to the target the
  // incoming child lays out to.
  _Vis? _from;
  _Vis? _to;
  // Opacities at the start of the journey (the fades run from these).
  double _fromOut = 1;
  double _fromIn = 1;
  // A key change snapshotted the shape and the next layout's new target is
  // part of it. A retarget found in layout holds t at 0 until restarted.
  bool _expectRetarget = false;
  bool _hold = false;

  double get _t => _hold ? 0.0 : _animation.value;
  bool get _hasOutgoing => childCount > 1;

  _Vis get _visual {
    final to = _to!;
    final from = _from;
    if (from == null || _snap) return to;
    return _Vis.lerp(from, to, _curve.transform(_t));
  }

  double get _outOpacity => _fromOut * (1 - _fadeOut.transform(_t));
  double get _inOpacity => _fromIn + (1 - _fromIn) * _fadeIn.transform(_t);

  /// Records what is on screen now as the start of the next journey.
  /// [resize]: the same state keeps showing (no cross-fade), so both
  /// opacities carry on from where they are. Otherwise the incoming state
  /// becomes the outgoing one, starting at its current opacity.
  void freeze({required bool resize}) {
    if (_to == null) return;
    final v = _visual;
    final out = _hasOutgoing ? _outOpacity : 0.0;
    final inn = _inOpacity;
    _from = v;
    if (resize) {
      _fromOut = out;
      _fromIn = inn;
    } else {
      _fromOut = inn;
      _fromIn = 0;
      _expectRetarget = true;
    }
  }

  /// Ends the hold set when a resize was found: the controller has been
  /// restarted from 0, so painting follows it again.
  void release() {
    _hold = false;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _animation.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool get alwaysNeedsCompositing => true; // opacity layers inside a clip

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _IslandParentData) {
      child.parentData = _IslandParentData();
    }
  }

  IslandShape _shapeOf(RenderBox c) =>
      (c.parentData! as _IslandParentData).shape!;

  @override
  void performLayout() {
    RenderBox? c = firstChild;
    while (c != null) {
      final s = _shapeOf(c);
      final w = s.width;
      c.layout(
        BoxConstraints(
          minWidth: w ?? s.minWidth,
          maxWidth: w ?? size.width,
          maxHeight: size.height,
        ),
        parentUsesSize: true,
      );
      c = childAfter(c);
    }
    final inc = lastChild;
    if (inc == null) return;
    final s = _shapeOf(inc);
    final w = s.width ?? inc.size.width;
    final h = math.max(inc.size.height, s.minHeight);
    final next = _Vis(
      Rect.fromLTWH(s.centerX - w / 2, s.top, w, h),
      s.stadium ? h / 2 : s.rTop,
      s.stadium ? h / 2 : s.rBot,
    );
    final old = _to;
    if (old == null) {
      _to = next;
    } else if (_expectRetarget) {
      _expectRetarget = false;
      _to = next;
    } else if (!old.near(next) ||
        old.rTop != next.rTop ||
        old.rBot != next.rBot) {
      // Same state, new size: snapshot, hold the old look for this frame,
      // and have the State run the 320 ms ease.
      freeze(resize: true);
      _to = next;
      _hold = true;
      onRetarget();
    } else {
      _to = next;
    }
  }

  RRect _rrect(_Vis v) {
    final r = v.rect;
    final m = math.min(r.width, r.height) / 2;
    final t = Radius.circular(math.min(v.rTop, m));
    final b = Radius.circular(math.min(v.rBot, m));
    return RRect.fromRectAndCorners(
      r,
      topLeft: t,
      topRight: t,
      bottomLeft: b,
      bottomRight: b,
    );
  }

  RSuperellipse _squircle(RRect r) => RSuperellipse.fromRectAndCorners(
    r.outerRect,
    topLeft: r.tlRadius,
    topRight: r.trRadius,
    bottomLeft: r.blRadius,
    bottomRight: r.brRadius,
  );

  Offset _childOffset(RenderBox c, _Vis v) =>
      Offset(v.rect.center.dx - c.size.width / 2, v.rect.top);

  static final _black = Paint()..color = const Color(0xFF000000);

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_to == null) return;
    final v = _visual;
    final rr = _rrect(v);
    void content(PaintingContext ctx, Offset o) {
      if (_superellipse) {
        ctx.canvas.drawRSuperellipse(_squircle(rr).shift(o), _black);
      } else {
        ctx.canvas.drawRRect(rr.shift(o), _black);
      }
      final inc = lastChild!;
      if (_hasOutgoing) _paintChild(ctx, o, firstChild!, _outOpacity, v);
      _paintChild(ctx, o, inc, _inOpacity, v);
    }

    if (_superellipse) {
      context.pushClipRSuperellipse(
        needsCompositing,
        offset,
        v.rect,
        _squircle(rr),
        content,
      );
    } else {
      context.pushClipRRect(needsCompositing, offset, v.rect, rr, content);
    }
  }

  void _paintChild(
    PaintingContext ctx,
    Offset o,
    RenderBox child,
    double opacity,
    _Vis v,
  ) {
    final alpha = (opacity.clamp(0.0, 1.0) * 255).round();
    if (alpha == 0) return;
    final at = o + _childOffset(child, v);
    if (alpha == 255) {
      ctx.paintChild(child, at);
    } else {
      ctx.pushOpacity(at, alpha, (c, p) => c.paintChild(child, p));
    }
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_to == null) return false;
    final v = _visual;
    if (!_rrect(v).contains(position)) return false;
    final child = lastChild;
    if (child != null) {
      final hit = result.addWithPaintOffset(
        offset: _childOffset(child, v),
        position: position,
        hitTest: (r, p) => child.hitTest(r, position: p),
      );
      if (hit) return true;
    }
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    final c = lastChild;
    if (c != null) visitor(c);
  }
}
