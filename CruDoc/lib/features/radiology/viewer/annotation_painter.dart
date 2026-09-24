import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/imaging/rad_pixels.dart';
import 'package:doctor_management_app/features/radiology/viewer/measure.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Colours inside the dark image viewport. Radiographs are read on black
/// whatever the app theme, and measurement ink must stand out on grey
/// bone, so these are fixed rather than theme tokens. They never appear
/// in the app chrome.
abstract final class RadInk {
  static const viewport = Color(0xFF000000);

  /// Between panes.
  static const gutter = Color(0xFF1C1E22);

  /// Measurement ink: the warm yellow radiologists expect.
  static const annotation = Color(0xFFFFD166);
  static const selected = Color(0xFFFFFFFF);

  /// The calibration ruler while it is drawn.
  static const calibrate = Color(0xFF7FDBFF);
  static const handleFill = Color(0xFFFFFFFF);
  static const handleRing = Color(0xFF000000);
  static const labelFill = Color(0xB8000000);
  static const labelText = Color(0xFFFFFFFF);
  static const overlay = Color(0xE6FFFFFF);
  static const overlayQuiet = Color(0x99FFFFFF);
  static const overlayFill = Color(0x99000000);
  static const loupeRing = Color(0xCCFFFFFF);

  /// Colours the doctor can give an annotation.
  static const swatches = <Color>[
    annotation,
    Color(0xFF7CE38B),
    Color(0xFF7FDBFF),
    Color(0xFFFF8FD8),
    Color(0xFFFFFFFF),
  ];

  static String hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static Color of(RadAnnotation a) {
    final h = a.colorHex.replaceFirst('#', '');
    final v = h.length == 6 ? int.tryParse(h, radix: 16) : null;
    return v == null ? annotation : Color(0xFF000000 | v);
  }
}

/// Mean ± SD for ROI annotations, cached until the ROI moves.
class RadRoiCache {
  final _cache = <String, (List<RadPoint>, String?)>{};

  /// "Mean 1234 ± 56" or null.
  String? text(RadAnnotation a, RadPixels? px) {
    if (px == null) return null;
    if (a.kind != RadAnnoKind.ellipse && a.kind != RadAnnoKind.rect) return null;
    final hit = _cache[a.id];
    if (hit != null && identical(hit.$1, a.points)) return hit.$2;
    final s = RadMeasure.roiStats(a, px.values, px.width, px.height);
    final digits = (px.maxValue - px.minValue).abs() < 20 ? 2 : 0;
    final t = s == null
        ? null
        : 'Mean ${s.mean.toStringAsFixed(digits)} ± ${s.sd.toStringAsFixed(digits)}';
    _cache[a.id] = (a.points, t);
    return t;
  }

  void clear() => _cache.clear();
}

/// The lines under an annotation's label: its name, value and ROI stats.
List<String> radLabelLines(RadAnnotation a, double? mmPerPx, String? roi) {
  final value = RadMeasure.valueText(a, mmPerPx);
  final lines = <String>[];
  if (a.text.isNotEmpty) lines.add(a.text);
  if (value != null) lines.add(value);
  if (roi != null) lines.add(roi);
  return lines;
}

/// Draws annotations in pane coordinates (lines stay the same thickness
/// at any zoom). [k] scales strokes and text for high-resolution exports.
class RadAnnotationPainter {
  RadAnnotationPainter({
    required this.toScreen,
    required this.mmPerPx,
    this.roi,
    this.px,
    this.k = 1,
  });

  final Offset Function(RadPoint p) toScreen;
  final double? mmPerPx;
  final RadRoiCache? roi;
  final RadPixels? px;
  final double k;

  void paintAll(Canvas canvas, List<RadAnnotation> list, {String? selectedId}) {
    for (final a in list) {
      paint(canvas, a, selected: a.id == selectedId);
    }
  }

