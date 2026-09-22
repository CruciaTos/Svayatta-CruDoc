// Test-only: renders the desktop shell layout with the dashboard, the
// same way DesktopShell does, but with fake providers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:doctor_management_app/features/shell/components/cru_sidebar.dart';
import 'package:doctor_management_app/features/shell/presentation/desktop_shell_layout.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import 'dashboard_fixtures.dart';

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

/// The dashboard inside the shell layout at the current view size.
Widget dashboardApp({required bool evening, bool emptyQueue = false}) {
  final appearance = evening ? CruAppearance.evening : CruAppearance.day;
  return ProviderScope(
    overrides: dashboardOverrides(evening: evening, emptyQueue: emptyQueue),
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
                currentTab: 0,
                collapsed: width < CruBreakpoint.compact,
                canExpand: width >= CruBreakpoint.compact,
                callbacks: _callbacks,
              ),
              content: DashboardScreen(onNavigateToTab: (_) {}),
            ),
          ),
        );
      }),
    ),
  );
}
