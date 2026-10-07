import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/mobile/mobile_more.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_actions.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
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
  const MobileScheduleScreen({super.key});

  @override
  ConsumerState<MobileScheduleScreen> createState() =>
      _MobileScheduleScreenState();
}

class _MobileScheduleScreenState extends ConsumerState<MobileScheduleScreen> {
  /// Week pages around the current week; page [_anchor] is this week.
  static const _anchor = 520;
  late final PageController _weeks = PageController(initialPage: _anchor);
  bool _isMonthExpanded = false;
  late DateTime _monthDate;

  @override
  void initState() {
    super.initState();
    _monthDate = DateTime.now();
  }

  @override
  void dispose() {
    _weeks.dispose();
    super.dispose();
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

  void _toggleCalendarView() {
    MobileHaptics.tap();
    setState(() {
      _isMonthExpanded = !_isMonthExpanded;
      if (_isMonthExpanded) {
        final currentDay = ref.read(mobileScheduleDayProvider);
        _monthDate = DateTime(currentDay.year, currentDay.month);
      }
    });
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
            overline: DateFormat('MMMM y').format(_isMonthExpanded ? _monthDate : day),
            title: 'Schedule',
            titleTrailing: _ViewDropdown(
              isMonth: _isMonthExpanded,
              onTap: _toggleCalendarView,
            ),
            onTitleTap: _toggleCalendarView,
            trailing: MobileCircleButton(
              icon: CruIcons.plus,
              semanticLabel: 'Book a visit',
              onPressed: () => _book(day),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: CruSpace.s16)),
        SliverToBoxAdapter(
          child: AnimatedCrossFade(
            duration: CruMotion.standard,
            firstCurve: CruMotion.curve,
            secondCurve: CruMotion.curve,
            sizeCurve: CruMotion.curve,
            crossFadeState: _isMonthExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: SizedBox(
              height: 74,
              child: PageView.builder(
                controller: _weeks,
                itemBuilder: (context, page) => _WeekStrip(
                  start: _weekStart(page),
                  selected: day,
                  today: now,
                  onSelect: _select,
                ),
              ),
            ),
            secondChild: _MonthGrid(
              month: _monthDate,
              selected: day,
              today: now,
              onSelect: (picked) {
                _select(picked);
                setState(() {
                  _isMonthExpanded = false;
                  _monthDate = DateTime(picked.year, picked.month);
                });
              },
              onMonthChange: (newMonth) {
                setState(() => _monthDate = newMonth);
              },
            ),
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
              child: MobileRowGroup(
                indent: 76,
                header: _dayHeader(c, day, now, isToday, value, walkIns),
                children: [
                  // Booked visits and walk-ins, in time order.
                  for (final (_, row) in [
                    for (final item in value)
                      (
                        item.start,
                        _ApptRow(item: item, today: isToday) as Widget,
                      ),
                    for (final w in walkIns) (w.time, _WalkInRow(item: w)),
                  ]..sort((a, b) => a.$1.compareTo(b.$1)))
                    row,
                ],
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
            'Swipe a row right to move them along. Hold it for more.',
            style: MobileType.caption.tint(c.label3),
          ),
        ],
      ],
    ),
  );
}

