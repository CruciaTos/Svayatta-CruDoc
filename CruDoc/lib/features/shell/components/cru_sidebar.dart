import 'package:doctor_management_app/features/shell/components/sync_status_line.dart';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';

class _NavItem {
  const _NavItem(this.tab, this.label, this.icon);
  final int tab;
  final String label;
  final CruIconData icon;
}

class _NavGroup {
  const _NavGroup(this.label, this.items);
  final String label;
  final List<_NavItem> items;
}

/// Extra sidebar pages per dental specialty. Phases add cases here.
List<_NavItem> specialtyNav(DoctorSpecialtyType? sub) => switch (sub) {
  DoctorSpecialtyType.periodontist => const [
    _NavItem(DesktopTab.perioPatients, 'Perio patients', RecIcons.perio),
  ],
  DoctorSpecialtyType.endodontist => const [
    _NavItem(DesktopTab.rootCanals, 'Root canals', RecIcons.endo),
  ],
  DoctorSpecialtyType.pediatricDentist => const [
    _NavItem(DesktopTab.pedoChildren, 'Children', CruIcons.patients),
  ],
  DoctorSpecialtyType.oralPathologist => const [
    _NavItem(DesktopTab.biopsies, 'Biopsies', CruIcons.flask),
  ],
  DoctorSpecialtyType.oralMedicine => const [
    _NavItem(DesktopTab.oralMedLesions, 'Lesions', RecIcons.pain),
    _NavItem(DesktopTab.oralMedForms, 'Forms', RecIcons.checklist),
  ],
  DoctorSpecialtyType.dentalAnesthesiologist => const [
    _NavItem(DesktopTab.sedationCases, 'Sedation cases', CruIcons.flask),
    _NavItem(DesktopTab.emergency, 'Emergency', CruIcons.warning),
  ],
  DoctorSpecialtyType.prosthodontist => const [
    _NavItem(DesktopTab.labCases, 'Lab cases', CruIcons.box),
  ],
  DoctorSpecialtyType.orthodontist => const [
    _NavItem(DesktopTab.orthoPatients, 'Ortho patients', CruIcons.patients),
  ],
  DoctorSpecialtyType.publicHealthDentist => const [
    _NavItem(DesktopTab.healthCamps, 'Camps', CruIcons.megaphone),
    _NavItem(DesktopTab.population, 'Population', CruIcons.patients),
  ],
  DoctorSpecialtyType.oralSurgeon => const [
    _NavItem(DesktopTab.surgeries, 'Surgeries', DentalIcons.procedures),
    _NavItem(DesktopTab.implants, 'Implants', DentalIcons.tooth),
  ],
  // ADD PER-PHASE CASES HERE for the next dental sub-specialty.
  _ => const [],
};

String specialtyNavTitle(DoctorSpecialtyType? sub) =>
    sub == null ? '' : DoctorSpecialty.ofType(sub).shortLabel;

