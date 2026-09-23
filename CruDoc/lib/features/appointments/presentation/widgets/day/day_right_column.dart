import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/day/mini_month_calendar.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/day/overlap_card.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/day/selected_appointment_card.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The Day view's 384 px right column: the month, then the selected
/// appointment or the selected overlap. "Open slots today" is a GAP
/// (slot length and working hours aren't stored), so it isn't built.
class DayRightColumn extends ConsumerWidget {
  const DayRightColumn({
    super.key,
    required this.day,
    required this.dayItems,
    this.selected,
    this.group,
  });

  /// Date only.
  final DateTime day;
  final List<ApptItem> dayItems;
  final ApptItem? selected;

  /// A selected unsorted overlap; replaces the appointment card.
  final OverlapGroup? group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(apptsNowProvider);
    final controller = ref.read(apptsControllerProvider.notifier);

    final Widget? card = group != null
        ? OverlapCard(
            key: ValueKey('overlap ${group!.start.toIso8601String()}'),
            group: group!,
            dayItems: dayItems,
            day: day,
          )
        : selected != null
            ? SelectedAppointmentCard(
                key: ValueKey('visit ${selected!.id}'),
                item: selected!,
              )
            : null;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MiniMonthCalendar(
            selected: day,
            today: ApptsBuilder.dateOnly(now),
            onPick: controller.goTo,
          ),
          AnimatedSwitcher(
            duration: CruMotion.of(context, CruMotion.fast),
            switchInCurve: CruMotion.curve,
            switchOutCurve: CruMotion.curve,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              fit: StackFit.passthrough,
              children: [...previous, ?current],
            ),
            child: card == null
                ? const SizedBox.shrink(key: ValueKey('none'))
                : Padding(
                    key: card.key,
                    padding: const EdgeInsets.only(top: CruSpace.cardGap),
                    child: card,
                  ),
          ),
        ],
      ),
    );
  }
}
