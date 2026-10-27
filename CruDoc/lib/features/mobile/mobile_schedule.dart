import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/appointment_actions.dart';
import 'package:doctor_management_app/features/appointments/presentation/patient_picker_dialog.dart';
import 'package:doctor_management_app/features/appointments/presentation/schedule_visit_sheet.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_models.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/mobile/mobile_more.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_actions.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/shell/components/cru_sidebar.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The selected day on the phone's Schedule. Kept for the session.
final mobileScheduleDayProvider = NotifierProvider<_DayController, DateTime>(
  _DayController.new,
);

class _DayController extends Notifier<DateTime> {
  @override
  DateTime build() => ApptsBuilder.dateOnly(ref.read(apptsNowProvider));

  void select(DateTime day) => state = ApptsBuilder.dateOnly(day);
}

/// Schedule: a week strip and the chosen day's list. Today's rows move
/// people along with a right swipe (check in, call in, finish); a long
/// press has everything else.
class MobileScheduleScreen extends ConsumerStatefulWidget {
  const MobileScheduleScreen({super.key, this.enabledModules});

  /// The doctor's modules (Scribe's button needs `ai_assistant`).
  final List<String>? enabledModules;

  @override
  ConsumerState<MobileScheduleScreen> createState() =>
      _MobileScheduleScreenState();
}