/// The sidebar for this login. Dentists also get Treatment plans,
/// Sterilization and Procedures. Oral & Maxillofacial Radiologists get the
/// Radiology group (Worklist, Reports, Referrers) instead of the
/// chairside dental screens.
List<_NavGroup> _groupsFor({
  required bool dentist,
  required bool radiologist,
  DoctorSpecialtyType? sub,
}) => [
  const _NavGroup('Today', [
    _NavItem(DesktopTab.dashboard, 'Dashboard', CruIcons.dashboard),
    // Live queue + calendar in one place (the queue tab opens its Live view).
    _NavItem(DesktopTab.appointments, 'Schedule', CruIcons.calendar),
  ]),
  if (radiologist || dentist)
    const _NavGroup('Radiology', [
      _NavItem(DesktopTab.worklist, 'Worklist', RadIcons.worklist),
      _NavItem(DesktopTab.reports, 'Reports', RadIcons.report),
      _NavItem(DesktopTab.referrers, 'Referrers', RadIcons.referrer),
    ]),
  _NavGroup('Patients', [
    const _NavItem(DesktopTab.patients, 'Patients', CruIcons.patients),
    if (dentist) ...const [
      _NavItem(DesktopTab.treatmentPlans, 'Treatment plans', DentalIcons.plan),
      _NavItem(DesktopTab.recalls, 'Recalls', RecIcons.recall),
      _NavItem(DesktopTab.dentalReferrals, 'Referrals', CruIcons.arrowUpRight),
    ],
    const _NavItem(DesktopTab.scribe, 'Scribe', CruIcons.mic),
  ]),
  _NavGroup('Clinic', [
    const _NavItem(DesktopTab.inventory, 'Inventory', CruIcons.box),
    if (dentist) ...const [
      _NavItem(DesktopTab.sterilization, 'Sterilization', DentalIcons.shield),
      _NavItem(DesktopTab.procedures, 'Procedures', DentalIcons.procedures),
    ],
    const _NavItem(DesktopTab.revenue, 'Revenue', CruIcons.rupee),
    const _NavItem(DesktopTab.campaigns, 'Campaigns', CruIcons.megaphone),
  ]),
  // Specialty pages for this dental login (each phase adds its own).
  if (specialtyNav(sub).isNotEmpty)
    _NavGroup(specialtyNavTitle(sub), specialtyNav(sub)),
];

/// Actions the account menu offers. The shell supplies them.
class SidebarCallbacks {
  const SidebarCallbacks({
    required this.onNavigate,
    required this.onClinicSwitcher,
    required this.onUpgrade,
    required this.onSettings,
    this.onProfile,
    required this.onHelp,
    required this.onLogout,
    required this.onToggleCollapsed,
    this.appearanceMenu,
    this.onSuperAdmin,
    this.onToggleTheme,
  });

  final ValueChanged<int> onNavigate;
  final VoidCallback onClinicSwitcher;
  final VoidCallback onUpgrade;
  final VoidCallback onSettings;

  /// Settings opened on the Profile section; the item is hidden if null.
  final VoidCallback? onProfile;
  final VoidCallback onHelp;
  final VoidCallback onLogout;
  final VoidCallback onToggleCollapsed;
  final VoidCallback? onSuperAdmin;
  final VoidCallback? onToggleTheme;

  /// Extra account-menu entries (appearance), built by the shell with the
  /// sidebar's current colours.
  final List<PopupMenuEntry<VoidCallback>> Function(CruColors c)?
  appearanceMenu;
}

/// Calm Clinical sidebar: no card behind it, sits on the canvas.
/// Every screen in this login's sidebar, so voice can go exactly where
/// the sidebar goes.
List<({int tab, String label})> sidebarTabs({
  required bool dentist,
  required bool radiologist,
  DoctorSpecialtyType? sub,
}) => [
  for (final g in _groupsFor(
    dentist: dentist,
    radiologist: radiologist,
    sub: sub,
  ))
    for (final i in g.items) (tab: i.tab, label: i.label),
];

class CruSidebar extends ConsumerWidget {
  const CruSidebar({
    super.key,
    required this.currentTab,
    required this.collapsed,
    required this.callbacks,
    this.canExpand = true,
  });

  final int currentTab;
  final bool collapsed;
  final SidebarCallbacks callbacks;

