import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

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

const _groups = [
  _NavGroup('Today', [
    _NavItem(DesktopTab.dashboard, 'Dashboard', CruIcons.dashboard),
    _NavItem(DesktopTab.queue, 'Queue', CruIcons.queue),
    _NavItem(DesktopTab.appointments, 'Appointments', CruIcons.calendar),
  ]),
  _NavGroup('Patients', [
    _NavItem(DesktopTab.patients, 'Patients', CruIcons.patients),
    _NavItem(DesktopTab.scribe, 'Scribe', CruIcons.mic),
  ]),
  _NavGroup('Clinic', [
    _NavItem(DesktopTab.inventory, 'Inventory', CruIcons.box),
    _NavItem(DesktopTab.revenue, 'Revenue', CruIcons.rupee),
    _NavItem(DesktopTab.campaigns, 'Campaigns', CruIcons.megaphone),
  ]),
];

/// Actions the account menu offers. The shell supplies them.
class SidebarCallbacks {
  const SidebarCallbacks({
    required this.onNavigate,
    required this.onClinicSwitcher,
    required this.onUpgrade,
    required this.onSettings,
    required this.onHelp,
    required this.onLogout,
    required this.onToggleCollapsed,
    this.appearanceMenu,
  });

  final ValueChanged<int> onNavigate;
  final VoidCallback onClinicSwitcher;
  final VoidCallback onUpgrade;
  final VoidCallback onSettings;
  final VoidCallback onHelp;
  final VoidCallback onLogout;
  final VoidCallback onToggleCollapsed;

  /// Extra account-menu entries (appearance), built by the shell.
  final List<PopupMenuEntry<VoidCallback>> Function()? appearanceMenu;
}

