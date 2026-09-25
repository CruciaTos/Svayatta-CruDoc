// Live checks against the real Gemini API, using the same prompts and
// schemas the app sends. Skipped unless a key is available.
//
// 1. Put the key in CruDoc/.env.local (git-ignored):
//      GEMINI_API_KEY=your-key
//      GEMINI_MODEL=gemini-3.5-flash   (optional)
// 2. Generate the recordings (Windows):
//      powershell -ExecutionPolicy Bypass -File tool/make_voice_fixtures.ps1
// 3. flutter test test/live/gemini_live_test.dart
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:doctor_management_app/core/services/gemini_json_client.dart';
import 'package:doctor_management_app/features/patients/services/patient_voice_fill_service.dart';
import 'package:doctor_management_app/features/scribe/data/models/physio_findings.dart';
import 'package:doctor_management_app/features/scribe/data/repo/consultation_note_repository.dart';
import 'package:doctor_management_app/features/scribe/services/scribe_processing_service.dart';

Map<String, String> _env() {
  final values = <String, String>{};
  final file = File('.env.local');
  if (file.existsSync()) {
    for (final line in file.readAsLinesSync()) {
      final i = line.indexOf('=');
      if (line.trim().startsWith('#') || i <= 0) continue;
      values[line.substring(0, i).trim()] = line.substring(i + 1).trim();
    }
  }
  for (final key in ['GEMINI_API_KEY', 'GEMINI_MODEL']) {
    final v = Platform.environment[key];
    if (v != null && v.isNotEmpty) values[key] = v;
  }
  return values;
}

void main() {
  final env = _env();
  final apiKey = env['GEMINI_API_KEY'] ?? '';
  final model = env['GEMINI_MODEL']?.isNotEmpty == true
      ? env['GEMINI_MODEL']!
      : GeminiJsonClient.fallbackModel;
  final skip = apiKey.isEmpty ? 'No GEMINI_API_KEY in .env.local' : false;
  final fixtures = Directory('build/voice_fixtures');

  GeminiJsonClient client() => GeminiJsonClient(apiKey: apiKey, model: model);

  test('the configured model is available to this key', () async {
    final res = await http.get(
      Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models'
        '?pageSize=200',
      ),
      headers: {'x-goog-api-key': apiKey},
    );
    expect(res.statusCode, 200, reason: res.body);
    final names = ((jsonDecode(res.body) as Map)['models'] as List)
        .map((m) => (m['name'] as String).replaceFirst('models/', ''))
        .toList();
    // ignore: avoid_print
    print(
      'Flash models for this key: '
      '${names.where((n) => n.contains('flash')).join(', ')}',
    );
    expect(names, contains(model));
  }, skip: skip);

  test(
    'AI Scribe: physiotherapy session → SOAP note',
    () async {
      final audio = File('${fixtures.path}/physio_session.wav');
      final watch = Stopwatch()..start();
      final parsed = await client().generateJson(
        systemPrompt: ScribeProcessingService.systemPrompt,
        prompt:
            'Consultation date: 2026-09-25. Transcribe this physiotherapy '
            'session and extract the clinical information into the requested '
            'SOAP JSON structure.',
        audioBytes: await audio.readAsBytes(),
        mimeType: 'audio/wav',
        schema: ScribeProcessingService.responseSchema,
        maxOutputTokens: 32768,
        timeout: const Duration(seconds: 150),
      );
      final note = ScribeProcessingService.noteFromParsed(
        parsed: parsed,
        noteId: 'live',
        doctorId: 'd',
        patientId: 'p',
        visitId: 'v',
        consentAt: DateTime(2026, 9, 25, 10),
        now: DateTime(2026, 9, 25, 10, 30),
      );
      // ignore: avoid_print
      print(
        '--- ${watch.elapsed.inSeconds}s with $model ---\n'
        '${ConsultationNoteRepository.buildVisitSummary(note)}\n'
        '--- AI note: ${note.confidenceNote}',
      );

      final p = note.physio;
      String rows(String key) => p
          .tableOf(key)
          .map((r) => r.values.join(' '))
          .join(' | ')
          .toLowerCase();

      expect(note.chiefComplaint.toLowerCase(), contains('knee'));
      expect(p.textOf('painNow'), contains('6'));
      expect(p.textOf('painWorst'), contains('8'));
      expect(rows('rom'), contains('95'));
      expect(rows('specialTests'), contains('mcmurray'));
      expect(rows('strength'), contains('4'));
      expect(rows('treatment'), contains('ift'));
      expect(rows('homeExercises'), contains('quad'));
      expect(
        note.diagnosisSuggestions.join(' ').toLowerCase(),
        contains('menisc'),
      );
      expect(
        note.medicines.map((m) => m.name.toLowerCase()).join(' '),
        contains('combiflam'),
      );
      expect(
        p.listOf('redFlags'),
        isEmpty,
        reason: 'all red flags were denied',
      );
      expect(p.listOf('redFlagsCleared'), isNotEmpty);
      expect(note.followUpDate, DateTime(2026, 9, 27));
      expect(p.isEmpty, isFalse);
      expect(PhysioFindings.fromStored(p.toStored()).toJson(), p.toJson());
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'Voice fill: front-desk dictation → Add Patient form',
    () async {
      final audio = File('${fixtures.path}/patient_intake.wav');
      final service = PatientVoiceFillService(client: client());
      final watch = Stopwatch()..start();
      final fill = await service.extract(
        await audio.readAsBytes(),
        today: DateTime(2026, 9, 25),
        mimeType: 'audio/wav',
      );
      // ignore: avoid_print
      print(
        '--- ${watch.elapsed.inSeconds}s: ${fill.firstName} ${fill.lastName}, '
        '${fill.gender}, age ${fill.ageYears}, ${fill.phone}, ${fill.email}, '
        '${fill.conditions}, notes "${fill.notes}", ₹${fill.packageBalance}',
      );

      expect(fill.firstName, 'Priya');
      expect(fill.lastName, 'Deshmukh');
      expect(fill.gender, 'Female');
      expect(fill.ageYears, 34);
      expect(fill.phone, '9822345678');
      expect(fill.email, 'priya.deshmukh@gmail.com');
      expect(fill.conditions.join(' ').toLowerCase(), contains('shoulder'));
      expect(fill.notes.toLowerCase(), contains('metformin'));
      expect(fill.packageBalance, 3000);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
