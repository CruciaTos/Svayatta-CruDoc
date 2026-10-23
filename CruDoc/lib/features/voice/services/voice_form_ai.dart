import 'dart:async';
import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/services/gemini_json_client.dart';

/// The forms voice can fill, each with the fields Gemini may return.
enum VoiceForm {
  patient,
  appointment,
  item,
  transaction,
  invoice;

  /// From [VoiceBus.openKind].
  static VoiceForm? ofKind(String? kind) => switch (kind) {
    'addPatient' || 'editPatient' => patient,
    'appointment' || 'reschedule' => appointment,
    'item' => item,
    'transaction' => transaction,
    'invoice' => invoice,
    _ => null,
  };
}

/// Reads one finished utterance into a form's fields with Gemini.
///
/// The keyword rules fill forms live while the doctor talks; this pass
/// reads the whole sentence once they stop and corrects what the rules
/// got wrong (names that swallowed a word, a complaint filed as the
/// visit reason, "five hundred and fifty"), and is the only reader for
/// forms the rules don't know (inventory items, payments, invoices).
///
/// Returns null when Gemini is unavailable or slow: the rules' fill
/// stands.
class VoiceFormAi {
  VoiceFormAi({GeminiJsonClient? client}) : _client = client;

  static final instance = VoiceFormAi();

  GeminiJsonClient? _client;
  GeminiJsonClient get _gemini => _client ??= GeminiJsonClient();

  /// Gemini didn't answer or isn't set up: stop asking for a while, so
  /// every utterance doesn't wait out the timeout.
  DateTime? _offUntil;

  static const timeout = Duration(seconds: 6);

  Future<Map<String, dynamic>?> read(
    VoiceForm form,
    String text, {
    required DateTime now,
    Map<String, Object?> current = const {},
    Map<String, List<String>> choices = const {},
  }) async {
    final said = text.trim();
    if (said.isEmpty) return null;
    final off = _offUntil;
    if (off != null && DateTime.now().isBefore(off)) return null;
    final started = DateTime.now();
    for (var attempt = 1; ; attempt++) {
      final left = timeout - DateTime.now().difference(started);
      try {
        final json = await _gemini
            .generateJson(
              systemPrompt: _system,
              prompt: _prompt(form, said, now, current, choices),
              schema: _schemas[form]!,
              maxOutputTokens: 1024,
              timeout: left,
              quick: true,
              feature: 'voice_form_ai',
            )
            .timeout(left);
        _offUntil = null;
        return json;
      } catch (e) {
        debugPrint('[VoiceFormAi] ${form.name}: ${e.runtimeType} $e');
        // "High demand" passes in a moment: ask once more while there's
        // time, and keep asking on the next utterance.
        final busy = e is GeminiHttpException && e.statusCode >= 500;
        if (busy &&
            attempt == 1 &&
            DateTime.now().difference(started) < timeout ~/ 2) {
          continue;
        }
        if (!busy) _offUntil = DateTime.now().add(const Duration(minutes: 2));
        return null;
      }
    }
  }

  static const _system = '''
You turn one spoken sentence from a doctor or receptionist in an Indian
clinic into the fields of the form on their screen. The words come from
speech-to-text: expect misheard words, missing punctuation, numbers
written as words ("nine eight seven…", "five hundred", "two thousand
five hundred", "one lakh"), Indian English, and Hindi or Marathi mixed
in ("paanch sau", "kal", "parso", "subah", "shaam").

Rules:
- Fill a field only if this sentence says it. Everything else is null
  (or an empty list). Never guess or invent values.
- Command words are not values: "add patient", "new item", "record
  payment", "and confirm", "save it", "please" are not names or notes.
- Correct obvious speech-to-text slips when the meaning is clear
  ("para cetamol" → "Paracetamol", "amoxy clav" → "Amoxiclav", "jai
  hind" in a name stays as said).
- Names: proper case. Medicine names: their usual brand or generic
  spelling, strength kept with the name ("Paracetamol 500mg").
- Phone numbers: digits only, 10 digits for Indian mobiles; drop a
  leading +91 or 0.
- Money: a plain number of rupees ("2.5k" → 2500, "1.5 lakh" → 150000).
- Dates: YYYY-MM-DD, worked out from today's date given below. An expiry
  said as month and year means the last day of that month.
- Times: 24-hour HH:mm ("5 in the evening" → 17:00, "quarter past four"
  → 16:15; a bare hour from 1 to 7 is afternoon/evening at a clinic).
- If the current form values are given, the sentence may change them
  ("make it 50", "no, the price is 30"): return the new value.
''';

