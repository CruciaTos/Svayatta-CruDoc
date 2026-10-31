import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:doctor_management_app/core/services/feature_usage_service.dart';
import 'package:doctor_management_app/core/services/auth_service.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/shell/components/cru_sidebar.dart';
import 'package:doctor_management_app/features/shell/components/desktop_page_tabs.dart';
import 'package:doctor_management_app/features/shell/components/mobile_feature_disabled_view.dart';
import 'package:doctor_management_app/features/shell/data/desktop_shell_preferences.dart';
import 'package:doctor_management_app/features/shell/presentation/desktop_shell_layout.dart';
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
import 'package:doctor_management_app/features/dental/specialties/pedo/large_mode.dart';
import 'package:doctor_management_app/features/scribe/presentation/desktop_scribe_screen.dart';
import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/subscription/presentation/feature_upgrade_sheet.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/charting_page.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/shared/widgets/page_search.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/dental/dental_features.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/procedures_screen.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/sterilization_screen.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/treatment_plans_screen.dart';
import 'package:doctor_management_app/features/dental/records/recalls.dart';
import 'package:doctor_management_app/features/dental/referrals/referrals_screen.dart';
import 'package:doctor_management_app/features/dental/specialties/anaesthesia/emergency_protocols.dart';
import 'package:doctor_management_app/features/dental/specialties/perio/perio_patients_screen.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_cases_screen.dart';
import 'package:doctor_management_app/features/dental/specialties/forms/forms_screen.dart';
import 'package:doctor_management_app/features/dental/referrals/referrers_screen.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/reports_screen.dart';
import 'package:doctor_management_app/features/radiology/presentation/worklist_screen.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/clinic/clinic_tabs.dart';
import 'package:doctor_management_app/features/team/presentation/not_available_view.dart';
import 'package:doctor_management_app/features/files/presentation/files_screen.dart';
import 'package:doctor_management_app/features/settings/presentation/documents/documents_screen.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/tutorial/domain/tutorial_step.dart';
import 'package:doctor_management_app/features/tutorial/presentation/tutorial_controller.dart';

/// Intent for the Ctrl+B sidebar toggle shortcut.
class _ToggleSidebarIntent extends Intent {
  const _ToggleSidebarIntent();
}

/// Intent for the Ctrl+1..Ctrl+8 tab-switch shortcuts.
class _NavigateToTabIntent extends Intent {
  const _NavigateToTabIntent(this.index);
  final int index;
}

/// Ctrl/⌘ K: focus "Search patients".
class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

/// Ctrl/⌘ F: focus the open page's own search box.
class _FocusPageSearchIntent extends Intent {
  const _FocusPageSearchIntent();
}

/// Only takes Ctrl F when the page has a search box (see [PageSearch]).
class _FocusPageSearchAction extends Action<_FocusPageSearchIntent> {
  @override
  bool isEnabled(_FocusPageSearchIntent intent) => PageSearch.available;

