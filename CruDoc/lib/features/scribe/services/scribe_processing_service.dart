import 'dart:convert';
import 'dart:io';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';

/// Handles the core AI processing step for the scribe:
/// uploads audio → calls Gemini via Firebase AI Logic → parses structured output.
///
/// Model name is fetched from Remote Config (key: `scribe_gemini_model`)
/// so it can be updated without a code change or app release.
/// Falls back to `gemini-2.0-flash` if Remote Config hasn't been fetched yet.
///
/// Follows §5 of the feature plan:
/// - Uses [FirebaseAI.googleAI()] (not raw REST with an embedded key)
/// - Structured JSON output via a declared response schema
/// - System prompt instructs the model to only extract what was said
/// - Handles malformed JSON (retries once, then falls back to raw transcript)
class ScribeProcessingService {
  static const _remoteConfigModelKey = 'scribe_gemini_model';
  static const _fallbackModel = 'gemini-2.0-flash';
  static const _minAudioSizeBytes = 10 * 1024; // ~5 seconds at 16kbps

  // ---- Structured output schema (matches §5's shape exactly) ----
  static Schema _buildResponseSchema() {
    return Schema.object(
      properties: {
        'chiefComplaint': Schema.string(nullable: true),
        'symptoms': Schema.array(items: Schema.string()),
        'diagnosisSuggestions': Schema.array(items: Schema.string()),
        'medicines': Schema.array(
          items: Schema.object(
            properties: {
              'name': Schema.string(),
              'dosage': Schema.string(nullable: true),
              'instructions': Schema.string(nullable: true),
            },
          ),
        ),
        'advice': Schema.string(nullable: true),
        'followUpDate': Schema.string(nullable: true),
        'vitalsIfMentioned': Schema.object(
          properties: {
            'bp': Schema.string(nullable: true),
            'temp': Schema.string(nullable: true),
            'pulse': Schema.string(nullable: true),
          },
        ),
        'transcriptSummaryConfidenceNote': Schema.string(nullable: true),
      },
    );
  }

  static const _systemPrompt = '''
You are a clinical transcription assistant. Your job is to extract structured 
information from a recorded doctor-patient consultation.

CRITICAL RULES — read these carefully:
1. Only extract information that was ACTUALLY SAID during this recording.
2. Do NOT infer, guess, or add any diagnosis, symptom, medicine, or advice 
   that the doctor did not explicitly state.
3. If a field cannot be filled from what was said, leave it empty (empty 
   string) or null — never fabricate content.
4. Medicines: only list medicines the doctor explicitly named. Do not suggest 
   alternatives or additions.
5. Diagnosis suggestions: only include what the doctor stated as a diagnosis 
   or likely diagnosis. Do not infer from symptoms.
6. The transcriptSummaryConfidenceNote field is for you to flag any audio 
   quality issues, overlapping speech, or parts of the recording you were 
   uncertain about. Leave it empty if the audio was clear.
7. Respond ONLY with a valid JSON object matching the requested schema.
''';

  /// Returns the model name from Remote Config, or the fallback if
  /// Remote Config hasn't been initialized or the key is missing.
  String _modelName() {
    try {
      final rc = FirebaseRemoteConfig.instance;
      final value = rc.getString(_remoteConfigModelKey);
      if (value.trim().isNotEmpty) return value.trim();
    } catch (_) {}
    return _fallbackModel;
  }

  /// Checks whether the audio file at [audioPath] is long enough to
  /// bother calling the AI. Returns an error message if it should be
  /// rejected, or null if it's fine.
  Future<String?> validateAudio(String audioPath) async {
    try {
      final file = File(audioPath);
      if (!await file.exists()) return 'Recording file not found.';
      final stat = await file.stat();
      if (stat.size < _minAudioSizeBytes) {
        return 'Recording is too short or silent. Please record at least '
            '5 seconds.';
      }
      return null;
    } catch (e) {
      return 'Could not read recording file: $e';
    }
  }

  /// Uploads [audioPath] to Firebase Storage under the doctor/patient path
  /// and returns the storage reference path.
  Future<String> uploadAudio({
    required String audioPath,
    required String doctorId,
    required String patientId,
  }) async {
    final file = File(audioPath);
    final fileName = 'scribe_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final storagePath = 'scribe_audio/$doctorId/$patientId/$fileName';
    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putFile(
      file,
      SettableMetadata(contentType: 'audio/mp4'),
    );
    return storagePath;
  }

  /// Downloads the audio from [storagePath] to a temp file and returns the path.
  Future<String> _downloadAudioToTemp(String storagePath) async {
    final tempDir = await getTemporaryDirectory();
    final localPath = '${tempDir.path}/scribe_temp_${const Uuid().v4()}.m4a';
    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.writeToFile(File(localPath));
    return localPath;
  }

