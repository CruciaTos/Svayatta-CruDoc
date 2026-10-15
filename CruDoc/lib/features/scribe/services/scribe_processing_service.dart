import 'dart:async';
import 'dart:io';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/core/services/gemini_json_client.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/services/scribe_transcript_formatter.dart';

/// Writes a session note from the conversation between the doctor and the
/// patient.
///
/// The conversation is transcribed on the device while it happens; only
/// that transcript text goes to Gemini (through [GeminiJsonClient]), never
/// the recording. The model writes the notes as the clinician would, from
/// what was actually said, and gives the session a one-line title.
///
/// Model name comes from Remote Config (key: `scribe_gemini_model`), see
/// [GeminiJsonClient.modelName].
class ScribeProcessingService {
  ScribeProcessingService({GeminiJsonClient? client})
    : _client = client ?? GeminiJsonClient();

  final GeminiJsonClient _client;

  /// Recordings shorter than this are rejected before any API call.
  static const minRecordingDuration = Duration(seconds: 5);

  /// Recording auto-stops here.
  static const maxRecordingDuration = Duration(minutes: 45);

  /// Fewer words than this isn't a conversation to write notes from.
  static const minTranscriptWords = 8;

  static const _requestTimeout = Duration(seconds: 90);

  @visibleForTesting
  static final Schema responseSchema = Schema.object(
    properties: {
      'notes': Schema.string(
        description:
            'The session notes: short headings, each on its own line and '
            'followed by its content, sections separated by a blank line.',
      ),
      'title': Schema.string(
        description:
            'What the session was about, in under 8 words, e.g. "Lower '
            'back pain radiating to right leg".',
      ),
      'confidenceNote': Schema.string(
        nullable: true,
        description:
            'Words, names, numbers or doses in the transcript that were '
            'unclear. Empty if nothing was.',
      ),
    },
    propertyOrdering: const ['notes', 'title', 'confidenceNote'],
  );

  @visibleForTesting
  static const systemPrompt = '''
You are a clinical scribe for a clinician in India. You are given the
transcript of a normal conversation between the clinician and a patient
during a visit, and you write the clinician's session notes for that visit.

The transcript was made on the device as people spoke. It may contain
recognition errors, repeated words and speaker labels ("Doctor:",
"Patient:") that were guessed and can be wrong — judge who is speaking from
what is said.

RULES:
1. Only write what was actually said in this conversation. Never add a
   symptom, finding, diagnosis, test, medicine, dose or advice that was not
   said. A question the clinician asked is not a finding — record the
   patient's answer.
2. Write as a clinician would: concise clinical English, standard medical
   terms, third person ("Patient reports…", "Advised…"). Hindi, Marathi,
   Gujarati or other Indian languages in the conversation are written in
   English in the notes; keep a patient's own striking words in quotes.
3. notes: plain text, no markdown (no #, no **). Put each heading on its own
   line, its content on the lines after it, and a blank line between
   sections. Use "- " for list items. Use only headings the conversation
   has content for, in this order:
     Presenting complaint, History, Examination, Assessment, Treatment
     given, Medicines, Advice, Follow-up
   Small talk and logistics (payment, directions) are left out.
4. Keep numbers exactly as spoken: vitals, pain scores ("6/10"), durations,
   measurements, doses. Record the side (left / right) when it is stated.
5. Medicines: name, strength, dose, frequency and duration, only as said.
   If a medicine name is unclear in the transcript, write it as heard and
   flag it in confidenceNote — never substitute a different medicine.
6. Follow-up: if a next visit was given, say when. Resolve relative phrases
   ("after 5 days", "next Monday") against the session date in the request
   and write the date as e.g. "20 Oct 2026".
7. title: what the session was about in under 8 words.
8. confidenceNote: anything you were unsure of in the transcript — unclear
   words, a medicine, dose or number that looks misheard. Empty if clear.
9. If the transcript holds no consultation (silence, noise, unrelated
   talk), return empty notes and title and say so in confidenceNote.
10. Respond ONLY with a JSON object matching the requested schema.
''';

  /// Writes the notes for [session] — a note carrying the visit, patient
  /// and consent details — from the conversation's [transcript], and
  /// returns the note with its title, notes and transcript filled in.
  /// Nothing is saved here.
  ///
  /// Throws [ScribeProcessingException] when no notes could be written.
  Future<ConsultationNote> writeSessionNote({
    required ConsultationNote session,
    required String transcript,
  }) async {
    final text = cleanTranscript(transcript);
    if (wordCount(text) < minTranscriptWords) {
      throw const ScribeProcessingException(
        'Not enough of the conversation was heard to write session notes. '
        'Check that the microphone is picking up both of you and record '
        'again.',
        kind: ScribeFailureKind.noConversation,
      );
    }

    Map<String, dynamic> parsed;
    try {
      parsed = await _call(text, session);
    } on FormatException catch (e) {
      // Malformed or truncated JSON — retry once with a stricter prompt.
      debugPrint('[ScribeProcessing] Malformed response, retrying: $e');
      try {
        parsed = await _call(text, session, strict: true);
      } catch (retryError) {
        throw _classify(retryError);
      }
    } catch (e) {
      throw _classify(e);
    }

    final note = noteFromParsed(parsed, session: session, transcript: text);
    if (note.notes.isEmpty) {
      throw ScribeProcessingException(
        note.confidenceNote.isEmpty
            ? 'No consultation was found in what was heard, so no notes '
                  'were written.'
            : 'No notes were written: ${note.confidenceNote}',
        kind: ScribeFailureKind.noConversation,
      );
    }
    return note;
  }

