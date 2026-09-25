import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_format.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// One visit in the overlap card: monogram, name with a "New" tag,
/// reason (· Returning), and when it was booked. How it was booked (by
/// phone) is a GAP, so it's left out.
class OverlapVisitRow extends StatelessWidget {
  const OverlapVisitRow({super.key, required this.item, required this.now});

  final ApptItem item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final (bookedLine1, bookedLine2) = ApptFormat.booked(item.visit.createdAt, now);
    final detail = [
      if (item.reason != null) item.reason!,
      if (!item.isNewPatient) 'Returning',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s10),
      child: Row(
        children: [
          CruMonogram(
            name: item.name,
            size: CruSize.monogramList,
            background: c.inset,
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.name,
                        style: CruType.nav.w600.tint(c.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item.isNewPatient) ...[
                      const SizedBox(width: CruSpace.s6),
                      const _NewTag(),
                    ],
                  ],
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: CruType.caption.tint(c.label2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          Text(
            '$bookedLine1\n$bookedLine2',
            textAlign: TextAlign.right,
            style: CruType.groupLabel
                .copyWith(fontWeight: FontWeight.w400)
                .tabular
                .tint(c.label3),
          ),
        ],
      ),
    );
  }
}

/// The accent "New" tag after a first-time patient's name.
class _NewTag extends StatelessWidget {
  const _NewTag();

  /// Tag height (no shared token; NEEDS.md).
  static const double _height = 20;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      height: _height,
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s6),
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: c.accentTint,
        shape: const StadiumBorder(),
      ),
      child: Text('New', style: CruType.micro.w600.tint(c.accentText)),
    );
  }
}