/// Seven days; swipe it for other weeks. A dot marks booked days.
class _WeekStrip extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    // Day: dark ink on the light canvas, the selected day a Neon Blue
    // circle. Evening: white on navy, the selected day a white circle.
    final eve = mobileOnDark(context);
    final ink = mobileInk(context);
    final selFill = eve ? Colors.white : MobileBlue.neon;
    final selText = eve ? MobileBlue.neon : Colors.white;
    final accent = eve ? Colors.white : MobileBlue.neon;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s10),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Builder(
                builder: (context) {
                  final d = start.add(Duration(days: i));
                  final isSel = ApptsBuilder.sameDay(d, selected);
                  final isToday = ApptsBuilder.sameDay(d, today);
                  final booked =
                      ref.watch(apptDayItemsProvider(d)).value?.isNotEmpty ??
                      false;
                  return CruPressable(
                    onTap: () => onSelect(d),
                    semanticLabel: DateFormat('EEEE d MMMM').format(d),
                    scaleOnPress: false,
                    builder: (context, _) => Column(
                      children: [
                        Text(
                          DateFormat('E').format(d).substring(0, 1),
                          style: MobileType.micro.tint(
                            isToday ? accent : ink.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: CruSpace.s6),
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
                                      ? accent.withValues(
                                          alpha: eve ? 0.2 : 0.1,
                                        )
                                      : null),
                          ),
                          child: Text(
                            '${d.day}',
                            style: MobileType.row.tabular.tint(
                              isSel ? selText : (isToday ? accent : ink),
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
                                ? accent.withValues(alpha: 0.7)
                                : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  );
                },
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
  const _WalkInRow({required this.item});

  final ScheduleItem item;

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
    final c = context.cru;
    final (time, meridiem) = DashFormat.timeParts(item.time);
    final done = item.status == ScheduleStatus.done;
    final pill = switch (item.status) {
      ScheduleStatus.inConsultation => const MobilePill(
        'With you',
        tone: MobileTone.blue,
      ),
      ScheduleStatus.called => const MobilePill(
        'Called',
        tone: MobileTone.blue,
      ),
      ScheduleStatus.waiting => MobilePill(
        item.waitMinutes == null
            ? 'Waiting'
            : DashFormat.minutes(item.waitMinutes!),
        tone: MobileTone.amber,
        icon: CruIcons.clock,
      ),
      ScheduleStatus.done => const MobilePill(
        'Done',
        tone: MobileTone.green,
        icon: CruIcons.check,
      ),
      ScheduleStatus.skipped => const MobilePill(
        'Not here',
        tone: MobileTone.slate,
      ),
      _ => null,
    };
    return MobileSwipeRow(
      action: _swipe(context, ref),
      child: MobileRow(
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
        leading: SizedBox(
          width: 48,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                time,
                style: MobileType.callout.tabular.tint(
                  done ? c.label3 : c.label,
                ),
              ),
              Text(meridiem, style: MobileType.micro.tint(c.label3)),
            ],
          ),
        ),
        title: item.name,
        titleStyle: MobileType.row.tint(done ? c.label2 : c.label),
        subtitle: [
          'Walk-in',
          if (item.tokenNumber != null) 'Token ${item.tokenNumber}',
          ?item.reason,
        ].join(' · '),
        trailing: pill,
        onTap: item.patient == null
            ? null
            : () => openMobilePatient(context, item.patient!),
        onLongPress: () => _sheet(context, ref),
      ),
    );
  }
}

/// One visit. Today's rows can be swiped right to take the next step.
class _ApptRow extends ConsumerWidget {
  const _ApptRow({required this.item, required this.today});

  final ApptItem item;
  final bool today;

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
    final c = context.cru;
    final (time, meridiem) = DashFormat.timeParts(item.start);
    final done = item.status == ApptStatus.done;
    final missed = item.status == ApptStatus.missed;
    final pill = switch (item.status) {
      ApptStatus.inConsultation => const MobilePill(
        'With you',
        tone: MobileTone.blue,
      ),
      ApptStatus.waiting => MobilePill(
        item.waitMinutes == null
            ? 'Waiting'
            : DashFormat.minutes(item.waitMinutes!),
        tone: MobileTone.amber,
        icon: CruIcons.clock,
      ),
      ApptStatus.done => const MobilePill(
        'Done',
        tone: MobileTone.green,
        icon: CruIcons.check,
      ),
      ApptStatus.missed => const MobilePill('Missed', tone: MobileTone.slate),
      ApptStatus.booked when item.isNewPatient => const MobilePill(
        'New',
        tone: MobileTone.sky,
      ),
      _ => null,
    };
    return MobileSwipeRow(
      action: _swipe(context, ref),
      child: MobileRow(
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
        leading: SizedBox(
          width: 48,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                time,
                style: MobileType.callout.tabular.tint(
                  done || missed ? c.label3 : c.label,
                ),
              ),
              Text(meridiem, style: MobileType.micro.tint(c.label3)),
            ],
          ),
        ),
        title: item.name,
        titleStyle: MobileType.row.copyWith(
          color: done || missed ? c.label2 : c.label,
          decoration: missed ? TextDecoration.lineThrough : null,
          decorationColor: c.label3,
        ),
        subtitle: [
          if (item.tokenNumber != null) 'Token ${item.tokenNumber}',
          if (item.isHomeVisit) 'Home visit',
          ?item.detailLine,
        ].join(' · ').ifEmpty(DashFormat.minutes(item.durationMinutes)),
        trailing: pill,
        onTap: () => ApptActions.openVisit(context, item),
        onLongPress: () => _sheet(context, ref),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// The dropdown pill beside "Schedule": toggles between Week and Month view.
