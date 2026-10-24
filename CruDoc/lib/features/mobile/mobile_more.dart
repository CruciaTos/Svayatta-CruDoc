import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/core/services/auth_service.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/procedures_screen.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/sterilization_screen.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/treatment_plans_screen.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/records/recalls.dart';
import 'package:doctor_management_app/features/dental/referrals/referrals_screen.dart';
import 'package:doctor_management_app/features/dental/specialties/anaesthesia/emergency_protocols.dart';
import 'package:doctor_management_app/features/dental/specialties/forms/forms_screen.dart';
import 'package:doctor_management_app/features/dental/specialties/perio/perio_patients_screen.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_cases_screen.dart';
import 'package:doctor_management_app/features/inventory/presentation/inventory_screen.dart';
import 'package:doctor_management_app/features/mobile/mobile_backdrop.dart';
import 'package:doctor_management_app/features/mobile/mobile_campaigns.dart';
import 'package:doctor_management_app/features/mobile/mobile_invoices.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/mobile/mobile_revenue.dart';
import 'package:doctor_management_app/features/mobile/mobile_wave.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/features/subscription/presentation/subscription_billing_page.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_details_view.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/presentation/referrers_screen.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/reports_screen.dart';
import 'package:doctor_management_app/features/radiology/presentation/worklist_screen.dart';
import 'package:doctor_management_app/features/scribe/presentation/desktop_scribe_screen.dart';
import 'package:doctor_management_app/features/settings/data/appearance_preferences.dart';
import 'package:doctor_management_app/features/settings/data/appearance_provider.dart';
import 'package:doctor_management_app/features/settings/presentation/desktop_settings_screen.dart';
import 'package:doctor_management_app/features/shell/components/cru_sidebar.dart';
import 'package:doctor_management_app/features/files/presentation/files_screen.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/tutorial/domain/tutorial_step.dart';
import 'package:doctor_management_app/features/tutorial/presentation/tutorial_controller.dart';

/// A patient's record over the phone screen (swipe back to return).
void openMobilePatient(BuildContext context, Patient patient) => pushMobile(
  context,
  MobileBackdropPage(child: PatientDetailsScreen(patientId: patient.id)),
);

void openMobileInvoices(BuildContext context, {String backLabel = 'Revenue'}) =>
    pushMobile(
      context,
      MobileHostPage(backLabel: backLabel, child: const MobileInvoicesScreen()),
    );

/// One Settings section on its own page.
void openMobileSettings(
  BuildContext context,
  WidgetRef ref,
  SettingsSection section, {
  String backLabel = 'Settings',
}) {
  ref.read(settingsSectionProvider.notifier).state = section;
  pushMobile(
    context,
    MobileHostPage(backLabel: backLabel, child: const DesktopSettingsScreen()),
  );
}

/// Opens a screen that lives in More (or a specialty page) by its
/// desktop tab, so phone and desktop share one list of places.
void openMobileDestination(
  BuildContext context,
  int tab, {
  String backLabel = 'Back',
}) {
  final screen = mobileDestinationScreen(tab);
  if (screen == null) return;
  pushMobile(context, MobileHostPage(backLabel: backLabel, child: screen));
}

Widget? mobileDestinationScreen(int tab) => switch (tab) {
  DesktopTab.inventory => const InventoryScreen(),
  DesktopTab.campaigns => const MobileCampaignsPage(),
  DesktopTab.scribe => const DesktopScribeScreen(),
  DesktopTab.settings => const DesktopSettingsScreen(),
  DesktopTab.treatmentPlans => const TreatmentPlansScreen(),
  DesktopTab.sterilization => const SterilizationScreen(),
  DesktopTab.procedures => const ProceduresScreen(),
  DesktopTab.worklist => const RadWorklistScreen(),
  DesktopTab.reports => const RadReportsScreen(),
  DesktopTab.referrers => const RadReferrersScreen(),
  DesktopTab.recalls => const RecallsScreen(),
  DesktopTab.perioPatients => const PerioPatientsScreen(),
  DesktopTab.dentalReferrals => const ReferralsScreen(),
  DesktopTab.oralMedForms => const FormsScreen(),
  DesktopTab.labCases => const LabCasesScreen(),
  DesktopTab.emergency => const EmergencyProtocolsScreen(),
  DesktopTab.files => const FilesScreen(),
  _ => null,
};

