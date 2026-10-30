import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

// The "same box" transition (design/motion-transitions.md): the tapped
// element grows into the next view, elements both views show travel from
// one place to the other ([MorphTag]), and everything else fades.

/// Which end of a same-box transition a subtree is.
enum MorphSide { source, destination }

/// The tagged elements on screen, by side, group and id.
class MorphRegistry {
  final Map<String, _MorphTagState> _source = {};
  final Map<String, _MorphTagState> _destination = {};

  Map<String, _MorphTagState> _of(MorphSide side) =>
      side == MorphSide.source ? _source : _destination;
}

/// Puts the [MorphTag]s below it on one side of a transition. [group]
/// keeps one card's tags apart from another's; with no [registry] the tags
/// only hide (a copy drawn inside the box). Tags whose id is in [hidden]
/// are laid out but not drawn: a flying copy stands in for them.
class MorphScope extends InheritedWidget {
  const MorphScope({
    super.key,
    required this.side,
    required this.group,
    required this.registry,
    this.hidden = const {},
    required super.child,
  });

  final MorphSide side;
  final String group;
  final MorphRegistry? registry;
  final Set<String> hidden;

  static MorphScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MorphScope>();

  @override
  bool updateShouldNotify(MorphScope oldWidget) =>
      side != oldWidget.side ||
      group != oldWidget.group ||
      registry != oldWidget.registry ||
      !setEquals(hidden, oldWidget.hidden);
}

/// An element that both ends of a transition show (a visit, a file row,
/// a title). It moves from where the source has it to where the
/// destination has it instead of fading; back is the same trip reversed.
/// [MorphTag.text] also turns one text style into the other.
class MorphTag extends StatefulWidget {
  const MorphTag({super.key, required this.id, required this.child})
    : text = null,
      style = null;

  MorphTag.text({
    super.key,
    required this.id,
    required String this.text,
    required TextStyle this.style,
  }) : child = Text(
         text,
         style: style,
         maxLines: 1,
         overflow: TextOverflow.ellipsis,
       );

  final String id;
  final Widget child;
  final String? text;
  final TextStyle? style;

  @override
  State<MorphTag> createState() => _MorphTagState();
}

class _MorphTagState extends State<MorphTag> {
  MorphRegistry? _registry;
  MorphSide? _side;
  String? _key;

  void _unregister() {
    final map = _side == null ? null : _registry?._of(_side!);
    if (map != null && map[_key] == this) map.remove(_key);
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = MorphScope.maybeOf(context);
    final key = scope == null ? null : '${scope.group}|${widget.id}';
    if (scope?.registry != _registry ||
        scope?.side != _side ||
        key != _key) {
      _unregister();
    }
    _registry = scope?.registry;
    _side = scope?.side;
    _key = key;
    if (scope != null && key != null) {
      scope.registry?._of(scope.side)[key] = this;
    }
    final hidden = scope?.hidden.contains(widget.id) ?? false;
    return Opacity(opacity: hidden ? 0 : 1, child: widget.child);
  }
}

/// A tagged element as measured: where it is and how it looks.
typedef MorphEnd = ({Rect rect, MorphTag tag});

/// [group]'s tags on [side], by id, measured inside [root] (unscaled:
/// transforms above [root] don't count) and shifted by [origin].
Map<String, MorphEnd> captureMorphTags({
  required MorphRegistry registry,
  required MorphSide side,
  required String group,
  required RenderBox root,
  Offset origin = Offset.zero,
}) {
  final prefix = '$group|';
  final out = <String, MorphEnd>{};
  for (final MapEntry(:key, value: tag) in registry._of(side).entries) {
    if (!key.startsWith(prefix) || !tag.mounted) continue;
    final box = tag.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) continue;
    try {
      final at = box.localToGlobal(Offset.zero, ancestor: root) + origin;
      out[tag.widget.id] = (rect: at & box.size, tag: tag.widget);
    } catch (_) {
      // Not inside [root].
    }
  }
  return out;
}

/// Elements both ends show, in [area]'s coordinates. Those off screen at
/// either end are left to fade.
List<MorphFlight> pairMorphFlights(
  Map<String, MorphEnd> sources,
  Map<String, MorphEnd> destinations,
  Rect area,
) => [
  for (final MapEntry(:key, value: dst) in destinations.entries)
    if (sources[key] case final src?)
      if (src.rect.overlaps(area) && dst.rect.overlaps(area))
        MorphFlight(
          id: key,
          from: src.rect,
          to: dst.rect,
          source: src.tag,
          destination: dst.tag,
        ),
];

/// One shared element's trip.
class MorphFlight {
  const MorphFlight({
    required this.id,
    required this.from,
    required this.to,
    required this.source,
    required this.destination,
  });

  final String id;
  final Rect from;
  final Rect to;
  final MorphTag source;
  final MorphTag destination;
}

