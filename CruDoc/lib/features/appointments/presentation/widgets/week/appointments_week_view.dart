import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import '../day/day_grid_metrics.dart';
import 'week_focus.dart';
import 'week_grid.dart';
import 'week_header.dart';
import 'week_metrics.dart';
import 'week_skeleton.dart';

/// Appointments, Week: one full-width card with columns Monday to Sunday
/// for the week containing the controller's anchor. Every column shares
/// one time range (1.2 px per minute). Closed days aren't stored (GAP),
/// so no column is drawn as closed.
///
/// Opening a day (its date or one of its visits): that column's edges
/// move out until it fills the grid, the other days squeeze away, and the
/// card's right edge comes in to where Day's grid ends; then Day takes
/// over. Back from Day, Week starts there and folds back into the week.
class AppointmentsWeekView extends ConsumerStatefulWidget {
  const AppointmentsWeekView({super.key});

  @override
  ConsumerState<AppointmentsWeekView> createState() =>
      _AppointmentsWeekViewState();
}

class _AppointmentsWeekViewState extends ConsumerState<AppointmentsWeekView>
    with SingleTickerProviderStateMixin {
  static const EdgeInsets _cardPadding = EdgeInsets.fromLTRB(
    CruSpace.s12,
    CruSpace.s16,
    CruSpace.s16,
    CruSpace.s18,
  );

  /// Day's grid card padding (DayGrid); the card eases to it as a column
  /// opens, so the last frame is Day's card exactly.
  static const EdgeInsets _dayPadding = EdgeInsets.fromLTRB(
    CruSpace.s16,
    CruSpace.s20,
    CruSpace.s20,
    CruSpace.s22,
  );

  /// 0 = the week, 1 = the opening column fills the grid.
  late final AnimationController _open;
  late final Animation<double> _curve;

  /// The column opening (or folding back), 0 = Monday.
  int? _focus;
  bool _folding = false;

  /// The visit Day shows selected; it is ringed while the column opens.
  String? _ringId;

  /// Back from Day: the ring still to work out once the theme is there.
  String? _fromDayVisit;
  bool _fromDay = false;

  /// The week's scroll; Week and Day hand the offset to each other.
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    _open = AnimationController(vsync: this, duration: CruMotion.standard);
    _curve = CurvedAnimation(
      parent: _open,
      curve: CruMotion.curve,
      reverseCurve: CruMotion.curve.flipped,
    );

    final controller = ref.read(apptsControllerProvider.notifier);
    final fromDay = controller.takeWeekFromDay();
    // Back from Day: start where Day was scrolled.
    _scroll = ScrollController(
      initialScrollOffset: fromDay ? controller.dayScroll : 0,
    );
    if (!fromDay) return;
    final state = ref.read(apptsControllerProvider);
    final anchor = state.anchor;
    final i = ApptsBuilder.weekDays(
      anchor,
    ).indexWhere((d) => DateUtils.isSameDay(d, anchor));
    if (i < 0) return;
    _focus = i;
    _fromDay = true;
    _fromDayVisit = state.selectedVisitId;
    _open.value = 1;
    WidgetsBinding.instance.addPostFrameCallback((_) => _foldBack());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fromDay) {
      _fromDay = false;
      final anchor = ref.read(apptsControllerProvider).anchor;
      _ringId = _dayRing(anchor, _fromDayVisit);
    }
  }

  /// The visit Day rings on [day]: [visitId], else its default selection
  /// (first waiting, else next up) when the right column is beside it.
  String? _dayRing(DateTime day, String? visitId) {
    if (visitId != null) return visitId;
    if (MediaQuery.sizeOf(context).width < CruBreakpoint.splitPane) return null;
    final items = ref.read(apptDayItemsProvider(ApptsBuilder.dateOnly(day)));
    final list = items.value;
    if (list == null) return null;
    return ApptsBuilder.defaultSelection(list, ref.read(apptsNowProvider))?.id;
  }

  @override
  void deactivate() {
    _folding = false;
    super.deactivate();
  }

  @override
  void dispose() {
    _open.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Back from Day: Day fades out over the open column, then it folds.
  Future<void> _foldBack() async {
    if (!mounted) return;
    _folding = true;
    final fast = CruMotion.of(context, CruMotion.fast);
    final std = CruMotion.of(context);
    await Future<void>.delayed(fast);
    if (!mounted || !_folding) return;
    _open.duration = std;
    try {
      await _open.reverse();
    } on TickerCanceled {
      return;
    }
    if (mounted && _folding) setState(() => _focus = null);
    _folding = false;
  }

  /// Opens column [index]'s [day] once the column has filled the grid.
  Future<void> _openDay(int index, DateTime day, {String? visitId}) async {
    if (_open.isAnimating || _focus != null || index < 0) return;
    setState(() {
      _focus = index;
      _ringId = _dayRing(day, visitId);
    });
    final std = CruMotion.of(context);
    _open.duration = std;
    try {
      await _open.forward(from: 0);
    } on TickerCanceled {
      return;
    }
    if (!mounted) return;
    final controller = ref.read(apptsControllerProvider.notifier);
    // Day opens scrolled exactly as the week is now.
    controller.handoffScroll = _scroll.hasClients ? _scroll.offset : 0;
    controller.openDay(day, visitId: visitId);
  }

  @override
  Widget build(BuildContext context) {
    final anchor = ref.watch(apptsControllerProvider.select((s) => s.anchor));
    final now = ref.watch(apptsNowProvider);
    final today = ApptsBuilder.dateOnly(now);
    final days = ApptsBuilder.weekDays(anchor);
    final async = ref.watch(apptItemsProvider);
    final all = async.value;

    if (all == null) {
      return SizedBox(
        width: double.infinity,
        child: async.hasError
            ? CruCard(
                child: Text(
                  "Couldn't load appointments.",
                  style: CruType.text.tint(context.cru.label2),
                ),
              )
            : const WeekSkeleton(),
      );
    }

    final last = days.last;
    final weekItems = ApptsBuilder.inRange(
      all,
      days.first,
      DateTime(last.year, last.month, last.day + 1),
    );
    // All seven columns share one range, built from the whole week.
    final range = ApptsBuilder.range(weekItems, days.first);
    final groups = <DateTime, List<OverlapGroup>>{
      for (final d in days)
        d: ref.watch(apptDayGroupsProvider(d)).value ?? const <OverlapGroup>[],
    };
    // Day's grid stops where its right column starts (split layout).
    final split = MediaQuery.sizeOf(context).width >= CruBreakpoint.splitPane;

    return LayoutBuilder(
      builder: (context, constraints) {
        final full = constraints.maxWidth;
        final dayGrid = split
            ? full - CruSize.rightColumn - CruSpace.cardGap
            : full;
        return AnimatedBuilder(
          animation: _curve,
          builder: (context, _) {
            final t = _focus == null ? 0.0 : _curve.value;
            final focus = WeekFocus(_focus, t, ringedId: _ringId);
            final c = context.cru;
            return Align(
              alignment: Alignment.topLeft,
              child: Container(
                width: lerpDouble(full, dayGrid, t),
                // Day's card fills the height; the week's grows to it.
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight * t,
                ),
                child: Semantics(
                  container: true,
                  label: 'Week schedule',
                  child: CustomPaint(
                    painter: _OpeningCardPainter(
                      surface: c.surface,
                      border: c.cardBorder,
                      t: t,
                      column: _focus == null
                          ? null
                          : _openingColumn(
                              lerpDouble(full, dayGrid, t)!,
                              focus,
                            ),
                      // Day's grid starts after its border, padding and
                      // time column; it ends at its padding.
                      dayLeft: 1 + _dayPadding.left + DayGridMetrics.gutter,
                      dayRight: 1 + _dayPadding.right,
                      to: Size(dayGrid, constraints.maxHeight),
                    ),
                    child: Padding(
                      // Inside the 1 px border, as CruCard does.
                      padding:
                          EdgeInsets.lerp(_cardPadding, _dayPadding, t)! +
                          const EdgeInsets.all(1),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Day has no date row: it folds away as the column
                          // opens, so the hours land where Day draws them.
                          ClipRect(
                            child: Align(
                              alignment: Alignment.topCenter,
                              heightFactor: 1 - t,
                              child: Opacity(
                                opacity: 1 - t,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    WeekHeaderRow(
                                      days: days,
                                      today: today,
                                      focus: focus,
                                      onOpenDay: _openDay,
                                    ),
                                    const SizedBox(height: CruSpace.s10),
                                    const CruSeparator(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Flexible(
                            child: SingleChildScrollView(
                              controller: _scroll,
                              // Day's session inset by the end.
                              padding: EdgeInsets.only(
                                top: lerpDouble(
                                  WeekMetrics.gridTop,
                                  DayGridMetrics.topInset,
                                  t,
                                )!,
                                bottom: lerpDouble(
                                  WeekMetrics.gridBottom,
                                  DayGridMetrics.topInset,
                                  t,
                                )!,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: _grid(
                                  range,
                                  days,
                                  groups,
                                  today,
                                  now,
                                  focus,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Where the opening column is right now in a card [cardWidth] wide (the
  /// same sums as WeekColumnsRow), so the box hugs it and nothing in the
  /// column pokes out of the box.
  static ({double left, double width}) _openingColumn(
    double cardWidth,
    WeekFocus focus,
  ) {
    final t = focus.t;
    final pad = EdgeInsets.lerp(_cardPadding, _dayPadding, t)!;
    final available = cardWidth - pad.horizontal - 2 - focus.gutter;
    final even = available / 7;
    return (
      left:
          1 + pad.left + focus.gutter + focus.index! * lerpDouble(even, 0, t)!,
      width: lerpDouble(even, available, t)!,
    );
  }

  List<Widget> _grid(
    DayRange range,
    List<DateTime> days,
    Map<DateTime, List<OverlapGroup>> groups,
    DateTime today,
    DateTime now,
    WeekFocus focus,
  ) {
    final sessions = range.sessions;
    final grid = <Widget>[];
    for (var i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      final start = WeekMetrics.minuteOf(s.start, s.start);
      final end = WeekMetrics.minuteOf(s.end, s.start);
      final isLast = i == sessions.length - 1;
      // Groups belong to the session they start in; the last session
      // takes anything after it, the first anything before it.
      bool inSession(OverlapGroup g) {
        final m = g.start.hour * 60 + g.start.minute;
        final afterStart = i == 0 || m >= start;
        final beforeEnd = isLast || m < end;
        return afterStart && beforeEnd;
      }

      if (i > 0) {
        grid.add(WeekBreakBand(from: sessions[i - 1].end, to: s.start));
      }
      grid.add(
        WeekSessionGrid(
          startMinute: start,
          endMinute: end,
          days: days,
          groupsByDay: {
            for (final e in groups.entries)
              e.key: e.value.where(inSession).toList(),
          },
          today: today,
          now: now,
          focus: focus,
          onOpenVisit: (day, item) =>
              _openDay(days.indexOf(day), day, visitId: item.id),
        ),
      );
    }
    return grid;
  }
}

/// The Week card, and while a day opens, the box that grows out of its
/// column into Day's card. The box starts exactly on the column (from its
/// date down to the grid's foot) and its edges move out on all four sides
/// to Day's card, [to] at the top left; the week's own card fades as it
/// grows. At rest it paints exactly what CruCard paints.
class _OpeningCardPainter extends CustomPainter {
  _OpeningCardPainter({
    required this.surface,
    required this.border,
    required this.t,
    required this.column,
    required this.dayLeft,
    required this.dayRight,
    required this.to,
  });

  final Color surface;
  final Color border;
  final double t;

  /// The opening column where it is now; null when no day is opening.
  final ({double left, double width})? column;

  /// The box's margin beside the column at the end: Day's card edge to its
  /// grid on the left, grid to card edge on the right.
  final double dayLeft;
  final double dayRight;

  /// Day's grid card.
  final Size to;

  static const double _top = 1 + CruSpace.s16;
  static const double _bottom = 1 + CruSpace.s18;

  static void _shape(
    Canvas canvas,
    Rect rect,
    double radius,
    Color fill,
    Color side,
  ) {
    ShapeDecoration(
        color: fill,
        shape: cruShape(radius, side: BorderSide(color: side)),
        shadows: const [],
      ).createBoxPainter(() {})
      ..paint(
        canvas,
        rect.topLeft,
        ImageConfiguration(size: rect.size, textDirection: TextDirection.ltr),
      )
      ..dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final col = column;
    final open = col != null && t > 0;
    final fade = open ? 1 - t : 1.0;
    _shape(
      canvas,
      Offset.zero & size,
      CruRadius.card,
      surface.withValues(alpha: surface.a * fade),
      border.withValues(alpha: border.a * fade),
    );
    if (!open) return;
    // Sides: the column plus margins that grow into Day's. Top and bottom:
    // from the column's date and foot out to Day's card.
    final box = Rect.fromLTRB(
      col.left - dayLeft * t,
      lerpDouble(_top, 0, t)!,
      col.left + col.width + dayRight * t,
      lerpDouble(size.height - _bottom, to.height, t)!,
    );
    _shape(
      canvas,
      box,
      lerpDouble(CruRadius.control, CruRadius.card, t)!,
      surface,
      // No edge on the column at rest; the card's border by the end.
      border.withValues(alpha: border.a * t),
    );
  }

  @override
  bool shouldRepaint(_OpeningCardPainter old) =>
      old.t != t ||
      old.column != column ||
      old.dayLeft != dayLeft ||
      old.dayRight != dayRight ||
      old.to != to ||
      old.surface != surface ||
      old.border != border;
}
