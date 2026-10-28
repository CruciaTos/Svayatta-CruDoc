import 'dart:math' as math;

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
import 'package:doctor_management_app/shared/widgets/swipe_pages.dart';
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
/// summary on the left; the calendar button (go to a month or year) and
/// the one filled button (fixed width) on the right; the view switcher on
/// its own row below. Away from today the title is outlined and takes you
/// back.
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
    // Nothing here slides with the views: the switcher, doctor filter and
    // Scribe stay put, and each view's title and button fade in place.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(context),
        const SizedBox(height: CruSpace.s12),
        const SwipePinned(
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ScheduleViewSwitcher(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SwipePinned.fade(
            child: Align(alignment: Alignment.centerLeft, child: title),
          ),
        ),
        const SizedBox(width: CruSpace.s16),
        const SwipePinned(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScheduleDoctorFilter(),
              _MonthYearButton(),
              _ScribeButton(),
            ],
          ),
        ),
        SwipePinned.fade(
          child: SizedBox(width: kSchedulePrimaryWidth, child: primary),
        ),
      ],
    );
  }
}

/// The calendar button: pick a month, and a year, to jump to. Day and
/// Week keep the day of the month; from Live it opens that month in Month.
class _MonthYearButton extends ConsumerStatefulWidget {
  const _MonthYearButton();

  @override
  ConsumerState<_MonthYearButton> createState() => _MonthYearButtonState();
}

class _MonthYearButtonState extends ConsumerState<_MonthYearButton> {
  final _menu = MenuController();

  void _goTo(int year, int month) {
    _menu.close();
    final controller = ref.read(apptsControllerProvider.notifier);
    final anchor = ref.read(apptsControllerProvider).anchor;
    final view = ref.read(effectiveApptsViewProvider);
    final toMonth = view == ApptsView.live || view == ApptsView.month;
    if (view == ApptsView.live) controller.setView(ApptsView.month);
    final day = toMonth
        ? 1
        : math.min(anchor.day, DateUtils.getDaysInMonth(year, month));
    controller.goTo(DateTime(year, month, day));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final anchor = ref.watch(apptsControllerProvider.select((s) => s.anchor));
    final today = ApptsBuilder.dateOnly(ref.watch(apptsNowProvider));
    return Padding(
      padding: const EdgeInsets.only(right: CruSpace.s10),
      child: MenuAnchor(
        controller: _menu,
        // Right edge under the button's (the button sits near the window's
        // right edge): the menu is the picker plus its padding.
        alignmentOffset: const Offset(
          CruSize.control - _MonthYearPickerState._width - 2 * CruSpace.s8,
          CruSpace.s6,
        ),
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(c.surface),
          surfaceTintColor: WidgetStatePropertyAll(
            c.surface.withValues(alpha: 0),
          ),
          shadowColor: WidgetStatePropertyAll(c.label.withValues(alpha: 0.18)),
          // A soft lift: it opens over the white week card.
          elevation: const WidgetStatePropertyAll(8),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(CruSpace.s8)),
          shape: WidgetStatePropertyAll(
            RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(CruRadius.control),
              side: BorderSide(color: c.hairline),
            ),
          ),
        ),
        menuChildren: [
          _MonthYearPicker(shown: anchor, today: today, onPick: _goTo),
        ],
        builder: (context, controller, _) => CruSquareButton(
          icon: CruIcons.calendar,
          semanticLabel: 'Go to a month',
          tooltip: 'Go to a month',
          secondary: true,
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      ),
    );
  }
}

/// The year (‹ 2026 ›) over its twelve months. The month on screen has a
/// tint; this month is in accent text.
class _MonthYearPicker extends StatefulWidget {
  const _MonthYearPicker({
    required this.shown,
    required this.today,
    required this.onPick,
  });

  final DateTime shown;
  final DateTime today;
  final void Function(int year, int month) onPick;

  @override
  State<_MonthYearPicker> createState() => _MonthYearPickerState();
}

class _MonthYearPickerState extends State<_MonthYearPicker> {
  late int _year = widget.shown.year;

