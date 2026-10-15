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
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
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
    'AI Scribe: physiotherapy conversation → session notes',
    () async {
      const transcript = '''
Doctor: Good morning, what brings you in today?
Patient: My right knee has been hurting for about three weeks, since I twisted it playing football.
Doctor: How bad is the pain right now, out of ten?
Patient: Around six. At its worst it gets to eight, especially on the stairs.
Doctor: Any locking? Any night pain, fever or weight loss?
Patient: No locking, no fever, nothing like that.
Doctor: Let me check. Right knee bends to about 95 degrees. McMurray is positive on the right. Quadriceps strength is four by five.
Doctor: This looks like a medial meniscus injury. Are you taking anything for the pain?
Patient: I take Combiflam sometimes, maybe once a day.
Doctor: Today we will do IFT for fifteen minutes. At home do static quads, three sets of ten, hold five seconds, twice a day. Avoid squatting. Come back after two days.
''';
      final watch = Stopwatch()..start();
      final note = await ScribeProcessingService(client: client())
          .writeSessionNote(
            session: ConsultationNote(
              id: 'live',
              doctorId: 'd',
              patientId: 'p',
              visitId: 'v',
              specialty: SessionSpecialty.physiotherapy,
              createdAt: DateTime(2026, 9, 25, 10),
            ),
            transcript: transcript,
          );
      // ignore: avoid_print
      print(
        '--- ${watch.elapsed.inSeconds}s with $model: ${note.chiefComplaint} ---\n'
        '${note.notes}\n'
        '--- Unsure: ${note.confidenceNote}',
      );

      final notes = note.notes.toLowerCase();
      expect(note.chiefComplaint.toLowerCase(), contains('knee'));
      expect(notes, contains('95'));
      expect(notes, contains('mcmurray'));
      expect(notes, contains('menisc'));
      expect(notes, contains('combiflam'));
      expect(notes, contains('ift'));
      expect(notes, contains('quad'));
      expect(notes, contains('27 sep'));
      expect(notes, isNot(contains('**')));
      expect(notes, isNot(contains('mri')), reason: 'nothing unsaid is added');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
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