class _MobileScheduleScreenState extends ConsumerState<MobileScheduleScreen>
    with SingleTickerProviderStateMixin {
  /// Week pages around the current week; page [_anchor] is this week.
  static const _anchor = 520;
  late PageController _weeks = PageController(initialPage: _anchor);
  int _page = _anchor;
  bool _isMonthExpanded = false;
  late DateTime _monthDate;

  /// The month row that is the week strip: it slides down into its slot as
  /// the month opens, and back up as it closes.
  int _anchorRow = 0;
  late final AnimationController _expand = AnimationController(
    vsync: this,
    duration: CruMotion.standard,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _expand,
    curve: CruMotion.curve,
  );

  /// Month pages, made each time the month finishes opening (on the month
  /// then on screen); null until the month first opens.
  PageController? _months;

  /// Where the chevrons are taking the months while they slide, so quick
  /// taps add up.
  int _monthTarget = 0;
  int _monthSlides = 0;

  @override
  void initState() {
    super.initState();
    _monthDate = DateTime.now();
    _expand.addStatusListener(_onExpandStatus);
  }

  @override
  void dispose() {
    _expand.dispose();
    _weeks.dispose();
    _months?.dispose();
    super.dispose();
  }

  /// Once the month is fully open, the animated grid hands over to pages
  /// that follow the finger, starting on the same month.
  void _onExpandStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_isMonthExpanded) return;
    _months?.dispose();
    _months = PageController(initialPage: _monthPage(_monthDate));
  }

  void _goToMonthPage(int page) {
    final months = _months;
    if (months == null || !months.hasClients) return;
    final duration = CruMotion.of(context);
    if (duration == Duration.zero) {
      months.jumpToPage(page);
      return;
    }
    _monthTarget = page;
    _monthSlides++;
    months
        .animateToPage(page, duration: duration, curve: CruMotion.curve)
        .whenComplete(() => _monthSlides--);
  }

  void _stepMonth(int delta) => _goToMonthPage(
    (_monthSlides > 0 ? _monthTarget : _monthPage(_monthDate)) + delta,
  );

  void _pickFromMonth(DateTime day) {
    _select(day);
    _collapse();
  }

  DateTime _monday(DateTime d) =>
      ApptsBuilder.dateOnly(d).subtract(Duration(days: d.weekday - 1));

  DateTime _weekStart(int page) => _monday(
    ref.read(apptsNowProvider),
  ).add(Duration(days: 7 * (page - _anchor)));

  int _pageOf(DateTime day) =>
      _anchor +
      (_monday(day).difference(_monday(ref.read(apptsNowProvider))).inDays / 7)
          .round();

  void _select(DateTime day) {
    MobileHaptics.select();
    ref.read(mobileScheduleDayProvider.notifier).select(day);
    final page = _pageOf(day);
    if (_weeks.hasClients && _weeks.page?.round() != page) {
      _weeks.animateToPage(
        page,
        duration: CruMotion.standard,
        curve: CruMotion.curve,
      );
    }
  }

  int _rowOf(DateTime month, DateTime day) =>
      ApptsBuilder.monthGrid(
        month,
      ).indexWhere((d) => ApptsBuilder.sameDay(d, day)) ~/
      7;

  void _toggleCalendarView() {
    MobileHaptics.tap();
    if (_isMonthExpanded) {
      _collapse();
      return;
    }
    // Open on the month of the week in view, with that week as the row
    // that moves.
    final week = _weekStart(_page);
    final day = ref.read(mobileScheduleDayProvider);
    final inWeek = !day.isBefore(week) && day.difference(week).inDays < 7;
    final pivot = inWeek ? day : week.add(const Duration(days: 3));
    setState(() {
      _isMonthExpanded = true;
      _monthDate = DateTime(pivot.year, pivot.month);
      _anchorRow = _rowOf(_monthDate, week);
    });
    _expand.duration = CruMotion.of(context, CruMotion.standard);
    _expand.forward();
  }

  /// Folds the month back to the selected day's week (or its first week
  /// when the selected day is not on this page).
  void _collapse() {
    final day = ref.read(mobileScheduleDayProvider);
    final grid = ApptsBuilder.monthGrid(_monthDate);
    final row = grid.any((d) => ApptsBuilder.sameDay(d, day))
        ? _rowOf(_monthDate, day)
        : 0;
    final page = _pageOf(grid[row * 7]);
    _weeks.dispose();
    setState(() {
      _isMonthExpanded = false;
      _anchorRow = row;
      _page = page;
      _weeks = PageController(initialPage: page);
    });
    _expand.duration = CruMotion.of(context, CruMotion.standard);
    _expand.reverse();
  }

  Future<void> _book(DateTime day) async {
    final root = mobileRoot(context);
    final patient = await showPatientPickerDialog(
      root,
      title: 'Book a visit for',
    );
    if (patient == null || !root.mounted) return;
    await showScheduleVisitSheet(
      root,
      patient: patient,
      visitRepository: ref.read(visitRepositoryProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final day = ref.watch(mobileScheduleDayProvider);
    final now = ref.watch(apptsNowProvider);
    final isToday = ApptsBuilder.sameDay(day, now);
    final items = ref.watch(apptDayItemsProvider(day));
    final scribe =
        DoctorFeatureGuard.isEnabled(
          widget.enabledModules ?? DoctorFeatureGuard.defaultModules,
          'ai_assistant',
        ) &&
        sidebarTabs(
          dental: ref.watch(dentalFeaturesProvider),
          access: ref.watch(clinicAccessProvider).value,
        ).any((t) => t.tab == DesktopTab.scribe);
    // Today's walk-ins: queue tokens with no booked visit behind them.
    final walkIns = isToday
        ? [
            for (final s
                in ref.watch(dashboardDataProvider).schedule ??
                    const <ScheduleItem>[])
              if (s.visitId == null) s,
          ]
        : const <ScheduleItem>[];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: MobileHeader(
            overline: DateFormat(
              'MMMM y',
            ).format(_isMonthExpanded ? _monthDate : day),
            title: 'Schedule',
            titleTrailing: _ViewDropdown(
              isMonth: _isMonthExpanded,
              onTap: _toggleCalendarView,
            ),
            onTitleTap: _toggleCalendarView,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Scribe left More for this button: it records the same
                // day's visits listed here.
                if (scribe) ...[
                  MobileCircleButton(
                    icon: CruIcons.mic,
                    filled: false,
                    semanticLabel: 'Scribe',
                    onPressed: () => openMobileDestination(
                      context,
                      DesktopTab.scribe,
                      backLabel: 'Schedule',
                    ),
                  ),
                  const SizedBox(width: CruSpace.s8),
                ],
                MobileCircleButton(
                  icon: CruIcons.plus,
                  semanticLabel: 'Book a visit',
                  onPressed: () => _book(day),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: CruSpace.s16)),
        SliverToBoxAdapter(
          child: Column(
            children: [
              _WeekdayInitials(
                today: _isMonthExpanded
                    ? (now.year == _monthDate.year &&
                              now.month == _monthDate.month
                          ? now
                          : null)
                    : (_pageOf(now) == _page ? now : null),
              ),
              const SizedBox(height: CruSpace.s6),
              AnimatedBuilder(
                animation: _t,
                builder: (context, _) {
                  if (_expand.isDismissed && !_isMonthExpanded) {
                    return SizedBox(
                      height: _DayCell.rowHeight,
                      child: PageView.builder(
                        controller: _weeks,
                        onPageChanged: (p) => setState(() => _page = p),
                        itemBuilder: (context, page) => _WeekStrip(
                          start: _weekStart(page),
                          selected: day,
                          today: now,
                          onSelect: _select,
                        ),
                      ),
                    );
                  }
                  final months = _months;
                  if (_expand.isCompleted &&
                      _isMonthExpanded &&
                      months != null) {
                    return _MonthPager(
                      controller: months,
                      month: _monthDate,
                      selected: day,
                      today: now,
                      onSelect: _pickFromMonth,
                      onPageChanged: (p) =>
                          setState(() => _monthDate = _pageMonth(p)),
                      onStep: _stepMonth,
                      onToday: () => _goToMonthPage(_monthPage(now)),
                    );
                  }
                  // Opening or closing: one month, its week row sliding.
                  return _MonthGrid(
                    month: _monthDate,
                    anchorRow: _anchorRow,
                    t: _t.value,
                    selected: day,
                    today: now,
                    onSelect: _pickFromMonth,
                    onMonthChange: (newMonth) {
                      setState(() => _monthDate = newMonth);
                    },
                  );
                },
              ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: CruSpace.s16)),
        ...switch (items) {
          AsyncData(:final value) when value.isEmpty && walkIns.isEmpty => [
            SliverToBoxAdapter(
              child: MobileRowGroup(
                header: _dayHeader(c, day, now, isToday, value, walkIns),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                    child: Column(
                      children: [
                        Text(
                          'Nothing booked. Book a visit or check in a walk-in.',
                          textAlign: TextAlign.center,
                          style: MobileType.subhead.tint(c.label2),
                        ),
                        const SizedBox(height: CruSpace.s16),
                        MobilePrimaryButton(
                          label: 'Book a visit',
                          icon: CruIcons.plus,
                          onPressed: () => _book(day),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          AsyncData(:final value) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MobileMetrics.gutter,
                ),
                child: MobileCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _dayHeader(c, day, now, isToday, value, walkIns),
                      Padding(
                        padding: const EdgeInsets.only(bottom: CruSpace.s8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _timeline(value, walkIns, isToday, now),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          AsyncError(:final error) => [
            SliverToBoxAdapter(
              child: MobileEmpty(
                icon: CruIcons.warning,
                title: 'Could not load the schedule',
                body: '$error',
              ),
            ),
          ],
          _ => [
            const SliverToBoxAdapter(
              child: MobileRowGroup(
                children: [MobileLoading('Loading the day…', height: 160)],
              ),
            ),
          ],
        },
        SliverToBoxAdapter(
          child: SizedBox(height: MobileMetrics.bottom(context)),
        ),
      ],
    );
  }

  /// The top of the day's card: which day, a way back to today, and the
  /// day's counts.
  Widget _dayHeader(
    CruColors c,
    DateTime day,
    DateTime now,
    bool isToday,
    List<ApptItem> items,
    List<ScheduleItem> walkIns,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isToday ? 'Today' : DateFormat('EEEE, d MMMM').format(day),
                style: MobileType.headline.tint(c.label),
              ),
            ),
            if (!isToday)
              CruCapsuleButton(
                label: 'Today',
                height: 32,
                onPressed: () => _select(now),
              ),
          ],
        ),
        if (items.isNotEmpty || walkIns.isNotEmpty) ...[
          const SizedBox(height: CruSpace.s10),
          _Summary(items: items, walkIns: walkIns, isToday: isToday),
        ],
        if (isToday && (items.isNotEmpty || walkIns.isNotEmpty)) ...[
          const SizedBox(height: CruSpace.s8),
          Text(
            'Swipe a visit right to move them along. Hold it for more.',
            style: MobileType.caption.tint(c.label3),
          ),
        ],
      ],
    ),
  );

  /// The day as a timeline: visits and walk-ins in time order, the free
  /// time between them, and (today) where now falls.
  List<Widget> _timeline(
    List<ApptItem> items,
    List<ScheduleItem> walkIns,
    bool isToday,
    DateTime now,
  ) {
    // Walk-ins have no length; a short slot keeps the gaps honest.
    const walkInSlot = Duration(minutes: 15);
    final slots =
        <
            ({
              DateTime start,
              DateTime end,
              ApptItem? appt,
              ScheduleItem? walkIn,
            })
          >[
            for (final i in items)
              (start: i.start, end: i.end, appt: i, walkIn: null),
            for (final w in walkIns)
              (
                start: w.time,
                end: w.time.add(walkInSlot),
                appt: null,
                walkIn: w,
              ),
          ]
          ..sort((a, b) => a.start.compareTo(b.start));

    // Now goes before the first slot that has not started yet.
    final upcoming = slots.indexWhere((s) => s.start.isAfter(now));
    final nowAt = !isToday ? -1 : (upcoming < 0 ? slots.length : upcoming);

    final out = <Widget>[];
    DateTime? busyUntil;
    for (var i = 0; i < slots.length; i++) {
      final s = slots[i];
      if (i == nowAt) out.add(_NowMarker(now: now, first: i == 0));
      final gap = busyUntil == null ? null : s.start.difference(busyUntil);
      final free = gap != null && gap.inMinutes >= 30
          ? '${DashFormat.minutes(gap.inMinutes)} free'
          : null;
      final first = i == 0 && nowAt != 0;
      final last = i == slots.length - 1 && nowAt != slots.length;
      // A hairline only between two visits that sit right next to each
      // other; the free time and the now line already split the rest.
      final divider = i > 0 && free == null && i != nowAt;
      out.add(
        s.appt != null
            ? _ApptRow(
                item: s.appt!,
                today: isToday,
                first: first,
                last: last,
                divider: divider,
                gapLabel: free,
              )
            : _WalkInRow(
                item: s.walkIn!,
                first: first,
                last: last,
                divider: divider,
                gapLabel: free,
              ),
      );
      if (busyUntil == null || s.end.isAfter(busyUntil)) busyUntil = s.end;
    }
    if (nowAt == slots.length && slots.isNotEmpty) {
      out.add(_NowMarker(now: now, first: false, last: true));
    }
    return out;
  }
}

/// The timeline's left edge for one stop: the track line through the
/// middle (the halves above and below drawn on their own, so the line
/// starts at the first stop and ends at the last) and, when [dot] is set,
/// the status dot from Today's schedule, ringed in the card's surface so
/// the line stops short of it.
class _Rail extends StatelessWidget {
  const _Rail({required this.top, required this.bottom, this.dot});

  final bool top;
  final bool bottom;
  final CruDotKind? dot;

  static const double width = CruSpace.s24;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    Widget half(bool on) => Expanded(
      child: on
          ? Center(
              child: SizedBox(
                width: 1.5,
                height: double.infinity,
                child: ColoredBox(color: c.separator),
              ),
            )
          : const SizedBox.shrink(),
    );
    return SizedBox(
      width: width,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(children: [half(top), half(bottom)]),
          if (dot != null)
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.surface,
              ),
              child: Padding(
                padding: const EdgeInsets.all(CruSpace.s4),
                child: CruStatusDot(dot!, size: CruSpace.s12),
              ),
            ),
        ],
      ),
    );
  }
}

