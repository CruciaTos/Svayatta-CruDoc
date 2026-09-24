import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/models/physio_findings.dart';

/// Handles the core AI processing step for the scribe:
/// local audio → Gemini via Firebase AI Logic → structured draft note.
///
/// Model name is fetched from Remote Config (key: `scribe_gemini_model`)
/// so it can be updated without a code change or app release. Falls back to
/// [fallbackModel] if Remote Config is unreachable or the key is unset.
///
/// Follows §5/§10 of the feature plan:
/// - Uses [FirebaseAI.googleAI] (not raw REST with an embedded key)
/// - Structured JSON output via a declared response schema
/// - System prompt instructs the model to only extract what was said
/// - Malformed JSON is retried once; any other failure surfaces as a
///   [ScribeProcessingException]. A draft is never invented locally.
class ScribeProcessingService {
  static const remoteConfigModelKey = 'scribe_gemini_model';

  /// GA Flash model; Firebase lists its retirement as no earlier than
  /// 2027-05-19. `gemini-2.0-flash` (the previous value) was shut down on
  /// 2026-06-01. Prefer moving to a newer model via Remote Config.
  static const fallbackModel = 'gemini-3.5-flash';

  /// Recordings shorter than this are rejected before any API call.
  static const minRecordingDuration = Duration(seconds: 5);

  /// Recording auto-stops here. At the recorder's 32 kbps this is ~11 MB,
  /// which stays under Gemini's 20 MB inline request limit after base64.
  static const maxRecordingDuration = Duration(minutes: 45);

  static const _minAudioSizeBytes = 8 * 1024;
  static const _maxInlineAudioBytes = 14 * 1024 * 1024;
  static const _requestTimeout = Duration(seconds: 150);

  bool _remoteConfigLoaded = false;

  // ---- Structured output schema ----
  //
  // General fields plus a `physio` object generated from the specs in
  // [PhysioFindings], so the schema, review form and summary never drift.
  static final Schema _responseSchema = _buildSchema();

  static Schema _buildSchema() {
    final physioProps = <String, Schema>{
      for (final f in PhysioFindings.textSpecs)
        f.key: Schema.string(nullable: true, description: f.instruction),
      for (final f in PhysioFindings.listSpecs)
        f.key: Schema.array(items: Schema.string(), description: f.instruction),
      for (final t in PhysioFindings.tableSpecs)
        t.key: Schema.array(
          description: t.instruction,
          items: Schema.object(
            properties: {
              for (final c in t.columns)
                c.key: Schema.string(nullable: true, description: c.label),
            },
          ),
        ),
    };

    return Schema.object(
      properties: {
        'transcript': Schema.string(),
        'chiefComplaint': Schema.string(
          nullable: true,
          description:
              "The patient's main problem in one line, with side and "
              'duration, e.g. "Right knee pain for 3 weeks".',
        ),
        'symptoms': Schema.array(
          items: Schema.string(),
          description:
              'Associated symptoms reported (stiffness, swelling, giving '
              'way, clicking, tingling...).',
        ),
        'diagnosisSuggestions': Schema.array(
          items: Schema.string(),
          description:
              'Clinical impression / physiotherapy diagnosis the clinician '
              'stated, or a diagnosis the patient reports from a referring '
              'doctor.',
        ),
        'medicines': Schema.array(
          description:
              'Medicines the patient reports taking or the clinician named '
              '(painkillers, gels, supplements).',
          items: Schema.object(
            properties: {
              'name': Schema.string(),
              'dosage': Schema.string(nullable: true),
              'instructions': Schema.string(nullable: true),
            },
          ),
        ),
        'advice': Schema.string(
          nullable: true,
          description:
              'Education and advice given: activity modification, '
              'ergonomics, precautions, what to avoid, ice/heat at home.',
        ),
        'followUpDate': Schema.string(nullable: true),
        'vitalsIfMentioned': Schema.object(
          properties: {
            'bp': Schema.string(nullable: true),
            'temp': Schema.string(nullable: true),
            'pulse': Schema.string(nullable: true),
          },
        ),
        'physio': Schema.object(
          properties: physioProps,
          propertyOrdering: physioProps.keys.toList(),
        ),
        'transcriptSummaryConfidenceNote': Schema.string(nullable: true),
      },
      // Transcript first so every extracted field is grounded in it.
      propertyOrdering: const [
        'transcript',
        'chiefComplaint',
        'symptoms',
        'diagnosisSuggestions',
        'medicines',
        'advice',
        'followUpDate',
        'vitalsIfMentioned',
        'physio',
        'transcriptSummaryConfidenceNote',
      ],
    );
  }

