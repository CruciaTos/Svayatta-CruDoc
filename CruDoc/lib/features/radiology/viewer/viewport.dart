import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:doctor_management_app/features/radiology/ai/rad_ai.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/viewer/annotation_painter.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_icons.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_pane.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_prefs.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// What the viewer screen does for its viewports: selection, saving
/// annotations, linking panes and loading dropped images.
abstract interface class RadViewportHost {
  RadViewerPrefs get prefs;
  RadRoiCache get roi;

  /// Makes [pane] the active one and takes keyboard focus.
  void activatePane(RadPane pane);
  void select(String? id);

  /// A finished drawing: saves it (after asking for a note, tooth or
  /// calibration length where the tool needs one).
  Future<void> commitDraft(RadPane pane, RadAnnotation draft, RadTool tool);

  /// Moving an annotation: [beginEdit] once, [updateAnnotation] on every
  /// move, [endEdit] when the pointer lifts (one undo step).
  void beginEdit();
  void updateAnnotation(RadPane pane, RadAnnotation a);
  void endEdit();

  /// The doctor zoomed or panned [pane] (linked panes follow).
  void viewChanged(RadPane pane);
  void dropImage(RadPane pane, RadImageDrag drag);

  /// Wheel scrolling: next / previous slice or frame, else image.
  void step(RadPane pane, int delta);

  /// Shows slice (of a stack) or frame (of a multi-frame file) [index].
  void setFrame(RadPane pane, int index);

  /// Upgrades [imageId] to full quality.
  void upgradeToFull(String imageId);
}

enum _Drag { none, pan, zoom, window, draw, angleArm, freehand, edit, pinch }

/// One dark image pane: the image through its window, annotations,
/// corner read-outs, the loupe and the frame slider. Left-drag uses the
/// active tool; right and middle drags follow the mouse preferences;
/// the wheel zooms at the cursor; double-click fits. On a touch screen one
/// finger uses the tool and two fingers pinch to zoom and drag to move,
/// whatever the tool.
class RadViewport extends StatefulWidget {
  const RadViewport({
    super.key,
    required this.pane,
    required this.host,
    required this.tool,
    required this.annotations,
    required this.selectedId,
    required this.mmPerPx,
    required this.canAnnotate,
    required this.active,
    required this.showActive,
    required this.loupe,
    required this.title,
    this.aiFindings = const [],
    this.showAiMarks = true,
  });

  final RadPane pane;
  final RadViewportHost host;
  final RadTool tool;
  final List<RadAnnotation> annotations;
  final String? selectedId;
  final double? mmPerPx;

  /// False for an earlier study shown for comparison (read only).
  final bool canAnnotate;
  final bool active;

  /// Outline the active pane (only when there are several).
  final bool showActive;
  final bool loupe;

  /// Top-left caption ("OPG · 1 of 3", "Earlier · 12 Mar 2025").
  final String title;
  final List<RadAiFinding> aiFindings;
  final bool showAiMarks;

  @override
  State<RadViewport> createState() => _RadViewportState();
}

class _RadViewportState extends State<RadViewport> {
  _Drag _drag = _Drag.none;
  Offset _downPos = Offset.zero;
  Offset _lastPos = Offset.zero;
  bool _moved = false;
  Duration? _lastClick;
  Offset _lastClickPos = Offset.zero;
  double _panZoomScale = 1;
  double _wheelAcc = 0;

  // Touch: fingers on the screen, and the pinch they make.
  final Map<int, Offset> _touches = {};
  Offset _pinchFocal = Offset.zero;
  double _pinchDist = 0;

  /// The draft before the first finger touched, so a pinch can take back
  /// what that finger started drawing.
  RadAnnotation? _draftBeforeTouch;

  /// After a pinch the finger still down does nothing until it lifts, so
  /// lifting one finger first doesn't start a drawing.
  bool _ignoreUntilUp = false;

  // Editing an existing annotation.
  RadAnnotation? _editOrig;
  int _editHandle = -1;
  Offset _editStart = Offset.zero;

  RadPane get pane => widget.pane;

  RadAnnotation? get _selected {
    final id = widget.selectedId;
    if (id == null) return null;
    for (final a in widget.annotations) {
      if (a.id == id) return a;
    }
    return null;
  }

