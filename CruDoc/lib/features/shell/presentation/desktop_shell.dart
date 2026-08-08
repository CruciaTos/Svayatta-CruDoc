import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/shell/components/mobile_feature_disabled_view.dart';
import 'package:doctor_management_app/features/dashboard/presentation/desktop_dashboard_screen.dart';
import 'package:doctor_management_app/features/patients/presentation/desktop_patient_records_screen.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_revenue_screen.dart';
import 'package:doctor_management_app/features/inventory/presentation/desktop_inventory_list_screen.dart';
import 'package:doctor_management_app/features/inventory/presentation/inventory_alert_listener.dart';
import 'package:doctor_management_app/features/appointments/presentation/desktop_events_screen.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_invoices_screen.dart';

/// Desktop layout with a custom sidebar that matches the Donezo dashboard style,
/// including categorized menus, selected state indicators, badges, and a download card.
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
            backgroundColor: Colors.transparent,
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    // ---------- Left: Custom Sidebar with own rounded corners ----------
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _DesktopSidebar(
                        currentIndex: _currentIndex,
                        labels: _labels,
                        icons: _icons,
                        onNavTap: _onNavTap,
                      ),
                    ),

                    // ---------- Right: Main Content Area ----------
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 16, right: 16),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          clipBehavior: Clip.hardEdge,
                          child: isTabEnabled
                              ? _buildScreen(_currentIndex)
                              : MobileFeatureDisabledView(
                                  featureTitle: DoctorFeatureGuard.getTabTitle(_currentIndex),
                                  icon: _icons[_currentIndex],
                                  onBackToDashboard: () => _onNavTap(0),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ==============================================================================
// SIDEBAR WIDGETS
// ==============================================================================

class _DesktopSidebar extends StatelessWidget {
  final int currentIndex;
  final List<String> labels;
  final List<IconData> icons;
  final Function(int) onNavTap;

  const _DesktopSidebar({
    required this.currentIndex,
    required this.labels,
    required this.icons,
    required this.onNavTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), // Reduced vertical padding
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- 1. Logo Area (Pinned to top) ---
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFF0D422C),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.local_hospital, color: Colors.white, size: 14), // Reduced icon size
              ),
              const SizedBox(width: 10),
              const Text(
                'CruDoc',
                style: TextStyle(
                  color: Color(0xFF0D422C),
                  fontSize: 18, // Reduced font size
                  fontWeight: FontWeight.w700,
                  fontFamily: AppColors.headingFontFamily,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24), // Reduced gap

          // --- 2. Scrollable Menu Area ---
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('MENU'),
                  const SizedBox(height: 8), // Reduced gap
                  ...List.generate(labels.length, (index) {
                    return _SidebarItem(
                      icon: icons[index],
                      label: labels[index],
                      isSelected: currentIndex == index,
                      badge: index == 1 ? '12' : null,
                      onTap: () => onNavTap(index),
                    );
                  }),

                  const SizedBox(height: 18), // Reduced gap between sections

                  _buildSectionHeader('GENERAL'),
                  const SizedBox(height: 8), // Reduced gap
                  _SidebarItem(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    isSelected: false,
                    onTap: () {},
                  ),
                  _SidebarItem(
                    icon: Icons.help_outline,
                    label: 'Help',
                    isSelected: false,
                    onTap: () {},
                  ),
                  _SidebarItem(
                    icon: Icons.logout,
                    label: 'Logout',
                    isSelected: false,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8), // Reduced gap before download card

          // --- 3. Mobile App Download Card ---
          _buildDownloadCard(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.grey.shade400,
        fontSize: 10, // Reduced font size
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildDownloadCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A3A24), Color(0xFF13553A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.download_rounded, color: Colors.white, size: 24),
          const SizedBox(height: 10),
          const Text(
            'Download our\nMobile App',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Get easy in another way',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF156B47),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Text(
              'Download',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final String? badge;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2.0), // Reduced gap between items
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0D422C) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : const Color(0xFF8E9BAB),
                size: 20,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF8E9BAB),
                    fontWeight: FontWeight.w500,
                    fontSize: 13, // Reduced font size
                  ),
                ),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF334A5E),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (isSelected)
                const Padding(
                  padding: EdgeInsets.only(left: 4.0),
                  child: Icon(Icons.arrow_forward_ios, color: Colors.white, size: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }
}