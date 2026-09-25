import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_builder.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_models.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_providers.dart';

/// Ticks every 30 s so waiting times, the greeting and Auto appearance
/// stay current without new data arriving.
final dashboardClockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now());
});

/// The dashboard's notion of "now". Tests override this.
final dashboardNowProvider = Provider<DateTime>(
  (ref) => ref.watch(dashboardClockProvider).value ?? DateTime.now(),
);

/// Everything on the dashboard, derived only from existing repository
/// providers — no SQLite or Firestore access here.
///
/// Uses today's raw queue (`todaysQueueProvider`) rather than the Queue
/// screen's `periodQueueWithPatientsProvider`, which follows that
/// screen's filters and checks visits into the queue as a side effect.
final dashboardDataProvider = Provider<DashboardData>((ref) {
  return buildDashboard(
    now: ref.watch(dashboardNowProvider),
    queue: ref.watch(todaysQueueProvider).value,
    visits: ref.watch(allVisitsProvider).value,
    patients: ref.watch(patientsStreamProvider).value,
    revenue: ref.watch(recentRevenueEntriesProvider).value,
    medicines: ref.watch(medicinesStreamProvider).value,
  );
});

/// Waiting count for the sidebar's Queue item.
final waitingNowCountProvider = Provider<int>(
  (ref) => ref.watch(dashboardDataProvider).glance?.waiting ?? 0,
);