  static String _prompt(
    VoiceForm form,
    String said,
    DateTime now,
    Map<String, Object?> current,
    Map<String, List<String>> choices,
  ) {
    final today = DateFormat('EEEE d MMMM yyyy, HH:mm').format(now);
    final what = switch (form) {
      VoiceForm.patient => 'Add or edit patient',
      VoiceForm.appointment => 'Book or move an appointment',
      VoiceForm.item => 'Add an inventory item (medicine or supply)',
      VoiceForm.transaction => 'Record a payment received or an expense',
      VoiceForm.invoice => 'Create a patient invoice',
    };
    final shown = {
      for (final e in current.entries)
        if (e.value != null && '${e.value}'.isNotEmpty)
          e.key: e.value is DateTime
              ? DateFormat('yyyy-MM-dd').format(e.value! as DateTime)
              : e.value,
    };
    return [
      'Form: $what.',
      'Today: $today.',
      if (shown.isNotEmpty) 'Current form values: ${jsonEncode(shown)}',
      for (final c in choices.entries)
        if (c.value.isNotEmpty) 'Listed ${c.key}: ${c.value.join(', ')}',
      'Sentence: "$said"',
    ].join('\n');
  }

  static Schema _str(String description) =>
      Schema.string(nullable: true, description: description);
  static Schema _int(String description) =>
      Schema.integer(nullable: true, description: description);
  static Schema _num(String description) =>
      Schema.number(nullable: true, description: description);
  static Schema _bool(String description) =>
      Schema.boolean(nullable: true, description: description);

  static final _schemas = <VoiceForm, Schema>{
    VoiceForm.patient: Schema.object(
      properties: {
        'firstName': _str('Patient first name.'),
        'lastName': _str('Surname; all the rest of the name.'),
        'age': _int('Age in years, only when no birth date was said.'),
        'dateOfBirth': _str('YYYY-MM-DD.'),
        'gender': Schema.enumString(
          enumValues: const ['Male', 'Female', 'Other'],
          nullable: true,
          description: 'Also from "he"/"she" or Mr/Mrs.',
        ),
        'phone': _str('Mobile number, digits only.'),
        'email': _str('Email address, written normally.'),
        'conditions': Schema.array(
          items: Schema.string(),
          description:
              'Diagnoses, complaints and chronic conditions, short and '
              'title case: "Low back pain", "Diabetes". At most 4.',
        ),
        'notes': _str(
          'Other clinical details: allergies, regular medicines, surgeries, '
          'how long a complaint has lasted, occupation, referred by.',
        ),
        'balance': _num('Package or advance amount, rupees.'),
        'address': _str('Home address.'),
      },
    ),
    VoiceForm.appointment: Schema.object(
      properties: {
        'date': _str('Appointment day, YYYY-MM-DD.'),
        'time': _str('Start time, HH:mm (24-hour), only if a time was said.'),
        'slot': Schema.enumString(
          enumValues: const ['morning', 'afternoon', 'evening', 'any'],
          nullable: true,
          description:
              'Part of the day, or "any" for "next free slot", only when no '
              'exact time was said.',
        ),
        'shiftMinutes': _int(
          'Moving the current time by an amount: "an hour later" → 60, '
          '"30 minutes earlier" → -30.',
        ),
        'durationMinutes': _int('Length of the visit in minutes.'),
        'reason': _str(
          'Why they are coming: "Root canal", "Follow-up", "Knee pain".',
        ),
        'notes': _str('Any other remark for this visit.'),
        'homeVisit': _bool('true for a home visit, false for in the clinic.'),
        'address': _str('Address for a home visit.'),
        'sendWhatsApp': _bool('Whether to send a WhatsApp confirmation.'),
        'addToQueue': _bool('Whether to add them to today\'s queue.'),
      },
    ),
    VoiceForm.item: Schema.object(
      properties: {
        'name': _str('Item name with strength: "Paracetamol 500mg".'),
        'category': _str(
          'One of the listed categories if one fits, else a short category.',
        ),
        'unit': _str('One of the listed units if one fits.'),
        'stock': _int('Quantity in stock now, in units.'),
        'reorderLevel': _int('Reorder when stock falls to this.'),
        'goodStockLevel': _int('A comfortable stock level.'),
        'unitPrice': _num('Price of one unit, rupees.'),
        'supplier': _str('Supplier, vendor, distributor or brand company.'),
        'batch': _str('Batch or lot number, as said.'),
        'expiryDate': _str('YYYY-MM-DD.'),
      },
    ),
    VoiceForm.transaction: Schema.object(
      properties: {
        'kind': Schema.enumString(
          enumValues: const ['payment', 'expense', 'pending'],
          nullable: true,
          description:
              'payment = money received; expense = money spent; pending = '
              'money still to be received. Only if the sentence says which.',
        ),
        'amount': _num('Rupees.'),
        'category': _str('One of the listed categories if one fits.'),
        'description': _str('What it was for, a few words.'),
        'payer': _str(
          'Who paid (payment) or who was paid (expense): patient, vendor, '
          'landlord, staff name.',
        ),
        'notes': _str('Payment mode (cash, UPI, card, cheque) and remarks.'),
        'date': _str('YYYY-MM-DD, only if a day was said.'),
      },
    ),
    VoiceForm.invoice: Schema.object(
      properties: {
        'patientName': _str('Who the invoice is for.'),
        'treatments': Schema.array(
          items: Schema.object(
            properties: {
              'name': Schema.string(description: 'Treatment or service.'),
              'price': Schema.number(description: 'Rupees.'),
            },
          ),
          description: 'Treatments, procedures, consultations with prices.',
        ),
        'medicines': Schema.array(
          items: Schema.object(
            properties: {
              'name': Schema.string(),
              'dosage': Schema.string(
                description: 'Dose or quantity, "" if not said.',
              ),
              'price': Schema.number(description: 'Rupees.'),
            },
          ),
          description: 'Medicines sold with prices.',
        ),
        'discount': _num('Discount in rupees.'),
        'status': Schema.enumString(
          enumValues: const ['Paid', 'Pending', 'Overdue'],
          nullable: true,
        ),
        'dueDate': _str('YYYY-MM-DD.'),
        'notes': _str('Clinical notes or remarks for the invoice.'),
      },
    ),
  };
}

