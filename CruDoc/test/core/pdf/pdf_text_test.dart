import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/core/pdf/render/pdf_text.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_body_sections.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_presets.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_template.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_bill.dart';

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

  group('InvoiceTotals.of calculations', () {
    test('2 x ₹333.33 at 18% tax', () {
      final bill = InvoiceBill(
        items: [
          InvoiceBillItem(
            name: 'Consultation',
            qty: 2,
            ratePaise: 33333,
            taxPct: 18,
          ),
        ],
        roundOff: true,
      );
      final totals = InvoiceTotals.of(bill);
      expect(totals.subtotal, 66666);
      expect(totals.tax, 12000);
      expect(totals.roundOff, 34);
      expect(totals.grand, 78700);
    });

    test('₹1,000 discount on a ₹500 bill (capped)', () {
      final bill = InvoiceBill(
        items: [
          InvoiceBillItem(
            name: 'Consultation',
            qty: 1,
            ratePaise: 50000,
          ),
        ],
        discountPaise: 100000,
        roundOff: false,
      );
      final totals = InvoiceTotals.of(bill);
      expect(totals.subtotal, 50000);
      expect(totals.tax, 0);
      expect(totals.discount, 50000);
      expect(totals.grand, 0);
      expect(totals.balance, 0);
    });

    test('round off of ₹1,234.50 -> ₹1,235', () {
      final bill = InvoiceBill(
        items: [
          InvoiceBillItem(
            name: 'Treatment',
            qty: 1,
            ratePaise: 123450,
          ),
        ],
        roundOff: true,
      );
      final totals = InvoiceTotals.of(bill);
      expect(totals.subtotal, 123450);
      expect(totals.roundOff, 50);
      expect(totals.grand, 123500);
    });

    test('received more than total (capped)', () {
      final bill = InvoiceBill(
        items: [
          InvoiceBillItem(
            name: 'Procedure',
            qty: 1,
            ratePaise: 10000,
          ),
        ],
        paidPaise: 15000,
        roundOff: false,
      );
      final totals = InvoiceTotals.of(bill);
      expect(totals.grand, 10000);
      expect(totals.paid, 10000);
      expect(totals.balance, 0);
    });
  });
}