  static const _systemPrompt = '''
You are a clinical documentation assistant for physiotherapists in India.
You transcribe a recorded physiotherapy session (assessment or treatment
visit) and extract a structured SOAP note from it.

CRITICAL RULES — read these carefully:
1. Only extract information that was ACTUALLY SAID during this recording.
2. Do NOT infer, guess, or add any diagnosis, finding, measurement,
   treatment or exercise that was not explicitly stated. A clinician
   saying "let us check how far the knee bends" is not a measurement —
   only record a value if it was spoken ("about 90 degrees").
3. If a field cannot be filled from what was said, leave it empty (empty
   string, empty list) or null — never fabricate content. Most sessions
   will leave many fields empty; that is expected.
4. Measurements: keep numbers exactly as spoken. Pain as "n/10". ROM in
   degrees. Muscle strength as "n/5" ("four by five" → "4/5", "4 plus" →
   "4+/5"). Always record the side (L / R / Bilateral) when it is stated.
5. Special tests: record the test name and whether it was positive or
   negative. Do not guess a result from the patient's reaction alone.
6. Red flags: put signs reported as present in physio.redFlags, and red
   flags the clinician asked about that the patient denied in
   physio.redFlagsCleared. Never mark a red flag cleared unless it was
   actually asked.
7. Separate what was DONE today (physio.treatment — manual therapy,
   electrotherapy with parameters, taping, dry needling, supervised
   exercise) from what the patient must do at HOME
   (physio.homeExercises, with sets, reps, hold time and frequency).
8. Medicines: list only medicines named in the recording. Physiotherapists
   usually record what the patient is taking — do not suggest any.
9. Diagnosis suggestions: only what the clinician stated as the clinical
   impression, or a diagnosis the patient reports from their doctor.
10. Vitals: only fill bp / temp / pulse if a value was spoken aloud.
11. followUpDate: an ISO date (YYYY-MM-DD) only if a specific next visit
    was given; resolve relative phrases ("come after 2 days", "next
    Monday") against the consultation date given in the request.
12. transcript: a faithful transcript. Prefix turns with "Doctor:" (the
    physiotherapist) or "Patient:" when it is clear who is speaking.
    Hindi, Marathi or other Indian languages may be mixed with English —
    transcribe them in Roman script. All other fields must be in concise
    clinical English using standard physiotherapy terms.
13. transcriptSummaryConfidenceNote: flag audio quality issues,
    overlapping speech, numbers you could not hear clearly, or anything
    you were unsure about. Leave it empty if the audio was clear.
14. If the recording contains no consultation (silence, noise, unrelated
    talk), return an empty transcript and empty fields, and explain in
    transcriptSummaryConfidenceNote.
15. Respond ONLY with a valid JSON object matching the requested schema.
''';

  /// Returns the model name from Remote Config, or [fallbackModel].
  Future<String> _modelName() async {
    try {
      final rc = FirebaseRemoteConfig.instance;
      if (!_remoteConfigLoaded) {
        _remoteConfigLoaded = true;
        await rc.setDefaults(const {remoteConfigModelKey: fallbackModel});
        await rc.fetchAndActivate().timeout(const Duration(seconds: 4));
      }
      final value = rc.getString(remoteConfigModelKey).trim();
      if (value.isNotEmpty) return value;
    } catch (e) {
      debugPrint('[ScribeProcessing] Remote Config unavailable: $e');
    }
    return fallbackModel;
  }

  /// Checks whether the audio file at [audioPath] is usable. Returns an
  /// error message if it should be rejected, or null if it's fine.
  Future<String?> validateAudio(String audioPath) async {
    try {
      final file = File(audioPath);
      if (!await file.exists()) return 'Recording file not found.';
      final size = await file.length();
      if (size < _minAudioSizeBytes) {
        return 'The recording is too short or empty. Please record at least '
            '${minRecordingDuration.inSeconds} seconds of the consultation.';
      }
      if (size > _maxInlineAudioBytes) {
        return 'The recording is too long to process in one go. Please keep '
            'recordings under ${maxRecordingDuration.inMinutes} minutes.';
      }
      return null;
    } catch (e) {
      return 'Could not read the recording file: $e';
    }
  }

