// Golden images of the Appointments Week and Month views next to
// design/clinic-redesign/screens/appointments-3-week.png (1440x860) and
// appointments-4-month.png (1440x776).
//
// Uses the fixture clinic in appointments_week_fixtures.dart (September
// 2026, now Wednesday 23 September 11:48) and the bundled Geist font.
// Differences from the mock-ups are GAPs: no closed days, no break band,
// no capacity bars, "N open" counts or legend. Saturday 26 carries one
// unsorted overlap so the split column and amber dots are covered.
// Regenerate with:
//   flutter test --update-goldens --tags golden test/appointments/appointments_week_month_golden_test.dart
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';

import '../patients/patients_fixtures.dart' show loadGeist;
import 'appointments_harness.dart' show pumpAppointments;
import 'appointments_week_fixtures.dart';

void main() {
  setUpAll(loadGeist);

  testWidgets('Week, 1440 x 860', (tester) async {
    await pumpAppointments(
      tester,
      visits: weekVisits,
      patients: weekPatients,
      queue: weekQueue,
      now: weekNow,
      view: ApptsView.week,
      anchor: DateTime(2026, 9, 23),
      size: const Size(1440, 860),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/appointments_3_week.png'),
    );
  });

  testWidgets('Month, 1440 x 776', (tester) async {
    await pumpAppointments(
      tester,
      visits: weekVisits,
      patients: weekPatients,
      queue: weekQueue,
      now: weekNow,
      view: ApptsView.month,
      anchor: DateTime(2026, 9, 23),
      monthSelected: DateTime(2026, 9, 24),
      size: const Size(1440, 776),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/appointments_4_month.png'),
    );
  });
}
