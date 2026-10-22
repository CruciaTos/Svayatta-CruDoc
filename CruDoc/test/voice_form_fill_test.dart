import 'dart:io';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/core/services/gemini_json_client.dart';
import 'package:doctor_management_app/features/voice/forms/voice_form_filler.dart';
import 'package:doctor_management_app/features/voice/forms/voice_form_scan.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Answers with fills keyed by field label, so tests don't depend on ids.
class _FakeGemini extends GeminiJsonClient {
  _FakeGemini(this.byLabel, {this.fail = false})
    : super(apiKey: 'test', model: 'test-model');

  final Map<String, String> byLabel;
  final bool fail;
  String? lastPrompt;

  @override
  Future<Map<String, dynamic>> generateJson({
    required String systemPrompt,
    required String prompt,
    Uint8List? audioBytes,
    List<Uint8List> images = const [],
    required Schema schema,
    String mimeType = 'audio/mp4',
    int maxOutputTokens = 8192,
    Duration timeout = const Duration(seconds: 60),
    bool quick = false,
  }) async {
    lastPrompt = prompt;
    if (fail) throw const SocketException('offline');
    final fields = RegExp(
      r'"id":"(f\d+)","label":"([^"]+)"',
    ).allMatches(prompt).map((m) => (id: m.group(1)!, label: m.group(2)!));
    return {
      'fills': [
        for (final f in fields)
          if (byLabel.containsKey(f.label))
            {'id': f.id, 'value': byLabel[f.label]},
      ],
      'unsure': '',
    };
  }
}

/// A medicine form using each kind of input the app's forms use.
class _MedicineForm extends StatefulWidget {
  const _MedicineForm({this.withPassword = false});
  final bool withPassword;

  @override
  State<_MedicineForm> createState() => _MedicineFormState();
}

class _MedicineFormState extends State<_MedicineForm> {
  final name = TextEditingController();
  final dose = TextEditingController();
  final phone = TextEditingController();
  final notes = TextEditingController();
  final search = TextEditingController();
  final locked = TextEditingController(text: 'MED-001');
  String? frequency;
  String unit = 'Tablet';
  String route = 'Oral';
  bool whatsapp = false;
  bool urgent = false;
  List<String> tags = const [];
  int doseChanges = 0;

  @override
  Widget build(BuildContext context) {
    return Material(
      child: SingleChildScrollView(
        child: Column(
          children: [
            CruTextField(label: 'Medicine name', controller: name),
            TextField(
              controller: dose,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => doseChanges++,
              decoration: const InputDecoration(labelText: 'Dose (mg) *'),
            ),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(hintText: 'Supplier phone'),
            ),
            TextField(
              controller: notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            TextField(
              controller: search,
              decoration: const InputDecoration(hintText: 'Search medicines'),
            ),
            TextField(
              controller: locked,
              enabled: false,
              decoration: const InputDecoration(labelText: 'Code'),
            ),
            DropdownButtonFormField<String>(
              initialValue: frequency,
              decoration: const InputDecoration(labelText: 'Frequency'),
              items: const [
                DropdownMenuItem(value: 'OD', child: Text('Once a day')),
                DropdownMenuItem(value: 'BD', child: Text('Twice a day')),
                DropdownMenuItem(value: 'TDS', child: Text('Thrice a day')),
              ],
              onChanged: (v) => setState(() => frequency = v),
            ),
            CruDropdownField<String>(
              label: 'Unit',
              value: unit,
              items: const ['Tablet', 'Syrup', 'Gel'],
              itemLabel: (s) => s,
              onChanged: (v) => setState(() => unit = v),
            ),
            CruSegmentedControl<String>(
              semanticLabel: 'Route',
              segments: const [
                CruSegment('Oral', 'Oral'),
                CruSegment('Topical', 'Topical'),
              ],
              selected: route,
              onChanged: (v) => setState(() => route = v),
            ),
            CheckboxListTile(
              title: const Text('Send on WhatsApp'),
              value: whatsapp,
              onChanged: (v) => setState(() => whatsapp = v ?? false),
            ),
            Row(
              children: [
                const Text('Urgent'),
                Switch(
                  value: urgent,
                  onChanged: (v) => setState(() => urgent = v),
                ),
              ],
            ),
            CruTagField(
              label: 'Allergies',
              values: tags,
              max: 5,
              onChanged: (v) => setState(() => tags = v),
            ),
            if (widget.withPassword)
              const TextField(
                obscureText: true,
                decoration: InputDecoration(labelText: 'Password'),
              ),
          ],
        ),
      ),
    );
  }
}

final _nav = GlobalKey<NavigatorState>();

BuildContext get _root => _nav.currentContext!;

