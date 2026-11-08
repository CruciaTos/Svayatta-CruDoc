import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/appointment_actions.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_format.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// What a dragged visit carries: the visit and the size of the block it was
/// picked up from (so the drop spot is worked out from the block's own
/// top left, wherever it was grabbed).
class ApptDragData {
  const ApptDragData(this.item, this.size);

  final ApptItem item;
  final Size size;
}

/// The time a dragged visit would land on, while one is being dragged. The
/// Week header shows it under the day being hovered.
abstract final class ApptDragHint {
  static final time = ValueNotifier<DateTime?>(null);
}

/// A one-day step of the Week columns (a drag held at the edge): the
/// columns start displaced by [dir] columns and slide to rest. Fired in
/// the same tick as the date change so both land in the same frame.
abstract final class ApptSlide {
  static final steps = ValueNotifier<({int seq, int dir})>((seq: 0, dir: 0));

  static void fire(int dir) =>
      steps.value = (seq: steps.value.seq + 1, dir: dir);
}

/// Where a drag would land: the snapped start and the box to outline.
typedef ApptDrop = ({DateTime start, Rect rect});

/// Rounds [minutes] to the nearest snap step and keeps it in [0, max].
int snapMinutes(double minutes, int max) {
  final snapped = (minutes / kApptSnapMinutes).round() * kApptSnapMinutes;
  return math.max(0, math.min(snapped, math.max(0, max)));
}

/// Lets a visit block be picked up and dropped on [ApptDropArea] to move it.
/// A mouse picks it up straight away; a finger holds first, so scrolling
/// still works. Visits that can't be rescheduled (seen, cancelled) stay put.
class ApptDraggable extends StatelessWidget {
  const ApptDraggable({
    super.key,
    required this.item,
    required this.feedback,
    required this.child,
  });

  final ApptItem item;

  /// The block that follows the pointer.
  final Widget feedback;
  final Widget child;

  static bool get _touch =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.fuchsia;

  @override
  Widget build(BuildContext context) {
    if (!ApptActions.canReschedule(item)) return child;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final data = ApptDragData(item, size);
        final lifted = Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: IgnorePointer(
              child: Opacity(opacity: 0.92, child: feedback),
            ),
          ),
        );
        final left = Opacity(opacity: 0.35, child: child);
        if (_touch) {
          return LongPressDraggable<ApptDragData>(
            data: data,
            rootOverlay: true,
            feedback: lifted,
            childWhenDragging: left,
            child: child,
          );
        }
        return Draggable<ApptDragData>(
          data: data,
          rootOverlay: true,
          feedback: lifted,
          childWhenDragging: left,
          child: child,
        );
      },
    );
  }
}

/// The grid a visit can be dropped on. [resolve] turns the dragged block's
/// top left (in this area's own coordinates) into a start time and an
/// outline; this widget draws the outline with the time in it, scrolls the
/// enclosing list when the block nears its top or bottom, and moves the
/// visit on drop.
class ApptDropArea extends ConsumerStatefulWidget {
  const ApptDropArea({
    super.key,
    required this.resolve,
    required this.ghostRadius,
    required this.child,
    this.stepDaysAtEdge = false,
  });

  /// Holding a dragged visit at the left or right edge moves the view back
  /// or on a day at a time, so it can reach days that are off screen.
  final bool stepDaysAtEdge;

  final ApptDrop? Function(Offset topLeft, ApptDragData data, Size area)
  resolve;
  final double ghostRadius;
  final Widget child;

  @override
  ConsumerState<ApptDropArea> createState() => _ApptDropAreaState();
}

class _ApptDropAreaState extends ConsumerState<ApptDropArea> {
  static const double _edge = 48;
  static const double _maxStep = 14;
  static const _stepEvery = Duration(milliseconds: 550);
  DateTime _lastStep = DateTime.fromMillisecondsSinceEpoch(0);

  ApptDrop? _hover;
  ApptDragData? _data;
  Offset? _global;
  Timer? _timer;

  RenderBox? get _box => context.findRenderObject() as RenderBox?;

  ApptDrop? _resolve(Offset global, ApptDragData data) {
    final box = _box;
    if (box == null || !box.hasSize) return null;
    return widget.resolve(box.globalToLocal(global), data, box.size);
  }

  void _update() {
    final data = _data;
    final global = _global;
    if (data == null || global == null) return;
    final next = _resolve(global, data);
    if (next?.start != _hover?.start || next?.rect != _hover?.rect) {
      setState(() => _hover = next);
      ApptDragHint.time.value = next?.start;
    }
  }

  void _onMove(DragTargetDetails<ApptDragData> d) {
    _data = d.data;
    _global = d.offset;
    _update();
    _timer ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  /// Moves the view a day back or on while the block is held at a side.
  void _stepAtEdge(Offset global, ApptDragData data) {
    final box = _box;
    if (box == null || !box.hasSize) return;
    final x = box.globalToLocal(global).dx;
    final dir = x < _edge
        ? -1
        : (x + data.size.width > box.size.width - _edge ? 1 : 0);
    if (dir == 0) return;
    final now = DateTime.now();
    if (now.difference(_lastStep) < _stepEvery) return;
    _lastStep = now;
    ref.read(apptsControllerProvider.notifier).shiftDays(dir);
    ApptSlide.fire(dir);
    // The columns have moved: work out what is under the block again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _update();
    });
  }

  /// Scrolls the enclosing list while the dragged block is near its edge.
  void _tick() {
    final data = _data;
    final global = _global;
    if (!mounted || data == null || global == null) return;
    if (widget.stepDaysAtEdge) _stepAtEdge(global, data);
    final scrollable = Scrollable.maybeOf(context);
    final viewport = scrollable?.context.findRenderObject() as RenderBox?;
    if (scrollable == null || viewport == null || !viewport.hasSize) return;
    final top = viewport.localToGlobal(Offset.zero).dy;
    final bottom = top + viewport.size.height;
    var step = 0.0;
    if (global.dy < top + _edge) {
      step = -((top + _edge - global.dy) / _edge).clamp(0.0, 1.0) * _maxStep;
    } else if (global.dy + data.size.height > bottom - _edge) {
      step =
          ((global.dy + data.size.height - (bottom - _edge)) / _edge).clamp(
            0.0,
            1.0,
          ) *
          _maxStep;
    }
    if (step == 0) return;
    final position = scrollable.position;
    final to = (position.pixels + step).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (to == position.pixels) return;
    position.jumpTo(to.toDouble());
    _update();
  }

  void _clear() {
    _timer?.cancel();
    _timer = null;
    _data = null;
    _global = null;
    ApptDragHint.time.value = null;
    if (mounted && _hover != null) setState(() => _hover = null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    ApptDragHint.time.value = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final hover = _hover;
    return DragTarget<ApptDragData>(
      onWillAcceptWithDetails: (_) => true,
      onMove: _onMove,
      onLeave: (_) => _clear(),
      onAcceptWithDetails: (d) {
        final drop = _resolve(d.offset, d.data);
        _clear();
        if (drop == null) return;
        ApptActions.moveTo(context, ref, d.data.item, drop.start);
      },
      builder: (context, _, _) => Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (hover != null)
            Positioned.fromRect(
              rect: hover.rect,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: c.accentWash,
                    shape: cruShape(
                      widget.ghostRadius,
                      side: BorderSide(color: c.accent, width: 2),
                    ),
                  ),
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CruSpace.s8,
                        ),
                        child: Text(
                          ApptFormat.time(hover.start),
                          maxLines: 1,
                          softWrap: false,
                          style: CruType.micro.w600.tabular.tint(c.accentText),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
