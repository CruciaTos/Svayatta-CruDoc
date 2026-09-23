import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/inventory/data/inventory_view_preferences.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_builder.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_models.dart';

/// Stock movements of every active item, by medicine id. Reloads when
/// the items change or a new movement is recorded. Tests override it.
final stockHistoryProvider =
    FutureProvider<Map<String, List<StockTransactionModel>>>((ref) async {
  // Watched before the first await so both keep this provider fresh.
  final medicinesFuture = ref.watch(medicinesStreamProvider.future);
  ref.watch(recentStockTransactionsProvider);
  final repository = ref.watch(inventoryRepositoryProvider);

  final medicines = await medicinesFuture;
  final entries = await Future.wait([
    for (final m in medicines)
      if (m.isActive)
        repository
            .getTransactionsForMedicine(m.id)
            .then((t) => MapEntry(m.id, t))
            // One unreadable history must not blank the whole screen.
            .catchError(
              (Object _) => MapEntry(m.id, const <StockTransactionModel>[]),
            ),
  ]);
  return Map.fromEntries(entries);
});

final inventoryViewPreferencesProvider = Provider<InventoryViewPreferences>(
  (ref) => InventoryViewPreferences(),
);

/// What the doctor has chosen on the Inventory screen.
@immutable
class InventoryState {
  const InventoryState({
    this.tab = InventoryTab.items,
    this.filter = InventoryFilter.all,
    this.sort = InventorySort.runsOut,
    this.query = '',
    this.selectedId,
    this.panelOpen = false,
    this.viewMode = InventoryViewMode.list,
    this.limit = InventoryBuilder.pageSize,
  });

  final InventoryTab tab;
  final InventoryFilter filter;
  final InventorySort sort;
  final String query;

  /// Null: the panel shows the first item in the current sort.
  final String? selectedId;

  /// Below 1200 px the panel is a sheet, open only after a selection.
  final bool panelOpen;

  final InventoryViewMode viewMode;

  /// Rows revealed so far.
  final int limit;

  InventoryState copyWith({
    InventoryTab? tab,
    InventoryFilter? filter,
    InventorySort? sort,
    String? query,
    String? selectedId,
    bool clearSelected = false,
    bool? panelOpen,
    InventoryViewMode? viewMode,
    int? limit,
  }) =>
      InventoryState(
        tab: tab ?? this.tab,
        filter: filter ?? this.filter,
        sort: sort ?? this.sort,
        query: query ?? this.query,
        selectedId: clearSelected ? null : (selectedId ?? this.selectedId),
        panelOpen: panelOpen ?? this.panelOpen,
        viewMode: viewMode ?? this.viewMode,
        limit: limit ?? this.limit,
      );
}

class InventoryController extends Notifier<InventoryState> {
  /// [initial] skips loading the stored view mode (tests).
  InventoryController({this.initial});

  final InventoryState? initial;

  @override
  InventoryState build() {
    if (initial != null) return initial!;
    Future(() async {
      final stored =
          await ref.read(inventoryViewPreferencesProvider).getViewMode();
      if (ref.mounted && stored != state.viewMode) {
        state = state.copyWith(viewMode: stored);
      }
    });
    return const InventoryState();
  }

  void setTab(InventoryTab tab) => state = state.copyWith(tab: tab);

  void setFilter(InventoryFilter filter) => state = state.copyWith(
        filter: filter,
        limit: InventoryBuilder.pageSize,
        clearSelected: true,
        panelOpen: false,
      );

  void setSort(InventorySort sort) => state = state.copyWith(
        sort: sort,
        limit: InventoryBuilder.pageSize,
      );

  void setQuery(String query) {
    if (query == state.query) return;
    state = state.copyWith(
      query: query,
      limit: InventoryBuilder.pageSize,
      clearSelected: true,
      panelOpen: false,
    );
  }

  void select(String id) =>
      state = state.copyWith(selectedId: id, panelOpen: true);

  void closePanel() => state = state.copyWith(panelOpen: false);

  void showMore() =>
      state = state.copyWith(limit: state.limit + InventoryBuilder.pageSize);

  Future<void> setViewMode(InventoryViewMode mode) async {
    if (mode == state.viewMode) return;
    state = state.copyWith(viewMode: mode);
    await ref.read(inventoryViewPreferencesProvider).setViewMode(mode);
  }
}

final inventoryControllerProvider =
    NotifierProvider<InventoryController, InventoryState>(
  InventoryController.new,
);

/// Everything the Items section shows. Loading until the items and their
/// movements arrive; an unreadable movement history counts as none.
final inventoryViewProvider = Provider<AsyncValue<InventoryView>>((ref) {
  final medicines = ref.watch(medicinesStreamProvider);
  final history = ref.watch(stockHistoryProvider);
  final s = ref.watch(inventoryControllerProvider);
  final now = ref.watch(dashboardNowProvider);

  final list = medicines.value;
  if (list == null) {
    if (medicines.hasError) {
      return AsyncError(
        medicines.error!,
        medicines.stackTrace ?? StackTrace.current,
      );
    }
    return const AsyncLoading();
  }
  final movements = history.value;
  if (movements == null && !history.hasError) return const AsyncLoading();

  return AsyncData(
    InventoryBuilder.view(
      medicines: list,
      history: movements ?? const {},
      now: now,
      filter: s.filter,
      sort: s.sort,
      query: s.query,
      selectedId: s.selectedId,
      limit: s.limit,
    ),
  );
});
