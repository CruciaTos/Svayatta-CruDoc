import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'package:doctor_management_app/features/radiology/viewer_plus/ceph/ceph_analysis.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/plus_canvas.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Draws a ceph tracing: reference planes, the analysis's lines (dashed),
/// the soft-tissue profile and the landmarks. [toScreen] maps image
/// points; [unit] scales strokes and text (1 on screen, larger for a
/// full-size export). [current] is the landmark being placed ("now").
void paintCephTracing(
  Canvas canvas, {
  required Map<String, Offset> points,
  required String analysis,
  required Offset Function(Offset p) toScreen,
  double unit = 1,
  String? current,
  String? hover,
  bool planes = true,
  bool labels = true,
}) {
  const ink = PlusStage.ink;
  if (planes) {
    final plane = Paint()
      ..color = ink.label2.withValues(alpha: 0.85)
      ..strokeWidth = 1.2 * unit
      ..strokeCap = StrokeCap.round;
    final own = Paint()
      ..color = ink.label.withValues(alpha: 0.8)
      ..strokeWidth = 1.2 * unit
      ..strokeCap = StrokeCap.round;
    for (final l in cephLines(analysis, points)) {
      final a = toScreen(l.a), b = toScreen(l.b);
      final d = b - a;
      if (d.distance < 1) continue;
      // Extend past the landmarks so the plane reads as a line.
      final ext = l.label == 'U1' || l.label == 'L1' ? 0.35 : 0.12;
      final from = a - d * ext, to = b + d * ext;
      if (l.analysis) {
        _dashed(canvas, from, to, own, 6 * unit, 4 * unit);
      } else {
        canvas.drawLine(from, to, plane);
      }
      if (labels) {
        final u = d / d.distance;
        _text(canvas, l.label, to + u * 6 * unit, unit,
            color: l.analysis ? ink.label : ink.label2, centred: true);
      }
    }
    final profile = cephProfile(points);
    if (profile.length > 1) {
      final path = Path()..moveTo(toScreen(profile.first).dx, toScreen(profile.first).dy);
      for (final p in profile.skip(1)) {
        final s = toScreen(p);
        path.lineTo(s.dx, s.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = ink.label3
          ..strokeWidth = 1.2 * unit
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  final dotFill = Paint()..color = ink.label;
  final dotRing = Paint()
    ..style = PaintingStyle.stroke
    ..color = PlusStage.background
    ..strokeWidth = 1.5 * unit;
  final now = Paint()
    ..style = PaintingStyle.stroke
    ..color = ink.accentText
    ..strokeWidth = 2 * unit;
  for (final e in points.entries) {
    final s = toScreen(e.value);
    final isNow = e.key == current;
    final isHover = e.key == hover;
    canvas
      ..drawCircle(s, 3.5 * unit, isHover ? (Paint()..color = ink.accentText) : dotFill)
      ..drawCircle(s, 3.5 * unit, dotRing);
    if (isNow) canvas.drawCircle(s, 9 * unit, now);
    if (labels || isNow || isHover) {
      _text(canvas, e.key, s + Offset(7 * unit, -15 * unit), unit,
          color: isNow || isHover ? ink.accentText : ink.label);
    }
  }
}

void _dashed(Canvas canvas, Offset a, Offset b, Paint paint, double dash, double gap) {
  final d = b - a;
  final len = d.distance;
  if (len == 0) return;
  final u = d / len;
  var t = 0.0;
  while (t < len) {
    final end = math.min(t + dash, len);
    canvas.drawLine(a + u * t, a + u * end, paint);
    t = end + gap;
  }
}

void _text(Canvas canvas, String text, Offset at, double unit,
    {required Color color, bool centred = false}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: CruType.micro.copyWith(
        fontSize: CruType.micro.fontSize! * unit,
        color: color,
        shadows: PlusStage.textShadow,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, centred ? at - Offset(tp.width / 2, tp.height / 2) : at);
}
