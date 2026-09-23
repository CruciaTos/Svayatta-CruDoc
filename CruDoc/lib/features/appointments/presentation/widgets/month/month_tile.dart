import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import 'month_metrics.dart';

/// Where a tile sits relative to today and the shown month.
enum MonthTileKind { otherMonth, past, today, future }

/// One date of the Month grid. Capacity bar, "N open" and "Almost full"
/// need working hours and slot length (GAP), so tiles show counts only.
/// Closed days aren't stored (GAP), so no tile is drawn as closed.
class MonthDayTile extends ConsumerStatefulWidget {
  const MonthDayTile({
    super.key,
    required this.date,
    required this.kind,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
  });

  final DateTime date;
  final MonthTileKind kind;
  final bool selected;

  /// Click: select the tile.
  final VoidCallback onSelect;

  /// Double-click: open that Day.
  final VoidCallback onOpen;

  @override
  ConsumerState<MonthDayTile> createState() => _MonthDayTileState();
}

class _MonthDayTileState extends ConsumerState<MonthDayTile> {
  DateTime? _lastTap;

  // Selection happens on the first click (no double-tap delay); a second
  // click within the double-tap timeout opens the day.
  void _handleTap() {
    final t = DateTime.now();
    final last = _lastTap;
    if (last != null && t.difference(last) <= kDoubleTapTimeout) {
      _lastTap = null;
      widget.onOpen();
      return;
    }
    _lastTap = t;
    widget.onSelect();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final kind = widget.kind;

    if (kind == MonthTileKind.otherMonth) {
      return Padding(
        padding: MonthMetrics.tilePadding,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: MonthMetrics.dateRow,
            child: Center(
              child: Text(
                '${widget.date.day}',
                style: CruType.chip.w600.tabular.tint(c.label3),
              ),
            ),
          ),
        ),
      );
    }

    final counts = ref.watch(apptDayCountsProvider(widget.date)).value;
    final lines = _lines(counts, c);
    final overlap = counts?.hasUnsortedOverlap ?? false;
    final summary = lines.map((l) => l.text).join(', ');

    return CruPressable(
      onTap: _handleTap,
      scaleOnPress: false,
      semanticLabel: '${DashFormat.dateLine(widget.date)}'
          '${summary.isEmpty ? '' : ', $summary'}',
      builder: (context, hovered) {
        // Selected: accent wash + 2 px accent ring. Past: 55% white +
        // hairline. Today and future: white + hairline + soft shadow.
        Color fill = c.surface;
        BorderSide side = BorderSide(color: c.hairline);
        List<BoxShadow>? shadows = c.cardShadow;
        if (widget.selected) {
          fill = c.accentWash;
          side = BorderSide(color: c.accent, width: MonthMetrics.ringWidth);
          shadows = null;
        } else if (kind == MonthTileKind.past) {
          fill = c.surface.withValues(alpha: MonthMetrics.pastTileAlpha);
          shadows = null;
        }
        return AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: MonthMetrics.tileHeight,
          padding: MonthMetrics.tilePadding,
          decoration: ShapeDecoration(
            color: hovered ? cruHoverShade(fill, c) : fill,
            shape: cruShape(MonthMetrics.tileRadius, side: side),
            shadows: shadows,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: MonthMetrics.dateRow,
                child: Row(
                  children: [
                    _DateNumber(
                      day: widget.date.day,
                      today: kind == MonthTileKind.today,
                    ),
                    if (overlap) ...[
                      const SizedBox(width: CruSpace.s6),
                      const CruStatusDot(
                        CruDotKind.waiting,
                        size: CruSize.smallDot,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: CruSpace.s4),
              for (final l in lines)
                Text(
                  l.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: l.style,
                ),
            ],
          ),
        );
      },
    );
  }

  /// Past: "N seen", then "N missed" on its own line. Today: "N booked"
  /// and an accent "N seen so far". Future: "N booked". Empty days show
  /// nothing.
  List<({String text, TextStyle style})> _lines(ApptDayCounts? counts, CruColors c) {
    if (counts == null || counts.appointments == 0) return const [];
    return switch (widget.kind) {
      MonthTileKind.past => [
          (text: '${counts.seen} seen', style: CruType.caption.tabular.tint(c.label2)),
          if (counts.missed > 0)
            (
              text: '${counts.missed} missed',
              style: CruType.caption.tabular.tint(c.label3),
            ),
        ],
      MonthTileKind.today => [
          (
            text: '${counts.appointments} booked',
            style: CruType.caption.w500.tabular.tint(c.label),
          ),
          if (counts.seen > 0)
            (
              text: '${counts.seen} seen so far',
              // 12 px in the design; caption (12.5) clips on a 97 px tile.
              style: CruType.micro.w600.tabular.tint(c.accentText),
            ),
        ],
      MonthTileKind.future => [
          (
            text: '${counts.appointments} booked',
            style: CruType.caption.w500.tabular.tint(c.label),
          ),
        ],
      MonthTileKind.otherMonth => const [],
    };
  }
}

class _DateNumber extends StatelessWidget {
  const _DateNumber({required this.day, required this.today});

  final int day;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    if (!today) {
      return Text('$day', style: CruType.chip.w600.tabular.tint(c.label));
    }
    return Container(
      width: MonthMetrics.dateRow,
      height: MonthMetrics.dateRow,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
      child: Text('$day', style: CruType.chip.w600.tabular.tint(c.onAccent)),
    );
  }
}
