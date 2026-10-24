import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Holds the strokes of a [SignaturePad].
class SignatureController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];
  Size _size = const Size(560, 160);

  bool get isEmpty => _strokes.every((s) => s.length < 2);

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  void _start(Offset p) {
    _strokes.add([p]);
    notifyListeners();
  }

  void _add(Offset p) {
    if (_strokes.isEmpty) return;
    _strokes.last.add(p);
    notifyListeners();
  }

  /// The signature as a transparent PNG at twice the pad's size.
  Future<Uint8List?> toPng() async {
    if (isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(2);
    _paint(canvas, const Color(0xFF111111));
    final image = await recorder.endRecording().toImage(
      (_size.width * 2).round(),
      (_size.height * 2).round(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  void _paint(Canvas canvas, Color color) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in _strokes) {
      if (s.length < 2) continue;
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final pt in s.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, p);
    }
  }
}

/// Sign with a mouse, pen or finger.
class SignaturePad extends StatelessWidget {
  const SignaturePad({super.key, required this.controller, this.height = 160});

  final SignatureController controller;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return LayoutBuilder(
      builder: (context, box) {
        controller._size = Size(box.maxWidth, height);
        return Container(
          height: height,
          decoration: ShapeDecoration(
            color: c.surface,
            shape: cruShape(
              CruRadius.control,
              side: BorderSide(color: c.hairline),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(CruRadius.control),
            // A RawGestureDetector with a greedy pan recognizer: on a phone or
            // tablet the finger must draw on the pad, not scroll the dialog it
            // sits inside, so the pad has to win the gesture arena outright.
            child: RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: <Type, GestureRecognizerFactory>{
                _SignPanRecognizer:
                    GestureRecognizerFactoryWithHandlers<_SignPanRecognizer>(
                      () => _SignPanRecognizer(),
                      (r) {
                        r.onStart = (d) => controller._start(d.localPosition);
                        r.onUpdate = (d) => controller._add(d.localPosition);
                      },
                    ),
              },
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => CustomPaint(
                  size: Size(box.maxWidth, height),
                  painter: _PadPainter(controller, c.label),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A pan recognizer that refuses to lose the gesture arena: inside the
/// consent dialog's scroll view a plain [GestureDetector] hands vertical
/// finger-drags to the scrollable, so nothing is drawn. Accepting on reject
/// keeps every stroke on the pad, on touch as well as with a mouse.
class _SignPanRecognizer extends PanGestureRecognizer {
  @override
  void rejectGesture(int pointer) => acceptGesture(pointer);
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.controller, this.color) : super(repaint: controller);

  final SignatureController controller;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => controller._paint(canvas, color);

  @override
  bool shouldRepaint(_PadPainter old) => true;
}
