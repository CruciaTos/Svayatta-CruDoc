import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_anatomy.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_art.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_2d.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_arches.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/odontogram_picture_chart.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_arches_3d.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_arches_vector.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_textures.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/records/perio_chart_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Raise (e.g. 2.5) to inspect edges closely; keep 1.0 otherwise.
const double _pixelRatio = 1.0;

void main() {
  testWidgets('renders tooth chart sheets A, B, C, D and Arches', (tester) async {
    final loader = FontLoader('Geist');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Geist/Geist-$w.ttf'));
    }
    await loader.load();

    final outDirAfter = Directory('dental3d/tmp/chart2d/after');
    if (!outDirAfter.existsSync()) {
      outDirAfter.createSync(recursive: true);
    }
    final outDirArches = Directory('dental3d/tmp/chart2d/arches');
    if (!outDirArches.existsSync()) {
      outDirArches.createSync(recursive: true);
    }

    await tester.runAsync(() async {
      await ToothTextures.instance.ensureLoaded();
    });
    expect(
      ToothTextures.instance.of('48'),
      isNotNull,
      reason: 'Tooth textures failed to load',
    );

    // ==================== Sheets A, B, C ====================
    for (final isDark in [false, true]) {
      final themeName = isDark ? 'dark' : 'light';
      final colors = isDark ? CruColors.evening : CruColors.day;

      await _renderSheetA(
        tester,
        File('${outDirAfter.path}/sheet_a_$themeName.png'),
        colors: colors,
        textures: ToothTextures.instance,
      );

      await _renderSheetB(
        tester,
        File('${outDirAfter.path}/sheet_b_$themeName.png'),
        colors: colors,
        textures: ToothTextures.instance,
      );

      await _renderSheetC(
        tester,
        File('${outDirAfter.path}/sheet_c_$themeName.png'),
        colors: colors,
        textures: ToothTextures.instance,
      );
    }

    // ==================== Sample Data for Sheet D and Arches ====================
    PerioTooth makePerio({
      required List<int?> pd,
      required List<int?> rec,
      required List<bool> bop,
      int? mobility,
      int? furcation,
    }) {
      final t = PerioTooth();
      for (var i = 0; i < 6; i++) {
        if (i < pd.length) t.pd[i] = pd[i];
        if (i < rec.length) t.rec[i] = rec[i];
        if (i < bop.length) t.bop[i] = bop[i];
      }
      t.mobility = mobility;
      t.furcation = furcation;
      return t;
    }

    final endo11 = EndoState(
      record: DentalRecord.create('p1', RecKind.endo, {
        'tooth': '11',
        'status': 'obturated',
        'canals': ['MB', 'DB', 'P'],
        'pulpal': 'Previously treated',
        'periapical': 'Normal apical tissues',
      }),
      obturated: true,
      canals: 3,
      pulpal: 'Previously treated',
      periapical: 'Normal apical tissues',
    );
    final endo46 = EndoState(
      record: DentalRecord.create('p1', RecKind.endo, {
        'tooth': '46',
        'status': 'inProgress',
        'canals': ['M', 'D'],
        'pulpal': 'Pulp necrosis',
        'periapical': 'Chronic apical periodontitis',
      }),
      obturated: false,
      canals: 2,
      pulpal: 'Pulp necrosis',
      periapical: 'Chronic apical periodontitis',
    );

    final samplePerioExam = DentalRecord.create('p1', RecKind.perio, {
      'teeth': {
        '16': makePerio(
          pd: [4, 5, 4, 3, 3, 4],
          rec: [1, 2, 1, 0, 0, 1],
          bop: [true, true, false, false, false, true],
          mobility: 1,
        ).toJson(),
        '11': makePerio(
          pd: [3, 2, 3, 2, 2, 2],
          rec: [1, 1, 0, 0, 0, 0],
          bop: [false, false, false, false, false, false],
        ).toJson(),
        '21': makePerio(
          pd: [3, 3, 4, 2, 2, 3],
          rec: [0, 1, 1, 0, 0, 0],
          bop: [false, true, true, false, false, false],
        ).toJson(),
        '26': makePerio(
          pd: [5, 6, 5, 4, 4, 4],
          rec: [2, 2, 1, 1, 1, 1],
          bop: [true, true, true, false, false, true],
          furcation: 1,
        ).toJson(),
        '36': makePerio(
          pd: [4, 4, 5, 3, 3, 4],
          rec: [1, 1, 2, 0, 0, 1],
          bop: [true, false, true, false, false, false],
        ).toJson(),
        '46': makePerio(
          pd: [5, 4, 4, 3, 3, 3],
          rec: [2, 1, 1, 0, 0, 0],
          bop: [true, true, false, false, false, false],
        ).toJson(),
      },
    });

    final sampleTeeth = <String, ToothVisual>{
      '16': ToothVisual(
        number: '16',
        state: ToothState.treated,
        treatment: ToothTreatment.crown,
        perio: makePerio(
          pd: [4, 5, 4, 3, 3, 4],
          rec: [1, 2, 1, 0, 0, 1],
          bop: [true, true, false, false, false, true],
          mobility: 1,
        ),
      ),
      '14': const ToothVisual(
        number: '14',
        state: ToothState.needsCare,
        condition: ToothCondition.caries,
        surfaces: [ToothSurface.mesial, ToothSurface.occlusal],
      ),
      '15': const ToothVisual(
        number: '15',
        state: ToothState.treated,
        treatment: ToothTreatment.filling,
        surfaces: [ToothSurface.occlusal],
      ),
      '12': const ToothVisual(
        number: '12',
        state: ToothState.healthy,
        planned: ['Crown'],
        plannedWork: [ToothTreatment.crown],
      ),
      '11': ToothVisual(
        number: '11',
        state: ToothState.treated,
        treatment: ToothTreatment.rct,
        endo: endo11,
        perio: makePerio(
          pd: [3, 2, 3, 2, 2, 2],
          rec: [1, 1, 0, 0, 0, 0],
          bop: [false, false, false, false, false, false],
        ),
      ),
      '21': ToothVisual(
        number: '21',
        state: ToothState.needsCare,
        condition: ToothCondition.fractured,
        perio: makePerio(
          pd: [3, 3, 4, 2, 2, 3],
          rec: [0, 1, 1, 0, 0, 0],
          bop: [false, true, true, false, false, false],
        ),
      ),
      '26': ToothVisual(
        number: '26',
        state: ToothState.treated,
        treatment: ToothTreatment.implant,
        perio: makePerio(
          pd: [5, 6, 5, 4, 4, 4],
          rec: [2, 2, 1, 1, 1, 1],
          bop: [true, true, true, false, false, true],
          furcation: 1,
        ),
      ),
      '34': const ToothVisual(
        number: '34',
        state: ToothState.healthy,
        planned: ['Resin filling'],
        plannedWork: [ToothTreatment.filling],
      ),
      '35': const ToothVisual(
        number: '35',
        state: ToothState.missing,
      ),
      '36': ToothVisual(
        number: '36',
        state: ToothState.treated,
        treatment: ToothTreatment.crown,
        perio: makePerio(
          pd: [4, 4, 5, 3, 3, 4],
          rec: [1, 1, 2, 0, 0, 1],
          bop: [true, false, true, false, false, false],
        ),
      ),
      '44': const ToothVisual(
        number: '44',
        state: ToothState.treated,
        treatment: ToothTreatment.filling,
        surfaces: [ToothSurface.occlusal],
      ),
      '45': const ToothVisual(
        number: '45',
        state: ToothState.needsCare,
        condition: ToothCondition.caries,
        surfaces: [ToothSurface.occlusal],
      ),
      '46': ToothVisual(
        number: '46',
        state: ToothState.treated,
        treatment: ToothTreatment.rct,
        endo: endo46,
        perio: makePerio(
          pd: [5, 4, 4, 3, 3, 3],
          rec: [2, 1, 1, 0, 0, 0],
          bop: [true, true, false, false, false, false],
        ),
      ),
    };

    final sampleData = ToothChartData(sampleTeeth, perioExam: samplePerioExam);

    // ==================== Sheet D (ToothChart2D widget at 1100 px) ====================
    for (final layer in [
      ChartLayer.dental,
      ChartLayer.plan,
      ChartLayer.perio,
      ChartLayer.endo,
    ]) {
      for (final isDark in [false, true]) {
        final themeName = isDark ? 'dark' : 'light';
        final colors = isDark ? CruColors.evening : CruColors.day;

        await _captureWidget(
          tester,
          _wrapWidget(
            child: ToothChart2D(
              data: sampleData,
              child: false,
              selected: '16',
              onSelect: (_) {},
              layer: layer,
            ),
            colors: colors,
            width: 1100,
          ),
          const Size(1100, 620),
          File('${outDirAfter.path}/sheet_d_${layer.name}_$themeName.png'),
        );
      }
    }

    await tester.runAsync(loadOdontogramPictures);
    // ==================== Arches Sheets (360 px and 900 px) ====================
    for (final width in [360.0, 900.0]) {
      final widthLabel = width.toInt().toString();
      for (final isDark in [false, true]) {
        final themeName = isDark ? 'dark' : 'light';
        final colors = isDark ? CruColors.evening : CruColors.day;

        final h = width == 360.0 ? 840.0 : 1020.0;
        await _captureWidget(
          tester,
          _wrapWidget(
            child: ToothChartArches(
              data: sampleData,
              child: false,
              selected: '16',
              onSelect: (_) {},
              layer: ChartLayer.dental,
            ),
            colors: colors,
            width: width,
          ),
          Size(width, h),
          File('${outDirArches.path}/arches_${widthLabel}_$themeName.png'),
        );
      }
    }

    // ==================== 3D odontogram (360 px) ====================
    for (final isDark in [false, true]) {
      final themeName = isDark ? 'dark' : 'light';
      await _captureWidget(
        tester,
        _wrapWidget(
          child: ToothChartArches3d(
            data: sampleData,
            child: false,
            selected: '16',
            onSelect: (_) {},
            layer: ChartLayer.dental,
          ),
          colors: isDark ? CruColors.evening : CruColors.day,
          width: 360,
        ),
        const Size(360, 840),
        File('${outDirArches.path}/arches3d_360_$themeName.png'),
      );
    }

    await _captureWidget(
      tester,
      _wrapWidget(
        child: ToothChartArches3d(
          data: sampleData,
          child: false,
          selected: '16',
          onSelect: (_) {},
          layer: ChartLayer.dental,
        ),
        colors: CruColors.day,
        width: 900,
      ),
      const Size(900, 1020),
      File('${outDirArches.path}/arches3d_900_light.png'),
    );

    // ==================== Layout checks ====================
    // Row chart: no tooth's box overlaps its neighbour's, at any width.
    for (final w in [360.0, 600.0, 900.0, 1100.0, 1400.0]) {
      for (final child in [false, true]) {
        for (final rows in ChartRows.values) {
          for (final row in toothChartBoxes(w, child: child, rows: rows)) {
            for (var i = 1; i < row.length; i++) {
              expect(
                row[i - 1].right,
                lessThanOrEqualTo(row[i].left + 0.01),
                reason: 'row chart w=$w child=$child $rows: tooth $i overlaps '
                    'tooth ${i - 1} (${row[i - 1]} / ${row[i]})',
              );
            }
          }
        }
      }
    }
    // Odontogram: a clear gap between the arches, each number inside its own
    // tooth and off every other tooth and number.
    for (final w in [360.0, 600.0, 900.0]) {
      for (final child in [false, true]) {
        final l = archChartLayout(w, child: child);
        expect(l.gap, greaterThanOrEqualTo(24), reason: 'arch gap at w=$w');
        for (final (n, own, box) in l.teeth) {
          expect(
            own.contains(box.center),
            isTrue,
            reason: 'number $n is off its tooth at w=$w child=$child',
          );
          for (final (m, outline, _) in l.teeth) {
            if (m == n) continue;
            for (final p in [
              box.topLeft,
              box.topRight,
              box.bottomLeft,
              box.bottomRight,
              box.center,
            ]) {
              expect(
                outline.contains(p),
                isFalse,
                reason: 'number $n sits on tooth $m at w=$w child=$child',
              );
            }
          }
          for (final (m, _, other) in l.teeth) {
            if (m == n) continue;
            expect(
              box.overlaps(other),
              isFalse,
              reason: 'numbers $n and $m overlap at w=$w child=$child',
            );
          }
        }
      }
    }
  });
}

