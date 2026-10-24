import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/core/pdf/render/pdf_text.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_body_sections.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_presets.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_template.dart';

void main() {
  group('pdf_text formatting and conversions', () {
    test('rupeesInWords exact values', () {
      expect(
        rupeesInWords(125050),
        'Rupees One Thousand Two Hundred Fifty and Fifty Paise Only',
      );
      expect(
        rupeesInWords(12345678900),
        'Rupees Twelve Crore Thirty Four Lakh Fifty Six Thousand Seven Hundred Eighty Nine Only',
      );
      expect(rupeesInWords(0), 'Rupees Zero Only');
      expect(rupeesInWords(10000000), 'Rupees One Lakh Only');
      expect(rupeesInWords(1000000000), 'Rupees One Crore Only');
    });

    test('financialYear calculation', () {
      expect(financialYear(DateTime(2026, 3, 31)), '25-26');
      expect(financialYear(DateTime(2026, 4, 1)), '26-27');
    });

    test('formatPaise currency format', () {
      expect(formatPaise(12500000), '₹1,25,000');
      expect(formatPaise(125050), '₹1,250.50');
    });

    test('DocTemplate round-trips every builtin', () {
      for (final t in builtinTemplates) {
        final map = t.toMap();
        final restored = DocTemplate.fromMap(t.id, map);
        expect(restored.toMap(), equals(map));
      }
    });

    test('bodyFor drops unknown section ids and appends missing ones', () {
      final t = DocTemplate(
        id: 'test',
        name: 'Test',
        body: {
          DocKind.invoice: const [
            DocBodySection('unknown_id', visible: true),
            DocBodySection(DocSection.items, visible: false),
          ],
        },
      );
      final body = t.bodyFor(DocKind.invoice);
      // 'unknown_id' is dropped
      expect(body.any((s) => s.id == 'unknown_id'), isFalse);
      // Saved item is first with visible: false
      expect(body.first.id, DocSection.items);
      expect(body.first.visible, isFalse);
      // All other default invoice sections are appended
      final defaults = defaultBodySections(DocKind.invoice);
      for (final d in defaults) {
        expect(body.any((s) => s.id == d.id), isTrue);
      }
    });
  });
}
