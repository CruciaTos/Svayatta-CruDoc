import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

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
  const _AdminNavGroup({required this.label, required this.items});

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

    return AnimatedTheme(
      data: theme,
      duration: CruMotion.of(context),
      curve: CruMotion.curve,
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
            child: Builder(builder: (ctx) => _buildShell(ctx)),
          ),
        ),
      ),
    );
  }

  Widget _buildShell(BuildContext context) {
    final appearance = ref.watch(resolvedAppearanceProvider);
    final isEvening = appearance == CruAppearance.evening;
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
      return Scaffold(
        backgroundColor: c.canvas,
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
              tooltip: isEvening
                  ? 'Switch to Day Mode'
                  : 'Switch to Night Mode',
              icon: CruIcon(
                isEvening ? CruIcons.moon : CruIcons.sun,
                size: 18,
                color: isEvening ? c.accentText : c.amberText,
              ),
              onPressed: () =>
                  ref.read(appearanceModeProvider.notifier).toggle(),
            ),
            IconButton(
              tooltip: 'Return to Clinic Portal',
              icon: CruIcon(
                CruIcons.arrowUpRight,
                size: 18,
                color: c.accentText,
              ),
              onPressed: () {
                DemoSessionService.startDemoSession();
                context.go('/dashboard');
              },
            ),
          ],
        ),
        drawer: Drawer(backgroundColor: c.surface, child: sidebar),
        body: CruAmbientBackground(
          isEvening: isEvening,
          child: _buildContent(uiState.selectedTab),
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.canvas,
      body: CruAmbientBackground(
        isEvening: isEvening,
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
                  Expanded(child: _buildContent(uiState.selectedTab)),
                ],
              ),
            ),
          ],
        ),
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
              _ShortcutRow(
                keys: 'Ctrl + B',
                description: 'Toggle Sidebar Collapse',
              ),
              _ShortcutRow(
                keys: 'Ctrl + K',
                description: 'Focus Global Search Bar',
              ),
              _ShortcutRow(
                keys: 'Ctrl + 1',
                description: 'Jump to Dashboard Overview',
              ),
              _ShortcutRow(
                keys: 'Ctrl + 2',
                description: 'Jump to Doctors & Clinics',
              ),
              _ShortcutRow(
                keys: 'Ctrl + 3',
                description: 'Jump to Feature Modules',
              ),
              _ShortcutRow(
                keys: 'Ctrl + 4',
                description: 'Jump to Analytics & Growth',
              ),
              _ShortcutRow(
                keys: 'Ctrl + 5',
                description: 'Jump to API Usage & Cost',
              ),
              _ShortcutRow(
                keys: 'Ctrl + 6',
                description: 'Jump to Security & Audit Logs',
              ),
              _ShortcutRow(
                keys: 'Ctrl + 7',
                description: 'Jump to Support Desk',
              ),
              _ShortcutRow(
                keys: 'Ctrl + 8',
                description: 'Jump to Platform Settings',
              ),
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
        title: Text(
          'Sign Out of Super Admin?',
          style: CruType.title.tint(c.label),
        ),
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

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        children: [
          // Breadcrumb Trail
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('CruDoc Admin', style: CruType.subhead.tint(c.label3)),
              const SizedBox(width: CruSpace.s8),
              CruIcon(CruIcons.chevronRight, size: 14, color: c.label3),
              const SizedBox(width: CruSpace.s8),
              Text(selectedTab.label, style: CruType.headline.tint(c.label)),
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
                    children: const [CruKeycap('Ctrl K')],
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 12,
                ),
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
              shape: cruShape(
                CruRadius.full,
                side: BorderSide(color: c.hairline),
              ),
              shadows: const [],
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

          // Interactive Night / Day Mode Toggle Button
          CruPressable(
            onTap: () => ref.read(appearanceModeProvider.notifier).toggle(),
            tooltip: c.isEvening
                ? 'Night Mode active (Click to switch to Day Mode)'
                : 'Day Mode active (Click to switch to Night Mode)',
            builder: (context, hovered) => Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: ShapeDecoration(
                color: hovered ? c.hoverFill : c.surface,
                shape: cruShape(
                  CruRadius.full,
                  side: BorderSide(
                    color: c.isEvening
                        ? c.accent.withValues(alpha: 0.35)
                        : c.hairline,
                  ),
                ),
                shadows: const [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CruIcon(
                    c.isEvening ? CruIcons.moon : CruIcons.sun,
                    size: 14,
                    color: c.isEvening ? c.accentText : c.amberText,
                  ),
                  const SizedBox(width: CruSpace.s6),
                  Text(
                    c.isEvening ? 'Night Mode' : 'Day Mode',
                    style: CruType.caption.w600.tint(c.label),
                  ),
                ],
              ),
            ),
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

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: isCollapsed ? 0.0 : 1.0),
      duration: CruMotion.of(context),
      curve: CruMotion.curve,
      builder: (context, progress, _) {
        final width = lerpDouble(CruSize.sidebarCollapsed, CruSize.sidebar, progress)!;
        final outerPadding = EdgeInsets.lerp(
          const EdgeInsets.fromLTRB(8, 12, 4, 12),
          const EdgeInsets.fromLTRB(12, 12, 4, 12),
          progress,
        )!;
        final innerPadding = EdgeInsets.lerp(
          const EdgeInsets.fromLTRB(6, 16, 6, 12),
          const EdgeInsets.fromLTRB(14, 18, 14, 14),
          progress,
        )!;

        return Container(
          width: width,
          color: Colors.transparent,
          padding: outerPadding,
          child: DecoratedBox(
            decoration: c.isEvening
                ? ShapeDecoration(
                    color: const Color(0xFF111214),
                    shape: cruShape(CruRadius.card),
                    shadows: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 16,
                        spreadRadius: 0,
                        offset: Offset(0, 4),
                      ),
                      BoxShadow(
                        color: Color(0x40000000),
                        blurRadius: 6,
                        offset: Offset(0, 1),
                      ),
                    ],
                  )
                : ShapeDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1E3A8A), Color(0xFF1F4FCB)],
                    ),
                    shape: cruShape(CruRadius.card),
                  ),
            child: Padding(
              padding: innerPadding,
              child: Semantics(
                container: true,
                label: 'Super Admin navigation',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand Header with Collapser
                    _AdminBrand(
                      collapsed: isCollapsed,
                      progress: progress,
                      onToggleCollapsed: onToggleCollapsed,
                    ),

                    const SizedBox(height: CruSpace.s14),

                    // Platform Master Scope Switcher Tile
                    _PlatformScopeTile(
                      collapsed: isCollapsed,
                      progress: progress,
                    ),

                    const SizedBox(height: CruSpace.s14),

                    // Navigation Groups
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (
                              var g = 0;
                              g < _SuperAdminShellState._navGroups.length;
                              g++
                            ) ...[
                              if (g > 0) const SizedBox(height: CruSpace.s16),
                              if (progress > 0.1)
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    lerpDouble(4, 10, progress)!,
                                    0,
                                    10,
                                    6,
                                  ),
                                  child: Opacity(
                                    opacity: ((progress - 0.25) / 0.75).clamp(0.0, 1.0),
                                    child: Transform.translate(
                                      offset: Offset((1.0 - progress) * -12.0, 0),
                                      child: Text(
                                        _SuperAdminShellState._navGroups[g].label,
                                        style: c.isEvening
                                            ? CruType.groupLabel.tint(c.label3)
                                            : CruType.groupLabel.tint(
                                                CruBrand.white.withValues(alpha: 0.72),
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              for (final item
                                  in _SuperAdminShellState._navGroups[g].items) ...[
                                const SizedBox(height: CruSpace.s2),
                                _AdminSidebarItemWidget(
                                  item: item,
                                  selected: selectedTab == item.tab,
                                  collapsed: isCollapsed,
                                  progress: progress,
                                  badge: switch (item.tab) {
                                    SuperAdminTab.doctors when pendingDoctors > 0 =>
                                      pendingDoctors,
                                    SuperAdminTab.support when openTickets > 0 =>
                                      openTickets,
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
                      progress: progress,
                      onHelp: onHelp,
                      onLogout: onLogout,
                      onToggleCollapsed: onToggleCollapsed,
                    ),

                    if (isCollapsed && progress < 0.75) ...[
                      Opacity(
                        opacity: ((0.75 - progress) / 0.75).clamp(0.0, 1.0),
                        child: Column(
                          children: [
                            const SizedBox(height: CruSpace.s8),
                            CruPressable(
                              onTap: onToggleCollapsed,
                              tooltip: 'Expand sidebar (Ctrl+B)',
                              builder: (ctx, hovered) => Container(
                                width: 32,
                                height: 32,
                                alignment: Alignment.center,
                                decoration: ShapeDecoration(
                                  color: hovered
                                      ? (c.isEvening
                                          ? c.inset
                                          : Colors.white.withValues(alpha: 0.12))
                                      : Colors.transparent,
                                  shape: cruShape(8),
                                ),
                                child: CruIcon(
                                  CruIcons.chevronRight,
                                  size: 16,
                                  color: c.isEvening ? c.label2 : CruBrand.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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

// ─────────────────────────────────────────────────────────────────────────────
// BRAND MARK & BRAND HEADER
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

class _AdminBrand extends StatelessWidget {
  const _AdminBrand({
    required this.collapsed,
    required this.progress,
    required this.onToggleCollapsed,
  });

  final bool collapsed;
  final double progress;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final curveProgress = Curves.easeInOutCubic.transform(progress);
    final impulse = math.sin(progress * math.pi);
    // Collapsed: centered in 48 -> (48 - 32) / 2 = 8.0.
    final markX = lerpDouble(8.0, 8.0, curveProgress)! + impulse * 3.0;
    final markScale = 1.0 + impulse * 0.10;

    return Semantics(
      label: 'CruDoc Super Admin Console',
      child: SizedBox(
        height: CruSize.appMark,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: markX,
              top: 0,
              child: Transform.scale(
                scale: markScale,
                child: const _AdminBrandMark(size: CruSize.appMark),
              ),
            ),
            if (progress > 0.15)
              Positioned(
                left: 8.0 + CruSize.appMark + CruSpace.s10,
                right: 32.0,
                top: 0,
                bottom: 0,
                child: Opacity(
                  opacity: ((progress - 0.25) / 0.75).clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset((1.0 - progress) * 16.0, 0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CruDoc',
                          style: CruType.wordmark.tint(
                            c.isEvening ? c.label : CruBrand.white,
                          ),
                        ),
                        Text(
                          'SUPER ADMIN CONSOLE',
                          style: CruType.caption.w600.tint(
                            c.isEvening
                                ? c.accentText
                                : CruBrand.white.withValues(alpha: 0.8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (progress > 0.25)
              Positioned(
                right: 0,
                top: (CruSize.appMark - 28.0) / 2,
                child: Opacity(
                  opacity: ((progress - 0.25) / 0.75).clamp(0.0, 1.0),
                  child: CruPressable(
                    onTap: onToggleCollapsed,
                    tooltip: 'Collapse sidebar (Ctrl+B)',
                    builder: (ctx, hovered) => Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        color: hovered
                            ? (c.isEvening
                                ? c.inset
                                : Colors.white.withValues(alpha: 0.12))
                            : Colors.transparent,
                        shape: cruShape(8),
                      ),
                      child: CruIcon(
                        CruIcons.chevronLeft,
                        size: 16,
                        color: c.label2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PLATFORM SCOPE TILE
// ─────────────────────────────────────────────────────────────────────────────

class _PlatformScopeTile extends StatelessWidget {
  const _PlatformScopeTile({
    required this.collapsed,
    this.progress = 1.0,
  });
  final bool collapsed;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final curveProgress = Curves.easeInOutCubic.transform(progress);
    final impulse = math.sin(progress * math.pi);
    // Collapsed: centered in 48 -> (48 - 32) / 2 = 8.0.
    // Expanded: left docked at 10.0.
    final tileX = lerpDouble(8.0, 10.0, curveProgress)! + impulse * 3.0;
    final tileScale = 1.0 + impulse * 0.10;
    final tileHeight = lerpDouble(40.0, 52.0, curveProgress)!;

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

    return Tooltip(
      message: collapsed ? 'Master Platform Scope' : '',
      child: AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        height: tileHeight,
        decoration: ShapeDecoration(
          color: c.surface,
          shape: cruShape(
            CruRadius.switcher,
            side: BorderSide(color: c.hairline),
          ),
          shadows: c.cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: tileX,
              top: (tileHeight - CruSize.clinicTile) / 2,
              child: Transform.scale(
                scale: tileScale,
                child: icon,
              ),
            ),
            if (progress > 0.2)
              Positioned(
                left: 10.0 + CruSize.clinicTile + CruSpace.s10,
                right: 28.0,
                top: 0,
                bottom: 0,
                child: Opacity(
                  opacity: ((progress - 0.3) / 0.7).clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset((1.0 - progress) * 16.0, 0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Master Scope',
                          style: CruType.callout
                              .copyWith(height: 18 / 14)
                              .tint(c.label),
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
                ),
              ),
            if (progress > 0.35)
              Positioned(
                right: 12.0,
                top: (tileHeight - 6.0) / 2,
                child: Opacity(
                  opacity: ((progress - 0.35) / 0.65).clamp(0.0, 1.0),
                  child: const CruStatusDot(CruDotKind.done, size: 6),
                ),
              ),
          ],
        ),
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
    this.progress = 1.0,
  });

  final _AdminNavItem item;
  final bool selected;
  final bool collapsed;
  final int? badge;
  final VoidCallback onTap;
  final double progress;

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
          final Color fill;
          final Color iconColor;
          final Color labelColor;
          final Color badgeColor;
          final List<BoxShadow>? shadows;

          if (c.isEvening) {
            // Dark mode: Black sidebar, active state with blue and white text/icon
            fill = selected
                ? c.accent
                : (hovered ? c.inset : Colors.transparent);
            iconColor = selected ? CruBrand.white : c.label2;
            labelColor = selected ? CruBrand.white : c.label;
            badgeColor = selected
                ? CruBrand.white.withValues(alpha: 0.9)
                : c.label2;
            shadows = selected ? c.inkShadow : null;
          } else {
            // Light mode: Blue gradient sidebar, white active item, blue icon/label
            fill = selected
                ? CruBrand.white
                : (hovered
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.transparent);
            iconColor = selected ? c.accent : CruBrand.white;
            labelColor = selected ? c.accent : CruBrand.white;
            badgeColor = selected
                ? c.accent.withValues(alpha: 0.9)
                : CruBrand.white.withValues(alpha: 0.9);
            shadows = null;
          }

          final curveProgress = Curves.easeInOutCubic.transform(progress);
          final impulse = math.sin(progress * math.pi);
          // Collapsed: centered in 48 -> (48 - 20) / 2 = 14.0.
          // Expanded: left docked at 10.0.
          // Dynamic impulse glides the icon physically across space with dynamic lift and settling
          final iconX = lerpDouble(14.0, 10.0, curveProgress)! + impulse * 4.0;
          final iconScale = 1.0 + impulse * 0.15;
          final iconShiftY = -impulse * 1.5;

          final icon = CruIcon(
            item.icon,
            size: CruSize.navIcon,
            color: iconColor,
          );

          return AnimatedContainer(
            duration: CruMotion.of(context, CruMotion.fast),
            curve: CruMotion.curve,
            height: CruSize.navItem,
            decoration: ShapeDecoration(
              color: fill,
              shape: cruShape(
                CruRadius.control,
                side: BorderSide.none,
              ),
              shadows: shadows,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Icon that physically glides dynamically
                Positioned(
                  left: iconX,
                  top: (CruSize.navItem - CruSize.navIcon) / 2 + iconShiftY,
                  child: Transform.scale(
                    scale: iconScale,
                    child: icon,
                  ),
                ),
                // Collapsed status dot
                if (badge != null && progress < 0.6)
                  Positioned(
                    left: iconX + 13.0,
                    top: 7.0 + iconShiftY,
                    child: Opacity(
                      opacity: ((0.6 - progress) / 0.6).clamp(0.0, 1.0),
                      child: const CruStatusDot(
                        CruDotKind.waiting,
                        size: CruSize.smallDot,
                      ),
                    ),
                  ),
                // Expanded label and count badge
                if (progress > 0.15)
                  Positioned(
                    left: 10.0 + CruSize.navIcon + CruSpace.s12,
                    right: 10.0,
                    top: 0,
                    bottom: 0,
                    child: Opacity(
                      opacity: ((progress - 0.25) / 0.75).clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset((1.0 - progress) * 20.0, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.label,
                                style: CruType.nav
                                    .copyWith(
                                      fontWeight: selected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                    )
                                    .tint(labelColor),
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
                                style: CruType.subhead.w500.tabular.tint(badgeColor),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
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
    this.progress = 1.0,
  });

  final String name;
  final String email;
  final bool collapsed;
  final VoidCallback onHelp;
  final VoidCallback onLogout;
  final VoidCallback onToggleCollapsed;
  final double progress;

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
                child: Text(
                  'Doctor Clinic Portal',
                  style: CruType.text.tint(c.label),
                ),
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
                child: Text(
                  'Shortcuts & Help',
                  style: CruType.text.tint(c.label),
                ),
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
    final curveProgress = Curves.easeInOutCubic.transform(progress);
    final impulse = math.sin(progress * math.pi);
    // Collapsed: centered in 48 -> (48 - 34) / 2 = 7.0.
    // Expanded: left docked at 10.0.
    final avatarX = lerpDouble(7.0, 10.0, curveProgress)! + impulse * 3.0;
    final avatarScale = 1.0 + impulse * 0.10;
    final cardHeight = lerpDouble(42.0, 52.0, curveProgress)!;

    final avatar = CruMonogram(
      name: name,
      size: 34,
      background: Colors.white,
      foreground: c.accent,
    );

    return CruPressable(
      onTap: () => _openMenu(context, ref),
      semanticLabel: '$name. Super Admin account and settings',
      tooltip: collapsed ? '$name ($email)' : null,
      scaleOnPress: false,
      builder: (ctx, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        height: cardHeight,
        decoration: ShapeDecoration(
          color: c.isEvening
              ? (hovered
                  ? c.accent.withValues(alpha: 0.9)
                  : c.accent)
              : Colors.white,
          shape: cruShape(
            CruRadius.switcher,
            side: BorderSide(
              color: c.isEvening
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.2),
            ),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: avatarX,
              top: (cardHeight - 34.0) / 2,
              child: Transform.scale(
                scale: avatarScale,
                child: avatar,
              ),
            ),
            if (progress > 0.2)
              Positioned(
                left: 10.0 + 34.0 + CruSpace.s10,
                right: 32.0,
                top: 0,
                bottom: 0,
                child: Opacity(
                  opacity: ((progress - 0.25) / 0.75).clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset((1.0 - progress) * 16.0, 0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: CruType.profileName.tint(
                            c.isEvening
                                ? CruBrand.white
                                : const Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Root Platform Admin',
                          style: CruType.caption.tint(
                            c.isEvening
                                ? CruBrand.white.withValues(alpha: 0.85)
                                : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (progress > 0.35)
              Positioned(
                right: 10.0,
                top: (cardHeight - 16.0) / 2,
                child: Opacity(
                  opacity: ((progress - 0.35) / 0.65).clamp(0.0, 1.0),
                  child: CruIcon(
                    CruIcons.more,
                    size: 16,
                    color: c.isEvening
                        ? CruBrand.white
                        : const Color(0xFF475569),
                  ),
                ),
              ),
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
            child: Text(description, style: CruType.text.tint(c.label2)),
          ),
        ],
      ),
    );
  }
}
