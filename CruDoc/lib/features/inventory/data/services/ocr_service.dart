import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:doctor_management_app/features/revenue/data/services/paddle_ocr_service.dart';

/// Result of an OCR scan on a medicine receipt/strip.
class OcrMedicineResult {
  const OcrMedicineResult({
    this.name,
    this.category,
    this.batchNumber,
    this.expiryDate,
    this.unitPrice,
    this.supplierName,
    this.quantity,
    this.rawText,
  });

  final String? name;
  final String? category;
  final String? batchNumber;
  final DateTime? expiryDate;
  final double? unitPrice;
  final String? supplierName;
  final int? quantity;

  /// Full OCR dump for debugging.
  final String? rawText;

  bool get isEmpty =>
      name == null &&
      category == null &&
      batchNumber == null &&
      expiryDate == null &&
      unitPrice == null &&
      supplierName == null &&
      quantity == null;

  int get filledFieldCount => [
        name,
        category,
        batchNumber,
        expiryDate,
        unitPrice,
        supplierName,
        quantity,
      ].where((v) => v != null).length;
}

/// Performs on-device OCR using Google ML Kit (on mobile) or PaddleOCR (on desktop)
/// and extracts medicine fields from a receipt or medicine strip image.
class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  TextRecognizer? _recognizer;

  TextRecognizer get recognizer {
    _recognizer ??= TextRecognizer(
      script: TextRecognitionScript.latin,
    );
    return _recognizer!;
  }

  /// Scans [imageFile] and returns extracted medicine fields.
  Future<OcrMedicineResult> scanMedicineReceipt(File imageFile) async {
    final bool isDesktop = !kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    if (isDesktop) {
      final paddleResult = await PaddleOcrService.instance.scanInvoice(imageFile);
      
      String? name;
      double? price;
      
      if (paddleResult.medicines.isNotEmpty) {
        name = paddleResult.medicines[0].name;
        price = paddleResult.medicines[0].price;
      } else if (paddleResult.treatments.isNotEmpty) {
        name = paddleResult.treatments[0].name;
        price = paddleResult.treatments[0].price;
      }
      
      final rawText = paddleResult.rawText ?? '';
      final allLines = rawText.split('\n');

      return OcrMedicineResult(
        name: name ?? _extractName(allLines),
        category: _extractCategory(allLines, rawText),
        batchNumber: _extractBatch(allLines),
        expiryDate: _extractExpiry(allLines),
        unitPrice: price ?? _extractPrice(allLines),
        supplierName: _extractSupplier(allLines),
        quantity: _extractQuantity(allLines),
        rawText: rawText,
      );
    } else {
      final inputImage = InputImage.fromFile(imageFile);
      final RecognizedText recognised = await recognizer.processImage(inputImage);

      final allLines = <String>[];
      for (final block in recognised.blocks) {
        for (final line in block.lines) {
          final text = line.text.trim();
          if (text.isNotEmpty) allLines.add(text);
        }
      }

      final rawText = allLines.join('\n');

      return OcrMedicineResult(
        name: _extractName(allLines),
        category: _extractCategory(allLines, rawText),
        batchNumber: _extractBatch(allLines),
        expiryDate: _extractExpiry(allLines),
        unitPrice: _extractPrice(allLines),
        supplierName: _extractSupplier(allLines),
        quantity: _extractQuantity(allLines),
        rawText: rawText,
      );
    }
  }

  /// Dispose the underlying ML Kit recognizer.
  Future<void> dispose() async {
    await _recognizer?.close();
  }

  // ─── Field extractors ────────────────────────────────────────────────────────

  /// The medicine name is usually the largest / first prominent text line.
  /// We skip very short lines and lines that look like labels.
  String? _extractName(List<String> lines) {
    final skipPatterns = RegExp(
      r'^(batch|lot|b\.?no|mfg|mfd|exp|expiry|mrp|price|qty|quantity|tab|cap|'
      r'mfr|manufactured|distributed|dist|net|contains|each|rx|schedule|'
      r'store|keep|composition|dosage|warning|caution|for|use|only|'
      r'drug|pharma|lab|industries|pvt|ltd|inc|corp)',
      caseSensitive: false,
    );

    for (final line in lines) {
      final cleaned = line.trim();
      if (cleaned.length < 4) continue;
      if (skipPatterns.hasMatch(cleaned)) continue;
      // Skip lines that are purely numbers / symbols
      if (RegExp(r'^[\d\s\-/\\.,₹$%]+$').hasMatch(cleaned)) continue;
      // Skip lines that look like addresses
      if (RegExp(r'\d{3,}').hasMatch(cleaned) && cleaned.length > 30) continue;
      return _toTitleCase(cleaned);
    }
    return null;
  }

  String? _extractCategory(List<String> lines, String rawText) {
    // Common medicine category keywords found on Indian packaging
    const categories = {
      'antibiotic': 'Antibiotic',
      'analgesic': 'Analgesic',
      'antipyretic': 'Antipyretic',
      'antifungal': 'Antifungal',
      'antiviral': 'Antiviral',
      'antacid': 'Antacid',
      'antiseptic': 'Antiseptic',
      'antidiabetic': 'Antidiabetic',
      'antihypertensive': 'Antihypertensive',
      'antihistamine': 'Antihistamine',
      'vitamin': 'Vitamin',
      'supplement': 'Supplement',
      'tablet': 'Tablet',
      'capsule': 'Capsule',
      'syrup': 'Syrup',
      'injection': 'Injection',
      'ointment': 'Ointment',
      'cream': 'Cream',
      'gel': 'Gel',
      'drops': 'Drops',
      'inhaler': 'Inhaler',
      'suspension': 'Suspension',
      'solution': 'Solution',
    };

    final lower = rawText.toLowerCase();
    for (final entry in categories.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return null;
  }

  String? _extractBatch(List<String> lines) {
    final batchRe = RegExp(
      r'(?:batch\s*(?:no\.?|number|#)?|lot\s*(?:no\.?)?|b\.?\s*no\.?)\s*[:\-]?\s*([A-Z0-9\-\/]+)',
      caseSensitive: false,
    );
    for (final line in lines) {
      final m = batchRe.firstMatch(line);
      if (m != null && m.group(1) != null) return m.group(1)!.trim();
    }
    return null;
  }

  DateTime? _extractExpiry(List<String> lines) {
    // Handles: EXP 03/27  |  Expiry: 2027-03  |  EXP DATE: 03-2027  | MFD 01/25 EXP 06/27
    final expiryRe = RegExp(
      r'(?:exp(?:iry|ires?|\.?\s*date)?|use\s+before|best\s+before)\s*[:\-]?\s*'
      r'(\d{1,2}[\/\-\.]\d{2,4}|\d{4}[\/\-]\d{1,2})',
      caseSensitive: false,
    );
    for (final line in lines) {
      final m = expiryRe.firstMatch(line);
      if (m != null && m.group(1) != null) {
        final date = _parsePartialDate(m.group(1)!.trim());
        if (date != null) return date;
      }
    }
    return null;
  }

  double? _extractPrice(List<String> lines) {
    final priceRe = RegExp(
      r'(?:mrp|price|m\.?r\.?p\.?|unit\s+price)\s*[:\-₹$]?\s*₹?\s*(\d+(?:\.\d{1,2})?)',
      caseSensitive: false,
    );
    for (final line in lines) {
      final m = priceRe.firstMatch(line);
      if (m != null && m.group(1) != null) {
        return double.tryParse(m.group(1)!.trim());
      }
    }
    // Fallback: standalone ₹ amount
    final rupeeRe = RegExp(r'₹\s*(\d+(?:\.\d{1,2})?)');
    for (final line in lines) {
      final m = rupeeRe.firstMatch(line);
      if (m != null && m.group(1) != null) {
        return double.tryParse(m.group(1)!.trim());
      }
    }
    return null;
  }

  String? _extractSupplier(List<String> lines) {
    final supplierRe = RegExp(
      r'(?:mfr(?:\.)?|mfd\s+by|manufactured\s+by|marketed\s+by|'
      r'distributed\s+by|dist(?:\.)?)\s*[:\-]?\s*(.*)',
      caseSensitive: false,
    );
    for (final line in lines) {
      final m = supplierRe.firstMatch(line);
      if (m != null) {
        final raw = m.group(1)?.trim() ?? '';
        if (raw.length > 3) return _toTitleCase(raw);
      }
    }
    return null;
  }

  int? _extractQuantity(List<String> lines) {
    final qtyRe = RegExp(
      r'(?:qty|quantity|units?|count|strips?|pcs|pieces?)\s*[:\-]?\s*(\d+)',
      caseSensitive: false,
    );
    for (final line in lines) {
      final m = qtyRe.firstMatch(line);
      if (m != null && m.group(1) != null) {
        return int.tryParse(m.group(1)!.trim());
      }
    }
    // Last resort: "10 tablets" / "30 capsules"
    final packRe = RegExp(
      r'(\d+)\s*(?:tab(?:let)?s?|cap(?:sule)?s?|vials?|ampoules?|ml)',
      caseSensitive: false,
    );
    for (final line in lines) {
      final m = packRe.firstMatch(line);
      if (m != null && m.group(1) != null) {
        return int.tryParse(m.group(1)!.trim());
      }
    }
    return null;
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  /// Parses partial dates like "03/27", "03-2027", "2027/03".
  DateTime? _parsePartialDate(String raw) {
    // Normalise separators
    final normalised = raw.replaceAll(RegExp(r'[\-\.]'), '/');
    final parts = normalised.split('/');
    if (parts.length != 2) return null;

    int? month, year;

    if (parts[0].length == 4) {
      // YYYY/MM
      year = int.tryParse(parts[0]);
      month = int.tryParse(parts[1]);
    } else {
      // MM/YY or MM/YYYY
      month = int.tryParse(parts[0]);
      final rawYear = int.tryParse(parts[1]);
      if (rawYear == null) return null;
      year = rawYear < 100 ? 2000 + rawYear : rawYear;
    }

    if (month == null || year == null) return null;
    if (month < 1 || month > 12) return null;

    // Use last day of the expiry month
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, lastDay);
  }

  String _toTitleCase(String s) {
    return s.split(' ').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
  }
}