CruIconData _iconFor(int tab) => switch (tab) {
  DesktopTab.inventory => CruIcons.box,
  DesktopTab.campaigns => CruIcons.megaphone,
  DesktopTab.scribe => CruIcons.mic,
  DesktopTab.treatmentPlans => DentalIcons.plan,
  DesktopTab.sterilization => DentalIcons.shield,
  DesktopTab.procedures || DesktopTab.surgeries => DentalIcons.procedures,
  DesktopTab.worklist => RadIcons.worklist,
  DesktopTab.reports => RadIcons.report,
  DesktopTab.referrers => RadIcons.referrer,
  DesktopTab.recalls => RecIcons.recall,
  DesktopTab.perioPatients => RecIcons.perio,
  DesktopTab.rootCanals => RecIcons.endo,
  DesktopTab.dentalReferrals => CruIcons.arrowUpRight,
  DesktopTab.oralMedLesions => RecIcons.pain,
  DesktopTab.oralMedForms => RecIcons.checklist,
  DesktopTab.labCases => CruIcons.box,
  DesktopTab.biopsies || DesktopTab.sedationCases => CruIcons.flask,
  DesktopTab.healthCamps => CruIcons.megaphone,
  DesktopTab.implants => DentalIcons.tooth,
  DesktopTab.emergency => CruIcons.warning,
  DesktopTab.files => FileIcons.folder,
  _ => CruIcons.patients,
};

/// More: everything that isn't one of the four main tabs, grouped the
/// way the desktop sidebar groups it, plus appearance, help and sign-out.
class MobileMoreScreen extends ConsumerWidget {
  const MobileMoreScreen({super.key, this.enabledModules});

  final List<String>? enabledModules;

  /// The phone's own tabs (and Settings, which has its own row).
  static const _onTabs = {
    DesktopTab.dashboard,
    DesktopTab.appointments,
    DesktopTab.patients,
    DesktopTab.revenue,
    DesktopTab.inventory,
    DesktopTab.campaigns,
    DesktopTab.scribe,
  };

  /// Pages that moved: Recalls to the Patients header; the radiology
  /// worklist and reports, treatment plans and lab cases into Tasks;
  /// Perio to a Patients filter; Sterilization beside Inventory;
  /// Procedures and form templates to Settings › Dental.
  static const _elsewhere = {
    DesktopTab.recalls,
    DesktopTab.worklist,
    DesktopTab.reports,
    DesktopTab.treatmentPlans,
    DesktopTab.labCases,
    DesktopTab.perioPatients,
    DesktopTab.sterilization,
    DesktopTab.procedures,
    DesktopTab.oralMedForms,
  };

  void _open(BuildContext context, int tab) =>
      openMobileDestination(context, tab, backLabel: 'More');

