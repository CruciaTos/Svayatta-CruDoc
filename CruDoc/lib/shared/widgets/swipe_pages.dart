import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Fling velocity (logical px/s) that keeps the next page whatever the
/// distance dragged.
const double _kFlingVelocity = 300;

/// A screen's sub-screens side by side, like pages in a row. Dragging
/// sideways (touch, pen, trackpad or mouse) pulls the next page in with
/// the pointer; let go past half way, or flick, and it stays, else it
/// springs back. Changing [value] from outside (the switcher above)
/// slides the same way. Parts every page shares (title, page switcher)
/// stay put: wrap them in [SwipePinned].
///
/// Fills its space when its height is bounded; inside a scrolling list it
/// takes the open page's height, and the page coming in hangs below it
/// until it lands.
///
/// With [axis] vertical the pages are stacked instead (the next one below)
/// and must fill a bounded height; a mouse wheel then steps one page per
/// turn too.
class SwipePages<T extends Object> extends StatefulWidget {
  const SwipePages({
    super.key,
    required this.values,
    required this.value,
    required this.onChanged,
    required this.builder,
    this.pageOf,
    this.slides,
    this.axis = Axis.horizontal,
  });

  final Axis axis;

  /// The pages, in swipe order.
  final List<T> values;

  /// The value shown.
  final T value;

  /// A drag landed on another page.
  final ValueChanged<T> onChanged;

  final Widget Function(BuildContext context, T value) builder;

  /// The page in [values] that [value] is shown on, when several values
  /// share one (Schedule's Day sits on Week's page). The page then shows
  /// whichever of them it showed last.
  final T Function(T value)? pageOf;

  /// Whether changing [value] from outside slides; false swaps in place
  /// (for views that animate the change themselves). Same-page changes
  /// always swap in place.
  final bool Function(T from, T to)? slides;

  @override
  State<SwipePages<T>> createState() => _SwipePagesState<T>();
}

