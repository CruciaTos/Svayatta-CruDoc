import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:doctor_management_app/core/services/demo_session_service.dart';
import 'package:doctor_management_app/features/settings/data/appearance_preferences.dart';
import 'package:doctor_management_app/features/settings/data/appearance_provider.dart';
import 'package:doctor_management_app/features/shell/presentation/desktop_shell_layout.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import '../config/enums.dart';
import '../providers/auth_provider.dart';
import '../providers/doctor_provider.dart';
import '../providers/support_ticket_provider.dart';
import '../providers/ui_provider.dart';
import 'dashboard/analytics_screen.dart';
import 'dashboard/api_usage_screen.dart';
import 'dashboard/audit_logs_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'dashboard/doctors_screen.dart';
import 'dashboard/features_screen.dart';
import 'dashboard/settings_screen.dart';
import 'dashboard/support_screen.dart';

// Intents for Super Admin keyboard shortcuts
class _ToggleSidebarIntent extends Intent {
  const _ToggleSidebarIntent();
}

class _NavigateToTabIntent extends Intent {
  const _NavigateToTabIntent(this.tab);
  final SuperAdminTab tab;
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

/// Navigation item definition for the Calm Clinical Super Admin sidebar.
class _AdminNavItem {
  const _AdminNavItem({
    required this.tab,
    required this.label,
    required this.icon,
  });

  final SuperAdminTab tab;
  final String label;
  final CruIconData icon;
}

class _AdminNavGroup {
  const _AdminNavGroup({
    required this.label,
    required this.items,
  });

  final String label;
  final List<_AdminNavItem> items;
}

/// Main Super Admin shell redesigned in the CruDoc Calm Clinical design system.
class SuperAdminShell extends ConsumerStatefulWidget {
  const SuperAdminShell({super.key});

  @override
  ConsumerState<SuperAdminShell> createState() => _SuperAdminShellState();
}

class _SuperAdminShellState extends ConsumerState<SuperAdminShell> {
  final FocusNode _shortcutsFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'admin search');
  final TextEditingController _searchController = TextEditingController();

  static const List<_AdminNavGroup> _navGroups = [
    _AdminNavGroup(
      label: 'OVERVIEW',
      items: [
        _AdminNavItem(
          tab: SuperAdminTab.dashboard,
          label: 'Dashboard',
          icon: CruIcons.dashboard,
        ),
        _AdminNavItem(
          tab: SuperAdminTab.doctors,
          label: 'Doctors & Clinics',
          icon: CruIcons.patients,
        ),
        _AdminNavItem(
          tab: SuperAdminTab.features,
          label: 'Feature Modules',
          icon: CruIcons.flask,
        ),
      ],
    ),
    _AdminNavGroup(
      label: 'OBSERVABILITY',
      items: [
        _AdminNavItem(
          tab: SuperAdminTab.analytics,
          label: 'Analytics & Growth',
          icon: CruIcons.sparkle,
        ),
        _AdminNavItem(
          tab: SuperAdminTab.apiKeys,
          label: 'API Usage & Cost',
          icon: CruIcons.rupee,
        ),
        _AdminNavItem(
          tab: SuperAdminTab.auditLogs,
          label: 'Security & Audits',
          icon: CruIcons.clock,
        ),
      ],
    ),
    _AdminNavGroup(
      label: 'GOVERNANCE',
      items: [
        _AdminNavItem(
          tab: SuperAdminTab.support,
          label: 'Support Desk',
          icon: CruIcons.help,
        ),
        _AdminNavItem(
          tab: SuperAdminTab.settings,
          label: 'Platform Settings',
          icon: CruIcons.settings,
        ),
      ],
    ),
  ];

