import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_style.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The list card while items load: same header and 64 px rows, so
/// nothing shifts when data arrives.
class InventoryListSkeleton extends StatelessWidget {
  const InventoryListSkeleton({super.key, this.rows = 7});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading items',
      child: CruCard(
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s12,
          CruSpace.s6,
          CruSpace.s12,
          CruSpace.s12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(
              height: CruSize.tableHeader,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: CruSpace.s16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SkeletonBox(width: 64, height: 10),
                ),
              ),
            ),
            const CruSeparator(),
            const SizedBox(height: CruSpace.s6),
            for (var i = 0; i < rows; i++) const _RowSkeleton(),
          ],
        ),
      ),
    );
  }
}

class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: CruSize.tableRow,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: CruSpace.s16),
        child: Row(
          children: [
            SkeletonBox(width: CruSize.iconTile, height: CruSize.iconTile),
            SizedBox(width: CruSpace.s12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 160, height: 12),
                  SizedBox(height: CruSpace.s8),
                  SkeletonBox(width: 96, height: 10),
                ],
              ),
            ),
            SizedBox(width: InventorySize.columnGap),
            SizedBox(
              width: InventorySize.stockColumn,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 64, height: 12),
                  SizedBox(height: CruSpace.s8),
                  SkeletonBox(
                    width: InventorySize.levelBarWidth,
                    height: InventorySize.levelBarHeight,
                  ),
                ],
              ),
            ),
            SizedBox(width: InventorySize.columnGap),
            SizedBox(
              width: InventorySize.lastsColumn,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SkeletonBox(width: 80, height: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
