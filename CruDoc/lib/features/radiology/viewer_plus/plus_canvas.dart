// The dark image stage shared by the ceph and subtraction screens: loading
// a study image, turning it into display pixels through a window, zoom and
// pan, and saving what's on it as a key image or a PNG file.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/imaging/rad_pixels.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Colours of the image stage. Radiographs are read on black whatever the
/// app theme, so lines and text on the stage use the Evening tokens.
abstract final class PlusStage {
  static const Color background = Color(0xFF000000);
  static const CruColors ink = CruColors.evening;

  /// Behind toolbars and text floating on the image.
  static const Color scrim = Color(0xD91C1D20);

  static const List<Shadow> textShadow = [
    Shadow(color: Color(0xE6000000), blurRadius: 3),
  ];
}

// ───────────────────────────── Loading ─────────────────────────────

RadImageRef? plusImageRef(RadStudy s, String imageId) {
  for (final i in s.images) {
    if (i.id == imageId) return i;
  }
  return null;
}

/// The series description, the study type for a single image, or
/// "Image 3".
String plusImageLabel(RadStudy s, String imageId) {
  for (var i = 0; i < s.images.length; i++) {
    final ref = s.images[i];
    if (ref.id != imageId) continue;
    if (ref.seriesDescription.trim().isNotEmpty) return ref.seriesDescription.trim();
    return s.images.length == 1 ? s.modality.label : 'Image ${i + 1}';
  }
  return 'Image';
}

/// Decodes one image of [s] off the UI thread. Throws [RadUnsupportedImage]
/// with a message for the stage when it can't be shown.
Future<RadPixels> plusLoadPixels(RadiologyController rad, RadStudy s, String imageId) async {
  final ref = plusImageRef(s, imageId);
  if (ref == null) throw RadUnsupportedImage('This image is no longer in the study');
  if (ref.compressed) throw RadUnsupportedImage("This image format isn't supported yet");
  return loadRadPixels(await rad.fileOf(s, ref.path), ref.kind);
}

// ───────────────────────────── Display pixels ─────────────────────────────

/// A decoded image shown through a window (centre, width). Grey values are
/// binned once, so a new window is one table lookup per pixel and stays
/// quick while the window is dragged.
class PlusRaster {
  PlusRaster._(this.px, this._levels, this._lo, this._step);

  static const int _levelCount = 4096;

  final RadPixels px;

  /// Bin of every pixel; null for colour pictures (shown from rgba).
  final Uint16List? _levels;
  final double _lo;
  final double _step;

  static Future<PlusRaster> of(RadPixels px) async {
    if (px.isColor) return PlusRaster._(px, null, 0, 1);
    final values = px.values;
    final lo = px.minValue;
    final span = px.maxValue - px.minValue;
    final step = span <= 0 ? 1.0 : span / (_levelCount - 1);
    final levels = await Isolate.run(() => _bin(values, lo, step));
    return PlusRaster._(px, levels, lo, step);
  }

  static Uint16List _bin(Float32List v, double lo, double step) {
    final out = Uint16List(v.length);
    final inv = 1 / step;
    for (var i = 0; i < v.length; i++) {
      final l = ((v[i] - lo) * inv).round();
      out[i] = l < 0 ? 0 : (l >= _levelCount ? _levelCount - 1 : l);
    }
    return out;
  }