  void _locked(BuildContext context, String what) => mobileSay(
    context,
    '$what is not part of your plan. Ask us to switch it on.',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revenueOpen = ref.watch(mobileRevenueOpenProvider);
    void showRevenue(bool open) =>
        ref.read(mobileRevenueOpenProvider.notifier).state = open;
    final modules = enabledModules ?? DoctorFeatureGuard.defaultModules;
    bool on(String m) => DoctorFeatureGuard.isEnabled(modules, m);
    final specialty = [
      for (final t in sidebarTabs(
        dental: ref.watch(dentalFeaturesProvider),
        access: ref.watch(clinicAccessProvider).value,
      ))
        if (!_onTabs.contains(t.tab) && !_elsewhere.contains(t.tab)) t,
    ];

    Widget row(
      String label,
      CruIconData icon,
      MobileTone tone,
      VoidCallback onTap, {
      String? detail,
    }) => MobileRow(
      leading: MobileIconTile(icon: icon, tone: tone),
      title: label,
      subtitle: detail,
      titleStyle: MobileType.row.copyWith(fontWeight: FontWeight.w500),
      chevron: true,
      onTap: onTap,
    );

    final bothReferrals =
        specialty.any((t) => t.tab == DesktopTab.dentalReferrals) &&
        specialty.any((t) => t.tab == DesktopTab.referrers);
    final revenueCard =
        on('revenue') && ref.watch(clinicCanProvider(ClinicPermission.revenue));

    // Revenue opens in place of More's list (Back returns).
    return _RevenueInPlace(
      open: revenueOpen,
      onClose: () => showRevenue(false),
      more: (cardKey) => [
        MobileHeader(
          title: 'More',
          trailing: MobileCircleButton(
            icon: CruIcons.settings,
            semanticLabel: 'Settings',
            onPressed: () => pushMobile(
              context,
              const MobileHostPage(
                backLabel: 'More',
                child: _MobileSettingsList(),
              ),
            ),
          ),
        ),
        const SizedBox(height: CruSpace.s16),
        if (revenueCard) ...[
          // As wide as a card on Revenue's strip, so it glides
          // straight into place.
          _RevenueSlot(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MobileMetrics.gutter,
              ),
              child: MobileWaveCard(
                key: cardKey,
                child: MobileRevenueCard(onTap: () => showRevenue(true)),
              ),
            ),
          ),
          const SizedBox(height: CruSpace.s16),
        ],
        MobileRowGroup(
          title: 'Plan',

          children: [
            row(
              'Subscription & Billing',
              CruIcons.wallet,
              MobileTone.green,
              () => pushMobile(context, const SubscriptionBillingPage()),
              detail: 'Unlock features, manage your plan & payments',
            ),
          ],
        ),
        const SizedBox(height: CruSpace.s16),
        MobileRowGroup(
          title: 'Clinic',

          children: [
            row(
              'Inventory',
              CruIcons.box,
              MobileTone.teal,
              () => on('inventory')
                  ? _open(context, DesktopTab.inventory)
                  : _locked(context, 'Inventory'),
            ),
            row(
              'Invoices',
              CruIcons.fileText,
              MobileTone.indigo,
              () => on('revenue')
                  ? openMobileInvoices(context, backLabel: 'More')
                  : _locked(context, 'Invoices'),
            ),
            row(
              'Campaigns',
              CruIcons.megaphone,
              MobileTone.amber,
              () => _open(context, DesktopTab.campaigns),
            ),
          ],
        ),
        if (specialty.isNotEmpty) ...[
          const SizedBox(height: CruSpace.s16),
          MobileRowGroup(
            title: ref.watch(dentalFeaturesProvider).isEmpty
                ? 'Clinical'
                : 'Dental',

            children: [
              for (final t in specialty)
                // Referrals (sent) and referrers (who send) are one page.
                if (!(t.tab == DesktopTab.referrers && bothReferrals))
                  row(
                    bothReferrals && t.tab == DesktopTab.dentalReferrals
                        ? 'Referrals'
                        : t.label,
                    _iconFor(t.tab),
                    MobileTone.blue,
                    () => bothReferrals && t.tab == DesktopTab.dentalReferrals
                        ? pushMobile(
                            context,
                            const MobileHostPage(
                              backLabel: 'More',
                              child: _PageHub(
                                pages: [
                                  ('Referrals', ReferralsScreen()),
                                  ('Referrers', RadReferrersScreen()),
                                ],
                              ),
                            ),
                          )
                        : _open(context, t.tab),
                  ),
            ],
          ),
        ],
      ],
    );
  }
}

/// More's list and Revenue, one in place of the other. The revenue card
/// stays on screen and glides between its two places while the page it is
/// joining ripples in around it (see MobileWave); the page it leaves goes
/// at once.
class _RevenueInPlace extends StatefulWidget {
  const _RevenueInPlace({
    required this.open,
    required this.onClose,
    required this.more,
  });

  final bool open;
  final VoidCallback onClose;

  /// More's list, with [cardKey] on the revenue card (if shown).
  final List<Widget> Function(GlobalKey cardKey) more;

  @override
  State<_RevenueInPlace> createState() => _RevenueInPlaceState();
}