  /// False when the window is too narrow to expand.
  final bool canExpand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final waiting = ref.watch(waitingNowCountProvider);
    final identity = ref.watch(doctorIdentityProvider);
    final plan = ref.watch(subscriptionInfoProvider).value;
    final groups = _groupsFor(
      dentist: ref.watch(isDentistProvider),
      radiologist: ref.watch(isOralRadiologistProvider),
      sub: ref.watch(activeDentalSubspecialtyProvider),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: collapsed ? 0.0 : 1.0),
      duration: CruMotion.of(context),
      curve: CruMotion.curve,
      builder: (context, progress, _) {
        final width = lerpDouble(
          CruSize.sidebarCollapsed,
          CruSize.sidebar,
          progress,
        )!;
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
                label: 'Main navigation',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _Brand(
                            collapsed: collapsed,
                            progress: progress,
                          ),
                        ),
                        if (canExpand && progress > 0.25)
                          Opacity(
                            opacity: ((progress - 0.25) / 0.75).clamp(0.0, 1.0),
                            child: CruPressable(
                              onTap: callbacks.onToggleCollapsed,
                              tooltip: 'Collapse sidebar (Ctrl+B)',
                              builder: (context, hovered) => Container(
                                width: 28,
                                height: 28,
                                alignment: Alignment.center,
                                decoration: ShapeDecoration(
                                  color: hovered
                                      ? (c.isEvening
                                            ? c.inset
                                            : Colors.white.withValues(
                                                alpha: 0.12,
                                              ))
                                      : Colors.transparent,
                                  shape: cruShape(8),
                                ),
                                child: CruIcon(
                                  CruIcons.chevronLeft,
                                  size: 16,
                                  color: c.isEvening
                                      ? c.label2
                                      : CruBrand.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: CruSpace.s16),
                    _ClinicSwitcher(
                      identity: identity,
                      collapsed: collapsed,
                      onTap: callbacks.onClinicSwitcher,
                      progress: progress,
                    ),
                    const SizedBox(height: CruSpace.s16),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Each group is a column with 2 px between its label
                            // and items; 18 px between groups.
                            for (var g = 0; g < groups.length; g++) ...[
                              if (g > 0) const SizedBox(height: 16),
                              if (progress > 0.1)
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    lerpDouble(4, 10, progress)!,
                                    0,
                                    10,
                                    6,
                                  ),
                                  child: Opacity(
                                    opacity: ((progress - 0.25) / 0.75).clamp(
                                      0.0,
                                      1.0,
                                    ),
                                    child: Transform.translate(
                                      offset: Offset(
                                        (1.0 - progress) * -12.0,
                                        0,
                                      ),
                                      child: Text(
                                        groups[g].label,
                                        style: c.isEvening
                                            ? CruType.groupLabel.tint(c.label3)
                                            : CruType.groupLabel.tint(
                                                CruBrand.white.withValues(
                                                  alpha: 0.72,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              for (
                                var i = 0;
                                i < groups[g].items.length;
                                i++
                              ) ...[
                                if (i > 0 || !collapsed)
                                  const SizedBox(height: CruSpace.s2),
                                _SidebarItem(
                                  item: groups[g].items[i],
                                  selected:
                                      currentTab == groups[g].items[i].tab,
                                  collapsed: collapsed,
                                  progress: progress,
                                  badge:
                                      groups[g].items[i].tab ==
                                              DesktopTab.appointments &&
                                          waiting > 0
                                      ? waiting
                                      : null,
                                  onTap: () => callbacks.onNavigate(
                                    groups[g].items[i].tab,
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: CruSpace.s10),
                    if (plan?.daysRemaining != null && progress > 0.25) ...[
                      Opacity(
                        opacity: ((progress - 0.25) / 0.75).clamp(0.0, 1.0),
                        child: _PlanLine(
                          text: plan!.isExpired
                              ? 'Plan expired'
                              : '${plan.doctorStatus.toLowerCase() == 'trial' ? 'Free trial' : '${plan.planName} plan'}'
                                    ' · ${plan.daysRemaining} days left',
                          onUpgrade: callbacks.onUpgrade,
                        ),
                      ),
                      const SizedBox(height: CruSpace.s8),
                    ],
                    SyncStatusLine(collapsed: collapsed),
                    _ProfileButton(
                      name: identity.fullName,
                      collapsed: collapsed,
                      callbacks: callbacks,
                      canExpand: canExpand,
                      progress: progress,
                    ),
                    if (canExpand && progress < 0.75) ...[
                      Opacity(
                        opacity: ((0.75 - progress) / 0.75).clamp(0.0, 1.0),
                        child: Column(
                          children: [
                            const SizedBox(height: CruSpace.s8),
                            if (callbacks.onToggleTheme != null) ...[
                              CruPressable(
                                onTap: callbacks.onToggleTheme,
                                tooltip: c.isEvening
                                    ? 'Night Mode (Click to switch to Day Mode)'
                                    : 'Day Mode (Click to switch to Night Mode)',
                                builder: (context, hovered) => Container(
                                  width: 32,
                                  height: 32,
                                  alignment: Alignment.center,
                                  decoration: ShapeDecoration(
                                    color: hovered
                                        ? (c.isEvening
                                              ? c.inset
                                              : Colors.white.withValues(
                                                  alpha: 0.12,
                                                ))
                                        : Colors.transparent,
                                    shape: cruShape(8),
                                  ),
                                  child: CruIcon(
                                    c.isEvening ? CruIcons.moon : CruIcons.sun,
                                    size: 16,
                                    color: c.isEvening
                                        ? c.accentText
                                        : const Color(0xFFF59E0B),
                                  ),
                                ),
                              ),
                              const SizedBox(height: CruSpace.s4),
                            ],
                            CruPressable(
                              onTap: callbacks.onToggleCollapsed,
                              tooltip: 'Expand sidebar (Ctrl+B)',
                              builder: (context, hovered) => Container(
                                width: 32,
                                height: 32,
                                alignment: Alignment.center,
                                decoration: ShapeDecoration(
                                  color: hovered
                                      ? (c.isEvening
                                            ? c.inset
                                            : Colors.white.withValues(
                                                alpha: 0.12,
                                              ))
                                      : Colors.transparent,
                                  shape: cruShape(8),
                                ),
                                child: CruIcon(
                                  CruIcons.chevronRight,
                                  size: 16,
                                  color: c.isEvening
                                      ? c.label2
                                      : CruBrand.white,
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

class _Brand extends StatelessWidget {
  const _Brand({required this.collapsed, this.progress = 1.0});
  final bool collapsed;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final curveProgress = Curves.easeInOutCubic.transform(progress);
    final impulse = math.sin(progress * math.pi);
    // In collapsed (48px wide): mark is 32px wide. Centered: (48 - 32) / 2 = 8.0.
    // In expanded: left margin is 8.0.
    final markX = lerpDouble(8.0, 8.0, curveProgress)! + impulse * 3.0;
    final markScale = 1.0 + impulse * 0.10;

    final mark = Container(
      width: CruSize.appMark,
      height: CruSize.appMark,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: c.accent,
        shape: cruShape(CruRadius.appMark),
      ),
      child: CruIcon(
        CruIcons.plus,
        size: 16,
        strokeWidth: 3.4,
        color: c.onAccent,
      ),
    );

    return Semantics(
      label: 'CruDoc',
      child: SizedBox(
        height: CruSize.appMark,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: markX,
              top: 0,
              child: Transform.scale(scale: markScale, child: mark),
            ),
            if (progress > 0.15)
              Positioned(
                left: 8.0 + CruSize.appMark + CruSpace.s10,
                top: 0,
                bottom: 0,
                child: Opacity(
                  opacity: ((progress - 0.25) / 0.75).clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset((1.0 - progress) * 16.0, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'CruDoc',
                        style: CruType.wordmark.tint(
                          c.isEvening ? c.label : CruBrand.white,
                        ),
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

/// Replaces the old Specialty Mode card and Switch Specialty button.
class _ClinicSwitcher extends StatelessWidget {
  const _ClinicSwitcher({
    required this.identity,
    required this.collapsed,
    required this.onTap,
    this.progress = 1.0,
  });

  final DoctorIdentity identity;
  final bool collapsed;
  final VoidCallback onTap;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final title = identity.clinicName ?? identity.specialty ?? '';
    final subtitle = identity.clinicName == null ? null : identity.specialty;
    final letter = title.isEmpty ? '·' : title[0].toUpperCase();

    final curveProgress = Curves.easeInOutCubic.transform(progress);
    final impulse = math.sin(progress * math.pi);
    // Collapsed: centered in 48 -> (48 - 32) / 2 = 8.0.
    // Expanded: left docked at 10.0.
    final tileX = lerpDouble(8.0, 10.0, curveProgress)! + impulse * 3.0;
    final tileScale = 1.0 + impulse * 0.10;
    final switcherHeight = lerpDouble(40.0, 52.0, curveProgress)!;

    final tile = Container(
      width: CruSize.clinicTile,
      height: CruSize.clinicTile,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: c.accentTint,
        shape: cruShape(CruRadius.appMark),
      ),
      child: Text(letter, style: CruType.callout.tint(c.accentText)),
    );

    return CruPressable(
      onTap: onTap,
      semanticLabel: 'Clinic: $title. Switch specialty',
      tooltip: collapsed ? title : null,
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        height: switcherHeight,
        decoration: ShapeDecoration(
          color: hovered ? cruHoverShade(c.surface, c) : c.surface,
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
              top: (switcherHeight - CruSize.clinicTile) / 2,
              child: Transform.scale(scale: tileScale, child: tile),
            ),
            if (progress > 0.2)
              Positioned(
                left: 10.0 + CruSize.clinicTile + CruSpace.s10,
                right: 32.0,
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
                          title,
                          style: CruType.callout
                              .copyWith(height: 18 / 14)
                              .tint(c.label),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle,
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
                right: 10.0,
                top: (switcherHeight - 16.0) / 2,
                child: Opacity(
                  opacity: ((progress - 0.35) / 0.65).clamp(0.0, 1.0),
                  child: CruIcon(
                    CruIcons.chevronsUpDown,
                    size: 16,
                    strokeWidth: 1.8,
                    color: c.label3,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
    this.badge,
    this.progress = 1.0,
  });

  final _NavItem item;
  final bool selected;
  final bool collapsed;
  final int? badge;
  final VoidCallback onTap;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final label = badge == null ? item.label : '${item.label}, $badge waiting';
    return Semantics(
      selected: selected,
      child: CruPressable(
        onTap: onTap,
        semanticLabel: label,
        tooltip: collapsed ? label : null,
        scaleOnPress: false,
        builder: (context, hovered) {
          final Color fill;
          final Color iconColor;
          final Color labelColor;
          final Color badgeColor;
          final List<BoxShadow>? shadows;

          if (c.isEvening) {
            // Dark mode: Black sidebar like the image, active state with blue and white text/icon
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
            // Light mode: Maintained untouched with blue sidebar, white active item & blue text/icon
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
              shape: cruShape(CruRadius.control, side: BorderSide.none),
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
                  child: Transform.scale(scale: iconScale, child: icon),
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
                                style: CruType.subhead.w500.tabular.tint(
                                  badgeColor,
                                ),
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

class _PlanLine extends StatelessWidget {
  const _PlanLine({required this.text, required this.onUpgrade});
  final String text;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: CruType.caption.tabular.tint(
                c.isEvening ? c.label2 : CruBrand.white.withValues(alpha: 0.8),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          CruLink(
            label: 'Upgrade',
            style: c.isEvening
                ? CruType.caption.w600
                : CruType.caption.w600.copyWith(color: CruBrand.white),
            onPressed: onUpgrade,
          ),
        ],
      ),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({
    required this.name,
    required this.collapsed,
    required this.callbacks,
    required this.canExpand,
    this.progress = 1.0,
  });

  final String? name;
  final bool collapsed;
  final SidebarCallbacks callbacks;
  final bool canExpand;
  final double progress;

  Future<void> _openMenu(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final c = context.cru;
    final chosen = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        topLeft.dy - 8,
        overlay.size.width - topLeft.dx - 220,
        overlay.size.height - topLeft.dy + 8,
      ),
      constraints: const BoxConstraints(minWidth: 220),
      items: [
        ...?callbacks.appearanceMenu?.call(c),
        if (callbacks.onProfile != null)
          _item(c, CruIcons.user, 'Profile', callbacks.onProfile!),
        _item(c, CruIcons.settings, 'Settings', callbacks.onSettings),
        _item(c, CruIcons.help, 'Help & shortcuts', callbacks.onHelp),
        if (canExpand)
          _item(
            c,
            CruIcons.sidebar,
            collapsed ? 'Expand sidebar' : 'Collapse sidebar',
            callbacks.onToggleCollapsed,
            trailing: 'Ctrl B',
          ),
        if (callbacks.onSuperAdmin != null) ...[
          const PopupMenuDivider(),
          _item(
            c,
            CruIcons.sparkle,
            'Super Admin Console',
            callbacks.onSuperAdmin!,
            trailing: 'Admin',
          ),
        ],
        const PopupMenuDivider(),
        _item(c, CruIcons.logout, 'Log out', callbacks.onLogout),
      ],
    );
    chosen?.call();
  }

  static PopupMenuItem<VoidCallback> _item(
    CruColors c,
    CruIconData icon,
    String label,
    VoidCallback action, {
    String? trailing,
  }) {
    return PopupMenuItem<VoidCallback>(
      value: action,
      height: CruSize.control,
      child: Row(
        children: [
          CruIcon(icon, size: 18, color: c.label2),
          const SizedBox(width: CruSpace.s10),
          Expanded(child: Text(label, style: CruType.text.tint(c.label))),
          if (trailing != null) CruKeycap(trailing),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final display = name ?? 'Account';
    final curveProgress = Curves.easeInOutCubic.transform(progress);
    final impulse = math.sin(progress * math.pi);
    // Collapsed: centered in 48 -> (48 - 34) / 2 = 7.0.
    // Expanded: left docked at 10.0.
    final avatarX = lerpDouble(7.0, 10.0, curveProgress)! + impulse * 3.0;
    final avatarScale = 1.0 + impulse * 0.10;
    final cardHeight = lerpDouble(42.0, 52.0, curveProgress)!;

    final avatar = CruMonogram(
      name: name ?? '',
      size: 34,
      background: Colors.white,
      foreground: c.accent,
    );
    return CruPressable(
      onTap: () => _openMenu(context),
      semanticLabel: '$display. Account and settings',
      tooltip: collapsed ? 'Account & settings' : null,
      scaleOnPress: false,
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        height: cardHeight,
        decoration: ShapeDecoration(
          color: c.isEvening
              ? (hovered ? c.accent.withValues(alpha: 0.9) : c.accent)
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
              child: Transform.scale(scale: avatarScale, child: avatar),
            ),
            if (progress > 0.2)
              Positioned(
                left: 10.0 + 34.0 + CruSpace.s10,
                right: callbacks.onToggleTheme != null ? 40.0 : 10.0,
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
                          display,
                          style: CruType.profileName.tint(
                            c.isEvening
                                ? CruBrand.white
                                : const Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Account & settings',
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
            if (callbacks.onToggleTheme != null && progress > 0.35)
              Positioned(
                right: 8.0,
                top: (cardHeight - 28.0) / 2,
                child: Opacity(
                  opacity: ((progress - 0.35) / 0.65).clamp(0.0, 1.0),
                  child: CruPressable(
                    onTap: callbacks.onToggleTheme,
                    tooltip: c.isEvening
                        ? 'Night Mode active (Click to switch to Day Mode)'
                        : 'Day Mode active (Click to switch to Night Mode)',
                    builder: (context, hovered) => Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        color: c.isEvening
                            ? Colors.white.withValues(alpha: 0.18)
                            : const Color(0xFFEEF2FF),
                        shape: cruShape(8),
                      ),
                      child: CruIcon(
                        c.isEvening ? CruIcons.moon : CruIcons.sun,
                        size: 16,
                        color: c.isEvening
                            ? CruBrand.white
                            : const Color(0xFFF59E0B),
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
