import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/day/day_grid.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/day/day_right_column.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/day/day_skeleton.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appts_side_sheet.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The Day view: the grid card and the 384 px right column. Below
/// [CruBreakpoint.splitPane] the right column becomes a sheet that
/// slides over the grid when something is selected.
///
/// With nothing selected, the split layout shows the default selection
/// (the first patient waiting, otherwise the next upcoming visit) without
/// writing it to the controller, so the sheet doesn't pop open by itself.
class AppointmentsDayView extends ConsumerWidget {
  const AppointmentsDayView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(apptsControllerProvider);
    final day = ApptsBuilder.dateOnly(state.anchor);
    final itemsAsync = ref.watch(apptDayItemsProvider(day));
    final groupsAsync = ref.watch(apptDayGroupsProvider(day));
    final now = ref.watch(apptsNowProvider);
    final split = MediaQuery.sizeOf(context).width >= CruBreakpoint.splitPane;

    final items = itemsAsync.value;
    final groups = groupsAsync.value;
    if (items == null || groups == null) {
      if (itemsAsync.hasError) return const _LoadError();
      return DaySkeleton(split: split);
    }

    OverlapGroup? group;
    final groupStart = state.selectedGroupStart;
    if (groupStart != null) {
      for (final g in groups) {
        if (g.isOverlap &&
            g.kind == OverlapKind.unsorted &&
            g.start == groupStart) {
          group = g;
          break;
        }
      }
    }
    ApptItem? selected;
    if (group == null && state.selectedVisitId != null) {
      for (final i in items) {
        if (i.id == state.selectedVisitId) {
          selected = i;
          break;
        }
      }
    }
    final explicit = group != null || selected != null;
    if (!explicit && split) {
      selected = ApptsBuilder.defaultSelection(items, now);
    }

    final ringed = <String>{
      if (group != null) ...group.items.map((i) => i.id),
      if (selected != null) selected.id,
    };

    final grid = DayGrid(
      key: ValueKey(day),
      day: day,
      items: items,
      groups: groups,
      now: now,
      ringedIds: ringed,
    );
    final column = DayRightColumn(
      day: day,
      dayItems: items,
      selected: selected,
      group: group,
    );

    if (split) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: grid),
          const SizedBox(width: CruSpace.cardGap),
          SizedBox(width: CruSize.rightColumn, child: column),
        ],
      );
    }
    return ApptsSideSheet(
      open: explicit,
      content: grid,
      sheet: column,
      onClose: () => ref.read(apptsControllerProvider.notifier).select(null),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError();

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: 'Day schedule',
      child: Center(
        child: Text(
          "Couldn't load appointments.",
          style: CruType.text.tint(c.label2),
        ),
      ),
    );
  }
}
