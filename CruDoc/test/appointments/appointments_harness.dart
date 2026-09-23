// Test-only: renders the desktop shell layout with the Appointments tab,
// the same way DesktopShell does, but with fake providers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/appointments_screen.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/homeopathy/data/providers/homeopathy_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/shell/components/cru_sidebar.dart';
import 'package:doctor_management_app/features/shell/presentation/desktop_shell_layout.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import '../patients/patients_fixtures.dart'
    show fixtureIdentity, fixturePlan, specialtyOf;
import 'appointments_fixtures.dart';

void _noop() {}

final _callbacks = SidebarCallbacks(
  onNavigate: (_) {},
  onClinicSwitcher: _noop,
  onUpgrade: _noop,
  onSettings: _noop,
  onHelp: _noop,
  onLogout: _noop,
  onToggleCollapsed: _noop,
);

/// Starts the screen on a given state instead of today's Day view.
class _FixedApptsController extends ApptsController {
  _FixedApptsController(this._initial);

  final ApptsState _initial;

  @override
  ApptsState build() => _initial;
}

/// Every provider the Appointments screen and the sidebar read.
List<Override> apptsOverrides({
  required List<Visit> visits,
  required List<Patient> patients,
  required List<QueueEntry> queue,
  required DateTime now,
  required ApptsState initial,
}) {
  final waiting = queue.where((q) => q.status == QueueStatus.waiting).length;
  return [
    dashboardNowProvider.overrideWithValue(now),
    allVisitsProvider.overrideWith((ref) => Stream.value(visits)),
    patientsStreamProvider.overrideWith((ref) => Stream.value(patients)),
    todaysQueueProvider.overrideWith((ref) => Stream.value(queue)),
    // The Live view (queue board) reads every token.
    allQueueProvider.overrideWith((ref) => Stream.value(queue)),
    homeopathyCaseSheetProvider.overrideWith(
      (ref, patientId) => Stream.value(apptsCaseSheets[patientId]),
    ),
    apptsControllerProvider.overrideWith(() => _FixedApptsController(initial)),
    activeDoctorSpecialtyProvider.overrideWith(
      (ref) => Stream.value(specialtyOf(DoctorSpecialtyType.generalPhysician)),
    ),
    // Who is signed in (sidebar).
    authStateProvider.overrideWith((ref) => Stream.value(null)),
    doctorProfileProvider.overrideWith((ref) => Stream.value(null)),
    doctorIdentityProvider.overrideWithValue(fixtureIdentity),
    subscriptionInfoProvider.overrideWith((ref) => Stream.value(fixturePlan)),
    // Sidebar Schedule badge.
    waitingNowCountProvider.overrideWithValue(waiting),
    // Queue and appointments both on: Live plus the calendar views.
    doctorEnabledModulesStreamProvider.overrideWith(
      (ref) => Stream.value(DoctorFeatureGuard.defaultModules),
    ),
  ];
}

/// Pumps [AppointmentsScreen] inside the sidebar layout at [size]
/// (logical px, device pixel ratio 1.5) and lets streams and animations
/// settle. [anchor] defaults to [now]'s date.
Future<void> pumpAppointments(
  WidgetTester tester, {
  required List<Visit> visits,
  required List<Patient> patients,
  List<QueueEntry> queue = const [],
  required DateTime now,
  ApptsView view = ApptsView.day,
  DateTime? anchor,
  String? selectedVisitId,
  DateTime? monthSelected,
  Size size = const Size(1440, 1024),
}) async {
  tester.view.devicePixelRatio = 1.5;
  tester.view.physicalSize = size * 1.5;
  addTearDown(tester.view.reset);

  final initial = ApptsState(
    view: view,
    anchor: ApptsBuilder.dateOnly(anchor ?? now),
    selectedVisitId: selectedVisitId,
    monthSelected:
        monthSelected == null ? null : ApptsBuilder.dateOnly(monthSelected),
  );

  const appearance = CruAppearance.day;
  await tester.pumpWidget(
    ProviderScope(
      overrides: apptsOverrides(
        visits: visits,
        patients: patients,
        queue: queue,
        now: now,
        initial: initial,
      ),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: CruTheme.day(),
        home: Builder(builder: (context) {
          final width = MediaQuery.sizeOf(context).width;
          return Theme(
            data: CruTheme.of(appearance),
            child: Scaffold(
              backgroundColor: CruColors.of(appearance).canvas,
              body: DesktopShellLayout(
                sidebar: CruSidebar(
                  currentTab: DesktopTab.appointments,
                  collapsed: width < CruBreakpoint.compact,
                  canExpand: width >= CruBreakpoint.compact,
                  callbacks: _callbacks,
                ),
                content: const AppointmentsScreen(),
              ),
            ),
          );
        }),
      ),
    ),
  );
  await settleAppointments(tester);
}

/// Streams deliver, then pane and card animations (≤ 250 ms) settle.
Future<void> settleAppointments(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  // The queue stream can land a frame later and re-tint blocks.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The container behind the pumped [AppointmentsScreen].
ProviderContainer appointmentsContainer(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(AppointmentsScreen)),
    );

/// The controller behind the pumped screen.
ApptsController appointmentsController(WidgetTester tester) =>
    appointmentsContainer(tester).read(apptsControllerProvider.notifier);
