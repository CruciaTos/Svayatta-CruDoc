import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import 'month_day_panel.dart';
import 'month_grid.dart';
import 'month_sheet.dart';

/// Appointments, Month: weekday labels, one rounded tile per date (no
/// container card) and a 384 px day panel on the right. Below 1200 px the
/// panel becomes a sheet over the grid, opened when a tile is selected.
class AppointmentsMonthView extends ConsumerWidget {
  const AppointmentsMonthView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => const _MonthBody();
}

class _MonthBody extends ConsumerStatefulWidget {
  const _MonthBody();

  @override
  ConsumerState<_MonthBody> createState() => _MonthBodyState();
}

class _MonthBodyState extends ConsumerState<_MonthBody> {
  /// Narrow layout only: the day panel is showing as a sheet.
  bool _sheetOpen = false;

  void _closeSheet() => setState(() => _sheetOpen = false);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(apptsControllerProvider);
    final today = ApptsBuilder.dateOnly(ref.watch(apptsNowProvider));
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final selected = state.monthSelected ?? tomorrow;
    final async = ref.watch(apptItemsProvider);
    final loading = async.value == null && !async.hasError;
    final wide =
        MediaQuery.sizeOf(context).width >= CruBreakpoint.splitPane;
    final controller = ref.read(apptsControllerProvider.notifier);

    final grid = SingleChildScrollView(
      child: MonthGrid(
        month: DateTime(state.anchor.year, state.anchor.month),
        today: today,
        selected: selected,
        loading: loading,
        onSelect: (d) {
          controller.selectMonthDay(d);
          if (!wide) setState(() => _sheetOpen = true);
        },
        onOpen: (d) => controller.openDay(d),
      ),
    );

    if (wide) {
      return SizedBox(
        width: double.infinity,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: grid),
            const SizedBox(width: CruSpace.cardGap),
            SizedBox(
              width: CruSize.rightColumn,
              child: MonthDayPanel(date: selected),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned.fill(child: grid),
            if (_sheetOpen) ...[
              Positioned.fill(child: MonthSheetBackdrop(onTap: _closeSheet)),
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: math.max(
                  0.0,
                  math.min(
                    CruSize.rightColumn,
                    constraints.maxWidth - 2 * CruSpace.s16,
                  ),
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: MonthSheetSlide(
                    child: MonthDayPanel(date: selected),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
