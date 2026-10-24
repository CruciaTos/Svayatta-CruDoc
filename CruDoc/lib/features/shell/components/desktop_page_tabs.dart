import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/shell/components/cru_sidebar.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/shared/widgets/page_tabs_scope.dart';

/// Several sidebar pages shown as one, with a segmented control in place of
/// the page title (Tasks: worklist, reports, treatment plans, lab cases;
/// Referrals: sent and referrers).
/// Each tab is still its own DesktopTab, so voice, shortcuts and saved
/// tabs keep working; only the tabs this login has are shown.
class DesktopPageTabs extends ConsumerWidget {
  const DesktopPageTabs({
    super.key,
    this.title,
    required this.current,
    required this.pages,
    required this.child,
  });

  /// An optional overall heading (e.g. 'Tasks') shown above the page tabs.
  final String? title;

  /// The DesktopTab being shown.
  final int current;

  /// Every possible tab, in order: (DesktopTab, label).
  final List<(int, String)> pages;

  /// The screen for [current].
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = {
      for (final t in sidebarTabs(
        dental: ref.watch(dentalFeaturesProvider),
        access: ref.watch(clinicAccessProvider).value,
      ))
        t.tab,
    };
    final shown = [
      for (final p in pages)
        if (allowed.contains(p.$1)) p,
    ];
    if (shown.length < 2) {
      if (title == null) return child;
      return PageTabsScope(title: title, tabs: null, child: child);
    }

    return PageTabsScope(
      title: title,
      tabs: _PageSwitcher(
        pages: shown,
        current: current,
        onSelect: (tab) => ref.read(shellNavigatorProvider)?.call(tab),
      ),
      child: child,
    );
  }
}

/// Switches between the pages that share a sidebar item.
class _PageSwitcher extends StatelessWidget {
  const _PageSwitcher({
    required this.pages,
    required this.current,
    required this.onSelect,
  });

  final List<(int, String)> pages;
  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    // The same segmented switch as Inventory's Items · Orders · Vendors.
    return CruSegmentedControl<int>(
      semanticLabel: 'Pages',
      segments: [for (final (tab, label) in pages) CruSegment(tab, label)],
      selected: current,
      onChanged: (tab) {
        if (tab != current) onSelect(tab);
      },
    );
  }
}

/// A page opened from another page rather than the sidebar (Procedures
/// and form templates, from Settings › Dental), with a "‹ Settings" link
/// in its top margin to go back.
class DesktopBackPage extends ConsumerWidget {
  const DesktopBackPage({
    super.key,
    required this.backLabel,
    required this.backTab,
    required this.child,
  });

  final String backLabel;

  /// The DesktopTab the link returns to.
  final int backTab;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final padding = MediaQuery.sizeOf(context).width < CruBreakpoint.compact
        ? CruSpace.mainPaddingCompact
        : CruSpace.mainPadding;
    // The link sits in the page's top margin, so the title below it stays
    // at the same height as on every other page.
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          left: padding.left,
          top: (padding.top - CruSpace.s24).clamp(0, padding.top),
          child: CruLink(
            label: backLabel,
            leading: CruIcon(CruIcons.chevronLeft, size: 16, color: c.accent),
            onPressed: () => ref.read(shellNavigatorProvider)?.call(backTab),
          ),
        ),
      ],
    );
  }
}
