import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/core/services/gemini_json_client.dart';
import 'package:doctor_management_app/features/scan/data/scan_capture.dart';

/// A handwritten session note, read and written up.
class ScannedNote {
  const ScannedNote({
    required this.title,
    required this.notes,
    required this.transcript,
    required this.unclear,
  });

  /// What the session was about, under 8 words.
  final String title;

  /// The clean write-up: headings, "- " lists, blank lines between
  /// sections (the layout `SessionNoteBody` draws).
  final String notes;

  /// What the pages say, line by line, as written.
  final String transcript;

  /// Words, doses or numbers that could not be read for certain.
  final String unclear;
}

/// One line of a supplier's bill.
class BillItem {
  BillItem({
    required this.name,
    required this.category,
    required this.unit,
    required this.quantity,
    this.freeQuantity = 0,
    this.manufacturer = '',
    this.pack = '',
    this.batchNumber = '',
    this.expiryDate,
    this.mrp,
    this.unitPrice,
    this.gstPercent,
    this.amount,
    this.page = 1,
  });

  String name;
  String category;
  String unit;
  int quantity;
  int freeQuantity;
  String manufacturer;

  /// As printed: "10's", "1x15", "100 ml".
  String pack;
  String batchNumber;
  DateTime? expiryDate;
  double? mrp;

  /// Purchase rate for one [unit], before tax.
  double? unitPrice;
  double? gstPercent;
  double? amount;

  /// The scanned page (1-based) the line is printed on.
  int page;

  /// Everything that goes into stock, free goods included.
  int get stockAdded => quantity + freeQuantity;
}

/// A supplier's bill, read for what was bought.
class ScannedBill {
  const ScannedBill({
    required this.supplierName,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.items,
    required this.total,
    required this.unclear,
  });

  final String supplierName;
  final String invoiceNumber;
  final DateTime? invoiceDate;
  final List<BillItem> items;

  /// The bill's grand total, as printed.
  final double? total;
  final String unclear;
}

/// A result on a report: "Haemoglobin 10.2 g/dL (13–17) low".
class RecordFinding {
  const RecordFinding({
    required this.name,
    required this.value,
    this.unit = '',
    this.range = '',
    this.flag = '',
  });

  final String name;
  final String value;
  final String unit;
  final String range;

  /// 'high', 'low' or '' (normal or not stated).
  final String flag;
}

/// A report, prescription or letter, digitised.
class ScannedRecord {
  const ScannedRecord({
    required this.kind,
    required this.title,
    required this.date,
    required this.source,
    required this.summary,
    required this.findings,
    required this.unclear,
  });

  /// One of [ScanReader.recordKinds].
  final String kind;
  final String title;
  final DateTime? date;

  /// Who issued it: a lab, hospital or doctor.
  final String source;

  /// The write-up: headings, "- " lists, blank lines between sections.
  final String summary;
  final List<RecordFinding> findings;
  final String unclear;
}

/// Why a scan could not be read, in words for the person holding it.
class ScanReadException implements Exception {
  const ScanReadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads scanned pages with Gemini. It reads them the way a person would,
/// from layout and context, not by looking for keywords: every supplier's
/// bill has its own columns and every clinician their own shorthand.
class ScanReader {
  ScanReader({GeminiJsonClient? client})
    : _client = client ?? GeminiJsonClient();

  final GeminiJsonClient _client;

  static const _timeout = Duration(seconds: 120);

  static const recordKinds = [
    'Lab report',
    'Prescription',
    'Imaging report',
    'Discharge summary',
    'Referral letter',
    'Certificate',
    'Insurance',
    'Other',
  ];

  // ───────────────────────── Session notes ─────────────────────────

  static final Schema _noteSchema = Schema.object(
    properties: {
      'transcript': Schema.string(
        description:
            'Everything written on the pages, in reading order, line by '
            'line, as written. Unreadable words as [illegible].',
      ),
      'notes': Schema.string(
        description:
            'The clean session notes: short headings each on their own '
            'line, content under them, a blank line between sections.',
      ),
      'title': Schema.string(
        description: 'What the session was about, in under 8 words.',
      ),
      'unclear': Schema.string(
        description:
            'Words, medicine names, doses or numbers that could not be '
            'read for certain. Empty if everything was clear.',
      ),
    },
    propertyOrdering: const ['transcript', 'notes', 'title', 'unclear'],
  );