  Future<Map<String, dynamic>> _call(
    String transcript,
    ConsultationNote session, {
    bool strict = false,
  }) {
    final date = session.createdAt.toIso8601String().split('T').first;
    final clinician = switch (session.specialty) {
      SessionSpecialty.physiotherapy => 'a physiotherapist',
      SessionSpecialty.homeopathy => 'a homeopathic doctor',
      _ => 'a doctor',
    };
    final prompt = [
      'Session date: $date. The clinician is $clinician.',
      strict
          ? 'Write the session notes for this conversation. Respond ONLY '
                'with a valid JSON object — no text outside it.'
          : 'Write the session notes for this conversation.',
      '',
      'TRANSCRIPT:',
      transcript,
    ].join('\n');

    return _client.generateJson(
      systemPrompt: systemPrompt,
      prompt: prompt,
      schema: responseSchema,
      maxOutputTokens: 16384,
      timeout: _requestTimeout,
    );
  }

  /// The live transcript tidied up: Whisper repetitions removed and turns
  /// split into "Doctor:" / "Patient:" lines where they can be told apart.
  static String cleanTranscript(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '';
    final formatted = ScribeTranscriptFormatter.format(text).trim();
    return formatted.isEmpty ? text : formatted;
  }

  static int wordCount(String text) =>
      text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  ScribeProcessingException _classify(Object error) {
    debugPrint('[ScribeProcessing] Processing failed: $error');
    if (error is ScribeProcessingException) return error;
    if (error is TimeoutException) {
      return ScribeProcessingException(
        'The AI took too long to respond. The conversation is kept — try '
        'again.',
        kind: ScribeFailureKind.timeout,
        cause: error,
      );
    }
    if (error is SocketException || error is HttpException) {
      return ScribeProcessingException(
        "You appear to be offline. The conversation is kept — try again once "
        "you're back online.",
        kind: ScribeFailureKind.offline,
        cause: error,
      );
    }
    if (error is QuotaExceeded ||
        (error is GeminiHttpException && error.isQuota)) {
      return ScribeProcessingException(
        'The AI usage limit has been reached. Try again in a few minutes, '
        'or save the transcript instead.',
        kind: ScribeFailureKind.quota,
        cause: error,
      );
    }
    if (error is GeminiHttpException) {
      if (error.isServiceDisabled) {
        return ScribeProcessingException(
          'Gemini API is not enabled in your Google Cloud project (474729174031). '
          'Please enable the Generative Language API in Google Cloud Console, then retry.',
          kind: ScribeFailureKind.notConfigured,
          cause: error,
        );
      }
      if (error.isKeyBlocked) {
        return ScribeProcessingException(
          'Gemini API key is restricted from calling Generative Language API. '
          'Please adjust API restrictions in Google Cloud Console or use an AI Studio key.',
          kind: ScribeFailureKind.notConfigured,
          cause: error,
        );
      }
    }
    final raw = error.toString().toLowerCase();
    final modelMissing =
        raw.contains('not found') ||
        raw.contains('404') ||
        raw.contains('is not supported');
    if (error is ServiceApiNotEnabled ||
        error is InvalidApiKey ||
        (error is GeminiHttpException && error.isNotConfigured) ||
        modelMissing) {
      return ScribeProcessingException(
        "AI Scribe isn't available for this clinic yet (Firebase AI Logic or "
        "the configured model is not set up). You can save the transcript "
        "instead.",
        kind: ScribeFailureKind.notConfigured,
        cause: error,
      );
    }
    if (error is FormatException) {
      return ScribeProcessingException(
        "The AI couldn't write readable notes from this conversation. Try "
        "again, or save the transcript instead.",
        kind: ScribeFailureKind.badResponse,
        cause: error,
      );
    }
    if (raw.contains('socket') ||
        raw.contains('network') ||
        raw.contains('failed host lookup') ||
        raw.contains('failed to resolve')) {
      return ScribeProcessingException(
        "You appear to be offline. The conversation is kept — try again once "
        "you're back online.",
        kind: ScribeFailureKind.offline,
        cause: error,
      );
    }
    return ScribeProcessingException(
      'Something went wrong while writing the session notes. Try again, or '
      'save the transcript instead.',
      kind: ScribeFailureKind.unknown,
      cause: error,
    );
  }

  /// Fills [session] in from the model's JSON. Tolerates missing keys and
  /// wrong types — anything unusable becomes an empty field.
  @visibleForTesting
  static ConsultationNote noteFromParsed(
    Map<String, dynamic> parsed, {
    required ConsultationNote session,
    required String transcript,
  }) {
    return session.copyWith(
      transcript: transcript,
      notes: cleanNotes(_cleanString(parsed['notes'])),
      chiefComplaint: _cleanString(parsed['title']),
      confidenceNote: _cleanString(parsed['confidenceNote']),
    );
  }

  /// Strips markdown the model may add despite instructions and collapses
  /// runs of blank lines, so the notes read as plain text.
  @visibleForTesting
  static String cleanNotes(String notes) {
    final lines = notes
        .replaceAll('\r\n', '\n')
        .replaceAll('**', '')
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'^\s*#+\s*'), '').trimRight());
    return lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  static String _cleanString(Object? value) {
    if (value is! String) return '';
    final trimmed = value.trim();
    return trimmed.toLowerCase() == 'null' ? '' : trimmed;
  }
}

/// Why processing failed — lets the UI pick the right recovery options.
enum ScribeFailureKind {
  offline,
  timeout,
  notConfigured,
  quota,
  badResponse,

  /// Too little was heard, or what was heard wasn't a consultation.
  noConversation,
  unknown;

  /// Whether retrying the same conversation could plausibly succeed.
  bool get isRetryable =>
      this != ScribeFailureKind.notConfigured &&
      this != ScribeFailureKind.noConversation;
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
