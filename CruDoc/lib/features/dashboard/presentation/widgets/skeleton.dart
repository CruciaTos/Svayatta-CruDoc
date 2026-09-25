import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// A static placeholder block shown while a section loads, sized like the
/// content it stands in for so nothing shifts when data arrives.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.circle = false,
  });

  final double? width;
  final double height;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: ShapeDecoration(
        color: context.cru.inset,
        shape: circle
            ? const CircleBorder()
            : cruShape(height / 2 > CruRadius.keycap ? CruRadius.keycap : height / 2),
      ),
    );
  }
}

/// A card-shaped skeleton with a title bar and [rows] row placeholders.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.rows = 3, this.rowHeight = CruSize.scheduleRow});

  final int rows;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    return CruCard(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(width: 140, height: 16),
          const SizedBox(height: CruSpace.s16),
          for (var i = 0; i < rows; i++)
            SizedBox(
              height: rowHeight,
              child: const Align(
                alignment: Alignment.centerLeft,
                child: SkeletonBox(height: 14),
              ),
            ),
        ],
      ),
    );
  }
}
