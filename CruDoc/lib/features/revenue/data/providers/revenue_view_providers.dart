import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_providers.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_builder.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_models.dart';

/// Streams the still-unpaid pending payments.
final pendingPaymentsProvider = StreamProvider<List<PendingPayment>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(revenueRepositoryProvider).watchPendingPayments();
});

/// What the Revenue screen is showing.
class RevenueViewState {
  const RevenueViewState({
    this.tab = RevenueTab.overview,
    this.period = RevenuePeriod.month,
    this.filter = TxnFilter.all,
    this.expanded = false,
  });

  final RevenueTab tab;
  final RevenuePeriod period;
  final TxnFilter filter;

  /// "See all transactions" is open.
  final bool expanded;

  RevenueViewState copyWith({
    RevenueTab? tab,
    RevenuePeriod? period,
    TxnFilter? filter,
    bool? expanded,
  }) =>
      RevenueViewState(
        tab: tab ?? this.tab,
        period: period ?? this.period,
        filter: filter ?? this.filter,
        expanded: expanded ?? this.expanded,
      );
}

class RevenueViewController extends Notifier<RevenueViewState> {
  RevenueViewController([this._initial = const RevenueViewState()]);

  final RevenueViewState _initial;

  @override
  RevenueViewState build() => _initial;

  void setTab(RevenueTab tab) => state = state.copyWith(tab: tab);

  void setPeriod(RevenuePeriod period) =>
      state = state.copyWith(period: period, expanded: false);

  void setFilter(TxnFilter filter) => state = state.copyWith(filter: filter);

  void toggleExpanded() => state = state.copyWith(expanded: !state.expanded);
}

final revenueViewControllerProvider =
    NotifierProvider<RevenueViewController, RevenueViewState>(
  () => RevenueViewController(),
);

/// The Overview's figures, or null while revenue entries load.
final revenueOverviewProvider = Provider<RevenueOverview?>((ref) {
  final async = ref.watch(recentRevenueEntriesProvider);
  final entries = async.hasError ? const <RevenueEntry>[] : async.value;
  if (entries == null) return null;
  final view = ref.watch(revenueViewControllerProvider);
  return RevenueBuilder.overview(
    entries: entries,
    period: view.period,
    filter: view.filter,
    now: ref.watch(dashboardNowProvider),
  );
});

/// Unpaid balances per patient, oldest first, or null while loading.
final revenuePendingProvider = Provider<List<PendingGroup>?>((ref) {
  final async = ref.watch(pendingPaymentsProvider);
  final pending = async.hasError ? const <PendingPayment>[] : async.value;
  if (pending == null) return null;
  final patients = ref.watch(patientsStreamProvider).value ?? const <Patient>[];
  return RevenueBuilder.pendingGroups(
    pending,
    patients,
    ref.watch(dashboardNowProvider),
  );
});
