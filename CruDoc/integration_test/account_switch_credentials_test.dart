// Repro for patients leaking into a scoped doctor's device copy after the
// front desk signs out and the doctor signs in on the same Windows PC.
//
// Right after the doctor signs in, runs the query a scoped doctor may NOT
// run (every patient of the clinic, no assignment filter) through the app's
// own Firestore client. The rules refuse it for the doctor, so if it
// succeeds the client is still sending the previous person's credentials.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:doctor_management_app/main.dart' as app;
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

const _clinicId = String.fromEnvironment('CLINIC_ID');
const _rounds = int.fromEnvironment('ROUNDS', defaultValue: 1);
// Seconds between the front desk logging out and the doctor signing in.
const _gap = int.fromEnvironment('GAP_SECONDS', defaultValue: 3);

void _report(String line) => debugPrint('REPORT: $line');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'front desk -> doctor account switch',
    (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (_) {};
      runZonedGuarded(app.main, (_, _) {});
      try {
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
        for (var round = 1; round <= _rounds; round++) {
          _report('===== round $round =====');
          await _signIn(tester, 'reception@crudoc.test');
          await _logOut(tester);
          _report('waiting ${_gap}s before the doctor signs in');
          await _until(tester, () => false, _gap);

          final t0 = DateTime.now();
          await _submit(tester, 'doctor2@crudoc.test');
          // Probe from the moment the doctor is the signed-in user.
          await _until(
            tester,
            () =>
                FirebaseAuth.instance.currentUser?.email ==
                'doctor2@crudoc.test',
            30,
          );
          final results = <String>[];
          final end = DateTime.now().add(const Duration(seconds: 12));
          while (DateTime.now().isBefore(end)) {
            final ms = DateTime.now().difference(t0).inMilliseconds;
            final who = FirebaseAuth.instance.currentUser?.email;
            Future<String> run(Source src) async {
              try {
                final snap = await FirebaseFirestore.instance
                    .collection('patients')
                    .where('doctorId', isEqualTo: _clinicId)
                    .get(GetOptions(source: src))
                    .timeout(const Duration(seconds: 4));
                final names = snap.docs
                    .map((d) => d.data()['firstName'])
                    .join('/');
                return 'ALLOWED ${snap.docs.length} [$names]';
              } on FirebaseException catch (e) {
                return e.code;
              } on TimeoutException {
                return 'timeout';
              }
            }

            final server = await run(Source.server);
            final cache = await run(Source.cache);
            final clock = DateTime.now().toIso8601String().substring(11, 19);
            final outcome = 'server=$server cache=$cache';
            results.add('$clock +${ms}ms auth=$who -> $outcome');
            await tester.pump(const Duration(milliseconds: 500));
          }
          for (final r in results) {
            _report('  $r');
          }
          final leaked = results
              .where((r) => r.contains('server=ALLOWED'))
              .length;
          final cached = results
              .where((r) => r.contains('cache=ALLOWED'))
              .length;
          _report(
            'round $round: as doctor2, server allowed $leaked/${results.length}, cache answered $cached/${results.length}',
          );

          await _waitFor(tester, _profileButton, 90);
          await _until(tester, () => false, 8);
          final skip = find.text('Skip');
          if (skip.evaluate().isNotEmpty) {
            await tester.tap(skip.first);
            await _until(tester, () => false, 2);
          }
          await _logOut(tester);
        }
      } finally {
        FlutterError.onError = originalOnError;
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

final _signInButton = find.byWidgetPredicate(
  (w) => w is CruButton && w.label == 'Sign in',
);
final _profileButton = find.byWidgetPredicate(
  (w) => w.runtimeType.toString() == '_ProfileButton',
);

Future<void> _submit(WidgetTester tester, String email) async {
  final toSignIn = find.byWidgetPredicate(
    (w) => w is CruLink && w.label == 'Sign in',
  );
  if (toSignIn.evaluate().isNotEmpty) {
    await tester.tap(toSignIn);
    await tester.pump(const Duration(milliseconds: 500));
  }
  await _waitFor(tester, _signInButton, 30);
  final fields = find.byType(EditableText);
  await tester.enterText(fields.at(0), email);
  await tester.enterText(fields.at(1), 'Test1234');
  await tester.pump();
  await tester.tap(_signInButton);
}

Future<void> _signIn(WidgetTester tester, String email) async {
  _report('step: sign in $email');
  await _submit(tester, email);
  await _waitFor(tester, _profileButton, 90);
  await _until(tester, () => false, 8);
  final skip = find.text('Skip');
  if (skip.evaluate().isNotEmpty) {
    await tester.tap(skip.first);
    await _until(tester, () => false, 2);
  }
}

Future<void> _logOut(WidgetTester tester) async {
  _report('step: log out');
  for (var tries = 0; tries < 5; tries++) {
    await tester.tap(_profileButton.first, warnIfMissed: false);
    if (await _until(
      tester,
      () => find.text('Log out').evaluate().isNotEmpty,
      3,
    ))
      break;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _until(tester, () => false, 2);
  }
  await _waitFor(tester, find.text('Log out'), 5);
  await tester.tap(find.text('Log out').last);
  await _waitFor(tester, _signInButton, 60);
  // About as long as a person takes to type the next login.
  await _until(tester, () => false, 3);
}

Future<bool> _until(
  WidgetTester tester,
  bool Function() ok,
  int seconds,
) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (ok()) return true;
  }
  return false;
}

Future<void> _waitFor(WidgetTester tester, Finder f, int seconds) async {
  if (!await _until(tester, () => f.evaluate().isNotEmpty, seconds)) {
    final view = tester.binding.renderViews.first;
    final image = await (view.debugLayer! as OffsetLayer).toImage(
      Offset.zero & view.size,
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '${Directory.systemTemp.path}/crudoc_switch_timeout.png',
    ).writeAsBytes(png!.buffer.asUint8List());
    _report('timeout screenshot: ${Directory.systemTemp.path}/crudoc_switch_timeout.png');
    throw TestFailure(
      'Timed out waiting for ${f.describeMatch(Plurality.zero)}',
    );
  }
}