  @override
  Object? invoke(_FocusPageSearchIntent intent) => PageSearch.focus();
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
    'Consults',
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
    'Emergency',
    'Files',
    'Documents',
    'Charting',
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
    Icons.medical_services_outlined,
    Icons.folder_outlined,
    Icons.description_outlined,
    Icons.grid_view_outlined,
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
    unawaited(FeatureUsageService.log(_labels[index]));
  }

  void _focusSearch() {
    if (_currentIndex != DesktopTab.dashboard) _onNavTap(DesktopTab.dashboard);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  /// Tabs shown as one page (Tasks, Consults) count as that page, so
  /// moving between them slides inside it instead of fading in anew.
  static int _pageOf(int tab) => switch (tab) {
    DesktopTab.reports ||
    DesktopTab.treatmentPlans ||
    DesktopTab.labCases => DesktopTab.worklist,
    DesktopTab.referrers => DesktopTab.dentalReferrals,
    _ => tab,
  };

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
      // Opened from the Sterilization button on Inventory.
      case DesktopTab.sterilization:
        return const DesktopBackPage(
          backLabel: 'Inventory',
          backTab: DesktopTab.inventory,
          child: SterilizationScreen(),
        );
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
      // Worklist, reports, treatment plans and lab cases are one Tasks
      // page.
      case DesktopTab.worklist:
      case DesktopTab.reports:
      case DesktopTab.treatmentPlans:
      case DesktopTab.labCases:
        return DesktopPageTabs(
          title: 'Tasks',
          current: index,
          pages: const [
            (DesktopTab.worklist, 'Worklist'),
            (DesktopTab.reports, 'Reports'),
            (DesktopTab.treatmentPlans, 'Treatment plans'),
            (DesktopTab.labCases, 'Lab cases'),
          ],
          builder: (tab) => switch (tab) {
            DesktopTab.worklist => const RadWorklistScreen(),
            DesktopTab.reports => const RadReportsScreen(),
            DesktopTab.labCases => const LabCasesScreen(),
            _ => const TreatmentPlansScreen(),
          },
        );
      // Referrals and referrers (the doctors and clinics they go to or
      // come from) are one page, for everyone.
      case DesktopTab.dentalReferrals:
      case DesktopTab.referrers:
        return DesktopPageTabs(
          title: 'Consults',
          current: index,
          pages: const [
            (DesktopTab.dentalReferrals, 'Referrals'),
            (DesktopTab.referrers, 'Referrers'),
          ],
          builder: (tab) => tab == DesktopTab.referrers
              ? const ReferrersScreen()
              : const ReferralsScreen(),
        );
      // Procedures and form templates are set up from Settings › Dental.
      case DesktopTab.procedures:
        return const DesktopBackPage(
          backLabel: 'Settings',
          backTab: DesktopTab.settings,
          child: ProceduresScreen(),
        );
      case DesktopTab.oralMedForms:
        return const DesktopBackPage(
          backLabel: 'Settings',
          backTab: DesktopTab.settings,
          child: FormsScreen(),
        );
      case DesktopTab.charting:
        return const ChartingPage();
      case DesktopTab.recalls:
        return const DesktopBackPage(
          backLabel: 'Patients',
          backTab: DesktopTab.patients,
          child: RecallsScreen(),
        );
      case DesktopTab.perioPatients:
        return const DesktopBackPage(
          backLabel: 'Patients',
          backTab: DesktopTab.patients,
          child: PerioPatientsScreen(),
        );
      case DesktopTab.emergency:
        return const EmergencyProtocolsScreen();
      case DesktopTab.files:
        return const FilesScreen();
      case DesktopTab.documents:
        return const DocumentsScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  /// Keyboard shortcuts scoped to the desktop shell: Ctrl+B toggles the
  /// sidebar, Ctrl+1..Ctrl+8 jump to a tab, Ctrl/⌘ K focuses search, Ctrl/⌘
  /// F focuses the open page's search and Enter on the dashboard starts
  /// the Up next consultation.
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
    const SingleActivator(LogicalKeyboardKey.keyF, control: true):
        const _FocusPageSearchIntent(),
    if (defaultTargetPlatform == TargetPlatform.macOS)
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
          const _FocusPageSearchIntent(),
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
          _FocusPageSearchIntent: _FocusPageSearchAction(),
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
      // The clinic tile opens the clinic's settings for its owner; a team
      // member can't edit the clinic, so it does nothing for them.
      onClinicSwitcher: () {
        final access = ref.read(clinicAccessProvider).value;
        if (access != null && !access.isOwner) return;
        ref.read(settingsSectionProvider.notifier).state =
            SettingsSection.clinic;
        _onNavTap(DesktopTab.settings);
      },
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
      onToggleTheme: () => ref.read(appearanceModeProvider.notifier).toggle(),
    );
  }

  Widget _buildContent(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: _enabledModules,
      builder: (context, snapshot) {
        final enabledModules =
            snapshot.data ?? DoctorFeatureGuard.defaultModules;
        final dentist = ref.watch(isDentalProvider);
        final access = ref.watch(clinicAccessProvider).value;
        final shown =
            DentalFeature.allowsTab(
                  _currentIndex,
                  ref.watch(dentalFeaturesProvider),
                ) &&
                clinicAllowsDesktopTab(access, _currentIndex)
            ? _currentIndex
            : DesktopTab.dashboard;
        final moduleKey = DoctorFeatureGuard.getModuleKeyForDesktopTab(shown);
        final isTabEnabled =
            shown == 0 ||
            shown == 5 ||
            shown == DesktopTab.settings ||
            shown == DesktopTab.files ||
            shown == DesktopTab.documents ||
            DesktopTab.isDental(shown) ||
            DesktopTab.isRadiology(shown) ||
            DoctorFeatureGuard.isEnabled(enabledModules, moduleKey) ||
            // Schedule also holds the Live queue.
            (shown == DesktopTab.appointments &&
                DoctorFeatureGuard.isEnabled(enabledModules, 'queue'));
        final isDashboard = shown == DesktopTab.dashboard;
        final isPatients = shown == DesktopTab.patients;
        // Screens built on the Calm Clinical tokens pad their own page.
        final isRedesigned =
            isPatients ||
            shown == DesktopTab.inventory ||
            shown == DesktopTab.revenue ||
            shown == DesktopTab.appointments ||
            shown == DesktopTab.settings ||
            shown == DesktopTab.files ||
            shown == DesktopTab.documents ||
            shown == DesktopTab.scribe ||
            shown == DesktopTab.campaigns ||
            DesktopTab.isDental(shown) ||
            DesktopTab.isRadiology(shown);

        final width = MediaQuery.sizeOf(context).width;
        final forcedCompact = width < CruBreakpoint.compact;
        final collapsed =
            forcedCompact ||
            !_isSidebarExpanded ||
            ref.watch(shellFocusProvider);

        Widget content = isTabEnabled
            ? _buildScreen(shown)
            : access == null || access.isOwner
            ? MobileFeatureDisabledView(
                featureTitle: DoctorFeatureGuard.getDesktopTabTitle(shown),
                icon: _icons[shown],
                onBackToDashboard: () => _onNavTap(0),
              )
            : NotAvailableView(
                featureTitle: DoctorFeatureGuard.getDesktopTabTitle(shown),
                inPlan: false,
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

        if (dentist) {
          final isLarge = ref.watch(largeModeProvider).value ?? false;
          final scale = isLarge ? largeModeScale : normalModeScale;
          final mediaQuery = MediaQuery.of(context);
          content = MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: TextScaler.linear(
                mediaQuery.textScaler.scale(1) * scale,
              ),
            ),
            child: CruIconScale(scale: scale, child: content),
          );
        }

        // A new screen fades in with a slight rise instead of snapping in,
        // whether it was opened from the sidebar or by voice. Only the new
        // screen is built, so a screen is never on the tree twice.
        content = AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          layoutBuilder: (current, _) => current ?? const SizedBox.shrink(),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.012),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: KeyedSubtree(key: ValueKey(_pageOf(shown)), child: content),
        );

        // Day or Evening for the shell chrome, the dashboard and the
        // redesigned screens (Auto by default). Older screens are wrapped
        // in Day above.
        final appearance = ref.watch(resolvedAppearanceProvider);
        final dayBackgroundColor = ref.watch(dayBackgroundColorProvider);

        return InventoryAlertListener(
          child: AnimatedTheme(
            data: CruTheme.of(appearance),
            duration: CruMotion.of(context),
            curve: CruMotion.curve,
            child: Builder(
              builder: (context) => Scaffold(
                backgroundColor: context.cru.canvas,
                body: DesktopShellLayout(
                  dayBackgroundColor: Color(dayBackgroundColor),
                  sidebar: CruSidebar(
                    currentTab: shown,
                    collapsed: collapsed,
                    canExpand: !forcedCompact,
                    callbacks: _sidebarCallbacks(context),
                  ),
                  content: content,
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
                CruIcon(
                  CruIcons.check,
                  size: 16,
                  strokeWidth: 2.2,
                  color: c.accentText,
                ),
            ],
          ),
        ),
      const PopupMenuDivider(),
    ];
  }
}

