import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/jaw_model.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum _Jaws { both, upper, lower }

/// Camera and pose of the 3D jaws.
@immutable
class _Pose {
  const _Pose(this.yaw, this.pitch, this.dist, this.open);

  static const front = _Pose(0, 0.14, 150, 0);

  final double yaw;
  final double pitch;
  final double dist;

  /// 0 closed, 1 fully open.
  final double open;

  _Pose copyWith({double? yaw, double? pitch, double? dist, double? open}) =>
      _Pose(
        yaw ?? this.yaw,
        pitch ?? this.pitch,
        dist ?? this.dist,
        open ?? this.open,
      );

  static _Pose lerp(_Pose a, _Pose b, double t) {
    var dy = (b.yaw - a.yaw) % (2 * math.pi);
    if (dy > math.pi) dy -= 2 * math.pi;
    if (dy < -math.pi) dy += 2 * math.pi;
    return _Pose(
      a.yaw + dy * t,
      a.pitch + (b.pitch - a.pitch) * t,
      a.dist + (b.dist - a.dist) * t,
      a.open + (b.open - a.open) * t,
    );
  }
}

/// Both jaws in 3D: white teeth in see-through jaw bone, the roots
/// showing faintly through it. Drag to turn, scroll or pinch to zoom,
/// click a tooth to select it, double-click to bring it to the front.
/// Open the mouth, show the roots plainly, or jump to a preset view.
/// Callouts name the teeth with findings (or planned work).
class ToothChart3D extends StatefulWidget {
  const ToothChart3D({
    super.key,
    required this.data,
    required this.child,
    required this.mode,
    required this.selected,
    required this.onSelect,
    this.onOpen,
    this.height = 460,
    this.numbering = ToothNumbering.fdi,
  });

  final ToothChartData data;
  final bool child;
  final ChartMode mode;
  final String? selected;
  final ValueChanged<String> onSelect;

  /// Enter on the selected tooth.
  final ValueChanged<String>? onOpen;
  final double height;

  /// How tooth numbers are shown; storage stays FDI regardless.
  final ToothNumbering numbering;

  @override
  State<ToothChart3D> createState() => _ToothChart3DState();
}