  /// Processes the recorded audio and returns a structured draft note.
  ///
  /// [consentAt] is the moment the doctor confirmed patient consent.
  /// Throws [ScribeProcessingException] when no usable draft could be
  /// produced — the caller keeps the audio so the doctor can retry.
  Future<ConsultationNote> processAudio({
    required String localAudioPath,
    String? audioStoragePath,
    required String noteId,
    required String doctorId,
    required String patientId,
    required String visitId,
    required DateTime consentAt,
  }) async {
    final Uint8List audioBytes;
    try {
      audioBytes = await File(localAudioPath).readAsBytes();
    } catch (e) {
      throw ScribeProcessingException(
        'Could not read the recording from this device.',
        kind: ScribeFailureKind.audio,
        cause: e,
      );
    }

    final modelName = await _modelName();
    Map<String, dynamic> parsed;
    try {
      parsed = await _callGemini(modelName, audioBytes, consentAt);
    } on FormatException catch (e) {
      // Malformed or truncated JSON — retry once with a stricter prompt.
      debugPrint('[ScribeProcessing] Malformed response, retrying: $e');
      try {
        parsed = await _callGemini(
          modelName,
          audioBytes,
          consentAt,
          strictRetry: true,
        );
      } catch (retryError) {
        throw _classify(retryError);
      }
    } catch (e) {
      throw _classify(e);
    }

    return noteFromParsed(
      parsed: parsed,
      noteId: noteId,
      doctorId: doctorId,
      patientId: patientId,
      visitId: visitId,
      consentAt: consentAt,
      audioStoragePath: audioStoragePath,
      now: DateTime.now(),
    );
  }

