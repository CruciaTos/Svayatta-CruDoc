import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';

/// Rows are revealed in pages as the list scrolls ("Showing N of M").
const int kPatientsPageSize = 50;

/// While the clinic has fewer patients than this, the list hides the
/// filter chips and shows the "Bring your existing patients" panel.
const int kFirstWeekThreshold = 10;

/// Every patient's summary, built only from existing repository streams
/// (patients + all visits). Null while either stream is loading.
final patientSummariesProvider = Provider<AsyncValue<List<PatientSummary>>>((
  ref,
) {
  final patients = ref.watch(patientsStreamProvider);
  final visits = ref.watch(allVisitsProvider);
  final now = ref.watch(dashboardNowProvider);
  if (patients.hasError) {
    return AsyncValue.error(patients.error!, patients.stackTrace!);
  }
  final p = patients.value;
  final v = visits.value ?? (visits.hasError ? const [] : null);
  if (p == null || v == null) return const AsyncValue.loading();
  return AsyncValue.data(
    PatientsBuilder.summaries(patients: p, visits: v, now: now),
  );
});

/// One patient's summary (details screen, preview pane).
final patientSummaryProvider =
    Provider.family<AsyncValue<PatientSummary?>, String>((ref, id) {
  return ref.watch(patientSummariesProvider).whenData((all) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  });
});

/// What the user has done on the Patients list. Kept for the session so
/// coming back from Patient details (or another tab) restores it.
class PatientsListState {
  const PatientsListState({
    this.filter = PatientFilter.all,
    this.sort = PatientSort.lastVisit,
    this.query = '',
    this.selectedId,
    this.paneOpen = const {},
    this.scrollOffset = 0,
    this.limit = kPatientsPageSize,
    this.detailsId,
  });

  final PatientFilter filter;
  final PatientSort sort;
  final String query;

  /// The row shown in the preview pane (split mode).
  final String? selectedId;

  /// Per filter: was the pane left open or closed this session.
  final Map<PatientFilter, bool> paneOpen;
  final double scrollOffset;

  /// Rows revealed so far.
  final int limit;

  /// Patient details open in place of the list.
  final String? detailsId;

  /// Work-through filters open with the pane; others start in table mode.
  bool get isPaneOpen => paneOpen[filter] ?? filter.workThrough;

  PatientsListState copyWith({
    PatientFilter? filter,
    PatientSort? sort,
    String? query,
    String? Function()? selectedId,
    Map<PatientFilter, bool>? paneOpen,
    double? scrollOffset,
    int? limit,
    String? Function()? detailsId,
  }) =>
      PatientsListState(
        filter: filter ?? this.filter,
        sort: sort ?? this.sort,
        query: query ?? this.query,
        selectedId: selectedId != null ? selectedId() : this.selectedId,
        paneOpen: paneOpen ?? this.paneOpen,
        scrollOffset: scrollOffset ?? this.scrollOffset,
        limit: limit ?? this.limit,
        detailsId: detailsId != null ? detailsId() : this.detailsId,
      );
}

class PatientsListController extends Notifier<PatientsListState> {
  @override
  PatientsListState build() => const PatientsListState();

  void setFilter(PatientFilter f) {
    if (f == state.filter) return;
    final keepSort = !state.filter.workThrough && !f.workThrough;
    state = state.copyWith(
      filter: f,
      sort: keepSort ? state.sort : PatientsBuilder.defaultSort(f),
      selectedId: () => null,
      scrollOffset: 0,
      limit: kPatientsPageSize,
    );
  }

  void setSort(PatientSort s) =>
      state = state.copyWith(sort: s, scrollOffset: 0);

  void setQuery(String q) {
    if (q == state.query) return;
    state = state.copyWith(query: q, scrollOffset: 0, limit: kPatientsPageSize);
  }

  /// Selects a row and opens the pane (split mode).
  void select(String id) => state = state.copyWith(
        selectedId: () => id,
        paneOpen: {...state.paneOpen, state.filter: true},
      );

  /// × or Esc: back to table mode, remembered for this filter.
  void closePane() => state = state.copyWith(
        selectedId: () => null,
        paneOpen: {...state.paneOpen, state.filter: false},
      );

  void showMore() =>
      state = state.copyWith(limit: state.limit + kPatientsPageSize);

  void saveScroll(double offset) => state = state.copyWith(scrollOffset: offset);

  void openDetails(String id) => state = state.copyWith(detailsId: () => id);

  void closeDetails() => state = state.copyWith(detailsId: () => null);
}

final patientsListControllerProvider =
    NotifierProvider<PatientsListController, PatientsListState>(
  PatientsListController.new,
);

/// Everything the Patients list renders for the current state.
class PatientsListView {
  const PatientsListView({
    required this.total,
    required this.newThisMonth,
    required this.counts,
    required this.rows,
    required this.visible,
    required this.groups,
    required this.selected,
    required this.balanceStrip,
    required this.followUpStrip,
    required this.firstWeek,
  });

  /// All patients in the clinic.
  final int total;
  final int newThisMonth;
  final Map<PatientFilter, int> counts;

  /// Filtered, searched and sorted (all pages).
  final List<PatientSummary> rows;

  /// The revealed page of [rows].
  final List<PatientSummary> visible;

  /// [visible] split into groups.
  final List<PatientGroup> groups;

  /// The patient in the preview pane; null in table mode.
  final PatientSummary? selected;
  final BalanceStripData? balanceStrip;
  final FollowUpStripData? followUpStrip;

  /// Fewer than [kFirstWeekThreshold] patients: no chips, import panel.
  final bool firstWeek;

  bool get split => selected != null;
}

final patientsListViewProvider = Provider<AsyncValue<PatientsListView>>((ref) {
  final state = ref.watch(patientsListControllerProvider);
  final now = ref.watch(dashboardNowProvider);
  return ref.watch(patientSummariesProvider).whenData((all) {
    final counts = PatientsBuilder.counts(all);
    final firstWeek = all.length < kFirstWeekThreshold;
    // A chip with no patients is hidden, so its filter can't stay active.
    final filter = firstWeek ||
            (state.filter != PatientFilter.all && counts[state.filter] == 0)
        ? PatientFilter.all
        : state.filter;
    final sort = filter == state.filter ? state.sort : PatientSort.lastVisit;
    final rows = PatientsBuilder.apply(
      all,
      filter: filter,
      sort: sort,
      query: state.query,
    );
    final visible = rows.take(state.limit).toList();

    PatientSummary? selected;
    if (filter == state.filter && state.isPaneOpen && rows.isNotEmpty) {
      selected = rows.firstWhere(
        (s) => s.id == state.selectedId,
        orElse: () => rows.first,
      );
    }

    return PatientsListView(
      total: all.length,
      newThisMonth: counts[PatientFilter.newThisMonth] ?? 0,
      counts: counts,
      rows: rows,
      visible: visible,
      groups: PatientsBuilder.group(visible, sort),
      selected: selected,
      balanceStrip: filter == PatientFilter.balanceDue
          ? PatientsBuilder.balanceStrip(rows)
          : null,
      followUpStrip: filter == PatientFilter.followUpOverdue
          ? PatientsBuilder.followUpStrip(rows, now)
          : null,
      firstWeek: firstWeek,
    );
  });
});
