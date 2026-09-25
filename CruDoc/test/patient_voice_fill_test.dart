import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:doctor_management_app/core/services/gemini_json_client.dart';
import 'package:doctor_management_app/features/patients/presentation/desktop_add_edit_patient_dialog.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_form.dart';
import 'package:doctor_management_app/features/patients/services/patient_voice_fill_service.dart';

final _today = DateTime(2026, 9, 25);

/// Stands in for the microphone + Gemini: "records" instantly and returns
/// a fixed fill.
class _FakeVoiceFillService extends PatientVoiceFillService {
  _FakeVoiceFillService(this.result);

  final PatientVoiceFill result;

  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> start() async {}
  @override
  Future<double> amplitude() async => -30;
  @override
  Future<PatientVoiceFill> stopAndExtract({DateTime? today}) async => result;
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
}

Future<void> _speak(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.mic_rounded).first);
  await tester.pump();
  expect(find.textContaining('Listening'), findsOneWidget);
  await tester.tap(find.text('Done'));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('PatientVoiceFill.fromJson', () {
    test('keeps valid values and normalises them', () {
      final fill = PatientVoiceFill.fromJson({
        'firstName': 'rahul',
        'lastName': 'sharma',
        'phone': '98765 43210',
        'email': 'Rahul.Sharma@Gmail.com',
        'gender': 'Male',
        'ageYears': 42,
        'conditions': ['Low back pain', 'low back pain', 'Sciatica (right)'],
        'notes': 'Software engineer, sits 10 hours a day',
        'packageBalance': 5000,
      }, _today);

      expect(fill.firstName, 'Rahul');
      expect(fill.lastName, 'Sharma');
      expect(fill.phone, '9876543210');
      expect(fill.email, 'rahul.sharma@gmail.com');
      expect(fill.gender, 'Male');
      expect(fill.dateOfBirthOr(_today), DateTime(1984, 9, 25));
      expect(fill.conditions, ['Low back pain', 'Sciatica (right)']);
      expect(fill.packageBalance, 5000);
      expect(fill.filledLabels, contains('age'));
    });

    test('drops implausible or unheard values instead of guessing', () {
      final fill = PatientVoiceFill.fromJson({
        'firstName': 'null',
        'phone': '123',
        'email': 'rahul at gmail',
        'gender': 'unknown',
        'dateOfBirth': '2030-01-01',
        'ageYears': 300,
        'conditions': 'not a list',
        'packageBalance': -10,
      }, _today);

      expect(fill.isEmpty, isTrue);
      expect(fill.dateOfBirthOr(_today), isNull);
    });

    test('a spoken birth date wins over an age', () {
      final fill = PatientVoiceFill.fromJson({
        'dateOfBirth': '1990-03-14',
        'ageYears': 36,
      }, _today);
      expect(fill.dateOfBirthOr(_today), DateTime(1990, 3, 14));
      expect(fill.filledLabels, ['date of birth']);
    });
  });

  group('GeminiJsonClient REST transport', () {
    test('sends audio + schema and joins non-thought text parts', () async {
      late Map<String, dynamic> sent;
      late http.Request request;
      final client = GeminiJsonClient(
        apiKey: 'test-key',
        model: 'test-model',
        httpClient: MockClient((req) async {
          request = req;
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'thinking…', 'thought': true},
                      {'text': '{"firstName": '},
                      {'text': '"Asha"}'},
                    ],
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final json = await client.generateJson(
        systemPrompt: 'sys',
        prompt: 'go',
        audioBytes: utf8.encode('fake audio'),
        schema: PatientVoiceFillService.responseSchema,
      );

      expect(json, {'firstName': 'Asha'});
      expect(request.url.path, endsWith('/models/test-model:generateContent'));
      expect(request.headers['x-goog-api-key'], 'test-key');
      expect(request.url.queryParameters, isEmpty); // key not in the URL
      final parts = sent['contents'][0]['parts'] as List;
      expect(parts[1]['inlineData']['mimeType'], 'audio/mp4');
      expect(sent['generationConfig']['responseSchema']['type'], 'OBJECT');
      expect(sent['systemInstruction']['parts'][0]['text'], 'sys');
    });

    test('maps HTTP errors for the UI', () async {
      Future<Object> errorFor(int status, [String body = '{}']) async {
        final client = GeminiJsonClient(
          apiKey: 'k',
          model: 'm',
          httpClient: MockClient((_) async => http.Response(body, status)),
        );
        try {
          await client.generateJson(
            systemPrompt: '',
            prompt: '',
            audioBytes: utf8.encode('x'),
            schema: PatientVoiceFillService.responseSchema,
          );
        } catch (e) {
          return e;
        }
        fail('expected an error');
      }

      expect(((await errorFor(429)) as GeminiHttpException).isQuota, isTrue);
      expect(
        ((await errorFor(400, '{"reason":"API_KEY_INVALID"}'))
                as GeminiHttpException)
            .isNotConfigured,
        isTrue,
      );
      expect(
        ((await errorFor(404)) as GeminiHttpException).isNotConfigured,
        isTrue,
      );
      expect(
        ((await errorFor(500)) as GeminiHttpException).isNotConfigured,
        isFalse,
      );
    });
  });

  group('Voice fill in the Add Patient forms', () {
    const fill = PatientVoiceFill(
      firstName: 'Rahul',
      lastName: 'Sharma',
      phone: '9876543210',
      gender: 'Female',
      ageYears: 42,
      conditions: ['Low back pain'],
      notes: 'Desk job',
      packageBalance: 5000,
    );

    testWidgets('mobile form fills only the heard fields', (tester) async {
      final formKey = GlobalKey<FormState>();
      final stateKey = GlobalKey<PatientFormState>();
      PatientFormResult? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PatientForm(
                key: stateKey,
                formKey: formKey,
                onSubmit: (r) => saved = r,
                initialEmail: 'kept@example.com',
                enableVoiceFill: true,
                voiceFillService: _FakeVoiceFillService(fill),
              ),
            ),
          ),
        ),
      );

      await _speak(tester);
      expect(find.text('Form filled'), findsOneWidget);
      expect(stateKey.currentState!.submit(), isTrue);

      expect(saved!.firstName, 'Rahul');
      expect(saved!.phone, '9876543210');
      expect(saved!.email, 'kept@example.com'); // not heard, not touched
      expect(saved!.gender, 'Female');
      expect(DateTime.now().year - saved!.dateOfBirth.year, 42);
      expect(saved!.diagnosis, ['Low back pain']);
      expect(saved!.packageBalance, 5000);
    });

    testWidgets('mobile form hides the mic unless enabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PatientForm(
                formKey: GlobalKey<FormState>(),
                onSubmit: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Fill by voice'), findsNothing);
    });

    testWidgets('desktop dialog fills the new-patient form', (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopAddEditPatientDialog(
              voiceFillService: _FakeVoiceFillService(fill),
            ),
          ),
        ),
      );
      expect(find.text('Fill by voice'), findsOneWidget);

      await _speak(tester);
      expect(find.text('Form filled'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Rahul'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Sharma'), findsOneWidget);
      expect(find.widgetWithText(TextField, '9876543210'), findsOneWidget);
      expect(find.widgetWithText(TextField, '42'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Desk job'), findsOneWidget);
      expect(find.text('Low back pain'), findsWidgets);
    });
  });
}
