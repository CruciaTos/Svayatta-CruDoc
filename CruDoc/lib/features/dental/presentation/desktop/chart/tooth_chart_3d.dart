import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
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
      _Pose(yaw ?? this.yaw, pitch ?? this.pitch, dist ?? this.dist,
          open ?? this.open);

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

/// Both jaws in 3D. Drag to turn, scroll or pinch to zoom, click a tooth
/// to select it, double-click to bring it to the front. Open the mouth,
/// show the roots, or jump to a preset view. Callouts name the teeth
/// with findings (or planned work).
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
  });

  final ToothChartData data;
  final bool child;
  final ChartMode mode;
  final String? selected;
  final ValueChanged<String> onSelect;

  /// Enter on the selected tooth.
  final ValueChanged<String>? onOpen;
  final double height;

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
      _pose = _Pose.lerp(_from, _to, Curves.easeOutCubic.transform(_anim.value));
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
    _animateTo(_Pose(
      math.atan2(-f.outward.x, f.outward.z),
      upper ? -0.3 : 0.38,
      98,
      _pose.open,
    ));
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
    _setPose(_pose.copyWith(
      yaw: _pose.yaw + delta.dx * 0.0085,
      pitch: _pose.pitch + delta.dy * 0.0085,
    ));
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
      final isDouble = _lastTapAt != null &&
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
        label: '3D jaws. Drag or use the arrow keys to turn, scroll or '
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
              ).render(size);
              _frame = frame;
              return DecoratedBox(
                decoration: ShapeDecoration(
                  color: c.stage,
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
                                    EagerGestureRecognizer>(
                              EagerGestureRecognizer.new,
                              (_) {},
                            ),
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
                                  _pose.copyWith(open: _pose.open > 0.5 ? 0 : 1)),
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
                              ('Left side', const _Pose(-1.15, 0.12, 140, 0), _Jaws.both),
                              ('Right side', const _Pose(1.15, 0.12, 140, 0), _Jaws.both),
                              ('Upper teeth', const _Pose(0, -1.2, 135, 1), _Jaws.upper),
                              ('Lower teeth', const _Pose(0, 1.2, 135, 1), _Jaws.lower),
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

/// A callout on the 3D view: which tooth, what to say, where.
class _Callout {
  const _Callout({
    required this.tooth,
    required this.text,
    required this.anchor,
    required this.at,
    required this.dot,
    required this.selected,
  });

  final String tooth;
  final String text;
  final Offset anchor;
  final Offset at;
  final Color dot;
  final bool selected;
}

/// One rendered image: the triangles to draw, what to pick, the callouts.
class _Frame {
  _Frame(this.vertices, this.screen, this.owner, this.callouts);

  final ui.Vertices? vertices;

  /// Six floats per triangle in draw order (back to front).
  final Float32List screen;

  /// Tooth per triangle; null for gums.
  final List<String?> owner;
  final List<_Callout> callouts;

  /// The front-most tooth under [p] (gums in front hide what's behind).
  String? pick(Offset p) {
    final x = p.dx, y = p.dy;
    for (var t = owner.length - 1; t >= 0; t--) {
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
      return owner[t];
    }
    return null;
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

  static const _lx = -0.36, _ly = 0.56, _lz = 0.745;

  _Frame render(Size size) {
    final c = colors;
    final cx = size.width / 2;
    final cy = size.height / 2 + 8;
    final focal = math.min(size.width, size.height) * 1.8;
    final cyaw = math.cos(pose.yaw), syaw = math.sin(pose.yaw);
    final cp = math.cos(pose.pitch), sp = math.sin(pose.pitch);
    final openA = pose.open * 0.42;
    final co = math.cos(openA), so = math.sin(openA);
    final hy = model.hingeY, hz = model.hingeZ;

    final screen = <double>[];
    final depth = <double>[];
    final colorsOut = <int>[];
    final owner = <String?>[];

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
      return [x1, y2, z2 - pose.dist];
    }

    for (final part in model.parts) {
      if (part.lower && jaws == _Jaws.upper) continue;
      if (!part.lower && jaws == _Jaws.lower) continue;
      final tooth = part.tooth;
      final v = tooth == null ? null : data.of(tooth);
      final frame = tooth == null ? null : model.frames[tooth];

      // What to draw, in which colour.
      Color base;
      var alpha = 1.0;
      var shiny = 0.0;
      switch (part.material) {
        case MeshMaterial.gum:
          base = c.gum;
          if (roots) alpha = 0.3;
        case MeshMaterial.root:
          if (!roots || v!.missing || v.implant) continue;
          base = c.toothRoot;
        case MeshMaterial.implant:
          if (!v!.implant || !roots) continue;
          base = c.implantMetal;
          shiny = 0.5;
        case MeshMaterial.crown:
          base = c.enamel;
          shiny = 0.38;
          if (v!.missing && !v.implant) {
            alpha = 0.16;
            shiny = 0;
          } else if (mode == ChartMode.plan) {
            if (v.isPlanned) base = Color.lerp(base, c.accent, 0.42)!;
          } else {
            base = switch (v.state) {
              ToothState.needsCare => Color.lerp(base, c.amber, 0.5)!,
              ToothState.treated => Color.lerp(base, c.green, v.capped ? 0.45 : 0.3)!,
              _ => base,
            };
          }
      }
      if (tooth != null && part.material != MeshMaterial.gum) {
        if (tooth == selected) {
          base = Color.lerp(base, c.accent, 0.5)!;
        } else if (tooth == hover) {
          base = Color.lerp(base, c.accent, 0.22)!;
        }
      }

      // Unerupted teeth sit down in the gum.
      var sx = 0.0, sy = 0.0, sz = 0.0;
      if (v != null && frame != null && v.state == ToothState.notErupted) {
        final k = frame.spec.crown * 0.55;
        sx = frame.axis.x * k;
        sy = frame.axis.y * k;
        sz = frame.axis.z * k;
      }

      final n = part.vertexCount;
      final vx = Float64List(n), vy = Float64List(n), vz = Float64List(n);
      final px = Float64List(n), py = Float64List(n);
      final col = Int32List(n);
      final argb = base.toARGB32();
      final br = (argb >> 16) & 0xFF, bg = (argb >> 8) & 0xFF, bb = argb & 0xFF;
      final a = (alpha * 255).round() << 24;
      final pos = part.positions, nrm = part.normals;
      final opens = part.lower && openA > 0;
      for (var i = 0; i < n; i++) {
        final x = pos[i * 3] + sx;
        var y = pos[i * 3 + 1] + sy;
        var z = pos[i * 3 + 2] + sz;
        if (opens) {
          final dy = y - hy, dz = z - hz;
          y = hy + dy * co - dz * so;
          z = hz + dy * so + dz * co;
        }
        final x1 = x * cyaw + z * syaw;
        final z1 = -x * syaw + z * cyaw;
        final y2 = y * cp - z1 * sp;
        final zc = y * sp + z1 * cp - pose.dist;
        vx[i] = x1;
        vy[i] = y2;
        vz[i] = zc;
        final w = -zc;
        px[i] = cx + focal * x1 / w;
        py[i] = cy - focal * y2 / w;
        // Normal: the same turns, no translation.
        var nx = nrm[i * 3], ny = nrm[i * 3 + 1], nz = nrm[i * 3 + 2];
        if (opens) {
          final ny2 = ny * co - nz * so;
          nz = ny * so + nz * co;
          ny = ny2;
        }
        final nx1 = nx * cyaw + nz * syaw;
        final nz1 = -nx * syaw + nz * cyaw;
        final ny2 = ny * cp - nz1 * sp;
        final nz2 = ny * sp + nz1 * cp;
        nx = nx1;
        ny = ny2;
        nz = nz2;
        final diff = math.max(0.0, nx * _lx + ny * _ly + nz * _lz);
        final fill = math.max(0.0, nx * 0.45 - ny * 0.3 + nz * 0.8) * 0.2;
        var k = 0.36 + 0.64 * diff + fill;
        // Specular (Blinn, view straight on).
        var spec = 0.0;
        if (shiny > 0) {
          var h = math.max(0.0, nx * -0.2 + ny * 0.32 + nz * 0.93);
          h = h * h;
          h = h * h;
          h = h * h;
          h = h * h;
          h = h * h;
          spec = h * shiny * 255;
        }
        if (k > 1.15) k = 1.15;
        final r = (br * k + spec).clamp(0, 255).toInt();
        final g = (bg * k + spec).clamp(0, 255).toInt();
        final b = (bb * k + spec).clamp(0, 255).toInt();
        col[i] = a | (r << 16) | (g << 8) | b;
      }

      final tris = part.triangles;
      for (var t = 0; t < tris.length; t += 3) {
        final ia = tris[t], ib = tris[t + 1], ic = tris[t + 2];
        // Back faces away.
        final ux = vx[ib] - vx[ia], uy = vy[ib] - vy[ia], uz = vz[ib] - vz[ia];
        final wx = vx[ic] - vx[ia], wy = vy[ic] - vy[ia], wz = vz[ic] - vz[ia];
        final fnx = uy * wz - uz * wy;
        final fny = uz * wx - ux * wz;
        final fnz = ux * wy - uy * wx;
        if (fnx * -vx[ia] + fny * -vy[ia] + fnz * -vz[ia] <= 0) continue;
        if (vz[ia] > -1 || vz[ib] > -1 || vz[ic] > -1) continue;
        screen
          ..add(px[ia])
          ..add(py[ia])
          ..add(px[ib])
          ..add(py[ib])
          ..add(px[ic])
          ..add(py[ic]);
        colorsOut
          ..add(col[ia])
          ..add(col[ib])
          ..add(col[ic]);
        depth.add((vz[ia] + vz[ib] + vz[ic]) / 3);
        owner.add(tooth);
      }
    }

    // Back to front.
    final order = List<int>.generate(depth.length, (i) => i)
      ..sort((a, b) => depth[a].compareTo(depth[b]));
    final positions = Float32List(order.length * 6);
    final colorsArr = Int32List(order.length * 3);
    final owners = List<String?>.filled(order.length, null);
    for (var k = 0; k < order.length; k++) {
      final t = order[k];
      for (var j = 0; j < 6; j++) {
        positions[k * 6 + j] = screen[t * 6 + j];
      }
      for (var j = 0; j < 3; j++) {
        colorsArr[k * 3 + j] = colorsOut[t * 3 + j];
      }
      owners[k] = owner[t];
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
      final dirV = f.outward;
      final a = toView(an.x, an.y, an.z, !upper);
      final tip = an + dirV * 10;
      final b = toView(tip.x, tip.y, tip.z, !upper);
      final pa = Offset(cx + focal * a[0] / -a[2], cy - focal * a[1] / -a[2]);
      final pb = Offset(cx + focal * b[0] / -b[2], cy - focal * b[1] / -b[2]);
      var dir = pb - pa;
      if (dir.distance < 1) dir = Offset(0, upper ? -1 : 1);
      dir = dir / dir.distance;
      final at = pa + dir * 46 + Offset(0, upper ? -16 : 16);
      final Color dot;
      if (mode == ChartMode.plan) {
        dot = c.accent;
      } else {
        dot = toothColors(c, v.state).text;
      }
      callouts.add(_Callout(
        tooth: tooth,
        text: text == null ? tooth : '$tooth  $text',
        anchor: pa,
        at: Offset(
          at.dx.clamp(60.0, size.width - 60),
          at.dy.clamp(56.0, size.height - 56),
        ),
        dot: dot,
        selected: isSel,
      ));
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
          : ui.Vertices.raw(ui.VertexMode.triangles, positions,
              colors: colorsArr),
      positions,
      owners,
      shown,
    );
  }
}

/// Moves callouts apart so none overlap (estimated pill sizes).
List<_Callout> _spread(List<_Callout> input, Size size) {
  if (input.length < 2) return input;
  final at = [for (final c in input) c.at];
  double w(int i) => input[i].text.length * 7.2 + 34;
  const h = 32.0;
  for (var pass = 0; pass < 24; pass++) {
    var moved = false;
    for (var i = 0; i < at.length; i++) {
      for (var j = i + 1; j < at.length; j++) {
        final dx = (at[i].dx - at[j].dx).abs();
        final dy = (at[i].dy - at[j].dy).abs();
        final minX = (w(i) + w(j)) / 2;
        if (dx >= minX || dy >= h) continue;
        moved = true;
        // Push apart vertically (the cheaper direction), half each.
        final push = (h - dy) / 2 + 1;
        final up = at[i].dy <= at[j].dy;
        at[i] = at[i].translate(0, up ? -push : push);
        at[j] = at[j].translate(0, up ? push : -push);
      }
    }
    if (!moved) break;
  }
  return [
    for (var i = 0; i < input.length; i++)
      _Callout(
        tooth: input[i].tooth,
        text: input[i].text,
        anchor: input[i].anchor,
        at: Offset(
          at[i].dx.clamp(60.0, size.width - 60),
          at[i].dy.clamp(56.0, size.height - 56),
        ),
        dot: input[i].dot,
        selected: input[i].selected,
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
    // Leader lines from each callout to its tooth.
    for (final c in frame.callouts) {
      final paint = Paint()
        ..color = c.selected ? colors.accent : colors.label3
        ..strokeWidth = 1.2;
      canvas.drawLine(c.anchor, c.at, paint);
      canvas.drawCircle(c.anchor, 3, Paint()..color = c.selected ? colors.accent : colors.surface);
      canvas.drawCircle(
        c.anchor,
        3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = c.selected ? colors.accent : colors.label2,
      );
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => true;
}

/// A callout pill: a dot in the tooth's colour, the number and finding.
class _CalloutChip extends StatelessWidget {
  const _CalloutChip({required this.label, required this.onTap});

  final _Callout label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    const h = 28.0;
    final text = Text(
      label.text,
      maxLines: 1,
      style: CruType.caption.w600.tabular
          .tint(label.selected ? c.onAccent : c.label),
    );
    return Positioned(
      left: label.at.dx,
      top: label.at.dy - h / 2,
      child: FractionalTranslation(
        translation: const Offset(-0.5, 0),
        child: CruPressable(
          onTap: onTap,
          semanticLabel: 'Tooth ${label.text}',
          builder: (context, hovered) => Container(
            height: h,
            padding: const EdgeInsets.fromLTRB(
                CruSpace.s8, 0, CruSpace.s10, 0),
            decoration: ShapeDecoration(
              color: label.selected
                  ? c.accent
                  : hovered
                      ? cruHoverShade(c.surface, c)
                      : c.surface,
              shape: StadiumBorder(side: BorderSide(color: c.hairline)),
              shadows: c.cardShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: ShapeDecoration(
                    color: label.selected ? c.onAccent : label.dot,
                    shape: const CircleBorder(),
                  ),
                ),
                const SizedBox(width: CruSpace.s6),
                text,
              ],
            ),
          ),
        ),
      ),
    );
  }
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
          children: [
            Text(label, style: CruType.subhead.w500.tint(c.label2)),
          ],
        ),
      ),
    );
  }
}
