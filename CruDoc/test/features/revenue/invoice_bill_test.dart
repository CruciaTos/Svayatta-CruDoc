import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/revenue/data/models/invoice_bill.dart';

void main() {
  group('InvoiceBill refunds', () {
    test('refundedPaise survives toJson / fromJson', () {
      const bill = InvoiceBill(
        items: [InvoiceBillItem(name: 'Scaling', ratePaise: 50000)],
        paidPaise: 50000,
        refundedPaise: 20000,
      );
      final back = InvoiceBill.fromJson(bill.toJson());
      expect(back.paidPaise, 50000);
      expect(back.refundedPaise, 20000);
    });

    test('an older bill without a refund field reads as 0 refunded', () {
      final back = InvoiceBill.fromJson(
        '{"v":1,"items":[{"name":"X","qty":1,"rate":1000}],"paid":1000}',
      );
      expect(back.refundedPaise, 0);
    });

    test('copyWith changes refundedPaise and keeps paidPaise', () {
      const bill = InvoiceBill(paidPaise: 30000, refundedPaise: 5000);
      final next = bill.copyWith(refundedPaise: 12000);
      expect(next.paidPaise, 30000);
      expect(next.refundedPaise, 12000);
    });

    test('a refund does not change the balance due', () {
      const bill = InvoiceBill(
        items: [InvoiceBillItem(name: 'Scaling', ratePaise: 50000)],
        roundOff: false,
        paidPaise: 50000,
        refundedPaise: 50000,
      );
      expect(InvoiceTotals.of(bill).balance, 0);
    });
  });
}
