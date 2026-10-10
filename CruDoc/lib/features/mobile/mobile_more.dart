import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/core/services/auth_service.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/procedures_screen.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/sterilization_screen.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/treatment_plans_screen.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/records/recalls.dart';
import 'package:doctor_management_app/features/dental/referrals/referrals_screen.dart';
import 'package:doctor_management_app/features/dental/specialties/anaesthesia/emergency_protocols.dart';
import 'package:doctor_management_app/features/dental/specialties/dental_not_built.dart';
import 'package:doctor_management_app/features/dental/specialties/forms/forms_screen.dart';
import 'package:doctor_management_app/features/dental/specialties/perio/perio_patients_screen.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_cases_screen.dart';
import 'package:doctor_management_app/features/inventory/presentation/inventory_screen.dart';
import 'package:doctor_management_app/features/mobile/mobile_backdrop.dart';
import 'package:doctor_management_app/features/mobile/mobile_campaigns.dart';
import 'package:doctor_management_app/features/mobile/mobile_invoices.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
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
  DesktopTab.rootCanals ||
  DesktopTab.pedoChildren ||
  DesktopTab.biopsies ||
  DesktopTab.oralMedLesions ||
  DesktopTab.sedationCases ||
  DesktopTab.orthoPatients ||
  DesktopTab.healthCamps ||
  DesktopTab.population ||
  DesktopTab.surgeries ||
  DesktopTab.implants => DentalNotBuiltScreen(
    icon: _iconFor(tab),
    title: DesktopTab.label(tab),
    body:
        'Not built yet. This page will hold your '
        '${DesktopTab.label(tab).toLowerCase()} once it is ready.',
  ),
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

  void _open(BuildContext context, int tab) =>
      openMobileDestination(context, tab, backLabel: 'More');

  void _locked(BuildContext context, String what) => mobileSay(
    context,
    '$what is not part of your plan. Ask us to switch it on.',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final identity = ref.watch(doctorIdentityProvider);
    final modules = enabledModules ?? DoctorFeatureGuard.defaultModules;
    bool on(String m) => DoctorFeatureGuard.isEnabled(modules, m);
    final specialty = [
      for (final t in sidebarTabs(
        dental: ref.watch(dentalFeaturesProvider),
        access: ref.watch(clinicAccessProvider).value,
      ))
        if (!_onTabs.contains(t.tab)) t,
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

    return ListView(
      padding: EdgeInsets.only(bottom: MobileMetrics.bottom(context)),
      children: [
        const MobileHeader(title: 'More'),
        const SizedBox(height: CruSpace.s16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: MobileMetrics.gutter),
          child: MobileCard(
            onTap: () => openMobileSettings(
              context,
              ref,
              SettingsSection.profile,
              backLabel: 'More',
            ),
            padding: const EdgeInsets.all(CruSpace.s16),
            child: Row(
              children: [
                MobileAvatar(name: identity.fullName ?? 'Doctor', size: 48),
                const SizedBox(width: CruSpace.s14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        identity.fullName ?? 'Your profile',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MobileType.headline.tint(c.label),
                      ),
                      const SizedBox(height: CruSpace.s2),
                      Text(
                        [
                              ?identity.clinicName,
                              ?identity.specialty,
                            ].join(' · ').isEmpty
                            ? 'Clinic profile'
                            : [
                                ?identity.clinicName,
                                ?identity.specialty,
                              ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MobileType.subhead.tint(c.label2),
                      ),
                    ],
                  ),
                ),
                CruIcon(
                  CruIcons.chevronRight,
                  size: 16,
                  strokeWidth: 2,
                  color: c.label3,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: CruSpace.s16),
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
              'Scribe',
              CruIcons.mic,
              MobileTone.violet,
              () => on('ai_assistant')
                  ? _open(context, DesktopTab.scribe)
                  : _locked(context, 'Scribe'),
              detail: 'Consultation notes from your voice',
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
            title: 'Dental',

            children: [
              for (final t in specialty)
                row(
                  t.label,
                  _iconFor(t.tab),
                  MobileTone.blue,
                  () => _open(context, t.tab),
                ),
            ],
          ),
        ],
        const SizedBox(height: CruSpace.s16),
        MobileRowGroup(
          title: 'App',

          children: [
            const _AppearanceRow(),
            row(
              'Settings',
              CruIcons.settings,
              MobileTone.slate,
              () => pushMobile(
                context,
                const MobileHostPage(
                  backLabel: 'More',
                  child: _MobileSettingsList(),
                ),
              ),
            ),
            row(
              'How the phone app works',
              CruIcons.help,
              MobileTone.slate,
              () => showMobileGestureGuide(context),
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
          detail: 'Move between Home, Schedule, Patients, Revenue, More',
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
    final sections = [
      for (final s in SettingsSection.values)
        if (showSettingsSection(ref, s)) s,
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
      ],
    );
  }
}
