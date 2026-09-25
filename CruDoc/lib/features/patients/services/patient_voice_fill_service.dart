import 'dart:async';
import 'dart:io';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/services/gemini_json_client.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// Patient details heard in a voice recording. Every field is optional —
/// only what was actually said is set, and the form only overwrites the
/// fields that are set.
class PatientVoiceFill {
  const PatientVoiceFill({
    this.firstName = '',
    this.lastName = '',
    this.phone = '',
    this.email = '',
    this.gender,
    this.dateOfBirth,
    this.ageYears,
    this.conditions = const [],
    this.notes = '',
    this.packageBalance,
  });

  static const genders = ['Male', 'Female', 'Other'];

  final String firstName;
  final String lastName;
  final String phone;
  final String email;

  /// One of [genders], or null if not stated.
  final String? gender;
  final DateTime? dateOfBirth;

  /// Used when only an age was given (no date of birth).
  final int? ageYears;
  final List<String> conditions;
  final String notes;
  final double? packageBalance;

  /// Names of the fields that were heard, for the "filled …" message.
  List<String> get filledLabels => [
    if (firstName.isNotEmpty || lastName.isNotEmpty) 'name',
    if (phone.isNotEmpty) 'mobile',
    if (email.isNotEmpty) 'email',
    if (gender != null) 'sex',
    if (dateOfBirth != null) 'date of birth' else if (ageYears != null) 'age',
    if (conditions.isNotEmpty) 'conditions',
    if (notes.isNotEmpty) 'notes',
    if (packageBalance != null) 'package balance',
  ];

  bool get isEmpty => filledLabels.isEmpty;

  /// Date of birth, or one estimated from [ageYears] as of [today].
  DateTime? dateOfBirthOr(DateTime today) {
    if (dateOfBirth != null) return dateOfBirth;
    if (ageYears == null) return null;
    return DateTime(today.year - ageYears!, today.month, today.day);
  }

  /// Maps the model's JSON onto a fill, validating every value. Anything
  /// implausible (bad email, 3-digit phone, future birth date) is dropped
  /// rather than put in the form.
  factory PatientVoiceFill.fromJson(Map<String, dynamic> json, DateTime today) {
    String str(String key) {
      final v = json[key];
      if (v is! String) return '';
      final t = v.trim();
      return t.toLowerCase() == 'null' ? '' : t;
    }

    final phoneDigits = str('phone').replaceAll(RegExp(r'[^0-9+]'), '');
    final digitCount = phoneDigits.replaceAll('+', '').length;
    final phone = digitCount >= 7 && digitCount <= 15 ? phoneDigits : '';

    final rawEmail = str('email').replaceAll(' ', '').toLowerCase();
    final email = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$').hasMatch(rawEmail)
        ? rawEmail
        : '';

    final g = str('gender').toLowerCase();
    final gender = genders.where((x) => x.toLowerCase() == g).firstOrNull;

    DateTime? dob = DateTime.tryParse(str('dateOfBirth'));
    if (dob != null && (dob.isAfter(today) || dob.year < 1900)) dob = null;

    final ageRaw = json['ageYears'];
    final age = ageRaw is num ? ageRaw.round() : int.tryParse(str('ageYears'));

    final balanceRaw = json['packageBalance'];
    final balance = balanceRaw is num
        ? balanceRaw.toDouble()
        : double.tryParse(str('packageBalance').replaceAll(',', ''));

    final seen = <String>{};
    final conditions =
        (json['conditions'] is List ? json['conditions'] as List : const [])
            .whereType<String>()
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty && seen.add(c.toLowerCase()))
            .take(Patient.maxDiagnoses)
            .toList();

    return PatientVoiceFill(
      firstName: _titleCase(str('firstName')),
      lastName: _titleCase(str('lastName')),
      phone: phone,
      email: email,
      gender: gender,
      dateOfBirth: dob == null ? null : DateTime(dob.year, dob.month, dob.day),
      ageYears: age != null && age >= 0 && age <= 120 ? age : null,
      conditions: conditions,
      notes: str('notes'),
      packageBalance: balance != null && balance >= 0 ? balance : null,
    );
  }

  static String _titleCase(String s) => s
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// Records a short dictation and turns it into a [PatientVoiceFill].
///
/// Nothing is saved: the result only pre-fills the Add Patient form, and the
/// doctor still reviews it and taps Save.
class PatientVoiceFillService {
  PatientVoiceFillService({GeminiJsonClient? client, AudioRecorder? recorder})
    : _client = client ?? GeminiJsonClient(),
      _recorderOverride = recorder;

  final GeminiJsonClient _client;
  final AudioRecorder? _recorderOverride;

  // Created on first use so the service can exist without a mic plugin.
  late final AudioRecorder _recorder = _recorderOverride ?? AudioRecorder();
  String? _path;

  static const maxDuration = Duration(minutes: 3);
  static const _minAudioBytes = 2 * 1024;