  late final Map<ShortcutActivator, Intent> _keyboardShortcuts = {
    const SingleActivator(LogicalKeyboardKey.keyB, control: true):
        const _ToggleSidebarIntent(),
    if (defaultTargetPlatform == TargetPlatform.macOS)
      const SingleActivator(LogicalKeyboardKey.keyB, meta: true):
          const _ToggleSidebarIntent(),
    const SingleActivator(LogicalKeyboardKey.keyK, control: true):
        const _FocusSearchIntent(),
    if (defaultTargetPlatform == TargetPlatform.macOS)
      const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
          const _FocusSearchIntent(),
    const SingleActivator(LogicalKeyboardKey.digit1, control: true):
        const _NavigateToTabIntent(SuperAdminTab.dashboard),
    const SingleActivator(LogicalKeyboardKey.digit2, control: true):
        const _NavigateToTabIntent(SuperAdminTab.doctors),
    const SingleActivator(LogicalKeyboardKey.digit3, control: true):
        const _NavigateToTabIntent(SuperAdminTab.features),
    const SingleActivator(LogicalKeyboardKey.digit4, control: true):
        const _NavigateToTabIntent(SuperAdminTab.analytics),
    const SingleActivator(LogicalKeyboardKey.digit5, control: true):
        const _NavigateToTabIntent(SuperAdminTab.apiKeys),
    const SingleActivator(LogicalKeyboardKey.digit6, control: true):
        const _NavigateToTabIntent(SuperAdminTab.auditLogs),
    const SingleActivator(LogicalKeyboardKey.digit7, control: true):
        const _NavigateToTabIntent(SuperAdminTab.support),
    const SingleActivator(LogicalKeyboardKey.digit8, control: true):
        const _NavigateToTabIntent(SuperAdminTab.settings),
  };