/// Left padding of every timeline row, before the rail.
const double _rowLead = CruSpace.s8;

/// Space between the time and the name.
const double _timeGap = CruSpace.s12;

/// Where a row's text starts; the hairlines between visits start here.
const double _textInset =
    _rowLead + _Rail.width + CruSize.timeColumn + _timeGap;

/// One stop on the timeline, as a flat row like the rest of the phone's
/// cards: an optional "1 h free" line above, then the dot, the time, the
/// name and reason, the status on the right and the more button. The
/// visit with the doctor is washed in the accent, as on the dashboard.
class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.time,
    required this.dot,
    required this.title,
    required this.detail,
    required this.first,
    required this.last,
    required this.divider,
    required this.onTap,
    required this.onMore,
    this.status,
    this.struck = false,
    this.gapLabel,
    this.swipe,
  });

  final DateTime time;
  final CruDotKind dot;
  final String title;
  final String? detail;

  /// The pill (or quiet "Booked") on the right.
  final Widget? status;
  final bool struck;
  final bool first;
  final bool last;

  /// A hairline above this row, from the text column to the edge.
  final bool divider;
  final VoidCallback onTap;
  final VoidCallback onMore;
  final String? gapLabel;
  final MobileSwipeAction? swipe;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final (hm, meridiem) = DashFormat.timeParts(time);
    final now = dot == CruDotKind.now;
    final quiet = dot == CruDotKind.done || dot == CruDotKind.inactive;

    final row = Material(
      color: now ? c.accentWash : c.surface,
      child: InkWell(
        onTap: onTap,
        onLongPress: () {
          MobileHaptics.commit();
          onMore();
        },
        splashFactory: NoSplash.splashFactory,
        highlightColor: c.hoverFill,
        child: Stack(
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(width: _rowLead),
                  _Rail(top: !first, bottom: !last, dot: dot),
                  SizedBox(
                    width: CruSize.timeColumn,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: hm,
                                style: MobileType.callout.tabular.tint(
                                  now
                                      ? c.accentText
                                      : (quiet ? c.label2 : c.label),
                                ),
                              ),
                              TextSpan(
                                text: ' $meridiem',
                                style: MobileType.micro.tint(c.label3),
                              ),
                            ],
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: _timeGap),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: CruSpace.s12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MobileType.row.copyWith(
                              color: struck
                                  ? c.label3
                                  : (quiet ? c.label2 : c.label),
                              decoration: struck
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: c.label3,
                            ),
                          ),
                          if (detail != null) ...[
                            const SizedBox(height: CruSpace.s2),
                            Text(
                              detail!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: MobileType.caption.tabular.tint(c.label2),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (status != null) ...[
                    const SizedBox(width: CruSpace.s8),
                    Center(child: status),
                  ],
                  Center(
                    child: CruIconButton(
                      icon: CruIcons.more,
                      semanticLabel: 'More for $title',
                      size: CruSize.squareButton,
                      iconSize: 18,
                      onPressed: () {
                        MobileHaptics.tap();
                        onMore();
                      },
                    ),
                  ),
                  const SizedBox(width: CruSpace.s4),
                ],
              ),
            ),
            if (divider)
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: CruSeparator(indent: _textInset),
              ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (gapLabel != null)
          SizedBox(
            height: CruSpace.s32,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(width: _rowLead),
                const _Rail(top: true, bottom: true),
                const SizedBox(width: CruSize.timeColumn + _timeGap),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      CruIcon(
                        CruIcons.clock,
                        size: 12,
                        strokeWidth: 2,
                        color: c.label3,
                      ),
                      const SizedBox(width: CruSpace.s4),
                      Text(
                        gapLabel!,
                        style: MobileType.micro.tabular.tint(c.label3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        MobileSwipeRow(action: swipe, child: row),
      ],
    );
  }
}