  Future<Map<String, dynamic>> _callGemini(
    String modelName,
    Uint8List audioBytes,
    DateTime consultationDate, {
    bool strictRetry = false,
  }) async {
    final model = FirebaseAI.googleAI().generativeModel(
      model: modelName,
      systemInstruction: Content.system(_systemPrompt),
      generationConfig: GenerationConfig(
        temperature: 0.1,
        maxOutputTokens: 32768,
        responseMimeType: 'application/json',
        responseSchema: _responseSchema,
      ),
    );

    final date = consultationDate.toIso8601String().split('T').first;
    final prompt = strictRetry
        ? 'Consultation date: $date. Extract clinical information from this '
              'consultation recording. Keep the transcript under 800 words. '
              'Respond ONLY with a valid JSON object — no text outside it.'
        : 'Consultation date: $date. Transcribe this physiotherapy '
              'session and extract the clinical information into the '
              'requested SOAP JSON structure.';

    final response = await model
        .generateContent([
          Content.multi([
            TextPart(prompt),
            InlineDataPart('audio/mp4', audioBytes),
          ]),
        ])
        .timeout(_requestTimeout);

    final text = response.text ?? '';
    if (text.trim().isEmpty) {
      throw const FormatException('Empty response from the model.');
    }
    final decoded = jsonDecode(extractJson(text));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Response was not a JSON object.');
    }
    return decoded;
  }

  ScribeProcessingException _classify(Object error) {
    debugPrint('[ScribeProcessing] Processing failed: $error');
    if (error is ScribeProcessingException) return error;
    if (error is TimeoutException) {
      return ScribeProcessingException(
        'The AI took too long to respond. Your recording is still on this '
        'device — try again.',
        kind: ScribeFailureKind.timeout,
        cause: error,
      );
    }
    if (error is SocketException || error is HttpException) {
      return ScribeProcessingException(
        "You appear to be offline. Your recording is still on this device — "
        "retry once you're back online.",
        kind: ScribeFailureKind.offline,
        cause: error,
      );
    }
    if (error is QuotaExceeded) {
      return ScribeProcessingException(
        'The AI usage limit has been reached. Try again in a few minutes, '
        'or write the note manually.',
        kind: ScribeFailureKind.quota,
        cause: error,
      );
    }
    final raw = error.toString().toLowerCase();
    final modelMissing =
        raw.contains('not found') ||
        raw.contains('404') ||
        raw.contains('is not supported');
    if (error is ServiceApiNotEnabled ||
        error is InvalidApiKey ||
        modelMissing) {
      return ScribeProcessingException(
        "AI Scribe isn't available for this clinic yet (Firebase AI Logic or "
        "the configured model is not set up). You can still write the note "
        "manually.",
        kind: ScribeFailureKind.notConfigured,
        cause: error,
      );
    }
    if (error is FormatException) {
      return ScribeProcessingException(
        "The AI couldn't produce a readable note from this recording. Try "
        "again, or write the note manually.",
        kind: ScribeFailureKind.badResponse,
        cause: error,
      );
    }
    if (raw.contains('socket') ||
        raw.contains('network') ||
        raw.contains('failed host lookup') ||
        raw.contains('failed to resolve')) {
      return ScribeProcessingException(
        "You appear to be offline. Your recording is still on this device — "
        "retry once you're back online.",
        kind: ScribeFailureKind.offline,
        cause: error,
      );
    }
    return ScribeProcessingException(
      'Something went wrong while analysing the recording. Try again, or '
      'write the note manually.',
      kind: ScribeFailureKind.unknown,
      cause: error,
    );
  }

  /// Strips any surrounding markdown code fences or prose the model might
  /// have added despite instructions.
  @visibleForTesting
  static String extractJson(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('{')) return trimmed;
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start != -1 && end > start) return trimmed.substring(start, end + 1);
    return trimmed;
  }

  /// Maps the model's JSON onto a draft [ConsultationNote]. Tolerates missing
  /// keys and wrong types — anything unusable becomes an empty field.
  @visibleForTesting
  static ConsultationNote noteFromParsed({
    required Map<String, dynamic> parsed,
    required String noteId,
    required String doctorId,
    required String patientId,
    required String visitId,
    required DateTime consentAt,
    String? audioStoragePath,
    required DateTime now,
  }) {
    final vitalsRaw = parsed['vitalsIfMentioned'] is Map
        ? parsed['vitalsIfMentioned'] as Map
        : const {};
    final vitals = <String, String?>{
      for (final key in const ['bp', 'temp', 'pulse'])
        key: _cleanString(vitalsRaw[key]).isEmpty
            ? null
            : _cleanString(vitalsRaw[key]),
    };

    final medicinesRaw = parsed['medicines'] is List
        ? parsed['medicines'] as List
        : const [];
    final medicines = medicinesRaw
        .whereType<Map>()
        .map(
          (m) => NotedMedicine(
            name: _cleanString(m['name']),
            dosage: _cleanString(m['dosage']),
            instructions: _cleanString(m['instructions']),
          ),
        )
        .where((m) => m.name.isNotEmpty)
        .toList();

    DateTime? followUpDate;
    final followUpRaw = _cleanString(parsed['followUpDate']);
    if (followUpRaw.isNotEmpty) {
      followUpDate = DateTime.tryParse(followUpRaw);
    }

    return ConsultationNote(
      id: noteId,
      doctorId: doctorId,
      patientId: patientId,
      visitId: visitId,
      transcript: _cleanString(parsed['transcript']),
      chiefComplaint: _cleanString(parsed['chiefComplaint']),
      symptoms: _toStringList(parsed['symptoms']),
      diagnosisSuggestions: _toStringList(parsed['diagnosisSuggestions']),
      medicines: medicines,
      advice: _cleanString(parsed['advice']),
      followUpDate: followUpDate,
      vitals: vitals,
      physio: PhysioFindings.fromJson(parsed['physio']),
      confidenceNote: _cleanString(parsed['transcriptSummaryConfidenceNote']),
      consentGiven: true,
      consentAt: consentAt,
      audioStoragePath: audioStoragePath,
      status: ConsultationNoteStatus.draft,
      createdAt: now,
    );
  }

  static String _cleanString(Object? value) {
    if (value is! String) return '';
    final trimmed = value.trim();
    return trimmed.toLowerCase() == 'null' ? '' : trimmed;
  }

  static List<String> _toStringList(Object? value) {
    if (value is! List) return const [];
    final seen = <String>{};
    return value
        .map(_cleanString)
        .where((e) => e.isNotEmpty && seen.add(e.toLowerCase()))
        .toList();
  }
}

/// Why processing failed — lets the UI pick the right recovery options.
enum ScribeFailureKind {
  offline,
  timeout,
  notConfigured,
  quota,
  badResponse,
  audio,
  unknown;

  /// Whether retrying the same recording could plausibly succeed.
  bool get isRetryable =>
      this != ScribeFailureKind.notConfigured &&
      this != ScribeFailureKind.audio;
}

class ScribeProcessingException implements Exception {
  final String message;
  final ScribeFailureKind kind;
  final Object? cause;

  const ScribeProcessingException(
    this.message, {
    this.kind = ScribeFailureKind.unknown,
    this.cause,
  });

  @override
  String toString() => 'ScribeProcessingException(${kind.name}): $message';
}
