import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/core/pdf/presentation/editor/template_editor_controller.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_template.dart';

void main() {
  group('TemplateEditorController', () {
    late DocBlock testBlock;
    late DocTemplate baseTemplate;
    late TemplateEditorController ctrl;

    setUp(() {
      testBlock = const DocBlock(
        id: 'b1',
        type: DocBlockType.field,
        field: 'clinic.name',
        zone: DocZone.header,
        x: 0,
        y: 0,
        w: 20,
        h: 10,
        fontPt: 10,
      );

      baseTemplate = DocTemplate(
        id: 't_test',
        name: 'Test Template',
        paper: const DocPaper(
          format: DocPaperFormat.a4,
          widthMm: 210,
          heightMm: 297,
          margins: DocMargins.all(12),
        ),
        headerMm: 50,
        footerMm: 20,
        blocks: [testBlock],
      );

      ctrl = TemplateEditorController(baseTemplate);
      ctrl.select('b1');
    });

    test('move snaps to the zone centre within 1.5 mm', () {
      // Zone content width = 210 - 24 = 186 mm.
      // Zone centre = 93.0 mm.
      // Block width = 20 mm. Its centre = x + 10 mm.
      // If we move so that start + 10 = 93.8 (x = 83.8), distance to 93.0 is 0.8 mm (< 1.5 mm).
      ctrl.snap = true;
      ctrl.moveTo(testBlock, 83.8, 0);

      final updated = ctrl.selected!;
      // Snapped to centre: x + 10 == 93.0 => x == 83.0
      expect(updated.x, 83.0);
      expect(ctrl.guideX, contains(93.0));
      expect(ctrl.guideZone, DocZone.header);
    });

    test('move clamps inside the zone', () {
      ctrl.snap = false;

      // Negative coordinates clamp to 0
      ctrl.moveTo(testBlock, -50, -30);
      expect(ctrl.selected!.x, 0.0);
      expect(ctrl.selected!.y, 0.0);

      // Positive coordinates clamp to (contentWidth - w) and (zoneHeight - h)
      // Content width = 186, block w = 20 => max x = 166.0
      // Header height = 50, block h = 10 => max y = 40.0
      ctrl.moveTo(testBlock, 300, 200);
      expect(ctrl.selected!.x, 166.0);
      expect(ctrl.selected!.y, 40.0);
    });

    test("resize keeps an image's aspect ratio", () {
      const imgBlock = DocBlock(
        id: 'img1',
        type: DocBlockType.image,
        imageRole: DocImageRole.logo,
        zone: DocZone.header,
        x: 10,
        y: 10,
        w: 20,
        h: 20,
      );

      final t = baseTemplate.copyWith(blocks: [imgBlock]);
      final c = TemplateEditorController(t);
      c.select('img1');

      // Drag bottom-right corner by dx = 10, dy = 0
      // Since ratio is 1.0 (20/20), height must also become 30.0
      c.resize(imgBlock, DocHandle.br, 10, 0);
      expect(c.selected!.w, 30.0);
      expect(c.selected!.h, 30.0);
    });

    test('resize never goes below 4 x 3 mm (or 0.5 mm line)', () {
      // Test field block min size 4 x 3 mm
      ctrl.resize(testBlock, DocHandle.br, -19, -9);
      expect(ctrl.selected!.w, 4.0);
      expect(ctrl.selected!.h, 3.0);

      // Test line block min height 0.5 mm
      const lineBlock = DocBlock(
        id: 'line1',
        type: DocBlockType.line,
        zone: DocZone.header,
        x: 0,
        y: 0,
        w: 50,
        h: 2,
      );
      final t = baseTemplate.copyWith(blocks: [lineBlock]);
      final c = TemplateEditorController(t);
      c.select('line1');

      c.resize(lineBlock, DocHandle.br, -49, -1.9);
      expect(c.selected!.w, 4.0);
      expect(c.selected!.h, 0.5);
    });

    test("header height can't leave the body under 40 mm", () {
      // Content height = 297 - 24 = 273 mm.
      // Footer = 20 mm.
      // Body minimum = 40 mm.
      // Max header = 273 - 20 - 40 = 213 mm.
      ctrl.setZoneHeight(DocZone.header, 250);
      expect(ctrl.template.headerMm, 213.0);
    });

    test('A4 -> A5 scales blocks by 132/186', () {
      // A4 content width: 210 - 24 = 186 mm
      // A5 content width: 148 - 16 = 132 mm (DocPaper.a5 margins: 8 mm)
      const b = DocBlock(
        id: 'b2',
        type: DocBlockType.field,
        field: 'clinic.name',
        zone: DocZone.header,
        x: 93,
        y: 10,
        w: 20,
        h: 10,
        fontPt: 10,
      );

      final t = baseTemplate.copyWith(blocks: [b]);
      final c = TemplateEditorController(t);

      const a5Paper = DocPaper(
        format: DocPaperFormat.a5,
        widthMm: 148,
        heightMm: 210,
        margins: DocMargins.all(8),
      );
      c.setPaper(a5Paper);

      final expectedF = 132.0 / 186.0;
      final scaled = c.template.blocks.first;
      expect(scaled.x, TemplateEditorController.r1(93 * expectedF));
      expect(scaled.w, TemplateEditorController.r1(20 * expectedF));
      expect(scaled.h, TemplateEditorController.r1(10 * expectedF));
    });

    test('undo/redo restore exact JSON', () {
      final initialJson = jsonEncode(ctrl.template.toMap());

      // Perform a modification
      ctrl.nudge(10, 5);
      expect(ctrl.canUndo, isTrue);
      expect(jsonEncode(ctrl.template.toMap()), isNot(equals(initialJson)));

      // Undo restores exact initial JSON
      ctrl.undo();
      expect(jsonEncode(ctrl.template.toMap()), equals(initialJson));
      expect(ctrl.canRedo, isTrue);

      // Redo restores modified state
      ctrl.redo();
      expect(jsonEncode(ctrl.template.toMap()), isNot(equals(initialJson)));
      expect(ctrl.selected!.x, 10.0);
      expect(ctrl.selected!.y, 5.0);
    });

    test('a press without move adds no undo entry', () {
      expect(ctrl.canUndo, isFalse);

      // Selecting blocks or selecting null
      ctrl.select('b1');
      expect(ctrl.canUndo, isFalse);

      ctrl.select(null);
      expect(ctrl.canUndo, isFalse);

      // On a drag, checkpoint is only called on the first move
      // When only press occurs (no moveTo or resize), checkpoint is not called
      expect(ctrl.canUndo, isFalse);

      // Simulating first move
      ctrl.checkpoint();
      ctrl.moveTo(testBlock, 5, 0);
      expect(ctrl.canUndo, isTrue);
    });
  });
}