  @override
  void dispose() {
    _shortcutsFocusNode.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabSelected(SuperAdminTab tab) {
    ref.read(superAdminUIProvider.notifier).selectTab(tab);
  }

  void _toggleSidebar() {
    ref.read(superAdminUIProvider.notifier).toggleSidebar();
  }

  void _focusSearch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appearance = ref.watch(resolvedAppearanceProvider);
    final theme = CruTheme.of(appearance);

    return Theme(
      data: theme,
      child: Shortcuts(
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
                _onTabSelected(intent.tab);
                return null;
              },
            ),
            _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
              onInvoke: (intent) {
                _focusSearch();
                return null;
              },
            ),
          },
          child: Focus(
            focusNode: _shortcutsFocusNode,
            autofocus: true,
            child: Builder(
              builder: (ctx) => _buildShell(ctx),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShell(BuildContext context) {
    final c = context.cru;
    final uiState = ref.watch(superAdminUIProvider);
    final authState = ref.watch(superAdminAuthProvider);
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 768;

    final sidebar = _CruSuperAdminSidebar(
      selectedTab: uiState.selectedTab,
      isCollapsed: !uiState.isSidebarOpen && !isMobile,
      onTabSelected: _onTabSelected,
      onToggleCollapsed: _toggleSidebar,
      onHelp: () => _showHelpDialog(context),
      onLogout: () => _showLogoutDialog(context),
      currentAdminName: authState.currentAdmin?.name ?? 'Root Administrator',
      currentAdminEmail: authState.currentAdmin?.email ?? 'admin@crudoc.com',
    );

    if (isMobile) {
      return CruAmbientBackground(
        isEvening: c.isEvening,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: c.surface,
            elevation: 0,
            leading: Builder(
              builder: (innerContext) => IconButton(
                icon: CruIcon(CruIcons.dashboard, size: 20, color: c.label),
                onPressed: () => Scaffold.of(innerContext).openDrawer(),
              ),
            ),
            title: Row(
              children: [
                _AdminBrandMark(size: 26),
                const SizedBox(width: CruSpace.s10),
                Text(
                  uiState.selectedTab.label,
                  style: CruType.callout.tint(c.label),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Return to Clinic Portal',
                icon: CruIcon(CruIcons.arrowUpRight, size: 18, color: c.accentText),
                onPressed: () {
                  DemoSessionService.startDemoSession();
                  context.go('/dashboard');
                },
              ),
            ],
          ),
          drawer: Drawer(
            backgroundColor: c.surface,
            child: sidebar,
          ),
          body: _buildContent(uiState.selectedTab),
        ),
      );
    }

    return CruAmbientBackground(
      isEvening: c.isEvening,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Calm Clinical Floating Sidebar
          sidebar,

          // Main Screen Area with Header
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Calm Clinical Top Header Bar
                _AdminTopBar(
                  selectedTab: uiState.selectedTab,
                  searchFocusNode: _searchFocusNode,
                  searchController: _searchController,
                  isSidebarOpen: uiState.isSidebarOpen,
                  onToggleSidebar: _toggleSidebar,
                ),

                // Selected Tab Content
                Expanded(
                  child: _buildContent(uiState.selectedTab),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(SuperAdminTab tab) {
    switch (tab) {
      case SuperAdminTab.dashboard:
        return const SuperAdminDashboardScreen();
      case SuperAdminTab.doctors:
        return const SuperAdminDoctorsScreen();
      case SuperAdminTab.features:
        return const SuperAdminFeaturesScreen();
      case SuperAdminTab.analytics:
        return const SuperAdminAnalyticsScreen();
      case SuperAdminTab.apiKeys:
        return const SuperAdminApiUsageScreen();
      case SuperAdminTab.support:
        return const SuperAdminSupportScreen();
      case SuperAdminTab.auditLogs:
        return const SuperAdminAuditLogsScreen();
      case SuperAdminTab.settings:
        return const SuperAdminSettingsScreen();
    }
  }

  void _showHelpDialog(BuildContext context) {
    final c = context.cru;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: c.surface,
        shape: cruShape(CruRadius.card),
        title: Row(
          children: [
            CruIcon(CruIcons.help, size: 22, color: c.accent),
            const SizedBox(width: CruSpace.s12),
            Text('Super Admin Shortcuts', style: CruType.title.tint(c.label)),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              _ShortcutRow(keys: 'Ctrl + B', description: 'Toggle Sidebar Collapse'),
              _ShortcutRow(keys: 'Ctrl + K', description: 'Focus Global Search Bar'),
              _ShortcutRow(keys: 'Ctrl + 1', description: 'Jump to Dashboard Overview'),
              _ShortcutRow(keys: 'Ctrl + 2', description: 'Jump to Doctors & Clinics'),
              _ShortcutRow(keys: 'Ctrl + 3', description: 'Jump to Feature Modules'),
              _ShortcutRow(keys: 'Ctrl + 4', description: 'Jump to Analytics & Growth'),
              _ShortcutRow(keys: 'Ctrl + 5', description: 'Jump to API Usage & Cost'),
              _ShortcutRow(keys: 'Ctrl + 6', description: 'Jump to Security & Audit Logs'),
              _ShortcutRow(keys: 'Ctrl + 7', description: 'Jump to Support Desk'),
              _ShortcutRow(keys: 'Ctrl + 8', description: 'Jump to Platform Settings'),
            ],
          ),
        ),
        actions: [
          CruButton(
            label: 'Got it',
            kind: CruButtonKind.primary,
            onPressed: () => Navigator.of(dialogCtx).pop(),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    final c = context.cru;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: c.surface,
        shape: cruShape(CruRadius.card),
        title: Text('Sign Out of Super Admin?', style: CruType.title.tint(c.label)),
        content: Text(
          'Your active platform administration session will be terminated. You will be returned to the clinic login portal.',
          style: CruType.text.tint(c.label2),
        ),
        actions: [
          CruButton(
            label: 'Cancel',
            kind: CruButtonKind.secondary,
            onPressed: () => Navigator.of(dialogCtx).pop(),
          ),
          CruButton(
            label: 'Sign Out',
            kind: CruButtonKind.primary,
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              ref.read(superAdminAuthProvider.notifier).logout();
              context.go('/auth');
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────────────────────────────────────

class _AdminTopBar extends ConsumerWidget {
  const _AdminTopBar({
    required this.selectedTab,
    required this.searchFocusNode,
    required this.searchController,
    required this.isSidebarOpen,
    required this.onToggleSidebar,
  });

  final SuperAdminTab selectedTab;
  final FocusNode searchFocusNode;
  final TextEditingController searchController;
  final bool isSidebarOpen;
  final VoidCallback onToggleSidebar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final isDemo = DemoSessionService.isSuperAdminMode;
    final appMode = ref.watch(appearanceModeProvider);

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(
          bottom: BorderSide(color: c.hairline),
        ),
      ),
      child: Row(
        children: [
          // Breadcrumb Trail
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'CruDoc Admin',
                style: CruType.subhead.tint(c.label3),
              ),
              const SizedBox(width: CruSpace.s8),
              CruIcon(CruIcons.chevronRight, size: 14, color: c.label3),
              const SizedBox(width: CruSpace.s8),
              Text(
                selectedTab.label,
                style: CruType.headline.tint(c.label),
              ),
            ],
          ),

          const SizedBox(width: CruSpace.s24),

          // Search Field (Ctrl + K)
          SizedBox(
            width: CruSize.searchWidth,
            height: 38,
            child: TextField(
              focusNode: searchFocusNode,
              controller: searchController,
              style: CruType.text.tint(c.label),
              decoration: InputDecoration(
                hintText: 'Search platform, doctors, logs...',
                hintStyle: CruType.text.tint(c.label3),
                filled: true,
                fillColor: c.surface,
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(10),
                  child: CruIcon(CruIcons.search, size: 16, color: c.label3),
                ),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      CruKeycap('Ctrl K'),
                    ],
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  borderSide: BorderSide(color: c.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  borderSide: BorderSide(color: c.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  borderSide: BorderSide(color: c.accent, width: 1.5),
                ),
              ),
            ),
          ),

          const Spacer(),

          // System Status Pill
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: ShapeDecoration(
              color: c.surface,
              shape: cruShape(CruRadius.full, side: BorderSide(color: c.hairline)),
              shadows: c.cardShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CruStatusDot(CruDotKind.done, size: 8),
                const SizedBox(width: CruSpace.s8),
                Text(
                  'Bridge: Active (Port 8766)',
                  style: CruType.caption.w600.tint(c.label),
                ),
              ],
            ),
          ),

          const SizedBox(width: CruSpace.s12),

          // Demo Mode Indicator Pill
          if (isDemo) ...[
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: ShapeDecoration(
                color: c.amberTint,
                shape: cruShape(CruRadius.full),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CruIcon(CruIcons.warning, size: 14, color: c.amberText),
                  const SizedBox(width: CruSpace.s6),
                  Text(
                    'DEV DEMO SESSION',
                    style: CruType.caption.w600.tint(c.amberText),
                  ),
                ],
              ),
            ),
            const SizedBox(width: CruSpace.s12),
          ],

          // Appearance Toggle
          IconButton(
            tooltip: appMode == AppearanceMode.evening ? 'Day theme' : 'Evening theme',
            icon: CruIcon(
              appMode == AppearanceMode.evening ? CruIcons.sun : CruIcons.moon,
              size: 18,
              color: c.label2,
            ),
            onPressed: () {
              final next = appMode == AppearanceMode.evening
                  ? AppearanceMode.day
                  : AppearanceMode.evening;
              ref.read(appearanceModeProvider.notifier).select(next);
            },
          ),

          const SizedBox(width: CruSpace.s8),

          // Return to Clinic Portal Button
          CruButton(
            label: 'Doctor Portal',
            kind: CruButtonKind.secondary,
            icon: CruIcons.arrowUpRight,
            onPressed: () {
              DemoSessionService.startDemoSession();
              context.go('/dashboard');
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CALM CLINICAL SUPER ADMIN SIDEBAR
// ─────────────────────────────────────────────────────────────────────────────

class _CruSuperAdminSidebar extends ConsumerWidget {
  const _CruSuperAdminSidebar({
    required this.selectedTab,
    required this.isCollapsed,
    required this.onTabSelected,
    required this.onToggleCollapsed,
    required this.onHelp,
    required this.onLogout,
    required this.currentAdminName,
    required this.currentAdminEmail,
  });

  final SuperAdminTab selectedTab;
  final bool isCollapsed;
  final ValueChanged<SuperAdminTab> onTabSelected;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onHelp;
  final VoidCallback onLogout;
  final String currentAdminName;
  final String currentAdminEmail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final doctorState = ref.watch(doctorListProvider);
    final ticketState = ref.watch(supportTicketProvider);

    final pendingDoctors = doctorState.doctors
        .where((d) => d.status.name.toLowerCase() == 'pending')
        .length;
    final openTickets = ticketState.tickets
        .where((t) => t.status == TicketStatus.open)
        .length;

    return AnimatedContainer(
      duration: CruMotion.of(context),
      curve: CruMotion.curve,
      width: isCollapsed ? CruSize.sidebarCollapsed : CruSize.sidebar,
      color: Colors.transparent,
      padding: isCollapsed
          ? const EdgeInsets.fromLTRB(8, 12, 4, 12)
          : const EdgeInsets.fromLTRB(12, 12, 4, 12),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: c.surface,
          shape: cruShape(CruRadius.card),
          shadows: [
            BoxShadow(
              color: c.isEvening
                  ? const Color(0x66000000)
                  : const Color(0x180F172A),
              blurRadius: 16,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: c.isEvening
                  ? const Color(0x40000000)
                  : const Color(0x0C0F172A),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Padding(
          padding: isCollapsed
              ? const EdgeInsets.fromLTRB(0, 16, 0, 12)
              : const EdgeInsets.fromLTRB(14, 18, 14, 14),
          child: Semantics(
            container: true,
            label: 'Super Admin navigation',
            child: Column(
              crossAxisAlignment: isCollapsed
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.stretch,
              children: [
                // Brand Header with Collapser
                if (isCollapsed)
                  const _AdminBrandMark(size: CruSize.appMark)
                else
                  Row(
                    children: [
                      const _AdminBrandMark(size: CruSize.appMark),
                      const SizedBox(width: CruSpace.s10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('CruDoc', style: CruType.wordmark.tint(c.label)),
                            Text(
                              'SUPER ADMIN CONSOLE',
                              style: CruType.caption.w600.tint(c.accentText),
                            ),
                          ],
                        ),
                      ),
                      CruPressable(
                        onTap: onToggleCollapsed,
                        tooltip: 'Collapse sidebar (Ctrl+B)',
                        builder: (ctx, hovered) => Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: ShapeDecoration(
                            color: hovered ? c.hoverFill : Colors.transparent,
                            shape: cruShape(8),
                          ),
                          child: CruIcon(
                            CruIcons.chevronLeft,
                            size: 16,
                            color: c.label2,
                          ),
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: CruSpace.s14),

                // Platform Master Scope Switcher Tile
                _PlatformScopeTile(collapsed: isCollapsed),

                const SizedBox(height: CruSpace.s14),

                // Navigation Groups
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: isCollapsed
                          ? CrossAxisAlignment.center
                          : CrossAxisAlignment.stretch,
                      children: [
                        for (var g = 0; g < _SuperAdminShellState._navGroups.length; g++) ...[
                          if (g > 0) const SizedBox(height: CruSpace.s16),
                          if (!isCollapsed)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                              child: Text(
                                _SuperAdminShellState._navGroups[g].label,
                                style: CruType.groupLabel.tint(c.label3),
                              ),
                            ),
                          for (final item in _SuperAdminShellState._navGroups[g].items) ...[
                            const SizedBox(height: CruSpace.s2),
                            _AdminSidebarItemWidget(
                              item: item,
                              selected: selectedTab == item.tab,
                              collapsed: isCollapsed,
                              badge: switch (item.tab) {
                                SuperAdminTab.doctors when pendingDoctors > 0 => pendingDoctors,
                                SuperAdminTab.support when openTickets > 0 => openTickets,
                                _ => null,
                              },
                              onTap: () => onTabSelected(item.tab),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: CruSpace.s10),

                // Admin Account Profile Menu
                _AdminProfileButton(
                  name: currentAdminName,
                  email: currentAdminEmail,
                  collapsed: isCollapsed,
                  onHelp: onHelp,
                  onLogout: onLogout,
                  onToggleCollapsed: onToggleCollapsed,
                ),

                if (isCollapsed) ...[
                  const SizedBox(height: CruSpace.s8),
                  CruPressable(
                    onTap: onToggleCollapsed,
                    tooltip: 'Expand sidebar (Ctrl+B)',
                    builder: (ctx, hovered) => Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        color: hovered ? c.hoverFill : Colors.transparent,
                        shape: cruShape(8),
                      ),
                      child: CruIcon(CruIcons.chevronRight, size: 16, color: c.label2),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BRAND MARK
// ─────────────────────────────────────────────────────────────────────────────

class _AdminBrandMark extends StatelessWidget {
  const _AdminBrandMark({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: c.accent,
        shape: cruShape(CruRadius.appMark),
      ),
      child: CruIcon(
        CruIcons.plus,
        size: size * 0.53,
        strokeWidth: 3.4,
        color: c.onAccent,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PLATFORM SCOPE TILE
// ─────────────────────────────────────────────────────────────────────────────

class _PlatformScopeTile extends StatelessWidget {
  const _PlatformScopeTile({required this.collapsed});
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final icon = Container(
      width: CruSize.clinicTile,
      height: CruSize.clinicTile,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: c.accentTint,
        shape: cruShape(CruRadius.appMark),
      ),
      child: CruIcon(CruIcons.dashboard, size: 16, color: c.accentText),
    );

    if (collapsed) {
      return Tooltip(
        message: 'Master Platform Scope',
        child: icon,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: ShapeDecoration(
        color: c.surface,
        shape: cruShape(CruRadius.switcher, side: BorderSide(color: c.hairline)),
        shadows: c.cardShadow,
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: CruSpace.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Master Scope',
                  style: CruType.callout.copyWith(height: 18 / 14).tint(c.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'All Clinics & Hardware',
                  style: CruType.caption.tint(c.label2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const CruStatusDot(CruDotKind.done, size: 6),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SIDEBAR ITEM WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class _AdminSidebarItemWidget extends StatelessWidget {
  const _AdminSidebarItemWidget({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
    this.badge,
  });

  final _AdminNavItem item;
  final bool selected;
  final bool collapsed;
  final int? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final label = badge == null ? item.label : '${item.label}, $badge alert';

    return Semantics(
      selected: selected,
      child: CruPressable(
        onTap: onTap,
        semanticLabel: label,
        tooltip: collapsed ? label : null,
        scaleOnPress: false,
        builder: (ctx, hovered) {
          final fill = selected
              ? c.accent
              : hovered
                  ? (c.isEvening ? c.inset : c.hoverFill)
                  : Colors.transparent;

          final icon = CruIcon(
            item.icon,
            size: CruSize.navIcon,
            color: selected ? CruBrand.white : c.label2,
          );

          return AnimatedContainer(
            duration: CruMotion.of(context, CruMotion.fast),
            curve: CruMotion.curve,
            height: CruSize.navItem,
            width: collapsed ? 48 : null,
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 10),
            decoration: ShapeDecoration(
              color: fill,
              shape: cruShape(CruRadius.control),
              shadows: selected ? c.inkShadow : null,
            ),
            child: collapsed
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      icon,
                      if (badge != null)
                        const Positioned(
                          top: 8,
                          right: 10,
                          child: CruStatusDot(
                            CruDotKind.waiting,
                            size: CruSize.smallDot,
                          ),
                        ),
                    ],
                  )
                : Row(
                    children: [
                      icon,
                      const SizedBox(width: CruSpace.s12),
                      Expanded(
                        child: Text(
                          item.label,
                          style: CruType.nav
                              .copyWith(
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              )
                              .tint(selected ? CruBrand.white : c.label),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (badge != null) ...[
                        const CruStatusDot(
                          CruDotKind.waiting,
                          size: CruSize.smallDot,
                        ),
                        const SizedBox(width: CruSpace.s6),
                        Text(
                          '$badge',
                          style: CruType.subhead.w500.tabular.tint(
                            selected
                                ? CruBrand.white.withValues(alpha: 0.9)
                                : c.label2,
                          ),
                        ),
                      ],
                    ],
                  ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN PROFILE BUTTON WITH ACCOUNT MENU
// ─────────────────────────────────────────────────────────────────────────────

class _AdminProfileButton extends ConsumerWidget {
  const _AdminProfileButton({
    required this.name,
    required this.email,
    required this.collapsed,
    required this.onHelp,
    required this.onLogout,
    required this.onToggleCollapsed,
  });

  final String name;
  final String email;
  final bool collapsed;
  final VoidCallback onHelp;
  final VoidCallback onLogout;
  final VoidCallback onToggleCollapsed;

  Future<void> _openMenu(BuildContext context, WidgetRef ref) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final c = context.cru;
    final currentMode = ref.read(appearanceModeProvider);

    final chosen = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        topLeft.dy - 8,
        overlay.size.width - topLeft.dx - 220,
        overlay.size.height - topLeft.dy + 8,
      ),
      constraints: const BoxConstraints(minWidth: 230),
      items: [
        // Theme / Appearance Section
        PopupMenuItem<VoidCallback>(
          enabled: false,
          height: 28,
          child: Text('Appearance', style: CruType.groupLabel.tint(c.label3)),
        ),
        for (final m in AppearanceMode.values)
          PopupMenuItem<VoidCallback>(
            value: () => ref.read(appearanceModeProvider.notifier).select(m),
            height: CruSize.control,
            child: Row(
              children: [
                CruIcon(
                  switch (m) {
                    AppearanceMode.auto => CruIcons.autoMode,
                    AppearanceMode.day => CruIcons.sun,
                    AppearanceMode.evening => CruIcons.moon,
                  },
                  size: 18,
                  color: c.label2,
                ),
                const SizedBox(width: CruSpace.s10),
                Expanded(
                  child: Text(
                    m == AppearanceMode.auto ? 'Auto (Day/Evening)' : m.label,
                    style: CruType.text.tint(c.label),
                  ),
                ),
                if (m == currentMode)
                  CruIcon(CruIcons.check, size: 16, color: c.accentText),
              ],
            ),
          ),
        const PopupMenuDivider(),

        // Quick Jump to Doctor Clinic Shell
        PopupMenuItem<VoidCallback>(
          value: () {
            DemoSessionService.startDemoSession();
            context.go('/dashboard');
          },
          height: CruSize.control,
          child: Row(
            children: [
              CruIcon(CruIcons.arrowUpRight, size: 18, color: c.accentText),
              const SizedBox(width: CruSpace.s10),
              Expanded(
                child: Text('Doctor Clinic Portal', style: CruType.text.tint(c.label)),
              ),
            ],
          ),
        ),

        // Shortcuts & Help
        PopupMenuItem<VoidCallback>(
          value: onHelp,
          height: CruSize.control,
          child: Row(
            children: [
              CruIcon(CruIcons.help, size: 18, color: c.label2),
              const SizedBox(width: CruSpace.s10),
              Expanded(
                child: Text('Shortcuts & Help', style: CruType.text.tint(c.label)),
              ),
            ],
          ),
        ),

        // Sidebar Collapse
        PopupMenuItem<VoidCallback>(
          value: onToggleCollapsed,
          height: CruSize.control,
          child: Row(
            children: [
              CruIcon(CruIcons.sidebar, size: 18, color: c.label2),
              const SizedBox(width: CruSpace.s10),
              Expanded(
                child: Text(
                  collapsed ? 'Expand Sidebar' : 'Collapse Sidebar',
                  style: CruType.text.tint(c.label),
                ),
              ),
              const CruKeycap('Ctrl B'),
            ],
          ),
        ),

        const PopupMenuDivider(),

        // Log out
        PopupMenuItem<VoidCallback>(
          value: onLogout,
          height: CruSize.control,
          child: Row(
            children: [
              CruIcon(CruIcons.logout, size: 18, color: c.redText),
              const SizedBox(width: CruSpace.s10),
              Expanded(
                child: Text('Sign Out', style: CruType.text.tint(c.redText)),
              ),
            ],
          ),
        ),
      ],
    );
    chosen?.call();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final avatar = CruMonogram(name: name, size: 34, background: c.track);

    return CruPressable(
      onTap: () => _openMenu(context, ref),
      semanticLabel: '$name. Super Admin account and settings',
      tooltip: collapsed ? '$name ($email)' : null,
      scaleOnPress: false,
      builder: (ctx, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        padding: collapsed
            ? const EdgeInsets.all(4)
            : const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: ShapeDecoration(
          color: hovered
              ? (c.isEvening ? c.inset : c.hoverFill)
              : Colors.transparent,
          shape: cruShape(CruRadius.switcher),
        ),
        child: collapsed
            ? avatar
            : Row(
                children: [
                  avatar,
                  const SizedBox(width: CruSpace.s10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: CruType.profileName.tint(c.label),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Root Platform Admin',
                          style: CruType.caption.tint(c.label2),
                        ),
                      ],
                    ),
                  ),
                  CruIcon(CruIcons.more, size: 16, color: c.label3),
                ],
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHORTCUT ROW IN HELP DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _ShortcutRow extends StatelessWidget {
  final String keys;
  final String description;

  const _ShortcutRow({required this.keys, required this.description});

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: c.inset,
              borderRadius: BorderRadius.circular(CruRadius.keycap),
              border: Border.all(color: c.hairline),
            ),
            child: Text(
              keys,
              style: CruType.caption.w600.tabular.tint(c.label),
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Text(
              description,
              style: CruType.text.tint(c.label2),
            ),
          ),
        ],
      ),
    );
  }
}