/// Reading Gemini's values safely: wrong types and "null" strings become
/// null.
abstract final class AiValue {
  static String? str(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty || t.toLowerCase() == 'null' ? null : t;
  }

  static int? integer(Object? v) => switch (v) {
    int() => v,
    double() when v.isFinite => v.round(),
    String() => int.tryParse(v.trim()),
    _ => null,
  };

  static double? number(Object? v) => switch (v) {
    num() when v.isFinite => v.toDouble(),
    String() => double.tryParse(v.replaceAll(RegExp(r'[^0-9.]'), '')),
    _ => null,
  };

  static bool? boolean(Object? v) => v is bool ? v : null;

  /// YYYY-MM-DD.
  static DateTime? date(Object? v) {
    final s = str(v);
    if (s == null) return null;
    final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
    if (m == null) return null;
    final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    return DateTime(y, mo, d);
  }

  /// HH:mm, as (hour, minute).
  static (int, int)? time(Object? v) {
    final s = str(v);
    if (s == null) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(s);
    if (m == null) return null;
    final h = int.parse(m[1]!), mi = int.parse(m[2]!);
    if (h > 23 || mi > 59) return null;
    return (h, mi);
  }

  static List<String> strings(Object? v) => [
    if (v is List)
      for (final e in v) ?str(e),
  ];

  /// [v] as one of [options] when it names one ("tablet" → "Tablets",
  /// "syrup" → "Syrup (ml)"), else [v] itself.
  static String pick(String v, List<String> options) {
    String key(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .replaceAll(RegExp(r's$'), '');
    final k = key(v);
    if (k.isEmpty) return v;
    for (final o in options) {
      if (key(o) == k) return o;
    }
    for (final o in options) {
      final ko = key(o);
      if (ko.length >= 4 && (ko.startsWith(k) || k.startsWith(ko))) return o;
    }
    return v;
  }

  static List<Map<String, dynamic>> objects(Object? v) => [
    if (v is List)
      for (final e in v)
        if (e is Map) e.cast<String, dynamic>(),
  ];
}
