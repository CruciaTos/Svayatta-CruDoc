// A patient's notes and conditions: hidden from the front desk, kept off
// their device, never wiped by their edits, and still there for a doctor.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:doctor_management_app/main.dart' as app;
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

const _project = 'svayatta-crudoc-dev';
const _shotDir = String.fromEnvironment('SHOT_DIR');
const _note = 'TESTNOTE penicillin reaction';
const _condition = 'TESTCOND caries';

void _report(String line) => debugPrint('REPORT: $line');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('clinical fields per role', (tester) async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (_) {};
    runZonedGuarded(app.main, (_, _) {});
    try {
      await _patch('patients/seed-alice', {
        'notes': _note,
        'diagnosis': [_condition],
      });
      await _until(
        tester,
        () =>
            _signInButton.evaluate().isNotEmpty ||
            _profileButton.evaluate().isNotEmpty,
        60,
      );
      if (_profileButton.evaluate().isNotEmpty) {
        await _until(tester, () => false, 5);
        await _logOut(tester);
      }

      for (final who in ['reception', 'doctor2']) {
        _report('===== $who =====');
        await _signIn(tester, '$who@crudoc.test');
        await _openPatients(tester);
        await _until(tester, () => false, 4);
        _report('patient list shows condition: ${_onScreen('TESTCOND')}');
        await tester.tap(
          find.textContaining('Alice').first,
          warnIfMissed: false,
        );
        await _until(tester, () => false, 5);
        final full = find.textContaining('Open full');
        if (full.evaluate().isNotEmpty) {
          await tester.tap(full.first, warnIfMissed: false);
          await _until(tester, () => false, 5);
        } else {
          _report('no "Open full" button');
        }
        await _shot(tester, 'C-$who-alice');
        _report(
          'page has "Clinical notes": ${_onScreen('Clinical notes')}, '
          '"Medical history": ${_onScreen('Medical history')}',
        );
        _report(
          'page shows the note: ${_onScreen('TESTNOTE')}, '
          'the condition: ${_onScreen('TESTCOND')}',
        );

        if (who == 'reception') {
          // What the edit form sends: the fields as this person holds them.
          await PatientRepository().updatePatient('seed-alice', {
            'phone': '9876500099',
            'diagnosis': <String>[],
            'notes': '',
          });
          await _until(tester, () => false, 10);
          final f = (await _get('patients/seed-alice'))['fields'] as Map;
          _report(
            'server after front-desk edit: '
            'notes=${f['notes']?.values.first} '
            'diagnosis=${jsonEncode(f['diagnosis'])} '
            'phone changed=${f['phone']?.values.first != '+919876500001'}',
          );
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _until(tester, () => false, 1);
        await _logOut(tester);
      }
    } finally {
      FlutterError.onError = originalOnError;
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}

// ---- emulator admin access ---------------------------------------------

final _http = HttpClient();
String _docUrl(String path) =>
    'http://localhost:8080/v1/projects/$_project/databases/(default)/documents/$path';

Object _value(Object? v) => switch (v) {
  bool b => {'booleanValue': b},
  String s => {'stringValue': s},
  List l => {
    'arrayValue': {'values': l.map(_value).toList()},
  },
  _ => throw ArgumentError(v),
};

Future<void> _patch(String path, Map<String, Object> fields) async {
  final mask = fields.keys.map((k) => 'updateMask.fieldPaths=$k').join('&');
  final req = await _http.openUrl('PATCH', Uri.parse('${_docUrl(path)}?$mask'));
  req.headers.set('Authorization', 'Bearer owner');
  req.headers.contentType = ContentType.json;
  req.write(
    jsonEncode({'fields': fields.map((k, v) => MapEntry(k, _value(v)))}),
  );
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  if (res.statusCode != 200) throw StateError('PATCH $path: $body');
}

Future<Map<String, dynamic>> _get(String path) async {
  final req = await _http.getUrl(Uri.parse(_docUrl(path)));
  req.headers.set('Authorization', 'Bearer owner');
  final res = await req.close();
  return jsonDecode(await res.transform(utf8.decoder).join())
      as Map<String, dynamic>;
}

// ---- UI helpers ----------------------------------------------------------

final _signInButton = find.byWidgetPredicate(
  (w) => w is CruButton && w.label == 'Sign in',
);
final _profileButton = find.byWidgetPredicate(
  (w) => w.runtimeType.toString() == '_ProfileButton',
);

Future<void> _signIn(WidgetTester tester, String email) async {
  final toSignIn = find.byWidgetPredicate(
    (w) => w is CruLink && w.label == 'Sign in',
  );
  if (toSignIn.evaluate().isNotEmpty) {
    await tester.tap(toSignIn);
    await _until(tester, () => false, 1);
  }
  await _waitFor(tester, _signInButton, 30);
  final fields = find.byType(EditableText);
  await tester.enterText(fields.at(0), email);
  await tester.enterText(fields.at(1), 'Test1234');
  await tester.pump();
  await tester.tap(_signInButton);
  await _waitFor(tester, _profileButton, 90);
  await _until(tester, () => false, 8);
  final skip = find.text('Skip');
  if (skip.evaluate().isNotEmpty) {
    await tester.tap(skip.first);
    await _until(tester, () => false, 2);
  }
}

Future<void> _openPatients(WidgetTester tester) async {
  final item = find.ancestor(
    of: find.text('Patients'),
    matching: find.byWidgetPredicate(
      (w) => w is GestureDetector || w is InkWell,
    ),
  );
  if (item.evaluate().isEmpty) return;
  await tester.tap(item.first, warnIfMissed: false);
}

Future<void> _logOut(WidgetTester tester) async {
  for (var tries = 0; tries < 5; tries++) {
    await tester.tap(_profileButton.first, warnIfMissed: false);
    if (await _until(
      tester,
      () => find.text('Log out').evaluate().isNotEmpty,
      3,
    )) {
      break;
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _until(tester, () => false, 2);
  }
  await _waitFor(tester, find.text('Log out'), 5);
  await tester.tap(find.text('Log out').last);
  await _waitFor(tester, _signInButton, 60);
  await _until(tester, () => false, 3);
}

bool _onScreen(String word) =>
    find.textContaining(word, findRichText: true).evaluate().isNotEmpty;

Future<bool> _until(
  WidgetTester tester,
  bool Function() ok,
  int seconds,
) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (ok()) return true;
  }
  return false;
}

Future<void> _waitFor(WidgetTester tester, Finder f, int seconds) async {
  if (!await _until(tester, () => f.evaluate().isNotEmpty, seconds)) {
    throw TestFailure('Timed out waiting for $f');
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (_shotDir.isEmpty) return;
  await tester.pump();
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  final image = await layer.toImage(Offset.zero & view.size);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  await File('$_shotDir/$name.png').writeAsBytes(png!.buffer.asUint8List());
}
