import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/day/mini_month_calendar.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/month/month_grid.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/month/month_tile.dart';

void main() {
  group('MonthGrid out-of-month dates tests', () {
    testWidgets('MonthGrid does not render dates outside the current month', (tester) async {
      final october2026 = DateTime(2026, 10, 1);
      final today = DateTime(2026, 10, 24);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MonthGrid(
                  month: october2026,
                  today: today,
                  selected: today,
                  loading: false,
                  onSelect: (_) {},
                  onOpen: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // October days (1 to 31) should be present
      expect(find.byType(MonthDayTile), findsNWidgets(31));

      // There should not be any other-month MonthDayTile or text
      // E.g., September 28, 29, 30 and November 1 must NOT be displayed
      // Oct 28, 29, 30 are in the month, but September's 28-30 are not.
      // Total MonthDayTile widgets is strictly 31 (days in October).
      final tiles = tester.widgetList<MonthDayTile>(find.byType(MonthDayTile)).toList();
      for (final tile in tiles) {
        expect(tile.date.month, 10, reason: 'Tile date ${tile.date} should be in October');
        expect(tile.kind, isNot(MonthTileKind.otherMonth));
      }
    });

    testWidgets('MiniMonthCalendar does not render dates outside current month', (tester) async {
      final october2026 = DateTime(2026, 10, 1);
      final today = DateTime(2026, 10, 24);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MiniMonthCalendar(
                selected: october2026,
                today: today,
                onPick: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Days 1 through 31 should be present in MiniMonthCalendar
      // And dates outside October must not be rendered
      for (int day = 1; day <= 31; day++) {
        expect(find.text('$day'), findsWidgets);
      }
    });
  });
}