  static const _noteSystem = '''
You read a clinician's handwritten session notes from photographs of the
pages (in page order) and write them up for the patient's record. The
clinician practises in India.

1. transcript: read every word first, faithfully, line by line, exactly as
   written, shorthand included. Write an unreadable word as [illegible].
2. notes: the same content, rewritten as clean, well-phrased clinical
   English a colleague can read at a glance:
   - Expand shorthand: c/o complains of, h/o history of, k/c/o known case
     of, o/e on examination, BD twice daily, TDS three times daily, OD once
     daily, HS at bedtime, SOS when needed, AC/PC before/after food,
     x5d for 5 days, Rx treatment, Ix investigations, Dx diagnosis,
     ↑ raised, ↓ reduced, +ve/-ve positive/negative.
   - Turn fragments into short sentences or bullet points; fix spelling and
     grammar; keep the clinician's meaning exactly.
   - Hindi, Marathi or other Indian-language words: write them in English.
   - Plain text, no markdown (no #, no **). Each heading on its own line,
     its content below, a blank line between sections, "- " for list items
     (findings, medicines, advice). Use only headings the pages have content
     for, in this order: Presenting complaint, History, Examination,
     Vitals, Assessment, Investigations, Treatment given, Medicines,
     Advice, Follow-up.
   - Medicines: one per line — name, strength, dose, frequency, duration,
     only as written.
   - A drawing or marked body chart: one line saying what it shows.
3. Never add anything that is not written: no symptom, finding, diagnosis,
   medicine, dose or advice of your own. Keep every number exactly (BP,
   pulse, doses, dates, scores). Keep left/right as written.
4. A medicine name or dose you are not sure of: write your best reading in
   notes and name it in unclear. Never swap in a different medicine.
5. Relative dates ("review after 1 week") are resolved against the session
   date given and written like "29 Oct 2026".
6. title: what the session was about, under 8 words.
7. If the pages are not clinical notes (a bill, a printed form, blank),
   return empty notes and title and say what they are in unclear.
8. Respond ONLY with a JSON object matching the schema.
''';

  Future<ScannedNote> readSessionNote(
    List<ScannedPage> pages, {
    required DateTime sessionDate,
    String clinician = 'a doctor',
  }) async {
    final json = await _read(
      system: _noteSystem,
      prompt:
          'Session date: ${_isoDate(sessionDate)}. The clinician is '
          '$clinician. Read these ${pages.length} handwritten page(s) and '
          'write up the session notes.',
      pages: pages,
      schema: _noteSchema,
    );
    final note = ScannedNote(
      title: _str(json['title']),
      notes: _str(json['notes']),
      transcript: _str(json['transcript']),
      unclear: _str(json['unclear']),
    );
    if (note.notes.isEmpty) {
      throw ScanReadException(
        note.unclear.isEmpty
            ? "These pages don't look like session notes."
            : note.unclear,
      );
    }
    return note;
  }

  // ───────────────────────── Supplier bills ─────────────────────────

  static final Schema _billSchema = Schema.object(
    properties: {
      'supplierName': Schema.string(
        description: 'The seller: the distributor or pharmacy that issued it.',
      ),
      'invoiceNumber': Schema.string(),
      'invoiceDate': Schema.string(description: 'YYYY-MM-DD, or empty.'),
      'items': Schema.array(
        items: Schema.object(
          properties: {
            'name': Schema.string(
              description:
                  'Product name with strength, without the form prefix: '
                  '"Dolo 650", "Augmentin 625 Duo", "Betadine 5% Solution".',
            ),
            'category': Schema.enumString(
              enumValues: const [
                'Tablet',
                'Capsule',
                'Syrup',
                'Injection',
                'Ointment',
                'Drops',
                'Powder',
                'Consumable',
                'Device',
                'Other',
              ],
            ),
            'unit': Schema.string(
              description:
                  'What quantity counts, singular: strip, bottle, box, '
                  'vial, ampoule, tube, packet, piece.',
            ),
            'pack': Schema.string(
              description: 'Pack size as printed ("10\'s", "1x15", "100ml").',
            ),
            'manufacturer': Schema.string(),
            'quantity': Schema.integer(description: 'Billed quantity.'),
            'freeQuantity': Schema.integer(
              description: 'Free / scheme / bonus quantity, 0 if none.',
            ),
            'batchNumber': Schema.string(),
            'expiryDate': Schema.string(
              description:
                  'YYYY-MM-DD. MM/YY on the bill means the last day of '
                  'that month. Empty if not printed.',
            ),
            'mrp': Schema.number(nullable: true),
            'unitPrice': Schema.number(
              nullable: true,
              description:
                  'Purchase rate for one unit before tax (Rate / PTR / '
                  'PTS). If only the line amount is printed, amount ÷ '
                  'quantity.',
            ),
            'gstPercent': Schema.number(nullable: true),
            'amount': Schema.number(nullable: true),
            'page': Schema.integer(
              description: 'Which page (1-based) the line is on.',
            ),
          },
          propertyOrdering: const [
            'name',
            'category',
            'unit',
            'pack',
            'manufacturer',
            'quantity',
            'freeQuantity',
            'batchNumber',
            'expiryDate',
            'mrp',
            'unitPrice',
            'gstPercent',
            'amount',
            'page',
          ],
        ),
      ),
      'total': Schema.number(
        nullable: true,
        description: 'Grand total payable, as printed.',
      ),
      'unclear': Schema.string(
        description: 'Anything that could not be read for certain.',
      ),
    },
    propertyOrdering: const [
      'supplierName',
      'invoiceNumber',
      'invoiceDate',
      'items',
      'total',
      'unclear',
    ],
  );

