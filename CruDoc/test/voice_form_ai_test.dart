import 'dart:typed_data';

import 'package:doctor_management_app/core/services/gemini_json_client.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/voice/domain/voice_command.dart';
import 'package:doctor_management_app/features/voice/domain/voice_navigation.dart';
import 'package:doctor_management_app/features/voice/services/voice_form_ai.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGemini extends GeminiJsonClient {
  _FakeGemini(this.reply) : super(apiKey: 'test', model: 'gemini-2.5-flash');

  final Map<String, dynamic> Function() reply;
  String? lastPrompt;
  bool? lastQuick;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> generateJson({
    required String systemPrompt,
    required String prompt,
    Uint8List? audioBytes,
    required Schema schema,
    String mimeType = 'audio/mp4',
    int maxOutputTokens = 8192,
    Duration timeout = const Duration(seconds: 60),
    bool quick = false,
  }) async {
    calls++;
    lastPrompt = prompt;
    lastQuick = quick;
    return reply();
  }
}

const _visible = <({int tab, String label})>[
  (tab: DesktopTab.dashboard, label: 'Dashboard'),
  (tab: DesktopTab.inventory, label: 'Inventory'),
  (tab: DesktopTab.revenue, label: 'Revenue'),
];

void main() {
  final now = DateTime(2026, 10, 15, 10);

  group('VoiceFormAi', () {
    test('sends the sentence, form values and lists; no thinking', () async {
      final gemini = _FakeGemini(() => {'name': 'Paracetamol 500mg'});
      final ai = VoiceFormAi(client: gemini);
      final out = await ai.read(
        VoiceForm.item,
        'add paracetamol 500 mg to inventory',
        now: now,
        current: {'unit': 'Tablets', 'batch': ''},
        choices: {
          'units': ['Tablets', 'Capsules'],
        },
      );
      expect(out, {'name': 'Paracetamol 500mg'});
      expect(gemini.lastQuick, isTrue);
      expect(gemini.lastPrompt, contains('"add paracetamol 500 mg'));
      expect(gemini.lastPrompt, contains('"unit":"Tablets"'));
      expect(gemini.lastPrompt, isNot(contains('"batch"')));
      expect(gemini.lastPrompt, contains('Listed units: Tablets, Capsules'));
      expect(gemini.lastPrompt, contains('Thursday 15 October 2026'));
    });

    test('a failure returns null and pauses asking', () async {
      final gemini = _FakeGemini(() => throw Exception('offline'));
      final ai = VoiceFormAi(client: gemini);
      expect(await ai.read(VoiceForm.item, 'add gloves', now: now), isNull);
      expect(await ai.read(VoiceForm.item, 'add gloves', now: now), isNull);
      expect(gemini.calls, 1);
    });

    test('a busy server is asked again, and not paused', () async {
      var busy = 1;
      final gemini = _FakeGemini(() {
        if (busy-- > 0) throw const GeminiHttpException(503, 'high demand');
        return {'name': 'Gloves'};
      });
      final ai = VoiceFormAi(client: gemini);
      expect(await ai.read(VoiceForm.item, 'add gloves', now: now), {
        'name': 'Gloves',
      });
      expect(gemini.calls, 2);

      busy = 2;
      expect(await ai.read(VoiceForm.item, 'add gloves', now: now), isNull);
      expect(await ai.read(VoiceForm.item, 'add gloves', now: now), {
        'name': 'Gloves',
      });
      expect(gemini.calls, 5);
    });

    test('kinds map to forms', () {
      expect(VoiceForm.ofKind('addPatient'), VoiceForm.patient);
      expect(VoiceForm.ofKind('reschedule'), VoiceForm.appointment);
      expect(VoiceForm.ofKind('item'), VoiceForm.item);
      expect(VoiceForm.ofKind('scribe'), isNull);
    });
  });

  group('AiValue', () {
    test('reads loose values safely', () {
      expect(AiValue.str(' null '), isNull);
      expect(AiValue.integer(12.6), 13);
      expect(AiValue.number('₹2,500'), 2500);
      expect(AiValue.date('2027-03-31'), DateTime(2027, 3, 31));
      expect(AiValue.date('2027-13-01'), isNull);
      expect(AiValue.time('17:05'), (17, 5));
      expect(AiValue.time('25:00'), isNull);
      expect(AiValue.strings(['Diabetes', '', null, 'BP']), ['Diabetes', 'BP']);
    });

    test('snaps to the form presets', () {
      const units = ['Tablets', 'Syrup (ml)', 'Pcs'];
      expect(AiValue.pick('tablet', units), 'Tablets');
      expect(AiValue.pick('Syrup', units), 'Syrup (ml)');
      expect(AiValue.pick('Boxes', units), 'Boxes');
      expect(AiValue.pick('analgesics', ['Analgesic']), 'Analgesic');
    });
  });

  group('opening forms by voice', () {
    NavTarget? target(String text) {
      final r = resolveNavigation(text, _visible, now);
      return r is NavScreen ? r.target : null;
    }

    test('"add X to the inventory" opens Add item', () {
      expect(target('add paracetamol 500 mg to the inventory')?.spots, {
        'action.addItem',
      });
      expect(target('put two boxes of gloves in stock')?.spots, {
        'action.addItem',
      });
    });

    test('an amount may sit inside the command', () {
      expect(target('add 2000 expense')?.spots, {'action.recordExpense'});
    });
  });

  group('live parser keeps names clean', () {
    test('a condition after the name', () {
      final c = VoiceCommand.parse(
        'add a new patient named Sneha Kulkarni, female, 28 years old, '
        'she has migraine',
        now,
      );
      expect(c.name, 'sneha kulkarni');
      expect(c.conditions, ['Migraine']);
    });

    test('"for follow up" is the reason', () {
      final c = VoiceCommand.parse(
        'book appointment for Maya Patel on 20th October at 11:30 am for '
        'follow up',
        now,
      );
      expect(c.name, 'maya patel');
      expect(c.reason, 'Follow-up');
    });
  });
}