/// Pairs [group]'s source tags with the destination's when both are on
/// screen at once: sources inside [sourceRoot] (at [sourceOrigin] in
/// [area]), destinations inside [destinationRoot] as it lies at rest.
List<MorphFlight> measureMorphFlights({
  required MorphRegistry registry,
  required String group,
  required RenderBox sourceRoot,
  required Offset sourceOrigin,
  required RenderBox destinationRoot,
  required Rect area,
}) => pairMorphFlights(
  captureMorphTags(
    registry: registry,
    side: MorphSide.source,
    group: group,
    root: sourceRoot,
    origin: sourceOrigin,
  ),
  captureMorphTags(
    registry: registry,
    side: MorphSide.destination,
    group: group,
    root: destinationRoot,
  ),
  area,
);

/// The flying copies at [t], each in the rectangle between its two ends.
/// Each end's look is laid out at its own height and the moving width, so
/// rows reflow rather than stretch. Texts turn one style into the other;
/// elements that look alike at both ends are drawn once, others
/// cross-fade over the middle of the motion.
class MorphFlights extends StatelessWidget {
  const MorphFlights({super.key, required this.t, required this.flights});

  final double t;
  final List<MorphFlight> flights;

  @override
  Widget build(BuildContext context) {
    final look = const Interval(0.15, 0.85).transform(t);
    Widget at(double height, Widget child) => OverflowBox(
      alignment: Alignment.topLeft,
      minHeight: height,
      maxHeight: height,
      child: child,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final f in flights)
          Builder(
            builder: (context) {
              final r = Rect.lerp(f.from, f.to, t)!;
              final src = f.source;
              final dst = f.destination;
              if (src.text != null && dst.text != null) {
                return Positioned(
                  left: r.left,
                  top: r.top,
                  child: Text(
                    dst.text!,
                    style: TextStyle.lerp(src.style, dst.style, t),
                    maxLines: 1,
                    softWrap: false,
                  ),
                );
              }
              final Widget body;
              if (src.child.runtimeType == dst.child.runtimeType) {
                body = at(f.to.height, dst.child);
              } else {
                body = Stack(
                  children: [
                    Opacity(
                      opacity: 1 - look,
                      child: at(f.from.height, src.child),
                    ),
                    Opacity(opacity: look, child: at(f.to.height, dst.child)),
                  ],
                );
              }
              return Positioned.fromRect(
                rect: r,
                child: ClipRect(child: body),
              );
            },
          ),
      ],
    );
  }
}

/// The growing box: from the tapped element's rectangle ([from], corners
/// [fromRadius]) to the whole [area]. Its colour turns from the card's to
/// the page's and then gives way to whatever is behind; the element's
/// look ([source]) fades out early, and the next view ([child], laid out
/// at its full size and scaled with the box) fades in once the box is
/// mostly open. At t = 1 every wrapper is a no-op: the box is the view.
class MorphBox extends StatelessWidget {
  const MorphBox({
    super.key,
    required this.t,
    required this.from,
    required this.area,
    required this.settled,
    required this.source,
    required this.child,
    this.fromRadius = CruRadius.card,
  });

  final double t;
  final Rect? from;
  final Rect area;
  final double fromRadius;

  /// Fully open: the view takes taps.
  final bool settled;
  final Widget source;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    // Nothing to grow from (not laid out): open from the middle.
    final start =
        from ??
        Rect.fromCenter(
          center: area.center,
          width: area.width / 2,
          height: area.height / 3,
        );
    final rect = Rect.lerp(start, area, t)!;
    final shape = cruShape(fromRadius * (1 - t));
    final fill = Color.lerp(
      c.surface,
      c.canvas,
      const Interval(0.3, 0.7).transform(t),
    )!;
    final fillAlpha = 1 - const Interval(0.85, 1).transform(t);
    final sourceOpacity = 1 - const Interval(0.15, 0.5).transform(t);
    final viewOpacity = const Interval(0.5, 0.85).transform(t);
    return Positioned.fromRect(
      rect: rect,
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: fill.withValues(alpha: fill.a * fillAlpha),
            shape: shape,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                ignoring: !settled,
                child: Opacity(
                  opacity: viewOpacity,
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: area.width,
                    maxWidth: area.width,
                    minHeight: area.height,
                    maxHeight: area.height,
                    child: Transform.scale(
                      scale: rect.width / area.width,
                      alignment: Alignment.topLeft,
                      child: child,
                    ),
                  ),
                ),
              ),
              if (sourceOpacity > 0)
                IgnorePointer(
                  child: Opacity(
                    opacity: sourceOpacity,
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: start.width,
                      maxWidth: start.width,
                      minHeight: start.height,
                      maxHeight: start.height,
                      child: Transform.scale(
                        scale: rect.width / start.width,
                        alignment: Alignment.topLeft,
                        child: source,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
