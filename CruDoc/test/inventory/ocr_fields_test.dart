import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/inventory/data/services/ocr_service.dart';
import 'package:doctor_management_app/features/inventory/domain/bill_import.dart';

// PaddleOCR's lines for a test carton label.
const carton = [
  'Rx only',
  'AMOXYCILLIN CAPSULES IP',
  'Amoxil 500 mg',
  '10 Capsules',
  'Each capsule contains: Amoxycillin Trihydrate IP',
  'equivalent to Amoxycillin 500 mg',
  'B.No. AMX24117',
  'Mfg. 05/2025 Exp. 04/2027',
  'M.R.P. Rs. 112.50 per strip of 10 capsules',
  'Mfd. by: Cipla Pharma Ltd, Goa 403722',
];

void main() {
  group('fields from a scan', () {
    test('a carton label fills every field', () {
      final r = OcrService.fieldsFromLines(carton);
      expect(r.name, 'Amoxil 500 mg');
      expect(r.category, 'Antibiotic');
      expect(r.unit, 'Capsules');
      expect(r.quantity, 10);
      expect(r.batchNumber, 'AMX24117');
      expect(r.expiryDate, DateTime(2027, 4, 30));
      expect(r.unitPrice, 11.25, reason: 'MRP per strip of 10, per capsule');
      expect(r.supplierName, 'Cipla Pharma Ltd');
      expect(r.filledFieldCount, 8);
    });

    test('a prescription line: "Rx: Amoxicillin 500mg caps"', () {
      // PaddleOCR's lines for prescription_images/Prescription3.webp.
      final r = OcrService.fieldsFromLines(const [
        'Riverside Medical Practice',
        'Name: Margaret Ellis',
        'Date: 14/03/26',
        'Rx: Amoxicillin 500mg caps',
        '1 Cap PO TID × 7 days',
        'Paracetamol 500mg PRN',
      ]);
      expect(r.name, 'Amoxicillin 500mg');
      expect(r.unit, 'Capsules');
      expect(r.category, 'Antibiotic');
    });

    test('a bill line loses its number, form and dose', () {
      final r = OcrService.fieldsFromLines(const [
        '1. Tab. Paracetamol 650 mg 1-1-1 x 3 days',
      ]);
      expect(r.name, 'Paracetamol 650 mg');
      expect(r.unit, 'Tablets');
      expect(r.category, 'Antipyretic');
    });

    test('all capitals are tidied, units stay lower case', () {
      final r = OcrService.fieldsFromLines(const ['PANTOPRAZOLE 40 MG']);
      expect(r.name, 'Pantoprazole 40 mg');
      expect(r.category, 'Gastrointestinal');
    });

    test('other label wordings', () {
      final r = OcrService.fieldsFromLines(const [
        'Cetirizine Tablets IP 10 mg',
        'Batch No: ct-2291',
        'EXP 11/26',
        'MRP ₹ 35',
      ]);
      expect(r.batchNumber, 'CT-2291');
      expect(r.expiryDate, DateTime(2026, 11, 30));
      expect(r.unitPrice, 35);
      expect(r.unit, 'Tablets');
    });

    test('nothing to read', () {
      final r = OcrService.fieldsFromLines(const ['', '  ']);
      expect(r.isEmpty, isTrue);
    });
  });

  group('one item from a bill (New item form)', () {
    test("the bill's first line", () {
      final r = OcrService.fromBill(
        ScannedBill.fromJson(const {
          'source': 'sarvam',
          'supplier': 'SHREE GANESH PHARMA DISTRIBUTORS',
          'items': [
            {
              'name': 'AMOXYCLAV 625 TAB',
              'pack': "6'S",
              'batch': 'ac3305',
              'expiry': '05/27',
              'quantity': 4,
              'rate': 161.9,
            },
          ],
        }),
      );
      expect(r.name, 'Amoxyclav 625');
      expect(r.unit, 'Tablets');
      expect(r.quantity, 24);
      expect(r.unitPrice, 26.98);
      expect(r.batchNumber, 'AC3305');
      expect(r.expiryDate, DateTime(2027, 5, 31));
      expect(r.supplierName, 'Shree Ganesh Pharma Distributors');
      expect(r.category, 'Antibiotic');
    });

    test('no table: the text read offline', () {
      final r = OcrService.fromBill(
        const ScannedBill(source: 'paddle', lines: carton),
      );
      expect(r.name, 'Amoxil 500 mg');
      expect(r.batchNumber, 'AMX24117');
    });
  });
}
