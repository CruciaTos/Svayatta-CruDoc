import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/revenue/domain/revenue_builder.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_models.dart';

import 'revenue_fixtures.dart';

void main() {
  group('periods', () {
    test('month runs 1 to 23 September against 1 to 23 August', () {
      final w = RevenueBuilder.window(RevenuePeriod.month, revenueNow);
      expect(w.toDate, DateSpan(DateTime(2026, 9, 1), DateTime(2026, 9, 24)));
      expect(w.previous, DateSpan(DateTime(2026, 8, 1), DateTime(2026, 8, 24)));
      expect(RevenueBuilder.subtitle(w), 'September 2026 · 1 to 23 September');
      expect(RevenueBuilder.comparisonLabel(w), 'August, same days');
    });

    test('month clamps to a shorter previous month', () {
      final w = RevenueBuilder.window(RevenuePeriod.month, DateTime(2026, 3, 31));
      expect(w.previous, DateSpan(DateTime(2026, 2, 1), DateTime(2026, 3, 1)));
    });

    test('week starts on Monday', () {
      final w = RevenueBuilder.window(RevenuePeriod.week, revenueNow);
      expect(w.toDate.start, DateTime(2026, 9, 21));
      expect(w.previous, DateSpan(DateTime(2026, 9, 14), DateTime(2026, 9, 17)));
      expect(RevenueBuilder.subtitle(w), 'This week · 21 to 23 September');
    });

    test('year and today subtitles', () {
      expect(
        RevenueBuilder.subtitle(RevenueBuilder.window(RevenuePeriod.year, revenueNow)),
        '2026 · 1 January to 23 September',
      );
      expect(
        RevenueBuilder.subtitle(RevenueBuilder.window(RevenuePeriod.today, revenueNow)),
        'Wednesday, 23 September',
      );
    });
  });

  test('overview matches the mock-up figures', () {
    final o = RevenueBuilder.overview(
      entries: buildRevenueEntries(),
      period: RevenuePeriod.month,
      filter: TxnFilter.all,
      now: revenueNow,
    );
    expect(o.collected, 67300);
    expect(o.expenses, 38700);
    expect(o.net, 28600);
    expect(o.netPercent, 42);
    expect(o.comparison.percent, 6);
    expect(o.expenseCaption, 'Clinic rent, staff salary, medical supplies');
    expect(o.todayIn, 3400);
    expect(o.todayOut, 200);

    final first = o.transactions.first;
    expect(first.title, 'Sunita Joshi');
    expect(first.dayLabel, 'Today');
    expect((first.time, first.meridiem), ('11:24', 'AM'));
    final gloves = o.transactions[5];
    expect(gloves.title, 'Gloves, 1 box');
    expect(gloves.subtitle, 'Medical supplies');
    expect(gloves.amount, '−₹200');
  });

  test('chart: one bar per day, Sundays flat, future outlined', () {
    final w = RevenueBuilder.window(RevenuePeriod.month, revenueNow);
    final chart = RevenueBuilder.chart(buildRevenueEntries(), w);
    expect(chart.bars, hasLength(30));
    expect(chart.bars[5].kind, BarKind.emptyPast); // Sunday 6
    expect(chart.bars[22].kind, BarKind.today);
    expect(chart.bars[23].kind, BarKind.future);
    expect(chart.todayAmount, 3400);
    expect(chart.ticks, [0, 2000, 4000]);
    expect(
      [for (final b in chart.bars) if (b.label != null) b.label],
      ['1', '7', '14', '21', '23', '28'],
    );
  });

  test('money filters', () {
    List<TxnRow> rows(TxnFilter f) => RevenueBuilder.overview(
          entries: buildRevenueEntries(),
          period: RevenuePeriod.today,
          filter: f,
          now: revenueNow,
        ).transactions;
    expect(rows(TxnFilter.all), hasLength(6));
    expect(rows(TxnFilter.moneyIn), hasLength(5));
    expect(rows(TxnFilter.moneyOut), hasLength(1));
  });

  test('pending grouped per patient, oldest first', () {
    final groups = RevenueBuilder.pendingGroups(
      revenuePending,
      revenuePatients,
      revenueNow,
    );
    expect([for (final g in groups) g.name],
        ['Rohan Mehta', 'Lakshmi Reddy', 'Anil Gupta']);
    expect(groups.first.detail, 'Visit on 6 Sep · 17 days');
    expect(groups.first.overdue, isTrue);
    expect(groups[1].overdue, isFalse);
    expect(groups.last.detail, 'Lab tests on 16 Sep · 7 days');
    expect(groups.every((g) => g.canRemind), isTrue);
  });

  test('descriptions', () {
    expect(RevenueBuilder.splitDescription('Medical Supplies (Gloves)'),
        ('Medical Supplies', 'Gloves'));
    expect(RevenueBuilder.sentence('Consultation and HbA1c'),
        'Consultation and HbA1c');
    expect(RevenueBuilder.niceTicks(900), [0, 250, 500, 750]);
  });
}