/// Calm Clinical sidebar: no card behind it, sits on the canvas.
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

    return AnimatedContainer(
      duration: CruMotion.of(context),
      curve: CruMotion.curve,
      width: collapsed ? CruSize.sidebarCollapsed : CruSize.sidebar,
      color: c.canvas,
      padding: collapsed
          ? const EdgeInsets.fromLTRB(12, 24, 12, 20)
          : CruSpace.sidebarPadding,
      child: Semantics(
        container: true,
        label: 'Main navigation',
        child: Column(
          crossAxisAlignment:
              collapsed ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
          children: [
            _Brand(collapsed: collapsed),
            const SizedBox(height: CruSpace.s22),
            _ClinicSwitcher(
              identity: identity,
              collapsed: collapsed,
              onTap: callbacks.onClinicSwitcher,
            ),
            const SizedBox(height: CruSpace.s22),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: collapsed
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.stretch,
                  children: [
                    for (var g = 0; g < _groups.length; g++) ...[
                      if (g > 0) const SizedBox(height: 18),
                      if (!collapsed)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                          child: Text(_groups[g].label,
                              style: CruType.groupLabel.tint(c.label3)),
                        ),
                      for (final item in _groups[g].items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: CruSpace.s2),
                          child: _SidebarItem(
                            item: item,
                            selected: currentTab == item.tab,
                            collapsed: collapsed,
                            badge: item.tab == DesktopTab.queue && waiting > 0
                                ? waiting
                                : null,
                            onTap: () => callbacks.onNavigate(item.tab),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: CruSpace.s12),
            if (!collapsed && plan?.daysRemaining != null) ...[
              _PlanLine(
                text: plan!.isExpired
                    ? 'Plan expired'
                    : '${plan.doctorStatus.toLowerCase() == 'trial' ? 'Free trial' : '${plan.planName} plan'}'
                        ' · ${plan.daysRemaining} days left',
                onUpgrade: callbacks.onUpgrade,
              ),
              const SizedBox(height: CruSpace.s10),
            ],
            _ProfileButton(
              name: identity.fullName,
              collapsed: collapsed,
              callbacks: callbacks,
              canExpand: canExpand,
            ),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.collapsed});
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final mark = Container(
      width: CruSize.appMark,
      height: CruSize.appMark,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: c.accent,
        shape: cruShape(CruRadius.appMark),
      ),
      child: CruIcon(CruIcons.plus, size: 16, strokeWidth: 3.4, color: c.onAccent),
    );
    if (collapsed) return Semantics(label: 'CruDoc', child: mark);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8),
      child: Row(
        children: [
          mark,
          const SizedBox(width: CruSpace.s10),
          Text('CruDoc', style: CruType.wordmark.tint(c.label)),
        ],
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
  });

  final DoctorIdentity identity;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final title = identity.clinicName ?? identity.specialty ?? '';
    final subtitle = identity.clinicName == null ? null : identity.specialty;
    final letter = title.isEmpty ? '·' : title[0].toUpperCase();

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
        padding: collapsed
            ? const EdgeInsets.all(4)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: ShapeDecoration(
          color: hovered ? cruHoverShade(c.surface, c) : c.surface,
          shape: cruShape(CruRadius.switcher, side: BorderSide(color: c.hairline)),
          shadows: c.cardShadow,
        ),
        child: collapsed
            ? tile
            : Row(
                children: [
                  tile,
                  const SizedBox(width: CruSpace.s10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: CruType.callout
                                .copyWith(height: 18 / 14)
                                .tint(c.label),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        if (subtitle != null)
                          Text(subtitle,
                              style: CruType.caption.tint(c.label2),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  CruIcon(CruIcons.chevronsUpDown,
                      size: 16, strokeWidth: 1.8, color: c.label3),
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
  });

  final _NavItem item;
  final bool selected;
  final bool collapsed;
  final int? badge;
  final VoidCallback onTap;

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
          final fill = selected
              ? c.sidebarSelected
              : hovered
                  ? c.sidebarSelected.withValues(alpha: c.isEvening ? 0.6 : 0.7)
                  : c.sidebarSelected.withValues(alpha: 0);
          final icon = CruIcon(
            item.icon,
            size: CruSize.navIcon,
            color: selected ? c.accent : c.label2,
          );
          return AnimatedContainer(
            duration: CruMotion.of(context, CruMotion.fast),
            curve: CruMotion.curve,
            height: CruSize.navItem,
            width: collapsed ? 48 : null,
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 10),
            decoration: ShapeDecoration(
              color: fill,
              shape: cruShape(
                CruRadius.control,
                side: selected ? BorderSide(color: c.hairline) : BorderSide.none,
              ),
              shadows: selected ? c.cardShadow : null,
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
                          child: CruStatusDot(CruDotKind.waiting,
                              size: CruSize.smallDot),
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
                                fontWeight:
                                    selected ? FontWeight.w600 : FontWeight.w500,
                              )
                              .tint(c.label),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (badge != null) ...[
                        const CruStatusDot(CruDotKind.waiting,
                            size: CruSize.smallDot),
                        const SizedBox(width: CruSpace.s6),
                        Text('$badge',
                            style: CruType.subhead.w500.tabular.tint(c.label2)),
                      ],
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
            child: Text(text,
                style: CruType.caption.tabular.tint(c.label2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          CruLink(
            label: 'Upgrade',
            style: CruType.caption.w600,
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
  });

  final String? name;
  final bool collapsed;
  final SidebarCallbacks callbacks;
  final bool canExpand;

  Future<void> _openMenu(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
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
        ...?callbacks.appearanceMenu?.call(),
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
    final avatar = CruMonogram(
      name: name ?? '',
      size: 34,
      background: c.track,
    );
    return CruPressable(
      onTap: () => _openMenu(context),
      semanticLabel: '$display. Account and settings',
      tooltip: collapsed ? 'Account & settings' : null,
      scaleOnPress: false,
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        padding: collapsed
            ? const EdgeInsets.all(4)
            : const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: ShapeDecoration(
          color: hovered
              ? c.sidebarSelected.withValues(alpha: 0.7)
              : c.sidebarSelected.withValues(alpha: 0),
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
                        Text(display,
                            style: CruType.profileName.tint(c.label),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text('Account & settings',
                            style: CruType.caption.tint(c.label2)),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