class _RevenueInPlaceState extends State<_RevenueInPlace>
    with SingleTickerProviderStateMixin {
  final _moreCard = GlobalKey();
  final _revenueCard = GlobalKey();
  final _revenueScroll = ScrollController();
  late final AnimationController _t =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1000),
        value: 1,
      )..addStatusListener((status) {
        // The page that left goes offstage once the waves end.
        if (status == AnimationStatus.completed && mounted) setState(() {});
      });
  late bool _showing = widget.open;
  Rect? _from;

  @override
  void didUpdateWidget(_RevenueInPlace old) {
    super.didUpdateWidget(old);
    if (widget.open == _showing) return;
    final open = widget.open;
    _from = mobileGlobalRect(_showing ? _revenueCard : _moreCard);
    _showing = open;
    if (MediaQuery.disableAnimationsOf(context)) {
      _t.value = 1;
    } else {
      _t.forward(from: 0);
    }
    // Revenue opens at its top next time.
    if (!open) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_revenueScroll.hasClients) _revenueScroll.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _t.dispose();
    _revenueScroll.dispose();
    super.dispose();
  }

  Widget _layer({required bool revenue, required Widget child}) {
    final on = _showing == revenue;
    final leaving = !on && _t.isAnimating;
    return Offstage(
      offstage: !on && !leaving,
      child: IgnorePointer(
        ignoring: leaving,
        child: TickerMode(
          enabled: on || leaving,
          child: MobileWave(
            t: on || leaving ? _t : kAlwaysCompleteAnimation,
            leaving: leaving,
            from: on ? _from : null,
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final more = widget.more(_moreCard);
    final card = more.indexWhere((w) => w is _RevenueSlot);
    return Stack(
      fit: StackFit.expand,
      children: [
        _layer(
          revenue: false,
          child: ListView(
            padding: EdgeInsets.only(bottom: MobileMetrics.bottom(context)),
            children: mobileWaveChildren(more, origin: card < 0 ? 0 : card),
          ),
        ),
        _layer(
          revenue: true,
          child: MobileRevenueScreen(
            onBack: widget.onClose,
            scrollController: _revenueScroll,
            cardKey: _revenueCard,
          ),
        ),
      ],
    );
  }
}

/// Auto / Day / Evening in one row, applied at once.
class _AppearanceRow extends ConsumerWidget {
  const _AppearanceRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final mode = ref.watch(appearanceModeProvider);
    return Container(
      color: c.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MobileIconTile(
                icon: c.isEvening ? CruIcons.moon : CruIcons.sun,
                tone: MobileTone.slate,
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Text(
                  'Appearance',
                  style: MobileType.row
                      .copyWith(fontWeight: FontWeight.w500)
                      .tint(c.label),
                ),
              ),
              if (mode == AppearanceMode.auto)
                Text(
                  'Evening from 5 PM',
                  style: MobileType.caption.tint(c.label3),
                ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),
          MobileSegmented<AppearanceMode>(
            values: AppearanceMode.values,
            label: (m) => m.label,
            selected: mode,
            onChanged: (m) =>
                ref.read(appearanceModeProvider.notifier).select(m),
          ),
        ],
      ),
    );
  }
}

/// Every shortcut the phone has, in one place.
Future<void> showMobileGestureGuide(BuildContext context) =>
    showMobileActionSheet(
      context,
      title: 'Shortcuts on the phone',
      subtitle: 'Everything also works with plain taps.',
      actions: [
        MobileSheetAction(
          label: 'Swipe left or right',
          detail: 'Move between Home, Schedule, Patients, Tasks, More',
          icon: CruIcons.importExport,
          tone: MobileTone.blue,
          onTap: () {},
        ),
        MobileSheetAction(
          label: 'Drag along the tab bar',
          detail: 'Slide your thumb to any tab',
          icon: CruIcons.dashboard,
          tone: MobileTone.blue,
          onTap: () {},
        ),
        MobileSheetAction(
          label: 'Swipe a Schedule row right',
          detail: "Today's next step: check in, call in, done",
          icon: CruIcons.userCheck,
          tone: MobileTone.amber,
          onTap: () {},
        ),
        MobileSheetAction(
          label: 'Hold any person',
          detail: 'Call, WhatsApp, book, pay, reschedule',
          icon: CruIcons.more,
          tone: MobileTone.green,
          onTap: () {},
        ),
        MobileSheetAction(
          label: 'Tap the black pill at the top',
          detail: "Who's next and the live queue",
          icon: CruIcons.mic,
          tone: MobileTone.violet,
          onTap: () {},
        ),
      ],
    );

