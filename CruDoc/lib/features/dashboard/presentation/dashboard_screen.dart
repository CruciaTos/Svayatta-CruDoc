import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/radiology/presentation/radiology_cards.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
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
import 'package:doctor_management_app/features/dental/specialties/specialty_cards.dart';

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

  bool get _isDentist => ref.watch(isDentistProvider);

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dashboardDataProvider);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= CruBreakpoint.wide;
    final compact = width < CruBreakpoint.compact;
    final theme = Theme.of(context);
    final dashboardColors = context.cru.copyWith(
      cardShadow: const [],
      segmentShadow: const [],
      inkShadow: const [],
      paneShadow: const [],
      hairline: Colors.transparent,
      separator: Colors.transparent,
    );
    final dashboardTheme = theme.copyWith(
      extensions: theme.extensions.values
          .map(
            (extension) => extension is CruColors ? dashboardColors : extension,
          )
          .toList(),
      popupMenuTheme: theme.popupMenuTheme.copyWith(
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
    );

    final left = <Widget>[
      data.schedule == null
          ? const SkeletonCard(rows: 5)
          : ScheduleCard(items: data.schedule!, now: data.now),
      // Dentists: today's sterilization and plans waiting for a yes.
      if (_isDentist) DentalTodayCard(onNavigate: widget.onNavigateToTab),
      // Dental sub-specialty cards (perio, endo, ortho, …).
      ...dentalSpecialtyCards(
        ref.watch(activeDentalSubspecialtyProvider),
        widget.onNavigateToTab,
      ),
      // Oral & Maxillofacial Radiologists and dentists: what's waiting to be read.
      if (ref.watch(isOralRadiologistProvider) || _isDentist)
        RadiologyTodayCard(onNavigate: widget.onNavigateToTab),
    ];

    final upNext = !data.scheduleReady
        ? const SkeletonCard(rows: 2, rowHeight: 48)
        : data.upNext != null
        ? UpNextCard(data: data.upNext!, navigate: widget.onNavigateToTab)
        : NoOneWaitingCard(nextBooking: data.nextBooking);

    final right = <Widget>[
      upNext,
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
      body = LayoutBuilder(
        builder: (context, constraints) {
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
        },
      );
    }

    return Theme(
      data: dashboardTheme,
      child: SingleChildScrollView(
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
      ),
    );
  }

  /// Cards above Collections in the right column. Content follows the live
  /// records, not the selected light/dark appearance.
  List<Widget> _rightColumnTop(BuildContext context, DashboardData data) {
    final cards = <Widget>[];
    final attention = data.attention;
    if (attention != null && attention.isNotEmpty) {
      cards.add(
        NeedsAttentionCard(
          items: attention,
          onOpenInventory: () => widget.onNavigateToTab(DesktopTab.inventory),
        ),
      );
    }
    final wrapUp = ref.watch(wrapUpProvider);
    if (wrapUp != null && wrapUp.hasRows) {
      cards.add(WrapUpCard(data: wrapUp, navigate: widget.onNavigateToTab));
    }
    return cards;
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
