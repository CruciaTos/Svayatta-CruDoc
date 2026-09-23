import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/providers/specialty_provider.dart';

import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/core/services/google_places_service.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/core/services/device_location_service.dart';

/// "Now" for the Appointments screens: the dashboard clock (tests
/// override `dashboardNowProvider`).
final apptsNowProvider = Provider<DateTime>(
  (ref) => ref.watch(dashboardNowProvider),
);

/// Every non-cancelled visit as a calendar item, built only from the
/// existing repository streams. Uses today's raw queue
/// (`todaysQueueProvider`), not the Queue screen's filtered provider.
final apptItemsProvider = Provider<AsyncValue<List<ApptItem>>>((ref) {
  final visits = ref.watch(allVisitsProvider);
  final patients = ref.watch(patientsStreamProvider);
  final queue = ref.watch(todaysQueueProvider);
  final now = ref.watch(apptsNowProvider);
  if (visits.hasError) {
    return AsyncValue.error(visits.error!, visits.stackTrace!);
  }
  final v = visits.value;
  final p = patients.value ?? (patients.hasError ? const [] : null);
  if (v == null || p == null) return const AsyncValue.loading();
  return AsyncValue.data(
    ApptsBuilder.items(
      visits: v,
      patients: p,
      todaysQueue: queue.value ?? const [],
      now: now,
    ),
  );
});

/// One day's items, sorted by start. Key is a date-only DateTime.
final apptDayItemsProvider =
    Provider.family<AsyncValue<List<ApptItem>>, DateTime>((ref, day) {
      return ref
          .watch(apptItemsProvider)
          .whenData((all) => ApptsBuilder.forDay(all, day));
    });

/// One day's overlap groups (every item is in exactly one group).
final apptDayGroupsProvider =
    Provider.family<AsyncValue<List<OverlapGroup>>, DateTime>((ref, day) {
      final now = ref.watch(apptsNowProvider);
      return ref
          .watch(apptDayItemsProvider(day))
          .whenData((items) => ApptsBuilder.groups(items, now));
    });

/// One day's counts.
final apptDayCountsProvider =
    Provider.family<AsyncValue<ApptDayCounts>, DateTime>((ref, day) {
      final now = ref.watch(apptsNowProvider);
      return ref
          .watch(apptDayItemsProvider(day))
          .whenData((items) => ApptsBuilder.counts(items, day, now));
    });

/// What the user is looking at. Kept for the session.
class ApptsState {
  const ApptsState({
    required this.view,
    required this.anchor,
    this.selectedVisitId,
    this.selectedGroupStart,
    this.monthSelected,
  });

  final ApptsView view;

  /// The date the current view is built around (date only).
  final DateTime anchor;

  /// Day view: the selected block.
  final String? selectedVisitId;

  /// Day view: set when a block in an unsorted overlap was clicked; the
  /// whole group (identified by its start) is selected.
  final DateTime? selectedGroupStart;

  /// Month view: the selected tile (date only). Null = tomorrow.
  final DateTime? monthSelected;

  ApptsState copyWith({
    ApptsView? view,
    DateTime? anchor,
    String? selectedVisitId,
    bool clearSelection = false,
    DateTime? selectedGroupStart,
    bool clearGroup = false,
    DateTime? monthSelected,
  }) {
    return ApptsState(
      view: view ?? this.view,
      anchor: anchor ?? this.anchor,
      selectedVisitId: clearSelection
          ? null
          : (selectedVisitId ?? this.selectedVisitId),
      selectedGroupStart: clearSelection || clearGroup
          ? null
          : (selectedGroupStart ?? this.selectedGroupStart),
      monthSelected: monthSelected ?? this.monthSelected,
    );
  }
}

class ApptsController extends Notifier<ApptsState> {
  @override
  ApptsState build() => ApptsState(
    view: ApptsView.live,
    anchor: ApptsBuilder.dateOnly(ref.read(apptsNowProvider)),
  );

  void setView(ApptsView view) => state = state.copyWith(view: view);

  /// ← / → : one day, week or month.
  void step(int delta) {
    if (state.view == ApptsView.live) {
      // Live is today; ‹ › open the calendar on the day before or after.
      final today = ApptsBuilder.dateOnly(ref.read(apptsNowProvider));
      state = ApptsState(
        view: ApptsView.day,
        anchor: DateTime(today.year, today.month, today.day + delta),
        monthSelected: state.monthSelected,
      );
      return;
    }
    final a = state.anchor;
    final next = switch (state.view) {
      ApptsView.live ||
      ApptsView.day ||
      ApptsView.agenda ||
      ApptsView.visits => DateTime(a.year, a.month, a.day + delta),
      ApptsView.week => DateTime(a.year, a.month, a.day + 7 * delta),
      ApptsView.month => DateTime(a.year, a.month + delta, 1),
    };
    state = state.copyWith(anchor: next, clearSelection: true);
  }

