import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/appointment_actions.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_format.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/core/clinic/clinic_doctors_provider.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/shell/components/cru_sidebar.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/features/tutorial/presentation/tutorial_target.dart';

/// Width of the header's one filled button, the same in every Schedule
/// view ("New appointment", "Call next token", "Finish & call next") so
/// the view switcher and search never move when the view changes.
const double kSchedulePrimaryWidth = 196;

/// Below this width (tablets in portrait) the Live view's filter row
/// wraps onto two rows.
const double kScheduleHeaderOneRow = 1080;

/// The Schedule header frame, shared by Live and the calendar views so
/// every control sits in the same place whichever view is open: title +
/// summary on the left; the one filled button (fixed width) on the right;
/// the view switcher on its own row below. Dates are picked from the
/// mini calendar beside the page.
class ScheduleHeaderFrame extends StatelessWidget {
  const ScheduleHeaderFrame({
    super.key,
    required this.title,
    required this.primary,
  });

  /// Usually a [ScheduleTitle].
  final Widget title;

  /// The one filled button; laid out at [kSchedulePrimaryWidth].
  final Widget primary;

  @override
  Widget build(BuildContext context) {
    // The view switcher sits on its own row, under the title and summary.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(context),
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
  }

  Widget _row(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Align(alignment: Alignment.centerLeft, child: title),
        ),
        const SizedBox(width: CruSpace.s16),
        const ScheduleDoctorFilter(),
        const _ScribeButton(),
        SizedBox(width: kSchedulePrimaryWidth, child: primary),
      ],
    );
  }
}

/// Opens Scribe, which left the sidebar for this button: it records the
/// same day's visits Schedule lists. Only where the login has Scribe.
class _ScribeButton extends ConsumerWidget {
  const _ScribeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigate = ref.watch(shellNavigatorProvider);
    final has = sidebarTabs(
      dental: ref.watch(dentalFeaturesProvider),
      access: ref.watch(clinicAccessProvider).value,
    ).any((t) => t.tab == DesktopTab.scribe);
    if (navigate == null || !has) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: CruSpace.s10),
      child: CruSquareButton(
        icon: CruIcons.mic,
        semanticLabel: 'Scribe',
        secondary: true,
        onPressed: () => navigate(DesktopTab.scribe),
      ),
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

    return ScheduleHeaderFrame(
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

/// Live · Week · Month · Agenda, shared by the Live (queue) header and the
/// calendar header. Live needs the queue module, the calendar views need
/// appointments; hidden when only one view is left. Day isn't listed: it
/// opens from a date in Week, Month or Agenda (no segment is lit there).
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
          ApptsView.day => false,
          ApptsView.visits => apptsOn && physio,
          _ => apptsOn,
        })
          v,
    ];
    if (views.length < 2) return const SizedBox.shrink();
    return TutorialAnchor(
      target: TutorialTarget.scheduleViews,
      radius: CruRadius.segmentOuter,
      child: CruSegmentedControl<ApptsView>(
        semanticLabel: 'Schedule view',
        segments: [for (final v in views) CruSegment(v, v.label)],
        selected: ref.watch(effectiveApptsViewProvider),
        onChanged: ref.read(apptsControllerProvider.notifier).setView,
      ),
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