Future<void> _pumpApp(WidgetTester t, Widget home) async {
  t.view.physicalSize = const Size(1200, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(navigatorKey: _nav, theme: CruTheme.day(), home: home),
  );
}

/// Opens [form] as a dialog over a plain page.
Future<_MedicineFormState> _openDialog(
  WidgetTester t, {
  Widget page = const Scaffold(body: Text('Dashboard')),
  bool withPassword = false,
}) async {
  await _pumpApp(t, page);
  showDialog<void>(
    context: _root,
    builder: (_) => Dialog(child: _MedicineForm(withPassword: withPassword)),
  );
  await t.pumpAndSettle();
  return t.state<_MedicineFormState>(find.byType(_MedicineForm).last);
}

void main() {
  group('VoiceFormScan', () {
    testWidgets('finds each labelled input with its kind', (t) async {
      await _openDialog(t);
      final scan = VoiceFormScan.of(_root);

      expect(scan.inPopup, isTrue);
      expect(scan.blockedReason, isNull);
      final byLabel = {for (final f in scan.fields) f.label: f};
      expect(byLabel.keys.toSet(), {
        'Medicine name',
        'Dose (mg)',
        'Supplier phone',
        'Notes',
        'Frequency',
        'Unit',
        'Route',
        'Send on WhatsApp',
        'Urgent',
        'Allergies',
      });
      expect(byLabel['Medicine name']!.type, VoiceFieldType.text);
      expect(byLabel['Dose (mg)']!.type, VoiceFieldType.number);
      expect(byLabel['Supplier phone']!.type, VoiceFieldType.phone);
      expect(byLabel['Notes']!.type, VoiceFieldType.multiline);
      expect(byLabel['Frequency']!.options, [
        'Once a day',
        'Twice a day',
        'Thrice a day',
      ]);
      expect(byLabel['Unit']!.type, VoiceFieldType.choice);
      expect(byLabel['Route']!.options, ['Oral', 'Topical']);
      expect(byLabel['Send on WhatsApp']!.type, VoiceFieldType.toggle);
      expect(byLabel['Urgent']!.type, VoiceFieldType.toggle);
      expect(byLabel['Allergies']!.type, VoiceFieldType.list);
    });

    testWidgets('a dialog in front hides the page behind it', (t) async {
      await _openDialog(t, page: const Scaffold(body: _MedicineForm()));
      final scan = VoiceFormScan.of(_root);
      expect(scan.inPopup, isTrue);
      expect(scan.fields.where((f) => f.label == 'Medicine name'), hasLength(1));
    });

    testWidgets('a dialog without inputs means no form', (t) async {
      await _pumpApp(t, const Scaffold(body: _MedicineForm()));
      expect(VoiceFormScan.of(_root).inPopup, isFalse);
      expect(VoiceFormScan.of(_root).fields, isNotEmpty);

      showDialog<void>(
        context: _root,
        builder: (_) => const AlertDialog(content: Text('Delete this?')),
      );
      await t.pumpAndSettle();
      expect(VoiceFormScan.of(_root).isEmpty, isTrue);
    });

    testWidgets('inputs offstage are left out', (t) async {
      await _pumpApp(
        t,
        const Scaffold(
          body: IndexedStack(
            index: 0,
            children: [Text('Tab one'), _MedicineForm()],
          ),
        ),
      );
      expect(VoiceFormScan.of(_root).isEmpty, isTrue);
    });

    testWidgets('a password form is blocked outright', (t) async {
      await _openDialog(t, withPassword: true);
      final scan = VoiceFormScan.of(_root);
      expect(scan.fields, isEmpty);
      expect(scan.blockedReason, contains("doesn't fill sign-in or payment"));
    });
  });

  group('VoiceFormFiller', () {
    testWidgets('fills every kind of input through its own handlers', (
      t,
    ) async {
      final form = await _openDialog(t);
      final gemini = _FakeGemini({
        'Medicine name': 'Paracetamol',
        'Dose (mg)': '500',
        'Supplier phone': '+91 98220 12345',
        'Frequency': 'Twice a day',
        'Unit': 'Syrup',
        'Route': 'Topical',
        'Send on WhatsApp': 'yes',
        'Urgent': 'yes',
        'Allergies': 'penicillin, sulfa',
      });
      final r = await VoiceFormFiller(client: gemini).fill(
        'paracetamol 500 twice a day syrup topical ...',
        VoiceFormScan.of(_root),
      );
      await t.pump();

      expect(r.rejected, isEmpty);
      expect(form.name.text, 'Paracetamol');
      expect(form.dose.text, '500');
      expect(form.doseChanges, greaterThan(0), reason: 'onChanged runs');
      expect(form.phone.text, '9822012345');
      expect(form.frequency, 'BD');
      expect(form.unit, 'Syrup');
      expect(form.route, 'Topical');
      expect(form.whatsapp, isTrue);
      expect(form.urgent, isTrue);
      expect(form.tags, ['penicillin', 'sulfa']);
      // Only labels and options go to the model, never what fields hold.
      expect(gemini.lastPrompt, isNot(contains('MED-001')));
      expect(r.summary, startsWith('Filled'));
      expect(r.summary, contains('tap Save'));
    });

    testWidgets('values that fail the input are reported, not forced in', (
      t,
    ) async {
      final form = await _openDialog(t);
      final r = await VoiceFormFiller(
        client: _FakeGemini({
          'Supplier phone': '98220',
          'Frequency': 'every hour',
          'Dose (mg)': 'a lot',
          'Urgent': 'maybe',
        }),
      ).fill('…', VoiceFormScan.of(_root));
      await t.pump();

      expect(form.phone.text, isEmpty);
      expect(form.frequency, isNull);
      expect(form.dose.text, isEmpty);
      expect(form.urgent, isFalse);
      expect(r.filled, isEmpty);
      expect(r.rejected.keys, containsAll(['Supplier phone', 'Frequency']));
      expect(r.rejected['Dose (mg)'], contains("isn't a number"));
    });

    testWidgets('typed text is kept unless the doctor names the field', (
      t,
    ) async {
      final form = await _openDialog(t);
      form.name.text = 'Crocin';
      final filler = VoiceFormFiller(
        client: _FakeGemini({'Medicine name': 'Dolo'}),
      );

      var r = await filler.fill('dolo 650', VoiceFormScan.of(_root));
      expect(form.name.text, 'Crocin');
      expect(r.kept, ['Medicine name']);

      r = await filler.fill(
        'change the medicine name to dolo',
        VoiceFormScan.of(_root),
      );
      expect(form.name.text, 'Dolo');
      expect(r.filled, ['Medicine name']);
    });

    testWidgets('undo puts back what the last fill changed', (t) async {
      final form = await _openDialog(t);
      final filler = VoiceFormFiller(
        client: _FakeGemini({'Medicine name': 'Dolo', 'Unit': 'Gel'}),
      );
      await filler.fill('dolo gel', VoiceFormScan.of(_root));
      await t.pump();
      expect(form.unit, 'Gel');

      expect(filler.undo(), 2);
      await t.pump();
      expect(form.name.text, isEmpty);
      expect(form.unit, 'Tablet');
      expect(filler.canUndo, isFalse);
    });

    testWidgets('on a full screen only named inputs are filled', (t) async {
      await _pumpApp(t, const Scaffold(body: _MedicineForm()));
      final form = t.state<_MedicineFormState>(find.byType(_MedicineForm));
      final r = await VoiceFormFiller(
        client: _FakeGemini({'Medicine name': 'Dolo', 'Notes': 'After food'}),
      ).fill('notes after food', VoiceFormScan.of(_root));

      expect(form.notes.text, 'After food');
      expect(form.name.text, isEmpty);
      expect(r.filled, ['Notes']);
    });

    testWidgets('offline, it matches spoken field names', (t) async {
      final form = await _openDialog(t);
      final r = await VoiceFormFiller(
        client: _FakeGemini(const {}, fail: true),
      ).fill(
        'medicine name is Azithromycin, dose 250 and notes take after food',
        VoiceFormScan.of(_root),
      );
      await t.pump();

      expect(form.name.text, 'Azithromycin');
      expect(form.dose.text, '250');
      expect(form.notes.text, 'take after food');
      expect(r.filled, hasLength(3));
    });

    testWidgets('a blocked form is never filled', (t) async {
      await _openDialog(t, withPassword: true);
      final r = await VoiceFormFiller(
        client: _FakeGemini({'Medicine name': 'Dolo'}),
      ).fill('dolo', VoiceFormScan.of(_root));
      expect(r.blocked, isNotNull);
      expect(r.filled, isEmpty);
    });
  });

  group('value checks', () {
    test('matchOption needs one clear option', () {
      const opts = ['Once a day', 'Twice a day', 'Thrice a day'];
      expect(VoiceFormFiller.matchOption('twice a day', opts), 'Twice a day');
      expect(VoiceFormFiller.matchOption('Twice', opts), 'Twice a day');
      expect(VoiceFormFiller.matchOption('a day', opts), isNull);
      expect(VoiceFormFiller.matchOption('weekly', opts), isNull);
    });

    test('mentions needs the field named, not a word that overlaps', () {
      expect(VoiceFormFiller.mentions('the dose is 500', 'Dose (mg)'), isTrue);
      expect(
        VoiceFormFiller.mentions('set the date to Friday', 'Date of birth'),
        isFalse,
      );
      expect(
        VoiceFormFiller.mentions('date of birth 3rd May', 'Date of birth'),
        isTrue,
      );
    });
  });
}
