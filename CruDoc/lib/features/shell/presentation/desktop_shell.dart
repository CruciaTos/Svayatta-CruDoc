import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/shell/components/mobile_feature_disabled_view.dart';
import 'package:doctor_management_app/features/dashboard/presentation/desktop_dashboard_screen.dart';
import 'package:doctor_management_app/features/patients/presentation/desktop_patient_records_screen.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_revenue_screen.dart';
import 'package:doctor_management_app/features/bottom_nav/bottom_nav_bar.dart' show chartBarLight;
import 'package:doctor_management_app/features/inventory/presentation/desktop_inventory_list_screen.dart';
import 'package:doctor_management_app/features/inventory/presentation/inventory_alert_listener.dart';
import 'package:doctor_management_app/features/appointments/presentation/desktop_events_screen.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_invoices_screen.dart';

/// First-pass desktop layout: a fixed sidebar (NavigationRail) on the left
/// + the same feature screens the mobile [Shell] uses on the right.
///
/// Deliberately minimal — no custom theming beyond reusing existing
/// [AppColors], no collapsing sidebar, no animation. This is a starting
/// point to refine later, not a final design.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  int _currentIndex = 0;

  static const List<String> _labels = [
    'Dashboard',
    'Invoices',
    'Patients',
    'Inventory',
    'Revenue',
    'Appointments',
  ];

  static const List<IconData> _icons = [
    Icons.grid_view_rounded,
    Icons.receipt_long_outlined,
    Icons.groups_rounded,
    Icons.inventory_2_outlined,
    Icons.payments_outlined,
    Icons.calendar_today_outlined,
  ];

  static const List<IconData> _activeIcons = [
    Icons.grid_view_rounded,
    Icons.receipt_long_rounded,
    Icons.groups_rounded,
    Icons.inventory_2,
    Icons.payments_outlined,
    Icons.calendar_today_outlined,
  ];

  void _onNavTap(int index) {
    if (index < 0 || index >= _labels.length) return;
    setState(() => _currentIndex = index);
  }

  /// Builds only the screen that's actually selected — mirrors the mobile
  /// Shell's behaviour of never constructing a screen behind a locked
  /// module (e.g. so it can't fire off Firestore reads it isn't allowed to).
  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return DesktopDashboardScreen(onNavigateToTab: _onNavTap);
      case 1:
        return const DesktopInvoicesScreen();
      case 2:
        return const DesktopPatientRecordsScreen();
      case 3:
        return const DesktopInventoryListScreen();
      case 4:
        return const DesktopRevenueScreen();
      case 5:
        return const DesktopEventsScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: DoctorFeatureGuard.watchEnabledModules(),
      builder: (context, snapshot) {
        final enabledModules = snapshot.data ?? DoctorFeatureGuard.defaultModules;
        final moduleKey = DoctorFeatureGuard.getModuleKeyForTab(_currentIndex);
        final isTabEnabled = _currentIndex == 0 ||
            DoctorFeatureGuard.isEnabled(enabledModules, moduleKey);

        return InventoryAlertListener(
          child: Scaffold(
            backgroundColor: AppColors.bgBottom,
            body: Row(
              children: [
                NavigationRail(
                  extended: true,
                  minExtendedWidth: 224,
                  backgroundColor: AppColors.midnightBlue,
                  selectedIndex: _currentIndex,
                  onDestinationSelected: _onNavTap,
                  useIndicator: true,
                  indicatorColor: chartBarLight,
                  selectedIconTheme: const IconThemeData(color: Colors.white),
                  unselectedIconTheme: const IconThemeData(color: AppColors.silver),
                  selectedLabelTextStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelTextStyle: const TextStyle(color: AppColors.silver),
                  leading: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'CruDoc',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        fontFamily: AppColors.headingFontFamily,
                      ),
                    ),
                  ),
                  destinations: List.generate(_labels.length, (index) {
                    return NavigationRailDestination(
                      icon: Icon(_icons[index]),
                      selectedIcon: Icon(_activeIcons[index]),
                      label: Text(_labels[index]),
                    );
                  }),
                ),
                const VerticalDivider(width: 1, color: AppColors.divider),
                Expanded(
                  child: isTabEnabled
                      ? _buildScreen(_currentIndex)
                      : MobileFeatureDisabledView(
                          featureTitle: DoctorFeatureGuard.getTabTitle(_currentIndex),
                          icon: _icons[_currentIndex],
                          onBackToDashboard: () => _onNavTap(0),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}