/// Where now falls between today's visits: the "now" dot and the time,
/// with a line across like the Day view's now line.
class _NowMarker extends StatelessWidget {
  const _NowMarker({required this.now, required this.first, this.last = false});

  final DateTime now;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return SizedBox(
      height: CruSpace.s32,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: _rowLead),
          _Rail(top: !first, bottom: !last, dot: CruDotKind.now),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Now · ${DashFormat.time(now)}',
              style: MobileType.micro.w600.tabular.tint(c.accentText),
            ),
          ),
          const SizedBox(width: CruSpace.s8),
          Expanded(
            child: Center(
              child: SizedBox(
                height: 1,
                width: double.infinity,
                child: ColoredBox(color: c.accent),
              ),
            ),
          ),
          const SizedBox(width: CruSpace.s16),
        ],
      ),
    );
  }
}

/// Weekday initials above the week strip and the month grid. They stay put
/// while the days move beneath them; today's column is tinted when today is
/// on screen.
class _WeekdayInitials extends StatelessWidget {
  const _WeekdayInitials({required this.today});

  final DateTime? today;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final eve = mobileOnDark(context);
    final ink = mobileInk(context);
    final accent = eve ? Colors.white : MobileBlue.neon;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s10),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Text(
                _letters[i],
                textAlign: TextAlign.center,
                style: MobileType.micro.tint(
                  today?.weekday == i + 1
                      ? accent
                      : ink.withValues(alpha: 0.55),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One day in the week strip or the month grid: a number in a circle and a
/// dot when the day is booked. [fade] dims days outside the month.
class _DayCell extends ConsumerWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.today,
    required this.onSelect,
    this.fade = 0,
  });

  static const rowHeight = 52.0;

  final DateTime day;
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onSelect;
  final double fade;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Day: dark ink on the light canvas, the selected day a Neon Blue
    // circle. Evening: white on navy, the selected day a white circle.
    final eve = mobileOnDark(context);
    final ink = mobileInk(context);
    final selFill = eve ? Colors.white : MobileBlue.neon;
    final selText = eve ? MobileBlue.neon : Colors.white;
    final accent = eve ? Colors.white : MobileBlue.neon;
    final isSel = ApptsBuilder.sameDay(day, selected);
    final isToday = ApptsBuilder.sameDay(day, today);
    final booked =
        ref.watch(apptDayItemsProvider(day)).value?.isNotEmpty ?? false;
    final dayInk = ink.withValues(alpha: 1 - 0.72 * fade);
    return CruPressable(
      onTap: () => onSelect(day),
      semanticLabel: DateFormat('EEEE d MMMM').format(day),
      scaleOnPress: false,
      builder: (context, _) => SizedBox(
        height: rowHeight,
        child: Column(
          children: [
            AnimatedContainer(
              duration: CruMotion.of(context, CruMotion.fast),
              curve: CruMotion.curve,
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSel
                    ? selFill
                    : (isToday
                          ? accent.withValues(alpha: eve ? 0.2 : 0.1)
                          : null),
              ),
              child: Text(
                '${day.day}',
                style: MobileType.row.tabular.tint(
                  isSel ? selText : (isToday ? accent : dayInk),
                ),
              ),
            ),
            const SizedBox(height: CruSpace.s4),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: booked
                    ? accent.withValues(alpha: 0.7 * (1 - fade))
                    : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Seven days; swipe it for other weeks. A dot marks booked days.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.start,
    required this.selected,
    required this.today,
    required this.onSelect,
  });

  final DateTime start;
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s10),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: _DayCell(
                day: start.add(Duration(days: i)),
                selected: selected,
                today: today,
                onSelect: onSelect,
              ),
            ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.items,
    required this.walkIns,
    required this.isToday,
  });

  final List<ApptItem> items;
  final List<ScheduleItem> walkIns;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    int n(ApptStatus s) => items.where((i) => i.status == s).length;
    int w(ScheduleStatus s) => walkIns.where((i) => i.status == s).length;
    final waiting = n(ApptStatus.waiting) + w(ScheduleStatus.waiting);
    final done = n(ApptStatus.done) + w(ScheduleStatus.done);
    final pills = <Widget>[
      MobilePill(
        DashFormat.plural(items.length + walkIns.length, 'visit'),
        tone: MobileTone.blue,
      ),
      if (isToday && waiting > 0)
        MobilePill('$waiting waiting', tone: MobileTone.amber),
      if (done > 0) MobilePill('$done done', tone: MobileTone.green),
    ];
    return Wrap(spacing: CruSpace.s6, runSpacing: CruSpace.s6, children: pills);
  }
}

