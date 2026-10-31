import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/shared/widgets/morph_tag.dart';

// A day opened from Month (a tile, or the day panel) or Agenda (a row) as
// the same box (design/motion-transitions.md): the tapped element grows
// into Day's area, visits both views show travel to their Day blocks, the
// rest fades. Picking that view again in the header folds the day back
// into where it came from. Week ⇄ Day has its own fold and is untouched.

/// The tag group Schedule's views share; visits are tagged `visit:<id>`.
const String kScheduleMorphGroup = 'schedule';

enum ScheduleTripPhase { opening, open, folding }

/// A day opened from Month or Agenda: what to grow from, and fold back to.
class ScheduleTrip {
  ScheduleTrip({
    required this.from,
    required this.date,
    required this.source,
    required this.radius,
    required this.copy,
    required this.backdrop,
    required this.sources,
  });

  final ApptsView from;
  final DateTime date;

  /// The tapped element in the calendar area, and its corners.
  final Rect source;
  final double radius;

  /// Its look, drawn in the box.
  final Widget copy;

  /// The page it came from as a picture, fading behind the box.
  final ui.Image? backdrop;

  /// The visits the source page showed, in the calendar area.
  final Map<String, MorphEnd> sources;

  ScheduleTripPhase phase = ScheduleTripPhase.opening;
  VoidCallback? _apply;
}

/// The trip under way (if any) and what both ends need to find each other.
class ScheduleMorph extends ChangeNotifier {
  final MorphRegistry registry = MorphRegistry();

  /// Each page's calendar area. Day shares Week's page, so its key.
  final Map<ApptsView, GlobalKey> _areas = {
    for (final v in ApptsView.values) v: GlobalKey(debugLabel: '${v.name} area'),
  };

  GlobalKey areaFor(ApptsView view) =>
      _areas[view == ApptsView.day ? ApptsView.week : view]!;

  ScheduleTrip? trip;
  bool _swapOnce = false;

  /// The pages swap in place (no sideways slide) for the next change.
  bool takeSwap() {
    final swap =
        _swapOnce ||
        (trip != null && trip!.phase == ScheduleTripPhase.opening);
    _swapOnce = false;
    return swap;
  }

  /// Opens [date]'s Day from [source] (a tile, the panel or a row) on
  /// [from]. [copy] is how [source] looks, [radius] its corners.
  Future<void> openDay(
    BuildContext source, {
    required ApptsView from,
    required DateTime date,
    String? visitId,
    required Widget copy,
    required double radius,
    required ApptsController controller,
  }) async {
    final instant =
        CruMotion.of(source) == Duration.zero ||
        (trip != null && trip!.phase != ScheduleTripPhase.open);
    final box = source.findRenderObject();
    final area = areaFor(from).currentContext?.findRenderObject();
    if (instant ||
        box is! RenderBox ||
        area is! RenderRepaintBoundary ||
        !box.attached) {
      controller.openDay(date, visitId: visitId);
      return;
    }
    final rect = box.localToGlobal(Offset.zero, ancestor: area) & box.size;
    final sources = captureMorphTags(
      registry: registry,
      side: MorphSide.source,
      group: kScheduleMorphGroup,
      root: area,
    );
    final ratio = MediaQuery.devicePixelRatioOf(source);
    ui.Image? picture;
    try {
      picture = await area.toImage(pixelRatio: ratio);
    } catch (_) {
      // No picture: the old page just isn't drawn behind the box.
    }
    _drop();
    trip = ScheduleTrip(
      from: from,
      date: date,
      source: rect,
      radius: radius,
      copy: copy,
      backdrop: picture,
      sources: sources,
    );
    notifyListeners();
    controller.openDay(date, visitId: visitId);
  }

  /// The header switched Day to [to]: fold back when the day was opened
  /// from [to] and is still that day ([anchor]); [apply] then switches at
  /// the end. False: nothing to fold into, switch now.
  bool foldBack(ApptsView to, DateTime anchor, bool fold, VoidCallback apply) {
    final t = trip;
    if (!fold ||
        t == null ||
        t.phase != ScheduleTripPhase.open ||
        t.from != to ||
        t.date != anchor) {
      if (t != null && t.phase == ScheduleTripPhase.open) {
        _drop();
        notifyListeners();
      }
      return false;
    }
    t.phase = ScheduleTripPhase.folding;
    t._apply = apply;
    notifyListeners();
    return true;
  }

  void _opened(ScheduleTrip t) {
    if (trip != t) return;
    t.phase = ScheduleTripPhase.open;
    notifyListeners();
  }

  void _folded(ScheduleTrip t) {
    if (trip != t) return;
    _swapOnce = true;
    final apply = t._apply;
    _drop();
    apply?.call();
    notifyListeners();
  }

  void _drop() {
    trip?.backdrop?.dispose();
    trip = null;
  }

