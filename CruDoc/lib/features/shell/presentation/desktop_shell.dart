import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:doctor_management_app/core/services/auth_service.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/shell/components/cru_sidebar.dart';
import 'package:doctor_management_app/features/shell/components/mobile_feature_disabled_view.dart';
import 'package:doctor_management_app/features/shell/components/specialty_switcher_dialog.dart';
import 'package:doctor_management_app/features/shell/data/desktop_shell_preferences.dart';
import 'package:doctor_management_app/features/shell/presentation/desktop_shell_layout.dart';
import 'package:doctor_management_app/features/chatbot/widgets/draggable_floating_chatbot_button.dart';
import 'package:doctor_management_app/features/settings/data/appearance_preferences.dart';
import 'package:doctor_management_app/features/settings/data/appearance_provider.dart';
import 'package:doctor_management_app/features/settings/presentation/desktop_settings_screen.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:doctor_management_app/features/patients/presentation/desktop_patient_records_screen.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_revenue_screen.dart';
import 'package:doctor_management_app/features/inventory/presentation/desktop_inventory_list_screen.dart';
import 'package:doctor_management_app/features/inventory/presentation/inventory_alert_listener.dart';
import 'package:doctor_management_app/features/appointments/presentation/desktop_events_screen.dart';
import 'package:doctor_management_app/features/campaigns/presentation/desktop_campaigns_screen.dart';
import 'package:doctor_management_app/features/scribe/presentation/desktop_scribe_screen.dart';
import 'package:doctor_management_app/features/queue/presentation/desktop_queue_screen.dart';
import 'package:doctor_management_app/features/subscription/presentation/feature_upgrade_sheet.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Intent for the Ctrl+B sidebar toggle shortcut.
class _ToggleSidebarIntent extends Intent {
  const _ToggleSidebarIntent();
}

/// Intent for the Ctrl+1..Ctrl+8 tab-switch shortcuts.
class _NavigateToTabIntent extends Intent {
  const _NavigateToTabIntent(this.index);
  final int index;
}

/// Ctrl/⌘ K: focus "Search patients or ask CruDoc".
class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

/// Enter on the dashboard: start the Up next consultation.
class _StartUpNextIntent extends Intent {
  const _StartUpNextIntent();
}

/// Only takes Enter when the dashboard is showing and nothing else has
/// focus. Otherwise the key passes through, so text fields and buttons on
/// every screen keep their own Enter.
class _StartUpNextAction extends Action<_StartUpNextIntent> {
  _StartUpNextAction(this.shell);

  final _DesktopShellState shell;

  @override
  bool isEnabled(_StartUpNextIntent intent) =>
      shell._currentIndex == DesktopTab.dashboard &&
      FocusManager.instance.primaryFocus == shell._shortcutsFocusNode;

  @override
  Object? invoke(_StartUpNextIntent intent) {
    shell._dashboardKey.currentState?.startUpNext();
    return null;
  }
}

