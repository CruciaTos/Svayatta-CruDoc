import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:doctor_management_app/core/services/auth_service.dart';
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

/// Desktop layout with a custom sidebar that matches the Donezo dashboard style.
/// Includes an immersive toggle between expanded (full-width) and collapsed (icon-only) states.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  static const chartBarDim = Color.fromARGB(255, 140, 188, 255);

  int _currentIndex = 0;
  bool _isSidebarExpanded = true;

  void _toggleSidebar() {
    setState(() {
      _isSidebarExpanded = !_isSidebarExpanded;
    });
  }

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

  /// Builds only the screen that's actually selected.
  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return DesktopDashboardScreen(onNavigateToTab: _onNavTap);
      case 1:
        return const DesktopInvoicesScreen();
      case 2:
        return const DesktopPatientRecordsScreen();
      case 3:
        return const DesktopInventoryScreen();
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
        final enabledModules =
            snapshot.data ?? DoctorFeatureGuard.defaultModules;
        final moduleKey = DoctorFeatureGuard.getModuleKeyForTab(_currentIndex);
        final isTabEnabled =
            _currentIndex == 0 ||
            DoctorFeatureGuard.isEnabled(enabledModules, moduleKey);

        return InventoryAlertListener(
          child: Scaffold(
            backgroundColor: Colors.white,
            body: Container(
              width: double.infinity,
              height: double.infinity,
              color: chartBarDim,
              child: Row(
                children: [
                  // ---------- Left: Animated Custom Sidebar ----------
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 16,
                      bottom: 16,
                      left: 16,
                    ),
                    child: _DesktopSidebar(
                      currentIndex: _currentIndex,
                      labels: _labels,
                      icons: _icons,
                      onNavTap: _onNavTap,
                      isExpanded: _isSidebarExpanded,
                      onToggle: _toggleSidebar,
                    ),
                  ),

                  const SizedBox(width: 16),

                  // ---------- Right: Main Content Area ----------
                  // [FIXED] Removed the clipping Container wrapper to let the inner screen
                  // fill the exact space with its own 24px border radius and shadow.
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(
                        top: 16,
                        bottom: 16,
                        right: 16,
                      ),
                      child: isTabEnabled
                          ? SizedBox.expand(child: _buildScreen(_currentIndex))
                          : SizedBox.expand(
                              child: MobileFeatureDisabledView(
                                featureTitle: DoctorFeatureGuard.getTabTitle(
                                  _currentIndex,
                                ),
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
        );
      },
    );
  }
}

// ==============================================================================
// SIDEBAR WIDGETS (Kept exactly as provided - no changes)
// ==============================================================================

