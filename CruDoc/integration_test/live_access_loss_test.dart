// A signed-in doctor loses access while the app is open: first one patient
// is reassigned to someone else, then their membership is switched off.
// Reports whether the running app follows, and whether Firestore could reach
// the server at the time (on Windows it can stay offline after an account
// switch, and then no change arrives at all).
//
//   --dart-define=BEFORE=reception@crudoc.test   sign that person in and out
//                                                first (an account switch)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/main.dart' as app;
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

const _before = String.fromEnvironment('BEFORE');
const _project = 'svayatta-crudoc-dev';

void _report(String line) => debugPrint('REPORT: $line');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'doctor loses access while signed in',
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
        if (_before.isNotEmpty) {
          _report('first signing in and out as $_before');
          await _signIn(tester, _before);
          await _logOut(tester);
        }

        await _signIn(tester, 'doctor2@crudoc.test');
        final clinicId = ClinicSession.instance.access!.clinicId;
        final d2 = FirebaseAuth.instance.currentUser!.uid;
        final d3 = await _uidOf('doctor3@crudoc.test');
        await _openPatients(tester);
        await _until(tester, () => false, 4);
        _report('server reachable: ${await _serverReachable()}');
        _report('sees Alice before: ${_onScreen('Alice')}');

        // ---- bug 3: patient reassigned away -------------------------------
        await _patch('patients/seed-alice', {
          'assignedDoctorUids': [d3],
        });
        final gone = await _until(tester, () => !_onScreen('Alice'), 30);
        _report('Alice gone after reassign: $gone');
        await _patch('patients/seed-alice', {
          'assignedDoctorUids': [d2],
        });
        final back = await _until(tester, () => _onScreen('Alice'), 30);
        _report('Alice back after reassign back: $back');

        // ---- bug 2: membership switched off --------------------------------
        _report('server reachable: ${await _serverReachable()}');
        await _patch('clinics/$clinicId/members/$d2', {'active': false});
        final kicked = await _until(
          tester,
          () => _signInButton.evaluate().isNotEmpty,
          30,
        );
        _report('sent to sign-in after deactivation: $kicked');
        _report(
          'access now: clinic=${ClinicSession.instance.access?.clinicId == clinicId ? 'Sunrise Dental' : ClinicSession.instance.access?.clinicId} '
          'auth=${FirebaseAuth.instance.currentUser?.email}',
        );
        await _patch('clinics/$clinicId/members/$d2', {'active': true});
        if (!kicked) await _logOut(tester);
      } finally {
        FlutterError.onError = originalOnError;
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

Future<String> _serverReachable() async {
  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 5));
    return 'yes';
  } on FirebaseException catch (e) {
    return e.code == 'unavailable' ? 'NO (offline)' : 'yes (${e.code})';
  } on TimeoutException {
    return 'NO (timeout)';
  }
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

Future<String> _uidOf(String email) async {
  final req = await _http.postUrl(
    Uri.parse(
      'http://localhost:9099/identitytoolkit.googleapis.com/v1/projects/$_project/accounts:lookup',
    ),
  );
  req.headers.set('Authorization', 'Bearer owner');
  req.headers.contentType = ContentType.json;
  req.write(
    jsonEncode({
      'email': [email],
    }),
  );
  final res = await req.close();
  final body = jsonDecode(await res.transform(utf8.decoder).join());
  return body['users'][0]['localId'] as String;
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
