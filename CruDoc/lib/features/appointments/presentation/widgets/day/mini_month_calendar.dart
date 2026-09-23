import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The month card at the top of the Day right column. Today is a filled
/// accent circle, the selected date a tint circle. Closed days are a GAP
/// (working hours aren't stored), so no day is greyed for that.
class MiniMonthCalendar extends StatefulWidget {
  const MiniMonthCalendar({
    super.key,
    required this.selected,
    required this.today,
    required this.onPick,
  });

  /// Date only.
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onPick;

  @override
  State<MiniMonthCalendar> createState() => _MiniMonthCalendarState();
}

class _MiniMonthCalendarState extends State<MiniMonthCalendar> {
  late DateTime _month;

  /// Day cell height and the day circle (no shared token; NEEDS.md).
  static const double _cell = 34;
  static const double _circle = 30;

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.selected.year, widget.selected.month);
  }

  @override
  void didUpdateWidget(MiniMonthCalendar old) {
    super.didUpdateWidget(old);
    if (!ApptsBuilder.sameDay(old.selected, widget.selected)) {
      _month = DateTime(widget.selected.year, widget.selected.month);
    }
  }

  void _shift(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final days = ApptsBuilder.monthGrid(_month);
    final weeks = <List<DateTime>>[
      for (var i = 0; i < days.length; i += 7) days.sublist(i, i + 7),
    ];
    return CruCard(
      semanticLabel: 'Month',
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s18,
        CruSpace.s18,
        CruSpace.s18,
        CruSpace.s14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CruSpace.s4,
              0,
              CruSpace.s4,
              CruSpace.s10,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat('MMMM yyyy').format(_month),
                    style: CruType.row.w600.tabular.tint(c.label),
                  ),
                ),
                CruIconButton(
                  icon: CruIcons.chevronLeft,
                  semanticLabel: 'Previous month',
                  size: _circle - CruSpace.s2,
                  iconSize: 16,
                  onPressed: () => _shift(-1),
                ),
                const SizedBox(width: CruSpace.s2),
                CruIconButton(
                  icon: CruIcons.chevronRight,
                  semanticLabel: 'Next month',
                  size: _circle - CruSpace.s2,
                  iconSize: 16,
                  onPressed: () => _shift(1),
                ),
              ],
            ),
          ),
          Row(
            children: [
              for (final d in _weekdays)
                Expanded(
                  child: Text(
                    d,
                    textAlign: TextAlign.center,
                    style: CruType.micro.w600.tint(c.label3),
                  ),
                ),
            ],
          ),
          const SizedBox(height: CruSpace.s2),
          for (final week in weeks)
            SizedBox(
              height: _cell,
              child: Row(
                children: [
                  for (final d in week) Expanded(child: _dayCell(context, d)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dayCell(BuildContext context, DateTime d) {
    final c = context.cru;
    final inMonth = d.month == _month.month;
    final isToday = ApptsBuilder.sameDay(d, widget.today);
    final isSelected = ApptsBuilder.sameDay(d, widget.selected);

    final Color? fill = isToday
        ? c.accent
        : isSelected
            ? c.accentTint
            : null;
    final Color fg = isToday
        ? c.onAccent
        : isSelected
            ? c.accentText
            : inMonth
                ? c.label
                : c.label3;
    var style = CruType.dateLine.tabular.tint(fg);
    if (isToday || isSelected) style = style.w600;

    return CruPressable(
      onTap: () => widget.onPick(d),
      semanticLabel: DateFormat('EEEE, d MMMM').format(d),
      builder: (context, hovered) => Center(
        child: AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          width: _circle,
          height: _circle,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: fill ?? (hovered ? c.inset : c.inset.withValues(alpha: 0)),
            shape: const CircleBorder(),
          ),
          child: Text('${d.day}', style: style),
        ),
      ),
    );
  }
}