class _DesktopSidebar extends StatelessWidget {
  final int currentIndex;
  final List<String> labels;
  final List<IconData> icons;
  final Function(int) onNavTap;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _DesktopSidebar({
    required this.currentIndex,
    required this.labels,
    required this.icons,
    required this.onNavTap,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
      width: isExpanded ? 220 : 76,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeInOutCubic,
          switchOutCurve: Curves.easeInOutCubic,
          child: isExpanded
              ? _ExpandedLayout(
                  key: const ValueKey('expanded'),
                  currentIndex: currentIndex,
                  labels: labels,
                  icons: icons,
                  onNavTap: onNavTap,
                  onToggle: onToggle,
                )
              : _CollapsedLayout(
                  key: const ValueKey('collapsed'),
                  currentIndex: currentIndex,
                  icons: icons,
                  onNavTap: onNavTap,
                  onToggle: onToggle,
                ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------
// EXPANDED LAYOUT (Full White Sidebar with Labels)
// ------------------------------------------------------------------------------

class _ExpandedLayout extends StatelessWidget {
  final int currentIndex;
  final List<String> labels;
  final List<IconData> icons;
  final Function(int) onNavTap;
  final VoidCallback onToggle;

  const _ExpandedLayout({
    required this.currentIndex,
    required this.labels,
    required this.icons,
    required this.onNavTap,
    required this.onToggle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Logo Area ---
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: Color(0xFF0D422C),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_hospital,
                color: Colors.white,
                size: 14,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'CruDoc',
              style: TextStyle(
                color: Color(0xFF0D422C),
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFamily: AppColors.headingFontFamily,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // --- Scrollable Menu Area ---
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader('MENU'),
                const SizedBox(height: 8),
                ...List.generate(labels.length, (index) {
                  return _SidebarItem(
                    icon: icons[index],
                    label: labels[index],
                    isSelected: currentIndex == index,
                    badge: index == 1 ? '12' : null,
                    onTap: () => onNavTap(index),
                  );
                }),
                const SizedBox(height: 18),
                _buildSectionHeader('GENERAL'),
                const SizedBox(height: 8),
                const _SidebarItem(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  isSelected: false,
                  onTap: null,
                ),
                const _SidebarItem(
                  icon: Icons.help_outline,
                  label: 'Help',
                  isSelected: false,
                  onTap: null,
                ),
                _SidebarItem(
                  icon: Icons.logout,
                  label: 'Logout',
                  isSelected: false,
                  onTap: () async {
                    final authService = AuthService();
                    await authService.signOut();
                    if (!context.mounted) return;
                    context.go('/auth');
                  },
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // --- Download Card ---
        _buildDownloadCard(),

        // --- Toggle Button (Collapse) ---
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            onPressed: onToggle,
            icon: const Icon(
              Icons.arrow_back_ios_new,
              size: 14,
              color: Color(0xFF8E9BAB),
            ),
            splashRadius: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.grey.shade400,
        fontSize: 10,
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
            style: TextStyle(color: Colors.white70, fontSize: 11),
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

// ------------------------------------------------------------------------------
// COLLAPSED LAYOUT (Clean, Minimalist, Icon-Only)
// ------------------------------------------------------------------------------

class _CollapsedLayout extends StatelessWidget {
  final int currentIndex;
  final List<IconData> icons;
  final Function(int) onNavTap;
  final VoidCallback onToggle;

  const _CollapsedLayout({
    required this.currentIndex,
    required this.icons,
    required this.onNavTap,
    required this.onToggle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // --- Minimalist Logo (Center) ---
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Color(0xFF0D422C),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.local_hospital,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(height: 32),

        // --- Navigation Icons (Center) ---
        ...List.generate(
          icons.length,
          (index) => _buildCollapsedNavItem(index),
        ),

        const Spacer(),

        // --- Bottom Utility Icons ---
        IconButton(
          icon: const Icon(
            Icons.settings_outlined,
            color: Color(0xFF8E9BAB),
            size: 20,
          ),
          onPressed: () {},
          splashRadius: 20,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
        const SizedBox(height: 4),
        IconButton(
          icon: const Icon(
            Icons.help_outline,
            color: Color(0xFF8E9BAB),
            size: 20,
          ),
          onPressed: () {},
          splashRadius: 20,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),

        const SizedBox(height: 8),

        // --- Toggle Button (Expand) ---
        IconButton(
          onPressed: onToggle,
          icon: const Icon(
            Icons.arrow_forward_ios,
            size: 14,
            color: Color(0xFF8E9BAB),
          ),
          splashRadius: 20,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }

  Widget _buildCollapsedNavItem(int index) {
    final bool isSelected = currentIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: InkWell(
        onTap: () => onNavTap(index),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF0D422C).withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icons[index],
            color: isSelected
                ? const Color(0xFF0D422C)
                : const Color(0xFF8E9BAB),
            size: 22,
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------
// STANDARD MENU ITEM (Used inside Expanded Layout)
// ------------------------------------------------------------------------------

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final String? badge;
  final VoidCallback? onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    this.badge,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2.0),
      child: InkWell(
        onTap: onTap ?? () {},
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
                    fontSize: 13,
                  ),
                ),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
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
                  child: Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
