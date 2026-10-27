import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/shell/components/cru_sidebar.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/shared/widgets/page_tabs_scope.dart';
import 'package:doctor_management_app/shared/widgets/swipe_pages.dart';

/// Several sidebar pages shown as one, with a segmented control in place of
/// the page title (Tasks: worklist, reports, treatment plans, lab cases;
/// Referrals: sent and referrers). The pages sit side by side as
/// [SwipePages]: drag sideways to the next one. The heading and the switch
/// stay put (pinned in [DentalPageHeader]); the rest of the page slides.
/// Each tab is still its own DesktopTab, so voice, shortcuts and saved
/// tabs keep working; only the tabs this login has are shown.
class DesktopPageTabs extends ConsumerWidget {
  const DesktopPageTabs({
    super.key,
    this.title,
    required this.current,
    required this.pages,
    required this.builder,
  });

  /// An optional overall heading (e.g. 'Tasks') shown above the page tabs.
  final String? title;

  /// The DesktopTab being shown.
  final int current;

  /// Every possible tab, in order: (DesktopTab, label).
  final List<(int, String)> pages;

  /// The screen for a tab.
  final Widget Function(int tab) builder;

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
      final child = builder(current);
      if (title == null) return child;
      return PageTabsScope(title: title, tabs: null, child: child);
    }

    void select(int tab) => ref.read(shellNavigatorProvider)?.call(tab);
    return SwipePages<int>(
      values: [for (final (tab, _) in shown) tab],
      value: current,
      onChanged: select,
      builder: (context, tab) => PageTabsScope(
        title: title,
        // Every page's switch shows the selected tab: it's pinned, so the
        // copies must match.
        tabs: _PageSwitcher(pages: shown, current: current, onSelect: select),
        child: builder(tab),
      ),
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
/// and form templates from Settings › Dental, Recalls from Patients). Its
/// header shows a back button before the title (see [PageBackScope]), so
/// the title stays at the same height as on every other page.
class DesktopBackPage extends ConsumerWidget {
  const DesktopBackPage({
    super.key,
    required this.backLabel,
    required this.backTab,
    required this.child,
  });

  final String backLabel;

  /// The DesktopTab the back button returns to.
  final int backTab;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PageBackScope(
      label: backLabel,
      onBack: () => ref.read(shellNavigatorProvider)?.call(backTab),
      child: child,
    );
  }
}