  /// The image through a window. [invert] flips it (MONOCHROME1 files are
  /// already shown the right way round).
  Future<ui.Image> render(double center, double width, {bool invert = false}) {
    final w = width <= 0 ? 1e-6 : width;
    final low = center - w / 2;
    final flip = invert != px.invert;
    final n = px.width * px.height;
    final out = Uint32List(n);
    final levels = _levels;
    if (levels != null) {
      final lut = Uint32List(_levelCount);
      for (var i = 0; i < _levelCount; i++) {
        var t = (_lo + i * _step - low) / w;
        t = t < 0 ? 0 : (t > 1 ? 1 : t);
        if (flip) t = 1 - t;
        final g = (t * 255).round();
        lut[i] = 0xFF000000 | (g << 16) | (g << 8) | g;
      }
      for (var i = 0; i < n; i++) {
        out[i] = lut[levels[i]];
      }
    } else {
      final rgba = px.rgba!;
      final lut = Uint8List(256);
      for (var i = 0; i < 256; i++) {
        var t = (i - low) / w;
        t = t < 0 ? 0 : (t > 1 ? 1 : t);
        if (flip) t = 1 - t;
        lut[i] = (t * 255).round();
      }
      final bytes = out.buffer.asUint8List();
      for (var i = 0; i < n * 4; i += 4) {
        bytes[i] = lut[rgba[i]];
        bytes[i + 1] = lut[rgba[i + 1]];
        bytes[i + 2] = lut[rgba[i + 2]];
        bytes[i + 3] = 255;
      }
    }
    return plusDecode(out.buffer.asUint8List(), px.width, px.height);
  }
}

