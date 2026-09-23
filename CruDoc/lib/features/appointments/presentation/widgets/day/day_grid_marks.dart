import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/day/day_grid_metrics.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_format.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// "9 AM" in the gutter and a hairline across the grid (the caller
/// positions it so the line sits on the hour).
class DayHourMark extends StatelessWidget {
  const DayHourMark({super.key, required this.hour});

  final int hour;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return SizedBox(
      height: CruType.groupLabel.fontSize! * CruType.groupLabel.height!,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            width: DayGridMetrics.hourLabelWidth,
            top: 0,
            child: Text(
              ApptFormat.hour(hour),
              textAlign: TextAlign.right,
              style: CruType.groupLabel.w500.tabular.tint(c.label3),
            ),
          ),
          Positioned(
            left: DayGridMetrics.gutter,
            right: 0,
            // The line sits on the label's centre line.
            top: CruType.groupLabel.fontSize! * CruType.groupLabel.height! / 2,
            height: 1,
            child: ColoredBox(color: c.separator),
          ),
        ],
      ),
    );
  }
}

/// Today only: a 2 px accent line with a dot, and the time in a pill in
/// the gutter. Centred on its own box so the caller positions the centre.
class DayNowLine extends StatelessWidget {
  const DayNowLine({super.key, required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    const h = DayGridMetrics.gutterPill;
    return IgnorePointer(
      child: SizedBox(
        height: h,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: DayGridMetrics.gutter - CruSpace.s4,
              right: 0,
              top: (h - DayGridMetrics.nowLine) / 2,
              height: DayGridMetrics.nowLine,
              child: ColoredBox(color: c.accent),
            ),
            Positioned(
              left: DayGridMetrics.gutter - CruSpace.s8,
              top: (h - DayGridMetrics.nowDot) / 2,
              width: DayGridMetrics.nowDot,
              height: DayGridMetrics.nowDot,
              child: DecoratedBox(
                decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
              ),
            ),
            Positioned(
              left: CruSpace.s4,
              top: 0,
              height: h,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: CruSpace.s6),
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: c.accent,
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  ApptFormat.clock(now),
                  style: CruType.micro.w600.tabular.tint(c.onAccent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An unsorted future overlap: a 4 px amber bar in the gutter spanning
/// the overlap, and an amber "2 at once" pill to its left.
class DayOverlapMarker extends StatelessWidget {
  const DayOverlapMarker({super.key, required this.group, required this.height});

  final OverlapGroup group;

  /// Height of the bar (the overlap's span on the grid).
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    const pill = DayGridMetrics.gutterPill;
    // Centre the pill on the first block row (at most 32 px tall).
    final pillTop = ((height.clamp(pill, DayGridMetrics.minutes(20)) - pill) / 2)
        .toDouble();
    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: DayGridMetrics.gutter - CruSpace.s2,
              top: 0,
              bottom: 0,
              width: DayGridMetrics.markerBar,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: c.amber,
                  shape: const StadiumBorder(),
                ),
              ),
            ),
            Positioned(
              // Ends 4 px before the bar; may run past the gutter's left
              // edge into the card padding so "2 at once" never clips.
              left: -CruSpace.s24,
              width: DayGridMetrics.gutter - CruSpace.s6 + CruSpace.s24,
              top: pillTop,
              height: pill,
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: CruSpace.s6),
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: c.amberTint,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    '${group.peak} at once',
                    maxLines: 1,
                    softWrap: false,
                    style: CruType.micro.w600.tabular.tint(c.amberText),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Morning session · 9:30 AM to 1:30 PM · 10 booked" above a session.
/// Only drawn when working hours give the session a label (a GAP today).
class DaySessionLabel extends StatelessWidget {
  const DaySessionLabel({
    super.key,
    required this.session,
    required this.booked,
  });

  final ClinicSession session;
  final int booked;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.only(
        left: DayGridMetrics.blockLeft,
        bottom: CruSpace.s12,
      ),
      child: Text.rich(
        TextSpan(
          text: session.label,
          style: CruType.groupLabel.tint(c.label2),
          children: [
            TextSpan(
              text: '  ${ApptFormat.range(session.start, session.end)} · '
                  '$booked booked',
              style: CruType.groupLabel
                  .copyWith(fontWeight: FontWeight.w400)
                  .tabular
                  .tint(c.label3),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// "Break · 1:30 to 5:00 PM": the gap between sessions, not to scale.
class DayBreakBand extends StatelessWidget {
  const DayBreakBand({super.key, required this.from, required this.to});

  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      height: DayGridMetrics.breakBand,
      margin: const EdgeInsets.only(
        left: DayGridMetrics.gutter,
        top: CruSpace.s12,
        bottom: CruSpace.s18,
      ),
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.iconTile),
      ),
      child: Text(
        'Break · ${ApptFormat.range(from, to)}',
        style: CruType.caption.tabular.tint(c.label2),
      ),
    );
  }
}

/// Under the grid, only on days with an overlap to sort out. The grey
/// "kept" item is a GAP (nothing stores that decision), so it's hidden.
class DayOverlapLegend extends StatelessWidget {
  const DayOverlapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.only(
        left: DayGridMetrics.blockLeft,
        top: CruSpace.s12,
      ),
      child: Row(
        children: [
          SizedBox(
            width: DayGridMetrics.markerBar,
            height: CruSpace.s14,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: c.amber,
                shape: const StadiumBorder(),
              ),
            ),
          ),
          const SizedBox(width: CruSpace.s8),
          Text('Overlap to sort out', style: CruType.caption.tint(c.label2)),
        ],
      ),
    );
  }
}