class _ToothChart3DState extends State<ToothChart3D>
    with SingleTickerProviderStateMixin {
  final FocusNode _focus = FocusNode(debugLabel: 'tooth chart 3D');
  late final AnimationController _anim;

  _Pose _pose = _Pose.front;
  _Pose _from = _Pose.front;
  _Pose _to = _Pose.front;
  _Jaws _jaws = _Jaws.both;
  bool _roots = false;
  String? _hover;
  bool _dragging = false;

  final Map<int, Offset> _pointers = {};
  Offset? _downPos;
  DateTime? _downAt;
  bool _moved = false;
  DateTime? _lastTapAt;
  String? _lastTapTooth;
  double? _lastPinch;
  double _panZoomScale = 1;

  _Frame? _frame;
  final _Buffers _buffers = _Buffers();

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(_onAnim);
  }

  @override
  void dispose() {
    _anim.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onAnim() {
    setState(() {
      _pose = _Pose.lerp(
        _from,
        _to,
        Curves.easeOutCubic.transform(_anim.value),
      );
    });
  }

  void _animateTo(_Pose target) {
    _from = _pose;
    _to = target;
    _anim
      ..duration = CruMotion.of(context)
      ..forward(from: 0);
  }

  void _setPose(_Pose p) {
    _anim.stop();
    setState(() => _pose = _clamp(p));
  }

  static _Pose _clamp(_Pose p) => _Pose(
    p.yaw,
    p.pitch.clamp(-1.45, 1.45),
    p.dist.clamp(70.0, 260.0),
    p.open.clamp(0.0, 1.0),
  );

  void _zoom(double factor) =>
      _setPose(_pose.copyWith(dist: _pose.dist * factor));

  void _focusTooth(String tooth) {
    final f = JawModel.of(child: widget.child).frames[tooth];
    if (f == null) return;
    final upper = f.axis.y > 0;
    if (upper && _jaws == _Jaws.lower || !upper && _jaws == _Jaws.upper) {
      setState(() => _jaws = _Jaws.both);
    }
    _animateTo(
      _Pose(
        math.atan2(-f.outward.x, f.outward.z),
        upper ? -0.3 : 0.38,
        98,
        _pose.open,
      ),
    );
  }

  // ------------------------------------------------------------- input

  String? _pick(Offset p) => _frame?.pick(p);

  void _onPointerDown(PointerDownEvent e) {
    _focus.requestFocus();
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1) {
      _downPos = e.localPosition;
      _downAt = DateTime.now();
      _moved = false;
      _anim.stop();
    } else {
      _moved = true;
      _lastPinch = _pinchDistance();
    }
  }

  double? _pinchDistance() {
    if (_pointers.length < 2) return null;
    final v = _pointers.values.toList();
    return (v[0] - v[1]).distance;
  }

  void _onPointerMove(PointerMoveEvent e) {
    final prev = _pointers[e.pointer];
    if (prev == null) return;
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length >= 2) {
      final d = _pinchDistance();
      if (d != null && _lastPinch != null && d > 0) {
        _zoom(_lastPinch! / d);
      }
      _lastPinch = d;
      // Two fingers also turn the jaws (half speed).
      final delta = (e.localPosition - prev) / 2;
      _rotate(delta);
      return;
    }
    if (_downPos != null && (e.localPosition - _downPos!).distance > 5) {
      _moved = true;
      if (!_dragging) setState(() => _dragging = true);
    }
    if (_moved) _rotate(e.localPosition - prev);
  }

  void _rotate(Offset delta) {
    _setPose(
      _pose.copyWith(
        yaw: _pose.yaw + delta.dx * 0.0085,
        pitch: _pose.pitch + delta.dy * 0.0085,
      ),
    );
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _lastPinch = null;
    if (_pointers.isNotEmpty) return;
    if (_dragging) setState(() => _dragging = false);
    final down = _downAt;
    if (!_moved &&
        down != null &&
        e is PointerUpEvent &&
        DateTime.now().difference(down) < const Duration(milliseconds: 400)) {
      final tooth = _pick(e.localPosition);
      final now = DateTime.now();
      final isDouble =
          _lastTapAt != null &&
          now.difference(_lastTapAt!) < kDoubleTapTimeout &&
          _lastTapTooth == tooth;
      _lastTapAt = now;
      _lastTapTooth = tooth;
      if (tooth != null) {
        widget.onSelect(tooth);
        if (isDouble) _focusTooth(tooth);
      }
    }
    _downPos = null;
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
        final dy = (ev as PointerScrollEvent).scrollDelta.dy;
        _zoom(math.exp(dy * 0.0012));
      });
    }
  }

  void _onPanZoomStart(PointerPanZoomStartEvent e) => _panZoomScale = 1;

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent e) {
    if (e.scale != _panZoomScale && e.scale > 0) {
      _zoom(_panZoomScale / e.scale);
      _panZoomScale = e.scale;
    }
    if (e.panDelta != Offset.zero) _rotate(e.panDelta);
  }

  void _onHover(PointerHoverEvent e) {
    if (_dragging) return;
    final hit = _pick(e.localPosition);
    if (hit != _hover) setState(() => _hover = hit);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    const step = 0.12;
    if (k == LogicalKeyboardKey.arrowLeft) {
      _setPose(_pose.copyWith(yaw: _pose.yaw - step));
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _setPose(_pose.copyWith(yaw: _pose.yaw + step));
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _setPose(_pose.copyWith(pitch: _pose.pitch - step));
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _setPose(_pose.copyWith(pitch: _pose.pitch + step));
    } else if (k == LogicalKeyboardKey.equal ||
        k == LogicalKeyboardKey.add ||
        k == LogicalKeyboardKey.numpadAdd) {
      _zoom(0.88);
    } else if (k == LogicalKeyboardKey.minus ||
        k == LogicalKeyboardKey.numpadSubtract) {
      _zoom(1 / 0.88);
    } else if (k == LogicalKeyboardKey.digit0 || k == LogicalKeyboardKey.home) {
      _animateTo(_Pose.front);
    } else if (k == LogicalKeyboardKey.keyO) {
      _animateTo(_pose.copyWith(open: _pose.open > 0.5 ? 0 : 1));
    } else if (k == LogicalKeyboardKey.enter && widget.selected != null) {
      widget.onOpen?.call(widget.selected!);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Semantics(
        label:
            '3D jaws. Drag or use the arrow keys to turn, scroll or '
            'plus and minus to zoom, O to open the mouth.',
        child: SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, widget.height);
              final frame = _Renderer(
                model: JawModel.of(child: widget.child),
                data: widget.data,
                mode: widget.mode,
                pose: _pose,
                jaws: _jaws,
                roots: _roots,
                selected: widget.selected,
                hover: _hover,
                colors: c,
                numbering: widget.numbering,
                buffers: _buffers,
              ).render(size);
              _frame = frame;
              return DecoratedBox(
                decoration: ShapeDecoration(
                  gradient: _stage(c),
                  shape: cruShape(CruRadius.panel),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(CruRadius.panel),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: RawGestureDetector(
                          gestures: {
                            EagerGestureRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                  EagerGestureRecognizer
                                >(EagerGestureRecognizer.new, (_) {}),
                          },
                          child: Listener(
                            onPointerDown: _onPointerDown,
                            onPointerMove: _onPointerMove,
                            onPointerUp: _onPointerUp,
                            onPointerCancel: _onPointerUp,
                            onPointerSignal: _onSignal,
                            onPointerPanZoomStart: _onPanZoomStart,
                            onPointerPanZoomUpdate: _onPanZoomUpdate,
                            child: MouseRegion(
                              cursor: _dragging
                                  ? SystemMouseCursors.grabbing
                                  : _hover != null
                                  ? SystemMouseCursors.click
                                  : SystemMouseCursors.grab,
                              onHover: _onHover,
                              onExit: (_) => setState(() => _hover = null),
                              child: CustomPaint(
                                painter: _FramePainter(frame, c),
                                size: size,
                              ),
                            ),
                          ),
                        ),
                      ),
                      for (final label in frame.callouts)
                        _CalloutChip(
                          label: label,
                          onTap: () => widget.onSelect(label.tooth),
                        ),
                      Positioned(
                        left: CruSpace.s12,
                        top: CruSpace.s12,
                        child: CruSegmentedControl<_Jaws>(
                          semanticLabel: 'Jaws',
                          segments: const [
                            CruSegment(_Jaws.both, 'Both'),
                            CruSegment(_Jaws.upper, 'Upper'),
                            CruSegment(_Jaws.lower, 'Lower'),
                          ],
                          selected: _jaws,
                          onChanged: (j) => setState(() => _jaws = j),
                        ),
                      ),
                      Positioned(
                        right: CruSpace.s12,
                        top: CruSpace.s12,
                        child: Row(
                          children: [
                            DentalChoiceChip(
                              onSurface: true,
                              label: 'Open mouth',
                              selected: _to.open > 0.5 && _pose.open > 0.01,
                              onTap: () => _animateTo(
                                _pose.copyWith(open: _pose.open > 0.5 ? 0 : 1),
                              ),
                            ),
                            const SizedBox(width: CruSpace.s8),
                            DentalChoiceChip(
                              onSurface: true,
                              label: 'Roots',
                              selected: _roots,
                              onTap: () => setState(() => _roots = !_roots),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: CruSpace.s12,
                        bottom: CruSpace.s12,
                        right: 150,
                        child: Wrap(
                          spacing: CruSpace.s6,
                          runSpacing: CruSpace.s6,
                          children: [
                            for (final (label, pose, jaws) in [
                              ('Front', _Pose.front, _Jaws.both),
                              (
                                'Left side',
                                const _Pose(-1.15, 0.12, 140, 0),
                                _Jaws.both,
                              ),
                              (
                                'Right side',
                                const _Pose(1.15, 0.12, 140, 0),
                                _Jaws.both,
                              ),
                              (
                                'Upper teeth',
                                const _Pose(0, -1.2, 135, 1),
                                _Jaws.upper,
                              ),
                              (
                                'Lower teeth',
                                const _Pose(0, 1.2, 135, 1),
                                _Jaws.lower,
                              ),
                            ])
                              _ViewChip(
                                label: label,
                                onTap: () {
                                  setState(() => _jaws = jaws);
                                  _animateTo(pose);
                                },
                              ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: CruSpace.s12,
                        bottom: CruSpace.s12,
                        child: Row(
                          children: [
                            CruSquareButton(
                              icon: const CruIconData('M5 12h14'),
                              secondary: true,
                              semanticLabel: 'Zoom out',
                              tooltip: 'Zoom out (−)',
                              onPressed: () => _zoom(1 / 0.85),
                            ),
                            const SizedBox(width: CruSpace.s6),
                            CruSquareButton(
                              icon: CruIcons.plus,
                              secondary: true,
                              semanticLabel: 'Zoom in',
                              tooltip: 'Zoom in (+)',
                              onPressed: () => _zoom(0.85),
                            ),
                            const SizedBox(width: CruSpace.s6),
                            CruSquareButton(
                              icon: DentalIcons.reset,
                              secondary: true,
                              semanticLabel: 'Reset view',
                              tooltip: 'Reset view (0)',
                              onPressed: () {
                                setState(() => _jaws = _Jaws.both);
                                _animateTo(_Pose.front);
                              },
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: CruSpace.s12 + CruSize.segmentHeight + CruSpace.s6,
                        child: IgnorePointer(
                          child: Text(
                            'Drag to turn · Scroll or pinch to zoom · '
                            'Double-click a tooth to bring it close',
                            textAlign: TextAlign.center,
                            style: CruType.caption.tint(c.label3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- renderer

/// Behind the jaws: white in the middle, a soft grey towards the edges.
Gradient _stage(CruColors c) => RadialGradient(
  center: const Alignment(0, -0.15),
  radius: 1.25,
  colors: c.isEvening
      ? const [Color(0xFF292D34), Color(0xFF1F2228), Color(0xFF16181C)]
      : const [Color(0xFFFFFFFF), Color(0xFFF6F7FA), Color(0xFFE8EBF1)],
  stops: const [0, 0.5, 1],
);

/// The disc behind a tooth's number in its callout: a soft tint of its
/// state's colour (amber waiting, green done, the accent for planned
/// work).
Color _mark(CruColors c, ToothState state, {required bool planned}) {
  final e = c.isEvening;
  Color tint(Color hue, double day, double evening) =>
      Color.lerp(c.surface, hue, e ? evening : day)!;
  if (planned) return tint(c.accent, 0.28, 0.55);
  return switch (state) {
    ToothState.needsCare => tint(c.amber, 0.36, 0.45),
    ToothState.treated => tint(c.green, 0.32, 0.42),
    ToothState.missing || ToothState.notErupted => tint(c.label3, 0.22, 0.3),
    ToothState.healthy => tint(c.label3, 0.1, 0.18),
  };
}

/// A colour in linear light (for shading).
typedef _Rgb = (double, double, double);

double _toLinear(double v) =>
    v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

_Rgb _lin(Color c) => (_toLinear(c.r), _toLinear(c.g), _toLinear(c.b));

_Rgb _mix(_Rgb a, _Rgb b, double t) => (
  a.$1 + (b.$1 - a.$1) * t,
  a.$2 + (b.$2 - a.$2) * t,
  a.$3 + (b.$3 - a.$3) * t,
);

/// Linear light (0..1 in 4096 steps) to an 8-bit sRGB channel.
final Uint8List _srgb = () {
  final t = Uint8List(4096);
  for (var i = 0; i < t.length; i++) {
    final v = i / (t.length - 1);
    final s = v <= 0.0031308 ? v * 12.92 : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
    t[i] = (s * 255).round().clamp(0, 255);
  }
  return t;
}();

/// The 3D chart's materials: porcelain teeth, their roots, titanium, and
/// the jaw bone as frosted glass (milky face-on, denser and greyer at
/// its edges).
class _Palette {
  _Palette(CruColors c)
    : enamel = _lin(
        c.isEvening ? const Color(0xFFDCDAD4) : const Color(0xFFF5F4F0),
      ),
      root = _lin(
        c.isEvening ? const Color(0xFF7D838D) : const Color(0xFFF1ECE3),
      ),
      rootShown = _lin(c.toothRoot),
      metal = _lin(c.implantMetal),
      accent = _lin(c.accent),
      amber = _lin(c.amber),
      green = _lin(c.green),
      boneFace = _lin(
        c.isEvening ? const Color(0xFF59606C) : const Color(0xFFF2F4F7),
      ),
      boneEdge = _lin(
        c.isEvening ? const Color(0xFFB9C1CE) : const Color(0xFFA2AAB7),
      );

  final _Rgb enamel;

  /// Roots inside the bone: near its colour, so they show only faintly.
  final _Rgb root;

  /// Roots when they're asked for: the cementum's own colour.
  final _Rgb rootShown;
  final _Rgb metal;
  final _Rgb accent;
  final _Rgb amber;
  final _Rgb green;
  final _Rgb boneFace;
  final _Rgb boneEdge;
}

/// A callout on the 3D view: which tooth, what to say, where.
class _Callout {
  const _Callout({
    required this.tooth,
    required this.number,
    required this.text,
    required this.anchor,
    required this.at,
    required this.mark,
    required this.selected,
  });

  final String tooth;

  /// The tooth's number as the clinic writes it.
  final String number;
  final String text;

  /// The point on the tooth, and the middle of the bubble.
  final Offset anchor;
  final Offset at;

  /// The disc behind the number.
  final Color mark;
  final bool selected;

  /// The bubble sits above its tooth (and points down to it).
  bool get above => at.dy < anchor.dy;

  /// The end of the bubble's pointer.
  Offset get tip => Offset(
    at.dx,
    at.dy + (above ? 1 : -1) * (_CalloutChip.height / 2 + _CalloutChip.tail),
  );

  _Callout movedTo(Offset p) => _Callout(
    tooth: tooth,
    number: number,
    text: text,
    anchor: anchor,
    at: p,
    mark: mark,
    selected: selected,
  );
}

/// One rendered image: the triangles to draw, what to pick, the callouts.
class _Frame {
  _Frame(this.vertices, this.screen, this.owner, this.teeth, this.callouts);

  final ui.Vertices? vertices;

  /// Six floats per triangle in draw order (back to front).
  final Float32List screen;

  /// Per triangle, its tooth's index in [teeth]; -1 for bone.
  final Int16List owner;
  final List<String> teeth;
  final List<_Callout> callouts;

  /// The front-most tooth under [p]. The bone is see-through, so it
  /// doesn't hide the teeth behind it.
  String? pick(Offset p) {
    final x = p.dx, y = p.dy;
    for (var t = owner.length - 1; t >= 0; t--) {
      if (owner[t] < 0) continue;
      final i = t * 6;
      final ax = screen[i], ay = screen[i + 1];
      final bx = screen[i + 2], by = screen[i + 3];
      final cx = screen[i + 4], cy = screen[i + 5];
      if (x < math.min(ax, math.min(bx, cx)) ||
          x > math.max(ax, math.max(bx, cx)) ||
          y < math.min(ay, math.min(by, cy)) ||
          y > math.max(ay, math.max(by, cy))) {
        continue;
      }
      final d1 = (x - bx) * (ay - by) - (ax - bx) * (y - by);
      final d2 = (x - cx) * (by - cy) - (bx - cx) * (y - cy);
      final d3 = (x - ax) * (cy - ay) - (cx - ax) * (y - ay);
      final neg = d1 < 0 || d2 < 0 || d3 < 0;
      final pos = d1 > 0 || d2 > 0 || d3 > 0;
      if (neg && pos) continue;
      return teeth[owner[t]];
    }
    return null;
  }
}

/// Scratch space for one chart's frames, reused from frame to frame.
class _Buffers {
  static const buckets = 1 << 14;

  Float64List vx = Float64List(0);
  Float64List vy = Float64List(0);
  Float64List vz = Float64List(0);
  Float64List px = Float64List(0);
  Float64List py = Float64List(0);
  Int32List col = Int32List(0);
  Float32List tri = Float32List(0);
  Int32List triCol = Int32List(0);
  Float64List depth = Float64List(0);
  Int16List owner = Int16List(0);
  Int32List keys = Int32List(0);
  Int32List order = Int32List(0);
  final Int32List counts = Int32List(buckets + 1);

  void ensure(int vertices, int triangles) {
    if (vx.length < vertices) {
      vx = Float64List(vertices);
      vy = Float64List(vertices);
      vz = Float64List(vertices);
      px = Float64List(vertices);
      py = Float64List(vertices);
      col = Int32List(vertices);
    }
    if (depth.length < triangles) {
      tri = Float32List(triangles * 6);
      triCol = Int32List(triangles * 3);
      depth = Float64List(triangles);
      owner = Int16List(triangles);
      keys = Int32List(triangles);
      order = Int32List(triangles);
    }
  }
}

class _Renderer {
  _Renderer({
    required this.model,
    required this.data,
    required this.mode,
    required this.pose,
    required this.jaws,
    required this.roots,
    required this.selected,
    required this.hover,
    required this.colors,
    required this.numbering,
    required this.buffers,
  });

  final JawModel model;
  final ToothChartData data;
  final ChartMode mode;
  final _Pose pose;
  final _Jaws jaws;
  final bool roots;
  final String? selected;
  final String? hover;
  final CruColors colors;
  final ToothNumbering numbering;
  final _Buffers buffers;

  // Lights, in view space: a key light from above left, a fill from the
  // right, and a rim from behind.
  static final _V _key = _V.unit(-0.42, 0.72, 0.56);
  static final _V _fill = _V.unit(0.62, -0.05, 0.78);
  static final _V _back = _V.unit(0.15, 0.55, -0.82);

  /// How a tooth part looks: its colour (linear), opacity and shine;
  /// null when it isn't drawn.
  (_Rgb, double, double)? _surface(MeshPart part, ToothVisual v, _Palette pal) {
    _Rgb base;
    var alpha = 1.0;
    double gloss;
    switch (part.material) {
      case MeshMaterial.bone:
        return null;
      case MeshMaterial.root:
        if (v.missing || v.implant) return null;
        base = roots ? pal.rootShown : pal.root;
        gloss = 0.06;
      case MeshMaterial.implant:
        if (!v.implant) return null;
        base = pal.metal;
        gloss = 0.8;
      case MeshMaterial.crown:
        base = pal.enamel;
        gloss = 0.42;
        if (v.missing && !v.implant) {
          alpha = 0.2;
          gloss = 0;
        } else if (mode == ChartMode.plan) {
          if (v.isPlanned) base = _mix(base, pal.accent, 0.42);
        } else {
          base = switch (v.state) {
            ToothState.needsCare => _mix(base, pal.amber, 0.45),
            ToothState.treated => _mix(base, pal.green, v.capped ? 0.42 : 0.3),
            _ => base,
          };
        }
    }
    if (part.tooth == selected) {
      base = _mix(base, pal.accent, 0.5);
    } else if (part.tooth == hover) {
      base = _mix(base, pal.accent, 0.22);
    }
    return (base, alpha, gloss);
  }

  _Frame render(Size size) {
    final c = colors;
    final pal = _Palette(c);
    final cx = size.width / 2;
    final cy = size.height / 2 + 8;
    final focal = math.min(size.width, size.height) * 1.8;
    final cyaw = math.cos(pose.yaw), syaw = math.sin(pose.yaw);
    final cp = math.cos(pose.pitch), sp = math.sin(pose.pitch);
    final openA = pose.open * 0.42;
    final co = math.cos(openA), so = math.sin(openA);
    final hy = model.hingeY, hz = model.hingeZ;
    final dist = pose.dist;

    final buf = buffers..ensure(model.maxVertices, model.triangleCount);
    final vx = buf.vx, vy = buf.vy, vz = buf.vz;
    final px = buf.px, py = buf.py, col = buf.col;
    final tri = buf.tri, triCol = buf.triCol, depth = buf.depth;
    final owner = buf.owner;
    final lut = _srgb;
    const top = 4095.0;
    final kx = _key.x, ky = _key.y, kz = _key.z;
    final fx = _fill.x, fy = _fill.y, fz = _fill.z;
    final bx = _back.x, by = _back.y, bz = _back.z;
    // The bone is milky face-on, so the roots show only as a hint, and
    // denser at its edges; nearly clear when the roots are asked for.
    final boneFaceA = roots ? 0.12 : 0.84;
    final boneEdgeA = roots ? 0.45 : 0.95;
    var count = 0;
    var zMin = double.infinity, zMax = -double.infinity;

    for (final part in model.parts) {
      if (part.lower ? jaws == _Jaws.upper : jaws == _Jaws.lower) continue;
      final tooth = part.tooth;
      final ghost = part.material == MeshMaterial.bone;
      final v = tooth == null ? null : data.of(tooth);
      var base = pal.boneFace;
      var alpha = 1.0;
      var gloss = 0.0;
      if (!ghost) {
        final look = _surface(part, v!, pal);
        if (look == null) continue;
        (base, alpha, gloss) = look;
      }
      final (ar, ag, ab) = base;
      final (er, eg, eb) = pal.boneEdge;
      final a = (alpha * 255).round() << 24;

      // Unerupted teeth sit down in the bone.
      var sx = 0.0, sy = 0.0, sz = 0.0;
      final frame = tooth == null ? null : model.frames[tooth];
      if (v != null && frame != null && v.state == ToothState.notErupted) {
        final k = frame.spec.crown * 0.55;
        sx = frame.axis.x * k;
        sy = frame.axis.y * k;
        sz = frame.axis.z * k;
      }

      final n = part.vertexCount;
      final pos = part.positions, nrm = part.normals;
      final occ = part.occlusion, fade = part.fade;
      // Where the bone covers a root's neck the root takes on its colour,
      // unless the roots are asked for.
      final neck = roots ? null : part.neck;
      final (gr, gg, gb) = pal.boneFace;
      final opens = part.lower && openA > 0;
      for (var i = 0; i < n; i++) {
        final i3 = i * 3;
        final x = pos[i3] + sx;
        var y = pos[i3 + 1] + sy;
        var z = pos[i3 + 2] + sz;
        var nx = nrm[i3], ny = nrm[i3 + 1], nz = nrm[i3 + 2];
        if (opens) {
          final dy = y - hy, dz = z - hz;
          y = hy + dy * co - dz * so;
          z = hz + dy * so + dz * co;
          final ny2 = ny * co - nz * so;
          nz = ny * so + nz * co;
          ny = ny2;
        }
        final x1 = x * cyaw + z * syaw;
        final z1 = -x * syaw + z * cyaw;
        final yv = y * cp - z1 * sp;
        final zv = y * sp + z1 * cp - dist;
        vx[i] = x1;
        vy[i] = yv;
        vz[i] = zv;
        final w = -zv;
        px[i] = cx + focal * x1 / w;
        py[i] = cy - focal * yv / w;
        // The normal, turned the same way.
        final nxv = nx * cyaw + nz * syaw;
        final nz1 = -nx * syaw + nz * cyaw;
        final nyv = ny * cp - nz1 * sp;
        final nzv = ny * sp + nz1 * cp;
        // Towards the eye.
        final il = 1 / math.sqrt(x1 * x1 + yv * yv + zv * zv);
        final ex = -x1 * il, ey = -yv * il, ez = -zv * il;
        var facing = nxv * ex + nyv * ey + nzv * ez;
        if (facing < 0) facing = 0;
        final rim = 1 - facing;
        final k1 = nxv * kx + nyv * ky + nzv * kz;

        if (ghost) {
          // Matte, lit like the teeth so it has form; greyer and denser
          // towards its edges, like frosted glass.
          final f2 = rim * rim;
          var d1 = (k1 + 0.4) / 1.4;
          if (d1 < 0) d1 = 0;
          var d2 = (nxv * fx + nyv * fy + nzv * fz + 0.4) / 1.4;
          if (d2 < 0) d2 = 0;
          final light = 0.5 + 0.08 * nyv + 0.46 * d1 + 0.12 * d2;
          // Where the bone fades out (at the necks, above the jaw) its
          // edges don't darken either.
          final f = fade![i];
          final edge = f2 * 0.5 * f;
          final r = ar * light * (1 - edge) + er * edge;
          final g = ag * light * (1 - edge) + eg * edge;
          final b = ab * light * (1 - edge) + eb * edge;
          final al = (f * (boneFaceA + (boneEdgeA - boneFaceA) * f2) * 255)
              .round();
          col[i] =
              (al << 24) |
              (lut[((r >= 1 ? 1.0 : r) * top).toInt()] << 16) |
              (lut[((g >= 1 ? 1.0 : g) * top).toInt()] << 8) |
              lut[((b >= 1 ? 1.0 : b) * top).toInt()];
          continue;
        }

        // Soft light that wraps round the crown, as through enamel; a
        // brighter sky than ground; grooves and contacts in shade.
        final ao = occ == null ? 1.0 : occ[i];
        var d1 = (k1 + 0.3) / 1.3;
        if (d1 < 0) d1 = 0;
        var d2 = (nxv * fx + nyv * fy + nzv * fz + 0.3) / 1.3;
        if (d2 < 0) d2 = 0;
        var d3 = nxv * bx + nyv * by + nzv * bz;
        if (d3 < 0) d3 = 0;
        // The sky and fill a little cool, the key light a little warm.
        final sky = (0.3 + 0.1 * nyv) * ao;
        final key = 0.62 * d1 * (0.4 + 0.6 * ao);
        final fill = 0.2 * d2 * (0.4 + 0.6 * ao);
        final glow = 0.1 * d3 + 0.08 * rim * rim * rim;
        final litR = sky * 0.95 + key * 1.03 + fill * 0.95 + glow;
        final litG = sky * 0.98 + key + fill * 0.99 + glow;
        final litB = sky * 1.05 + key * 0.95 + fill * 1.05 + glow;
        // A glossy highlight from the key light.
        var spec = 0.0;
        if (gloss > 0) {
          final hx = kx + ex, hy2 = ky + ey, hz2 = kz + ez;
          var h =
              (nxv * hx + nyv * hy2 + nzv * hz2) /
              math.sqrt(hx * hx + hy2 * hy2 + hz2 * hz2);
          if (h < 0) h = 0;
          final h2 = h * h, h4 = h2 * h2, h8 = h4 * h4;
          final h16 = h8 * h8, h32 = h16 * h16;
          spec = gloss * (0.55 * h32 * h16 + 0.12 * h8) * ao;
        }
        var r = ar, g = ag, b = ab;
        if (neck != null) {
          final t = neck[i];
          r += (gr - r) * t;
          g += (gg - g) * t;
          b += (gb - b) * t;
        }
        r = r * litR + spec;
        g = g * litG + spec;
        b = b * litB + spec;
        if (r > 1) r = 1;
        if (g > 1) g = 1;
        if (b > 1) b = 1;
        col[i] =
            a |
            (lut[(r * top).toInt()] << 16) |
            (lut[(g * top).toInt()] << 8) |
            lut[(b * top).toInt()];
      }

      final tris = part.triangles;
      final id = tooth == null ? -1 : model.toothIds[tooth]!;
      // The bone sorts a little nearer than it is, so where it meets
      // the teeth at their necks it covers them evenly.
      final bias = ghost ? 1.5 : 0.0;
      for (var t = 0; t < tris.length; t += 3) {
        final ia = tris[t], ib = tris[t + 1], ic = tris[t + 2];
        final az = vz[ia], bz2 = vz[ib], cz = vz[ic];
        if (az > -1 || bz2 > -1 || cz > -1) continue;
        // Back faces away.
        final ax = vx[ia], ay = vy[ia];
        final ux = vx[ib] - ax, uy = vy[ib] - ay, uz = bz2 - az;
        final wx = vx[ic] - ax, wy = vy[ic] - ay, wz = cz - az;
        final fnx = uy * wz - uz * wy;
        final fny = uz * wx - ux * wz;
        final fnz = ux * wy - uy * wx;
        if (fnx * -ax + fny * -ay + fnz * -az <= 0) continue;
        final o = count * 6;
        tri[o] = px[ia];
        tri[o + 1] = py[ia];
        tri[o + 2] = px[ib];
        tri[o + 3] = py[ib];
        tri[o + 4] = px[ic];
        tri[o + 5] = py[ic];
        final oc = count * 3;
        triCol[oc] = col[ia];
        triCol[oc + 1] = col[ib];
        triCol[oc + 2] = col[ic];
        final d = az + bz2 + cz + bias;
        depth[count] = d;
        if (d < zMin) zMin = d;
        if (d > zMax) zMax = d;
        owner[count] = id;
        count++;
      }
    }

    // Back to front: a counting sort on depth.
    const buckets = _Buffers.buckets;
    final counts = buf.counts..fillRange(0, buckets + 1, 0);
    final keys = buf.keys, order = buf.order;
    final span = zMax - zMin;
    final scale = span > 0 ? (buckets - 1) / span : 0.0;
    for (var t = 0; t < count; t++) {
      final k = ((depth[t] - zMin) * scale).toInt();
      keys[t] = k;
      counts[k + 1]++;
    }
    for (var k = 1; k <= buckets; k++) {
      counts[k] += counts[k - 1];
    }
    for (var t = 0; t < count; t++) {
      order[counts[keys[t]]++] = t;
    }
    final positions = Float32List(count * 6);
    final colorsOut = Int32List(count * 3);
    final owners = Int16List(count);
    for (var k = 0; k < count; k++) {
      final t = order[k];
      final s6 = t * 6, d6 = k * 6;
      positions[d6] = tri[s6];
      positions[d6 + 1] = tri[s6 + 1];
      positions[d6 + 2] = tri[s6 + 2];
      positions[d6 + 3] = tri[s6 + 3];
      positions[d6 + 4] = tri[s6 + 4];
      positions[d6 + 5] = tri[s6 + 5];
      final s3 = t * 3, d3 = k * 3;
      colorsOut[d3] = triCol[s3];
      colorsOut[d3 + 1] = triCol[s3 + 1];
      colorsOut[d3 + 2] = triCol[s3 + 2];
      owners[k] = owner[t];
    }

    // Transforms a model point into view space ([x, y, z]; camera at the
    // origin looking down -z).
    List<double> toView(double x, double y, double z, bool lower) {
      if (lower && openA > 0) {
        final dy = y - hy, dz = z - hz;
        y = hy + dy * co - dz * so;
        z = hz + dy * so + dz * co;
      }
      final x1 = x * cyaw + z * syaw;
      final z1 = -x * syaw + z * cyaw;
      final y2 = y * cp - z1 * sp;
      final z2 = y * sp + z1 * cp;
      return [x1, y2, z2 - dist];
    }

    // Callouts for teeth with something to say, facing the camera.
    final callouts = <_Callout>[];
    for (final e in model.frames.entries) {
      final tooth = e.key;
      final f = e.value;
      final upper = f.axis.y > 0;
      if (upper && jaws == _Jaws.lower || !upper && jaws == _Jaws.upper) {
        continue;
      }
      final v = data.of(tooth);
      final text = v.callout(mode);
      final isSel = tooth == selected;
      if (text == null && !isSel) continue;
      // Facing: the cheek side or the biting surface points at the camera.
      double facingOf(V3 point, V3 dir) {
        final a = toView(point.x, point.y, point.z, !upper);
        final tip = point + dir * 10;
        final b = toView(tip.x, tip.y, tip.z, !upper);
        final ox = b[0] - a[0], oy = b[1] - a[1], oz = b[2] - a[2];
        return (ox * -a[0] + oy * -a[1] + oz * -a[2]) /
            (math.sqrt(ox * ox + oy * oy + oz * oz) *
                math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]));
      }

      final side = facingOf(f.anchor, f.outward);
      final top = facingOf(f.base, f.axis * -1);
      final fromTop = top > side;
      if (math.max(side, top) < 0.2 && !isSel) continue;
      final an = fromTop ? f.base : f.anchor;
      final a = toView(an.x, an.y, an.z, !upper);
      final tip = an + f.outward * 10;
      final b = toView(tip.x, tip.y, tip.z, !upper);
      final pa = Offset(cx + focal * a[0] / -a[2], cy - focal * a[1] / -a[2]);
      final pb = Offset(cx + focal * b[0] / -b[2], cy - focal * b[1] / -b[2]);
      var dir = pb - pa;
      if (dir.distance < 1) dir = Offset(0, upper ? -1 : 1);
      dir = dir / dir.distance;
      // Out from the arch, and up from the upper teeth or down from the
      // lower ones.
      var lift = dir + Offset(0, upper ? -1.6 : 1.6);
      lift = lift / lift.distance;
      final at = pa + lift * 54;
      callouts.add(
        _Callout(
          tooth: tooth,
          number: toothLabel(tooth, numbering),
          text:
              text ??
              (mode == ChartMode.plan
                  ? 'Nothing planned'
                  : DentalChart.stateLabel(v.state)),
          anchor: pa,
          at: Offset(
            at.dx.clamp(70.0, size.width - 70),
            at.dy.clamp(56.0, size.height - 56),
          ),
          mark: _mark(
            c,
            v.state,
            planned: mode == ChartMode.plan && v.isPlanned,
          ),
          selected: isSel,
        ),
      );
    }
    final shown = _spread(
      callouts.length <= 12
          ? callouts
          : [
              ...callouts.where((c) => c.selected),
              ...callouts.where((c) => !c.selected).take(11),
            ],
      size,
    );

    return _Frame(
      positions.isEmpty
          ? null
          : ui.Vertices.raw(
              ui.VertexMode.triangles,
              positions,
              colors: colorsOut,
            ),
      positions,
      owners,
      model.teeth,
      shown,
    );
  }
}

/// A unit vector for the lights.
class _V {
  const _V(this.x, this.y, this.z);

  factory _V.unit(double x, double y, double z) {
    final l = math.sqrt(x * x + y * y + z * z);
    return _V(x / l, y / l, z / l);
  }

  final double x, y, z;
}

/// Moves callouts apart so none overlap (estimated bubble sizes). A
/// bubble above its tooth moves up and one below moves down, away from
/// the teeth.
List<_Callout> _spread(List<_Callout> input, Size size) {
  if (input.length < 2) return input;
  final at = [for (final c in input) c.at];
  double w(int i) => input[i].text.length * 7.0 + 52;
  const h = _CalloutChip.height + _CalloutChip.tail + 4;
  for (var pass = 0; pass < 24; pass++) {
    var moved = false;
    for (var i = 0; i < at.length; i++) {
      for (var j = i + 1; j < at.length; j++) {
        final dx = (at[i].dx - at[j].dx).abs();
        final dy = (at[i].dy - at[j].dy).abs();
        final minX = (w(i) + w(j)) / 2;
        if (dx >= minX || dy >= h) continue;
        moved = true;
        final iFirst = at[i].dy <= at[j].dy;
        final push = h - dy + 1;
        final up = input[i].above && input[j].above;
        final down = !input[i].above && !input[j].above;
        if (up) {
          // The higher one goes higher.
          if (iFirst) {
            at[i] = at[i].translate(0, -push);
          } else {
            at[j] = at[j].translate(0, -push);
          }
        } else if (down) {
          if (iFirst) {
            at[j] = at[j].translate(0, push);
          } else {
            at[i] = at[i].translate(0, push);
          }
        } else {
          at[i] = at[i].translate(0, iFirst ? -push / 2 : push / 2);
          at[j] = at[j].translate(0, iFirst ? push / 2 : -push / 2);
        }
      }
    }
    if (!moved) break;
  }
  return [
    for (var i = 0; i < input.length; i++)
      input[i].movedTo(
        Offset(
          at[i].dx.clamp(70.0, size.width - 70),
          at[i].dy.clamp(56.0, size.height - 56),
        ),
      ),
  ];
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.frame, this.colors);

  final _Frame frame;
  final CruColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final v = frame.vertices;
    if (v != null) canvas.drawVertices(v, BlendMode.dst, Paint());
    // A fine line from each bubble's pointer to its tooth, and a dot on
    // the tooth.
    for (final c in frame.callouts) {
      final ink = c.selected ? colors.accent : colors.label3;
      final tip = c.tip;
      if ((tip - c.anchor).distance > 4) {
        canvas.drawLine(
          tip,
          c.anchor,
          Paint()
            ..color = ink.withValues(alpha: 0.6)
            ..strokeWidth = 1,
        );
      }
      canvas.drawCircle(c.anchor, 3, Paint()..color = colors.surface);
      canvas.drawCircle(
        c.anchor,
        3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = c.selected ? colors.accent : colors.label2,
      );
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => true;
}

/// A white bubble pointing at its tooth: the tooth's number on a disc in
/// its state's colour, then what was found or planned.
class _CalloutChip extends StatelessWidget {
  const _CalloutChip({required this.label, required this.onTap});

  static const double height = 30;
  static const double tail = 6;

  final _Callout label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final selected = label.selected;
    final above = label.above;
    return Positioned(
      left: label.at.dx,
      top: label.at.dy - height / 2 - (above ? 0 : tail),
      child: FractionalTranslation(
        translation: const Offset(-0.5, 0),
        child: CruPressable(
          onTap: onTap,
          semanticLabel: 'Tooth ${label.number}, ${label.text}',
          builder: (context, hovered) => Container(
            height: height + tail,
            padding: EdgeInsets.fromLTRB(
              4,
              above ? 0 : tail,
              CruSpace.s12,
              above ? tail : 0,
            ),
            decoration: ShapeDecoration(
              color: selected
                  ? c.accent
                  : hovered
                  ? cruHoverShade(c.surface, c)
                  : c.surface,
              shape: _BubbleBorder(pointDown: above, tail: tail),
              shadows: [
                BoxShadow(
                  color: c.isEvening
                      ? const Color(0x73000000)
                      : const Color(0x243B4A6B),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: selected ? c.onAccent : label.mark,
                    shape: const CircleBorder(),
                  ),
                  child: Text(
                    label.number,
                    maxLines: 1,
                    style: CruType.micro.w600.tabular.tint(
                      selected ? c.accent : c.label,
                    ),
                  ),
                ),
                const SizedBox(width: CruSpace.s8),
                Text(
                  label.text,
                  maxLines: 1,
                  style: CruType.caption.w600.tint(
                    selected
                        ? c.onAccent
                        : c.isEvening
                        ? CruBrand.ink300
                        : c.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill with a small pointer in the middle of its top or bottom edge.
class _BubbleBorder extends ShapeBorder {
  const _BubbleBorder({required this.pointDown, required this.tail});

  final bool pointDown;
  final double tail;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  Path _path(Rect rect) {
    final pill = pointDown
        ? Rect.fromLTRB(rect.left, rect.top, rect.right, rect.bottom - tail)
        : Rect.fromLTRB(rect.left, rect.top + tail, rect.right, rect.bottom);
    final x = rect.center.dx;
    final body = Path()
      ..addRRect(
        RRect.fromRectAndRadius(pill, Radius.circular(pill.height / 2)),
      );
    final edge = pointDown ? pill.bottom - 1 : pill.top + 1;
    final end = pointDown ? rect.bottom : rect.top;
    final pointer = Path()
      ..moveTo(x - tail, edge)
      ..quadraticBezierTo(x - tail * 0.3, edge, x, end)
      ..quadraticBezierTo(x + tail * 0.3, edge, x + tail, edge)
      ..close();
    return Path.combine(PathOperation.union, body, pointer);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}

/// A preset view ("Front", "Upper teeth").
class _ViewChip extends StatelessWidget {
  const _ViewChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      semanticLabel: '$label view',
      builder: (context, hovered) => Container(
        height: CruSize.chip,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
        decoration: ShapeDecoration(
          color: hovered ? cruHoverShade(c.surface, c) : c.surface,
          shape: StadiumBorder(side: BorderSide(color: c.hairline)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text(label, style: CruType.subhead.w500.tint(c.label2))],
        ),
      ),
    );
  }
}