/// Settings on the phone: the sections as a list, each on its own page.
class _MobileSettingsList extends ConsumerWidget {
  const _MobileSettingsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final sections = [
      for (final s in SettingsSection.values)
        if (showSettingsSection(ref, s) && s != SettingsSection.appearance) s,
    ];
    return ListView(
      padding: EdgeInsets.only(
        bottom: MobileMetrics.navBottom(context) + CruSpace.s24,
      ),
      children: [
        const MobileHeader(pushed: true, title: 'Settings'),
        const SizedBox(height: CruSpace.s16),
        MobileRowGroup(
          children: [
            for (final s in sections)
              MobileRow(
                leading: MobileIconTile(icon: s.icon, tone: MobileTone.slate),
                title: s.label,
                titleStyle: MobileType.row.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                chevron: true,
                onTap: () => openMobileSettings(context, ref, s),
              ),
          ],
        ),
        const SizedBox(height: CruSpace.s16),
        MobileRowGroup(
          children: [
            const _AppearanceRow(),
            MobileRow(
              leading: const MobileIconTile(
                icon: CruIcons.help,
                tone: MobileTone.slate,
              ),
              title: 'How the phone app works',
              titleStyle: MobileType.row.copyWith(fontWeight: FontWeight.w500),
              chevron: true,
              onTap: () => showMobileGestureGuide(context),
            ),
            MobileRow(
              leading: const MobileIconTile(
                icon: CruIcons.help,
                tone: MobileTone.slate,
              ),
              title: 'Take the tour again',
              titleStyle: MobileType.row.copyWith(fontWeight: FontWeight.w500),
              chevron: true,
              // Back to the tabs; the tour starts from Home.
              onTap: () {
                Navigator.of(context, rootNavigator: true).pop();
                ref
                    .read(tutorialControllerProvider.notifier)
                    .requestReplay(TutorialPlatform.mobile);
              },
            ),
            MobileRow(
              leading: const MobileIconTile(
                icon: CruIcons.mic,
                tone: MobileTone.slate,
              ),
              title: 'Voice tour',
              titleStyle: MobileType.row.copyWith(fontWeight: FontWeight.w500),
              chevron: true,
              onTap: () {
                Navigator.of(context, rootNavigator: true).pop();
                ref
                    .read(tutorialControllerProvider.notifier)
                    .requestReplay(
                      TutorialPlatform.mobile,
                      tour: TutorialTour.voice,
                    );
              },
            ),
            MobileRow(
              leading: const MobileIconTile(
                icon: CruIcons.logout,
                tone: MobileTone.slate,
              ),
              title: 'Sign out',
              titleStyle: MobileType.row
                  .copyWith(fontWeight: FontWeight.w500)
                  .tint(c.label),
              onTap: () async {
                try {
                  await AuthService().signOut();
                } catch (_) {}
                if (context.mounted) context.go('/auth');
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// Marks the revenue card's place in More's list.
class _RevenueSlot extends StatelessWidget {
  const _RevenueSlot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Several pages on one, with a segmented control on top: referrals
/// sent out and the people who refer patients in.
class _PageHub extends StatefulWidget {
  const _PageHub({required this.pages});

  /// (label, page), in order.
  final List<(String, Widget)> pages;

  @override
  State<_PageHub> createState() => _PageHubState();
}

class _PageHubState extends State<_PageHub> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MobileMetrics.gutter,
            CruSpace.s8,
            MobileMetrics.gutter,
            0,
          ),
          child: MobileSegmented<int>(
            values: [for (var i = 0; i < widget.pages.length; i++) i],
            label: (i) => widget.pages[i].$1,
            selected: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [for (final p in widget.pages) p.$2],
          ),
        ),
      ],
    );
  }
}
