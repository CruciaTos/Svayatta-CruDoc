import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/appointment_actions.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_format.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appts_search_dialog.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Width of the header's one filled button, the same in every Schedule
/// view ("New appointment", "Call next token", "Finish & call next") so
/// the view switcher and search never move when the view changes.
const double kSchedulePrimaryWidth = 196;

/// Below this width (tablets in portrait) the view switcher moves to its
/// own row under the title; every other control keeps its place.
const double kScheduleHeaderOneRow = 1080;

/// The Schedule header frame, shared by Live and the calendar views so
/// every control sits in the same place whichever view is open: Today,
/// ‹ ›, title + summary on the left; the view switcher, search and the
/// one filled button (fixed width) on the right.
class ScheduleHeaderFrame extends StatelessWidget {
  const ScheduleHeaderFrame({
    super.key,
    required this.stepLabel,
    required this.onToday,
    required this.onStep,
    required this.title,
    required this.primary,
  });

  /// "day", "week" or "month" (for the ‹ › labels).
  final String stepLabel;
  final VoidCallback onToday;
  final ValueChanged<int> onStep;

  /// Usually a [ScheduleTitle].
  final Widget title;

  /// The one filled button; laid out at [kSchedulePrimaryWidth].
  final Widget primary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final oneRow = constraints.maxWidth >= kScheduleHeaderOneRow;
        final top = _row(context, switcher: oneRow);
        if (oneRow) return top;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            top,
            const SizedBox(height: CruSpace.s12),
            const Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ScheduleViewSwitcher(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _row(BuildContext context, {required bool switcher}) {
    return Row(
      children: [
        CruButton(
          label: 'Today',
          kind: CruButtonKind.secondary,
          onPressed: onToday,
        ),
        const SizedBox(width: CruSpace.s12),
        CruIconButton(
          icon: CruIcons.chevronLeft,
          semanticLabel: 'Previous $stepLabel',
          size: CruSize.squareButton,
          onPressed: () => onStep(-1),
        ),
        const SizedBox(width: CruSpace.s4),
        CruIconButton(
          icon: CruIcons.chevronRight,
          semanticLabel: 'Next $stepLabel',
          size: CruSize.squareButton,
          onPressed: () => onStep(1),
        ),
        const SizedBox(width: CruSpace.s16),
        Expanded(child: title),
        const SizedBox(width: CruSpace.s24),
        if (switcher) ...[
          const ScheduleViewSwitcher(),
          const SizedBox(width: CruSpace.s10),
        ],
        CruSquareButton(
          icon: CruIcons.search,
          semanticLabel: 'Search appointments',
          secondary: true,
          onPressed: () => showApptsSearchDialog(context),
        ),
        const SizedBox(width: CruSpace.s10),
        SizedBox(width: kSchedulePrimaryWidth, child: primary),
      ],
    );
  }
}

/// Title (22/600) over a one-line 13.5 px summary. The summary line has a
/// fixed height so the header never jumps while data loads.
class ScheduleTitle extends StatelessWidget {
  const ScheduleTitle({
    super.key,
    required this.title,
    this.shortTitle,
    this.summary,
  });

  final String title;

  /// Shown instead of [title] when it doesn't fit ("Wed, 23 September").
  final String? shortTitle;

  /// Null while loading.
  final InlineSpan? summary;