/// A walk-in on today's queue (a token with no booked visit). Swipe
/// right to call them in when they are next, or to finish with them.
class _WalkInRow extends ConsumerWidget {
  const _WalkInRow({
    required this.item,
    required this.first,
    required this.last,
    required this.divider,
    this.gapLabel,
  });

  final ScheduleItem item;
  final bool first;
  final bool last;
  final bool divider;
  final String? gapLabel;

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
    String done,
  ) async {
    try {
      await action();
      if (context.mounted) mobileSay(context, done);
    } catch (e) {
      if (context.mounted) mobileSay(context, '$e');
    }
  }

  MobileSwipeAction? _swipe(BuildContext context, WidgetRef ref) {
    final id = item.queueEntryId;
    if (id == null) return null;
    final first = item.firstName;
    switch (item.status) {
      case ScheduleStatus.waiting:
        final up = ref.read(dashboardDataProvider).upNext;
        if (up == null ||
            up.entryId != id ||
            !up.isNextInCallOrder ||
            up.servingName != null) {
          return null;
        }
        return MobileSwipeAction(
          label: 'Call in',
          icon: CruIcons.play,
          tone: MobileTone.blue,
          onCommit: () => _run(context, () async {
            final repo = ref.read(queueRepositoryProvider);
            final called = await repo.callNext();
            await repo.startConsultation(called.id);
          }, 'Started with $first.'),
        );
      case ScheduleStatus.inConsultation || ScheduleStatus.called:
        return MobileSwipeAction(
          label: 'Done',
          icon: CruIcons.check,
          tone: MobileTone.green,
          onCommit: () => _run(
            context,
            () => ref.read(queueRepositoryProvider).complete(id),
            '$first is done.',
          ),
        );
      default:
        return null;
    }
  }

  void _sheet(BuildContext context, WidgetRef ref) {
    final p = item.patient;
    final id = item.queueEntryId;
    showMobileActionSheet(
      context,
      title: item.name,
      subtitle: [
        'Walk-in',
        if (item.tokenNumber != null) 'Token ${item.tokenNumber}',
        ?item.reason,
      ].join(' · '),
      leading: MobileAvatar(name: item.name, size: 34),
      actions: [
        if (p != null)
          MobileSheetAction(
            label: 'Open patient',
            icon: CruIcons.user,
            tone: MobileTone.sky,
            onTap: () => openMobilePatient(context, p),
          ),
        if (p != null && p.phone.trim().isNotEmpty) ...[
          MobileSheetAction(
            label: 'Call',
            icon: CruIcons.phone,
            tone: MobileTone.green,
            onTap: () => PatientActions.call(context, p),
          ),
          MobileSheetAction(
            label: 'WhatsApp',
            icon: CruIcons.whatsapp,
            tone: MobileTone.teal,
            onTap: () => PatientActions.whatsApp(context, p),
          ),
        ],
        if (id != null && item.status.isOpen)
          MobileSheetAction(
            label: 'Cancel token',
            icon: CruIcons.close,
            destructive: true,
            onTap: () => _run(
              context,
              () => ref.read(queueRepositoryProvider).cancel(id),
              'Token cancelled for ${item.firstName}.',
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (dot, status) = switch (item.status) {
      ScheduleStatus.inConsultation => (CruDotKind.now, _Status.withYou),
      ScheduleStatus.called => (CruDotKind.now, _Status.called),
      ScheduleStatus.waiting => (CruDotKind.waiting, _Status.waiting),
      ScheduleStatus.booked => (CruDotKind.booked, _Status.booked),
      ScheduleStatus.done => (CruDotKind.done, _Status.done),
      ScheduleStatus.missed => (CruDotKind.inactive, _Status.missed),
      ScheduleStatus.skipped => (CruDotKind.inactive, _Status.notHere),
    };
    return _TimelineTile(
      time: item.time,
      dot: dot,
      title: item.name,
      status: _StatusPill(status, waitMinutes: item.waitMinutes),
      struck: item.status == ScheduleStatus.missed,
      detail: [
        'Walk-in',
        if (item.tokenNumber != null) 'Token ${item.tokenNumber}',
        ?item.reason,
      ].join(' · '),
      first: first,
      last: last,
      divider: divider,
      gapLabel: gapLabel,
      swipe: _swipe(context, ref),
      onTap: item.patient == null
          ? () => _sheet(context, ref)
          : () => openMobilePatient(context, item.patient!),
      onMore: () => _sheet(context, ref),
    );
  }
}

enum _Status { withYou, called, waiting, booked, done, missed, notHere }

/// A row's status on the right: the phone's pills (blue only while with
/// the doctor, amber waiting, green done, grey missed) and a quiet
/// "Booked" when nothing has happened yet.
class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status, {this.waitMinutes});

  final _Status status;
  final int? waitMinutes;

  @override
  Widget build(BuildContext context) => switch (status) {
    _Status.withYou => const MobilePill('With you', tone: MobileTone.blue),
    _Status.called => const MobilePill('Called', tone: MobileTone.blue),
    _Status.waiting => MobilePill(
      waitMinutes == null ? 'Waiting' : DashFormat.minutes(waitMinutes!),
      tone: MobileTone.amber,
      icon: CruIcons.clock,
    ),
    _Status.done => const MobilePill(
      'Done',
      tone: MobileTone.green,
      icon: CruIcons.check,
    ),
    _Status.missed => const MobilePill('Missed', tone: MobileTone.slate),
    _Status.notHere => const MobilePill('Not here', tone: MobileTone.slate),
    _Status.booked => Text(
      'Booked',
      style: MobileType.caption.tint(context.cru.label3),
    ),
  };
}

/// One visit. Today's rows can be swiped right to take the next step.
class _ApptRow extends ConsumerWidget {
  const _ApptRow({
    required this.item,
    required this.today,
    required this.first,
    required this.last,
    required this.divider,
    this.gapLabel,
  });

  final ApptItem item;
  final bool today;
  final bool first;
  final bool last;
  final bool divider;
  final String? gapLabel;

  QueueEntry? _entry(WidgetRef ref) {
    for (final e in ref.read(todaysQueueProvider).value ?? const []) {
      if (e.linkedVisitId == item.id) return e;
    }
    return null;
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
    String done,
  ) async {
    try {
      await action();
      if (context.mounted) mobileSay(context, done);
    } catch (e) {
      if (context.mounted) mobileSay(context, '$e');
    }
  }

  /// The next step for this row, if a swipe can take it.
  MobileSwipeAction? _swipe(BuildContext context, WidgetRef ref) {
    if (!today) return null;
    final first = item.firstName;
    switch (item.status) {
      case ApptStatus.booked when item.tokenNumber == null:
        return MobileSwipeAction(
          label: 'Check in',
          icon: CruIcons.userCheck,
          tone: MobileTone.amber,
          onCommit: () => _run(
            context,
            () => ref.read(queueRepositoryProvider).checkInVisit(item.visit),
            '$first is checked in.',
          ),
        );
      case ApptStatus.waiting:
        final up = ref.read(dashboardDataProvider).upNext;
        final entry = _entry(ref);
        if (up == null ||
            entry == null ||
            up.entryId != entry.id ||
            !up.isNextInCallOrder ||
            up.servingName != null) {
          return null;
        }
        return MobileSwipeAction(
          label: 'Call in',
          icon: CruIcons.play,
          tone: MobileTone.blue,
          onCommit: () => _run(context, () async {
            final called = await ref.read(queueRepositoryProvider).callNext();
            await ref
                .read(queueRepositoryProvider)
                .startConsultation(called.id);
          }, 'Started with $first.'),
        );
      case ApptStatus.inConsultation:
        final entry = _entry(ref);
        if (entry == null) return null;
        return MobileSwipeAction(
          label: 'Done',
          icon: CruIcons.check,
          tone: MobileTone.green,
          onCommit: () => _run(
            context,
            () => ref.read(queueRepositoryProvider).complete(entry.id),
            '$first is done.',
          ),
        );
      default:
        return null;
    }
  }

  void _sheet(BuildContext context, WidgetRef ref) {
    final p = item.patient;
    showMobileActionSheet(
      context,
      title: item.name,
      subtitle:
          '${DashFormat.time(item.start)} · ${DashFormat.minutes(item.durationMinutes)}'
          '${item.detailLine == null ? '' : ' · ${item.detailLine}'}',
      leading: MobileAvatar(name: item.name, size: 34),
      actions: [
        MobileSheetAction(
          label: 'Visit details',
          icon: CruIcons.fileText,
          tone: MobileTone.blue,
          onTap: () => ApptActions.openVisit(context, item),
        ),
        if (p != null)
          MobileSheetAction(
            label: 'Open patient',
            icon: CruIcons.user,
            tone: MobileTone.sky,
            onTap: () => openMobilePatient(context, p),
          ),
        if (p != null && p.phone.trim().isNotEmpty) ...[
          MobileSheetAction(
            label: 'Call',
            icon: CruIcons.phone,
            tone: MobileTone.green,
            onTap: () => PatientActions.call(context, p),
          ),
          MobileSheetAction(
            label: 'WhatsApp',
            icon: CruIcons.whatsapp,
            tone: MobileTone.teal,
            onTap: () => PatientActions.whatsApp(context, p),
          ),
        ],
        if (ApptActions.canReschedule(item))
          MobileSheetAction(
            label: 'Reschedule',
            icon: CruIcons.clock,
            tone: MobileTone.amber,
            onTap: () => ApptActions.reschedule(context, ref, item),
          ),
        if (ApptActions.canCancel(item))
          MobileSheetAction(
            label: 'Cancel appointment',
            icon: CruIcons.close,
            destructive: true,
            onTap: () => ApptActions.cancel(context, ref, item),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (dot, status) = switch (item.status) {
      ApptStatus.inConsultation => (CruDotKind.now, _Status.withYou),
      ApptStatus.waiting => (CruDotKind.waiting, _Status.waiting),
      ApptStatus.done => (CruDotKind.done, _Status.done),
      ApptStatus.missed => (CruDotKind.inactive, _Status.missed),
      ApptStatus.booked => (CruDotKind.booked, _Status.booked),
    };
    return _TimelineTile(
      time: item.start,
      dot: dot,
      title: item.name,
      status: _StatusPill(status, waitMinutes: item.waitMinutes),
      struck: item.status == ApptStatus.missed,
      detail:
          [
            if (item.tokenNumber != null) 'Token ${item.tokenNumber}',
            if (item.isHomeVisit) 'Home visit',
            if (item.isNewPatient) 'New patient',
            ?item.detailLine,
          ].join(' · ').nullIfEmpty ??
          DashFormat.minutes(item.durationMinutes),
      first: first,
      last: last,
      divider: divider,
      gapLabel: gapLabel,
      swipe: _swipe(context, ref),
      onTap: () => ApptActions.openVisit(context, item),
      onMore: () => _sheet(context, ref),
    );
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

/// The dropdown pill beside "Schedule": toggles between Week and Month view.
class _ViewDropdown extends StatelessWidget {
  const _ViewDropdown({required this.isMonth, required this.onTap});

  final bool isMonth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final eve = mobileOnDark(context);
    final accent = eve ? Colors.white : MobileBlue.neon;
    final bg = accent.withValues(alpha: 0.12);

    return CruPressable(
      onTap: onTap,
      semanticLabel: isMonth
          ? 'Switch to weekly view'
          : 'Switch to monthly view',
      scaleOnPress: true,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: hovered ? bg.withValues(alpha: 0.22) : bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.28), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isMonth ? 'Month' : 'Week',
              style: MobileType.caption.w600.tint(accent),
            ),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: isMonth ? 0.5 : 0.0,
              duration: CruMotion.standard,
              curve: CruMotion.curve,
              child: CruIcon(CruIcons.chevronDown, size: 13, color: accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// Month pages count from January 1900, so a page is always the same
/// month whatever today is.
const _monthEpoch = 1900;

int _monthPage(DateTime month) =>
    (month.year - _monthEpoch) * 12 + month.month - 1;

DateTime _pageMonth(int page) =>
    DateTime(_monthEpoch + page ~/ 12, page % 12 + 1);

/// Today, the previous and next month: under the open month.
class _MonthStepper extends StatelessWidget {
  const _MonthStepper({
    required this.month,
    required this.today,
    required this.onStep,
    required this.onToday,
  });

  final DateTime month;
  final DateTime today;
  final ValueChanged<int> onStep;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final isCurrentMonth =
        month.year == today.year && month.month == today.month;
    return Padding(
      padding: const EdgeInsets.only(top: CruSpace.s4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!isCurrentMonth) ...[
            CruCapsuleButton(
              label: 'Today',
              height: 28,
              onPressed: () {
                MobileHaptics.select();
                onToday();
              },
            ),
            const SizedBox(width: CruSpace.s6),
          ],
          CruIconButton(
            icon: CruIcons.chevronLeft,
            semanticLabel: 'Previous month',
            size: 32,
            iconSize: 16,
            onPressed: () {
              MobileHaptics.select();
              onStep(-1);
            },
          ),
          const SizedBox(width: CruSpace.s4),
          CruIconButton(
            icon: CruIcons.chevronRight,
            semanticLabel: 'Next month',
            size: 32,
            iconSize: 16,
            onPressed: () {
              MobileHaptics.select();
              onStep(1);
            },
          ),
        ],
      ),
    );
  }
}

/// The month grid. [t] runs 0 → 1 as it opens: row [anchorRow] (the week
/// strip) slides from the top down into its slot while the other weeks
/// fade in around it and the grid grows to full height. At 1 it looks
/// exactly like a [_MonthPager] page, which takes over once open.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.anchorRow,
    required this.t,
    required this.selected,
    required this.today,
    required this.onSelect,
    required this.onMonthChange,
  });

  final DateTime month;
  final int anchorRow;
  final double t;
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<DateTime> onMonthChange;

  @override
  Widget build(BuildContext context) {
    const rowH = _DayCell.rowHeight;
    final days = ApptsBuilder.monthGrid(month);
    final weeks = <List<DateTime>>[
      for (var i = 0; i < days.length; i += 7) days.sublist(i, i + 7),
    ];
    final height = rowH + (weeks.length - 1) * rowH * t;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRect(
            child: SizedBox(
              height: height,
              child: Stack(
                children: [
                  for (var i = 0; i < weeks.length; i++)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: (i - anchorRow * (1 - t)) * rowH,
                      height: rowH,
                      child: Opacity(
                        opacity: i == anchorRow ? 1 : t,
                        child: Row(
                          children: [
                            for (final d in weeks[i])
                              Expanded(
                                child: _DayCell(
                                  day: d,
                                  selected: selected,
                                  today: today,
                                  onSelect: onSelect,
                                  fade: d.month == month.month ? 0 : t,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Month stepper; the month's name is in the header above.
          ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: t,
              child: Opacity(
                opacity: t,
                child: _MonthStepper(
                  month: month,
                  today: today,
                  onStep: (delta) =>
                      onMonthChange(DateTime(month.year, month.month + delta)),
                  onToday: () =>
                      onMonthChange(DateTime(today.year, today.month)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The open month, sliding with the finger like the week strip. Its
/// height follows the slide between months of four, five and six weeks.
class _MonthPager extends StatelessWidget {
  const _MonthPager({
    required this.controller,
    required this.month,
    required this.selected,
    required this.today,
    required this.onSelect,
    required this.onPageChanged,
    required this.onStep,
    required this.onToday,
  });

  final PageController controller;

  /// The month the pages settled on.
  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onStep;
  final VoidCallback onToday;

  static double _heightOf(int page) =>
      ApptsBuilder.monthGrid(_pageMonth(page)).length / 7 * _DayCell.rowHeight;

  double get _height {
    final settled = _monthPage(month).toDouble();
    final page = controller.hasClients && controller.position.haveDimensions
        ? (controller.page ?? settled)
        : settled;
    final a = page.floor();
    final ha = _heightOf(a);
    return ha + (_heightOf(a + 1) - ha) * (page - a);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: controller,
          builder: (context, child) => SizedBox(height: _height, child: child),
          child: PageView.builder(
            controller: controller,
            onPageChanged: onPageChanged,
            itemBuilder: (context, page) => OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: double.infinity,
              child: _MonthWeeks(
                month: _pageMonth(page),
                selected: selected,
                today: today,
                onSelect: onSelect,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s10),
          child: _MonthStepper(
            month: month,
            today: today,
            onStep: onStep,
            onToday: onToday,
          ),
        ),
      ],
    );
  }
}

/// One whole month on a page: every week, days outside the month dimmed.
class _MonthWeeks extends StatelessWidget {
  const _MonthWeeks({
    required this.month,
    required this.selected,
    required this.today,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final days = ApptsBuilder.monthGrid(month);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < days.length; i += 7)
            Row(
              children: [
                for (final d in days.sublist(i, i + 7))
                  Expanded(
                    child: d.month != month.month
                        ? const SizedBox.shrink()
                        : _DayCell(
                            day: d,
                            selected: selected,
                            today: today,
                            onSelect: onSelect,
                          ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
