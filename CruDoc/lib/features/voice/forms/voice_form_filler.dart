import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/core/services/gemini_json_client.dart';
import 'package:doctor_management_app/features/voice/forms/voice_form_scan.dart';

/// What one spoken fill did to the form.
class VoiceFormFillResult {
  const VoiceFormFillResult({
    this.filled = const [],
    this.rejected = const {},
    this.kept = const [],
    this.unsure = '',
    this.blocked,
  });

  /// Labels of the inputs that were filled.
  final List<String> filled;

  /// Values that failed the input's checks: label → why.
  final Map<String, String> rejected;

  /// Inputs the doctor had typed in, left alone because the speech didn't
  /// name them.
  final List<String> kept;

  /// What the model wasn't sure where to put.
  final String unsure;

  /// Voice won't fill this form at all.
  final String? blocked;

  /// One line for the voice pill.
  String get summary {
    if (blocked != null) return blocked!;
    final parts = <String>[
      if (filled.isNotEmpty) 'Filled ${filled.join(', ')}',
      for (final e in rejected.entries) '${e.key}: ${e.value}',
      if (kept.isNotEmpty) 'Kept what you typed in ${kept.join(', ')}',
      if (unsure.isNotEmpty) 'Not sure: $unsure',
    ];
    if (parts.isEmpty) return "Didn't catch a value for any field";
    return [...parts, if (filled.isNotEmpty) 'Check it, then tap Save'].join(
      ' · ',
    );
  }
}

/// Fills the form on screen from what the doctor said, with guardrails:
///
/// - Only inputs the speech gave a value for are touched; the model is told
///   never to guess, and on a full screen (not a dialog) an input must be
///   named out loud before voice fills it.
/// - Every value is checked against its input — numbers must be numbers,
///   phone numbers 10 digits, emails well-formed, choices one of the
///   options shown — and goes through the input's own formatters, as if
///   typed. A value that fails is reported, never forced in.
/// - Something the doctor typed by hand is only replaced when they name
///   that input ("change the dose to 250").
/// - Password, OTP and payment inputs are never filled (see
///   [VoiceFormScan.blockedReason]); their values are never sent anywhere.
/// - Nothing is saved: the doctor checks the form and taps Save.
/// - "Undo" puts back everything the last fill changed.
///
/// Only the spoken words and the inputs' labels and options go to the
/// model — never what the form already holds. Without the model (offline,
/// not configured) it falls back to "label … value" matching.
class VoiceFormFiller {
  VoiceFormFiller({GeminiJsonClient? client}) : _clientOverride = client;

  final GeminiJsonClient? _clientOverride;
  GeminiJsonClient? _client;
  GeminiJsonClient get _gemini =>
      _clientOverride ?? (_client ??= GeminiJsonClient());

  static const _timeout = Duration(seconds: 20);

  /// Inputs voice itself filled, by [VoiceFormField.key].
  final _voiceSet = <String>{};
  List<VoidCallback> _undo = const [];

  bool get canUndo => _undo.isNotEmpty;

  /// Puts back what the last fill changed. Returns how many inputs.
  int undo() {
    final steps = _undo;
    _undo = const [];
    for (final restore in steps.reversed) {
      restore();
    }
    return steps.length;
  }

  @visibleForTesting
  static final Schema responseSchema = Schema.object(
    properties: {
      'fills': Schema.array(
        items: Schema.object(
          properties: {'id': Schema.string(), 'value': Schema.string()},
        ),
      ),
      'unsure': Schema.string(
        nullable: true,
        description: 'Values heard that could not be placed with confidence.',
      ),
    },
  );

  @visibleForTesting
  static const systemPrompt = '''
You fill in a form in a clinic app from what the user just said. You get the
form's fields (id, label, type and, for choices, the options) and the words
spoken. Return the values the user gave, one per field.

RULES:
1. Only fill a field the user actually gave a value for. Never guess, never
   fill a field from general knowledge, never copy one value into two fields.
2. Decide where a value goes from the field labels. If a value could belong
   to more than one field, leave it out and mention it in "unsure".
3. Value formats by type:
   - number: digits only, with a decimal point if needed ("five hundred" →
     "500", "two and a half" → "2.5"). No units.
   - phone: the digits only.
   - email: a plain address ("ravi at gmail dot com" → "ravi@gmail.com").
   - choice: exactly one of the field's options, copied character for
     character. If what was said matches none of them, leave it out.
   - toggle: "yes" or "no".
   - list: the items, separated by commas.
   - text / multiline: what was said for it, concise, in English, keeping
     names, medicine names, doses and units exactly as spoken.
4. Words like "save", "cancel", "and", "please", and the field names
   themselves are not values.
5. Respond ONLY with a JSON object matching the schema.
''';

