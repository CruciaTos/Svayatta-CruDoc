import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/services/bill_scan_tool.dart';
import 'package:doctor_management_app/features/inventory/domain/bill_import.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_format.dart';

/// Sarvam Vision's reading of the test bill (bill_scan.py --json).
const _reply =
    '{"source": "sarvam", "note": null, '
    '"supplier": "SHREE GANESH PHARMA DISTRIBUTORS", '
    '"invoiceNumber": "SGPD/2026/04512", "invoiceDate": "14/10/2026", '
    '"items": ['
    '{"name": "DOLO 650 TAB", "pack": "15\'S", "batch": "DL24A91", "expiry": "03/28", "quantity": 10.0, "freeQuantity": 1.0, "mrp": 33.6, "rate": 24.1, "amount": 241.0}, '
    '{"name": "PANTOCID 40MG TAB", "pack": "10\'S", "batch": "PT77812", "expiry": "09/27", "quantity": 6.0, "freeQuantity": 0.0, "mrp": 155.0, "rate": 112.4, "amount": 674.4}, '
    '{"name": "VOLINI GEL 30GM", "pack": "1\'S", "batch": "VG2611", "expiry": "12/27", "quantity": 5.0, "freeQuantity": 0.0, "mrp": 145.0, "rate": 104.5, "amount": 522.5}, '
    '{"name": "BECOSULES CAP", "pack": "20\'S", "batch": "BC90122", "expiry": "11/27", "quantity": 3.0, "freeQuantity": 0.0, "mrp": 61.3, "rate": 44.2, "amount": 132.6}'
    ']}';

