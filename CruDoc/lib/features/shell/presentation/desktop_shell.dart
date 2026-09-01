import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:doctor_management_app/core/services/auth_service.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/shell/components/mobile_feature_disabled_view.dart';
import 'package:doctor_management_app/features/shell/data/desktop_shell_preferences.dart';
import 'package:doctor_management_app/features/chatbot/widgets/draggable_floating_chatbot_button.dart';
import 'package:doctor_management_app/features/profile/presentation/profile_screen.dart';
import 'package:doctor_management_app/features/dashboard/presentation/desktop_dashboard_screen.dart';
import 'package:doctor_management_app/features/patients/presentation/desktop_patient_records_screen.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_revenue_screen.dart';
import 'package:doctor_management_app/features/inventory/presentation/desktop_inventory_list_screen.dart';
import 'package:doctor_management_app/features/inventory/presentation/inventory_alert_listener.dart';
import 'package:doctor_management_app/features/appointments/presentation/desktop_events_screen.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_invoices_screen.dart';
import 'package:doctor_management_app/features/campaigns/presentation/desktop_campaigns_screen.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/repo/invoice_repo.dart';

/// Intent for the Ctrl+B sidebar toggle shortcut.
class _ToggleSidebarIntent extends Intent {
  const _ToggleSidebarIntent();
}

/// Intent for the Ctrl+1..Ctrl+6 tab-switch shortcuts.
class _NavigateToTabIntent extends Intent {
  const _NavigateToTabIntent(this.index);
  final int index;
}