  /// Fills [scan]'s inputs from [utterance]. Never throws.
  Future<VoiceFormFillResult> fill(
    String utterance,
    VoiceFormScan scan, {
    DateTime? now,
  }) async {
    if (scan.blockedReason != null) {
      return VoiceFormFillResult(blocked: scan.blockedReason);
    }
    final text = utterance.trim();
    if (text.isEmpty || scan.fields.isEmpty) return const VoiceFormFillResult();

    var unsure = '';
    Map<String, String> values;
    try {
      final parsed = await _ask(text, scan.fields, now ?? DateTime.now());
      values = _valuesFrom(parsed);
      final u = parsed['unsure'];
      if (u is String && u.trim().toLowerCase() != 'null') unsure = u.trim();
    } catch (e) {
      debugPrint('[VoiceForm] Model unavailable, matching labels: $e');
      values = matchByLabel(text, scan.fields);
    }

    // On a full screen, voice only fills inputs named out loud, so a
    // command meant for the app never lands in a form by accident.
    if (!scan.inPopup) {
      values.removeWhere((id, _) {
        final f = scan.fields.where((f) => f.id == id).firstOrNull;
        return f == null || !mentions(text, f.label);
      });
    }

    final byId = {for (final f in scan.fields) f.id: f};
    final filled = <String>[];
    final rejected = <String, String>{};
    final kept = <String>[];
    final undo = <VoidCallback>[];
    for (final entry in values.entries) {
      final field = byId[entry.key];
      if (field == null) continue;

      final typedByHand =
          field.current.trim().isNotEmpty &&
          field.type != VoiceFieldType.toggle &&
          field.type != VoiceFieldType.choice &&
          !_voiceSet.contains(field.key);
      if (typedByHand && !mentions(text, field.label)) {
        kept.add(field.label);
        continue;
      }

      final check = normalise(field, entry.value);
      if (check.error != null) {
        rejected[field.label] = check.error!;
        continue;
      }
      if (field.current == check.value) continue;
      final restore = field.snapshot();
      if (field.write(check.value!)) {
        undo.add(restore);
        _voiceSet.add(field.key);
        filled.add(field.label);
      } else {
        rejected[field.label] = "the form didn't accept “${entry.value}”";
      }
    }
    if (undo.isNotEmpty) _undo = undo;
    return VoiceFormFillResult(
      filled: filled,
      rejected: rejected,
      kept: kept,
      unsure: unsure,
    );
  }

  Future<Map<String, dynamic>> _ask(
    String text,
    List<VoiceFormField> fields,
    DateTime now,
  ) {
    final described = [
      for (final f in fields)
        {
          'id': f.id,
          'label': f.label,
          'type': f.type.name,
          if (f.options.isNotEmpty) 'options': f.options,
        },
    ];
    final prompt = [
      'Today is ${now.toIso8601String().split('T').first}.',
      'FIELDS:',
      jsonEncode(described),
      'SPOKEN:',
      text,
    ].join('\n');
    return _gemini.generateJson(
      systemPrompt: systemPrompt,
      prompt: prompt,
      schema: responseSchema,
      maxOutputTokens: 2048,
      timeout: _timeout,
      feature: 'voice_form',
    );
  }

  static Map<String, String> _valuesFrom(Map<String, dynamic> parsed) {
    final out = <String, String>{};
    final fills = parsed['fills'];
    if (fills is! List) return out;
    for (final f in fills.whereType<Map>()) {
      final id = f['id'];
      final value = f['value'];
      if (id is! String || value is! String) continue;
      final v = value.trim();
      if (v.isEmpty || v.toLowerCase() == 'null') continue;
      // The same input twice: the model contradicted itself; trust neither.
      if (out.containsKey(id)) {
        out.remove(id);
        continue;
      }
      out[id] = v;
    }
    return out;
  }