  /// One line of 13.5/18 summary text.
  static const double _summaryHeight = 18;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final style = CruType.amount.tint(c.label);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            var text = title;
            if (shortTitle != null) {
              final painter = TextPainter(
                text: TextSpan(text: title, style: style),
                maxLines: 1,
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              if (painter.width > constraints.maxWidth) text = shortTitle!;
              painter.dispose();
            }
            return Text(
              text,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
        SizedBox(
          height: _summaryHeight,
          child: summary == null
              ? const SizedBox.shrink()
              : Text.rich(
                  summary!,
                  style: CruType.dateLine.tabular.tint(c.label2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
      ],
    );
  }
}

/// The calendar views' header: "New appointment" is the filled button.
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

    return ScheduleHeaderFrame(
      stepLabel: stepLabel,
      onToday: controller.today,
      onStep: controller.step,
      title: _TitleBlock(state: state),
      primary: CruButton(
        label: state.view == ApptsView.visits
            ? 'New home visit'
            : 'New appointment',
        icon: CruIcons.plus,
        expand: true,
        onPressed: () => ApptActions.newAppointment(
          context,
          ref,
          day: state.view == ApptsView.day || state.view == ApptsView.visits
              ? state.anchor
              : null,
          type: state.view == ApptsView.visits
              ? VisitType.home
              : VisitType.clinic,
        ),
      ),
    );
  }
}

/// Live · Day · Week · Month · Agenda, shared by the Live (queue) header
/// and the calendar header. Live needs the queue module, the calendar
/// views need appointments; hidden when only one view is left.
class ScheduleViewSwitcher extends ConsumerWidget {
  const ScheduleViewSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueOn = ref.watch(isQueueFeatureEnabledProvider);
    final apptsOn = ref.watch(isAppointmentsFeatureEnabledProvider);
    final physio = ref.watch(isPhysiotherapyProvider);
    final views = [
      for (final v in ApptsView.values)
        if (switch (v) {
          ApptsView.live => queueOn,
          ApptsView.visits => apptsOn && physio,
          _ => apptsOn,
        })
          v,
    ];
    if (views.length < 2) return const SizedBox.shrink();
    return CruSegmentedControl<ApptsView>(
      semanticLabel: 'Schedule view',
      segments: [for (final v in views) CruSegment(v, v.label)],
      selected: ref.watch(effectiveApptsViewProvider),
      onChanged: ref.read(apptsControllerProvider.notifier).setView,
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
      ApptsView.live ||
      ApptsView.day ||
      ApptsView.agenda ||
      ApptsView.visits => ApptFormat.dateLine(anchor),
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
          final seen = ApptsBuilder.patientsWith(items, ApptStatus.done);
          final missed = items
              .where((i) => i.status == ApptStatus.missed)
              .length;
          summary = [
            DashFormat.plural(items.length, 'appointment'),
            '$seen seen',
            '$missed missed',
          ].join(' · ');
        case ApptsView.month:
          final first = DateTime(anchor.year, anchor.month);
          final next = DateTime(anchor.year, anchor.month + 1);
          final items = ApptsBuilder.inRange(all, first, next);
          final seen = ApptsBuilder.patientsWith(items, ApptStatus.done);
          summary =
              '${DashFormat.plural(items.length, 'appointment')} · '
              '$seen seen so far';
        case ApptsView.live:
          break;
        case ApptsView.visits:
          final home = ApptsBuilder.forDay(
            all,
            anchor,
          ).where((i) => i.visit.visitType == VisitType.home).length;
          summary = home == 0
              ? 'No home visits'
              : DashFormat.plural(home, 'home visit');
        case ApptsView.agenda:
          final from = ApptsBuilder.dateOnly(anchor);
          final upcoming = all.where((i) => !i.start.isBefore(from)).length;
          summary = '$upcoming upcoming';
      }
    }

    final summaryStyle = CruType.dateLine.tabular.tint(c.label2);
    return ScheduleTitle(
      title: title,
      shortTitle: switch (state.view) {
        ApptsView.week || ApptsView.month => null,
        _ => DateFormat('EEE, d MMMM').format(anchor),
      },
      summary: summary == null
          ? null
          : TextSpan(
              text: summary,
              children: [
                if (unsorted > 0)
                  TextSpan(
                    text: ' · ${ApptFormat.overlaps(unsorted)} to sort out',
                    style: summaryStyle.w500.tint(c.amberText),
                  ),
              ],
            ),
    );
  }

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
