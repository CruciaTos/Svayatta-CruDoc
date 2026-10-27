import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/appointments_screen.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';

import '../patients/patients_fixtures.dart' show loadGeist;
import 'appointments_fixtures.dart';
import 'appointments_harness.dart';

void main() {
  setUpAll(loadGeist);
  group('Schedule views', () {
    test('availableApptsViewsProvider respects feature toggles', () {
      final container = ProviderContainer(
        overrides: [
          isQueueFeatureEnabledProvider.overrideWithValue(true),
          isAppointmentsFeatureEnabledProvider.overrideWithValue(true),
          isPhysiotherapyProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);

      final views = container.read(availableApptsViewsProvider);
      expect(views, [
        ApptsView.live,
        ApptsView.week,
        ApptsView.month,
        ApptsView.agenda,
        ApptsView.visits,
      ]);
    });
  });

  group('Schedule horizontal swipe widget tests', () {
    testWidgets('Day swipes as Week: one page, remembered', (tester) async {
      await pumpAppointments(
        tester,
        visits: apptsVisits,
        patients: apptsPatients,
        queue: apptsQueue,
        now: apptsNow,
        view: ApptsView.day,
      );

      final container = appointmentsContainer(tester);
      ApptsView view() => container.read(apptsControllerProvider).view;
      Future<void> swipe(double dx) async {
        await tester.fling(
          find.byType(AppointmentsScreen),
          Offset(dx, 0),
          1000,
        );
        await tester.pumpAndSettle();
      }

      expect(view(), ApptsView.day);

      // Day sits on Week's page, so the next page is Month.
      await swipe(-400);
      expect(view(), ApptsView.month);

      await swipe(-400);
      expect(view(), ApptsView.agenda);

      await swipe(400);
      expect(view(), ApptsView.month);

      // Back onto Week's page: it still shows the day.
      await swipe(400);
      expect(view(), ApptsView.day);

      // From Week itself, the next page is Month too.
      container.read(apptsControllerProvider.notifier).setView(ApptsView.week);
      await tester.pumpAndSettle();
      await swipe(-400);
      expect(view(), ApptsView.month);
    });
  });
}
