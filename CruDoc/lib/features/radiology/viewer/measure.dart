import 'dart:math' as math;
import 'dart:typed_data';

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';

/// Measurement values of an annotation, shared by the viewer and the
/// report. Distances are in mm when the image is calibrated (from the
/// file or with the ruler), else in pixels.
abstract final class RadMeasure {
  static double _dist(RadPoint a, RadPoint b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

  /// Angle at the middle point (three points), in degrees.
  static double angleDeg(RadPoint a, RadPoint vertex, RadPoint c) {
    final a1 = math.atan2(a.y - vertex.y, a.x - vertex.x);
    final a2 = math.atan2(c.y - vertex.y, c.x - vertex.x);
    var d = (a1 - a2).abs() * 180 / math.pi;
    if (d > 180) d = 360 - d;
    return d;
  }

  /// Shoelace area of a closed polygon, in pixels².
  static double polygonAreaPx(List<RadPoint> pts) {
    if (pts.length < 3) return 0;
    var s = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      s += a.x * b.y - b.x * a.y;
    }
    return s.abs() / 2;
  }

  static double pathLengthPx(List<RadPoint> pts) {
    var s = 0.0;
    for (var i = 1; i < pts.length; i++) {
      s += _dist(pts[i - 1], pts[i]);
    }
    return s;
  }

  static String _len(double px, double? mmPerPx) =>
      mmPerPx == null ? '${px.toStringAsFixed(0)} px' : '${(px * mmPerPx).toStringAsFixed(1)} mm';

  static String _area(double px2, double? mmPerPx) => mmPerPx == null
      ? '${px2.toStringAsFixed(0)} px²'
      : '${(px2 * mmPerPx * mmPerPx).toStringAsFixed(1)} mm²';

  /// "12.4 mm", "38.2°", "45.1 mm²"; null for annotations that aren't
  /// measurements (arrows, text).
  static String? valueText(RadAnnotation a, double? mmPerPx) {
    final p = a.points;
    switch (a.kind) {
      case RadAnnoKind.length:
        return p.length < 2 ? null : _len(_dist(p[0], p[1]), mmPerPx);
      case RadAnnoKind.polyline:
        return p.length < 2 ? null : _len(pathLengthPx(p), mmPerPx);
      case RadAnnoKind.angle:
        return p.length < 3 ? null : '${angleDeg(p[0], p[1], p[2]).toStringAsFixed(1)}°';
      case RadAnnoKind.polygon:
        return p.length < 3 ? null : _area(polygonAreaPx(p), mmPerPx);
      case RadAnnoKind.rect:
        if (p.length < 2) return null;
        final w = (p[1].x - p[0].x).abs(), h = (p[1].y - p[0].y).abs();
        return '${_len(w, mmPerPx)} × ${_len(h, mmPerPx)} · ${_area(w * h, mmPerPx)}';
      case RadAnnoKind.ellipse:
        if (p.length < 2) return null;
        final rx = (p[1].x - p[0].x).abs() / 2, ry = (p[1].y - p[0].y).abs() / 2;
        return _area(math.pi * rx * ry, mmPerPx);
      case RadAnnoKind.arrow:
      case RadAnnoKind.text:
      case RadAnnoKind.freehand:
      case RadAnnoKind.toothLabel:
        return null;
    }
  }

  /// "Length", "Angle"…
  static String kindLabel(RadAnnoKind k) => switch (k) {
        RadAnnoKind.length => 'Length',
        RadAnnoKind.angle => 'Angle',
        RadAnnoKind.polygon => 'Area',
        RadAnnoKind.ellipse => 'Ellipse',
        RadAnnoKind.rect => 'Rectangle',
        RadAnnoKind.polyline => 'Path',
        RadAnnoKind.arrow => 'Arrow',
        RadAnnoKind.text => 'Note',
        RadAnnoKind.freehand => 'Drawing',
        RadAnnoKind.toothLabel => 'Tooth',
      };

  /// Mean and standard deviation of the pixel [values] inside an ellipse
  /// or rectangle ROI (image [width] × [height], row by row). Null for
  /// other kinds or an ROI outside the image.
  static ({double mean, double sd, int n})? roiStats(
    RadAnnotation a,
    Float32List values,
    int width,
    int height,
  ) {
    if (a.points.length < 2) return null;
    if (a.kind != RadAnnoKind.ellipse && a.kind != RadAnnoKind.rect) return null;
    final p = a.points;
    final x0 = math.min(p[0].x, p[1].x), x1 = math.max(p[0].x, p[1].x);
    final y0 = math.min(p[0].y, p[1].y), y1 = math.max(p[0].y, p[1].y);
    final cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
    final rx = math.max((x1 - x0) / 2, 0.5), ry = math.max((y1 - y0) / 2, 0.5);
    final ix0 = x0.floor().clamp(0, width - 1), ix1 = x1.ceil().clamp(0, width - 1);
    final iy0 = y0.floor().clamp(0, height - 1), iy1 = y1.ceil().clamp(0, height - 1);
    // Large ROIs are sampled on a grid: the statistics barely move and
    // dragging stays smooth.
    final area = (ix1 - ix0 + 1) * (iy1 - iy0 + 1);
    final step = area > 400000 ? math.sqrt(area / 400000).ceil() : 1;
    var n = 0;
    var sum = 0.0, sum2 = 0.0;
    for (var y = iy0; y <= iy1; y += step) {
      for (var x = ix0; x <= ix1; x += step) {
        if (a.kind == RadAnnoKind.ellipse) {
          final dx = (x + 0.5 - cx) / rx, dy = (y + 0.5 - cy) / ry;
          if (dx * dx + dy * dy > 1) continue;
        }
        final v = values[y * width + x];
        sum += v;
        sum2 += v * v;
        n++;
      }
    }
    if (n == 0) return null;
    final mean = sum / n;
    final variance = math.max(0.0, sum2 / n - mean * mean);
    return (mean: mean, sd: math.sqrt(variance), n: n);
  }

  /// mm per pixel for an image: the ruler calibration, else the file's.
  static double? mmPerPx(RadStudy s, String imageId) {
    final cal = s.calibration[imageId];
    if (cal != null) return cal;
    for (final i in s.images) {
      if (i.id == imageId) return i.pixelSpacingMm;
    }
    return null;
  }

  /// Every measurement in the study for the report: 2D annotations
  /// (labelled with their text or kind) and any values modules added to
  /// `extras['reportMeasurements']` (CBCT, ceph).
  static List<({String id, String label, String value})> reportRows(RadStudy s) {
    final out = <({String id, String label, String value})>[];
    for (final e in s.annotations.entries) {
      final cal = mmPerPx(s, e.key);
      for (final a in e.value) {
        final v = valueText(a, cal);
        if (v == null) continue;
        out.add((id: a.id, label: a.text.isNotEmpty ? a.text : kindLabel(a.kind), value: v));
      }
    }
    final extra = s.extras['reportMeasurements'];
    if (extra is List) {
      for (final m in extra) {
        if (m is Map) {
          out.add((id: '${m['id']}', label: '${m['label']}', value: '${m['value']}'));
        }
      }
    }
    return out;
  }
}
