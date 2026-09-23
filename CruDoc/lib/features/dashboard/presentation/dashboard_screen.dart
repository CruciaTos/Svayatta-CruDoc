import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/wrap_up_providers.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/wrap_up_card.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_models.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/dashboard_header.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/glance_card.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/schedule_card.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/side_cards.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/up_next_card.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_today_card.dart';

/// The Calm Clinical desktop dashboard: "Who's next, and what must I
/// know before they walk in?"
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({
    super.key,
    required this.onNavigateToTab,
    this.searchFocusNode,
  });

  final ValueChanged<int> onNavigateToTab;

  /// Focused by Ctrl/⌘ K (handled by the shell).
  final FocusNode? searchFocusNode;

  @override
  ConsumerState<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends ConsumerState<DashboardScreen> {
  /// Enter on the dashboard starts the Up next consultation.
  void startUpNext() {
    final upNext = ref.read(dashboardDataProvider).upNext;
    if (upNext == null) return;
    DashboardActions.startConsultation(
      context,
      ref,
      upNext,
      navigate: widget.onNavigateToTab,
    );
  }

  bool get _isDentist =>
      ref.watch(doctorIdentityProvider).specialty?.toLowerCase().contains('dent') ??
      false;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dashboardDataProvider);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= CruBreakpoint.wide;
    final compact = width < CruBreakpoint.compact;

    final left = <Widget>[
      if (!data.scheduleReady)
        const SkeletonCard(rows: 2, rowHeight: 48)
      else if (data.upNext != null)
        UpNextCard(data: data.upNext!, navigate: widget.onNavigateToTab)
      else
        NoOneWaitingCard(nextBooking: data.nextBooking),
      data.schedule == null
          ? const SkeletonCard(rows: 5)
          : ScheduleCard(items: data.schedule!, now: data.now),
      // Dentists: today's sterilization and plans waiting for a yes.
      if (_isDentist) DentalTodayCard(onNavigate: widget.onNavigateToTab),
    ];

    final right = <Widget>[
      ..._rightColumnTop(context, data),
      data.collections == null
          ? const SkeletonCard(rows: 1, rowHeight: 140)
          : CollectionsCard(data: data.collections!),
    ];

    Widget body;
    if (wide) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _stack(left)),
          const SizedBox(width: CruSpace.cardGap),
          SizedBox(width: CruSize.rightColumn, child: _stack(right)),
        ],
      );
    } else {
      // Right column drops below the main column, two-up while there's
      // room for it.
      body = LayoutBuilder(builder: (context, constraints) {
        final twoUp = constraints.maxWidth >= 720 && right.length > 1;
        return _stack([
          ...left,
          if (twoUp)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _stack(right.sublist(0, right.length - 1))),
                const SizedBox(width: CruSpace.cardGap),
                Expanded(child: right.last),
              ],
            )
          else
            ...right,
        ]);
      });
    }

    return SingleChildScrollView(
      padding: compact
          ? const EdgeInsets.fromLTRB(12, 24, 24, 24)
          : CruSpace.mainPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardHeader(searchFocusNode: widget.searchFocusNode),
          const SizedBox(height: CruSpace.stackGap),
          GlanceCard(glance: data.glance, collected: data.collected),
          const SizedBox(height: CruSpace.stackGap),
          body,
        ],
      ),
    );
  }

  /// Cards above Collections in the right column: Wrap up the day in the
  /// evening, Needs attention during the day. (Insights stay hidden: no
  /// AI insights are generated from records yet.)
  List<Widget> _rightColumnTop(BuildContext context, DashboardData data) {
    if (context.cru.isEvening) {
      final wrapUp = ref.watch(wrapUpProvider);
      if (wrapUp == null || !wrapUp.hasRows) return const [];
      return [WrapUpCard(data: wrapUp, navigate: widget.onNavigateToTab)];
    }
    final attention = data.attention;
    if (attention == null || attention.isEmpty) return const [];
    return [
      NeedsAttentionCard(
        items: attention,
        onOpenInventory: () => widget.onNavigateToTab(DesktopTab.inventory),
      ),
    ];
  }

  static Widget _stack(List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: CruSpace.cardGap),
            children[i],
          ],
        ],
      );
}
