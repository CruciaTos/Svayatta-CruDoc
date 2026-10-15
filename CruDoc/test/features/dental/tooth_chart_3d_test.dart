import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crudoc_shared/theme/cru_theme.dart';
import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/jaw_model.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_anatomy.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_3d.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';

const _size = Size(900, 540);

/// Where a model point lands in the chart's front view (yaw 0, pitch
/// 0.14, 150 mm away; see ToothChart3D's front pose).
Offset _front(V3 p) {
  const pitch = 0.14, dist = 150.0;
  final y = p.y * math.cos(pitch) - p.z * math.sin(pitch);
  final z = p.y * math.sin(pitch) + p.z * math.cos(pitch) - dist;
  final focal = math.min(_size.width, _size.height) * 1.8;
  return Offset(
    _size.width / 2 + focal * p.x / -z,
    _size.height / 2 + 8 - focal * y / -z,
  );
}

void main() {
  late List<String> selected;
  late List<String> opened;

  Future<void> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 640);
    addTearDown(tester.view.reset);
    selected = [];
    opened = [];
    String? current;
    await tester.pumpWidget(
      MaterialApp(
        theme: CruTheme.day(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: _size.width,
              child: StatefulBuilder(
                builder: (context, setState) => ToothChart3D(
                  data: ToothChartData({
                    '24': const ToothVisual(
                      number: '24',
                      state: ToothState.treated,
                      treatment: ToothTreatment.filling,
                    ),
                  }),
                  child: false,
                  mode: ChartMode.findings,
                  selected: current,
                  onSelect: (t) => setState(() {
                    current = t;
                    selected.add(t);
                  }),
                  onOpen: opened.add,
                  height: _size.height,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Offset at(WidgetTester tester, V3 p) =>
      tester.getTopLeft(find.byType(ToothChart3D)) + _front(p);

  testWidgets('a tap on a crown selects that tooth', (tester) async {
    await pump(tester);
    final f = JawModel.of(child: false).frames['21']!;
    await tester.tapAt(
      at(tester, f.base + f.axis * (f.spec.crown * 0.5) + f.outward * 2),
    );
    await tester.pump();
    expect(selected, ['21']);
  });

  testWidgets('the jaw bone does not hide the roots from a tap', (
    tester,
  ) async {
    await pump(tester);
    final f = JawModel.of(child: false).frames['21']!;
    // Halfway up the root, under the frosted bone.
    await tester.tapAt(
      at(tester, f.base + f.axis * (f.spec.crown + f.spec.root * 0.45)),
    );
    await tester.pump();
    expect(selected, ['21']);
  });

  testWidgets('a tap beside the jaws selects nothing', (tester) async {
    await pump(tester);
    await tester.tapAt(
      tester.getTopLeft(find.byType(ToothChart3D)) +
          Offset(24, _size.height / 2),
    );
    await tester.pump();
    expect(selected, isEmpty);
  });

  testWidgets('a callout names the finding and selects its tooth', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('24'), findsOneWidget);
    await tester.tap(find.text('Filling'));
    await tester.pump();
    expect(selected, ['24']);
  });

  testWidgets('Enter opens the selected tooth', (tester) async {
    await pump(tester);
    final f = JawModel.of(child: false).frames['11']!;
    await tester.tapAt(
      at(tester, f.base + f.axis * (f.spec.crown * 0.5) + f.outward * 2),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, ['11']);
    expect(opened, ['11']);
  });

  test('both jaws are built for adult and milk teeth', () {
    for (final child in [false, true]) {
      final model = JawModel.of(child: child);
      final (upper, lower) = ToothSpec.arches(child: child);
      expect(model.frames.keys, unorderedEquals([...upper, ...lower]));
      // Every tooth has its crown, root and implant; the bone is the
      // upper jaw, the palate and the lower jaw.
      for (final material in MeshMaterial.values) {
        final parts = model.parts.where((p) => p.material == material);
        expect(
          parts.length,
          material == MeshMaterial.bone ? 3 : upper.length + lower.length,
        );
      }
      for (final part in model.parts) {
        final n = part.vertexCount;
        expect(part.triangles.every((i) => i >= 0 && i < n), isTrue);
        final tooth = part.tooth;
        // Lower teeth move with the lower jaw when the mouth opens.
        if (tooth != null) expect(part.lower, !ToothSpec.of(tooth).upper);
      }
      expect(
        model.parts.where((p) => p.material == MeshMaterial.bone && p.lower),
        hasLength(1),
      );
    }
  });
}
