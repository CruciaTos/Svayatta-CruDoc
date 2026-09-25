import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import 'week_metrics.dart';

/// The Week card while visits load: header placeholders and quiet
/// columns, the same size as the loaded card so nothing jumps.
class WeekSkeleton extends StatelessWidget {
  const WeekSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s12,
        CruSpace.s16,
        CruSpace.s16,
        CruSpace.s18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(width: WeekMetrics.gutter),
              for (var i = 0; i < 7; i++)
                const Expanded(
                  child: Column(
                    children: [
                      SkeletonBox(width: 28, height: 12),
                      SizedBox(height: CruSpace.s10),
                      SkeletonBox(
                        width: WeekMetrics.dateCircle,
                        height: WeekMetrics.dateCircle,
                        circle: true,
                      ),
                      SizedBox(height: CruSpace.s8),
                      SkeletonBox(width: 56, height: 12),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: CruSpace.s10),
          const CruSeparator(),
          const SizedBox(height: WeekMetrics.gridTop),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(width: WeekMetrics.gutter),
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: c.separator)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
