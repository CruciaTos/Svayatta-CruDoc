import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/services/gemini_json_client.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_session_note.dart';

/// Turns a recorded homeopathy follow-up visit into one dated
/// [HomeopathySessionNote]: the audio goes to Gemini, which transcribes it
/// and fills the session fields in a single call.
///
/// Separate from [HomeopathyVoiceScribeService], which fills the one
/// growing case sheet. Every call here produces a fresh note for one visit;
/// nothing is merged into an earlier note, so the saved notes form the
/// patient's session history.
class HomeopathySessionScribeService {
  HomeopathySessionScribeService({GeminiJsonClient? client})
    : _client = client ?? GeminiJsonClient();

  final GeminiJsonClient _client;

  static const _requestTimeout = Duration(seconds: 120);

  @visibleForTesting
  static final Schema responseSchema = _buildSchema();

  static Schema _buildSchema() {
    Schema text(String description) =>
        Schema.string(nullable: true, description: description);

    final properties = <String, Schema>{
      'transcript': Schema.string(),
      'problemToday': text(
        'The problem addressed at this visit, in one or two lines, e.g. '
        '"Follow-up for right-sided migraine" or "New acidity since last '
        'week".',
      ),
      'symptomStatus': Schema.enumString(
        enumValues: [for (final s in HomeopathySymptomStatus.values) s.name],
        description: "The patient's overall change since the last visit.",
      ),
      'symptomDetails': text(
        'What specifically changed since the last visit and by how much.',
      ),
      'oldSymptomsReturned': text(
        'Old or past symptoms the patient says have come back. Not a flare '
        'of the current complaint.',
      ),
      'newSymptoms': text('Symptoms that are new since the last visit.'),
      'modalitiesToday': text(
        'What makes the complaint better or worse, as reported today.',
      ),
      'mentalStateToday': text('Mood, disposition and emotional state today.'),
      'generalsToday': text(
        'Appetite, thirst, sleep, energy, stool, urine, sweat, as reported '
        'today.',
      ),
      'complianceNotes': text(
        'Whether the previous remedy was taken as advised: missed doses, '
        'self-repetition, antidoting (coffee, camphor, mint).',
      ),
      'intercurrentIllness': text(
        'A new, unrelated illness or injury since the last visit.',
      ),
      'responseToRemedy': Schema.enumString(
        enumValues: [for (final r in HomeopathyRemedyResponse.values) r.name],
        description: 'How the case responded to the previous remedy.',
      ),
      'heringsLawObservation': text(
        "The doctor's own stated read on direction of cure.",
      ),
      'clinicalImpression': text(
        "The doctor's overall assessment of this visit.",
      ),
      'remedyGiven': text('Remedy prescribed at this visit.'),
      'potency': text('Potency of that remedy, e.g. "30C", "200C", "LM1".'),
      'repetition': text(
        'How often to take it, e.g. "single dose", "3 pills twice daily for '
        '5 days".',
      ),
      'adviceGiven': text('Diet, lifestyle and other advice given today.'),
      'nextFollowUpDate': text(
        'ISO date (YYYY-MM-DD) of the next visit, only if one was given.',
      ),
      'confidenceNote': text(
        'Audio problems, unclear words or numbers. Empty if the audio was '
        'clear.',
      ),
    };

    return Schema.object(
      properties: properties,
      // Transcript first so every extracted field is grounded in it.
      propertyOrdering: properties.keys.toList(),
    );
  }

  @visibleForTesting
  static const systemPrompt = '''
You are a clinical documentation assistant for homeopathic doctors in India.
You transcribe a recorded FOLLOW-UP visit and extract a session note for
that one visit. First-time case-taking is handled elsewhere; this note is
one dated entry in the patient's session history, so it must describe only
what happened at THIS visit, never a summary of the whole case.

CRITICAL RULES:
1. Only extract what was ACTUALLY SAID in this recording. Do not infer,
   guess or carry anything forward from earlier visits unless it was
   repeated or referred to today.
2. Leave a field empty (null) when it was not discussed. Most visits leave
   several fields empty; that is expected. Never invent content to fill one.
3. problemToday should almost always be filled: the problem addressed at
   this visit. If the visit was only a remedy review, summarise what was
   reviewed.
4. symptomStatus: "better", "worse", "same", "mixed" (some symptoms better,
   others not), "newProblem" (the visit is about a new complaint), or
   "unspecified" if the patient did not say. Put the specifics in
   symptomDetails, e.g. "Headaches down from daily to twice a week,
   intensity unchanged".
5. oldSymptomsReturned: only symptoms described as OLD or PAST ones coming
   back (an old eruption, an old joint pain). This matters in homeopathy as
   a sign of cure by Hering's Law. A flare of the current complaint belongs
   in symptomDetails instead.
6. responseToRemedy: "ameliorated"; "aggravatedThenBetter" (an initial
   aggravation followed by improvement); "aggravatedNoRelief"; "noAction";
   "tooEarly"; or "notApplicable" when no previous remedy was under review.
   Base this on what the doctor or patient said, not on your own judgement.
7. heringsLawObservation: only the doctor's own spoken read on direction of
   cure (from within outward, from more to less vital organs, from above
   downward, or in reverse order of onset). Empty if not mentioned.
8. remedyGiven, potency and repetition describe what was prescribed AT THIS
   VISIT. If the doctor said to continue the same remedy, record it here so
   the note stands on its own. If the plan was to wait without a new
   prescription (placebo / Sac lac / observe), leave remedyGiven empty and
   say so in clinicalImpression. Write remedy names in their standard
   abbreviated or full Latin form as spoken (e.g. "Nux vomica", "Puls",
   "Calc carb"); do not substitute a different remedy.
9. Keep potencies exactly as spoken: "thirty" → "30C", "two hundred" →
   "200C", "1M", "LM1"/"0/1". Do not convert between scales.
10. nextFollowUpDate: an ISO date only if a specific next visit was given.
    Resolve relative phrases ("after 15 days", "next month") against the
    session date in the request.
11. transcript: a faithful transcript. Prefix turns with "Doctor:" or
    "Patient:" when it is clear who is speaking. Hindi, Marathi, Gujarati or
    other Indian languages mixed with English go in Roman script. Every
    other field is concise clinical English using standard homeopathic
    terms, but keep the patient's own striking words in quotes when they
    describe a peculiar sensation (e.g. "as if a nail is driven in").
12. confidenceNote: flag audio problems, overlapping speech, or a remedy
    name or potency you could not hear clearly. A misheard remedy is
    dangerous, so say so rather than guess.
13. If the recording has no consultation in it (silence, noise, unrelated
    talk), return an empty transcript and empty fields and explain in
    confidenceNote.
14. Respond ONLY with a JSON object matching the requested schema.
''';

