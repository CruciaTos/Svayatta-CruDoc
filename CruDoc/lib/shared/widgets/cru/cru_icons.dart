import 'package:flutter/widgets.dart';

/// Stroke icons from the Calm Clinical reference (24-unit viewBox,
/// round caps and joins). Painted from their SVG path data, so they look
/// the same in the app and in golden tests without an icon font.
@immutable
class CruIconData {
  const CruIconData(
    this.path, {
    this.circles = const [],
    this.rects = const [],
    this.filled = false,
    this.viewBox = 24,
  });

  /// SVG path data (M L H V C S A Z, absolute and relative).
  final String path;

  /// (cx, cy, r) circles.
  final List<(double, double, double)> circles;

  /// (x, y, w, h, rx) rounded rectangles.
  final List<(double, double, double, double, double)> rects;

  /// Fill instead of stroke (the "more" dots).
  final bool filled;

  final double viewBox;
}

abstract final class CruIcons {
  static const plus = CruIconData('M12 5v14M5 12h14');
  static const chevronsUpDown = CruIconData('m8 9 4-4 4 4M8 15l4 4 4-4');
  static const chevronDown = CruIconData('m6 9.5 6 6 6-6');
  static const chevronLeft = CruIconData('m14.5 6-6 6 6 6');
  static const chevronRight = CruIconData('m9.5 6 6 6-6 6');
  static const dashboard = CruIconData('', rects: [
    (3.5, 3.5, 7, 7, 2),
    (13.5, 3.5, 7, 7, 2),
    (3.5, 13.5, 7, 7, 2),
    (13.5, 13.5, 7, 7, 2),
  ]);
  static const queue = CruIconData('M4 6.5h16M4 12h16M4 17.5h10');
  static const calendar = CruIconData(
    'M3.5 10h17M8 3v4M16 3v4',
    rects: [(3.5, 5, 17, 15.5, 3.5)],
  );
  static const patients = CruIconData(
    'M2.5 20c.6-3.6 3.3-6 6.5-6s5.9 2.4 6.5 6'
    'M16 4.6a3.5 3.5 0 0 1 0 6.8M18 14.3c2 .8 3.2 2.8 3.5 5.7',
    circles: [(9, 8, 3.5)],
  );
  static const mic = CruIconData(
    'M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21',
    rects: [(9, 3, 6, 11, 3)],
  );
  static const box = CruIconData(
    'M3.5 7.5 12 3l8.5 4.5v9L12 21l-8.5-4.5z'
    'M3.5 7.5 12 12l8.5-4.5M12 12v9',
  );
  static const rupee = CruIconData(
    'M7 4.5h10M7 9h10M9.5 4.5c3.3 0 5 1.7 5 4.5s-1.7 4.5-5 4.5H7l7.5 6.5',
  );
  static const megaphone = CruIconData(
    'M4 10v4a1 1 0 0 0 1 1h2l8 4.5V4.5L7 9H5a1 1 0 0 0-1 1z'
    'M18.5 9.5a3.5 3.5 0 0 1 0 5',
  );
  static const search = CruIconData(
    'm20 20-4.2-4.2',
    circles: [(11, 11, 6.5)],
  );
  /// A house (home visits).
  static const home = CruIconData(
    'M4 10.5 12 4l8 6.5V19a1 1 0 0 1-1 1h-4.5v-5.5h-5V20H5a1 1 0 0 1-1-1z',
  );

