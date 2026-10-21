import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Every real element the first-run tour can point at.
enum TutorialTarget {
  // Desktop.
  sidebar,
  search,
  addPatient,
  newAppointment,
  upNext,
  sidebarSchedule,
  sidebarScribe,
  account,

  /// Schedule's Live · Day · Week · Month switcher.
  scheduleViews,

  /// The Scribe screen's recording panel ("Choose a visit").
  scribePanel,

  /// The Settings screen's section list.
  settingsSections,

  /// The voice pill at the top of the desktop window.
  voicePill,

  // Phone.

  /// The floating mic.
  voiceBubble,
  mobileUpNext,
  navHome,
  navSchedule,
  navPatients,
  navTasks,
  navMore,
  mobileAddPatient,
  island,
}

/// The cut-out's shape around a target.
enum TutorialShape {
  /// A rounded rect: the target's own radius plus the 8 px padding.
  rounded,

  /// A circle (nav icons, round buttons, avatars).
  circle,

  /// Fully round ends (the phone's black pill).
  stadium,
}

/// Marks a real widget as a tour target. It adds no layout of its own: the
/// child is laid out and painted exactly as before.
class TutorialAnchor extends ConsumerStatefulWidget {
  const TutorialAnchor({
    super.key,
    required this.target,
    required this.child,
    this.radius = CruRadius.control,
    this.shape = TutorialShape.rounded,
  });

  final TutorialTarget target;
  final Widget child;

  /// The target's own corner radius (the cut-out adds the padding to it).
  final double radius;
  final TutorialShape shape;

  /// Wraps [child] only when there is a [target].
  static Widget maybe({
    required TutorialTarget? target,
    required Widget child,
    double radius = CruRadius.control,
    TutorialShape shape = TutorialShape.rounded,
  }) => target == null
      ? child
      : TutorialAnchor(
          target: target,
          radius: radius,
          shape: shape,
          child: child,
        );

  @override
  ConsumerState<TutorialAnchor> createState() => _TutorialAnchorState();
}

class _TutorialAnchorState extends ConsumerState<TutorialAnchor> {
  final GlobalKey _key = GlobalKey(debugLabel: 'tutorial anchor');
  late final TutorialAnchors _anchors;
  late TutorialAnchorEntry _entry;

  @override
  void initState() {
    super.initState();
    _anchors = ref.read(tutorialAnchorsProvider);
    _entry = TutorialAnchorEntry(_key, widget.radius, widget.shape);
    _anchors._add(widget.target, _entry);
  }

  @override
  void didUpdateWidget(TutorialAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target ||
        oldWidget.radius != widget.radius ||
        oldWidget.shape != widget.shape) {
      _anchors._remove(oldWidget.target, _entry);
      _entry = TutorialAnchorEntry(_key, widget.radius, widget.shape);
      _anchors._add(widget.target, _entry);
    }
  }

  @override
  void dispose() {
    _anchors._remove(widget.target, _entry);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}

/// One mounted [TutorialAnchor].
class TutorialAnchorEntry {
  TutorialAnchorEntry(this.key, this.radius, this.shape);

  final GlobalKey key;
  final double radius;
  final TutorialShape shape;

  /// The laid-out box, or null while it isn't on the tree.
  RenderBox? get box {
    final object = key.currentContext?.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return null;
    }
    return object.size.isEmpty ? null : object;
  }
}

/// Where a target is, in the overlay's coordinates.
typedef TutorialLocation = ({Rect rect, double radius, TutorialShape shape});

/// Every mounted anchor, by target. Anchors add and remove themselves; the
/// tour reads their boxes. It never notifies: the overlay measures after
/// every frame instead, so anchors can come and go during a build.
class TutorialAnchors {
  final Map<TutorialTarget, List<TutorialAnchorEntry>> _byTarget = {};

  void _add(TutorialTarget target, TutorialAnchorEntry entry) =>
      (_byTarget[target] ??= []).add(entry);

  void _remove(TutorialTarget target, TutorialAnchorEntry entry) =>
      _byTarget[target]?.remove(entry);

  /// The newest anchor for [target] that is laid out.
  TutorialAnchorEntry? entryFor(TutorialTarget target) {
    final entries = _byTarget[target];
    if (entries == null) return null;
    for (final entry in entries.reversed) {
      if (entry.box != null) return entry;
    }
    return null;
  }

  /// Whether [target] is on the tree and laid out.
  bool isPresent(TutorialTarget target) => entryFor(target) != null;

  /// [target]'s bounds in [ancestor]'s coordinates (any box in the same
  /// render tree), or null when it isn't laid out or is off screen.
  TutorialLocation? locate(TutorialTarget target, RenderBox ancestor) {
    final entry = entryFor(target);
    final box = entry?.box;
    if (entry == null || box == null || !ancestor.attached) return null;
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(ancestor),
      Offset.zero & box.size,
    );
    if (!rect.isFinite || !(Offset.zero & ancestor.size).overlaps(rect)) {
      return null;
    }
    return (rect: rect, radius: entry.radius, shape: entry.shape);
  }

  /// Scrolls the nearest vertical list holding [target] until it is fully
  /// in view. Sideways pagers (the phone's tabs) are left alone: the tour
  /// switches tabs itself.
  Future<void> ensureVisible(TutorialTarget target) async {
    final entry = entryFor(target);
    final context = entry?.key.currentContext;
    final box = entry?.box;
    if (context == null || box == null) return;
    final scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
    if (scrollable == null) return;
    final viewport = scrollable.context.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return;
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(viewport),
      Offset.zero & box.size,
    );
    // Room for the 8 px padding and the ring around the cut-out.
    final visible = (Offset.zero & viewport.size).deflate(CruSpace.s12);
    if (rect.top >= visible.top && rect.bottom <= visible.bottom) return;
    final duration = CruMotion.of(context);
    await scrollable.position.ensureVisible(
      box,
      // A little above centre, leaving room for the card below.
      alignment: 0.3,
      duration: duration,
      curve: CruMotion.curve,
    );
  }
}

final tutorialAnchorsProvider = Provider<TutorialAnchors>(
  (ref) => TutorialAnchors(),
);
