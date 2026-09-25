// Golden images of the Appointments Day view next to
// design/clinic-redesign/screens/appointments-1-day.png and
// appointments-2-day-overlap.png.
//
// Rendered 1440 wide at 1.5x with fake providers
// (test/appointments/appointments_fixtures.dart) and the bundled Geist
// font. Taller than the mock-ups: working hours aren't stored, so the
// grid is one continuous 9 AM to 7 PM range with no break band.
// Regenerate with:
//   flutter test --update-goldens --tags golden test/appointments
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';

import '../patients/patients_fixtures.dart' show loadGeist;
import 'appointments_fixtures.dart';
import 'appointments_harness.dart';

const Size _size = Size(1440, 1180);

void main() {
  setUpAll(loadGeist);

  testWidgets('Day, Kavya Iyer waiting and selected', (tester) async {
    await pumpAppointments(
      tester,
      visits: apptsVisits,
      patients: apptsPatients,
      queue: apptsQueue,
      now: apptsNow,
      size: _size,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/appointments_1_day.png'),
    );
  });

  testWidgets('Day, overlap at 12:30 PM selected', (tester) async {
    await pumpAppointments(
      tester,
      visits: apptsOverlapVisits,
      patients: apptsPatients,
      queue: apptsQueue,
      now: apptsNow,
      size: _size,
    );
    final container = appointmentsContainer(tester);
    final group = container
        .read(apptDayGroupsProvider(apptsDay))
        .requireValue
        .firstWhere((g) => g.isOverlap && g.items.any((i) => i.id == 'v_neha'));
    container.read(apptsControllerProvider.notifier).selectGroup(group);
    await settleAppointments(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/appointments_2_day_overlap.png'),
    );
  });
}
