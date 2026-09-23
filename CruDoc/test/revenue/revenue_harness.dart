// Test-only: renders the desktop shell layout with the Revenue tab, the
// same way DesktopShell does, but with fake providers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/revenue/presentation/revenue_overview_screen.dart';
import 'package:doctor_management_app/features/shell/components/cru_sidebar.dart';
import 'package:doctor_management_app/features/shell/presentation/desktop_shell_layout.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import 'revenue_fixtures.dart';

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

/// The Revenue tab inside the shell layout at the current view size.
/// Defaults to the mock-up's September data.
Widget revenueApp({List<Override>? overrides}) {
  const appearance = CruAppearance.day;
  return ProviderScope(
    overrides: overrides ?? revenueOverrides(),
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
                currentTab: DesktopTab.revenue,
                collapsed: width < CruBreakpoint.compact,
                canExpand: width >= CruBreakpoint.compact,
                callbacks: _callbacks,
              ),
              content: const RevenueOverviewScreen(),
            ),
          ),
        );
      }),
    ),
  );
}

/// Sets the view size (logical × [dpr]) and resets it after the test.
void setViewSize(WidgetTester tester, Size logical, {double dpr = 1}) {
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = logical * dpr;
  addTearDown(tester.view.reset);
}

/// Streams deliver, then bar and row animations (250 ms) settle.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
