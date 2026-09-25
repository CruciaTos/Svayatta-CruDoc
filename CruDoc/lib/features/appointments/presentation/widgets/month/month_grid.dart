import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import 'month_metrics.dart';
import 'month_tile.dart';

/// Weekday labels and the Monday-first tiles of [month]. No container
/// card: every date is its own rounded tile.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.month,
    required this.today,
    required this.selected,
    required this.loading,
    required this.onSelect,
    required this.onOpen,
  });

  /// Any date in the month shown.
  final DateTime month;
  final DateTime today;
  final DateTime selected;

  /// Visits are still loading: tiles show placeholders.
  final bool loading;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<DateTime> onOpen;

  MonthTileKind _kind(DateTime d) {
    if (d.month != month.month || d.year != month.year) {
      return MonthTileKind.otherMonth;
    }
    if (d == today) return MonthTileKind.today;
    return d.isBefore(today) ? MonthTileKind.past : MonthTileKind.future;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final days = ApptsBuilder.monthGrid(month);
    final weeks = [
      for (var i = 0; i + 7 <= days.length; i += 7) days.sublist(i, i + 7),
    ];

    Widget spaced(List<Widget> cells) {
      final children = <Widget>[];
      for (var i = 0; i < cells.length; i++) {
        if (i > 0) children.add(const SizedBox(width: MonthMetrics.gap));
        children.add(Expanded(child: cells[i]));
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        spaced([
          for (final d in days.take(7))
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CruSpace.s10,
                0,
                CruSpace.s10,
                CruSpace.s8,
              ),
              child: Text(
                DateFormat('E').format(d),
                style: CruType.groupLabel.tint(c.label2),
              ),
            ),
        ]),
        for (var w = 0; w < weeks.length; w++) ...[
          if (w > 0) const SizedBox(height: MonthMetrics.gap),
          spaced([
            for (final d in weeks[w])
              SizedBox(
                height: MonthMetrics.tileHeight,
                child: loading && _kind(d) != MonthTileKind.otherMonth
                    ? const _TileSkeleton()
                    : MonthDayTile(
                        key: ValueKey(d),
                        date: d,
                        kind: _kind(d),
                        selected: d == selected &&
                            _kind(d) != MonthTileKind.otherMonth,
                        onSelect: () => onSelect(d),
                        onOpen: () => onOpen(d),
                      ),
              ),
          ]),
        ],
      ],
    );
  }
}

class _TileSkeleton extends StatelessWidget {
  const _TileSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: c.surface.withValues(alpha: MonthMetrics.pastTileAlpha),
        shape: cruShape(
          MonthMetrics.tileRadius,
          side: BorderSide(color: c.hairline),
        ),
      ),
      child: const Padding(
        padding: MonthMetrics.tilePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: MonthMetrics.dateRow,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SkeletonBox(width: 18, height: 12),
              ),
            ),
            SizedBox(height: CruSpace.s8),
            SkeletonBox(width: 56, height: 10),
          ],
        ),
      ),
    );
  }
}