  /// Transcribes [audioBytes] and returns a new, unsaved session note for
  /// [sessionDate]. Throws on failure ([FormatException] for an unreadable
  /// reply, plus the network, timeout and Gemini errors that
  /// [GeminiJsonClient] passes through) — a note is never invented.
  Future<HomeopathySessionNote> processAudio({
    required Uint8List audioBytes,
    String mimeType = 'audio/mp4',
    required String patientId,
    required String doctorId,
    String visitId = '',
    required DateTime sessionDate,
  }) async {
    Map<String, dynamic> parsed;
    try {
      parsed = await _call(audioBytes, mimeType, sessionDate);
    } on FormatException catch (e) {
      debugPrint('[HomeopathySessionScribe] Malformed response, retrying: $e');
      parsed = await _call(audioBytes, mimeType, sessionDate, strict: true);
    }

    return noteFromParsed(
      parsed,
      id: const Uuid().v4(),
      patientId: patientId,
      doctorId: doctorId,
      visitId: visitId,
      sessionDate: sessionDate,
      now: DateTime.now(),
    );
  }

  Future<Map<String, dynamic>> _call(
    Uint8List audioBytes,
    String mimeType,
    DateTime sessionDate, {
    bool strict = false,
  }) {
    final date = sessionDate.toIso8601String().split('T').first;
    final prompt = strict
        ? 'Session date: $date. Extract this homeopathy follow-up visit. '
              'Keep the transcript under 800 words. Respond ONLY with a '
              'valid JSON object.'
        : 'Session date: $date. Transcribe this homeopathy follow-up visit '
              'and extract the session note.';
    return _client.generateJson(
      systemPrompt: systemPrompt,
      prompt: prompt,
      audioBytes: audioBytes,
      mimeType: mimeType,
      schema: responseSchema,
      maxOutputTokens: 16384,
      timeout: _requestTimeout,
    );
  }

  /// Maps the model's JSON onto a new note. Missing keys and wrong types
  /// become empty fields; never throws.
  @visibleForTesting
  static HomeopathySessionNote noteFromParsed(
    Map<String, dynamic> parsed, {
    required String id,
    required String patientId,
    required String doctorId,
    String visitId = '',
    required DateTime sessionDate,
    required DateTime now,
  }) {
    String s(String key) {
      final v = parsed[key];
      if (v is! String) return '';
      final t = v.trim();
      return t.toLowerCase() == 'null' ? '' : t;
    }

    final followUp = s('nextFollowUpDate');

    return HomeopathySessionNote(
      id: id,
      patientId: patientId,
      doctorId: doctorId,
      visitId: visitId,
      sessionDate: sessionDate,
      problemToday: s('problemToday'),
      symptomStatus: HomeopathySymptomStatus.fromString(s('symptomStatus')),
      symptomDetails: s('symptomDetails'),
      oldSymptomsReturned: s('oldSymptomsReturned'),
      newSymptoms: s('newSymptoms'),
      modalitiesToday: s('modalitiesToday'),
      mentalStateToday: s('mentalStateToday'),
      generalsToday: s('generalsToday'),
      complianceNotes: s('complianceNotes'),
      intercurrentIllness: s('intercurrentIllness'),
      responseToRemedy: HomeopathyRemedyResponse.fromString(
        s('responseToRemedy'),
      ),
      heringsLawObservation: s('heringsLawObservation'),
      clinicalImpression: s('clinicalImpression'),
      remedyGiven: s('remedyGiven'),
      potency: s('potency'),
      repetition: s('repetition'),
      adviceGiven: s('adviceGiven'),
      nextFollowUpDate: followUp.isEmpty ? null : DateTime.tryParse(followUp),
      transcript: s('transcript'),
      confidenceNote: s('confidenceNote'),
      createdAt: now,
    );
  }
}
