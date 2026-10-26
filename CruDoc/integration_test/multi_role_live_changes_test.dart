// Changes a signed-in person's access from outside the app (as the clinic
// admin would, through the Firestore emulator's admin REST access) and
// reports whether the running app follows. Same setup as
// multi_role_login_test.dart; re-seed before each run.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/main.dart' as app;
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

const _shotDir = String.fromEnvironment('SHOT_DIR');
const _project = 'svayatta-crudoc-dev';
const _password = 'Test1234';

final _errors = <String>[];
void _report(String line) => debugPrint('REPORT: $line');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('multi-role live access changes', (tester) async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (d) =>
        _errors.add('FlutterError: ${d.exceptionAsString()}'.split('\n').first);
    runZonedGuarded(
      app.main,
      (e, s) => _errors.add('Uncaught: $e'.split('\n').first),
    );

    try {
      await _waitFor(
        tester,
        _signInButton,
        'auth screen',
        timeout: const Duration(seconds: 60),
      );

      // ---- 1. wrong password ------------------------------------------
      _report('===== 1. wrong password =====');
      await _typeAndSubmit(tester, 'owner@crudoc.test', 'nope-wrong');
      await _settle(tester, seconds: 4);
      await _shot(tester, 'L1-wrong-password');
      _report(
        'still on sign-in: ${_signInButton.evaluate().isNotEmpty}, '
        'shell shown: ${_profileButton.evaluate().isNotEmpty}',
      );
      _report(
        'notice: ${_texts().where((t) => t.contains('nvalid') || t.contains('password')).join(' | ')}',
      );

      // ---- 2. manager gets, then loses, clinical access ----------------
      _report('===== 2. manager clinical access toggled live =====');
      await _signIn(tester, 'manager@crudoc.test');
      final clinicId = ClinicSession.instance.access!.clinicId;
      _report('manager sidebar has Files before: ${_navHas('Files')}');
      await _patch('clinics/$clinicId', {'adminClinicalAccess': true});
      final gained = await _until(tester, () => _navHas('Files'), 25);
      await _shot(tester, 'L2a-manager-granted');
      _report(
        'Files appeared after grant: $gained '
        '(perm now ${ClinicSession.instance.access?.perms.map((p) => p.key).toList()})',
      );
      await _patch('clinics/$clinicId', {'adminClinicalAccess': false});
      final lost = await _until(tester, () => !_navHas('Files'), 25);
      await _shot(tester, 'L2b-manager-revoked');
      _report('Files gone after revoke: $lost');
      await _logOut(tester);

      // ---- 3. receptionist: patient detail + permission removed --------
      _report('===== 3. receptionist =====');
      await _signIn(tester, 'reception@crudoc.test');
      final recepUid = FirebaseAuth.instance.currentUser!.uid;
      await _openPatients(tester);
      await _settle(tester, seconds: 4);
      final alice = find.textContaining('Alice');
      if (alice.evaluate().isNotEmpty) {
        await tester.tap(alice.first, warnIfMissed: false);
        await _settle(tester, seconds: 4);
        await _shot(tester, 'L3a-reception-patient-detail');
        final t = _texts();
        _report(
          'reception patient detail headings: '
          '${t.where((s) => RegExp(r'^(Clinical|Medical|Notes|History|Treatment|Dental|Files|Prescription|Overview|Visits|Billing|Invoices)', caseSensitive: false).hasMatch(s)).toSet().join(', ')}',
        );
        await _closeAnySheet(tester);
      } else {
        _report('reception: Alice not found on Patients');
      }
      _report('reception sidebar has Schedule before: ${_navHas('Schedule')}');
      await _patch('clinics/$clinicId/members/$recepUid', {
        'perms': ['patients.view', 'patients.edit', 'billing', 'messaging'],
      });
      final schedGone = await _until(tester, () => !_navHas('Schedule'), 25);
      await _shot(tester, 'L3b-reception-schedule-removed');
      _report('Schedule gone after perm removed: $schedGone');
      await _patch('clinics/$clinicId/members/$recepUid', {
        'perms': [
          'patients.view',
          'patients.edit',
          'schedule',
          'billing',
          'messaging',
        ],
      });
      final schedBack = await _until(tester, () => _navHas('Schedule'), 25);
      _report('Schedule back after perm restored: $schedBack');
      await _logOut(tester);

      // ---- 4/5. doctor: patient reassigned, then deactivated -----------
      _report('===== 4. doctor2 loses a patient live =====');
      await _signIn(tester, 'doctor2@crudoc.test');
      final d2 = FirebaseAuth.instance.currentUser!.uid;
      await _openPatients(tester);
      await _settle(tester, seconds: 4);
      _report('doctor2 sees Alice before: ${_onScreen('Alice')}');
      final d3 = await _uidOf('doctor3@crudoc.test');
      await _patch('patients/seed-alice', {
        'assignedDoctorUids': [d3],
      });
      final aliceGone = await _until(tester, () => !_onScreen('Alice'), 30);
      await _shot(tester, 'L4-doctor2-after-reassign');
      _report('Alice gone from doctor2 after reassign: $aliceGone');
      await _patch('patients/seed-alice', {
        'assignedDoctorUids': [d2],
      });
      final aliceBack = await _until(tester, () => _onScreen('Alice'), 30);
      _report('Alice back after reassign back: $aliceBack');

      _report('===== 5. doctor2 deactivated live =====');
      await _patch('clinics/$clinicId/members/$d2', {'active': false});
      final kicked = await _until(
        tester,
        () => _signInButton.evaluate().isNotEmpty,
        30,
      );
      await _shot(tester, 'L5a-doctor2-deactivated');
      _report('doctor2 sent to sign-in after deactivation: $kicked');
      _report(
        'snackbar: ${_texts().where((t) => t.contains('access')).join(' | ')}',
      );
      if (!kicked) await _logOut(tester);

      await _patch('clinics/$clinicId/members/$d2', {'active': true});
      await _settle(tester, seconds: 2);
      _report('===== 5b. doctor2 re-activated signs in again =====');
      await _signIn(tester, 'doctor2@crudoc.test');
      _report(
        'doctor2 clinic after reactivation: '
        '${ClinicSession.instance.access?.clinicId == clinicId ? 'Sunrise Dental' : 'own solo practice (${ClinicSession.instance.access?.clinicId})'}',
      );
      await _openPatients(tester);
      await _settle(tester, seconds: 5);
      await _shot(tester, 'L5b-doctor2-reactivated-patients');
      _report(
        'doctor2 patients after reactivation: '
        '${['Alice', 'Bhavna', 'Chetan', 'Dinesh'].where(_onScreen).join(', ')}',
      );
      await _logOut(tester);

      // ---- profile role field ------------------------------------------
      final recepProfile = await _get('users/$recepUid');
      _report(
        'receptionist users doc role field: '
        '${recepProfile['fields']?['role']} memberKind: ${recepProfile['fields']?['memberKind']}',
      );
    } finally {
      _report('errors during run: ${_errors.length}');
      for (final e in _errors.toSet()) {
        _report('  - $e');
      }
      FlutterError.onError = originalOnError;
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
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

Future<void> _typeAndSubmit(
  WidgetTester tester,
  String email,
  String pw,
) async {
  final toSignIn = find.byWidgetPredicate(
    (w) => w is CruLink && w.label == 'Sign in',
  );
  if (toSignIn.evaluate().isNotEmpty) {
    await tester.tap(toSignIn);
    await _settle(tester);
  }
  await _waitFor(tester, _signInButton, 'sign-in button');
  final fields = find.byType(EditableText);
  await tester.enterText(fields.at(0), email);
  await tester.enterText(fields.at(1), pw);
  await tester.pump();
  await tester.tap(_signInButton);
}

Future<void> _signIn(WidgetTester tester, String email) async {
  await _typeAndSubmit(tester, email, _password);
  await _waitFor(
    tester,
    _profileButton,
    'shell after sign-in ($email)',
    timeout: const Duration(seconds: 90),
  );
  await _settle(tester, seconds: 8);
  final skip = find.text('Skip');
  if (skip.evaluate().isNotEmpty) {
    await tester.tap(skip.first);
    await _settle(tester);
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

Future<void> _closeAnySheet(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await _settle(tester, seconds: 1);
}

Future<void> _logOut(WidgetTester tester) async {
  await tester.tap(_profileButton.first);
  await _settle(tester, seconds: 1);
  await _waitFor(tester, find.text('Log out'), 'Log out menu item');
  await tester.tap(find.text('Log out').last);
  await _waitFor(
    tester,
    _signInButton,
    'auth screen after logout',
    timeout: const Duration(seconds: 60),
  );
  await _settle(tester, seconds: 3);
}

bool _navHas(String label) {
  final nav = find.bySemanticsLabel('Main navigation');
  final scope = nav.evaluate().isNotEmpty
      ? find.descendant(of: nav.first, matching: find.text(label))
      : find.text(label);
  return scope.evaluate().isNotEmpty;
}

List<String> _texts() => find
    .byType(Text)
    .evaluate()
    .map((e) => (e.widget as Text).data ?? '')
    .where((s) => s.trim().isNotEmpty)
    .toList();

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

Future<void> _settle(WidgetTester tester, {int seconds = 2}) =>
    _until(tester, () => false, seconds);

Future<void> _waitFor(
  WidgetTester tester,
  Finder f,
  String what, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  if (await _until(tester, () => f.evaluate().isNotEmpty, timeout.inSeconds)) {
    return;
  }
  await _shot(
    tester,
    'timeout-${what.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '-')}',
  );
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