  /// One person (Profile).
  static const user = CruIconData(
    'M4.5 20c.6-3.6 3.6-6 7.5-6s6.9 2.4 7.5 6',
    circles: [(12, 8, 3.5)],
  );
  static const userPlus = CruIconData(
    'M3.5 20c.6-3.6 3.2-6 6.5-6s5.9 2.4 6.5 6M19 8v6M16 11h6',
    circles: [(10, 8, 3.5)],
  );
  static const clock = CruIconData(
    'M12 7.5V12l3 2',
    circles: [(12, 12, 8.5)],
  );
  static const warning = CruIconData(
    'M10.3 4.8a2 2 0 0 1 3.4 0l7 12.2a2 2 0 0 1-1.7 3H5a2 2 0 0 1-1.7-3z'
    'M12 10v4M12 17h.01',
  );
  static const check = CruIconData('m5 12.5 4.5 4.5L19 7.5');
  static const more = CruIconData(
    '',
    circles: [(5.5, 12, 1.7), (12, 12, 1.7), (18.5, 12, 1.7)],
    filled: true,
  );
  static const flask = CruIconData(
    'M9.5 3.5h5M10 3.5v5.5L4.8 17.6A2 2 0 0 0 6.5 20.5h11a2 2 0 0 0 1.7-2.9'
    'L14 9V3.5M7.5 14.5h9',
  );
  static const phone = CruIconData(
    'M5 4.5h3.5l1.5 4-2 1.5a11 11 0 0 0 6 6l1.5-2 4 1.5V19a1.5 1.5 0 0 1'
    '-1.5 1.5A15.5 15.5 0 0 1 3.5 6 1.5 1.5 0 0 1 5 4.5z',
  );
  static const sparkle = CruIconData(
    'M11 3.5C11.6 8 14 10.4 18.5 11 14 11.6 11.6 14 11 18.5 10.4 14 8 11.6'
    ' 3.5 11 8 10.4 10.4 8 11 3.5z'
    'M18.5 2c.2 1.6.9 2.3 2.5 2.5-1.6.2-2.3.9-2.5 2.5-.2-1.6-.9-2.3-2.5-2.5'
    ' 1.6-.2 2.3-.9 2.5-2.5z',
  );
  static const moon = CruIconData('M19.5 14.5A8 8 0 0 1 9.5 4.5a8 8 0 1 0 10 10z');
  static const sun = CruIconData(
    'M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6 7 7M17 17l1.4 1.4'
    'M5.6 18.4 7 17M17 7l1.4-1.4',
    circles: [(12, 12, 4)],
  );
  static const pen = CruIconData('M4 20h4L19 9a2.8 2.8 0 0 0-4-4L4 16zm9.5-13.5 4 4');
  static const wallet = CruIconData(
    'M3.5 10h17M15.5 14.5h2',
    rects: [(3.5, 6, 17, 13, 3)],
  );
  static const arrowUp = CruIconData('M12 19V5M6 11l6-6 6 6');
  static const arrowDown = CruIconData('M12 5v14M6 13l6 6 6-6');
  static const settings = CruIconData(
    'M4 7h8M16 7h4M4 17h4M12 17h8',
    circles: [(14, 7, 2), (10, 17, 2)],
  );
  static const help = CruIconData(
    'M9.6 9.5a2.5 2.5 0 0 1 4.8.9c0 1.7-2.4 2.1-2.4 3.6M12 17h.01',
    circles: [(12, 12, 8.5)],
  );
  static const logout = CruIconData(
    'M9 20H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h3M16 16l4-4-4-4M20 12H9',
  );
  static const sidebar = CruIconData(
    'M9.5 4.5v15',
    rects: [(3.5, 4.5, 17, 15, 3.5)],
  );
  /// WhatsApp-style chat bubble.
  static const whatsapp = CruIconData(
    'M20.5 11.5a8.5 8.5 0 0 1-12.4 7.5L3.5 20.5l1.4-4.3A8.5 8.5 0 1 1 20.5 11.5z',
  );
  static const close = CruIconData('M6.5 6.5l11 11M17.5 6.5l-11 11');
  static const arrowUpRight = CruIconData('M8 16 16 8M9 8h7v7');
  static const importExport = CruIconData('M8 20V5M4 9l4-4 4 4M16 4v15M12 15l4 4 4-4');
  static const download = CruIconData(
    'M12 3.5v11M7.5 10l4.5 4.5 4.5-4.5'
    'M4 15.5v2a3 3 0 0 0 3 3h10a3 3 0 0 0 3-3v-2',
  );

  /// Single four-point star: the Scribe provenance tag.
  static const sparkleSingle = CruIconData(
    'M12 3.5C12.7 8.5 15.5 11.3 20.5 12 15.5 12.7 12.7 15.5 12 20.5'
    ' 11.3 15.5 8.5 12.7 3.5 12 8.5 11.3 11.3 8.5 12 3.5z',
  );
  static const autoMode = CruIconData(
    'M12 3.5v17',
    circles: [(12, 12, 8.5)],
  );
}

/// Makes every [CruIcon] below it [scale] times larger (the dental
/// chairside mode enlarges the main area's text and icons together).
class CruIconScale extends InheritedWidget {
  const CruIconScale({super.key, required this.scale, required super.child});

  final double scale;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CruIconScale>()?.scale ?? 1;

