import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/core/clinic/clinic_access.dart';
import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/theme/cru_theme.dart';
import 'package:doctor_management_app/features/onboarding/presentation/onboarding_flow.dart';

/// Signup: choosing Clinic asks whether the person is a doctor or a manager;
/// choosing Solo practice must look and behave exactly as it always has.
void main() {
  // The pre-sign-in mode (onAnswered set) needs no Firebase, which keeps
  // these widget tests self-contained.
  Future<OnboardingAnswers?> pumpFlow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    OnboardingAnswers? got;
    await tester.pumpWidget(
      MaterialApp(
        theme: CruTheme.day(),
        home: OnboardingFlow(onDone: () {}, onAnswered: (a) => got = a),
      ),
    );
    await tester.pumpAndSettle();
    return got;
  }

  Future<void> choose(WidgetTester tester, String practice) async {
    await tester.tap(find.text(practice));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }

  testWidgets('Solo practice shows nothing new on the About step', (tester) async {
    await pumpFlow(tester);
    await choose(tester, PracticeType.solo.label);
    expect(find.text('About you'), findsOneWidget);
    expect(find.text('Your role in the clinic'), findsNothing);
    expect(find.text('Clinic name'), findsNothing);
    expect(find.text("I'm a doctor here"), findsNothing);
    expect(find.text('Specialty'), findsOneWidget);
  });

  testWidgets('Clinic asks for the role and the clinic name, doctor first', (tester) async {
    await pumpFlow(tester);
    await choose(tester, PracticeType.clinic.label);
    expect(find.text('Your role in the clinic'), findsOneWidget);
    expect(find.text("I'm a doctor here"), findsOneWidget);
    expect(find.text('I manage the clinic'), findsOneWidget);
    expect(find.text('Clinic name'), findsOneWidget);
    expect(find.text('Specialty'), findsOneWidget,
        reason: 'a doctor-owner picks their own specialty');

    await tester.tap(find.text('I manage the clinic'));
    await tester.pumpAndSettle();
    expect(find.text('Clinic specialty'), findsOneWidget,
        reason: "a manager picks the clinic's specialty, not their own");
  });

  testWidgets("a manager's answers reach sign-up intact", (tester) async {
    OnboardingAnswers? got;
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: CruTheme.day(),
        home: OnboardingFlow(onDone: () {}, onAnswered: (a) => got = a),
      ),
    );
    await tester.pumpAndSettle();
    await choose(tester, PracticeType.clinic.label);

    await tester.tap(find.text('I manage the clinic'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Sunrise Dental').first,
      'Sunrise Dental',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Priya Sharma').first,
      'Priya Nair',
    );
    await tester.tap(find.text('Dentist').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use what we suggest'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(got, isNotNull);
    expect(got!.practice, PracticeType.clinic);
    expect(got!.ownerIsDoctor, isFalse);
    expect(got!.clinicName, 'Sunrise Dental');
    expect(got!.name, 'Priya Nair');
  });

  test('answers default to a doctor-owner, as every owner was before', () {
    const a = OnboardingAnswers(
      practice: PracticeType.solo,
      name: 'Dr A',
      specialty: DoctorSpecialtyType.dentist,
      suggest: true,
      picked: {},
    );
    expect(a.ownerIsDoctor, isTrue);
    expect(a.clinicName, '');
  });

  group('ClinicAccess.owner', () {
    test('a doctor-owner (and every solo doctor) keeps everything', () {
      final a = ClinicAccess.owner('u1');
      expect(a.perms, ClinicPermission.values.toSet());
      expect(a.kind, MemberKind.doctor);
    });

    test('a manager-owner runs the clinic without medical records', () {
      final a = ClinicAccess.owner('u1', clinical: false);
      expect(a.isOwner, isTrue);
      expect(a.kind, MemberKind.staff);
      expect(a.can(ClinicPermission.clinicalView), isFalse);
      expect(a.can(ClinicPermission.clinicalEdit), isFalse);
      for (final p in [
        ClinicPermission.team,
        ClinicPermission.settings,
        ClinicPermission.billing,
        ClinicPermission.revenue,
        ClinicPermission.patientsView,
        ClinicPermission.patientsEdit,
      ]) {
        expect(a.can(p), isTrue, reason: '$p');
      }
      expect(a.allowsModule('patients'), isTrue);
    });

    test("a manager-owner's restriction survives the offline cache", () {
      final a = ClinicAccess.fromJson(
        ClinicAccess.owner('u1', clinical: false).toJson(),
      );
      expect(a.can(ClinicPermission.clinicalView), isFalse);
      expect(a.can(ClinicPermission.team), isTrue);
    });
  });
}