/// Desktop layout with a custom sidebar that matches the Donezo dashboard style.
/// Includes an immersive toggle between expanded (full-width) and collapsed (icon-only) states.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  final DesktopShellPreferences _shellPrefs = DesktopShellPreferences();
  final FocusNode _shortcutsFocusNode = FocusNode();
  final InvoiceRepository _invoiceRepository = InvoiceRepository();

  int _currentIndex = 0;
  bool _isSidebarExpanded = true;

  @override
  void initState() {
    super.initState();
    _restorePreferences();
    // Set the animated background colors to light blue → white → light blue.
    GrainientBackground.colorNotifier.value = const [
      Color.fromARGB(255, 183, 233, 255), // light blue top
      Color.fromARGB(255, 181, 249, 255), // white middle
      Color.fromARGB(255, 205, 239, 255), // light blue bottom
    ];
  }

  @override
  void dispose() {
    _shortcutsFocusNode.dispose();
    super.dispose();
  }

  Future<void> _restorePreferences() async {
    final expanded = await _shellPrefs.getSidebarExpanded();
    final lastTabIndex = await _shellPrefs.getLastTabIndex();
    if (!mounted) return;
    setState(() {
      _isSidebarExpanded = expanded;
      if (lastTabIndex >= 0 && lastTabIndex < _labels.length) {
        _currentIndex = lastTabIndex;
      }
    });
  }

  void _toggleSidebar() {
    setState(() {
      _isSidebarExpanded = !_isSidebarExpanded;
    });
    unawaited(_shellPrefs.setSidebarExpanded(_isSidebarExpanded));
  }

  static const List<String> _labels = [
    'Dashboard',
    'Patients',
    'Inventory',
    'Revenue',
    'Appointments',
    'Campaigns',
  ];

  static const List<IconData> _icons = [
    Icons.grid_view_rounded,
    Icons.groups_rounded,
    Icons.inventory_2_outlined,
    Icons.payments_outlined,
    Icons.calendar_today_outlined,
    Icons.campaign_rounded,
  ];

  void _onNavTap(int index) {
    if (index < 0 || index >= _labels.length) return;
    setState(() => _currentIndex = index);
    unawaited(_shellPrefs.setLastTabIndex(index));
  }

  /// Builds only the screen that's actually selected.
  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return DesktopDashboardScreen(onNavigateToTab: _onNavTap);
      case 1:
        return const DesktopPatientRecordsScreen();
      case 2:
        return const DesktopInventoryScreen();
      case 3:
        return const DesktopRevenueScreen();
      case 4:
        return const DesktopEventsScreen();
      case 5:
        return const DesktopCampaignsScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  /// Keyboard shortcuts scoped to the desktop shell: Ctrl+B toggles the
  /// sidebar and Ctrl+1..Ctrl+6 jump straight to a tab.
  Map<ShortcutActivator, Intent> get _keyboardShortcuts => {
    const SingleActivator(LogicalKeyboardKey.keyB, control: true):
        const _ToggleSidebarIntent(),
    for (var i = 0; i < _labels.length; i++)
      SingleActivator(_digitKeyFor(i), control: true): _NavigateToTabIntent(i),
  };

  static LogicalKeyboardKey _digitKeyFor(int index) {
    const digitKeys = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
    ];
    return digitKeys[index];
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: _keyboardShortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ToggleSidebarIntent: CallbackAction<_ToggleSidebarIntent>(
            onInvoke: (intent) {
              _toggleSidebar();
              return null;
            },
          ),
          _NavigateToTabIntent: CallbackAction<_NavigateToTabIntent>(
            onInvoke: (intent) {
              _onNavTap(intent.index);
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _shortcutsFocusNode,
          autofocus: true,
          child: _buildContent(context),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: DoctorFeatureGuard.watchEnabledModules(),
      builder: (context, snapshot) {
        final enabledModules =
            snapshot.data ?? DoctorFeatureGuard.defaultModules;
        final moduleKey = DoctorFeatureGuard.getModuleKeyForDesktopTab(
          _currentIndex,
        );
        final isTabEnabled =
            _currentIndex == 0 ||
            _currentIndex == 5 ||
            DoctorFeatureGuard.isEnabled(enabledModules, moduleKey);

        return StreamBuilder<List<InvoiceModel>>(
          stream: _invoiceRepository.watchInvoices(),
          builder: (context, invoiceSnapshot) {
            final pendingInvoiceCount = (invoiceSnapshot.data ?? const [])
                .where((invoice) => invoice.isPending || invoice.isOverdue)
                .length;

            return InventoryAlertListener(
              child: Scaffold(
                backgroundColor: Colors.white,
                body: Stack(
                  children: [
                    // ---------- Animated Grainient Background ----------
                    const GrainientBackground(),

                    // ---------- Main UI Row ----------
                    Row(
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
                            invoiceBadgeCount: pendingInvoiceCount,
                          ),
                        ),

                        const SizedBox(width: 16),

                        // ---------- Right: Main Content Area ----------
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: 16,
                              bottom: 16,
                              right: 16,
                            ),
                            child: isTabEnabled
                                ? SizedBox.expand(
                                    child: _buildScreen(_currentIndex),
                                  )
                                : SizedBox.expand(
                                    child: MobileFeatureDisabledView(
                                      featureTitle:
                                          DoctorFeatureGuard.getDesktopTabTitle(
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

                    // ---- Free-Floating / Draggable Chat FAB ----
                    const DraggableFloatingChatbotButton(
                      initialBottom: 32,
                      initialRight: 32,
                    ),
                  ],
                ),
              ),
            );
          },
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
  final bool isExpanded;
  final VoidCallback onToggle;
  final int invoiceBadgeCount;

  const _DesktopSidebar({
    required this.currentIndex,
    required this.labels,
    required this.icons,
    required this.onNavTap,
    required this.isExpanded,
    required this.onToggle,
    this.invoiceBadgeCount = 0,
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
                  invoiceBadgeCount: invoiceBadgeCount,
                )
              : _CollapsedLayout(
                  key: const ValueKey('collapsed'),
                  currentIndex: currentIndex,
                  labels: labels,
                  icons: icons,
                  onNavTap: onNavTap,
                  onToggle: onToggle,
                  invoiceBadgeCount: invoiceBadgeCount,
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
  final int invoiceBadgeCount;

  const _ExpandedLayout({
    required this.currentIndex,
    required this.labels,
    required this.icons,
    required this.onNavTap,
    required this.onToggle,
    this.invoiceBadgeCount = 0,
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
                  final badge = index == 3 && invoiceBadgeCount > 0
                      ? (invoiceBadgeCount > 99
                            ? '99+'
                            : invoiceBadgeCount.toString())
                      : null;
                  return _SidebarItem(
                    icon: icons[index],
                    label: labels[index],
                    isSelected: currentIndex == index,
                    badge: badge,
                    onTap: () => onNavTap(index),
                  );
                }),
                const SizedBox(height: 18),
                _buildSectionHeader('GENERAL'),
                const SizedBox(height: 8),
                _SidebarItem(
                  icon: Icons.person_outline,
                  label: 'Profile',
                  isSelected: false,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  ),
                ),
                _SidebarItem(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  isSelected: false,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  ),
                ),
                _SidebarItem(
                  icon: Icons.help_outline,
                  label: 'Help',
                  isSelected: false,
                  onTap: () => showDesktopShellHelpDialog(context),
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
            tooltip: 'Collapse sidebar (Ctrl+B)',
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
// COLLAPSED LAYOUT (Mirrors expanded structure, icons only)
// ------------------------------------------------------------------------------

class _CollapsedLayout extends StatelessWidget {
  final int currentIndex;
  final List<String> labels;
  final List<IconData> icons;
  final Function(int) onNavTap;
  final VoidCallback onToggle;
  final int invoiceBadgeCount;

  const _CollapsedLayout({
    required this.currentIndex,
    required this.labels,
    required this.icons,
    required this.onNavTap,
    required this.onToggle,
    this.invoiceBadgeCount = 0,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // --- Centered Logo (same size as expanded) ---
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
        const SizedBox(height: 24),

        // --- Scrollable Navigation Area ---
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Main navigation items (icons only)
                ...List.generate(labels.length, (index) {
                  final badge = index == 3 && invoiceBadgeCount > 0
                      ? (invoiceBadgeCount > 99
                            ? '99+'
                            : invoiceBadgeCount.toString())
                      : null;
                  return _CollapsedSidebarItem(
                    icon: icons[index],
                    label: labels[index],
                    isSelected: currentIndex == index,
                    badge: badge,
                    onTap: () => onNavTap(index),
                  );
                }),
                // Spacing equivalent to section header + gap in expanded
                const SizedBox(height: 18),

                // General items (icons only)
                _CollapsedSidebarItem(
                  icon: Icons.person_outline,
                  label: 'Profile',
                  isSelected: false,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  ),
                ),
                _CollapsedSidebarItem(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  isSelected: false,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  ),
                ),
                _CollapsedSidebarItem(
                  icon: Icons.help_outline,
                  label: 'Help',
                  isSelected: false,
                  onTap: () => showDesktopShellHelpDialog(context),
                ),
                _CollapsedSidebarItem(
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

        // --- Toggle Button (Expand) ---
        Align(
          alignment: Alignment.center,
          child: IconButton(
            onPressed: onToggle,
            tooltip: 'Expand sidebar (Ctrl+B)',
            icon: const Icon(
              Icons.arrow_forward_ios,
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
}

// ------------------------------------------------------------------------------
// COLLAPSED SIDEBAR ITEM (Icon-only, but visual style matches expanded)
// ------------------------------------------------------------------------------

class _CollapsedSidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final String? badge;
  final VoidCallback? onTap;

  const _CollapsedSidebarItem({
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
      child: Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          onTap: onTap ?? () {},
          borderRadius: BorderRadius.circular(10),
          hoverColor: isSelected
              ? const Color(0xFF2563EB).withOpacity(0.08)
              : const Color(0xFF2563EB).withOpacity(0.05),
          mouseCursor: onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF2563EB) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  icon,
                  color: isSelected ? Colors.white : const Color(0xFF8E9BAB),
                  size: 20,
                ),
                if (badge != null)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF334A5E),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
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
        hoverColor: isSelected
            ? const Color(0xFF2563EB).withOpacity(0.08)
            : const Color(0xFF2563EB).withOpacity(0.05),
        mouseCursor: onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF2563EB) : Colors.transparent,
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

// ------------------------------------------------------------------------------
// HELP & SUPPORT DIALOG
// ------------------------------------------------------------------------------

/// Lightweight, self-contained help dialog for the desktop shell.
void showDesktopShellHelpDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Help & Support'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Stuck on something? The chat bubble in the bottom-right '
              'corner can answer questions about any screen or feature.',
              style: TextStyle(fontSize: 13.5, height: 1.4),
            ),
            SizedBox(height: 18),
            Text(
              'KEYBOARD SHORTCUTS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: Color(0xFF8E9BAB),
              ),
            ),
            SizedBox(height: 10),
            _ShortcutRow(
              keys: 'Ctrl + B',
              description: 'Show or hide the sidebar',
            ),
            _ShortcutRow(
              keys: 'Ctrl + 1 – 7',
              description: 'Jump straight to a tab',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

class _ShortcutRow extends StatelessWidget {
  final String keys;
  final String description;

  const _ShortcutRow({required this.keys, required this.description});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              keys,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: Color(0xFF334A5E),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(fontSize: 13, color: Color(0xFF334A5E)),
            ),
          ),
        ],
      ),
    );
  }
}

// ==============================================================================
// ANIMATED GRAINIENT BACKGROUND
// ==============================================================================

/// A fluid animated background: wavy ribbons with a single blurred layer,
/// base gradient, animated film grain, and smooth colour transitions.
///
/// The color palette is driven by a static [ValueNotifier] so it can be
/// changed globally from anywhere in the app.
class GrainientBackground extends StatefulWidget {
  static final colorNotifier = ValueNotifier<List<Color>>(const [
    Colors.white,
    Color(0xFF81D4FA),
  ]);

  const GrainientBackground({super.key});

  @override
  State<GrainientBackground> createState() => _GrainientBackgroundState();
}

class _GrainientBackgroundState extends State<GrainientBackground>
    with TickerProviderStateMixin {
  late final AnimationController _blobController;
  late final AnimationController _colorController;

  List<Color> _fromColors = GrainientBackground.colorNotifier.value;
  List<Color> _toColors = GrainientBackground.colorNotifier.value;

  Timer? _grainTimer;
  int _grainSeed = 0;

  @override
  void initState() {
    super.initState();

    _blobController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    )..repeat();

    _colorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fromColors = GrainientBackground.colorNotifier.value;
    _toColors = GrainientBackground.colorNotifier.value;
    GrainientBackground.colorNotifier.addListener(_onColorsChanged);

    _grainTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _grainSeed = Random().nextInt(0xFFFFF));
    });
  }

  void _onColorsChanged() {
    final snapshot = _lerpColors(
      _fromColors,
      _toColors,
      _colorController.value,
    );
    setState(() {
      _fromColors = snapshot;
      _toColors = GrainientBackground.colorNotifier.value;
    });
    _colorController.forward(from: 0);
  }

  /// Interpolates between two colour lists. If they differ in length,
  /// the missing indices use the last available colour.
  static List<Color> _lerpColors(List<Color> from, List<Color> to, double t) {
    final len = max(from.length, to.length);
    return List.generate(len, (i) {
      final a = i < from.length ? from[i] : from.last;
      final b = i < to.length ? to[i] : to.last;
      return Color.lerp(a, b, t) ?? a;
    });
  }

  List<Color> get _activeColors =>
      _lerpColors(_fromColors, _toColors, _colorController.value);

  @override
  void dispose() {
    GrainientBackground.colorNotifier.removeListener(_onColorsChanged);
    _blobController.dispose();
    _colorController.dispose();
    _grainTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_blobController, _colorController]),
      builder: (context, _) => CustomPaint(
        painter: _GrainientPainter(
          t: _blobController.value * 2 * pi,
          colors: _activeColors,
          grainSeed: _grainSeed,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _GrainientPainter extends CustomPainter {
  final double t;
  final List<Color> colors;
  final int grainSeed;

  const _GrainientPainter({
    required this.t,
    required this.colors,
    required this.grainSeed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 1. Base gradient – supports 2, 3 (or more) colours
    final baseGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
      stops: _generateStops(colors.length),
    );
    canvas.drawRect(rect, Paint()..shader = baseGradient.createShader(rect));

    // 2. Blue grid (behind white grid)
    _drawBlueGrid(canvas, size);

    // 3. White grid
    _drawGrid(canvas, size);

    // 4. All ribbons drawn together into a single blurred layer
    _drawRibbonsWithSharedBlur(canvas, size);

    // 5. Film grain
    final rng = Random(grainSeed);
    _grain(canvas, size, rng, opacity: 0.022, count: 500);
    _grain(canvas, size, rng, opacity: 0.048, count: 250);
    _grain(canvas, size, rng, opacity: 0.085, count: 100);
  }

  /// Creates evenly spaced stops for a given number of colours.
  List<double>? _generateStops(int count) {
    if (count <= 1) return null;
    return List.generate(count, (i) => i / (count - 1));
  }

  /// Returns the colour at a fraction (0…1) along a multi‑stop gradient.
  Color _colorAtFraction(double fraction) {
    if (colors.isEmpty) return Colors.transparent;
    if (colors.length == 1) return colors.first;

    fraction = fraction.clamp(0.0, 1.0);

    final double step = 1.0 / (colors.length - 1);
    final int lowerIndex = (fraction / step).floor();
    final int upperIndex = lowerIndex + 1;

    if (upperIndex >= colors.length) return colors.last;

    final double localT = (fraction - lowerIndex * step) / step;
    return Color.lerp(colors[lowerIndex], colors[upperIndex], localT)!;
  }

  /// Draws all wavy ribbons inside a [saveLayer] and applies a single blur
  /// to the whole layer.
  void _drawRibbonsWithSharedBlur(Canvas canvas, Size size) {
    final layerPaint = Paint()
      ..imageFilter = ImageFilter.blur(
        sigmaX: 40,
        sigmaY: 40,
        tileMode: TileMode.clamp,
      );
    canvas.saveLayer(Offset.zero & size, layerPaint);

    const int ribbonCount = 5;
    for (int i = 0; i < ribbonCount; i++) {
      final double yFrac = 0.05 + (i / (ribbonCount - 1)) * 0.9;
      final Color ribbonColor = _colorAtFraction(yFrac);
      final double amplitude = size.height * 0.18;
      final double freq1 = 0.007 + 0.01 * sin(yFrac * 2.4);
      final double freq2 = 0.005 + 0.012 * cos(yFrac * 3.1);

      _ribbonPath(canvas, size, ribbonColor, yFrac, amplitude, freq1, freq2);
    }

    canvas.restore();
  }

  void _ribbonPath(
    Canvas canvas,
    Size size,
    Color color,
    double baseYRatio,
    double amplitude,
    double freq1,
    double freq2,
  ) {
    final path = Path();
    final double baseY = size.height * baseYRatio;

    for (double x = 0; x <= size.width; x += 8) {
      final y =
          baseY +
          amplitude * sin(x * freq1 + t * 0.7) +
          amplitude * 0.6 * cos(x * freq2 + t * 1.3);
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withOpacity(0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 120
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawBlueGrid(Canvas canvas, Size size) {
    const spacing = 60.0;
    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.10)
      ..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    const spacing = 40.0;
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _grain(
    Canvas canvas,
    Size size,
    Random rng, {
    required double opacity,
    required int count,
  }) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(opacity)
      ..strokeWidth = 1.1;
    for (int i = 0; i < count; i++) {
      canvas.drawPoints(PointMode.points, [
        Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
      ], paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GrainientPainter old) => true;
}
