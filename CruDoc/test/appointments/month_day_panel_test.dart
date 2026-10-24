import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/month/appt_time_label.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/month/month_day_panel.dart';
import 'package:doctor_management_app/features/mobile/activity/visit_badge.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

void main() {
  final testPatient = Patient(
    id: 'p1',
    firstName: 'Covid-19',
    lastName: 'Patient',
    phone: '1234567890',
    gender: 'Other',
    dateOfBirth: DateTime(1990, 1, 1),
    diagnosis: const [],
    packageBalance: 0,
    isArchived: false,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  final now = DateTime(2026, 10, 24, 2, 0);

  final clinicVisit = Visit(
    id: 'v_clinic',
    patientId: 'p1',
    scheduledStart: DateTime(2026, 10, 24, 3, 0),
    durationMinutes: 30,
    address: '',
    visitType: VisitType.clinic,
    status: VisitStatus.scheduled,
    treatmentType: 'General consultation',
    createdAt: now,
    updatedAt: now,
  );

  final homeVisit = Visit(
    id: 'v_home',
    patientId: 'p1',
    scheduledStart: DateTime(2026, 10, 24, 10, 0),
    durationMinutes: 45,
    address: 'Dahisar East',
    visitType: VisitType.home,
    status: VisitStatus.scheduled,
    treatmentType: 'Follow-up',
    createdAt: now,
    updatedAt: now,
  );

  final clinicItem = ApptsBuilder.items(
    visits: [clinicVisit],
    patients: [testPatient],
    todaysQueue: const [],
    now: DateTime(2026, 10, 24, 2, 0),
  ).first;

  final homeItem = ApptsBuilder.items(
    visits: [homeVisit],
    patients: [testPatient],
    todaysQueue: const [],
    now: DateTime(2026, 10, 24, 2, 0),
  ).first;

  group('MonthPanelRow Layout & Indicators', () {
    testWidgets('clinic appointment has VisitBadged(homeVisit: false) and right-aligned time', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 384,
                child: MonthPanelRow(
                  item: clinicItem,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check avatar with VisitBadged
      final badgedFinder = find.byType(VisitBadged);
      expect(badgedFinder, findsOneWidget);
      final badgedWidget = tester.widget<VisitBadged>(badgedFinder);
      expect(badgedWidget.homeVisit, isFalse, reason: 'Clinic appointment should have homeVisit = false (blue calendar)');

      // Verify no visit pill text exists
      expect(find.text('Visit'), findsNothing);

      // Verify time label is on extreme right (x > name x)
      final nameFinder = find.text(clinicItem.name);
      final timeFinder = find.byType(ApptTimeLabel);
      expect(nameFinder, findsOneWidget);
      expect(timeFinder, findsOneWidget);

      final nameTopLeft = tester.getTopLeft(nameFinder);
      final timeTopLeft = tester.getTopLeft(timeFinder);
      expect(timeTopLeft.dx, greaterThan(nameTopLeft.dx));
    });

    testWidgets('home visit has VisitBadged(homeVisit: true) and no visit pill', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 384,
                child: MonthPanelRow(
                  item: homeItem,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final badgedFinder = find.byType(VisitBadged);
      expect(badgedFinder, findsOneWidget);
      final badgedWidget = tester.widget<VisitBadged>(badgedFinder);
      expect(badgedWidget.homeVisit, isTrue, reason: 'Home visit should have homeVisit = true (green house)');

      // Verify no visit pill is present
      expect(find.text('Visit'), findsNothing);

      // Verify time label is on extreme right
      final nameTopLeft = tester.getTopLeft(find.text(homeItem.name));
      final timeTopLeft = tester.getTopLeft(find.byType(ApptTimeLabel));
      expect(timeTopLeft.dx, greaterThan(nameTopLeft.dx));
    });
  });
}
