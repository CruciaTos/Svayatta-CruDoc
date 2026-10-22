import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:doctor_management_app/features/inventory/data/services/bill_scan_tool.dart';
import 'package:doctor_management_app/features/inventory/domain/bill_import.dart';
import 'package:doctor_management_app/features/revenue/data/services/paddle_ocr_service.dart';
import 'package:image_picker/image_picker.dart';

/// Result of an OCR scan on a medicine receipt/strip.
class OcrMedicineResult {
  const OcrMedicineResult({
    this.name,
    this.category,
    this.unit,
    this.batchNumber,
    this.expiryDate,
    this.unitPrice,
    this.supplierName,
    this.quantity,
    this.rawText,
  });

  final String? name;
  final String? category;

  /// One of the form's units: 'Tablets', 'Capsules', 'Syrup (ml)'…
  final String? unit;
  final String? batchNumber;
  final DateTime? expiryDate;
  final double? unitPrice;
  final String? supplierName;
  final int? quantity;

  /// Full OCR dump for debugging.
  final String? rawText;

  bool get isEmpty => filledFieldCount == 0;

  int get filledFieldCount => [
    name,
    category,
    unit,
    batchNumber,
    expiryDate,
    unitPrice,
    supplierName,
    quantity,
  ].where((v) => v != null).length;
}

