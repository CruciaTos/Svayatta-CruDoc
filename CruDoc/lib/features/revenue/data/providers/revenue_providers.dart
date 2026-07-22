import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/repo/revenue_repo.dart';

/// Shared Riverpod providers for revenue data — mirrors the shape of
/// patients/data/providers/patient_providers.dart and
/// inventory/data/providers/inventory_providers.dart.
///
/// [RevenueScreen] currently talks to [RevenueRepository] directly via a
/// raw `StreamBuilder` rather than through Riverpod — this file doesn't
/// change that. It only adds the provider the dashboard's "Recent
/// Activity" card needs, following the same pattern as every other
/// feature's providers.
final revenueRepositoryProvider = Provider<RevenueRepository>(
  (ref) => RevenueRepository(),
);

/// Streams active, non-deleted revenue entries (income and expense).
/// Feeds the dashboard's "Recent Activity" card.
final recentRevenueEntriesProvider = StreamProvider<List<RevenueEntry>>(
  (ref) => ref.watch(revenueRepositoryProvider).watchRevenueEntries(),
);
