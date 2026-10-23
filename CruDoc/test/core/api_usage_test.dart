import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/core/services/api_usage_service.dart';
import 'package:doctor_management_app/core/services/demo_session_service.dart';

void main() {
  late List<(String, String, Map<String, Object?>)> writes;

  setUp(() {
    writes = [];
    ApiUsage.writeOverride = (uid, day, data) async =>
        writes.add((uid, day, data));
    ApiUsage.currentUid = () => 'doc-1';
  });

  tearDown(() {
    ApiUsage.writeOverride = null;
    DemoSessionService.endDemoSession();
  });

  test('a Gemini call adds calls, tokens and its feature', () {
    ApiUsage.record(
      ApiService.gemini,
      feature: 'Voice form',
      inputTokens: 800,
      outputTokens: 120,
    );
    final (uid, day, data) = writes.single;
    expect(uid, 'doc-1');
    expect(day, ApiUsage.dayKey(DateTime.now()));
    expect(data['date'], day);
    expect(data['clinicId'], 'doc-1');
    expect(data['gemini'], {
      'calls': 1,
      'inputTokens': 800,
      'outputTokens': 120,
      'features': {'voice_form': 1},
    });
  });

  test('errors and seconds are counted; nothing is recorded in a demo', () {
    ApiUsage.record(ApiService.sarvam, feature: 'scribe', seconds: 4.257);
    ApiUsage.record(ApiService.places, feature: 'autocomplete', error: true);
    expect(writes[0].$3['sarvam'], {
      'calls': 1,
      'seconds': 4.26,
      'features': {'scribe': 1},
    });
    expect((writes[1].$3['places'] as Map)['errors'], 1);

    DemoSessionService.startDemoSession();
    ApiUsage.record(ApiService.gemini, feature: 'scribe');
    expect(writes, hasLength(2));
  });

  test('signed out records nothing', () {
    ApiUsage.currentUid = () => null;
    ApiUsage.record(ApiService.gemini, feature: 'scribe');
    expect(writes, isEmpty);
  });

  test('a map image counts once per run, however often it is drawn', () {
    for (var i = 0; i < 5; i++) {
      ApiUsage.recordOnce(
        ApiService.maps,
        'https://maps.test/a.png',
        feature: 'visit_map',
      );
    }
    ApiUsage.recordOnce(
      ApiService.maps,
      'https://maps.test/b.png',
      feature: 'visit_map',
    );
    expect(writes, hasLength(2));
  });

  test('a raw Gemini reply records its tokens, or an error', () {
    ApiUsage.recordGeminiRest(
      200,
      '{"usageMetadata":{"promptTokenCount":50,"candidatesTokenCount":10,'
      '"thoughtsTokenCount":5}}',
      feature: 'radiology_ai',
    );
    ApiUsage.recordGeminiRest(404, 'not found', feature: 'radiology_ai');
    expect(writes[0].$3['gemini'], {
      'calls': 1,
      'inputTokens': 50,
      'outputTokens': 15,
      'features': {'radiology_ai': 1},
    });
    expect((writes[1].$3['gemini'] as Map)['errors'], 1);
  });
}