// ------------------------------------------------------------------------------
// HELP & SHORTCUTS
// ------------------------------------------------------------------------------

/// Help & shortcuts, from the account menu: the keys, voice, and both tours.
void showDesktopShellHelpDialog(BuildContext context) {
  final mac = defaultTargetPlatform == TargetPlatform.macOS;
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final c = dialogContext.cru;
      void tour(TutorialTour which) {
        Navigator.of(dialogContext).pop();
        ProviderScope.containerOf(context, listen: false)
            .read(tutorialControllerProvider.notifier)
            .requestReplay(TutorialPlatform.desktop, tour: which);
      }

      return DentalPanelDialog(
        title: 'Help & shortcuts',
        width: CruSize.dialog + 60,
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            CruSpace.s8,
            CruSpace.s16,
            CruSpace.s8,
            CruSpace.s4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Keyboard', style: CruType.groupLabel.tint(c.label3)),
              const SizedBox(height: CruSpace.s8),
              _ShortcutRow(
                keys: [mac ? '⌘ K' : 'Ctrl K'],
                description: 'Search patients',
              ),
              const _ShortcutRow(
                keys: ['Ctrl B'],
                description: 'Show or hide the sidebar',
              ),
              const _ShortcutRow(
                keys: ['Ctrl 1 – 8'],
                description:
                    'Jump to Dashboard, Patients, Inventory, Revenue, '
                    'Schedule, Campaigns, Scribe or the queue',
              ),
              const _ShortcutRow(
                keys: ['Enter'],
                description: 'On the Dashboard: start the Up next consultation',
              ),
              const SizedBox(height: CruSpace.s16),
              Text('Voice', style: CruType.groupLabel.tint(c.label3)),
              const SizedBox(height: CruSpace.s8),
              const _ShortcutRow(
                keys: ['Hold Space', 'F2'],
                description: 'Talk to CruDoc; let go when you are done',
              ),
              const _ShortcutRow(
                keys: ['Tap Space'],
                description: 'Hands-free on or off',
              ),
              const _ShortcutRow(
                keys: ['Enter'],
                description: 'Save a form voice filled (or say "confirm")',
              ),
            ],
          ),
        ),
        footer: Row(
          children: [
            CruButton(
              label: 'Take the tour',
              kind: CruButtonKind.inset,
              onPressed: () => tour(TutorialTour.app),
            ),
            const SizedBox(width: CruSpace.s8),
            CruButton(
              label: 'Voice tour',
              kind: CruButtonKind.inset,
              onPressed: () => tour(TutorialTour.voice),
            ),
            const Spacer(),
            CruButton(
              label: 'Done',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
      );
    },
  );
}

/// Keys on the left, what they do on the right.
class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.keys, required this.description});

  final List<String> keys;
  final String description;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Wrap(
              spacing: CruSpace.s4,
              runSpacing: CruSpace.s4,
              children: [for (final k in keys) CruKeycap(k)],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(child: Text(description, style: CruType.text.tint(c.label))),
        ],
      ),
    );
  }
}
