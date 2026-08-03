import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/repo/revenue_repo.dart';

final revenueRepositoryProvider = Provider<RevenueRepository>(
  (ref) => RevenueRepository(),
);

/// Streams active, non-deleted revenue entries (income and expense).
/// Feeds the dashboard's "Recent Activity" card.
final recentRevenueEntriesProvider = StreamProvider<List<RevenueEntry>>(
  (ref) {
    ref.watch(authStateProvider);
    return ref.watch(revenueRepositoryProvider).watchRevenueEntries();
  },
);