Widget _wrapWidget({
  required Widget child,
  required CruColors colors,
  required double width,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      fontFamily: 'Geist',
      extensions: [colors],
      scaffoldBackgroundColor: colors.surface,
    ),
    home: Scaffold(
      backgroundColor: colors.surface,
      body: Center(
        child: SizedBox(
          width: width,
          child: child,
        ),
      ),
    ),
  );
}

Future<void> _captureWidget(
  WidgetTester tester,
  Widget widget,
  Size size,
  File file,
) async {
  await tester.binding.setSurfaceSize(size);
  final repaintKey = GlobalKey();
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size),
      child: RepaintBoundary(
        key: repaintKey,
        child: widget,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  await tester.runAsync(() async {
    final boundary =
        repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    await file.writeAsBytes(byteData!.buffer.asUint8List());
  });
}

void _drawText(
  Canvas canvas,
  String text,
  Offset center,
  Color color, {
  double fontSize = 11,
  FontWeight fontWeight = FontWeight.normal,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: 'Geist',
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}

Future<void> _renderSheetA(
  WidgetTester tester,
  File file, {
  required CruColors colors,
  required ToothTextures textures,
}) async {
  const k = 6.0;
  final recorder = ui.PictureRecorder();

  const leftMargin = 40.0;
  const gap = 1.2 * k;

  const upperEdgeY = 200.0;
  const lowerEdgeY = 260.0;

  final upperXs = <String, double>{};
  var xUpper = leftMargin;
  for (final n in DentalChart.adultUpper) {
    final spec = ToothSpec.of(n);
    final s0 = BuccalShape.of(spec, k: k, cx: 0, edgeY: upperEdgeY);
    final w = s0.crownRect.width;
    upperXs[n] = xUpper + w / 2;
    xUpper += w + gap;
  }

  final lowerXs = <String, double>{};
  var xLower = leftMargin;
  for (final n in DentalChart.adultLower) {
    final spec = ToothSpec.of(n);
    final s0 = BuccalShape.of(spec, k: k, cx: 0, edgeY: lowerEdgeY);
    final w = s0.crownRect.width;
    lowerXs[n] = xLower + w / 2;
    xLower += w + gap;
  }

  final width = (math.max(xUpper, xLower) + leftMargin - gap).ceilToDouble();
  const height = 480.0;

  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height),
    Paint()..color = colors.surface,
  );

  final midX = width / 2;
  canvas.drawLine(
    Offset(midX, 20),
    Offset(midX, height - 20),
    Paint()
      ..color = colors.separator
      ..strokeWidth = 1.0,
  );

  for (final n in DentalChart.adultUpper) {
    final spec = ToothSpec.of(n);
    final cx = upperXs[n]!;
    final shape = BuccalShape.of(spec, k: k, cx: cx, edgeY: upperEdgeY);
    ToothArt.buccal(
      canvas,
      shape,
      const ToothLook(),
      colors,
      texture: textures.of(n),
    );
    _drawText(
      canvas,
      n,
      Offset(cx, 25),
      colors.label3,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
  }

  for (final n in DentalChart.adultLower) {
    final spec = ToothSpec.of(n);
    final cx = lowerXs[n]!;
    final shape = BuccalShape.of(spec, k: k, cx: cx, edgeY: lowerEdgeY);
    ToothArt.buccal(
      canvas,
      shape,
      const ToothLook(),
      colors,
      texture: textures.of(n),
    );
    _drawText(
      canvas,
      n,
      Offset(cx, height - 25),
      colors.label3,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
  }

  final picture = recorder.endRecording();
  await tester.runAsync(() async {
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    await file.writeAsBytes(byteData!.buffer.asUint8List());
  });
}

Future<void> _renderSheetB(
  WidgetTester tester,
  File file, {
  required CruColors colors,
  required ToothTextures textures,
}) async {
  const k = 6.0;
  final recorder = ui.PictureRecorder();

  const leftMargin = 40.0;
  const gap = 1.2 * k;

  const upperCenterY = 100.0;
  const lowerCenterY = 190.0;

  final upperXs = <String, double>{};
  var xUpper = leftMargin;
  for (final n in DentalChart.adultUpper) {
    final spec = ToothSpec.of(n);
    final s0 = OcclusalShape.of(spec, k: k, center: Offset.zero);
    final w = s0.rect.width;
    upperXs[n] = xUpper + w / 2;
    xUpper += w + gap;
  }

  final lowerXs = <String, double>{};
  var xLower = leftMargin;
  for (final n in DentalChart.adultLower) {
    final spec = ToothSpec.of(n);
    final s0 = OcclusalShape.of(spec, k: k, center: Offset.zero);
    final w = s0.rect.width;
    lowerXs[n] = xLower + w / 2;
    xLower += w + gap;
  }

  final width = (math.max(xUpper, xLower) + leftMargin - gap).ceilToDouble();
  const height = 300.0;

  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height),
    Paint()..color = colors.surface,
  );

  final midX = width / 2;
  canvas.drawLine(
    Offset(midX, 20),
    Offset(midX, height - 20),
    Paint()
      ..color = colors.separator
      ..strokeWidth = 1.0,
  );

  for (final n in DentalChart.adultUpper) {
    final spec = ToothSpec.of(n);
    final cx = upperXs[n]!;
    final shape = OcclusalShape.of(
      spec,
      k: k,
      center: Offset(cx, upperCenterY),
    );
    ToothArt.occlusal(
      canvas,
      shape,
      const ToothLook(),
      colors,
      texture: textures.of(n),
    );
    _drawText(
      canvas,
      n,
      Offset(cx, 25),
      colors.label3,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
  }

  for (final n in DentalChart.adultLower) {
    final spec = ToothSpec.of(n);
    final cx = lowerXs[n]!;
    final shape = OcclusalShape.of(
      spec,
      k: k,
      center: Offset(cx, lowerCenterY),
    );
    ToothArt.occlusal(
      canvas,
      shape,
      const ToothLook(),
      colors,
      texture: textures.of(n),
    );
    _drawText(
      canvas,
      n,
      Offset(cx, height - 25),
      colors.label3,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
  }

  final picture = recorder.endRecording();
  await tester.runAsync(() async {
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    await file.writeAsBytes(byteData!.buffer.asUint8List());
  });
}

Future<void> _renderSheetC(
  WidgetTester tester,
  File file, {
  required CruColors colors,
  required ToothTextures textures,
}) async {
  const k = 6.0;
  final recorder = ui.PictureRecorder();

  const teeth = ['16', '11', '36', '46'];
  bool isFront(ToothSpec s) =>
      s.kind != ToothKind.premolar && s.kind != ToothKind.molar;

  final conditions = <(String, ToothLook Function(ToothSpec))>[
    (
      'Decay (2 surf)',
      (ToothSpec s) => ToothLook(
        decay: isFront(s)
            ? {ToothSurface.mesial, ToothSurface.incisal}
            : {ToothSurface.mesial, ToothSurface.occlusal},
      ),
    ),
    (
      'Filling',
      (ToothSpec s) => ToothLook(
        filled: isFront(s) ? {ToothSurface.mesial} : {ToothSurface.occlusal},
      ),
    ),
    ('Crown', (ToothSpec s) => const ToothLook(capped: true)),
    ('Root Canal', (ToothSpec s) => const ToothLook(rootCanal: true)),
    ('Implant', (ToothSpec s) => const ToothLook(implant: true)),
    ('Missing', (ToothSpec s) => const ToothLook(missing: true)),
    ('Fractured', (ToothSpec s) => const ToothLook(fractured: true)),
    ('Lesion', (ToothSpec s) => const ToothLook(lesion: true, pulp: true)),
    (
      'Planned',
      (ToothSpec s) => const ToothLook(planned: [ToothTreatment.crown]),
    ),
  ];

  const colWidth = 120.0;
  const rowHeaderWidth = 80.0;
  const colHeaderHeight = 50.0;
  const rowHeight = 260.0;

  final width = rowHeaderWidth + conditions.length * colWidth + 20.0;
  final height = colHeaderHeight + teeth.length * rowHeight + 20.0;

  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height),
    Paint()..color = colors.surface,
  );

  for (var c = 0; c < conditions.length; c++) {
    final cx = rowHeaderWidth + c * colWidth + colWidth / 2;
    _drawText(
      canvas,
      conditions[c].$1,
      Offset(cx, 25),
      colors.label,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
  }

  for (var r = 0; r < teeth.length; r++) {
    final toothNum = teeth[r];
    final spec = ToothSpec.of(toothNum);
    final cellTop = colHeaderHeight + r * rowHeight;
    final rowCenterY = cellTop + rowHeight / 2;

    _drawText(
      canvas,
      'Tooth $toothNum',
      Offset(rowHeaderWidth / 2, rowCenterY),
      colors.label,
      fontSize: 13,
      fontWeight: FontWeight.bold,
    );

    for (var c = 0; c < conditions.length; c++) {
      final cellLeft = rowHeaderWidth + c * colWidth;
      final cx = cellLeft + colWidth / 2;
      final look = conditions[c].$2(spec);

      canvas.drawRect(
        Rect.fromLTWH(cellLeft, cellTop, colWidth, rowHeight),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = colors.separator.withValues(alpha: 0.5),
      );

      if (spec.upper) {
        final edgeY = cellTop + 155.0;
        final occCenterY = cellTop + 195.0;

        final buccal = BuccalShape.of(spec, k: k, cx: cx, edgeY: edgeY);
        ToothArt.buccal(
          canvas,
          buccal,
          look,
          colors,
          texture: textures.of(toothNum),
        );

        final occlusal = OcclusalShape.of(
          spec,
          k: k,
          center: Offset(cx, occCenterY),
        );
        ToothArt.occlusal(
          canvas,
          occlusal,
          look,
          colors,
          texture: textures.of(toothNum),
        );
      } else {
        final occCenterY = cellTop + 50.0;
        final edgeY = cellTop + 95.0;

        final occlusal = OcclusalShape.of(
          spec,
          k: k,
          center: Offset(cx, occCenterY),
        );
        ToothArt.occlusal(
          canvas,
          occlusal,
          look,
          colors,
          texture: textures.of(toothNum),
        );

        final buccal = BuccalShape.of(spec, k: k, cx: cx, edgeY: edgeY);
        ToothArt.buccal(
          canvas,
          buccal,
          look,
          colors,
          texture: textures.of(toothNum),
        );
      }
    }
  }

  final picture = recorder.endRecording();
  await tester.runAsync(() async {
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    await file.writeAsBytes(byteData!.buffer.asUint8List());
  });
}