  static const _billSystem = '''
You read a purchase bill from a pharmaceutical distributor, chemist or
medical supplier in India (usually a GST tax invoice), photographed page
by page, and list what was bought so it can be added to a clinic's stock.

Every supplier lays out its bill differently. Work out what each column
means from its header and from the values in it, not from its position:
the same thing may be headed Qty / Quantity / Billed, Free / Sch / Bonus,
Pack / Packing / Unit, Batch / B.No / Lot, Exp / Expiry, MRP, Rate / PTR /
PTS / Price, Disc %, GST % / CGST + SGST / IGST, Amount / Net / Value, HSN,
Mfr / Mfg / Company. Columns may be missing, merged or handwritten.

1. One item per product line. Leave out everything that is not a product:
   totals, sub-totals, tax summaries, discounts, round off, freight,
   previous balance, scheme notes.
2. name: the product as a clinic would call it, with strength, without a
   form prefix like TAB, CAP, SYP, INJ (that goes in category). Write it in
   normal capitalisation ("Pan 40", not "PAN-40 TAB").
3. category from the form (TAB → Tablet, CAP → Capsule, SYP/SUSP →
   Syrup, INJ → Injection, OINT/CREAM/GEL → Ointment, DROP → Drops). Gloves,
   syringes, cotton, bandages, masks → Consumable. Instruments → Device.
4. unit and quantity: count what was billed — strips, bottles, boxes,
   vials, pieces — as the bill counts it. Free goods go in freeQuantity.
5. expiryDate: MM/YY or MM/YYYY becomes the last day of that month.
6. unitPrice: the purchase rate for one unit before tax. Keep MRP separate.
   Never use MRP as unitPrice.
7. Numbers exactly as printed. If a value is unreadable, leave it empty or
   null and name it in unclear — never guess a batch number.
8. page: which photographed page the line is on, counting from 1.
9. If this is not a purchase bill, return no items and say what it is in
   unclear.
10. Respond ONLY with a JSON object matching the schema.
''';

  Future<ScannedBill> readBill(List<ScannedPage> pages) async {
    final json = await _read(
      system: _billSystem,
      prompt:
          'Read this ${pages.length}-page bill and list every product '
          'bought.',
      pages: pages,
      schema: _billSchema,
    );
    final items = <BillItem>[
      for (final raw in (json['items'] as List?) ?? const [])
        if (raw is Map && _str(raw['name']).isNotEmpty)
          BillItem(
            name: _str(raw['name']),
            category: _str(raw['category']).isEmpty
                ? 'Other'
                : _str(raw['category']),
            unit: _str(raw['unit']).isEmpty ? 'piece' : _str(raw['unit']),
            pack: _str(raw['pack']),
            manufacturer: _str(raw['manufacturer']),
            quantity: _int(raw['quantity']),
            freeQuantity: _int(raw['freeQuantity']),
            batchNumber: _str(raw['batchNumber']),
            expiryDate: _date(raw['expiryDate']),
            mrp: _num(raw['mrp']),
            unitPrice: _num(raw['unitPrice']),
            gstPercent: _num(raw['gstPercent']),
            amount: _num(raw['amount']),
            page: _int(raw['page']).clamp(1, pages.length),
          ),
    ];
    final bill = ScannedBill(
      supplierName: _str(json['supplierName']),
      invoiceNumber: _str(json['invoiceNumber']),
      invoiceDate: _date(json['invoiceDate']),
      items: items,
      total: _num(json['total']),
      unclear: _str(json['unclear']),
    );
    if (items.isEmpty) {
      throw ScanReadException(
        bill.unclear.isEmpty
            ? 'No items were found on this bill.'
            : bill.unclear,
      );
    }
    return bill;
  }

  // ───────────────────────── Patient records ─────────────────────────

  static final Schema _recordSchema = Schema.object(
    properties: {
      'kind': Schema.enumString(enumValues: recordKinds),
      'title': Schema.string(
        description:
            'A file name a doctor would recognise: "CBC report, Metropolis '
            'Labs", "Discharge summary, Ruby Hall".',
      ),
      'date': Schema.string(description: 'Date of the document, YYYY-MM-DD.'),
      'source': Schema.string(
        description: 'Who issued it: lab, hospital, clinic or doctor.',
      ),
      'summary': Schema.string(
        description:
            'The write-up: short headings each on their own line, content '
            'below, a blank line between sections.',
      ),
      'findings': Schema.array(
        items: Schema.object(
          properties: {
            'name': Schema.string(),
            'value': Schema.string(),
            'unit': Schema.string(),
            'range': Schema.string(description: 'Reference range as printed.'),
            'flag': Schema.enumString(
              enumValues: const ['high', 'low', 'normal'],
            ),
          },
          propertyOrdering: const ['name', 'value', 'unit', 'range', 'flag'],
        ),
      ),
      'unclear': Schema.string(),
    },
    propertyOrdering: const [
      'kind',
      'title',
      'date',
      'source',
      'summary',
      'findings',
      'unclear',
    ],
  );