  RadPoint _imagePoint(Offset s) {
    final i = pane.toImage(s);
    return RadPoint(i.dx, i.dy);
  }

  void _startDrag(RadDragAction a) {
    _drag = switch (a) {
      RadDragAction.pan => _Drag.pan,
      RadDragAction.zoom => _Drag.zoom,
      RadDragAction.window => _Drag.window,
    };
    setState(() {});
  }

  // ───────────────────────────── Pointer ─────────────────────────────

  void _down(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.touch) {
      _touches[e.pointer] = e.localPosition;
      if (_touches.length == 2) return _startPinch();
      if (_touches.length > 2 || _ignoreUntilUp) return;
      _draftBeforeTouch = pane.draft;
    }
    widget.host.activatePane(pane);
    final pos = e.localPosition;
    pane.cursor = pos;
    if (!pane.hasImage) return;
    _downPos = _lastPos = pos;
    _moved = false;

    final prefs = widget.host.prefs;
    if (e.buttons & kSecondaryMouseButton != 0) return _startDrag(prefs.right);
    if (e.buttons & kMiddleMouseButton != 0) return _startDrag(prefs.middle);
    if (e.buttons & kPrimaryMouseButton == 0) return;

    final isDouble =
        _lastClick != null &&
        e.timeStamp - _lastClick! < const Duration(milliseconds: 350) &&
        (pos - _lastClickPos).distance < 6;
    _lastClick = isDouble ? null : e.timeStamp;
    _lastClickPos = pos;

    final draft = pane.draft;
    if (isDouble) {
      if (draft != null &&
          (draft.kind == RadAnnoKind.polygon ||
              draft.kind == RadAnnoKind.polyline)) {
        _finishPath(draft);
        return;
      }
      if (draft == null) {
        pane.fit();
        widget.host.viewChanged(pane);
        return;
      }
    }

    if (HardwareKeyboard.instance.logicalKeysPressed.contains(
      LogicalKeyboardKey.space,
    )) {
      return _startDrag(RadDragAction.pan);
    }

    // The selected annotation's handles can be dragged with any tool.
    final sel = _selected;
    if (widget.canAnnotate && sel != null && draft == null) {
      final h = radHitHandle(sel, pos, pane.pointToScreen);
      if (h != null) return _beginEdit(sel, h, pos);
    }