  void paint(
    Canvas canvas,
    RadAnnotation a, {
    bool selected = false,
    bool draft = false,
    Offset? hover,
    Color? color,
  }) {
    final ink = color ?? (selected ? RadInk.selected : RadInk.of(a));
    final pts = [for (final p in a.points) toScreen(p)];
    if (hover != null) pts.add(hover);
    if (pts.isEmpty) return;
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = (selected ? 2.2 : 1.6) * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    // A soft dark halo keeps thin ink readable on bright bone.
    final halo = Paint()
      ..color = const Color(0x66000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.strokeWidth + 2 * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void both(void Function(Paint p) draw) {
      draw(halo);
      draw(stroke);
    }

    Offset? labelAt;
    switch (a.kind) {
      case RadAnnoKind.length:
        if (pts.length >= 2) {
          both((p) => canvas.drawLine(pts[0], pts[1], p));
          for (final end in [pts[0], pts[1]]) {
            final d = pts[1] - pts[0];
            final n = d.distance == 0 ? Offset.zero : Offset(-d.dy, d.dx) / d.distance * 6 * k;
            both((p) => canvas.drawLine(end - n, end + n, p));
          }
          labelAt = Offset.lerp(pts[0], pts[1], 0.5)! + Offset(8 * k, 8 * k);
        }
      case RadAnnoKind.angle:
        if (pts.length >= 2) both((p) => canvas.drawLine(pts[0], pts[1], p));
        if (pts.length >= 3) {
          both((p) => canvas.drawLine(pts[1], pts[2], p));
          final a1 = math.atan2(pts[0].dy - pts[1].dy, pts[0].dx - pts[1].dx);
          final a2 = math.atan2(pts[2].dy - pts[1].dy, pts[2].dx - pts[1].dx);
          var sweep = a2 - a1;
          while (sweep > math.pi) {
            sweep -= 2 * math.pi;
          }
          while (sweep < -math.pi) {
            sweep += 2 * math.pi;
          }
          final r = 22 * k;
          both((p) => canvas.drawArc(Rect.fromCircle(center: pts[1], radius: r), a1, sweep, false, p));
          final mid = a1 + sweep / 2;
          labelAt = pts[1] + Offset(math.cos(mid), math.sin(mid)) * (r + 10 * k);
        }
      case RadAnnoKind.polygon:
      case RadAnnoKind.polyline:
      case RadAnnoKind.freehand:
        if (pts.length >= 2) {
          final path = Path()..moveTo(pts[0].dx, pts[0].dy);
          for (final q in pts.skip(1)) {
            path.lineTo(q.dx, q.dy);
          }
          if (a.kind == RadAnnoKind.polygon && !draft) path.close();
          both((p) => canvas.drawPath(path, p));
        } else {
          canvas.drawCircle(pts[0], 2 * k, Paint()..color = ink);
        }
        if (a.kind == RadAnnoKind.polygon && pts.length >= 3) {
          var cx = 0.0, cy = 0.0;
          for (final q in pts) {
            cx += q.dx;
            cy += q.dy;
          }
          labelAt = Offset(cx / pts.length, cy / pts.length);
        } else {
          labelAt = pts.last + Offset(8 * k, 8 * k);
        }
      case RadAnnoKind.rect:
      case RadAnnoKind.ellipse:
        if (pts.length >= 2) {
          final r = Rect.fromPoints(pts[0], pts[1]);
          if (a.kind == RadAnnoKind.rect) {
            both((p) => canvas.drawRect(r, p));
          } else {
            both((p) => canvas.drawOval(r, p));
          }
          labelAt = r.bottomRight + Offset(6 * k, 4 * k);
        }
      case RadAnnoKind.arrow:
        if (pts.length >= 2) {
          final head = pts[0], tail = pts[1];
          both((p) => canvas.drawLine(tail, head, p));
          final d = head - tail;
          if (d.distance > 0) {
            final u = d / d.distance;
            final n = Offset(-u.dy, u.dx);
            final size = 12 * k;
            final wing = Path()
              ..moveTo(head.dx, head.dy)
              ..lineTo((head - u * size + n * size * 0.5).dx, (head - u * size + n * size * 0.5).dy)
              ..moveTo(head.dx, head.dy)
              ..lineTo((head - u * size - n * size * 0.5).dx, (head - u * size - n * size * 0.5).dy);
            both((p) => canvas.drawPath(wing, p));
          }
          labelAt = tail + Offset(6 * k, 6 * k);
        }
      case RadAnnoKind.text:
        canvas.drawCircle(pts[0], 3 * k, Paint()..color = ink);
        labelAt = pts[0] + Offset(8 * k, -10 * k);
      case RadAnnoKind.toothLabel:
        _toothChip(canvas, pts[0], a.text, ink);
    }

    if (selected || draft) {
      for (final q in (draft ? pts.take(a.points.length) : pts)) {
        if (a.kind == RadAnnoKind.freehand) break;
        canvas.drawCircle(q, 4.5 * k, Paint()..color = RadInk.handleRing);
        canvas.drawCircle(q, 3.5 * k, Paint()..color = RadInk.handleFill);
      }
    }

    if (labelAt != null && a.kind != RadAnnoKind.toothLabel) {
      final lines = radLabelLines(a, mmPerPx, roi?.text(a, px));
      if (lines.isNotEmpty) _label(canvas, labelAt, lines, ink);
    }
  }

  void _label(Canvas canvas, Offset at, List<String> lines, Color ink) {
    final tp = TextPainter(
      text: TextSpan(
        style: CruType.caption.tabular.copyWith(
          color: RadInk.labelText,
          fontSize: CruType.caption.fontSize! * k,
          height: 1.3,
        ),
        children: [
          for (var i = 0; i < lines.length; i++)
            TextSpan(
              text: i == 0 ? lines[i] : '\n${lines[i]}',
              style: i == 0 ? TextStyle(fontWeight: FontWeight.w600, color: ink) : null,
            ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pad = EdgeInsets.symmetric(horizontal: 6 * k, vertical: 3 * k);
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(at.dx, at.dy, tp.width + pad.horizontal, tp.height + pad.vertical),
      Radius.circular(CruRadius.keycap * k),
    );
    canvas.drawRRect(r, Paint()..color = RadInk.labelFill);
    tp.paint(canvas, at + Offset(pad.left, pad.top));
  }

  void _toothChip(Canvas canvas, Offset at, String number, Color ink) {
    final tp = TextPainter(
      text: TextSpan(
        text: number.isEmpty ? '?' : number,
        style: CruType.caption.w600.tabular.copyWith(
          color: RadInk.viewport,
          fontSize: CruType.caption.fontSize! * k,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = math.max(tp.width + 12 * k, 24 * k), h = 20 * k;
    final r = RRect.fromRectAndRadius(
      Rect.fromCenter(center: at, width: w, height: h),
      Radius.circular(h / 2),
    );
    canvas.drawRRect(r.inflate(1 * k), Paint()..color = const Color(0x99000000));
    canvas.drawRRect(r, Paint()..color = ink);
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }
}

// ───────────────────────────── Hit testing ─────────────────────────────

double _segDist(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// Distance in pane pixels from [s] to the annotation's ink.
double radAnnotationDistance(RadAnnotation a, Offset s, Offset Function(RadPoint) toScreen) {
  final pts = [for (final p in a.points) toScreen(p)];
  if (pts.isEmpty) return double.infinity;
  switch (a.kind) {
    case RadAnnoKind.text:
    case RadAnnoKind.toothLabel:
      final d = (s - pts[0]).distance;
      // The label to the right of a note is part of it too.
      if (a.kind == RadAnnoKind.text) {
        final label = Rect.fromLTWH(pts[0].dx, pts[0].dy - 10, 8.0 * math.max(a.text.length, 4) + 12, 22);
        if (label.contains(s)) return 0;
      }
      return math.max(0, d - 10);
    case RadAnnoKind.rect:
    case RadAnnoKind.ellipse:
      if (pts.length < 2) return double.infinity;
      final r = Rect.fromPoints(pts[0], pts[1]);
      if (r.contains(s)) {
        if (a.kind == RadAnnoKind.rect) return 0;
        final c = r.center;
        final dx = (s.dx - c.dx) / math.max(r.width / 2, 1), dy = (s.dy - c.dy) / math.max(r.height / 2, 1);
        if (dx * dx + dy * dy <= 1) return 0;
      }
      return math.min(
        math.min(_segDist(s, r.topLeft, r.topRight), _segDist(s, r.topRight, r.bottomRight)),
        math.min(_segDist(s, r.bottomRight, r.bottomLeft), _segDist(s, r.bottomLeft, r.topLeft)),
      );
    case RadAnnoKind.polygon:
      var best = double.infinity;
      for (var i = 0; i < pts.length; i++) {
        best = math.min(best, _segDist(s, pts[i], pts[(i + 1) % pts.length]));
      }
      return best;
    default:
      if (pts.length == 1) return (s - pts[0]).distance;
      var best = double.infinity;
      for (var i = 1; i < pts.length; i++) {
        best = math.min(best, _segDist(s, pts[i - 1], pts[i]));
      }
      return best;
  }
}

/// The top-most annotation within [tolerance] pane pixels of [s].
RadAnnotation? radHitAnnotation(
  List<RadAnnotation> list,
  Offset s,
  Offset Function(RadPoint) toScreen, {
  double tolerance = 7,
}) {
  RadAnnotation? best;
  var bestD = tolerance;
  for (final a in list.reversed) {
    final d = radAnnotationDistance(a, s, toScreen);
    if (d <= bestD) {
      best = a;
      bestD = d;
      if (d == 0) break;
    }
  }
  return best;
}

/// The index of the handle of [a] under [s], if any.
int? radHitHandle(RadAnnotation a, Offset s, Offset Function(RadPoint) toScreen, {double tolerance = 9}) {
  if (a.kind == RadAnnoKind.freehand) return null;
  for (var i = a.points.length - 1; i >= 0; i--) {
    if ((toScreen(a.points[i]) - s).distance <= tolerance) return i;
  }
  return null;
}

// ───────────────────────────── Scale bar ─────────────────────────────

/// A millimetre scale bar in the bottom-right corner of a pane.
void radPaintScaleBar(Canvas canvas, Size size, double mmPerScreenPx, {double k = 1}) {
  if (mmPerScreenPx <= 0 || !mmPerScreenPx.isFinite) return;
  const nice = [0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0];
  var mm = nice.first;
  for (final n in nice) {
    mm = n;
    if (n / mmPerScreenPx >= 70 * k) break;
  }
  final len = mm / mmPerScreenPx;
  if (len > size.width * 0.45) return;
  final right = size.width - 16 * k, y = size.height - 16 * k;
  final left = right - len;
  final paint = Paint()
    ..color = RadInk.overlay
    ..strokeWidth = 1.5 * k
    ..style = PaintingStyle.stroke;
  canvas.drawLine(Offset(left, y), Offset(right, y), paint);
  canvas.drawLine(Offset(left, y - 5 * k), Offset(left, y), paint);
  canvas.drawLine(Offset(right, y - 5 * k), Offset(right, y), paint);
  final tp = TextPainter(
    text: TextSpan(
      text: '${mm < 1 ? mm.toStringAsFixed(1) : mm.toStringAsFixed(0)} mm',
      style: CruType.micro.tabular.copyWith(
        color: RadInk.overlay,
        fontSize: CruType.micro.fontSize! * k,
      ),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  tp.paint(canvas, Offset(right - tp.width, y - 8 * k - tp.height));
}
