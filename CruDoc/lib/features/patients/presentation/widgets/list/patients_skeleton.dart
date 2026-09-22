import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The list card while patients load: fixed 64 px rows, so nothing jumps
/// when the data arrives.
class PatientsSkeleton extends StatelessWidget {
  const PatientsSkeleton({super.key, this.rows = 8});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      label: 'Loading patients',
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
            Container(
              height: CruSize.tableHeader,
              padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.separator)),
              ),
              child: const SkeletonBox(width: 120, height: 12),
            ),
            const SizedBox(height: CruSpace.s8),
            for (var i = 0; i < rows; i++)
              SizedBox(
                height: CruSize.tableRow,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CruSpace.s16,
                  ),
                  child: Row(
                    children: [
                      const SkeletonBox(
                        width: CruSize.monogramList,
                        height: CruSize.monogramList,
                        circle: true,
                      ),
                      const SizedBox(width: CruSpace.s12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: i.isEven ? 160 : 128, height: 14),
                            const SizedBox(height: CruSpace.s6),
                            const SkeletonBox(width: 96, height: 12),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
