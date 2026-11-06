import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/files/domain/files_models.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// What a file dragged on a touch screen looks like, Instagram's
/// hold-to-share style: the file floats above the finger (so the finger
/// never hides it), the screen dims lightly while it moves (folders stay
/// readable) and fully once it is on the clinic logo, the logo stays lit
/// through a hole in the dim, and on release the file flies into the
/// colleague it was dropped on or glides back to its row.
///
/// The Files rows drive it ([pressAt], [start], [end]; the finger is
/// followed on its own, even if the row rebuilds mid-drag); the clinic
/// logo registers itself as the [spotlight] and the colleague row calls
/// [setFocus] and [landOn].
abstract final class ShareDragStage {
  /// Gap between the fingertip and the floating file's centre.
  static const double _aboveFinger = 52;

  static OverlayState? _overlay;
  static OverlayEntry? _scrim;
  static OverlayEntry? _ghost;
  static final _model = _StageModel();

  /// True from the moment a file lifts until it is released.
  static final ValueNotifier<bool> active = ValueNotifier(false);

  /// The lit element (the phone's clinic logo), or null when it isn't on
  /// screen: then nothing dims.
  static State? spotlight;

  /// The overlay the stage draws in, so a colleague row opened during the
  /// drag can sit under the floating file ([ghostEntry]).
  static OverlayState? get overlay => _overlay;
  static OverlayEntry? get ghostEntry => _ghost;

  /// Whether the last release landed on a colleague.
  static bool get landed => _model.landing != null;

  static Offset? _pressedAt;

  /// Where the finger went down; the file floats there as soon as it lifts
  /// (before the first move).
  static void pressAt(Offset global) => _pressedAt = global;

  static void start(BuildContext context, FileEntry entry) {
    _finish();
    final box = context.findRenderObject();
    final source = box is RenderBox && box.attached && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    _overlay = Overlay.of(context);
    _model
      ..entry = entry
      ..pointer = _pressedAt ?? source?.center
      ..source = source
      ..focus.clear()
      ..landing = null
      ..phase = _Phase.dragging
      ..changed();
    _scrim = OverlayEntry(builder: (_) => _ScrimLayer(model: _model));
    _ghost = OverlayEntry(builder: (_) => _GhostLayer(model: _model));
    _overlay!
      ..insert(_scrim!)
      ..insert(_ghost!);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_follow);
    _following = true;
    active.value = true;
  }

  static void _follow(PointerEvent e) {
    if (e is! PointerMoveEvent || _model.phase != _Phase.dragging) return;
    _model
      ..pointer = e.position
      ..changed();
  }

  /// [owner] (the logo or the colleague row) has the file over it, or not:
  /// the dim deepens and the file shrinks to an icon while any does.
  static void setFocus(Object owner, bool on) {
    if (_model.phase != _Phase.dragging) return;
    final changed = on ? _model.focus.add(owner) : _model.focus.remove(owner);
    if (changed) _model.changed();
  }

  /// The release is on a colleague whose avatar centre is [target]: the
  /// file flies into it. Called before [end].
  static void landOn(Offset target) => _model.landing = target;

  /// The finger lifted. [accepted]: something took the file (a colleague
  /// or a folder); otherwise it glides back to its row.
  static void end({required bool accepted}) {
    if (_model.phase != _Phase.dragging) return;
    _model
      ..phase = _model.landing != null
          ? _Phase.landing
          : accepted
          ? _Phase.dropped
          : _Phase.returning
      ..focus.clear()
      ..changed();
    _stopFollowing();
    active.value = false;
  }

  static bool _following = false;

  static void _stopFollowing() {
    if (!_following) return;
    _following = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_follow);
  }

  static void _finish() {
    _stopFollowing();
    _scrim?.remove();
    _ghost?.remove();
    _scrim = null;
    _ghost = null;
    _overlay = null;
    if (_model.phase != _Phase.idle) {
      _model
        ..phase = _Phase.idle
        ..changed();
    }
    if (active.value) active.value = false;
  }

  /// The spotlight's rectangle on screen, or null.
  static Rect? _spotRect() {
    final s = spotlight;
    if (s == null || !s.mounted) return null;
    final box = s.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}

/// The overlay's top-left on screen and its width: the stage works in
/// screen coordinates, the overlay may not start at the screen's corner.
(Offset, double) _overlayFrame(BuildContext context) {
  final box = Overlay.maybeOf(context)?.context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) {
    return (Offset.zero, MediaQuery.sizeOf(context).width);
  }
  return (box.localToGlobal(Offset.zero), box.size.width);
}

enum _Phase { idle, dragging, landing, dropped, returning }

class _StageModel extends ChangeNotifier {
  FileEntry? entry;
  Offset? pointer;
  Rect? source;
  Offset? landing;
  final Set<Object> focus = {};
  _Phase phase = _Phase.idle;

  bool get focused => focus.isNotEmpty;

  void changed() => notifyListeners();
}

/// The dim with a hole around the clinic logo, and a hint beside the logo
/// until the file reaches it.
class _ScrimLayer extends StatelessWidget {
  const _ScrimLayer({required this.model});

  final _StageModel model;