class _SwipePagesState<T extends Object> extends State<SwipePages<T>>
    with SingleTickerProviderStateMixin {
  /// How far the page beside the open one has come in (0 to 1).
  late final AnimationController _slide = AnimationController(vsync: this);

  late T _open = widget.value;
  T? _beside;

  /// +1 when [_beside] is on the right (the next page), -1 on the left.
  int _side = 1;

  /// Where the running slide ends (null while none is running).
  T? _headed;

  /// Bumped whenever a slide is cut short, so it can't finish later.
  int _run = 0;

  bool _dragging = false;
  double _drag = 0;
  double _width = 1;

  /// Each shared page's last value.
  final Map<T, T> _shownOn = {};

  /// Keeps a page's state as it moves from beside to open.
  final Map<T, GlobalKey> _keys = {};

  @override
  void initState() {
    super.initState();
    _shownOn[_page(_open)] = _open;
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  T _page(T value) => widget.pageOf?.call(value) ?? value;

  int _indexOf(T value) => widget.values.indexOf(_page(value));

  /// The value next to the open page on [side], if there is one.
  T? _neighbour(int side) {
    final i = _indexOf(_open);
    if (i < 0) return null;
    final j = i + side;
    if (j < 0 || j >= widget.values.length) return null;
    final page = widget.values[j];
    return _shownOn[page] ?? page;
  }

  /// Stops any slide and shows [value] alone (no rebuild).
  void _reset(T value) {
    _shownOn[_page(value)] = value;
    _run++;
    _slide.stop();
    _slide.value = 0;
    _open = value;
    _beside = null;
    _headed = null;
  }

  /// Ends a slide on [value], reporting it if a drag brought it in.
  void _land(T value) {
    final dragged = value != widget.value;
    setState(() => _reset(value));
    if (dragged) {
      HapticFeedback.selectionClick();
      widget.onChanged(value);
    }
  }

  /// Slides to [end]: the page beside (all the way in) or the open one
  /// (back out), taking the rest of the motion's time.
  void _slideTo(T end) {
    final target = end == _beside ? 1.0 : 0.0;
    final full = CruMotion.of(context, CruMotion.standard);
    final run = ++_run;
    _headed = end;
    _slide
        .animateTo(
          target,
          duration: full * (target - _slide.value).abs(),
          curve: CruMotion.curve,
        )
        .then((_) {
          if (run == _run && mounted) _land(end);
        });
  }

  @override
  void didUpdateWidget(SwipePages<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.value;
    // Nothing new: already open, or already on its way.
    if (next == _open || next == _headed) return;
    final from = _indexOf(_open);
    final to = _indexOf(next);
    final slides = widget.slides?.call(_open, next) ?? true;
    if (_dragging ||
        _beside != null ||
        !slides ||
        from < 0 ||
        to < 0 ||
        from == to) {
      _reset(next);
      return;
    }
    _beside = next;
    _side = to > from ? 1 : -1;
    _slideTo(next);
  }

  void _onDragStart(DragStartDetails _) {
    final headed = _headed;
    if (headed != null) _land(headed);
    _dragging = true;
    _drag = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    _drag += details.primaryDelta ?? 0;
    final side = _drag < 0 ? 1 : -1;
    final beside = _drag == 0 ? null : _neighbour(side);
    if (beside != _beside || side != _side) {
      setState(() {
        _beside = beside;
        _side = side;
      });
    }
    _slide.value = beside == null ? 0 : (_drag.abs() / _width).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    final beside = _beside;
    if (beside == null) return;
    final v = details.primaryVelocity ?? 0;
    final keep = v.abs() >= _kFlingVelocity
        ? (v < 0 ? 1 : -1) == _side
        : _slide.value >= 0.5;
    _slideTo(keep ? beside : _open);
  }

  void _onDragCancel() {
    if (!_dragging) return;
    _dragging = false;
    if (_beside != null) _slideTo(_open);
  }

  /// Stacked pages: one wheel turn steps one page (down = next).
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final dy = event.scrollDelta.dy;
    if (dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      // One page at a time: turns during a slide are dropped.
      if (_dragging || _headed != null || _beside != null) return;
      final side = dy > 0 ? 1 : -1;
      final next = _neighbour(side);
      if (next == null) return;
      setState(() {
        _beside = next;
        _side = side;
      });
      _slideTo(next);
    });
  }

  Widget _pageFor(T value) => KeyedSubtree(
    key: _keys.putIfAbsent(value, () => GlobalKey(debugLabel: '$value page')),
    child: RepaintBoundary(child: widget.builder(context, value)),
  );

  @override
  Widget build(BuildContext context) {
    final open = _open;
    final beside = _beside;
    final vertical = widget.axis == Axis.vertical;
    // Pages that left (months gone by) don't keep their keys.
    _keys.removeWhere(
      (v, _) => v != open && v != beside && !widget.values.contains(v),
    );
    // Built once per state change, so the pages don't rebuild every frame
    // of a slide.
    final openPage = _pageFor(open);
    final besidePage = beside == null ? null : _pageFor(beside);

    const devices = {
      PointerDeviceKind.touch,
      PointerDeviceKind.stylus,
      PointerDeviceKind.invertedStylus,
      PointerDeviceKind.trackpad,
      PointerDeviceKind.mouse,
    };
    Widget pager = LayoutBuilder(
      builder: (context, box) {
        final bounded = vertical || box.hasBoundedHeight;
        final extent = vertical ? box.maxHeight : box.maxWidth;
        _width = extent.isFinite
            ? math.max(extent, 1)
            : MediaQuery.sizeOf(context).width;
        return ClipRect(
          // In a list the incoming page may be taller: clip the sides only.
          clipper: bounded ? null : const _SidesClipper(),
          child: AnimatedBuilder(
            animation: _slide,
            builder: (context, _) {
              final t = _slide.value;
              Widget shifted(T value, Widget page, double dx) =>
                  FractionalTranslation(
                    key: ValueKey(value),
                    translation: vertical ? Offset(0, dx) : Offset(dx, 0),
                    child: _PageSlot(
                      slide: _slide,
                      open: value == open,
                      side: _side,
                      width: _width,
                      axis: widget.axis,
                      child: page,
                    ),
                  );
              return Stack(
                fit: bounded ? StackFit.expand : StackFit.passthrough,
                clipBehavior: Clip.none,
                children: [
                  shifted(open, openPage, -_side * t),
                  if (beside != null)
                    bounded
                        ? shifted(beside, besidePage!, _side * (1 - t))
                        : Positioned(
                            key: ValueKey(beside),
                            top: 0,
                            left: 0,
                            right: 0,
                            child: shifted(
                              beside,
                              besidePage!,
                              _side * (1 - t),
                            ),
                          ),
                ],
              );
            },
          ),
        );
      },
    );
    if (vertical) {
      pager = Listener(onPointerSignal: _onPointerSignal, child: pager);
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      supportedDevices: devices,
      onHorizontalDragStart: vertical ? null : _onDragStart,
      onHorizontalDragUpdate: vertical ? null : _onDragUpdate,
      onHorizontalDragEnd: vertical ? null : _onDragEnd,
      onHorizontalDragCancel: vertical ? null : _onDragCancel,
      onVerticalDragStart: vertical ? _onDragStart : null,
      onVerticalDragUpdate: vertical ? _onDragUpdate : null,
      onVerticalDragEnd: vertical ? _onDragEnd : null,
      onVerticalDragCancel: vertical ? _onDragCancel : null,
      child: pager,
    );
  }
}

