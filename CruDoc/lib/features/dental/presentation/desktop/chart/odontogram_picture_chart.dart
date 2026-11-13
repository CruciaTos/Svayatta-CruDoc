import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/odontogram_regions.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_art.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_2d.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_arches_vector.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The two odontogram pictures (artwork used with the owner's permission).
enum OdontogramArt {
  /// Black line art: findings are a soft colour under the lines.
  line2d('assets/images/odontogram/odontogram_2d.jpg'),

  /// Grey clay render: findings are a translucent tint and a coloured outline.
  clay3d('assets/images/odontogram/odontogram_3d.jpg');

  const OdontogramArt(this.asset);
  final String asset;

  Size get size => this == line2d ? odontogram2DSize : odontogram3DSize;
  Map<int, OdontogramRegion> get regions =>
      this == line2d ? odontogram2DRegions : odontogram3DRegions;
}

/// Decodes each picture once.
class _Pictures extends ChangeNotifier {
  _Pictures._();
  static final instance = _Pictures._();

  final Map<OdontogramArt, ui.Image> _images = {};
  final Set<OdontogramArt> _started = {};

  ui.Image? of(OdontogramArt art) => _images[art];

  Future<void> ensureLoaded(OdontogramArt art) async {
    if (!_started.add(art)) return;
    try {
      final data = await rootBundle.load(art.asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      _images[art] = (await codec.getNextFrame()).image;
      codec.dispose();
      notifyListeners();
    } catch (_) {
      _started.remove(art);
    }
  }
}

/// Loads both pictures (for tests that render off the real clock).
@visibleForTesting
Future<void> loadOdontogramPictures() => Future.wait([
  for (final a in OdontogramArt.values) _Pictures.instance.ensureLoaded(a),
]);

/// Odontogram drawn on one of the two odontogram pictures: the picture
/// scaled to fit, each tooth a region of it (tap, findings, selection and
/// numbers use the region polygons).
///
/// Perio and endo layers use the row chart; milk teeth (not in the
/// pictures) use the vector odontogram.
class OdontogramPictureChart extends StatefulWidget {
  const OdontogramPictureChart({
    super.key,
    required this.art,
    required this.data,
    required this.child,
    required this.selected,
    required this.onSelect,
    this.onOpen,
    this.onDeselect,
    this.layer = ChartLayer.dental,
    this.numbering = ToothNumbering.fdi,
    this.showBar = false,
  });

  final OdontogramArt art;
  final ToothChartData data;
  final bool child;
  final String? selected;
  final ValueChanged<String> onSelect;
  final ValueChanged<String>? onOpen;
  final VoidCallback? onDeselect;
  final ChartLayer layer;
  final ToothNumbering numbering;
  final bool showBar;

  @override
  State<OdontogramPictureChart> createState() => _OdontogramPictureChartState();
}

class _OdontogramPictureChartState extends State<OdontogramPictureChart> {
  @override
  void initState() {
    super.initState();
    _Pictures.instance.ensureLoaded(widget.art);
  }

  @override
  void didUpdateWidget(covariant OdontogramPictureChart old) {
    super.didUpdateWidget(old);
    if (old.art != widget.art) _Pictures.instance.ensureLoaded(widget.art);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.layer == ChartLayer.perio || widget.layer == ChartLayer.endo) {
      return ToothChart2D(
        data: widget.data,
        child: widget.child,
        selected: widget.selected,
        onSelect: widget.onSelect,
        onOpen: widget.onOpen,
        onDeselect: widget.onDeselect,
        layer: widget.layer,
        numbering: widget.numbering,
      );
    }
    if (widget.child) {
      return ToothChartArchesVector(
        data: widget.data,
        child: widget.child,
        selected: widget.selected,
        onSelect: widget.onSelect,
        onOpen: widget.onOpen,
        onDeselect: widget.onDeselect,
        layer: widget.layer,
        numbering: widget.numbering,
      );
    }

    final c = context.cru;
    final paper =
        chartPaper(widget.layer, c, base: c.isEvening ? c.surface : null);
    final selTooth = widget.selected;
    final selVisual = selTooth != null ? widget.data.of(selTooth) : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _PictureLayout.of(widget.art, constraints.maxWidth);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: layout.height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final hit = layout.hitTest(d.localPosition);
                  if (hit != null) {
                    widget.onSelect(hit);
                  } else {
                    widget.onDeselect?.call();
                  }
                },
                child: ListenableBuilder(
                  listenable: _Pictures.instance,
                  builder: (context, _) => CustomPaint(
                    size: Size(constraints.maxWidth, layout.height),
                    painter: _PicturePainter(
                      art: widget.art,
                      layout: layout,
                      image: _Pictures.instance.of(widget.art),
                      data: widget.data,
                      layer: widget.layer,
                      selected: widget.selected,
                      numbering: widget.numbering,
                      colors: c,
                      paper: paper,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.showBar && selTooth != null && selVisual != null) ...[
              const SizedBox(height: CruSpace.s12),
              ArchSelectedToothBar(
                fdi: selTooth,
                visual: selVisual,
                layer: widget.layer,
                numbering: widget.numbering,
                onOpen: () => (widget.onOpen ?? widget.onSelect)(selTooth),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A closed smooth curve through [pts] (Catmull-Rom as cubic Beziers).
Path _smoothClosed(List<Offset> pts) {
  final n = pts.length;
  final path = Path()..moveTo(pts[0].dx, pts[0].dy);
  for (var i = 0; i < n; i++) {
    final p0 = pts[(i - 1 + n) % n], p1 = pts[i];
    final p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n];
    final a = p1 + (p2 - p0) / 6, b = p2 - (p3 - p1) / 6;
    path.cubicTo(a.dx, a.dy, b.dx, b.dy, p2.dx, p2.dy);
  }
  return path..close();
}

class _Tooth {
  const _Tooth(this.number, this.outline, this.center, this.radius);
  final String number;
  final Path outline;
  final Offset center;
  final double radius;
}

/// Where the picture and its teeth sit for a given chart width.
class _PictureLayout {
  _PictureLayout._(
    this.width,
    this.height,
    this.panel,
    this.picture,
    this.scale,
    this.teeth,
    this.upperLabel,
    this.lowerLabel,
    this.gapY,
  );

  static const double pad = 10;
  static const double maxWidth = 440;

  final double width;
  final double height;

  /// The white rounded panel the picture sits on, and the picture on it.
  final Rect panel;
  final Rect picture;
  final double scale;
  final List<_Tooth> teeth;
  final Offset upperLabel;
  final Offset lowerLabel;
  final double gapY;

  static final Map<(OdontogramArt, double), _PictureLayout> _cache = {};

  factory _PictureLayout.of(OdontogramArt art, double width) {
    final key = (art, width);
    final hit = _cache[key];
    if (hit != null) return hit;
    if (_cache.length > 24) _cache.clear();
    return _cache[key] = _build(art, width);
  }

  static _PictureLayout _build(OdontogramArt art, double width) {
    final size = art.size;
    final panelW = math.min(width, maxWidth);
    final scale = (panelW - 2 * pad) / size.width;
    final pic = Size(size.width * scale, size.height * scale);
    final panel = Rect.fromLTWH(
      (width - panelW) / 2,
      0,
      panelW,
      pic.height + 2 * pad,
    );
    final picture = Rect.fromLTWH(panel.left + pad, panel.top + pad, pic.width, pic.height);

    final teeth = <_Tooth>[];
    var upperY = 0.0, lowerY = 0.0, nu = 0, nl = 0;
    var upperMax = 0.0, lowerMin = double.infinity;
    for (final e in art.regions.entries) {
      final r = e.value;
      Offset map(Offset p) => picture.topLeft + p * scale;
      final path = _smoothClosed([for (final p in r.outline) map(p)]);
      teeth.add(_Tooth('${e.key}', path, map(r.center), r.radius * scale));
      final upper = e.key < 30;
      final cy = map(r.center).dy;
      if (upper) {
        upperY += cy;
        nu++;
        upperMax = math.max(upperMax, cy);
      } else {
        lowerY += cy;
        nl++;
        lowerMin = math.min(lowerMin, cy);
      }
    }
    final midX = picture.center.dx;
    return _PictureLayout._(
      width,
      panel.height,
      panel,
      picture,
      scale,
      teeth,
      Offset(midX, upperY / nu),
      Offset(midX, lowerY / nl),
      (upperMax + lowerMin) / 2,
    );
  }

  String? hitTest(Offset pos) {
    for (final t in teeth) {
      if (t.outline.contains(pos)) return t.number;
    }
    // Close to a tooth counts too (thin gaps).
    String? best;
    var bestD = 16.0;
    for (final t in teeth) {
      final d = (t.center - pos).distance;
      if (d < bestD) {
        bestD = d;
        best = t.number;
      }
    }
    return best;
  }
}

class _PicturePainter extends CustomPainter {
  _PicturePainter({
    required this.art,
    required this.layout,
    required this.image,
    required this.data,
    required this.layer,
    required this.selected,
    required this.numbering,
    required this.colors,
    required this.paper,
  });

  final OdontogramArt art;
  final _PictureLayout layout;
  final ui.Image? image;
  final ToothChartData data;
  final ChartLayer layer;
  final String? selected;
  final ToothNumbering numbering;
  final CruColors colors;
  final Color paper;

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors;
    final line = art == OdontogramArt.line2d;

    // White paper by day, the card surface in evening.
    final panel = RRect.fromRectAndRadius(
      layout.panel,
      const Radius.circular(CruRadius.panel),
    );
    canvas.drawRRect(panel, Paint()..color = paper);
    if (!c.isEvening) {
      canvas.drawRRect(
        panel.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = c.hairline,
      );
    }
    final img = image;
    if (img != null) {
      // Evening: the picture's white paper must not show, so draw it only
      // inside the tooth outlines. The teeth keep their natural look and the
      // dark card shows around them.
      if (c.isEvening) {
        final teeth = Path();
        for (final t in layout.teeth) {
          teeth.addPath(t.outline, Offset.zero);
        }
        canvas.save();
        canvas.clipPath(teeth, doAntiAlias: true);
      }
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        layout.picture,
        Paint()
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.high,
      );
      if (c.isEvening) canvas.restore();
    }

    const grey = Color(0xFF8A8A8A);
    final arch = CruType.groupLabel.tint(grey);
    _label(canvas, 'Upper', layout.upperLabel, arch);
    _label(canvas, 'Lower', layout.lowerLabel, arch);
    final side = CruType.micro.w600.tint(grey);
    _label(canvas, 'R', Offset(layout.panel.left + 9, layout.gapY), side);
    _label(canvas, 'L', Offset(layout.panel.right - 9, layout.gapY), side);

    // Findings keep the light palette (solid colours read on both papers).
    final f = CruColors.day;
    final texts = <(_Tooth, Color)>[];
    for (final t in layout.teeth) {
      final look = data.of(t.number).look(layer);
      if (look.missing) {
        // Paper over the tooth, then a dashed outline only.
        canvas.drawPath(t.outline, Paint()..color = paper);
        canvas.drawPath(
          t.outline,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4
            ..strokeJoin = StrokeJoin.round
            ..isAntiAlias = true
            ..color = paper,
        );
        dashPath(
          canvas,
          t.outline,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = grey,
          dash: 3,
          gap: 2.5,
        );
        texts.add((t, grey.withValues(alpha: 0.7)));
        continue;
      }

      Color? found;
      var dashed = false;
      var edge = grey;
      if (look.decay.isNotEmpty) {
        found = f.caries;
        edge = _darker(found, 0.75);
      } else if (look.filled.isNotEmpty || look.capped || look.rootCanal) {
        found = f.restoration;
        edge = _darker(found, 0.75);
      } else if (look.planned.isNotEmpty) {
        found = f.accentTint;
        edge = f.accent;
        dashed = true;
      }
      if (found != null) {
        canvas.save();
        canvas.clipPath(t.outline, doAntiAlias: true);
        if (line) {
          // Multiply: the paper turns into the colour, the lines stay black.
          canvas.drawPath(
            t.outline,
            Paint()
              ..blendMode = BlendMode.multiply
              ..color = found.withValues(alpha: dashed ? 0.75 : 0.85),
          );
        } else {
          canvas.drawPath(
            t.outline,
            Paint()..color = found.withValues(alpha: dashed ? 0.35 : 0.5),
          );
        }
        canvas.restore();
        if (!line || dashed) {
          final stroke = Paint()
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round
            ..isAntiAlias = true
            ..strokeWidth = line ? 1.2 : 1.4
            ..color = edge;
          if (dashed) {
            dashPath(canvas, t.outline, stroke, dash: 3, gap: 2.5);
          } else {
            canvas.drawPath(t.outline, stroke);
          }
        }
      }
      texts.add((t, const Color(0xFF2B2B2B)));
    }

    // Selection: a thin accent outline along the tooth.
    for (final t in layout.teeth) {
      if (t.number != selected) continue;
      canvas.drawPath(
        t.outline,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true
          ..color = c.accent,
      );
    }

    // Numbers inside the teeth (a light halo keeps them readable over the
    // fissures), the same in both styles.
    final b = CruType.micro.w600.tabular;
    for (final (t, color) in texts) {
      final fs = (t.radius * 0.62).clamp(7.5, 11.0);
      final weight = t.number == selected ? FontWeight.w700 : b.fontWeight;
      final text = toothLabel(t.number, numbering);
      _label(
        canvas,
        text,
        t.center,
        TextStyle(
          fontFamily: b.fontFamily,
          fontSize: fs,
          fontWeight: weight,
          fontFeatures: b.fontFeatures,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = 2.6
            ..color = const Color(0xD9FFFFFF),
        ),
      );
      _label(
        canvas,
        text,
        t.center,
        b.copyWith(fontSize: fs, fontWeight: weight, color: color),
      );
    }
  }

  static Color _darker(Color c, double k) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness * k).clamp(0.0, 1.0)).toColor();
  }

  void _label(Canvas canvas, String text, Offset center, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _PicturePainter old) => true;
}
