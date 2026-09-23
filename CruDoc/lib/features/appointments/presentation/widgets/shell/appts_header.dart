import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/appointment_actions.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_format.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appts_search_dialog.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Today, ‹ ›, title + summary on the left; Day / Week / Month / Agenda,
/// search and "New appointment" (the only filled button) on the right.
class ApptsHeader extends ConsumerWidget {
  const ApptsHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(apptsControllerProvider);
    final controller = ref.read(apptsControllerProvider.notifier);
    final stepLabel = switch (state.view) {
      ApptsView.week => 'week',
      ApptsView.month => 'month',
      _ => 'day',
    };

    return Row(
      children: [
        CruButton(
          label: 'Today',
          kind: CruButtonKind.secondary,
          onPressed: controller.today,
        ),
        const SizedBox(width: CruSpace.s12),
        CruIconButton(
          icon: CruIcons.chevronLeft,
          semanticLabel: 'Previous $stepLabel',
          size: CruSize.squareButton,
          onPressed: () => controller.step(-1),
        ),
        const SizedBox(width: CruSpace.s4),
        CruIconButton(
          icon: CruIcons.chevronRight,
          semanticLabel: 'Next $stepLabel',
          size: CruSize.squareButton,
          onPressed: () => controller.step(1),
        ),
        const SizedBox(width: CruSpace.s16),
        Expanded(child: _TitleBlock(state: state)),
        const SizedBox(width: CruSpace.s24),
        CruSegmentedControl<ApptsView>(
          semanticLabel: 'Calendar view',
          segments: [
            for (final v in ApptsView.values) CruSegment(v, v.label),
          ],
          selected: state.view,
          onChanged: controller.setView,
        ),
        const SizedBox(width: CruSpace.s10),
        CruSquareButton(
          icon: CruIcons.search,
          semanticLabel: 'Search appointments',
          secondary: true,
          onPressed: () => showApptsSearchDialog(context),
        ),
        const SizedBox(width: CruSpace.s10),
        CruButton(
          label: 'New appointment',
          icon: CruIcons.plus,
          onPressed: () => ApptActions.newAppointment(
            context,
            ref,
            day: state.view == ApptsView.day ? state.anchor : null,
          ),
        ),
      ],
    );
  }
}

class _TitleBlock extends ConsumerWidget {
  const _TitleBlock({required this.state});

  final ApptsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final anchor = state.anchor;
    final now = ref.watch(apptsNowProvider);
    final all = ref.watch(apptItemsProvider).value;

    final title = switch (state.view) {
      ApptsView.day || ApptsView.agenda => ApptFormat.dateLine(anchor),
      ApptsView.week => _weekTitle(anchor),
      ApptsView.month => DateFormat('MMMM yyyy').format(anchor),
    };

    String? summary;
    var unsorted = 0;
    if (all != null) {
      switch (state.view) {
        case ApptsView.day:
          final counts = ApptsBuilder.counts(
            ApptsBuilder.forDay(all, anchor),
            anchor,
            now,
          );
          summary = [
            DashFormat.plural(counts.appointments, 'appointment'),
            if (counts.seen > 0) '${counts.seen} seen',
            // With an overlap to sort out the line gives way to it (as in
            // the design); the grid still shows who is in and waiting.
            if (counts.unsortedOverlaps == 0 && counts.inConsultation > 0)
              '${counts.inConsultation} in consultation',
            if (counts.unsortedOverlaps == 0 && counts.waiting > 0)
              '${counts.waiting} waiting',
          ].join(' · ');
          unsorted = counts.unsortedOverlaps;
        case ApptsView.week:
          final days = ApptsBuilder.weekDays(anchor);
          final items = ApptsBuilder.inRange(
            all,
            days.first,
            days.last.add(const Duration(days: 1)),
          );
          final seen = items.where((i) => i.status == ApptStatus.done).length;
          final missed =
              items.where((i) => i.status == ApptStatus.missed).length;
          summary = [
            DashFormat.plural(items.length, 'appointment'),
            '$seen seen',
            '$missed missed',
          ].join(' · ');
        case ApptsView.month:
          final first = DateTime(anchor.year, anchor.month);
          final next = DateTime(anchor.year, anchor.month + 1);
          final items = ApptsBuilder.inRange(all, first, next);
          final seen = items.where((i) => i.status == ApptStatus.done).length;
          summary = '${DashFormat.plural(items.length, 'appointment')} · '
              '$seen seen so far';
        case ApptsView.agenda:
          final from = ApptsBuilder.dateOnly(anchor);
          final upcoming = all.where((i) => !i.start.isBefore(from)).length;
          summary = '$upcoming upcoming';
      }
    }

    final summaryStyle = CruType.dateLine.tabular.tint(c.label2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: CruType.amount.tint(c.label),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // Fixed height so the header never jumps while data loads.
        SizedBox(
          height: _summaryHeight,
          child: summary == null
              ? const SizedBox.shrink()
              : Text.rich(
                  TextSpan(
                    text: summary,
                    children: [
                      if (unsorted > 0)
                        TextSpan(
                          text: ' · ${ApptFormat.overlaps(unsorted)} to sort out',
                          style: summaryStyle.w500.tint(c.amberText),
                        ),
                    ],
                  ),
                  style: summaryStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
      ],
    );
  }

  /// One line of 13.5/18 summary text.
  static const double _summaryHeight = 18;

  /// "21 to 27 September", "28 September to 4 October".
  static String _weekTitle(DateTime anchor) {
    final days = ApptsBuilder.weekDays(anchor);
    final a = days.first;
    final b = days.last;
    final end = DateFormat('d MMMM').format(b);
    if (a.month == b.month) return '${a.day} to $end';
    return '${DateFormat('d MMMM').format(a)} to $end';
  }
}
