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
import 'package:doctor_management_app/features/patients/presentation/patients_screen.dart';
import 'package:doctor_management_app/features/revenue/presentation/revenue_overview_screen.dart';
import 'package:doctor_management_app/features/inventory/presentation/inventory_screen.dart';
import 'package:doctor_management_app/features/inventory/presentation/inventory_alert_listener.dart';
import 'package:doctor_management_app/features/appointments/presentation/appointments_screen.dart';
import 'package:doctor_management_app/features/campaigns/presentation/desktop_campaigns_screen.dart';
import 'package:doctor_management_app/features/scribe/presentation/desktop_scribe_screen.dart';
import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/subscription/presentation/feature_upgrade_sheet.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/procedures_screen.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/sterilization_screen.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/treatment_plans_screen.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/records/recalls.dart';
import 'package:doctor_management_app/features/dental/specialties/dental_not_built.dart';
import 'package:doctor_management_app/features/dental/specialties/perio/perio_patients_screen.dart';
import 'package:doctor_management_app/features/radiology/presentation/referrers_screen.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/reports_screen.dart';
import 'package:doctor_management_app/features/radiology/presentation/worklist_screen.dart';

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
    // Lets "Open patient" (and other screens) switch tabs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(shellNavigatorProvider.notifier).state = (tab) {
        if (!mounted) return false;
        _onNavTap(tab);
        return true;
      };
    });
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
        _currentIndex = _resolveTab(lastTabIndex);
        ref.read(shellCurrentTabProvider.notifier).state = _currentIndex;
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
    'Schedule',
    'Campaigns',
    'Scribe',
    'Queue',
    'Settings',
    'Treatment plans',
    'Sterilization',
    'Procedures',
    'Worklist',
    'Reports',
    'Referrers',
    'Recalls',
    'Perio patients',
    'Root canals',
    'Referrals',
    'Children',
    'Biopsies',
    'Lesions',
    'Forms',
    'Sedation cases',
    'Lab cases',
    'Ortho patients',
    'Camps',
    'Population',
    'Surgeries',
    'Implants',
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
    Icons.settings_outlined,
    Icons.assignment_outlined,
    Icons.verified_user_outlined,
    Icons.list_alt_rounded,
    Icons.view_list_rounded,
    Icons.description_outlined,
    Icons.person_pin_outlined,
    Icons.notifications_outlined,
    Icons.health_and_safety_outlined,
    Icons.healing_outlined,
    Icons.forward_to_inbox_outlined,
    Icons.child_care_outlined,
    Icons.biotech_outlined,
    Icons.report_problem_outlined,
    Icons.fact_check_outlined,
    Icons.medication_outlined,
    Icons.inventory_outlined,
    Icons.align_horizontal_center_outlined,
    Icons.location_city_outlined,
    Icons.groups_outlined,
    Icons.content_cut_outlined,
    Icons.build_outlined,
  ];

  /// The queue lives in the Schedule tab as its Live view: anything that
  /// opens the queue tab (dashboard, Ctrl+8, a saved tab) lands there.
  int _resolveTab(int index) {
    if (index != DesktopTab.queue) return index;
    ref.read(apptsControllerProvider.notifier).setView(ApptsView.live);
    return DesktopTab.appointments;
  }

  void _onNavTap(int index) {
    if (index < 0 || index >= _labels.length) return;
    index = _resolveTab(index);
    ref.read(shellCurrentTabProvider.notifier).state = index;
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
        return const PatientsScreen();
      case 2:
        return const InventoryScreen();
      case 3:
        return const RevenueOverviewScreen();
      case 4:
        return const AppointmentsScreen();
      case 5:
        return const DesktopCampaignsScreen();
      case 6:
        return const DesktopScribeScreen();
      case 7:
        // Never selected (see _resolveTab).
        return const AppointmentsScreen();
      case DesktopTab.settings:
        return const DesktopSettingsScreen();
      case DesktopTab.treatmentPlans:
        return const TreatmentPlansScreen();
      case DesktopTab.sterilization:
        return const SterilizationScreen();
      case DesktopTab.procedures:
        return const ProceduresScreen();
      case DesktopTab.worklist:
        return const RadWorklistScreen();
      case DesktopTab.reports:
        return const RadReportsScreen();
      case DesktopTab.referrers:
        return const RadReferrersScreen();
      case DesktopTab.recalls:
        return const RecallsScreen();
      case DesktopTab.perioPatients:
        return const PerioPatientsScreen();
      case DesktopTab.rootCanals:
        return const DentalNotBuiltScreen(
          icon: RecIcons.endo,
          title: 'Root canals',
          body: 'Not built yet. This will list root canal cases with '
              'canal counts, working lengths and obturation status.',
        );
      case DesktopTab.dentalReferrals:
        return const DentalNotBuiltScreen(
          icon: CruIcons.arrowUpRight,
          title: 'Referrals',
          body: 'Not built yet. This will track referrals sent to and '
              'received from other dentists.',
        );
      case DesktopTab.pedoChildren:
        return const DentalNotBuiltScreen(
          icon: CruIcons.patients,
          title: 'Children',
          body: 'Not built yet. This will list your young patients with '
              'growth, behaviour and eruption tracking.',
        );
      case DesktopTab.biopsies:
        return const DentalNotBuiltScreen(
          icon: CruIcons.flask,
          title: 'Biopsies',
          body: 'Not built yet. This will track biopsy specimens from '
              'collection through to histopathology report.',
        );
      case DesktopTab.oralMedLesions:
        return const DentalNotBuiltScreen(
          icon: RecIcons.pain,
          title: 'Lesions',
          body: 'Not built yet. This will chart oral mucosal lesions with '
              'photos and follow-up.',
        );
      case DesktopTab.oralMedForms:
        return const DentalNotBuiltScreen(
          icon: RecIcons.checklist,
          title: 'Forms',
          body: 'Not built yet. This will hold oral medicine intake and '
              'referral forms.',
        );
      case DesktopTab.sedationCases:
        return const DentalNotBuiltScreen(
          icon: CruIcons.flask,
          title: 'Sedation cases',
          body: 'Not built yet. This will log sedation plans, vitals and '
              'recovery for each case.',
        );
      case DesktopTab.labCases:
        return const DentalNotBuiltScreen(
          icon: CruIcons.box,
          title: 'Lab cases',
          body: 'Not built yet. This will track lab cases from impression '
              'to try-in and delivery.',
        );
      case DesktopTab.orthoPatients:
        return const DentalNotBuiltScreen(
          icon: CruIcons.patients,
          title: 'Ortho patients',
          body: 'Not built yet. This will list patients in active '
              'treatment with bracket and wire history.',
        );
      case DesktopTab.healthCamps:
        return const DentalNotBuiltScreen(
          icon: CruIcons.megaphone,
          title: 'Camps',
          body: 'Not built yet. This will log community dental camps and '
              'screenings.',
        );
      case DesktopTab.population:
        return const DentalNotBuiltScreen(
          icon: CruIcons.patients,
          title: 'Population',
          body: 'Not built yet. This will summarise population-level '
              'oral health survey data.',
        );
      case DesktopTab.surgeries:
        return const DentalNotBuiltScreen(
          icon: DentalIcons.procedures,
          title: 'Surgeries',
          body: 'Not built yet. This will list scheduled and completed '
              'surgeries with consent and post-op notes.',
        );
      case DesktopTab.implants:
        return const DentalNotBuiltScreen(
          icon: DentalIcons.tooth,
          title: 'Implants',
          body: 'Not built yet. This will track implant cases from '
              'placement through to restoration.',
        );
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
      // Settings is a shell tab (sidebar stays, follows Day / Evening).
      onSettings: () => _onNavTap(DesktopTab.settings),
      onProfile: () {
        ref.read(settingsSectionProvider.notifier).state =
            SettingsSection.profile;
        _onNavTap(DesktopTab.settings);
      },
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
        // Dental screens are for dentist logins only; anyone else lands
        // on the dashboard (a tab saved under another specialty).
        final dentist = ref.watch(isDentistProvider);
        final radiologist = ref.watch(isOralRadiologistProvider);
        final shown = (!dentist && DesktopTab.isDental(_currentIndex)) ||
                (!radiologist && DesktopTab.isRadiology(_currentIndex))
            ? DesktopTab.dashboard
            : _currentIndex;
        final moduleKey = DoctorFeatureGuard.getModuleKeyForDesktopTab(
          shown,
        );
        final isTabEnabled =
            shown == 0 ||
            shown == 5 ||
            shown == DesktopTab.settings ||
            DesktopTab.isDental(shown) ||
            DesktopTab.isRadiology(shown) ||
            DoctorFeatureGuard.isEnabled(enabledModules, moduleKey) ||
            // Schedule also holds the Live queue.
            (shown == DesktopTab.appointments &&
                DoctorFeatureGuard.isEnabled(enabledModules, 'queue'));
        final isDashboard = shown == DesktopTab.dashboard;
        final isPatients = shown == DesktopTab.patients;
        // Screens built on the Calm Clinical tokens pad their own page and
        // have no floating chatbot button.
        final isRedesigned = isPatients ||
            shown == DesktopTab.inventory ||
            shown == DesktopTab.revenue ||
            shown == DesktopTab.appointments ||
            shown == DesktopTab.settings ||
            DesktopTab.isDental(shown) ||
            DesktopTab.isRadiology(shown);

        final width = MediaQuery.sizeOf(context).width;
        final forcedCompact = width < CruBreakpoint.compact;
        final collapsed = forcedCompact || !_isSidebarExpanded;

        Widget content = isTabEnabled
            ? _buildScreen(shown)
            : MobileFeatureDisabledView(
                featureTitle: DoctorFeatureGuard.getDesktopTabTitle(
                  shown,
                ),
                icon: _icons[shown],
                onBackToDashboard: () => _onNavTap(0),
              );
        if (isRedesigned) {
          // Patients, Inventory, Revenue and Schedule are built on the Calm
          // Clinical tokens and pad their own page like the dashboard. They
          // follow Day / Evening with the shell; the older dialogs they
          // open pin themselves to Day.
          content = SizedBox.expand(child: content);
        } else if (!isDashboard) {
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

        // Day or Evening for the shell chrome, the dashboard and the
        // redesigned screens (Auto by default). Older screens are wrapped
        // in Day above.
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
                    currentTab: shown,
                    collapsed: collapsed,
                    canExpand: !forcedCompact,
                    callbacks: _sidebarCallbacks(context),
                  ),
                  content: content,
                  // The dashboard reaches the assistant through "Ask
                  // CruDoc" in its search; the redesigned screens have no
                  // floating button either. Other screens keep it.
                  overlay: isDashboard || isRedesigned
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