  @visibleForTesting
  static final Schema responseSchema = Schema.object(
    properties: {
      'firstName': Schema.string(nullable: true),
      'lastName': Schema.string(nullable: true),
      'phone': Schema.string(
        nullable: true,
        description:
            'Digits only, e.g. "9876543210"; keep a + country '
            'code only if one was said.',
      ),
      'email': Schema.string(nullable: true),
      'gender': Schema.enumString(
        enumValues: PatientVoiceFill.genders,
        nullable: true,
      ),
      'dateOfBirth': Schema.string(
        nullable: true,
        description:
            'YYYY-MM-DD, only if a full or partial birth date was '
            'said.',
      ),
      'ageYears': Schema.integer(
        nullable: true,
        description: 'Age in years, only if an age was said.',
      ),
      'conditions': Schema.array(
        items: Schema.string(),
        description:
            'Diagnoses or presenting problems, e.g. "Low back '
            'pain", "Frozen shoulder (left)". At most 4.',
      ),
      'notes': Schema.string(
        nullable: true,
        description:
            'Other clinically useful details said: allergies, '
            'regular medicines, past surgeries, occupation, referring doctor.',
      ),
      'packageBalance': Schema.number(
        nullable: true,
        description: 'Advance or package amount paid, in rupees.',
      ),
    },
  );

  @visibleForTesting
  static const systemPrompt = '''
You fill in a clinic's "Add patient" form from a short voice recording.
The speaker is usually the doctor or receptionist dictating the details,
or a conversation with the patient. Speech may mix English with Hindi or
Marathi, and numbers may be spoken in any of these languages.

RULES:
1. Only fill fields that were actually said. Leave everything else null
   or empty — never guess.
2. Names: correct capitalisation. If a name is spelled out letter by
   letter, use the spelling. Put a single spoken name in firstName.
3. Phone: digits only. Convert spoken numbers ("double nine" = 99,
   "nau aath" = 98). Drop a leading 0 or +91 only if the rest is a
   10-digit Indian mobile.
4. Email: convert "at the rate" to @ and "dot" to ".", no spaces.
5. gender: Male / Female / Other only if stated, or clear from the words
   used (Mr, Mrs, Ms, "he", "she", "ladka", "ladki").
6. dateOfBirth only for a birth date; resolve partial dates against the
   given date. An age ("45 years old", "pachas saal") goes in ageYears.
7. conditions: short clinical terms, English, with side if said.
8. Respond ONLY with a JSON object matching the schema.
''';

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start() async {
    if (await _recorder.isRecording()) await _recorder.stop();
    final dir = await getTemporaryDirectory();
    _path =
        '${dir.path}${Platform.pathSeparator}voice_fill_${const Uuid().v4()}.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 32000,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _path!,
    );
  }

  Future<double> amplitude() async {
    try {
      return (await _recorder.getAmplitude()).current;
    } catch (_) {
      return -160;
    }
  }

  /// Stops recording and extracts the patient details. Throws
  /// [PatientVoiceFillException] with a message fit to show the doctor.
  Future<PatientVoiceFill> stopAndExtract({DateTime? today}) async {
    final path = await _recorder.stop() ?? _path;
    _path = null;
    if (path == null) {
      throw const PatientVoiceFillException('No recording found.');
    }
    final file = File(path);
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length < _minAudioBytes) {
        throw const PatientVoiceFillException(
          'That was too short. Tap the mic and say the patient details.',
        );
      }
      return await extract(bytes, today: today ?? DateTime.now());
    } on PatientVoiceFillException {
      rethrow;
    } catch (e) {
      throw PatientVoiceFillException(_messageFor(e));
    } finally {
      unawaited(file.delete().then((_) {}, onError: (_) {}));
    }
  }

  /// Sends [audioBytes] to Gemini and maps the reply. Separate from the
  /// recorder so it can be tested with a fixed audio file.
  Future<PatientVoiceFill> extract(
    Uint8List audioBytes, {
    required DateTime today,
    String mimeType = 'audio/mp4',
  }) async {
    final date = today.toIso8601String().split('T').first;
    final json = await _client.generateJson(
      systemPrompt: systemPrompt,
      prompt: "Today's date: $date. Extract the patient details.",
      audioBytes: audioBytes,
      mimeType: mimeType,
      schema: responseSchema,
      maxOutputTokens: 2048,
      timeout: const Duration(seconds: 45),
    );
    final fill = PatientVoiceFill.fromJson(json, today);
    if (fill.isEmpty) {
      throw const PatientVoiceFillException(
        "Couldn't hear any patient details. Try again, speaking a little "
        'closer to the mic.',
      );
    }
    return fill;
  }

  Future<void> cancel() async {
    try {
      await _recorder.cancel();
    } catch (_) {}
    _path = null;
  }

  Future<void> dispose() => _recorder.dispose();

  static String _messageFor(Object e) {
    debugPrint('[PatientVoiceFill] $e');
    if (e is TimeoutException) {
      return 'The AI took too long. Try again.';
    }
    if (e is SocketException) {
      return "You're offline. Connect to the internet to fill by voice.";
    }
    if (e is QuotaExceeded || (e is GeminiHttpException && e.isQuota)) {
      return 'AI usage limit reached. Try again in a minute.';
    }
    if (e is ServiceApiNotEnabled ||
        e is InvalidApiKey ||
        (e is GeminiHttpException && e.isNotConfigured)) {
      return "Voice fill isn't set up for this clinic yet.";
    }
    return "Couldn't fill the form from that recording. Try again.";
  }
}

class PatientVoiceFillException implements Exception {
  const PatientVoiceFillException(this.message);
  final String message;

  @override
  String toString() => message;
}