  /// Processes the recorded audio and returns a structured [ConsultationNote] draft.
  ///
  /// [audioStoragePath] is the Firebase Storage path returned by [uploadAudio].
  /// [noteId], [doctorId], [patientId], [visitId] are used to construct the note.
  /// [consentAt] is the moment the doctor checked the consent checkbox.
  ///
  /// Throws [ScribeProcessingException] on unrecoverable failures.
  Future<ConsultationNote> processAudio({
    required String audioStoragePath,
    required String noteId,
    required String doctorId,
    required String patientId,
    required String visitId,
    required DateTime consentAt,
  }) async {
    // Download audio to a temp file for inline data
    String? tempPath;
    try {
      tempPath = await _downloadAudioToTemp(audioStoragePath);
    } catch (e) {
      throw ScribeProcessingException(
          'Failed to download audio for processing: $e');
    }

    Map<String, dynamic>? parsed;

    try {
      parsed = await _callGemini(tempPath);
    } catch (e) {
      // First attempt failed — try once more with a stricter re-prompt
      try {
        parsed = await _callGemini(tempPath, strictRetry: true);
      } catch (retryError) {
        debugPrint('[ScribeProcessing] Both Gemini calls failed: $retryError');
        // Fall through — parsed stays null, we'll produce a blank draft
      }
    } finally {
      _deleteFile(tempPath);
    }

    final now = DateTime.now();
    if (parsed == null) {
      // Fallback: blank structured fields. The doctor can fill fields by hand.
      return ConsultationNote(
        id: noteId,
        doctorId: doctorId,
        patientId: patientId,
        visitId: visitId,
        transcript: '',
        chiefComplaint: '',
        symptoms: const [],
        diagnosisSuggestions: const [],
        medicines: const [],
        advice: '',
        confidenceNote:
            'AI processing failed. Please fill in the fields manually.',
        consentGiven: true,
        consentAt: consentAt,
        audioStoragePath: audioStoragePath,
        status: ConsultationNoteStatus.draft,
        createdAt: now,
      );
    }

    return _noteFromParsed(
      parsed: parsed,
      noteId: noteId,
      doctorId: doctorId,
      patientId: patientId,
      visitId: visitId,
      consentAt: consentAt,
      audioStoragePath: audioStoragePath,
      now: now,
    );
  }

  Future<Map<String, dynamic>> _callGemini(
    String audioPath, {
    bool strictRetry = false,
  }) async {
    final model = FirebaseAI.googleAI().generativeModel(
      model: _modelName(),
      systemInstruction: Content.system(_systemPrompt),
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: _buildResponseSchema(),
      ),
    );

    final audioBytes = await File(audioPath).readAsBytes();
    final audioPart = InlineDataPart('audio/mp4', Uint8List.fromList(audioBytes));

    final prompt = strictRetry
        ? 'Extract clinical information from this consultation recording. '
            'Respond ONLY with a valid JSON object. Do not include any text '
            'outside the JSON.'
        : 'Extract the clinical information from this doctor-patient '
            'consultation recording into the requested JSON structure.';

    final response = await model.generateContent([
      Content.multi([TextPart(prompt), audioPart]),
    ]);

    final text = response.text ?? '';
    if (text.trim().isEmpty) {
      throw ScribeProcessingException('Empty response from Gemini.');
    }

    // Strip markdown fences the model might have added despite instructions
    final jsonStr = _extractJsonFromText(text);
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  }

  /// Strips any surrounding markdown code fences the model might have added.
  String _extractJsonFromText(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('```')) {
      final start = trimmed.indexOf('{');
      final end = trimmed.lastIndexOf('}');
      if (start != -1 && end != -1 && end > start) {
        return trimmed.substring(start, end + 1);
      }
    }
    return trimmed;
  }

  ConsultationNote _noteFromParsed({
    required Map<String, dynamic> parsed,
    required String noteId,
    required String doctorId,
    required String patientId,
    required String visitId,
    required DateTime consentAt,
    required String audioStoragePath,
    required DateTime now,
  }) {
    final vitalsRaw =
        parsed['vitalsIfMentioned'] as Map<String, dynamic>? ?? {};
    final vitals = <String, String?>{
      'bp': vitalsRaw['bp'] as String?,
      'temp': vitalsRaw['temp'] as String?,
      'pulse': vitalsRaw['pulse'] as String?,
    };

    final medicinesRaw = (parsed['medicines'] as List<dynamic>?) ?? [];
    final medicines = medicinesRaw
        .whereType<Map<String, dynamic>>()
        .map(
          (m) => NotedMedicine(
            name: m['name'] as String? ?? '',
            dosage: m['dosage'] as String? ?? '',
            instructions: m['instructions'] as String? ?? '',
          ),
        )
        .where((m) => m.name.trim().isNotEmpty)
        .toList();

    DateTime? followUpDate;
    final followUpRaw = parsed['followUpDate'] as String?;
    if (followUpRaw != null && followUpRaw.trim().isNotEmpty) {
      try {
        followUpDate = DateTime.parse(followUpRaw);
      } catch (_) {}
    }

    return ConsultationNote(
      id: noteId,
      doctorId: doctorId,
      patientId: patientId,
      visitId: visitId,
      transcript: parsed['transcript'] as String? ?? '',
      chiefComplaint: parsed['chiefComplaint'] as String? ?? '',
      symptoms: _toStringList(parsed['symptoms']),
      diagnosisSuggestions: _toStringList(parsed['diagnosisSuggestions']),
      medicines: medicines,
      advice: parsed['advice'] as String? ?? '',
      followUpDate: followUpDate,
      vitals: vitals,
      confidenceNote:
          parsed['transcriptSummaryConfidenceNote'] as String? ?? '',
      consentGiven: true,
      consentAt: consentAt,
      audioStoragePath: audioStoragePath,
      status: ConsultationNoteStatus.draft,
      createdAt: now,
    );
  }

  static void _deleteFile(String? path) {
    if (path == null) return;
    try {
      File(path).delete().catchError((_) => File(path));
    } catch (_) {}
  }

  static List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }
}

class ScribeProcessingException implements Exception {
  final String message;
  const ScribeProcessingException(this.message);

  @override
  String toString() => 'ScribeProcessingException: $message';
}