  @override
  void dispose() {
    _drop();
    super.dispose();
  }
}

final scheduleMorphProvider = Provider<ScheduleMorph>((ref) {
  final morph = ScheduleMorph();
  ref.onDispose(morph.dispose);
  return morph;
});

/// A calendar view's area. Month and Agenda tag their visits as the
/// source; Day as the destination, and during a trip the box grows from
/// the tapped element into it (or folds back), the old page fades behind
/// it as a picture, and shared visits fly. At rest Day is just itself.
class ScheduleMorphArea extends ConsumerStatefulWidget {
  const ScheduleMorphArea({super.key, required this.view, required this.child});

  final ApptsView view;
  final Widget child;

  @override
  ConsumerState<ScheduleMorphArea> createState() => _ScheduleMorphAreaState();
}

class _ScheduleMorphAreaState extends ConsumerState<ScheduleMorphArea>
    with SingleTickerProviderStateMixin {
  late final ScheduleMorph _morph = ref.read(scheduleMorphProvider);
  late final AnimationController _c = AnimationController(
    vsync: this,
    value: 1,
  );
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _c,
    curve: CruMotion.curve,
    reverseCurve: CruMotion.curve.flipped,
  );

  ScheduleTrip? _playing;
  ScheduleTripPhase? _phase;
  List<MorphFlight> _flights = const [];

  bool get _day => widget.view == ApptsView.day;

  @override
  void initState() {
    super.initState();
    _morph.addListener(_onTrip);
    _c.addStatusListener((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(ScheduleMorphArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    }
  }

  @override
  void dispose() {
    _morph.removeListener(_onTrip);
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  void _onTrip() {
    if (!mounted) return;
    setState(() {});
    // Day is laid out by the next frame; start from there.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    if (!mounted || !_day) return;
    final trip = _morph.trip;
    if (trip == null) {
      if (_playing != null) {
        setState(() {
          _playing = null;
          _flights = const [];
        });
      }
      return;
    }
    if (trip == _playing && trip.phase == _phase) return;
    _playing = trip;
    _phase = trip.phase;
    switch (trip.phase) {
      case ScheduleTripPhase.opening:
        _c.value = 0;
        _measure(trip);
        _c.duration = CruMotion.of(context);
        _c.forward(from: 0).whenComplete(() => _morph._opened(trip));
      case ScheduleTripPhase.folding:
        // Day may have scrolled: measure its blocks again.
        _measure(trip);
        _c.duration = CruMotion.of(context);
        _c.reverse(from: 1).whenComplete(() => _morph._folded(trip));
      case ScheduleTripPhase.open:
        break;
    }
  }

  void _measure(ScheduleTrip trip) {
    final me = context.findRenderObject();
    final area = _morph.areaFor(ApptsView.day).currentContext
        ?.findRenderObject();
    if (me is! RenderBox || area is! RenderBox) return;
    final dests = captureMorphTags(
      registry: _morph.registry,
      side: MorphSide.destination,
      group: kScheduleMorphGroup,
      root: area,
    );
    setState(
      () => _flights = pairMorphFlights(
        trip.sources,
        dests,
        Offset.zero & me.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_day) {
      return MorphScope(
        side: MorphSide.source,
        group: kScheduleMorphGroup,
        registry: _morph.registry,
        child: widget.child,
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final area = Offset.zero & box.biggest;
        return AnimatedBuilder(
          animation: _t,
          child: widget.child,
          builder: (context, child) {
            final trip = _morph.trip;
            // Before the first frame of an opening trip: still the source.
            final t = trip == null
                ? 1.0
                : trip.phase == ScheduleTripPhase.opening && _playing != trip
                ? 0.0
                : trip.phase == ScheduleTripPhase.open && !_c.isAnimating
                ? 1.0
                : _t.value;
            final moving = t < 1;
            final flying = moving
                ? {for (final f in _flights) f.id}
                : const <String>{};
            final picture = moving ? trip?.backdrop : null;
            return Stack(
              fit: StackFit.expand,
              children: [
                if (picture != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 1 - const Interval(0, 0.5).transform(t),
                        child: RawImage(image: picture, fit: BoxFit.fill),
                      ),
                    ),
                  ),
                MorphBox(
                  key: const ValueKey('day'),
                  t: t,
                  from: trip?.source,
                  area: area,
                  fromRadius: trip?.radius ?? 0,
                  settled: !moving,
                  source: MorphScope(
                    side: MorphSide.source,
                    group: 'copy',
                    registry: null,
                    hidden: flying,
                    child: trip?.copy ?? const SizedBox.shrink(),
                  ),
                  child: MorphScope(
                    side: MorphSide.destination,
                    group: kScheduleMorphGroup,
                    registry: _morph.registry,
                    hidden: flying,
                    child: child!,
                  ),
                ),
                if (moving && _flights.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: MorphFlights(t: t, flights: _flights),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
