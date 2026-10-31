import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Cards stacked like DetailsStack in a column that scrolls vertically and
/// comes to rest with a card's top at the top. One card changes at a time:
/// a wheel spin moves exactly one card (more ticks are ignored until the
/// wheel goes quiet), and a drag or fling settles at most one card from
/// where it started. Space below the last card lets it reach the top too.
class SnapColumn extends StatefulWidget {
  const SnapColumn({super.key, required this.children});

  final List<Widget> children;

  @override
  State<SnapColumn> createState() => _SnapColumnState();
}

class _SnapColumnState extends State<SnapColumn> {
  final ScrollController _controller = ScrollController();
  final GlobalKey _content = GlobalKey(debugLabel: 'snap column');
  final List<GlobalKey> _cards = [];

  /// Each card's top and height, measured after the frame that laid them
  /// out. The physics may ask during layout, when sizes can't be read.
  List<({double top, double height})> _measured = const [];
  bool _measureQueued = false;

  /// The column's height, and the empty space below the last card that
  /// lets its top reach the top of the column.
  double _view = 0;
  double _tail = 0;

  /// Where the column rested when the current drag began.
  double? _dragFrom;

  /// A wheel move is running, or the wheel hasn't gone quiet since.
  bool _wheelBusy = false;
  final Stopwatch _sinceWheel = Stopwatch();
  static const _wheelQuiet = Duration(milliseconds: 160);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _queueMeasure() {
    if (_measureQueued) return;
    _measureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureQueued = false;
      if (!mounted) return;
      _measured = _measure();
      final last = _measured.lastOrNull;
      final tail = last == null
          ? 0.0
          : (_view - last.height).clamp(0.0, double.infinity);
      if ((tail - _tail).abs() > 0.5) setState(() => _tail = tail);
    });
  }

  List<({double top, double height})> _measure() {
    final content = _content.currentContext?.findRenderObject();
    if (content is! RenderBox) return const [];
    return [
      for (final key in _cards)
        if (key.currentContext?.findRenderObject() case final RenderBox card
            when card.hasSize)
          (
            top: card.localToGlobal(Offset.zero, ancestor: content).dy,
            height: card.size.height,
          ),
    ];
  }

  /// Where the column may rest: each card's top, the bottom of a card
  /// taller than the column, and the very ends.
  List<double> _stops(ScrollMetrics m) {
    final min = m.minScrollExtent;
    final max = m.maxScrollExtent;
    return <double>{
      min,
      for (final c in _measured) ...[
        c.top.clamp(min, max),
        if (c.height > m.viewportDimension)
          (c.top + c.height - m.viewportDimension).clamp(min, max),
      ],
      max,
    }.toList()..sort();
  }

  /// The next stop from [from], down or up; [from] itself when there is
  /// none that way.
  double _next(ScrollMetrics m, double from, {required bool down}) {
    const slack = 0.5;
    final stops = _stops(m);
    if (down) {
      return stops.firstWhere((s) => s > from + slack, orElse: () => from);
    }
    return stops.lastWhere((s) => s < from - slack, orElse: () => from);
  }

  double _nearest(ScrollMetrics m, double to) =>
      _stops(m).reduce((a, b) => (a - to).abs() <= (b - to).abs() ? a : b);

  /// Where a drag or fling settles: one card on from where it began, in
  /// its direction; a nudge (under a fifth of the column, no fling) goes
  /// back.
  double _settle(ScrollMetrics m, double velocity) {
    final at = m.pixels;
    final from = _dragFrom ?? _nearest(m, at);
    final fling = velocity.abs() > 300;
    final moved = at - from;
    if (!fling && moved.abs() < m.viewportDimension / 5) return from;
    final down = fling ? velocity > 0 : moved > 0;
    return _next(m, from, down: down);
  }

  /// The wheel: one spin, one card.
  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    // Registered before the scroll view's own handler, so it wins and the
    // view doesn't also scroll by the tick.
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      final dy = (e as PointerScrollEvent).scrollDelta.dy;
      _sinceWheel
        ..reset()
        ..start();
      if (_wheelBusy || dy == 0) return;
      final position = _controller.position;
      final from = _nearest(position, position.pixels);
      final target = _next(position, from, down: dy > 0);
      if ((target - position.pixels).abs() < 0.5) return;
      _wheelBusy = true;
      position
          .animateTo(
            target,
            duration: CruMotion.of(context),
            curve: CruMotion.curve,
          )
          .whenComplete(_wheelSettle);
    });
  }

  void _wheelSettle() {
    final left = _wheelQuiet - _sinceWheel.elapsed;
    if (left <= Duration.zero) {
      _wheelBusy = false;
      return;
    }
    Future.delayed(left, () {
      if (mounted) _wheelSettle();
    });
  }

  @override
  Widget build(BuildContext context) {
    final children = widget.children;
    while (_cards.length < children.length) {
      _cards.add(GlobalKey(debugLabel: 'snap card ${_cards.length}'));
    }
    _queueMeasure();
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollStartNotification && n.dragDetails != null) {
          _dragFrom = _nearest(n.metrics, n.metrics.pixels);
        } else if (n is ScrollEndNotification) {
          _dragFrom = null;
        }
        return false;
      },
      // Cards that grow or shrink later (data arriving) change the extent.
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          _queueMeasure();
          return false;
        },
        child: LayoutBuilder(
          builder: (context, box) {
            if (box.maxHeight != _view) {
              _view = box.maxHeight;
              _queueMeasure();
            }
            return SingleChildScrollView(
              controller: _controller,
              physics: _CardSnapPhysics(
                ready: () => _measured.isNotEmpty,
                settle: _settle,
              ),
              // Inside the scroll view, so it hears the wheel first.
              child: Listener(
                onPointerSignal: _onWheel,
                child: Column(
                  key: _content,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0) const SizedBox(height: CruSpace.cardGap),
                      KeyedSubtree(key: _cards[i], child: children[i]),
                    ],
                    SizedBox(height: _tail),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CardSnapPhysics extends ScrollPhysics {
  const _CardSnapPhysics({
    required this.ready,
    required this.settle,
    super.parent,
  });

  /// Firmer than the default scroll spring: it pulls into place quickly
  /// (about 200 ms) and doesn't overshoot.
  static final SpringDescription _snapSpring =
      SpringDescription.withDampingRatio(mass: 0.5, stiffness: 600, ratio: 1);

  final bool Function() ready;
  final double Function(ScrollMetrics position, double velocity) settle;

  @override
  _CardSnapPhysics applyTo(ScrollPhysics? ancestor) => _CardSnapPhysics(
    ready: ready,
    settle: settle,
    parent: buildParent(ancestor),
  );

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final free = super.createBallisticSimulation(position, velocity);
    if (position.outOfRange || !ready()) return free;
    final target = settle(position, velocity);
    if ((target - position.pixels).abs() < toleranceFor(position).distance) {
      return null;
    }
    return ScrollSpringSimulation(
      _snapSpring,
      position.pixels,
      target,
      velocity,
      tolerance: toleranceFor(position),
    );
  }
}