/// RGBA bytes to an image the canvas can draw.
Future<ui.Image> plusDecode(Uint8List rgba, int width, int height) {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, width, height, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// Runs only the newest job: one asked for while another runs replaces
/// any that is waiting (a window drag asks for a render per mouse move).
class PlusLatest {
  Future<void> Function()? _next;
  bool _busy = false;

  void run(Future<void> Function() job) {
    _next = job;
    if (!_busy) unawaited(_pump());
  }

  Future<void> _pump() async {
    _busy = true;
    try {
      while (_next != null) {
        final job = _next!;
        _next = null;
        await job();
      }
    } finally {
      _busy = false;
    }
  }
}

// ───────────────────────────── Zoom and pan ─────────────────────────────

/// Where the image sits on the stage: screen = image × scale + offset.
class PlusView extends ChangeNotifier {
  double scale = 1;
  Offset offset = Offset.zero;
  Size imageSize = Size.zero;
  Size viewport = Size.zero;
  bool _fitted = false;

  Offset toScreen(Offset p) => p * scale + offset;
  Offset toImage(Offset s) => (s - offset) / scale;

  /// A new image: fits it once the stage has a size.
  void setImage(Size size) {
    imageSize = size;
    _fitted = false;
    if (!viewport.isEmpty) fit();
  }

  /// Called on layout (no rebuild): fits the first time, then keeps the
  /// image centred as the stage resizes.
  void setViewport(Size size) {
    if (size == viewport) return;
    final old = viewport;
    viewport = size;
    if (!_fitted) {
      _fit();
    } else if (!old.isEmpty) {
      offset += Offset((size.width - old.width) / 2, (size.height - old.height) / 2);
    }
  }

  void fit() {
    _fit();
    notifyListeners();
  }

  void _fit() {
    if (imageSize.isEmpty || viewport.isEmpty) return;
    const margin = CruSpace.s24;
    scale = math.min(
      (viewport.width - margin * 2) / imageSize.width,
      (viewport.height - margin * 2) / imageSize.height,
    ).clamp(0.01, 40.0);
    offset = Offset(
      (viewport.width - imageSize.width * scale) / 2,
      (viewport.height - imageSize.height * scale) / 2,
    );
    _fitted = true;
  }

  /// Zooms by [factor] keeping the image point under [focal] still.
  void zoomAt(Offset focal, double factor) {
    final p = toImage(focal);
    scale = (scale * factor).clamp(0.02, 40.0);
    offset = focal - p * scale;
    notifyListeners();
  }

  void pan(Offset delta) {
    offset += delta;
    notifyListeners();
  }
}

enum _StageDrag { none, primary, pan, window }

/// The black stage: left press goes to the screen's tool (or pans when the
/// tool doesn't want it), right drag = window/level, middle drag or
/// Space + drag = pan, wheel = zoom at the cursor, double-click = fit.
class PlusCanvas extends StatefulWidget {
  const PlusCanvas({
    super.key,
    required this.view,
    required this.painter,
    this.repaint,
    this.onPrimaryDown,
    this.onPrimaryMove,
    this.onPrimaryUp,
    this.onWindowDrag,
    this.onHover,
    this.cursor = SystemMouseCursors.precise,
    this.focusNode,
    this.overlays = const [],
  });

  final PlusView view;

  /// Paints the stage in screen space; place image points with [view].
  final void Function(Canvas canvas, Size size) painter;
  final Listenable? repaint;

  /// A left press at an image point. Return true to take the drag
  /// ([onPrimaryMove] and [onPrimaryUp] follow); false pans instead.
  final bool Function(Offset imagePoint)? onPrimaryDown;
  final ValueChanged<Offset>? onPrimaryMove;
  final VoidCallback? onPrimaryUp;

  /// Right drag, in screen pixels.
  final ValueChanged<Offset>? onWindowDrag;

  /// The image point under the mouse; null when it leaves the stage.
  final ValueChanged<Offset?>? onHover;
  final MouseCursor cursor;

  /// Takes keyboard focus when the stage is pressed (the screen's keys).
  final FocusNode? focusNode;

  /// Widgets floating on the stage (toolbars, readouts).
  final List<Widget> overlays;

  @override
  State<PlusCanvas> createState() => _PlusCanvasState();
}

class _PlusCanvasState extends State<PlusCanvas> {
  _StageDrag _drag = _StageDrag.none;
  Offset _last = Offset.zero;
  DateTime? _lastClick;
  Offset _lastClickAt = Offset.zero;
  double _pinch = 1;

  void _setDrag(_StageDrag d) {
    if (d == _drag) return;
    final cursorChanges = d == _StageDrag.pan || _drag == _StageDrag.pan;
    _drag = d;
    if (cursorChanges) setState(() {});
  }

  void _down(PointerDownEvent e) {
    widget.focusNode?.requestFocus();
    _last = e.localPosition;
    final b = e.buttons;
    final space =
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.space);
    if (b & kSecondaryMouseButton != 0) {
      _setDrag(widget.onWindowDrag == null ? _StageDrag.pan : _StageDrag.window);
      return;
    }
    if (b & kMiddleMouseButton != 0 || space) {
      _setDrag(_StageDrag.pan);
      return;
    }
    if (b & kPrimaryMouseButton == 0) return;
    final taken = widget.onPrimaryDown?.call(widget.view.toImage(e.localPosition)) ?? false;
    if (taken) {
      _setDrag(_StageDrag.primary);
      return;
    }
    final now = DateTime.now();
    final last = _lastClick;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 320) &&
        (e.localPosition - _lastClickAt).distance < CruSpace.s8) {
      _lastClick = null;
      widget.view.fit();
      _setDrag(_StageDrag.none);
      return;
    }
    _lastClick = now;
    _lastClickAt = e.localPosition;
    _setDrag(_StageDrag.pan);
  }

  void _move(PointerMoveEvent e) {
    final d = e.localPosition - _last;
    _last = e.localPosition;
    switch (_drag) {
      case _StageDrag.pan:
        widget.view.pan(d);
      case _StageDrag.window:
        widget.onWindowDrag?.call(d);
      case _StageDrag.primary:
        widget.onPrimaryMove?.call(widget.view.toImage(e.localPosition));
      case _StageDrag.none:
        break;
    }
    widget.onHover?.call(widget.view.toImage(e.localPosition));
  }

  void _up(PointerEvent e) {
    if (_drag == _StageDrag.primary) widget.onPrimaryUp?.call();
    _setDrag(_StageDrag.none);
  }

  void _signal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final factor = math.pow(1.0015, -e.scrollDelta.dy).toDouble();
      widget.view.zoomAt(e.localPosition, factor);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      widget.view.setViewport(box.biggest);
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        onPointerSignal: _signal,
        onPointerPanZoomStart: (_) => _pinch = 1,
        onPointerPanZoomUpdate: (e) {
          widget.view.pan(e.localPanDelta);
          if (e.scale > 0 && e.scale != _pinch) {
            widget.view.zoomAt(e.localPosition, e.scale / _pinch);
            _pinch = e.scale;
          }
        },
        child: MouseRegion(
          cursor: _drag == _StageDrag.pan ? SystemMouseCursors.grabbing : widget.cursor,
          onHover: (e) => widget.onHover?.call(widget.view.toImage(e.localPosition)),
          onExit: (_) => widget.onHover?.call(null),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: PlusStage.background),
              CustomPaint(
                painter: _StagePainter(
                  widget.painter,
                  Listenable.merge([widget.view, ?widget.repaint]),
                ),
              ),
              ...widget.overlays,
            ],
          ),
        ),
      );
    });
  }
}

