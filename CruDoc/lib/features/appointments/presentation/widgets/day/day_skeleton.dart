import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/appointments/presentation/widgets/day/day_grid_metrics.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Loading state for the Day view: grey blocks where the visits will
/// be, and the right column's cards, at their final sizes.
class DaySkeleton extends StatelessWidget {
  const DaySkeleton({super.key, required this.split});

  /// Wide layout: also draw the right column.
  final bool split;

  /// One 20-minute block and the gap below it.
  static const double _block = DayGridMetrics.pxPerMinute * 20 - 2;
  static const double _gap = DayGridMetrics.pxPerMinute * 10;

  @override
  Widget build(BuildContext context) {
    final grid = CruCard(
      semanticLabel: 'Loading the day',
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s16,
        CruSpace.s20,
        CruSpace.s20,
        CruSpace.s22,
      ),
      child: ClipRect(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < 12; i++)
                Padding(
                  padding: const EdgeInsets.only(
                    left: DayGridMetrics.blockLeft,
                    right: DayGridMetrics.blockRight,
                    bottom: _gap,
                  ),
                  child: const SkeletonBox(height: _block),
                ),
            ],
          ),
        ),
      ),
    );
    if (!split) return grid;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: grid),
        const SizedBox(width: CruSpace.cardGap),
        const SizedBox(
          width: CruSize.rightColumn,
          child: SingleChildScrollView(
            physics: NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SkeletonCard(
                  rows: 6,
                  rowHeight: CruSize.segmentItem + CruSpace.s4,
                ),
                SizedBox(height: CruSpace.cardGap),
                SkeletonCard(rows: 3),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