/// Reads a medicine strip, carton or bill and picks out the item's fields:
/// on desktop Sarvam Vision, or PaddleOCR on this computer when offline
/// ([BillScanTool]); Google ML Kit on phones; the PaddleOCR server on the
/// web.
class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  TextRecognizer? _recognizer;

  TextRecognizer get recognizer {
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    return _recognizer!;
  }

  /// Scans [imageFile] and returns extracted medicine fields.
  Future<OcrMedicineResult> scanMedicineReceipt(XFile imageFile) async {
    if (kIsWeb) {
      final paddleResult = await PaddleOcrService.instance.scanInvoice(
        imageFile,
      );
      final lines = (paddleResult.rawText ?? '').split('\n');
      final fields = fieldsFromLines(lines);
      final first = paddleResult.medicines.firstOrNull;
      return OcrMedicineResult(
        name: first?.name ?? fields.name,
        category: fields.category,
        unit: fields.unit,
        batchNumber: fields.batchNumber,
        expiryDate: fields.expiryDate,
        unitPrice: first?.price ?? fields.unitPrice,
        supplierName: fields.supplierName,
        quantity: fields.quantity,
        rawText: fields.rawText,
      );
    }

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return fromBill(await BillScanTool.scan(imageFile.path));
    }

    final recognised = await recognizer.processImage(
      InputImage.fromFilePath(imageFile.path),
    );
    return fieldsFromLines([
      for (final block in recognised.blocks)
        for (final line in block.lines)
          if (line.text.trim().isNotEmpty) line.text.trim(),
    ]);
  }

  /// Dispose the underlying ML Kit recognizer.
  Future<void> dispose() async {
    await _recognizer?.close();
  }

  /// One item's fields from a scanned purchase bill: its first line, else
  /// whatever the bill's text says (a carton photographed by mistake).
  static OcrMedicineResult fromBill(ScannedBill bill) {
    final supplier = bill.supplier == null ? null : tidyCaps(bill.supplier!);
    final first = bill.items.firstOrNull;
    if (first == null) {
      final fields = fieldsFromLines(bill.lines);
      return supplier == null || fields.supplierName != null
          ? fields
          : OcrMedicineResult(
              name: fields.name,
              category: fields.category,
              unit: fields.unit,
              batchNumber: fields.batchNumber,
              expiryDate: fields.expiryDate,
              unitPrice: fields.unitPrice,
              supplierName: supplier,
              quantity: fields.quantity,
              rawText: fields.rawText,
            );
    }
    final draft = BillItemDraft.fromLine(
      first,
      cost: costBill(bill).lines.first,
    );
    return OcrMedicineResult(
      name: draft.name,
      category: categoryOf(first.name),
      unit: draft.unit,
      batchNumber: draft.batch,
      expiryDate: draft.expiry,
      unitPrice: draft.unitPrice,
      supplierName: supplier,
      quantity: draft.stock > 0 ? draft.stock : null,
      rawText: bill.lines.join('\n'),
    );
  }

  /// The form's category for a medicine named or described in [text].
  static String? categoryOf(String text) => _extractCategory(text);

  /// The item's fields in the text [lines] read off a strip or bill.
  static OcrMedicineResult fieldsFromLines(List<String> lines) {
    final clean = [
      for (final l in lines)
        if (l.trim().isNotEmpty) l.trim(),
    ];
    final rawText = clean.join('\n');
    final unit = _extractUnit(rawText);
    return OcrMedicineResult(
      name: _extractName(clean),
      category: _extractCategory(rawText),
      unit: unit,
      batchNumber: _extractBatch(clean),
      expiryDate: _extractExpiry(clean),
      unitPrice: _extractPrice(clean, unit),
      supplierName: _extractSupplier(clean),
      quantity: _extractQuantity(clean),
      rawText: rawText,
    );
  }

  // ─── Field extractors ────────────────────────────────────────────────────────

  /// A drug strength: "500 mg", "650mg", "10 ml", "0.5%".
  static final _strength = RegExp(
    r'\b\d+(?:\.\d+)?\s?(?:mg|mcg|µg|g|ml|iu|%)(?![a-z])',
    caseSensitive: false,
  );

  /// Words before the name on a bill line: "1.", "Rx:", "Tab.", "Cap".
  static final _namePrefix = RegExp(
    r'^(?:\d+\s*[.)]\s*)?(?:rx\s*[:.]?\s*)?'
    r'(?:(?:tab|tablet|cap|capsule|syp|syrup|inj|injection)s?\b\.?\s*)?',
    caseSensitive: false,
  );

  static final _nameSkip = RegExp(
    r'^(batch|lot|b\.?no|mfg|mfd|exp|expiry|mrp|m\.r\.p|price|qty|quantity|'
    r'mfr|manufactured|marketed|distributed|dist|net|contains|each|'
    r'equivalent|schedule|store|keep|composition|dosage|warning|'
    r'caution|for|use|only|drug|pharma|lab|industries|pvt|ltd|inc|corp)',
    caseSensitive: false,
  );

  /// The medicine name: the first line with a strength ("Amoxil 500 mg",
  /// "1. Tab. Paracetamol 650 mg 1-0-1" → "Paracetamol 650 mg"), else the
  /// first line that doesn't look like a label, a number or an address.
  static String? _extractName(List<String> lines) {
    for (final line in lines) {
      if (_nameSkip.hasMatch(line)) continue;
      final s = _strength.firstMatch(line);
      if (s == null) continue;
      final name = line
          .substring(0, s.end)
          .replaceFirst(_namePrefix, '')
          .trim();
      if (RegExp(r'[A-Za-z]{3,}').hasMatch(name)) return _tidyCase(name);
    }
    for (final line in lines) {
      if (line.length < 4 || _nameSkip.hasMatch(line)) continue;
      // "Rx only", "Rx:" with nothing after it.
      if (RegExp(r'^rx\b', caseSensitive: false).hasMatch(line)) continue;
      if (RegExp(r'^[\d\s\-/\\.,₹$%]+$').hasMatch(line)) continue;
      if (RegExp(r'\d{3,}').hasMatch(line) && line.length > 30) continue;
      return _tidyCase(line.replaceFirst(_namePrefix, '').trim());
    }
    return null;
  }

  /// Category words, or well-known drugs, to the form's categories.
  static const _categories = [
    (
      r'antibiotic|\w*(?:cillin|mycin|floxacin|cycline)\b|\bcef\w+|\bamox\w*'
          r'|\w*clav\b|\bazith\w*|\blinezolid',
      'Antibiotic',
    ),
    (r'antipyretic|paracetamol|acetaminophen', 'Antipyretic'),
    (
      r'analgesic|painkiller|ibuprofen|diclofenac|aceclofenac|tramadol',
      'Analgesic',
    ),
    (r'antidiabetic|metformin|glimepiride|gliclazide|insulin', 'Antidiabetic'),
    (
      r'antihypertensive|amlodipine|telmisartan|atorvastatin|losartan',
      'Cardiovascular',
    ),
    (
      r'antacid|pantoprazole|omeprazole|rabeprazole|ranitidine|ondansetron',
      'Gastrointestinal',
    ),
    (r'antihistamine|cetirizine|fexofenadine|montelukast', 'Antihistamine'),
    (r'vitamin|supplement|calcium|multivit', 'Vitamins & Supplements'),
    (r'antifungal|fluconazole|clotrimazole', 'Antifungal'),
    (r'antiviral|acyclovir|oseltamivir', 'Antiviral'),
    (r'antiseptic|povidone|chlorhexidine', 'Antiseptic'),
  ];

  static String? _extractCategory(String rawText) {
    for (final (pattern, category) in _categories) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(rawText)) {
        return category;
      }
    }
    return null;
  }

  /// The dosage form, as one of the form's units. A strip of tablets is
  /// counted in tablets.
  static const _units = [
    (r'\b(?:tablets?|tabs?)\b', 'Tablets'),
    (r'\b(?:capsules?|caps?)\b', 'Capsules'),
    (r'\b(?:syrup|syp|suspension|oral solution)\b', 'Syrup (ml)'),
    (r'\b(?:injection|inj)\b', 'Injections'),
    (r'\b(?:vials?|ampoules?)\b', 'Vials'),
    (r'\b(?:ointment|cream|gel)\b', 'Ointment'),
    (r'\bdrops\b', 'Drops'),
    (r'\bsachets?\b', 'Sachets'),
    (r'\bstrips?\b', 'Strips'),
  ];

  static String? _extractUnit(String rawText) {
    for (final (pattern, unit) in _units) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(rawText)) return unit;
    }
    return null;
  }

  static String? _extractBatch(List<String> lines) {
    final batchRe = RegExp(
      r'\b(?:batch\s*(?:no\.?|number|#)?|lot\s*(?:no\.?)?|b\.?\s*no\.?)'
      r'\s*[:\-]?\s*([A-Z0-9][A-Z0-9\-\/]*)',
      caseSensitive: false,
    );
    for (final line in lines) {
      final m = batchRe.firstMatch(line);
      if (m != null && RegExp(r'\d').hasMatch(m.group(1)!)) {
        return m.group(1)!.toUpperCase();
      }
    }
    return null;
  }

  /// "EXP 03/27", "Exp. 04/2027", "Expiry: 2027-03", "Use before 06/27".
  static DateTime? _extractExpiry(List<String> lines) {
    final expiryRe = RegExp(
      r'(?:\bexp(?:iry|ires?)?\.?(?:\s*date)?|use\s+before|best\s+before)'
      r'\s*[:\-.]?\s*(\d{1,2}[\/\-\.]\d{2,4}|\d{4}[\/\-]\d{1,2})',
      caseSensitive: false,
    );
    for (final line in lines) {
      final m = expiryRe.firstMatch(line);
      if (m == null) continue;
      final date = _parsePartialDate(m.group(1)!);
      if (date != null) return date;
    }
    return null;
  }

  /// The price of one [unit]: an MRP "per strip of 10" is split across
  /// the 10.
  static double? _extractPrice(List<String> lines, String? unit) {
    final priceRe = RegExp(
      r'(?:\bm\.?\s?r\.?\s?p\.?|\bprice|\bunit\s+price|\brate)\s*[:\-]?\s*'
      r'(?:₹|rs\.?|inr)?\s*(\d+(?:\.\d{1,2})?)',
      caseSensitive: false,
    );
    final rupeeRe = RegExp(
      r'(?:₹|\brs\.?)\s*(\d+(?:\.\d{1,2})?)',
      caseSensitive: false,
    );
    for (final re in [priceRe, rupeeRe]) {
      for (final line in lines) {
        final m = re.firstMatch(line);
        final price = double.tryParse(m?.group(1) ?? '');
        if (price == null || price <= 0) continue;
        final pack = RegExp(
          r'(?:per|/)\s*(?:strip|pack|box)\s*of\s*(\d+)',
          caseSensitive: false,
        ).firstMatch(line);
        final count = int.tryParse(pack?.group(1) ?? '');
        if (count != null && count > 1 && unit != 'Strips') {
          return (price / count * 100).roundToDouble() / 100;
        }
        return price;
      }
    }
    return null;
  }

  /// "Mfd. by: Cipla Ltd, Goa" → "Cipla Ltd".
  static String? _extractSupplier(List<String> lines) {
    final supplierRe = RegExp(
      r'(?:\bmf[dg]\.?\s*by|\bmanufactured\s+by|\bmarketed\s+by|\bmkt\.?\s*by|'
      r'\bdistributed\s+by|\bdist\.?\s*by|\bmfr\.?\s*:|\bsupplier\s*:)'
      r'\s*[:\-]?\s*(.*)',
      caseSensitive: false,
    );
    for (final line in lines) {
      final m = supplierRe.firstMatch(line);
      if (m == null) continue;
      final name = m.group(1)!.split(',').first.trim();
      if (name.length > 3) return _tidyCase(name);
    }
    return null;
  }

  static int? _extractQuantity(List<String> lines) {
    final qtyRe = RegExp(
      r'\b(?:qty|quantity|count|pcs|pieces?)\s*[:\-]?\s*(\d+)',
      caseSensitive: false,
    );
    for (final line in lines) {
      final m = qtyRe.firstMatch(line);
      if (m != null) return int.tryParse(m.group(1)!);
    }
    // "10 Capsules", "30 tablets" (not "500 mg tablets").
    final packRe = RegExp(
      r'\b(\d+)\s*(?:tab(?:let)?s?|cap(?:sule)?s?|vials?|ampoules?|sachets?)\b',
      caseSensitive: false,
    );
    for (final line in lines) {
      final m = packRe.firstMatch(line);
      if (m != null) return int.tryParse(m.group(1)!);
    }
    return null;
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  /// Parses partial dates like "03/27", "03-2027", "2027/03".
  static DateTime? _parsePartialDate(String raw) {
    final parts = raw.replaceAll(RegExp(r'[\-\.]'), '/').split('/');
    if (parts.length != 2) return null;

    final int? month, year;
    if (parts[0].length == 4) {
      year = int.tryParse(parts[0]);
      month = int.tryParse(parts[1]);
    } else {
      month = int.tryParse(parts[0]);
      final rawYear = int.tryParse(parts[1]);
      year = rawYear == null
          ? null
          : (rawYear < 100 ? 2000 + rawYear : rawYear);
    }
    if (month == null || year == null || month < 1 || month > 12) return null;

    // Medicines expire at the end of the month printed.
    return DateTime(year, month + 1, 0);
  }

  static String _tidyCase(String s) => tidyCaps(s);
}
