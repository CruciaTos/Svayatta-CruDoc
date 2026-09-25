import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_art.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// A mark on the chart, as the legend shows it.
enum ChartMark {
  decay('Decay'),
  filling('Filling'),
  crown('Crown or bridge'),
  canal('Root canal'),
  implant('Implant'),
  missing('Missing'),
  planned('Planned'),
  extraction('To extract'),
  gum('Gum line'),
  pocket('Pocket 4 mm+'),
  bleeding('Bleeding'),
  pulp('Pulp'),
  obturated('Canals filled'),
  inProgress('Endo in progress'),
  lesion('Infection at root tip');

  const ChartMark(this.label);
  final String label;

  /// What the legend lists for [layer].
  static List<ChartMark> of(ChartLayer layer) => switch (layer) {
        ChartLayer.dental => const [decay, filling, crown, canal, implant, missing, planned],
        ChartLayer.plan => const [planned, extraction],
        ChartLayer.perio => const [gum, pocket, bleeding],
        ChartLayer.endo => const [pulp, obturated, inProgress, lesion],
        ChartLayer.all => const [decay, filling, crown, planned, gum, pocket, obturated],
      };
}

/// The marks used in [layer], each with a small swatch drawn like the
/// chart draws it.
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.layer, this.trailing});

  final ChartLayer layer;

  /// A last quiet note ("Exam 12 Sep 2026").
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Wrap(
      spacing: CruSpace.s14,
      runSpacing: CruSpace.s8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final m in ChartMark.of(layer))
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(size: const Size.square(16), painter: _Swatch(m, c)),
              const SizedBox(width: CruSpace.s6),
              Text(m.label, style: CruType.caption.tint(c.label2)),
            ],
          ),
        if (trailing != null)
          Text(trailing!, style: CruType.caption.tabular.tint(c.label3)),
      ],
    );
  }
}

class _Swatch extends CustomPainter {
  _Swatch(this.mark, this.c);

  final ChartMark mark;
  final CruColors c;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final center = r.center;
    Paint stroke(Color color, [double w = 1.4]) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final tile = RRect.fromRectAndRadius(r.deflate(2), const Radius.circular(4));
    switch (mark) {
      case ChartMark.decay:
        canvas.drawCircle(
          center,
          6,
          Paint()
            ..shader = ui.Gradient.radial(center, 6, [
              c.caries,
              c.amber.withValues(alpha: 0.4),
              c.amber.withValues(alpha: 0),
            ], const [0, 0.6, 1]),
        );
      case ChartMark.filling:
        canvas.drawRRect(tile, Paint()..color = c.restoration);
        canvas.drawRRect(tile, stroke(c.greenText, 1));
      case ChartMark.crown:
        final p = smoothClosed([
          const Offset(3, 13),
          const Offset(2.5, 6),
          const Offset(5, 3),
          const Offset(8, 4.5),
          const Offset(11, 3),
          const Offset(13.5, 6),
          const Offset(13, 13),
        ]);
        canvas.drawPath(p, Paint()..color = c.restoration);
        canvas.drawPath(p, stroke(c.greenText, 1));
      case ChartMark.canal || ChartMark.obturated:
        canvas.drawLine(const Offset(8, 2), const Offset(8, 14), stroke(c.greenText, 2.4));
      case ChartMark.implant:
        final body = RRect.fromLTRBR(5, 2, 11, 14, const Radius.circular(2.5));
        canvas.drawRRect(body, Paint()..color = c.implantMetal);
        for (var y = 4.5; y < 13; y += 2.5) {
          canvas.drawLine(Offset(5, y), Offset(11, y + 1), stroke(Color.lerp(c.implantMetal, c.toothShadow, 0.45)!, 0.9));
        }
      case ChartMark.missing:
        dashPath(canvas, Path()..addRRect(tile), stroke(c.label3, 1), dash: 2.5, gap: 2);
      case ChartMark.planned:
        canvas.drawRRect(tile, Paint()..color = c.accentTint);
        dashPath(canvas, Path()..addRRect(tile), stroke(c.accent, 1.3), dash: 2.5, gap: 2);
      case ChartMark.extraction:
        canvas.drawLine(const Offset(3, 3), const Offset(13, 13), stroke(c.accent, 1.8));
        canvas.drawLine(const Offset(13, 3), const Offset(3, 13), stroke(c.accent, 1.8));
      case ChartMark.gum:
        final p = Path()..moveTo(1, 7);
        for (var x = 1.0; x < 15; x += 7) {
          p.quadraticBezierTo(x + 3.5, 13, x + 7, 7);
        }
        canvas.drawPath(p, stroke(c.gumShade, 1.6));
      case ChartMark.pocket:
        canvas.drawRRect(
          RRect.fromLTRBR(1, 4, 15, 12, const Radius.circular(3)),
          Paint()..color = c.amber.withValues(alpha: 0.42),
        );
        canvas.drawLine(const Offset(1, 4), const Offset(15, 4), stroke(c.gumShade, 1.4));
      case ChartMark.bleeding:
        canvas.drawCircle(center, 4, Paint()..color = c.amber);
      case ChartMark.pulp:
        canvas.drawPath(
          smoothClosed([const Offset(8, 2), const Offset(11, 6), const Offset(9, 14), const Offset(7, 14), const Offset(5, 6)]),
          Paint()..color = c.pulp,
        );
      case ChartMark.inProgress:
        dashPath(
          canvas,
          Path()
            ..moveTo(8, 2)
            ..lineTo(8, 14),
          stroke(c.amberText, 2.2)..strokeCap = StrokeCap.butt,
          dash: 3,
          gap: 2,
        );
      case ChartMark.lesion:
        canvas.drawCircle(
          center,
          7,
          Paint()
            ..shader = ui.Gradient.radial(center, 7, [
              c.amber.withValues(alpha: 0.7),
              c.amber.withValues(alpha: 0),
            ]),
        );
        canvas.drawCircle(center, 1.6, Paint()..color = c.amberText);
    }
  }

  @override
  bool shouldRepaint(_Swatch old) => old.mark != mark || old.c != c;
}