  /// Checks [raw] against what [field] accepts and puts it in the form the
  /// input expects.
  @visibleForTesting
  static ({String? value, String? error}) normalise(
    VoiceFormField field,
    String raw,
  ) {
    final v = raw.trim();
    switch (field.type) {
      case VoiceFieldType.number:
        final m = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(v.replaceAll(',', ''));
        if (m == null) return (value: null, error: "“$v” isn't a number");
        return (value: m.group(0), error: null);
      case VoiceFieldType.phone:
        var digits = v.replaceAll(RegExp(r'\D'), '');
        if (digits.length == 12 && digits.startsWith('91')) {
          digits = digits.substring(2);
        } else if (digits.length == 11 && digits.startsWith('0')) {
          digits = digits.substring(1);
        }
        if (digits.length != 10) {
          return (value: null, error: "“$v” isn't a 10-digit number");
        }
        return (value: digits, error: null);
      case VoiceFieldType.email:
        final e = v
            .toLowerCase()
            .replaceAll(RegExp(r'\s+at\s+'), '@')
            .replaceAll(RegExp(r'\s+dot\s+'), '.')
            .replaceAll(RegExp(r'\s+'), '');
        if (!RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$').hasMatch(e)) {
          return (value: null, error: "“$v” isn't an email address");
        }
        return (value: e, error: null);
      case VoiceFieldType.choice:
        final match = matchOption(v, field.options);
        if (match == null) {
          return (value: null, error: "“$v” isn't one of the options");
        }
        return (value: match, error: null);
      case VoiceFieldType.toggle:
        final s = v.toLowerCase();
        if (RegExp(r'^(yes|y|true|on|checked|tick|enable|enabled)$').hasMatch(s)) {
          return (value: 'yes', error: null);
        }
        if (RegExp(r'^(no|n|false|off|unchecked|untick|disable|disabled)$')
            .hasMatch(s)) {
          return (value: 'no', error: null);
        }
        return (value: null, error: "say yes or no for it");
      case VoiceFieldType.text:
      case VoiceFieldType.multiline:
      case VoiceFieldType.list:
        if (v.length > 2000) {
          return (value: null, error: 'too long to fill by voice');
        }
        return (value: v, error: null);
    }
  }

  /// The one option [said] refers to, or null if none or several do.
  @visibleForTesting
  static String? matchOption(String said, List<String> options) {
    final s = _norm(said);
    if (s.isEmpty) return null;
    for (final o in options) {
      if (_norm(o) == s) return o;
    }
    final partial = [
      for (final o in options)
        if (_norm(o).isNotEmpty &&
            (_norm(o).contains(s) || s.contains(_norm(o))))
          o,
    ];
    return partial.length == 1 ? partial.single : null;
  }

  /// Whether [text] names the input labelled [label].
  static bool mentions(String text, String label) {
    final t = ' ${_norm(text)} ';
    return _namesFor(label).any((n) => t.contains(' $n '));
  }

  /// The ways an input can be named: its label, the label without what's
  /// in brackets, and a lone main word ("Dose (mg)" is named by "dose";
  /// "Date of birth" isn't named by "date").
  static List<String> _namesFor(String label) {
    final full = _norm(label);
    final bare = _norm(label.replaceAll(RegExp(r'\([^)]*\)'), ' '));
    final words = bare.split(' ').where((w) => w.length >= 4).toList();
    return {
      if (full.isNotEmpty) full,
      if (bare.isNotEmpty) bare,
      if (words.length == 1 && bare.split(' ').length <= 2) words.single,
    }.toList();
  }

  /// Offline fallback: "dose 500 mg, frequency twice daily" → each named
  /// input gets the words after its name, up to the next name.
  @visibleForTesting
  static Map<String, String> matchByLabel(
    String text,
    List<VoiceFormField> fields,
  ) {
    final s = text.toLowerCase();
    final hits = <({int start, int end, VoiceFormField field})>[];
    for (final f in fields) {
      for (final name in _namesFor(f.label)) {
        final pattern = name.split(' ').map(RegExp.escape).join(r'\W+');
        final m = RegExp('\\b$pattern\\b').firstMatch(s);
        if (m == null) continue;
        hits.add((start: m.start, end: m.end, field: f));
        break;
      }
    }
    hits.sort((a, b) => a.start.compareTo(b.start));
    final out = <String, String>{};
    for (var i = 0; i < hits.length; i++) {
      final from = hits[i].end;
      final to = i + 1 < hits.length ? hits[i + 1].start : s.length;
      if (to <= from) continue;
      final value = text
          .substring(from, to)
          .replaceFirst(
            RegExp(r'^\s*(is|are|to|as|of|=|:|should be|will be)\b\s*|^\s*[:=]\s*',
                caseSensitive: false),
            '',
          )
          .replaceFirst(RegExp(r'[\s,.;]*(and)?[\s,.;]*$', caseSensitive: false), '')
          .trim();
      if (value.isNotEmpty) out[hits[i].field.id] = value;
    }
    return out;
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