  @override
  bool updateShouldNotify(CruIconScale old) => old.scale != scale;
}

/// Paints a [CruIconData].
class CruIcon extends StatelessWidget {
  const CruIcon(
    this.icon, {
    super.key,
    this.size = 20,
    this.color,
    this.strokeWidth = 1.7,
    this.semanticLabel,
  });

  final CruIconData icon;
  final double size;

  /// Defaults to the ambient [IconTheme] colour.
  final Color? color;

  /// In viewBox units (the reference's `stroke-width`).
  final double strokeWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? IconTheme.of(context).color ?? const Color(0xFF000000);
    final painted = CustomPaint(
      size: Size.square(size * CruIconScale.of(context)),
      painter: _CruIconPainter(icon, resolved, strokeWidth),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: painted);
    return Semantics(label: semanticLabel, child: painted);
  }
}

class _CruIconPainter extends CustomPainter {
  _CruIconPainter(this.icon, this.color, this.strokeWidth);

  final CruIconData icon;
  final Color color;
  final double strokeWidth;

  static final Map<CruIconData, Path> _cache = {};

  static Path _pathFor(CruIconData icon) {
    return _cache.putIfAbsent(icon, () {
      final path = icon.path.isEmpty ? Path() : parseSvgPath(icon.path);
      for (final (cx, cy, r) in icon.circles) {
        path.addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      }
      for (final (x, y, w, h, rx) in icon.rects) {
        path.addRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(rx)),
        );
      }
      return path;
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / icon.viewBox;
    canvas.save();
    canvas.scale(scale);
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    if (icon.filled) {
      paint.style = PaintingStyle.fill;
    } else {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
    }
    canvas.drawPath(_pathFor(icon), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CruIconPainter old) =>
      old.icon != icon || old.color != color || old.strokeWidth != strokeWidth;
}

final RegExp _token = RegExp(r'[MmLlHhVvCcSsAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');

/// Parses the subset of SVG path syntax the reference icons use.
Path parseSvgPath(String data) {
  final tokens = _token.allMatches(data).map((m) => m.group(0)!).toList();
  final path = Path();
  var i = 0;
  var cmd = '';
  var cur = Offset.zero;
  var start = Offset.zero;
  Offset? lastCtrl;

  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double next() => double.parse(tokens[i++]);

  while (i < tokens.length) {
    if (isCmd(tokens[i])) {
      cmd = tokens[i++];
    }
    final rel = cmd == cmd.toLowerCase();
    Offset pt(double x, double y) => rel ? cur + Offset(x, y) : Offset(x, y);

    switch (cmd.toUpperCase()) {
      case 'M':
        cur = pt(next(), next());
        start = cur;
        path.moveTo(cur.dx, cur.dy);
        // Further pairs are implicit line-tos.
        cmd = rel ? 'l' : 'L';
        lastCtrl = null;
      case 'L':
        cur = pt(next(), next());
        path.lineTo(cur.dx, cur.dy);
        lastCtrl = null;
      case 'H':
        final x = next();
        cur = Offset(rel ? cur.dx + x : x, cur.dy);
        path.lineTo(cur.dx, cur.dy);
        lastCtrl = null;
      case 'V':
        final y = next();
        cur = Offset(cur.dx, rel ? cur.dy + y : y);
        path.lineTo(cur.dx, cur.dy);
        lastCtrl = null;
      case 'C':
        final c1 = pt(next(), next());
        final c2 = pt(next(), next());
        final end = pt(next(), next());
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
        lastCtrl = c2;
        cur = end;
      case 'S':
        final c1 = lastCtrl == null ? cur : cur * 2 - lastCtrl;
        final c2 = pt(next(), next());
        final end = pt(next(), next());
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
        lastCtrl = c2;
        cur = end;
      case 'A':
        final rx = next();
        final ry = next();
        final rotation = next();
        final largeArc = next() != 0;
        final sweep = next() != 0;
        final end = pt(next(), next());
        path.arcToPoint(
          end,
          radius: Radius.elliptical(rx, ry),
          // Path.arcToPoint takes degrees, same as SVG.
          rotation: rotation,
          largeArc: largeArc,
          clockwise: sweep,
        );
        cur = end;
        lastCtrl = null;
      case 'Z':
        path.close();
        cur = start;
        lastCtrl = null;
      default:
        throw FormatException('Unsupported SVG path command "$cmd"', data);
    }
  }
  return path;
}