  /// How much of the full scrim shows while the file is still on its way.
  static const _light = 0.3;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final motion = CruMotion.of(context, CruMotion.fast);
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: model,
        builder: (context, _) {
          final (origin, width) = _overlayFrame(context);
          final spot = ShareDragStage._spotRect()?.shift(-origin);
          if (spot == null) return const SizedBox.shrink();
          final dragging = model.phase == _Phase.dragging;
          final strength = !dragging
              ? 0.0
              : model.focused
              ? 1.0
              : _light;
          final hole = RRect.fromRectAndRadius(
            spot.inflate(CruSpace.s6),
            const Radius.circular(CruRadius.control + CruSpace.s6),
          );
          return Stack(
            children: [
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: strength),
                  duration: motion,
                  curve: CruMotion.curve,
                  builder: (_, s, _) => CustomPaint(
                    painter: _ScrimPainter(
                      color: c.scrim.withValues(alpha: c.scrim.a * s),
                      hole: hole,
                    ),
                  ),
                ),
              ),
              // "Send to a colleague", left of the logo, until the file
              // gets there: says what the lit logo is for.
              Positioned(
                right: width - hole.left + CruSpace.s8,
                top: hole.center.dy - CruSpace.s16,
                height: CruSpace.s32,
                child: AnimatedOpacity(
                  opacity: dragging && !model.focused ? 1 : 0,
                  duration: motion,
                  curve: CruMotion.curve,
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: CruSpace.s12,
                    ),
                    decoration: ShapeDecoration(
                      color: c.surface,
                      shape: const StadiumBorder(),
                      shadows: c.paneShadow,
                    ),
                    child: Text(
                      'Send to a colleague',
                      style: CruType.callout.w500.tint(c.label),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  _ScrimPainter({required this.color, required this.hole});

  final Color color;
  final RRect hole;

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0) return;
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(hole),
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.color != color || old.hole != hole;
}

/// The floating file: a chip with its name while it travels, an icon tile
/// once it is over the colleagues (so they stay visible), then flying into
/// the chosen avatar, fading where it was taken, or gliding back.
class _GhostLayer extends StatefulWidget {
  const _GhostLayer({required this.model});

  final _StageModel model;

  @override
  State<_GhostLayer> createState() => _GhostLayerState();
}

class _GhostLayerState extends State<_GhostLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _out = AnimationController(vsync: this);
  Offset? _from;

  _StageModel get m => widget.model;

  @override
  void initState() {
    super.initState();
    m.addListener(_changed);
    _out.addStatusListener((s) {
      if (s == AnimationStatus.completed) ShareDragStage._finish();
    });
  }

  void _changed() {
    if (!mounted) return;
    if (m.phase != _Phase.dragging &&
        m.phase != _Phase.idle &&
        !_out.isAnimating &&
        _out.value == 0) {
      _from = _centre(m.pointer);
      _out.duration = CruMotion.of(context);
      if (_out.duration == Duration.zero) {
        // Reduced motion: no flight, just gone.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => ShareDragStage._finish(),
        );
      } else {
        _out.forward(from: 0);
      }
    }
    setState(() {});
  }

  Offset? _centre(Offset? pointer) =>
      pointer?.translate(0, -ShareDragStage._aboveFinger);

  @override
  void dispose() {
    m.removeListener(_changed);
    _out.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = m.entry;
    final dragCentre = _centre(m.pointer);
    if (entry == null || dragCentre == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _out,
        builder: (context, _) {
          final t = CruMotion.curve.transform(_out.value);
          var centre = dragCentre;
          var scale = 1.0;
          var opacity = 1.0;
          final from = _from ?? dragCentre;
          switch (m.phase) {
            case _Phase.landing:
              centre = Offset.lerp(from, m.landing!, t)!;
              scale = 1 - 0.7 * t;
              opacity = 1 - 0.6 * t;
            case _Phase.returning:
              centre = Offset.lerp(from, m.source?.center ?? from, t)!;
              scale = 1 - 0.1 * t;
              opacity = 1 - t;
            case _Phase.dropped:
              centre = from;
              scale = 1 - 0.2 * t;
              opacity = 1 - t;
            case _Phase.dragging:
            case _Phase.idle:
              break;
          }
          final compact = m.focused || m.phase == _Phase.landing;
          final at = centre - _overlayFrame(context).$1;
          return Stack(
            children: [
              Positioned(
                left: at.dx,
                top: at.dy,
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: Opacity(
                    opacity: opacity.clamp(0, 1).toDouble(),
                    child: Transform.scale(
                      scale: scale,
                      child: _GhostChip(entry: entry, compact: compact),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GhostChip extends StatelessWidget {
  const _GhostChip({required this.entry, required this.compact});

  final FileEntry entry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final motion = CruMotion.of(context, CruMotion.fast);
    return Material(
      type: MaterialType.transparency,
      child: AnimatedContainer(
        duration: motion,
        curve: CruMotion.curve,
        height: CruSize.searchBar,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
        decoration: ShapeDecoration(
          color: c.surface,
          shape: cruShape(
            compact ? CruRadius.iconTile : CruRadius.control,
            side: BorderSide(color: c.cardBorder),
          ),
          shadows: c.paneShadow,
        ),
        child: AnimatedSize(
          duration: motion,
          curve: CruMotion.curve,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CruIcon(
                fileKindIcon(entry.file.kind),
                size: 18,
                strokeWidth: 1.9,
                color: c.label2,
              ),
              if (!compact) ...[
                const SizedBox(width: CruSpace.s8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    entry.file.name,
                    style: CruType.text.w500.tint(c.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
