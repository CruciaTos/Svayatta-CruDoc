import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/core/pdf/presentation/editor/editor_canvas.dart';
import 'package:doctor_management_app/core/pdf/presentation/editor/template_editor_controller.dart';
import 'package:doctor_management_app/core/pdf/render/doc_samples.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_presets.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_template.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The phone editor's page: the canvas inside a pinch-to-zoom view that
/// stops panning while an element is being dragged (as the screen does).
class _Host extends StatefulWidget {
  const _Host({required this.controller, required this.view});

  final TemplateEditorController controller;
  final TransformationController view;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool _locked = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.controller.template;
    return LayoutBuilder(
      builder: (context, box) {
        const pad = 16.0;
        final s = (box.maxWidth - pad * 2) / t.paper.widthMm;
        return InteractiveViewer(
          transformationController: widget.view,
          constrained: false,
          minScale: 1,
          maxScale: 4,
          panEnabled: !_locked,
          child: Padding(
            padding: const EdgeInsets.all(pad),
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) => EditorCanvas(
                controller: widget.controller,
                pxPerMm: s,
                previewCtx: docSampleContext(docSampleData(DocKind.invoice)),
                touch: true,
                onDragLock: (v) => setState(() => _locked = v),
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  TemplateEditorController ctrl,
  TransformationController view,
) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: CruTheme.day(),
      home: Scaffold(
        body: _Host(controller: ctrl, view: view),
      ),
    ),
  );
  await tester.pump();
}

DocBlock _clinicName(TemplateEditorController c) =>
    c.template.blocks.firstWhere((b) => b.field == 'clinic.name');

/// Centre of [b] on screen.
Offset _centreOf(WidgetTester tester, TemplateEditorController c, DocBlock b) {
  final t = c.template;
  final canvas = tester.getTopLeft(find.byType(EditorCanvas));
  final width = tester.getSize(find.byType(EditorCanvas)).width;
  final s = width / t.paper.widthMm;
  return canvas +
      Offset(
        (t.paper.margins.left + b.x + b.noLogoDx + b.w / 2) * s,
        (t.paper.margins.top + b.y + b.noLogoDy + b.h / 2) * s,
      );
}

void main() {
  test('size slider grows a block around its centre and keeps its shape', () {
    final c = TemplateEditorController(builtinById('builtin.classic'));
    // A new element goes in the middle of the header, with room to grow.
    expect(
      c.add(
        const DocBlock(
          id: '',
          type: DocBlockType.field,
          field: 'clinic.phone',
          x: 0,
          y: 0,
          w: 40,
          h: 6,
        ),
      ),
      isTrue,
    );
    final b = c.selected!;
    c.beginLive();
    c.setScaleLive(b.id, 1.2);
    c.endLive();
    final grown = c.template.blocks.firstWhere((x) => x.id == b.id);
    expect(c.scaleOf(grown), closeTo(1.2, 0.02));
    expect(grown.fontPt, closeTo(b.fontPt * 1.2, 0.1));
    expect(grown.x + grown.w / 2, closeTo(b.x + b.w / 2, 0.2));
    // One slide is one undo step.
    c.undo();
    expect(c.template.blocks.firstWhere((x) => x.id == b.id).w, b.w);
  });

  test('growing or moving a block keeps it on the page without a logo', () {
    final c = TemplateEditorController(builtinById('builtin.classic'));
    final zw = c.template.paper.contentWidthMm;
    bool onPage(DocBlock b) =>
        b.x >= 0 &&
        b.x + b.w <= zw + 0.05 &&
        b.x + b.noLogoDx >= 0 &&
        b.x + b.noLogoDx + b.w <= zw + 0.05;

    final b = _clinicName(c);
    expect(b.noLogoDx, isNot(0), reason: 'Classic slides it into the logo gap');
    c.beginLive();
    c.setScaleLive(b.id, 5); // past the largest size: clamps
    c.endLive();
    expect(onPage(_clinicName(c)), isTrue);

    c.moveTo(_clinicName(c), -500, 0);
    expect(onPage(_clinicName(c)), isTrue);
    c.moveTo(_clinicName(c), 500, 0);
    expect(onPage(_clinicName(c)), isTrue);
  });

  testWidgets('one finger moves an element', (tester) async {
    final ctrl = TemplateEditorController(builtinById('builtin.classic'));
    final view = TransformationController();
    await _pump(tester, ctrl, view);
    final before = _clinicName(ctrl);

    final g = await tester.startGesture(_centreOf(tester, ctrl, before));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(4, 0));
      await tester.pump();
    }
    await g.up();
    await tester.pump();

    expect(ctrl.selectedId, before.id);
    expect(_clinicName(ctrl).x, greaterThan(before.x + 3));
    expect(view.value.getMaxScaleOnAxis(), 1.0);
  });

  testWidgets('two fingers on the paper zoom in', (tester) async {
    final ctrl = TemplateEditorController(builtinById('builtin.classic'));
    final view = TransformationController();
    await _pump(tester, ctrl, view);

    // The middle of the body: no element there.
    final canvas = tester.getRect(find.byType(EditorCanvas));
    final mid = canvas.center;
    final a = await tester.startGesture(mid - const Offset(30, 0), pointer: 1);
    await tester.pump();
    final b = await tester.startGesture(mid + const Offset(30, 0), pointer: 2);
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await a.moveBy(const Offset(-8, 0));
      await b.moveBy(const Offset(8, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();

    expect(view.value.getMaxScaleOnAxis(), greaterThan(1.5));
    expect(ctrl.selectedId, isNull);
  });

  testWidgets('a second finger lets go of the element being dragged', (
    tester,
  ) async {
    final ctrl = TemplateEditorController(builtinById('builtin.classic'));
    final view = TransformationController();
    await _pump(tester, ctrl, view);
    final start = _clinicName(ctrl);

    final a = await tester.startGesture(
      _centreOf(tester, ctrl, start),
      pointer: 1,
    );
    for (var i = 0; i < 5; i++) {
      await a.moveBy(const Offset(4, 0));
      await tester.pump();
    }
    final afterDrag = _clinicName(ctrl).x;
    expect(afterDrag, greaterThan(start.x));

    // Second finger: from here on it's a pinch, not a drag.
    final b = await tester.startGesture(
      _centreOf(tester, ctrl, start) + const Offset(0, 160),
      pointer: 2,
    );
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await a.moveBy(const Offset(-6, -6));
      await b.moveBy(const Offset(6, 6));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();

    expect(_clinicName(ctrl).x, afterDrag);
    expect(view.value.getMaxScaleOnAxis(), greaterThan(1.2));
  });

  testWidgets('a receipt (no fixed page height) draws without errors', (
    tester,
  ) async {
    final ctrl = TemplateEditorController(builtinById('builtin.receipt80'));
    final view = TransformationController();
    await _pump(tester, ctrl, view);

    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(EditorCanvas));
    expect(size.height, greaterThan(size.width));

    // Tapping the receipt selects nothing and changes nothing.
    await tester.tapAt(tester.getCenter(find.byType(EditorCanvas)));
    await tester.pump();
    expect(ctrl.selectedId, isNull);
    expect(ctrl.template.headerMm, 0);
    expect(ctrl.dirty, isFalse);
  });
}