  /// T : jump to today.
  void today() {
    state = state.copyWith(
      anchor: ApptsBuilder.dateOnly(ref.read(apptsNowProvider)),
      clearSelection: true,
    );
  }

  /// Opens the Day view on [date], optionally selecting [visitId].
  void openDay(DateTime date, {String? visitId}) {
    state = ApptsState(
      view: ApptsView.day,
      anchor: ApptsBuilder.dateOnly(date),
      selectedVisitId: visitId,
      monthSelected: state.monthSelected,
    );
  }

  /// Day view: select one block (clears any group selection).
  void select(String? visitId) {
    state = visitId == null
        ? state.copyWith(clearSelection: true)
        : state.copyWith(selectedVisitId: visitId, clearGroup: true);
  }

  /// Day view: select a whole unsorted overlap group.
  void selectGroup(OverlapGroup group) {
    state = state.copyWith(
      selectedVisitId: group.items.first.id,
      selectedGroupStart: group.start,
    );
  }

  /// Month view: select a tile.
  void selectMonthDay(DateTime date) =>
      state = state.copyWith(monthSelected: ApptsBuilder.dateOnly(date));

  /// Jump to any date (mini calendar, search).
  void goTo(DateTime date) => state = state.copyWith(
    anchor: ApptsBuilder.dateOnly(date),
    clearSelection: true,
  );
}

final apptsControllerProvider = NotifierProvider<ApptsController, ApptsState>(
  ApptsController.new,
);

/// The view actually shown: Live needs the queue module and the calendar
/// views need appointments, so fall back when one is switched off.
final effectiveApptsViewProvider = Provider<ApptsView>((ref) {
  final view = ref.watch(apptsControllerProvider.select((s) => s.view));
  final queueOn = ref.watch(isQueueFeatureEnabledProvider);
  final apptsOn = ref.watch(isAppointmentsFeatureEnabledProvider);
  if (view == ApptsView.visits && !ref.watch(isPhysiotherapyProvider)) {
    return ApptsView.day;
  }
  if (view == ApptsView.live && !queueOn) return ApptsView.day;
  if (view != ApptsView.live && !apptsOn && queueOn) return ApptsView.live;
  return view;
});

/// The other patients booked with a visit (same group), for "Seen with
/// Priya Verma" in a patient's history. Empty for a single visit.
final visitGroupNamesProvider =
    Provider.family<List<String>, ({String groupId, String visitId})>((
      ref,
      key,
    ) {
      final visits = ref.watch(allVisitsProvider).value ?? const [];
      final patients = ref.watch(patientsStreamProvider).value ?? const [];
      final byId = {for (final p in patients) p.id: p};
      return [
        for (final v in visits)
          if (v.groupId == key.groupId &&
              v.id != key.visitId &&
              !v.isDeleted &&
              v.status != VisitStatus.cancelled)
            byId[v.patientId]?.fullName.trim() ?? 'Patient',
      ];
    });

/// Where the clinic is, from its address in Settings. Address search
/// measures from here when this device's location isn't available. Null
/// without a clinic address or a Maps key.
final clinicLocationProvider =
    FutureProvider<({double latitude, double longitude})?>((ref) async {
      final profile = ref.watch(doctorProfileProvider).value;
      final address = (profile?['clinicAddress'] as String?)?.trim() ?? '';
      if (address.isEmpty) return null;
      return GooglePlacesService.instance.geocode(address);
    });

/// This device's live position (GPS on phones, Windows location on a
/// laptop). Null when location is off or refused.
final deviceLocationProvider =
    FutureProvider.autoDispose<({double latitude, double longitude})?>(
      (ref) => DeviceLocationService.instance.current(),
    );

/// A point address search measures distance from, and whether it is where
/// the doctor is now ([fromYou]) or the clinic.
typedef SearchOrigin = ({double latitude, double longitude, bool fromYou});

/// Where address suggestions are ordered from: where the doctor is now,
/// else the clinic. Null when neither is known.
final addressSearchOriginProvider = FutureProvider.autoDispose<SearchOrigin?>((
  ref,
) async {
  final hereSoon = ref.watch(deviceLocationProvider.future);
  final clinicSoon = ref.watch(clinicLocationProvider.future);
  final here = await hereSoon;
  if (here != null) {
    return (latitude: here.latitude, longitude: here.longitude, fromYou: true);
  }
  final clinic = await clinicSoon;
  if (clinic == null) return null;
  return (
    latitude: clinic.latitude,
    longitude: clinic.longitude,
    fromYou: false,
  );
});

/// The search origin for a search starting now. Waits briefly for a first
/// fix, so a slow one never holds up the suggestions.
Future<({double latitude, double longitude})?> searchOriginNow(
  WidgetRef ref,
) async {
  try {
    final origin = await ref
        .read(addressSearchOriginProvider.future)
        .timeout(const Duration(seconds: 2));
    if (origin == null) return null;
    return (latitude: origin.latitude, longitude: origin.longitude);
  } catch (_) {
    return null;
  }
}