MedicineModel _medicine(String name, {int stock = 0}) => MedicineModel(
  id: name,
  name: name,
  unit: 'Tablets',
  currentStock: stock,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  group("the script's reply", () {
    test('a bill, after any other output', () {
      final bill = BillScanTool.parseOutput('Creating model...\n$_reply\n')!;
      expect(bill.source, 'sarvam');
      expect(bill.readOffline, isFalse);
      expect(bill.invoiceNumber, 'SGPD/2026/04512');
      expect(bill.items.map((i) => i.name), [
        'DOLO 650 TAB',
        'PANTOCID 40MG TAB',
        'VOLINI GEL 30GM',
        'BECOSULES CAP',
      ]);
      expect(bill.items.first.freeQuantity, 1);
    });

    test('read offline, with the reason', () {
      final bill = BillScanTool.parseOutput(
        '{"source": "paddle", "note": "no internet connection to Sarvam", '
        '"items": [], "lines": ["A", " ", "B"]}',
      )!;
      expect(bill.readOffline, isTrue);
      expect(bill.note, 'no internet connection to Sarvam');
      expect(bill.lines, ['A', 'B']);
    });

    test('an error is thrown; no reply is null', () {
      expect(
        () => BillScanTool.parseOutput('{"error": "File not found: x.png"}'),
        throwsA(predicate((e) => '$e'.contains('File not found: x.png'))),
      );
      expect(BillScanTool.parseOutput('Traceback ...\n'), isNull);
    });
  });

  group('a bill line as an inventory item', () {
    final items = BillScanTool.parseOutput(_reply)!.items;

    test('strips of tablets are counted in tablets, priced per tablet', () {
      final d = BillItemDraft.fromLine(items[0]);
      expect(d.name, 'Dolo 650');
      expect(d.unit, 'Tablets');
      expect(d.perPack, 15);
      expect(d.stock, 165, reason: '(10 + 1 free) strips of 15');
      expect(d.unitPrice, 1.61, reason: '₹24.10 a strip / 15');
      expect(d.batch, 'DL24A91');
      expect(d.expiry, DateTime(2028, 3, 31));
    });

    test('strength stays in the name', () {
      final d = BillItemDraft.fromLine(items[1]);
      expect(d.name, 'Pantocid 40mg');
      expect(d.stock, 60);
      expect(d.unitPrice, 11.24);
    });

    test('a tube is counted as one', () {
      final d = BillItemDraft.fromLine(items[2]);
      expect(d.name, 'Volini Gel 30gm');
      expect(d.unit, 'Ointment');
      expect(d.stock, 5);
      expect(d.unitPrice, 104.5);
    });

    test('capsules', () {
      final d = BillItemDraft.fromLine(items[3]);
      expect(d.name, 'Becosules');
      expect(d.unit, 'Capsules');
      expect(d.stock, 60);
      expect(d.unitPrice, 2.21);
    });

    test('no rate: the amount over the quantity', () {
      final d = BillItemDraft.fromLine(
        const BillLine(
          name: 'ZINCOVIT TAB',
          pack: '1x15',
          quantity: 2,
          amount: 180,
        ),
      );
      expect(d.unitPrice, 6, reason: '₹180 / 2 strips / 15');
      expect(d.stock, 30);
    });
  });

  group('what each line cost', () {
    // Sarvam's reading of the MediCare Wholesale Pharmacy test invoice:
    // 10% off every line, 12% IGST, ₹2,469.60 in all.
    const medicare = ScannedBill(
      source: 'sarvam',
      subtotal: 2205,
      taxAmount: 264.6,
      taxPercent: 12,
      grandTotal: 2469.6,
      items: [
        BillLine(
          name: 'Paracetamol 500 mg',
          quantity: 10,
          quantityUnit: 'TBS',
          mrp: 50,
          rate: 40,
          discountPercent: 10,
          amount: 360,
        ),
        BillLine(
          name: 'Cough Syrup (200ml)',
          pack: '200ml',
          quantity: 20,
          quantityUnit: 'BTL',
          rate: 80,
          discountPercent: 10,
          amount: 1440,
        ),
        BillLine(
          name: 'Antibiotic Cream (30g)',
          pack: '30g',
          quantity: 10,
          quantityUnit: 'PKG',
          rate: 45,
          discountPercent: 10,
          amount: 405,
        ),
      ],
    );

    test('rate less discount plus GST adds up to the bill total', () {
      final costing = costBill(medicare);
      expect(costing.itemsTotal, closeTo(2469.6, 0.001));
      expect(costing.matchesBill, isTrue);
      expect(costing.lines.map((l) => l!.total), [
        closeTo(403.2, 0.001),
        closeTo(1612.8, 0.001),
        closeTo(453.6, 0.001),
      ]);
      expect(costing.lines.first!.taxPercent, 12);
      expect(costing.lines.first!.discountPercent, 10);
    });

    test('unit prices hold the inventory at what was paid', () {
      final costing = costBill(medicare);
      final drafts = [
        for (final (i, line) in medicare.items.indexed)
          BillItemDraft.fromLine(line, cost: costing.lines[i]),
      ];
      expect(drafts.map((d) => (d.unit, d.stock, d.unitPrice)), [
        ('Tablets', 10, 40.32), // "10 TBS": already single tablets
        ('Bottles', 20, 80.64),
        ('Ointment', 10, 45.36),
      ]);
      final value = drafts.fold(0.0, (s, d) => s + d.unitPrice! * d.stock);
      expect(value, closeTo(2469.6, 0.001));
    });

    test('GST worked out from the totals when no rate is printed', () {
      // CGST 6% + SGST 6%, read as subtotal and total only: the four
      // lines come to ₹1,570.50 before GST.
      final bill = BillScanTool.parseOutput(_reply)!;
      final costing = costBill(
        ScannedBill(
          source: 'sarvam',
          subtotal: 1570.5,
          grandTotal: 1758.96,
          items: bill.items,
        ),
      );
      expect(costing.lines.first!.taxPercent, closeTo(12, 0.01));
      expect(costing.itemsTotal, closeTo(1758.96, 0.001));
    });

    test('an amount that already has GST in it is not taxed again', () {
      final costing = costBill(
        const ScannedBill(
          source: 'paddle',
          taxPercent: 12,
          items: [BillLine(name: 'X', quantity: 10, rate: 10, amount: 112)],
        ),
      );
      expect(costing.lines.single!.total, 112);
      expect(costing.lines.single!.taxIncluded, isTrue);
    });

    test('round-off is spread over the lines', () {
      final costing = costBill(
        const ScannedBill(
          source: 'sarvam',
          taxPercent: 12,
          grandTotal: 2470,
          items: [
            BillLine(name: 'A', amount: 360),
            BillLine(name: 'B', amount: 1845),
          ],
        ),
      );
      expect(costing.itemsTotal, 2470);
      expect(costing.matchesBill, isTrue);
    });

    test('a total missing its last digit trusts the lines', () {
      final costing = costBill(
        const ScannedBill(
          source: 'sarvam',
          grandTotal: 4092.7, // the bill's corner is torn: ₹4,092.75
          items: [
            BillLine(name: 'A', quantity: 1, rate: 4000, amount: 4000),
            BillLine(name: 'B', quantity: 1, rate: 92.75, amount: 92.75),
          ],
        ),
      );
      expect(costing.itemsTotal, closeTo(4092.75, 1e-9));
      expect(costing.billTotal, closeTo(4092.75, 1e-9));
      expect(costing.lines.last!.total, closeTo(92.75, 1e-9));
    });

    test('lines far from the total are flagged', () {
      final costing = costBill(
        const ScannedBill(
          source: 'sarvam',
          taxPercent: 12,
          grandTotal: 3000,
          items: [BillLine(name: 'A', amount: 360)],
        ),
      );
      expect(costing.matchesBill, isFalse);
    });

    // A chemist's cash memo (Health Corner, ₹7,021.84): the values have
    // GST in them and add up to the amount payable. Sarvam read it as
    // "without GST, 5%": the arithmetic wins.
    const memo = ScannedBill(
      source: 'sarvam',
      grandTotal: 7021.84,
      subtotal: 5349.97, // one page's taxable value only
      taxPercent: 5,
      amountsIncludeTax: false,
      items: [
        BillLine(name: 'AXCER 90', quantity: 1, rate: 4210.31, amount: 4210.31),
        BillLine(name: 'REST', quantity: 1, rate: 2811.53, amount: 2811.53),
      ],
    );

    test('prices that add up to the total already have GST', () {
      final costing = costBill(memo);
      expect(costing.itemsTotal, closeTo(7021.84, 1e-9));
      expect(costing.lines.first!.total, closeTo(4210.31, 1e-9));
      expect(costing.lines.first!.taxIncluded, isTrue);
      expect(costing.matchesBill, isTrue);
    });

    test('a wrongly read GST rate gives way to the total', () {
      // Without GST in the prices, ₹1,000 + GST = ₹1,120: 12%, not 5%.
      final costing = costBill(
        const ScannedBill(
          source: 'sarvam',
          grandTotal: 1120,
          taxPercent: 5,
          items: [BillLine(name: 'A', quantity: 10, rate: 100, amount: 1000)],
        ),
      );
      expect(costing.lines.single!.taxPercent, closeTo(12, 1e-9));
      expect(costing.itemsTotal, closeTo(1120, 1e-9));
    });

    test('without GST: the taxable value', () {
      final costing = costBill(medicare, includeTax: false);
      expect(costing.lines.map((l) => l!.total), [360, 1440, 405]);
      expect(costing.billTotal, 2205);
      expect(costing.matchesBill, isTrue);
      expect(costing.includeTax, isFalse);
    });

    test('without GST: taken out of prices that have it, at a known rate', () {
      final costing = costBill(
        const ScannedBill(
          source: 'sarvam',
          grandTotal: 1120,
          items: [
            BillLine(
              name: 'A',
              quantity: 1,
              rate: 1120,
              amount: 1120,
              taxPercent: 12,
            ),
          ],
        ),
        includeTax: false,
      );
      expect(costing.lines.single!.total, closeTo(1000, 1e-9));
      expect(costing.lines.single!.taxRemoved, isTrue);
    });

    test("without GST, and the bill doesn't show the rate: kept", () {
      final costing = costBill(
        const ScannedBill(
          source: 'sarvam',
          grandTotal: 7021.84,
          items: [
            BillLine(name: 'A', quantity: 1, rate: 7021.84, amount: 7021.84),
          ],
        ),
        includeTax: false,
      );
      expect(costing.lines.single!.total, closeTo(7021.84, 1e-9));
      expect(costing.taxNotSeparable, isTrue);
      expect(costing.matchesBill, isTrue, reason: 'nothing to check against');
    });
  });

  test('amounts keep their paise', () {
    expect(InventoryFormat.rupees(7021.84), '₹7,021.84');
    expect(InventoryFormat.rupees(2450), '₹2,450');
    expect(InventoryFormat.rupees(150000), '₹1,50,000');
    expect(InventoryFormat.rupees(241 / 165), '₹1.46');
    expect(InventoryFormat.rupees(0.1 + 0.2), '₹0.30');
  });

  test('units', () {
    expect(billUnit('BENADRYL SYP', '100ML'), 'Bottles');
    expect(billUnit('BETADINE', '100ML'), 'Bottles');
    expect(billUnit('MONOCEF 1GM INJ', null), 'Injections');
    expect(billUnit('MOXICIP EYE DROPS', '5ML'), 'Drops');
    expect(billUnit('ORS', "21'S"), 'Packs');
  });

  test('pharmacy pack shorthand: 14T, 120T, 10C', () {
    expect(packCount('14T'), 14);
    expect(packCount('120T'), 120);
    expect(packCount('10C'), 10);
    expect(billUnit('AXCER 90', '14T'), 'Tablets');
    expect(billUnit('UNISTAR 20/75', '10C'), 'Capsules');
    expect(billUnit('LIVON SERUM', '20ML'), 'Bottles');
  });

  group('matching the inventory', () {
    InventoryMatch? match(
      String name,
      List<MedicineModel> items, {
      String unit = 'Tablets',
    }) => matchInventoryItem(name, unit, items);

    test('the same name, written any way', () {
      final stock = [_medicine('Pantocid 40 mg'), _medicine('Dolo 650')];
      final m = match('PANTOCID 40MG TAB', stock)!;
      expect((m.item.id, m.exact), ('Pantocid 40 mg', true));
      expect(match('Dolo 650 Tablets', stock)?.item.id, 'Dolo 650');
      expect(match('Dolo 500', stock), isNull);
      expect(match('', stock), isNull);
    });

    test('a different unit is a different item', () {
      final stock = [_medicine('Crocin 500')];
      expect(match('CROCIN 500 SYP', stock, unit: 'Bottles'), isNull);
      expect(match('Crocin 500', stock, unit: 'tablets'), isNotNull);
    });

    test('one letter misread is a possible match, not a sure one', () {
      for (final (read, stocked) in [
        ('GENER 1MG', 'Gemer 1mg'),
        ('KENIA ST 25', 'Xenia St 25'),
        ('TELHA 40MG (30T)', 'Telma 40mg (30t)'),
      ]) {
        final m = match(read, [_medicine(stocked)]);
        expect(m?.item.name, stocked, reason: read);
        expect(m?.exact, isFalse, reason: read);
      }
    });

    test('more than a letter, another strength or length: no match', () {
      for (final (read, stocked) in [
        ('Amlokind-AT 5', 'Amlokind 5'), // a combination: longer name
        ('Dolo 650', 'Dolo 500'),
        ('Crocin 500', 'Calpol 500'),
        ('Zincovit', 'Zincofer'),
        ('Pan 40', 'Pin 40'), // too short to call a misread
      ]) {
        expect(match(read, [_medicine(stocked)]), isNull, reason: read);
      }
    });

    test('two items a letter away: too unsure to pick', () {
      final stock = [_medicine('Gemer 1mg'), _medicine('Gever 1mg')];
      expect(match('Gener 1mg', stock), isNull);
    });

    test('lines of one bill join only when name and unit are the same', () {
      expect(
        sameMedicine('CONCOR 2.5MG', 'Tablets', 'Concor 2.5 mg', 'Tablets'),
        isTrue,
      );
      expect(
        sameMedicine('GENER 1MG', 'Tablets', 'Gemer 1mg', 'Tablets'),
        isFalse,
      );
      expect(
        sameMedicine('Crocin 500', 'Tablets', 'Crocin 500', 'Bottles'),
        isFalse,
      );
    });
  });

  test('a bill is known by its supplier and invoice number', () {
    expect(
      billKeyOf(
        const ScannedBill(
          source: 'sarvam',
          supplier: 'HEALTH CORNER MEDICAL AND GENERAL STORE',
          invoiceNumber: '165534',
        ),
      ),
      'healthcornermedicalandgeneralstore#165534',
    );
    expect(
      billKeyOf(
        const ScannedBill(
          source: 'sarvam',
          supplier: 'Health Corner',
          invoiceDate: '02/07/26',
          grandTotal: 7021.84,
        ),
      ),
      'healthcorner@020726=7021.84',
    );
    expect(
      billKeyOf(const ScannedBill(source: 'sarvam', invoiceNumber: '1')),
      isNull,
    );
  });

  test('pack sizes, and which ones are a guess', () {
    expect(readPack("15'S"), (count: 15, sure: true));
    expect(readPack('1x10'), (count: 10, sure: true));
    expect(readPack('14T'), (count: 14, sure: true));
    expect(readPack('10x10'), (count: 100, sure: false));
    expect(readPack(null), (count: 1, sure: false));
    expect(readPack('2.0'), (count: 1, sure: false));
    const box = BillLine(name: 'ZINCOVIT TAB', pack: '10x10', quantity: 2);
    expect(BillItemDraft.fromLine(box).perPackSure, isFalse);
    final corrected = BillItemDraft.fromLine(box, perPack: 10);
    expect((corrected.stock, corrected.perPackSure), (20, true));
    // A tube is one, however its pack reads.
    expect(
      BillItemDraft.fromLine(
        const BillLine(name: 'VOLINI GEL', pack: '2.0', quantity: 1),
      ).perPackSure,
      isTrue,
    );
  });

  test('pack sizes', () {
    expect(packCount("15'S"), 15);
    expect(packCount('15S'), 15);
    expect(packCount('1x10'), 10);
    expect(packCount('10X10'), 100);
    expect(packCount('10 TAB'), 10);
    expect(packCount('100ML'), 1);
    expect(packCount(null), 1);
  });

  test('expiry dates as bills print them', () {
    expect(parseBillExpiry('03/28'), DateTime(2028, 3, 31));
    expect(parseBillExpiry('3-2028'), DateTime(2028, 3, 31));
    expect(parseBillExpiry('MAR-28'), DateTime(2028, 3, 31));
    expect(parseBillExpiry('Feb 2028'), DateTime(2028, 2, 29));
    expect(parseBillExpiry('2027-11'), DateTime(2027, 11, 30));
    expect(parseBillExpiry('13/27'), isNull);
    expect(parseBillExpiry(''), isNull);
    expect(formatBillExpiry(DateTime(2028, 3, 31)), '03/28');
  });
}
