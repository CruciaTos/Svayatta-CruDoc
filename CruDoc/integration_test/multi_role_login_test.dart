// Signs into the real app as each role of the seeded emulator clinic, one
// after another in the same app run, and reports what each person sees.
//
//   firebase emulators:start
//   node seed_emulator_clinic.js
//   flutter test integration_test/multi_role_login_test.dart -d windows \
//     --dart-define=USE_FIREBASE_EMULATORS=true \
//     --dart-define=EMULATOR_HOST=localhost \
//     --dart-define=SHOT_DIR=<folder for screenshots>
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:doctor_management_app/main.dart' as app;
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

const _shotDir = String.fromEnvironment('SHOT_DIR');
const _password = 'Test1234';

const _patients = ['Alice', 'Bhavna', 'Chetan', 'Dinesh'];

class _Account {
  const _Account(this.key, this.email, this.name);
  final String key;
  final String email;
  final String name;
}

const _accounts = [
  _Account('owner', 'owner@crudoc.test', 'Dr Asha Rao'),
  _Account('manager', 'manager@crudoc.test', 'Priya Nair'),
  _Account('doctor2', 'doctor2@crudoc.test', 'Dr Vikram Shah'),
  _Account('doctor3', 'doctor3@crudoc.test', 'Dr Meera Pillai'),
  _Account('reception', 'reception@crudoc.test', 'Rahul Das'),
];

final _errors = <String>[];
void _report(String line) => debugPrint('REPORT: $line');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('multi-role login', (tester) async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      _errors.add(
        'FlutterError: ${details.exceptionAsString()}'.split('\n').first,
      );
    };

    runZonedGuarded(app.main, (e, s) {
      _errors.add('Uncaught: $e'.split('\n').first);
    });

    try {
      await _waitFor(
        tester,
        _signInButton,
        'auth screen',
        timeout: const Duration(seconds: 60),
      );

      var i = 0;
      for (final a in _accounts) {
        i++;
        final before = _errors.length;
        _report('===== ${a.key} (${a.email}) =====');
        await _signIn(tester, a);
        await _shot(tester, '${i}a-${a.key}-dashboard');
        _report('${a.key} sidebar: ${_sidebarLabels().join(', ')}');

        await _openPatients(tester);
        await _settle(tester, seconds: 6);
        await _shot(tester, '${i}b-${a.key}-patients');
        final visible = _patients.where(_onScreen).toList();
        _report('${a.key} patients visible: ${visible.join(', ')}');

        await _logOut(tester);
        await _shot(tester, '${i}c-${a.key}-after-logout');
        final newErrors = _errors.sublist(before);
        _report('${a.key} errors during session: ${newErrors.length}');
        for (final e in newErrors.toSet()) {
          _report('  - $e');
        }
      }
    } finally {
      FlutterError.onError = originalOnError;
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}

final _signInButton = find.byWidgetPredicate(
  (w) => w is CruButton && w.label == 'Sign in',
);
final _profileButton = find.byWidgetPredicate(
  (w) => w.runtimeType.toString() == '_ProfileButton',
);

Future<void> _signIn(WidgetTester tester, _Account a) async {
  // First launch opens on Sign up; switch to the sign-in form.
  final toSignIn = find.byWidgetPredicate(
    (w) => w is CruLink && w.label == 'Sign in',
  );
  if (toSignIn.evaluate().isNotEmpty) {
    await tester.tap(toSignIn);
    await _settle(tester);
  }
  await _waitFor(tester, _signInButton, 'sign-in button');
  final fields = find.byType(EditableText);
  await tester.enterText(fields.at(0), a.email);
  await tester.enterText(fields.at(1), _password);
  await tester.pump();
  await tester.tap(_signInButton);
  await _waitFor(
    tester,
    _profileButton,
    'shell after sign-in (${a.key})',
    timeout: const Duration(seconds: 90),
  );
  // Let the first sync run.
  await _settle(tester, seconds: 8);
  // A first-run tour may cover the shell.
  final skip = find.text('Skip');
  if (skip.evaluate().isNotEmpty) {
    await tester.tap(skip.first);
    await _settle(tester);
  }
}

Future<void> _openPatients(WidgetTester tester) async {
  // "Patients" is both a sidebar group heading and the item; the item is
  // the tappable one.
  final item = find.ancestor(
    of: find.text('Patients'),
    matching: find.byWidgetPredicate(
      (w) => w is GestureDetector || w is InkWell,
    ),
  );
  if (item.evaluate().isEmpty) {
    _report('  Patients not in sidebar');
    return;
  }
  await tester.tap(item.first, warnIfMissed: false);
}

Future<void> _logOut(WidgetTester tester) async {
  await tester.tap(_profileButton.first);
  await _settle(tester, seconds: 1);
  final logout = find.text('Log out');
  await _waitFor(tester, logout, 'Log out menu item');
  await tester.tap(logout.last);
  await _waitFor(
    tester,
    _signInButton,
    'auth screen after logout',
    timeout: const Duration(seconds: 60),
  );
  await _settle(tester, seconds: 3);
}

List<String> _sidebarLabels() {
  final nav = find.bySemanticsLabel('Main navigation');
  final scope = nav.evaluate().isNotEmpty
      ? find.descendant(of: nav.first, matching: find.byType(Text))
      : find.byType(Text);
  return scope
      .evaluate()
      .map((e) => (e.widget as Text).data ?? '')
      .where((s) => s.trim().isNotEmpty)
      .toList();
}

bool _onScreen(String word) =>
    find.textContaining(word, findRichText: true).evaluate().isNotEmpty;

Future<void> _settle(WidgetTester tester, {int seconds = 2}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder f,
  String what, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (f.evaluate().isNotEmpty) return;
  }
  await _shot(tester, 'timeout-${what.replaceAll(RegExp(r'[^a-z0-9]+'), '-')}');
  throw TestFailure('Timed out waiting for $what');
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
