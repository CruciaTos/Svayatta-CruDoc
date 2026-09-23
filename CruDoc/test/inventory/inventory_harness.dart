// Test-only: renders the desktop shell layout with the Inventory tab, the
// same way DesktopShell does, but with fake providers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_view_providers.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_models.dart';
import 'package:doctor_management_app/features/inventory/presentation/inventory_screen.dart';
import 'package:doctor_management_app/features/shell/components/cru_sidebar.dart';
import 'package:doctor_management_app/features/shell/presentation/desktop_shell_layout.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import 'inventory_fixtures.dart';

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

/// The Inventory tab inside the shell layout at the current view size.
/// [initial] seeds the screen state (view mode, filter, selection…).
Widget inventoryApp({
  List<Override>? overrides,
  InventoryState initial = const InventoryState(),
}) {
  const appearance = CruAppearance.day;
  return ProviderScope(
    overrides: [
      ...(overrides ?? inventoryOverrides()),
      inventoryControllerProvider.overrideWith(
        () => InventoryController(initial: initial),
      ),
    ],
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
                currentTab: DesktopTab.inventory,
                collapsed: width < CruBreakpoint.compact,
                canExpand: width >= CruBreakpoint.compact,
                callbacks: _callbacks,
              ),
              content: const InventoryScreen(),
            ),
          ),
        );
      }),
    ),
  );
}

/// The grid view.
const InventoryState gridState =
    InventoryState(viewMode: InventoryViewMode.grid);

/// Sets the view size (logical × [dpr]) and resets it after the test.
void setViewSize(WidgetTester tester, Size logical, {double dpr = 1}) {
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = logical * dpr;
  addTearDown(tester.view.reset);
}

/// Mocks SharedPreferences (the sidebar's appearance choice).
void mockPreferences() => SharedPreferences.setMockInitialValues({});

/// Streams and futures deliver, then row and panel animations settle.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The container behind the pumped [InventoryScreen].
ProviderContainer inventoryContainer(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(InventoryScreen)));