  static const _recordSystem = '''
You digitise a medical document for a patient's record in an Indian
clinic: a lab report, prescription, imaging report, discharge summary,
referral letter, certificate or similar, photographed page by page. It may
be printed or handwritten.

1. kind: what the document is. title: a short name a doctor would
   recognise in a file list (type plus issuer, e.g. "Lipid profile, Dr Lal
   PathLabs"). date: the report or issue date. source: who issued it.
2. summary: plain text, no markdown. Each heading on its own line, content
   below, a blank line between sections, "- " for list items. Write what
   the document says, clearly — for a report: what was tested and the
   impression or conclusion; for a prescription: diagnosis, each medicine
   with dose, frequency and duration, advice; for a discharge summary:
   diagnosis, course, procedures, medicines at discharge, follow-up.
   Expand shorthand (BD, TDS, OD, c/o, h/o).
3. findings: every measured result with its value, unit, reference range
   and flag (high / low when the value is outside the range or marked H/L,
   otherwise empty). Lab reports only; empty for other kinds.
4. Never add an interpretation, diagnosis or advice the document does not
   state. Keep every number exactly as printed.
5. Anything unreadable: leave it out and name it in unclear.
6. Respond ONLY with a JSON object matching the schema.
''';

  Future<ScannedRecord> readRecord(List<ScannedPage> pages) async {
    final json = await _read(
      system: _recordSystem,
      prompt: 'Digitise this ${pages.length}-page document.',
      pages: pages,
      schema: _recordSchema,
    );
    final kind = _str(json['kind']);
    return ScannedRecord(
      kind: recordKinds.contains(kind) ? kind : 'Other',
      title: _str(json['title']),
      date: _date(json['date']),
      source: _str(json['source']),
      summary: _str(json['summary']),
      findings: [
        for (final raw in (json['findings'] as List?) ?? const [])
          if (raw is Map && _str(raw['name']).isNotEmpty)
            RecordFinding(
              name: _str(raw['name']),
              value: _str(raw['value']),
              unit: _str(raw['unit']),
              range: _str(raw['range']),
              flag: _str(raw['flag']) == 'normal' ? '' : _str(raw['flag']),
            ),
      ],
      unclear: _str(json['unclear']),
    );
  }

  // ───────────────────────── Plumbing ─────────────────────────

  Future<Map<String, dynamic>> _read({
    required String system,
    required String prompt,
    required List<ScannedPage> pages,
    required Schema schema,
  }) async {
    final images = [for (final p in pages) p.jpeg];
    try {
      return await _client.generateJson(
        systemPrompt: system,
        prompt: prompt,
        images: images,
        schema: schema,
        maxOutputTokens: 16384,
        timeout: _timeout,
      );
    } on FormatException {
      // A truncated or chatty reply: once more, firmly.
      try {
        return await _client.generateJson(
          systemPrompt: system,
          prompt: '$prompt Respond ONLY with a valid JSON object.',
          images: images,
          schema: schema,
          maxOutputTokens: 16384,
          timeout: _timeout,
        );
      } catch (e) {
        throw _explain(e);
      }
    } catch (e) {
      throw _explain(e);
    }
  }

  static ScanReadException _explain(Object e) {
    debugPrint('[ScanReader] $e');
    if (e is ScanReadException) return e;
    if (e is TimeoutException) {
      return const ScanReadException(
        'Reading the scan took too long. Check the connection and try again.',
      );
    }
    if (e is GeminiHttpException) {
      if (e.isQuota) {
        return const ScanReadException(
          'The AI is busy right now. Try again in a minute.',
        );
      }
      if (e.isNotConfigured) {
        return const ScanReadException(
          "The AI isn't set up for this clinic yet.",
        );
      }
    }
    return const ScanReadException(
      "Couldn't read the scan. Check the connection and try again.",
    );
  }

  static String _isoDate(DateTime d) => d.toIso8601String().split('T').first;

  static String _str(Object? v) => v is String ? v.trim() : '';

  static int _int(Object? v) => v is num ? v.round() : 0;

  static double? _num(Object? v) => v is num && v > 0 ? v.toDouble() : null;

  static DateTime? _date(Object? v) {
    final s = _str(v);
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
}