  static const double _width = 264;
  static const double _cell = 36;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    Widget month(int m) {
      final shown = _year == widget.shown.year && m == widget.shown.month;
      final now = _year == widget.today.year && m == widget.today.month;
      final ink = shown || now ? c.accentText : c.label;
      return CruPressable(
        onTap: () => widget.onPick(_year, m),
        semanticLabel: DateFormat('MMMM y').format(DateTime(_year, m)),
        scaleOnPress: false,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: _cell,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: shown
                ? c.accentTint
                : hovered
                ? c.hoverFill
                : c.hoverFill.withValues(alpha: 0),
            shape: cruShape(CruRadius.control - CruSpace.s4),
          ),
          child: Text(
            DateFormat('MMM').format(DateTime(_year, m)),
            style: (shown || now ? CruType.text.w600 : CruType.text.w500).tint(
              ink,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: _width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CruIconButton(
                icon: CruIcons.chevronLeft,
                size: CruSize.capsule,
                iconSize: 16,
                semanticLabel: 'Previous year',
                tooltip: 'Previous year',
                onPressed: () => setState(() => _year--),
              ),
              Expanded(
                child: Text(
                  '$_year',
                  textAlign: TextAlign.center,
                  style: CruType.row.w600.tabular.tint(c.label),
                ),
              ),
              CruIconButton(
                icon: CruIcons.chevronRight,
                size: CruSize.capsule,
                iconSize: 16,
                semanticLabel: 'Next year',
                tooltip: 'Next year',
                onPressed: () => setState(() => _year++),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s8),
          for (var row = 0; row < 4; row++) ...[
            if (row > 0) const SizedBox(height: CruSpace.s4),
            Row(
              children: [
                for (var col = 0; col < 3; col++) ...[
                  if (col > 0) const SizedBox(width: CruSpace.s4),
                  Expanded(child: month(row * 3 + col + 1)),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The title line of a view that doesn't show today: always on a light
/// blue fill with a blue outline; hover makes the outline solid. Clicking
/// it goes back to today.
class _BackToToday extends ConsumerWidget {
  const _BackToToday({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    return CruPressable(
      onTap: ref.read(apptsControllerProvider.notifier).today,
      semanticLabel: 'Back to today',
      tooltip: 'Back to today',
      scaleOnPress: false,
      builder: (context, hovered) => Stack(
        clipBehavior: Clip.none,
        children: [
          // Drawn around the text, so the title doesn't move.
          Positioned(
            left: -CruSpace.s10,
            right: -CruSpace.s10,
            top: -CruSpace.s4,
            bottom: -CruSpace.s2,
            child: AnimatedContainer(
              duration: CruMotion.of(context, CruMotion.fast),
              curve: CruMotion.curve,
              decoration: ShapeDecoration(
                color: c.accentTint,
                shape: cruShape(
                  CruRadius.control,
                  side: BorderSide(
                    color: hovered ? c.accent : c.accent.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
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
    this.wrapTitle,
  });

  final String title;

  /// Shown instead of [title] when it doesn't fit ("Wed, 23 September").
  final String? shortTitle;

  /// Null while loading.
  final InlineSpan? summary;

  /// Wraps the title line alone (not the summary): the "back to today"
  /// outline.
  final Widget Function(Widget title)? wrapTitle;

  /// One line of 13.5/18 summary text.
  static const double _summaryHeight = 18;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final style = CruType.amount.tint(c.label);
    final line = LayoutBuilder(
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
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: CruMotion.of(context, CruMotion.fast),
          switchInCurve: CruMotion.curve,
          switchOutCurve: CruMotion.curve,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.centerLeft,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          ),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: KeyedSubtree(
            key: ValueKey<String>(title),
            child: wrapTitle?.call(line) ?? line,
          ),
        ),
        SizedBox(
          height: _summaryHeight,
          child: AnimatedSwitcher(
            duration: CruMotion.of(context, CruMotion.fast),
            switchInCurve: CruMotion.curve,
            switchOutCurve: CruMotion.curve,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: Alignment.centerLeft,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            ),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: summary == null
                ? const SizedBox.shrink(key: ValueKey<String>('empty'))
                : Text.rich(
                    summary!,
                    key: ValueKey<String>(summary!.toPlainText()),
                    style: CruType.dateLine.tabular.tint(c.accentText),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        ),
      ],
    );
  }
}

/// Marks a Schedule page with the view it shows, so its title, summary
/// and button show that view while the page slides in beside the open one.
class ScheduleViewPage extends InheritedWidget {
  const ScheduleViewPage({super.key, required this.view, required super.child});

  final ApptsView view;

  static ApptsView? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ScheduleViewPage>()?.view;

  @override
  bool updateShouldNotify(ScheduleViewPage oldWidget) => oldWidget.view != view;
}

/// The calendar views' header: "New appointment" is the filled button.
class ApptsHeader extends ConsumerWidget {
  const ApptsHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ScheduleViewPage.maybeOf(context);
    var state = ref.watch(apptsControllerProvider);
    if (page != null) state = state.copyWith(view: page);

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

/// Live · Week (or Day) · Month · Agenda, shared by the Live (queue) header
/// and the calendar header. Live needs the queue module, the calendar views
/// need appointments; hidden when only one view is left. When Day view is open,
/// the Week segment changes to Day.
class ScheduleViewSwitcher extends ConsumerWidget {
  const ScheduleViewSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueOn = ref.watch(isQueueFeatureEnabledProvider);
    final apptsOn = ref.watch(isAppointmentsFeatureEnabledProvider);
    final physio = ref.watch(isPhysiotherapyProvider);
    final current = ref.watch(effectiveApptsViewProvider);
    final isDay = current == ApptsView.day;
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
        segments: [
          for (final v in views)
            if (v == ApptsView.week && isDay)
              const CruSegment(ApptsView.day, 'Day')
            else
              CruSegment(v, v.label),
        ],
        // The open view, on every page: the switcher is pinned, so the
        // copies must match.
        selected: current,
        onChanged: (v) {
          final controller = ref.read(apptsControllerProvider.notifier);
          if (v == ApptsView.day) {
            controller.setView(ApptsView.week);
          } else {
            controller.setView(v);
          }
        },
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

    // Does the view show today? If not, the title takes you back to it.
    final today = ApptsBuilder.dateOnly(now);
    final showsToday = switch (state.view) {
      ApptsView.week => ApptsBuilder.weekDays(
        anchor,
      ).any((d) => ApptsBuilder.sameDay(d, today)),
      ApptsView.month =>
        anchor.year == today.year && anchor.month == today.month,
      _ => ApptsBuilder.sameDay(anchor, today),
    };

    final summaryStyle = CruType.dateLine.tabular.tint(c.accentText);
    return ScheduleTitle(
      title: title,
      // The outline hugs the title line alone ("August 2026").
      wrapTitle: showsToday ? null : (line) => _BackToToday(child: line),
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
