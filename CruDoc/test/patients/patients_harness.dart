// Test-only: renders the desktop shell layout with the Patients tab, the
// same way DesktopShell does, but with fake providers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/patients/data/providers/patients_list_providers.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_details_view.dart';
import 'package:doctor_management_app/features/patients/presentation/patients_screen.dart';
import 'package:doctor_management_app/features/shell/components/cru_sidebar.dart';
import 'package:doctor_management_app/features/shell/presentation/desktop_shell_layout.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import 'patients_fixtures.dart';

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

/// [content] inside the shell layout (Patients tab selected) at the
/// current view size.
Widget _shell(List<Override> overrides, Widget content) {
  const appearance = CruAppearance.day;
  return ProviderScope(
    overrides: overrides,
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
                currentTab: DesktopTab.patients,
                collapsed: width < CruBreakpoint.compact,
                canExpand: width >= CruBreakpoint.compact,
                callbacks: _callbacks,
              ),
              content: content,
            ),
          ),
        );
      }),
    ),
  );
}

/// The Patients tab (list, or details when the controller opens them).
/// Defaults to the 12-patient fixture clinic.
Widget patientsApp({List<Override>? overrides}) =>
    _shell(overrides ?? fixtureOverrides(), const PatientsScreen());

/// Patient details rendered directly in the shell.
Widget detailsApp({
  String patientId = 'p_soham',
  List<Override>? overrides,
}) =>
    _shell(
      overrides ?? fixtureOverrides(),
      PatientDetailsView(patientId: patientId, onBack: () {}),
    );

/// The container behind the pumped [PatientsScreen] (or details view).
ProviderContainer patientsContainer(WidgetTester tester) {
  final screen = find.byType(PatientsScreen);
  final at = screen.evaluate().isNotEmpty
      ? screen
      : find.byType(PatientDetailsView);
  return ProviderScope.containerOf(tester.element(at.first));
}

/// The list controller behind the pumped screen.
PatientsListController patientsController(WidgetTester tester) =>
    patientsContainer(tester).read(patientsListControllerProvider.notifier);

/// Sets the view size (logical × [dpr]) and resets it after the test.
void setViewSize(WidgetTester tester, Size logical, {double dpr = 1}) {
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = logical * dpr;
  addTearDown(tester.view.reset);
}

/// Streams deliver, then pane/row animations (240 ms) settle.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