class _StagePainter extends CustomPainter {
  _StagePainter(this.fn, Listenable repaint) : super(repaint: repaint);

  final void Function(Canvas canvas, Size size) fn;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    fn(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _StagePainter old) => true;
}

/// Draws [image] where [view] puts the image. Smooth when zoomed out,
/// bilinear when zoomed in.
void plusPaintImage(Canvas canvas, PlusView view, ui.Image image) {
  canvas
    ..save()
    ..translate(view.offset.dx, view.offset.dy)
    ..scale(view.scale)
    ..drawImage(
      image,
      Offset.zero,
      Paint()..filterQuality = view.scale < 1 ? FilterQuality.medium : FilterQuality.low,
    )
    ..restore();
}

/// A millimetre scale bar in the bottom-right corner (1–100 mm, whatever
/// is 60–160 screen pixels long). Nothing when the image isn't calibrated.
void plusPaintScaleBar(Canvas canvas, Size size, PlusView view, double? mmPerPx) {
  if (mmPerPx == null || mmPerPx <= 0) return;
  final pxPerMm = view.scale / mmPerPx;
  double mm = 1;
  for (final step in const [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0]) {
    mm = step;
    if (step * pxPerMm >= 60) break;
  }
  final len = mm * pxPerMm;
  if (len > 160 || len < 20) return;
  const ink = PlusStage.ink;
  final right = size.width - CruSpace.s16;
  final y = size.height - CruSpace.s16;
  final paint = Paint()
    ..color = ink.label
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round;
  canvas
    ..drawLine(Offset(right - len, y), Offset(right, y), paint)
    ..drawLine(Offset(right - len, y - 5), Offset(right - len, y), paint)
    ..drawLine(Offset(right, y - 5), Offset(right, y), paint);
  final tp = TextPainter(
    text: TextSpan(
      text: '${mm.toStringAsFixed(0)} mm',
      style: CruType.micro.tabular.copyWith(color: ink.label, shadows: PlusStage.textShadow),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, Offset(right - len / 2 - tp.width / 2, y - 8 - tp.height));
}

// ───────────────────────────── Saving pictures ─────────────────────────────

/// Draws [paint] into a [width] × [height] PNG.
Future<Uint8List> plusRenderPng(int width, int height, void Function(Canvas canvas) paint) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
  paint(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

/// Writes [png] into the study folder (`keys/<id>.png`) and returns the
/// key image record; the caller adds it to the study.
Future<RadKeyImage> plusWriteKeyImage(
  RadiologyController rad,
  RadStudy s, {
  required String imageId,
  required Uint8List png,
  required String caption,
}) async {
  final id = radId('key_');
  final rel = 'keys/$id.png';
  final file = await rad.fileOf(s, rel);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(png, flush: true);
  return RadKeyImage(
    id: id,
    imageId: imageId,
    pngPath: rel,
    caption: caption,
    createdAt: DateTime.now(),
  );
}

/// Asks where to save [png] and writes it. Returns the path, or null when
/// the doctor cancels.
Future<String?> plusSavePngAs(Uint8List png, String suggestedName) async {
  final path = await FilePicker.saveFile(
    dialogTitle: 'Save picture',
    fileName: suggestedName,
    type: FileType.custom,
    allowedExtensions: const ['png'],
  );
  if (path == null) return null;
  final out = path.toLowerCase().endsWith('.png') ? path : '$path.png';
  await File(out).writeAsBytes(png, flush: true);
  return out;
}

/// "Asha Patil ceph tracing 12 Sep 2026.png" without characters Windows
/// refuses in file names.
String plusFileName(RadStudy s, String what) {
  final d = s.studyDate;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final name = '${s.patientName} $what ${d.day} ${months[d.month - 1]} ${d.year}.png';
  return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').replaceAll(RegExp(r'\s+'), ' ').trim();
}