/// Where a page sits in the slide, for [SwipePinned] inside it.
class _PageSlot extends InheritedWidget {
  const _PageSlot({
    required this.slide,
    required this.open,
    required this.side,
    required this.width,
    required this.axis,
    required super.child,
  });

  final Animation<double> slide;
  final bool open;
  final int side;

  /// The page's extent along [axis].
  final double width;
  final Axis axis;

  /// The page's shift, in page widths.
  double get shift => open ? -side * slide.value : side * (1 - slide.value);

  @override
  bool updateShouldNotify(_PageSlot oldWidget) =>
      oldWidget.open != open ||
      oldWidget.side != side ||
      oldWidget.width != width ||
      oldWidget.axis != axis ||
      oldWidget.slide != slide;
}

/// A part of a page's header that stays put while the rest of the page
/// slides, so nothing in the header slides across anything else.
///
/// [SwipePinned.new] is for what every page shows alike (a title, the page
/// switcher): each page keeps its own copy and the one of the page more
/// than half in shows, so the copies must look the same.
/// [SwipePinned.fade] is for what each page has of its own in the header
/// (its summary, its buttons): it fades out in place as its page leaves
/// and the next page's fades in.
class SwipePinned extends StatelessWidget {
  const SwipePinned({super.key, required this.child}) : fade = false;

  const SwipePinned.fade({super.key, required this.child}) : fade = true;

  final Widget child;
  final bool fade;

  @override
  Widget build(BuildContext context) {
    final slot = context.dependOnInheritedWidgetOfExactType<_PageSlot>();
    if (slot == null) return child;
    return AnimatedBuilder(
      animation: slot.slide,
      child: child,
      builder: (context, child) {
        final t = slot.slide.value;
        final shown = slot.open ? t < 0.5 : t >= 0.5;
        final double opacity = !fade
            ? (shown ? 1 : 0)
            : slot.open
            ? (1 - 2 * t).clamp(0.0, 1.0)
            : (2 * t - 1).clamp(0.0, 1.0);
        final back = -slot.shift * slot.width;
        return Transform.translate(
          offset: slot.axis == Axis.vertical
              ? Offset(0, back)
              : Offset(back, 0),
          child: IgnorePointer(
            ignoring: !shown,
            child: Opacity(opacity: opacity, child: child),
          ),
        );
      },
    );
  }
}

/// Clips left and right only, so a taller page can hang below.
class _SidesClipper extends CustomClipper<Rect> {
  const _SidesClipper();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -size.height - 1e5, size.width, size.height + 1e5);

  @override
  bool shouldReclip(_SidesClipper oldClipper) => false;
}
