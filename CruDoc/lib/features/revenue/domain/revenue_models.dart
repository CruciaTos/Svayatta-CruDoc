import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';

/// Sections of the Revenue screen. "Expenses" from the design has no
/// screen of its own (GAP), so it isn't offered.
enum RevenueTab { overview, invoices }

/// The period every figure on the Overview follows.
enum RevenuePeriod { today, week, month, year }

/// The Transactions card filter.
enum TxnFilter { all, moneyIn, moneyOut }

/// A half-open date range [start, end).
class DateSpan {
  const DateSpan(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);

  @override
  bool operator ==(Object other) =>
      other is DateSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DateSpan($start, $end)';
}

/// The selected period around "now".
class PeriodWindow {
  const PeriodWindow({
    required this.period,
    required this.full,
    required this.toDate,
    required this.previous,
    required this.today,
  });

  final RevenuePeriod period;

  /// The whole period (all of September).
  final DateSpan full;

  /// From the start of the period to the end of today (1 to 23 September).
  final DateSpan toDate;

  /// The same day range of the previous period (1 to 23 August).
  final DateSpan previous;

  /// Midnight today.
  final DateTime today;
}

/// Collected now against the same days of the previous period.
class Comparison {
  const Comparison({required this.current, required this.previous});

  final double current;
  final double previous;

  /// Whole-number change, or null when the previous period had nothing
  /// to compare against.
  int? get percent =>
      previous <= 0 ? null : ((current - previous) / previous * 100).round();
}

enum BarKind {
  /// A past day with collections.
  past,

  /// Today (or this month on Year).
  today,

  /// A past day with no collections: a flat grey stub.
  emptyPast,

  /// Still to come: an empty outline stub.
  future,
}

class ChartBar {
  const ChartBar({
    required this.date,
    required this.amount,
    required this.kind,
    required this.semantic,
    this.label,
  });

  final DateTime date;
  final double amount;
  final BarKind kind;

  /// x-axis label, or null for an unlabelled bar.
  final String? label;

  /// "Tuesday, 1 September: ₹3,000".
  final String semantic;

  bool get isToday => kind == BarKind.today;
}

class ChartData {
  const ChartData({
    required this.bars,
    required this.ticks,
    required this.scaleMax,
    required this.todayAmount,
    required this.todayLegend,
    this.note,
  });

  final List<ChartBar> bars;

  /// y ticks from ₹0 up (₹0, ₹2k, ₹4k).
  final List<double> ticks;

  /// The amount drawn at full bar height.
  final double scaleMax;

  final double todayAmount;

  /// "Today" (or "This month" on Year).
  final String todayLegend;

  /// Top-right note ("This week" when the period is Today).
  final String? note;
}

/// One row of the Transactions card.
class TxnRow {
  const TxnRow({
    required this.entry,
    required this.moneyOut,
    required this.dayLabel,
    required this.time,
    required this.meridiem,
    required this.title,
    required this.subtitle,
    required this.amount,
  });

  final RevenueEntry entry;
  final bool moneyOut;

  /// "Today", "Yesterday" or "Mon 21 Sep".
  final String dayLabel;

  /// "11:24" and "AM".
  final String time;
  final String meridiem;

  /// The payer, or the item bought.
  final String title;

  /// What it was for.
  final String subtitle;

  /// "₹900" or "−₹200".
  final String amount;
}

/// Everything one patient (or payer) still owes.
class PendingGroup {
  const PendingGroup({
    required this.key,
    required this.name,
    required this.patient,
    required this.rows,
    required this.total,
    required this.oldest,
    required this.ageDays,
    required this.detail,
  });

  final String key;
  final String name;

  /// The patient record, when the pending rows link to one.
  final Patient? patient;

  /// Oldest first.
  final List<PendingPayment> rows;
  final double total;
  final DateTime oldest;
  final int ageDays;

  /// "Visit on 6 Sep · 17 days".
  final String detail;

  /// Over 14 days old: the date line turns amber.
  bool get overdue => ageDays > 14;

  /// A patient with a phone number can get a WhatsApp reminder.
  bool get canRemind => (patient?.phone.trim().isNotEmpty ?? false);
}

/// The Overview's figures for the selected period and filter.
class RevenueOverview {
  const RevenueOverview({
    required this.window,
    required this.subtitle,
    required this.collected,
    required this.expenses,
    required this.comparison,
    required this.comparisonLabel,
    required this.expenseCaption,
    required this.chart,
    required this.transactions,
    required this.periodTransactionCount,
    required this.todayIn,
    required this.todayOut,
  });

  final PeriodWindow window;

  /// "September 2026 · 1 to 23 September".
  final String subtitle;

  final double collected;
  final double expenses;
  final Comparison comparison;

  /// "August, same days".
  final String comparisonLabel;

  /// "Rent, salary, supplies".
  final String expenseCaption;

  final ChartData chart;

  /// The period's transactions after the filter, newest first.
  final List<TxnRow> transactions;

  /// Every transaction in the period, before the filter.
  final int periodTransactionCount;

  final double todayIn;
  final double todayOut;

  double get net => collected - expenses;

  /// Net as a share of collections, or null with nothing collected.
  int? get netPercent =>
      collected <= 0 ? null : (net / collected * 100).round();
}