/// Desktop layout: Calm Clinical sidebar on a neutral canvas.
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key});

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  final DesktopShellPreferences _shellPrefs = DesktopShellPreferences();
  final FocusNode _shortcutsFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'dashboard search');
  final GlobalKey<DashboardScreenState> _dashboardKey = GlobalKey();

  /// Created once so shell rebuilds (tab changes, appearance switches)
  /// don't resubscribe to Firestore.
  final Stream<List<String>> _enabledModules =
      DoctorFeatureGuard.watchEnabledModules();

  int _currentIndex = DesktopTab.dashboard;
  bool _isSidebarExpanded = true;

  @override
  void initState() {
    super.initState();
    _restorePreferences();
  }

  @override
  void dispose() {
    _shortcutsFocusNode.dispose();
    _searchFocusNode.dispose();
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

  /// Tab titles in index order (indices are shared with
  /// [DoctorFeatureGuard] and the Ctrl+1..8 shortcuts).
  static const List<String> _labels = [
    'Dashboard',
    'Patients',
    'Inventory',
    'Revenue',
    'Appointments',
    'Campaigns',
    'Scribe',
    'Queue',
  ];

  static const List<IconData> _icons = [
    Icons.grid_view_rounded,
    Icons.groups_rounded,
    Icons.inventory_2_outlined,
    Icons.payments_outlined,
    Icons.calendar_today_outlined,
    Icons.campaign_rounded,
    Icons.mic_rounded,
    Icons.format_list_numbered_rounded,
  ];

  void _onNavTap(int index) {
    if (index < 0 || index >= _labels.length) return;
    setState(() => _currentIndex = index);
    unawaited(_shellPrefs.setLastTabIndex(index));
  }

  void _focusSearch() {
    if (_currentIndex != DesktopTab.dashboard) _onNavTap(DesktopTab.dashboard);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  /// Builds only the screen that's actually selected.
  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return DashboardScreen(
          key: _dashboardKey,
          onNavigateToTab: _onNavTap,
          searchFocusNode: _searchFocusNode,
        );
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
      case 6:
        return const DesktopScribeScreen();
      case 7:
        return const DesktopQueueScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  /// Keyboard shortcuts scoped to the desktop shell: Ctrl+B toggles the
  /// sidebar, Ctrl+1..Ctrl+8 jump to a tab, Ctrl/⌘ K focuses search and
  /// Enter on the dashboard starts the Up next consultation.
  Map<ShortcutActivator, Intent> get _keyboardShortcuts => {
    const SingleActivator(LogicalKeyboardKey.keyB, control: true):
        const _ToggleSidebarIntent(),
    for (var i = 0; i < _labels.length && i < 8; i++)
      SingleActivator(_digitKeyFor(i), control: true): _NavigateToTabIntent(i),
    const SingleActivator(LogicalKeyboardKey.keyK, control: true):
        const _FocusSearchIntent(),
    if (defaultTargetPlatform == TargetPlatform.macOS)
      const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
          const _FocusSearchIntent(),
    const SingleActivator(LogicalKeyboardKey.enter): const _StartUpNextIntent(),
  };

  static LogicalKeyboardKey _digitKeyFor(int index) {
    const digitKeys = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
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
          _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
            onInvoke: (intent) {
              _focusSearch();
              return null;
            },
          ),
          _StartUpNextIntent: _StartUpNextAction(this),
        },
        child: Focus(
          focusNode: _shortcutsFocusNode,
          autofocus: true,
          child: _buildContent(context),
        ),
      ),
    );
  }

  SidebarCallbacks _sidebarCallbacks(BuildContext context) {
    final root = Navigator.of(context, rootNavigator: true).context;
    return SidebarCallbacks(
      onNavigate: _onNavTap,
      onClinicSwitcher: () => showSpecialtySwitcherDialog(root),
      onUpgrade: () {
        final info = ref.read(subscriptionInfoProvider).value;
        if (info != null) {
          FeatureUpgradeSheet.show(root, subscriptionInfo: info);
        }
      },
      onSettings: () => Navigator.of(root).push(
        MaterialPageRoute(builder: (_) => const DesktopSettingsScreen()),
      ),
      onHelp: () => showDesktopShellHelpDialog(root),
      onLogout: () async {
        try {
          await AuthService().signOut();
        } catch (_) {}
        if (!context.mounted) return;
        context.go('/auth');
      },
      onToggleCollapsed: _toggleSidebar,
      appearanceMenu: _appearanceMenu,
    );
  }

  Widget _buildContent(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: _enabledModules,
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
        final isDashboard = _currentIndex == DesktopTab.dashboard;

        final width = MediaQuery.sizeOf(context).width;
        final forcedCompact = width < CruBreakpoint.compact;
        final collapsed = forcedCompact || !_isSidebarExpanded;

        Widget content = isTabEnabled
            ? _buildScreen(_currentIndex)
            : MobileFeatureDisabledView(
                featureTitle: DoctorFeatureGuard.getDesktopTabTitle(
                  _currentIndex,
                ),
                icon: _icons[_currentIndex],
                onBackToDashboard: () => _onNavTap(0),
              );
        if (!isDashboard) {
          // Other screens keep their own layout, on the Day theme, with
          // the spacing they had before.
          content = Theme(
            data: CruTheme.day(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 16, 16),
              child: SizedBox.expand(child: content),
            ),
          );
        }

        // Day or Evening for the shell chrome and the dashboard (Auto by
        // default). Other screens are wrapped in Day above.
        final appearance = ref.watch(resolvedAppearanceProvider);

        return InventoryAlertListener(
          child: AnimatedTheme(
            data: CruTheme.of(appearance),
            duration: CruMotion.of(context),
            curve: CruMotion.curve,
            child: Builder(
              builder: (context) => Scaffold(
                backgroundColor: context.cru.canvas,
                body: DesktopShellLayout(
                  sidebar: CruSidebar(
                    currentTab: _currentIndex,
                    collapsed: collapsed,
                    canExpand: !forcedCompact,
                    callbacks: _sidebarCallbacks(context),
                  ),
                  content: content,
                  // The dashboard reaches the assistant through "Ask
                  // CruDoc" in its search; other screens keep the
                  // floating button.
                  overlay: isDashboard
                      ? null
                      : const DraggableFloatingChatbotButton(
                          initialBottom: 32,
                          initialRight: 32,
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Auto / Day / Evening entries at the top of the account menu.
  List<PopupMenuEntry<VoidCallback>> _appearanceMenu(CruColors c) {
    final current = ref.read(appearanceModeProvider);
    CruIconData iconFor(AppearanceMode m) => switch (m) {
          AppearanceMode.auto => CruIcons.autoMode,
          AppearanceMode.day => CruIcons.sun,
          AppearanceMode.evening => CruIcons.moon,
        };
    return [
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
              CruIcon(iconFor(m), size: 18, color: c.label2),
              const SizedBox(width: CruSpace.s10),
              Expanded(
                child: Text(
                  m == AppearanceMode.auto
                      ? 'Auto (Evening from 5 PM)'
                      : m.label,
                  style: CruType.text.tint(c.label),
                ),
              ),
              if (m == current)
                CruIcon(CruIcons.check, size: 16, strokeWidth: 2.2,
                    color: c.accentText),
            ],
          ),
        ),
      const PopupMenuDivider(),
    ];
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

