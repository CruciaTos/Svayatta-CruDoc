import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_format.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The next free start for a visit of [durationMinutes] on [start]'s day,
/// at or after [start] (and never in the past). Working hours aren't
/// stored (GAP), so the day ends where the drawn range ends, stretched to
/// include the requested visit. Null when nothing fits.
DateTime? apptNextFreeSlot(
  WidgetRef ref, {
  required DateTime start,
  required int durationMinutes,
  String? excludeVisitId,
}) {
  final day = ApptsBuilder.dateOnly(start);
  final items = ref.read(apptDayItemsProvider(day)).value ?? const [];
  final now = ref.read(apptsNowProvider);
  var after = start;
  if (after.isBefore(now)) {
    // Round now up to the snap grid.
    final snapped = ApptsBuilder.snap(now);
    after = snapped.isBefore(now)
        ? snapped.add(const Duration(minutes: kApptSnapMinutes))
        : snapped;
  }
  var rangeEnd = ApptsBuilder.range(items, day).end;
  final requestedEnd = start.add(Duration(minutes: durationMinutes));
  if (requestedEnd.isAfter(rangeEnd)) rangeEnd = requestedEnd;
  return ApptsBuilder.nextFreeSlot(
    dayItems: items,
    after: after,
    durationMinutes: durationMinutes,
    rangeEnd: rangeEnd,
    excludeVisitId: excludeVisitId,
  );
}

/// Inline, under a time field: the repository refused a fifth visit at
/// one moment. Offers the next free slot as a chip.
class ApptCapNotice extends StatelessWidget {
  const ApptCapNotice({
    super.key,
    required this.at,
    required this.nextFree,
    required this.onPick,
  });

  /// The requested start.
  final DateTime at;
  final DateTime? nextFree;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final slot = nextFree;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$kMaxOverlappingVisits visits already at ${ApptFormat.time(at)}. '
          "That's the most CruDoc allows at one time.",
          style: CruType.caption.w500.tabular.tint(c.amberText),
        ),
        if (slot != null) ...[
          const SizedBox(height: CruSpace.s8),
          CruCapsuleButton(
            label: ApptFormat.time(slot),
            icon: CruIcons.clock,
            kind: CruCapsuleKind.tinted,
            semanticLabel: 'Use the next free slot, ${ApptFormat.time(slot)}',
            onPressed: () => onPick(slot),
          ),
        ],
      ],
    );
  }
}

/// Inline, under a time field: any other reason the save was refused.
class ApptInlineError extends StatelessWidget {
  const ApptInlineError(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: CruType.caption.w500.tabular.tint(context.cru.amberText),
      );
}