    switch (widget.tool) {
      case RadTool.select:
        final hit = widget.canAnnotate
            ? radHitAnnotation(widget.annotations, pos, pane.pointToScreen)
            : null;
        if (hit != null) {
          widget.host.select(hit.id);
          _beginEdit(hit, -1, pos);
        } else {
          widget.host.select(null);
          _startDrag(RadDragAction.pan);
        }
      case RadTool.pan:
        _startDrag(RadDragAction.pan);
      case RadTool.zoom:
        _startDrag(RadDragAction.zoom);
      case RadTool.window:
        _startDrag(RadDragAction.window);
      default:
        if (!widget.canAnnotate) return _startDrag(RadDragAction.pan);
        _drawDown(pos);
    }
  }

  void _beginEdit(RadAnnotation a, int handle, Offset pos) {
    widget.host.beginEdit();
    _editOrig = a;
    _editHandle = handle;
    _editStart = pane.toImage(pos);
    _drag = _Drag.edit;
  }

  void _drawDown(Offset pos) {
    final kind = widget.tool.kind!;
    final pt = _imagePoint(pos);
    final d = pane.draft;
    RadAnnotation fresh(List<RadPoint> pts) =>
        RadAnnotation(id: radId('ann_'), kind: kind, points: pts);

    switch (kind) {
      case RadAnnoKind.length:
      case RadAnnoKind.rect:
      case RadAnnoKind.ellipse:
      case RadAnnoKind.arrow:
        pane.draft = fresh([pt, pt]);
        _drag = _Drag.draw;
      case RadAnnoKind.angle:
        if (d == null) {
          pane.draft = fresh([pt, pt]);
          _drag = _Drag.angleArm;
        } else if ((pane.pointToScreen(d.points.last) - pos).distance >= 3) {
          final next = d.copyWith(points: [...d.points, pt]);
          if (next.points.length >= 3) {
            pane.draft = null;
            pane.draftHover = null;
            widget.host.commitDraft(pane, next, widget.tool);
          } else {
            pane.draft = next;
          }
        }
      case RadAnnoKind.polygon:
      case RadAnnoKind.polyline:
        if (d == null) {
          pane.draft = fresh([pt]);
        } else if (kind == RadAnnoKind.polygon &&
            d.points.length >= 3 &&
            (pane.pointToScreen(d.points.first) - pos).distance < 10) {
          _finishPath(d);
          return;
        } else if ((pane.pointToScreen(d.points.last) - pos).distance >= 3) {
          pane.draft = d.copyWith(points: [...d.points, pt]);
        }
      case RadAnnoKind.freehand:
        pane.draft = fresh([pt]);
        _drag = _Drag.freehand;
      case RadAnnoKind.text:
      case RadAnnoKind.toothLabel:
        widget.host.commitDraft(pane, fresh([pt]), widget.tool);
    }
    pane.touch();
  }

  void _finishPath(RadAnnotation d) {
    final min = d.kind == RadAnnoKind.polygon ? 3 : 2;
    pane.draft = null;
    pane.draftHover = null;
    pane.touch();
    if (d.points.length >= min) widget.host.commitDraft(pane, d, widget.tool);
  }

  void _move(PointerMoveEvent e) {
    if (e.kind == PointerDeviceKind.touch) {
      if (_touches.containsKey(e.pointer)) {
        _touches[e.pointer] = e.localPosition;
      }
      if (_drag == _Drag.pinch) return _pinchUpdate();
      if (_ignoreUntilUp) return;
    }
    final pos = e.localPosition;
    final delta = pos - _lastPos;
    _lastPos = pos;
    pane.cursor = pos;
    if ((pos - _downPos).distance > 3) _moved = true;
    final d = pane.draft;
    switch (_drag) {
      case _Drag.none:
        pane.touch();
      case _Drag.pinch:
        // Handled above; a pinch never reaches the tools.
        break;
      case _Drag.pan:
        pane.pan += delta;
        pane.touch();
        widget.host.viewChanged(pane);
      case _Drag.zoom:
        pane.zoomAt(_downPos, math.exp(-delta.dy / 150));
        widget.host.viewChanged(pane);
      case _Drag.window:
        final px = pane.px;
        if (px == null) return;
        final range = math.max((px.highPct - px.lowPct).abs(), 1e-3);
        // Right = more contrast (narrower window); up = brighter.
        pane.setWindow(
          pane.center + delta.dy * range / 400,
          pane.width * math.exp(-delta.dx / 250),
          interactive: true,
        );
      case _Drag.draw:
      case _Drag.angleArm:
        if (d != null) {
          pane.draft = d.copyWith(points: [d.points.first, _imagePoint(pos)]);
          pane.touch();
        }
      case _Drag.freehand:
        if (d != null &&
            (pane.pointToScreen(d.points.last) - pos).distance >= 2) {
          pane.draft = d.copyWith(points: [...d.points, _imagePoint(pos)]);
          pane.touch();
        }
      case _Drag.edit:
        final orig = _editOrig;
        if (orig == null) return;
        final now = pane.toImage(pos);
        final RadAnnotation next;
        if (_editHandle >= 0) {
          next = orig.copyWith(
            points: [
              for (var i = 0; i < orig.points.length; i++)
                i == _editHandle ? RadPoint(now.dx, now.dy) : orig.points[i],
            ],
          );
        } else {
          final dd = now - _editStart;
          next = orig.copyWith(
            points: [
              for (final p in orig.points) RadPoint(p.x + dd.dx, p.y + dd.dy),
            ],
          );
        }
        widget.host.updateAnnotation(pane, next);
    }
  }

  void _up(PointerUpEvent e) {
    if (e.kind == PointerDeviceKind.touch && _touchUp(e.pointer)) return;
    final d = pane.draft;
    switch (_drag) {
      case _Drag.draw:
        pane.draft = null;
        pane.touch();
        if (_moved && d != null) widget.host.commitDraft(pane, d, widget.tool);
      case _Drag.angleArm:
        if (d != null && !_moved) {
          pane.draft = d.copyWith(points: [d.points.first]);
        }
        pane.draftHover = e.localPosition;
        pane.touch();
      case _Drag.freehand:
        pane.draft = null;
        pane.touch();
        if (d != null && d.points.length >= 2) {
          widget.host.commitDraft(pane, d, widget.tool);
        }
      case _Drag.edit:
        _editOrig = null;
        widget.host.endEdit();
      case _Drag.window:
        pane.requestRender(progressive: true);
      default:
        break;
    }
    if (_drag != _Drag.none) setState(() => _drag = _Drag.none);
    if (e.kind == PointerDeviceKind.touch) {
      // No finger, no loupe.
      pane.cursor = null;
      pane.touch();
    }
  }

  // ───────────────────────────── Touch ─────────────────────────────

  /// A second finger: undo what the first one started, then pinch.
  void _startPinch() {
    switch (_drag) {
      case _Drag.draw:
      case _Drag.angleArm:
      case _Drag.freehand:
        pane.draft = _draftBeforeTouch;
        pane.draftHover = null;
      case _Drag.edit:
        _editOrig = null;
        widget.host.endEdit();
      case _Drag.window:
        pane.requestRender(progressive: true);
      default:
        // A tap that added a point to an area or path: take it back.
        if (widget.tool.draws) pane.draft = _draftBeforeTouch;
    }
    final pts = _touches.values.take(2).toList();
    _pinchFocal = (pts[0] + pts[1]) / 2;
    _pinchDist = (pts[0] - pts[1]).distance;
    _lastClick = null;
    pane.cursor = null;
    pane.touch();
    setState(() => _drag = _Drag.pinch);
  }

  void _pinchUpdate() {
    if (!pane.hasImage || _touches.length < 2) return;
    final pts = _touches.values.take(2).toList();
    final focal = (pts[0] + pts[1]) / 2;
    final dist = (pts[0] - pts[1]).distance;
    pane.pan += focal - _pinchFocal;
    if (_pinchDist > 0 && dist > 0) pane.zoomAt(focal, dist / _pinchDist);
    _pinchFocal = focal;
    _pinchDist = dist;
    pane.touch();
    widget.host.viewChanged(pane);
  }

  /// A finger lifted. True when it was part of a pinch (or its tail) and
  /// so shouldn't finish a tool action.
  bool _touchUp(int pointer) {
    _touches.remove(pointer);
    if (_drag == _Drag.pinch) {
      if (_touches.length < 2) {
        _ignoreUntilUp = _touches.isNotEmpty;
        setState(() => _drag = _Drag.none);
      }
      return true;
    }
    if (_ignoreUntilUp) {
      if (_touches.isEmpty) _ignoreUntilUp = false;
      return true;
    }
    return false;
  }

  void _hover(PointerHoverEvent e) {
    pane.cursor = e.localPosition;
    final d = pane.draft;
    if (d != null &&
        (d.kind == RadAnnoKind.angle ||
            d.kind == RadAnnoKind.polygon ||
            d.kind == RadAnnoKind.polyline)) {
      pane.draftHover = e.localPosition;
    }
    pane.touch();
  }

  void _signal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
      final s = ev as PointerScrollEvent;
      if (!pane.hasImage) return;
      var action = widget.host.prefs.wheel;
      if (HardwareKeyboard.instance.isControlPressed) {
        action = action == RadWheelAction.zoom
            ? RadWheelAction.scroll
            : RadWheelAction.zoom;
      }
      if (action == RadWheelAction.zoom) {
        pane.zoomAt(s.localPosition, math.exp(-s.scrollDelta.dy / 300));
        widget.host.viewChanged(pane);
      } else {
        _wheelAcc += s.scrollDelta.dy;
        if (_wheelAcc.abs() >= 40) {
          widget.host.step(pane, _wheelAcc > 0 ? 1 : -1);
          _wheelAcc = 0;
        }
      }
    });
  }

  MouseCursor get _cursor {
    if (!pane.hasImage) return SystemMouseCursors.basic;
    return switch (_drag) {
      _Drag.pan => SystemMouseCursors.grabbing,
      _Drag.zoom => SystemMouseCursors.zoomIn,
      _Drag.window => SystemMouseCursors.allScroll,
      _Drag.edit => SystemMouseCursors.move,
      _ => switch (widget.tool) {
        RadTool.select => SystemMouseCursors.basic,
        RadTool.pan => SystemMouseCursors.grab,
        RadTool.zoom => SystemMouseCursors.zoomIn,
        RadTool.window => SystemMouseCursors.allScroll,
        _ =>
          widget.canAnnotate
              ? SystemMouseCursors.precise
              : SystemMouseCursors.grab,
      },
    };
  }

  // ───────────────────────────── Build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return DragTarget<RadImageDrag>(
      onAcceptWithDetails: (d) => widget.host.dropImage(pane, d.data),
      builder: (context, candidates, _) => LayoutBuilder(
        builder: (context, box) {
          pane.viewport = box.biggest;
          return MouseRegion(
            cursor: _cursor,
            onExit: (_) {
              pane.cursor = null;
              pane.touch();
            },
            child: Listener(
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: (e) {
                _touches.remove(e.pointer);
                if (_touches.isEmpty) _ignoreUntilUp = false;
                setState(() => _drag = _Drag.none);
              },
              onPointerHover: _hover,
              onPointerSignal: _signal,
              onPointerPanZoomStart: (_) => _panZoomScale = 1,
              onPointerPanZoomUpdate: (e) {
                if (!pane.hasImage) return;
                pane.pan += e.panDelta;
                pane.zoomAt(e.localPosition, e.scale / _panZoomScale);
                _panZoomScale = e.scale;
                widget.host.viewChanged(pane);
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _ImagePainter(pane, loupe: widget.loupe),
                    ),
                  ),
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _OverlayPainter(
                        pane,
                        annotations: widget.annotations,
                        selectedId: widget.selectedId,
                        mmPerPx: widget.mmPerPx,
                        roi: widget.host.roi,
                        calibrating: widget.tool == RadTool.calibrate,
                        aiFindings: widget.aiFindings,
                        showAiMarks: widget.showAiMarks,
                      ),
                    ),
                  ),
                  _Corners(pane: pane, title: widget.title, host: widget.host),
                  if (candidates.isNotEmpty ||
                      (widget.active && widget.showActive))
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: candidates.isNotEmpty
                                ? RadInk.overlay
                                : c.accent,
                            width: candidates.isNotEmpty ? 2 : 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ───────────────────────────── Painters ─────────────────────────────

class _ImagePainter extends CustomPainter {
  _ImagePainter(this.pane, {required this.loupe}) : super(repaint: pane);

  final RadPane pane;
  final bool loupe;

  static const _loupeRadius = 90.0;
  static const _loupeZoom = 3.0;

  void _drawImage(Canvas canvas) {
    final img = pane.image ?? pane.placeholder;
    if (img == null) return;
    final w =
        (pane.px?.width ??
                (pane.nominalWidth > 0 ? pane.nominalWidth : img.width))
            .toDouble();
    final h =
        (pane.px?.height ??
                (pane.nominalHeight > 0 ? pane.nominalHeight : img.height))
            .toDouble();
    if (w <= 0 || h <= 0) return;
    canvas.save();
    pane.applyTransform(canvas);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..filterQuality = pane.zoom >= 2.5
            ? FilterQuality.none
            : FilterQuality.medium,
    );
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = RadInk.viewport);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _drawImage(canvas);
    final at = pane.cursor;
    if (loupe && at != null && pane.image != null) {
      final circle = Rect.fromCircle(center: at, radius: _loupeRadius);
      canvas.save();
      canvas.clipPath(Path()..addOval(circle));
      canvas.drawRect(circle, Paint()..color = RadInk.viewport);
      canvas
        ..translate(at.dx, at.dy)
        ..scale(_loupeZoom)
        ..translate(-at.dx, -at.dy);
      _drawImage(canvas);
      canvas.restore();
      canvas.drawCircle(
        at,
        _loupeRadius,
        Paint()
          ..color = RadInk.loupeRing
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ImagePainter old) =>
      old.pane != pane || old.loupe != loupe;
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(
    this.pane, {
    required this.annotations,
    required this.selectedId,
    required this.mmPerPx,
    required this.roi,
    required this.calibrating,
    this.aiFindings = const [],
    this.showAiMarks = true,
  }) : super(repaint: pane);

  final RadPane pane;
  final List<RadAnnotation> annotations;
  final String? selectedId;
  final double? mmPerPx;
  final RadRoiCache roi;
  final bool calibrating;
  final List<RadAiFinding> aiFindings;
  final bool showAiMarks;

  @override
  void paint(Canvas canvas, Size size) {
    if (!pane.hasImage) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final painter = RadAnnotationPainter(
      toScreen: pane.pointToScreen,
      mmPerPx: mmPerPx,
      roi: roi,
      px: pane.px,
    );
    painter.paintAll(canvas, annotations, selectedId: selectedId);
    final d = pane.draft;
    if (d != null) {
      final rubber =
          d.kind == RadAnnoKind.angle ||
          d.kind == RadAnnoKind.polygon ||
          d.kind == RadAnnoKind.polyline;
      painter.paint(
        canvas,
        d,
        draft: true,
        hover: rubber ? pane.draftHover : null,
        color: calibrating ? RadInk.calibrate : null,
      );
    }
    if (showAiMarks && aiFindings.isNotEmpty && pane.px != null) {
      _paintAiFindings(canvas, size);
    }
    final mm = mmPerPx;
    if (mm != null && pane.zoom > 0)
      radPaintScaleBar(canvas, size, mm / pane.zoom);
    canvas.restore();
  }

  void _paintAiFindings(Canvas canvas, Size size) {
    final px = pane.px;
    if (px == null) return;
    canvas.save();
    pane.applyTransform(canvas);
    final strokeWidth = 2.0 / (pane.zoom > 0 ? pane.zoom : 1.0);
    const aiColor = Color(0xFF8B5CF6);

    for (final f in aiFindings) {
      if (f.status == 'rejected' || f.box == null) continue;
      final b = f.box!;
      final rect = Rect.fromLTRB(
        b.left * px.width,
        b.top * px.height,
        b.right * px.width,
        b.bottom * px.height,
      );

      final paint = Paint()
        ..color = aiColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;

      if (f.status == 'accepted') {
        canvas.drawRect(rect, paint);
      } else {
        _drawDashedRect(
          canvas,
          rect,
          paint,
          6.0 / (pane.zoom > 0 ? pane.zoom : 1.0),
          4.0 / (pane.zoom > 0 ? pane.zoom : 1.0),
        );
      }
    }
    canvas.restore();
  }

  void _drawDashedRect(
    Canvas canvas,
    Rect rect,
    Paint paint,
    double dashWidth,
    double dashSpace,
  ) {
    void drawLine(Offset p1, Offset p2) {
      final dx = p2.dx - p1.dx;
      final dy = p2.dy - p1.dy;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance == 0) return;
      final u = Offset(dx / distance, dy / distance);
      var d = 0.0;
      while (d < distance) {
        final start = p1 + u * d;
        final end = p1 + u * math.min(d + dashWidth, distance);
        canvas.drawLine(start, end, paint);
        d += dashWidth + dashSpace;
      }
    }

    drawLine(rect.topLeft, rect.topRight);
    drawLine(rect.topRight, rect.bottomRight);
    drawLine(rect.bottomRight, rect.bottomLeft);
    drawLine(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.pane != pane ||
      old.annotations != annotations ||
      old.selectedId != selectedId ||
      old.mmPerPx != mmPerPx ||
      old.calibrating != calibrating ||
      old.aiFindings != aiFindings ||
      old.showAiMarks != showAiMarks;
}

// ───────────────────────────── Corners ─────────────────────────────

class _Corners extends StatelessWidget {
  const _Corners({required this.pane, required this.title, required this.host});

  final RadPane pane;
  final String title;
  final RadViewportHost host;

  static String _num(double v, double range) =>
      range < 20 ? v.toStringAsFixed(2) : v.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final style = CruType.micro.tabular.copyWith(
      color: RadInk.overlay,
      shadows: const [],
    );
    return ListenableBuilder(
      listenable: pane,
      builder: (context, _) {
        final px = pane.px;
        if (pane.imageId.isEmpty) {
          return Center(
            child: Text(
              'Drag an image here',
              style: CruType.subhead.tint(RadInk.overlayQuiet),
            ),
          );
        }
        if (pane.loading && px == null && pane.placeholder == null) {
          return Center(
            child: Text(
              'Opening image…',
              style: CruType.subhead.tint(RadInk.overlayQuiet),
            ),
          );
        }
        final error = pane.error;
        if (error != null) {
          final unsupported = error.toLowerCase().contains('not supported');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(CruSpace.s24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CruIcon(
                    RadIcons.unlink,
                    size: 22,
                    color: RadInk.overlayQuiet,
                  ),
                  const SizedBox(height: CruSpace.s10),
                  Text(
                    unsupported
                        ? "This image format isn't supported yet"
                        : error,
                    textAlign: TextAlign.center,
                    style: CruType.callout.tint(RadInk.overlay),
                  ),
                  if (unsupported) ...[
                    const SizedBox(height: CruSpace.s4),
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      style: CruType.caption.tint(RadInk.overlayQuiet),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        if (px == null) return const SizedBox.shrink();
        final range = (px.maxValue - px.minValue).abs();
        final probe = pane.cursor == null ? null : pane.probe(pane.cursor!);
        final rgb = probe?.rgb;
        final valueText = probe == null
            ? null
            : rgb != null
            ? 'x ${probe.x} · y ${probe.y} · RGB ${rgb[0]} ${rgb[1]} ${rgb[2]}'
            : 'x ${probe.x} · y ${probe.y} · ${_num(probe.value, range)}';
        return Stack(
          children: [
            Positioned(
              left: CruSpace.s12,
              top: CruSpace.s10,
              right: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: style,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (px.isPreview) ...[
                    const SizedBox(height: CruSpace.s6),
                    _PreviewPill(
                      upgrading: pane.upgrading,
                      onUpgrade: () => host.upgradeToFull(pane.imageId),
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              right: CruSpace.s12,
              top: CruSpace.s10,
              child: Text(
                'W ${_num(pane.width, range)} · L ${_num(pane.center, range)}'
                '${pane.invert ? ' · Inverted' : ''}',
                style: style,
              ),
            ),
            Positioned(
              left: CruSpace.s12,
              bottom: CruSpace.s10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (valueText != null) Text(valueText, style: style),
                  Text('Zoom ${(pane.zoom * 100).round()}%', style: style),
                ],
              ),
            ),
            if (pane.sliceCount > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: CruSpace.s10,
                child: Center(
                  child: _FrameSlider(pane: pane, host: host),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Frame slider for multi-frame 2D files.
class _FrameSlider extends StatelessWidget {
  const _FrameSlider({required this.pane, required this.host});

  final RadPane pane;
  final RadViewportHost host;

  @override
  Widget build(BuildContext context) {
    final n = pane.sliceCount;
    final i = pane.sliceIndex;
    return Container(
      width: 320,
      height: CruSize.chip,
      padding: const EdgeInsets.only(left: CruSpace.s12),
      decoration: const ShapeDecoration(
        color: RadInk.overlayFill,
        shape: StadiumBorder(),
      ),
      child: Row(
        children: [
          const CruIcon(
            RadViewerIcons.frames,
            size: 14,
            strokeWidth: 2,
            color: RadInk.overlay,
          ),
          const SizedBox(width: CruSpace.s6),
          Text(
            '${pane.stack != null ? 'Slice' : 'Frame'} ${i + 1} / $n',
            style: CruType.micro.tabular.tint(RadInk.overlay),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                activeTrackColor: RadInk.overlay,
                inactiveTrackColor: RadInk.overlayQuiet,
                thumbColor: RadInk.overlay,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: i.toDouble().clamp(0.0, (n - 1).toDouble()),
                min: 0,
                max: (n - 1).toDouble(),
                divisions: n > 1 ? n - 1 : null,
                onChanged: (v) => host.setFrame(pane, v.round()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewPill extends StatelessWidget {
  const _PreviewPill({required this.upgrading, required this.onUpgrade});

  final bool upgrading;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      height: CruSize.pill,
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s10),
      decoration: const ShapeDecoration(
        color: RadInk.overlayFill,
        shape: StadiumBorder(side: BorderSide(color: RadInk.overlayBorder)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Preview',
            style: CruType.caption.w600.tabular.copyWith(color: RadInk.overlay),
          ),
          const SizedBox(width: CruSpace.s8),
          if (upgrading)
            const SizedBox(
              width: CruSpace.s12,
              height: CruSpace.s12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(RadInk.overlay),
              ),
            )
          else
            CruPressable(
              onTap: onUpgrade,
              semanticLabel: 'Full quality',
              builder: (context, hovered) => Text(
                'Full quality',
                style: CruType.caption.w600.copyWith(
                  color: hovered ? c.accentText : c.accent,
                  decoration: hovered
                      ? TextDecoration.underline
                      : TextDecoration.none,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
