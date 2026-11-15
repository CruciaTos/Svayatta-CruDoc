import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/vector_teeth/vector_tooth.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/vector_teeth/vector_tooth_painter.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Review sheets for the vector tooth library (PNG, look at them).
void main() {
  testWidgets('renders vector tooth sheets', (tester) async {
    final loader = FontLoader('Geist');
    for (final w in ['Regular', 'SemiBold']) {
      loader.addFont(rootBundle.load('assets/fonts/Geist/Geist-$w.ttf'));
    }
    await loader.load();

    final out = Directory('dental3d/tmp/chart2d/vector');
    if (!out.existsSync()) out.createSync(recursive: true);

    for (final dark in [false, true]) {
      final name = dark ? 'dark' : 'light';
      final colors = dark ? CruColors.evening : CruColors.day;
      await _sheet(
        tester,
        File('${out.path}/row_adult_$name.png'),
        colors,
        (cv, size) => _rowChart(
          cv,
          size,
          colors,
          upper: DentalChart.adultUpper,
          lower: DentalChart.adultLower,
          k: 11,
          gap: 1.2,
        ),
        size: const Size(2100, 1500),
      );
      await _sheet(
        tester,
        File('${out.path}/row_milk_$name.png'),
        colors,
        (cv, size) => _rowChart(
          cv,
          size,
          colors,
          upper: DentalChart.childUpper,
          lower: DentalChart.childLower,
          k: 16,
          gap: 1.4,
        ),
        size: const Size(1900, 1200),
      );
    }
    for (final dark in [false, true]) {
      final name = dark ? 'dark' : 'light';
      final colors = dark ? CruColors.evening : CruColors.day;
      await _sheet(
        tester,
        File('${out.path}/zoom_$name.png'),
        colors,
        (cv, size) => _zoom(cv, size, colors),
        size: const Size(2700, 1700),
      );
    }
  });
}

Future<void> _sheet(
  WidgetTester tester,
  File file,
  CruColors colors,
  void Function(Canvas, Size) draw, {
  required Size size,
}) async {
  final rec = ui.PictureRecorder();
  final cv = Canvas(rec, Offset.zero & size);
  cv.drawRect(Offset.zero & size, Paint()..color = colors.surface);
  draw(cv, size);
  final pic = rec.endRecording();
  await tester.runAsync(() async {
    final img = await pic.toImage(size.width.toInt(), size.height.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void _label(Canvas cv, String s, Offset c, Color col, double fs) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(fontFamily: 'Geist', fontSize: fs, color: col, fontWeight: FontWeight.w600),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(cv, c - Offset(tp.width / 2, tp.height / 2));
}

void _rowChart(
  Canvas cv,
  Size size,
  CruColors c, {
  required List<String> upper,
  required List<String> lower,
  required double k,
  required double gap,
}) {
  List<double> xs(List<String> row) {
    var x = 0.0;
    final out = <double>[];
    for (final n in row) {
      final t = VectorTooth.of(int.parse(n));
      out.add(x + t.dims.crownW / 2);
      x += t.dims.crownW + gap;
    }
    final total = x - gap;
    return [for (final v in out) v - total / 2];
  }

  final cx = size.width / 2;
  final upperXs = xs(upper);
  final lowerXs = xs(lower);
  final uBite = size.height * 0.37;
  final uOcc = size.height * 0.46;
  final lOcc = size.height * 0.56;
  final lBite = size.height * 0.65;
  for (var i = 0; i < upper.length; i++) {
    final t = VectorTooth.of(int.parse(upper[i]));
    VectorToothPainter.paintBuccal(
      cv, t,
      anchor: Offset(cx + upperXs[i] * k, uBite),
      scale: k,
      colors: c,
      rootsUp: true,
    );
    VectorToothPainter.paintOcclusal(
      cv, t,
      center: Offset(cx + upperXs[i] * k, uOcc),
      scale: k,
      colors: c,
    );
    _label(cv, upper[i], Offset(cx + upperXs[i] * k, 30), c.label3, 14);
  }
  for (var i = 0; i < lower.length; i++) {
    final t = VectorTooth.of(int.parse(lower[i]));
    VectorToothPainter.paintOcclusal(
      cv, t,
      center: Offset(cx + lowerXs[i] * k, lOcc),
      scale: k,
      colors: c,
    );
    VectorToothPainter.paintBuccal(
      cv, t,
      anchor: Offset(cx + lowerXs[i] * k, lBite),
      scale: k,
      colors: c,
    );
    _label(cv, lower[i], Offset(cx + lowerXs[i] * k, size.height - 30), c.label3, 14);
  }
}

void _zoom(Canvas cv, Size size, CruColors c) {
  const k = 28.0;
  const teeth = [11, 13, 14, 16, 36, 46];
  final colW = size.width / teeth.length;
  for (var i = 0; i < teeth.length; i++) {
    final t = VectorTooth.of(teeth[i]);
    final x = colW * (i + 0.5);
    _label(cv, '${teeth[i]}', Offset(x, 30), c.label3, 18);
    if (t.upper) {
      VectorToothPainter.paintBuccal(
        cv, t,
        anchor: Offset(x, 1000),
        scale: k,
        colors: c,
        rootsUp: true,
      );
    } else {
      VectorToothPainter.paintBuccal(
        cv, t,
        anchor: Offset(x, 110),
        scale: k,
        colors: c,
      );
    }
    VectorToothPainter.paintOcclusal(
      cv, t,
      center: Offset(x, 1430),
      scale: k * 1.0,
      colors: c,
    );
  }
}