class _ViewDropdown extends StatelessWidget {
  const _ViewDropdown({
    required this.isMonth,
    required this.onTap,
  });

  final bool isMonth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final eve = mobileOnDark(context);
    final accent = eve ? Colors.white : MobileBlue.neon;
    final bg = accent.withValues(alpha: 0.12);

    return CruPressable(
      onTap: onTap,
      semanticLabel: isMonth ? 'Switch to weekly view' : 'Switch to monthly view',
      scaleOnPress: true,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: hovered ? bg.withValues(alpha: 0.22) : bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accent.withValues(alpha: 0.28),
            width: 1,
          ),
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
              child: CruIcon(
                CruIcons.chevronDown,
                size: 13,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Expanded month grid with appointment dots and month stepper.
class _MonthGrid extends ConsumerWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.today,
    required this.onSelect,
    required this.onMonthChange,
  });

  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<DateTime> onMonthChange;

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eve = mobileOnDark(context);
    final ink = mobileInk(context);
    final selFill = eve ? Colors.white : MobileBlue.neon;
    final selText = eve ? MobileBlue.neon : Colors.white;
    final accent = eve ? Colors.white : MobileBlue.neon;
    final days = ApptsBuilder.monthGrid(month);
    final isCurrentMonth = month.year == today.year && month.month == today.month;
    final weeks = <List<DateTime>>[
      for (var i = 0; i < days.length; i += 7) days.sublist(i, i + 7),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v.abs() < 250) return;
        MobileHaptics.select();
        if (v < 0) {
          onMonthChange(DateTime(month.year, month.month + 1));
        } else {
          onMonthChange(DateTime(month.year, month.month - 1));
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Month navigation bar
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat('MMMM yyyy').format(month),
                      style: MobileType.headline.tint(ink),
                    ),
                  ),
                  if (!isCurrentMonth) ...[
                    CruCapsuleButton(
                      label: 'Today',
                      height: 28,
                      onPressed: () {
                        MobileHaptics.select();
                        onMonthChange(DateTime(today.year, today.month));
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
                      onMonthChange(DateTime(month.year, month.month - 1));
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
                      onMonthChange(DateTime(month.year, month.month + 1));
                    },
                  ),
                ],
              ),
            ),
            // Weekday initials
            Row(
              children: [
                for (final d in _weekdays)
                  Expanded(
                    child: Text(
                      d,
                      textAlign: TextAlign.center,
                      style: MobileType.micro.tint(ink.withValues(alpha: 0.55)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: CruSpace.s6),
            // Month week rows
            for (final week in weeks)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    for (final d in week)
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final inMonth = d.month == month.month;
                            final isSel = ApptsBuilder.sameDay(d, selected);
                            final isToday = ApptsBuilder.sameDay(d, today);
                            final booked = ref
                                    .watch(apptDayItemsProvider(d))
                                    .value
                                    ?.isNotEmpty ??
                                false;
                            final dayInk = inMonth
                                ? ink
                                : ink.withValues(alpha: 0.28);

                            return CruPressable(
                              onTap: () => onSelect(d),
                              semanticLabel: DateFormat('EEEE d MMMM').format(d),
                              scaleOnPress: false,
                              builder: (context, _) => Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedContainer(
                                    duration: CruMotion.of(
                                      context,
                                      CruMotion.fast,
                                    ),
                                    curve: CruMotion.curve,
                                    width: 36,
                                    height: 36,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isSel
                                          ? selFill
                                          : (isToday
                                              ? accent.withValues(
                                                  alpha: eve ? 0.2 : 0.1,
                                                )
                                              : null),
                                    ),
                                    child: Text(
                                      '${d.day}',
                                      style: MobileType.row.tabular.tint(
                                        isSel
                                            ? selText
                                            : (isToday ? accent : dayInk),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Container(
                                    width: 4,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: booked && inMonth
                                          ? accent.withValues(alpha: 0.7)
                                          : Colors.transparent,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
