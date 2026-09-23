import 'dart:math' as math;

import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_models.dart';

/// Pure maths behind the Revenue Overview: period ranges, the
/// same-days comparison, chart buckets, the expense caption, pending
/// grouping and the transaction list. No Flutter, no repositories.
abstract final class RevenueBuilder {
  /// Transactions shown before "See all transactions".
  static const int collapsedRows = 6;

  /// A balance older than this many days reads amber.
  static const int overdueDays = 14;

  // ---------------------------------------------------------------------
  // Dates
  // ---------------------------------------------------------------------

  static DateTime day(DateTime t) => DateTime(t.year, t.month, t.day);

  static DateTime addDays(DateTime d, int n) =>
      DateTime(d.year, d.month, d.day + n);

  static int daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  /// Monday of the week containing [t].
  static DateTime weekStart(DateTime t) =>
      DateTime(t.year, t.month, t.day - (t.weekday - 1));

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Whole calendar days from [from] to [to].
  static int daysBetween(DateTime from, DateTime to) {
    final a = DateTime.utc(from.year, from.month, from.day);
    final b = DateTime.utc(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }

  /// The moment a transaction happened. Entries saved with a date only
  /// (midnight) fall back to their creation time on the same day.
  static DateTime when(RevenueEntry e) {
    final d = e.date;
    if (d.hour == 0 && d.minute == 0 && d.second == 0 && sameDay(d, e.createdAt)) {
      return e.createdAt;
    }
    return d;
  }

  // ---------------------------------------------------------------------
  // Periods
  // ---------------------------------------------------------------------

  static PeriodWindow window(RevenuePeriod period, DateTime now) {
    final today = day(now);
    final tomorrow = addDays(today, 1);
    switch (period) {
      case RevenuePeriod.today:
        final yesterday = addDays(today, -1);
        return PeriodWindow(
          period: period,
          full: DateSpan(today, tomorrow),
          toDate: DateSpan(today, tomorrow),
          previous: DateSpan(yesterday, today),
          today: today,
        );
      case RevenuePeriod.week:
        final ws = weekStart(today);
        final elapsed = daysBetween(ws, today) + 1;
        final prevStart = addDays(ws, -7);
        return PeriodWindow(
          period: period,
          full: DateSpan(ws, addDays(ws, 7)),
          toDate: DateSpan(ws, tomorrow),
          previous: DateSpan(prevStart, addDays(prevStart, elapsed)),
          today: today,
        );
      case RevenuePeriod.month:
        final ms = DateTime(today.year, today.month);
        final prevStart = DateTime(today.year, today.month - 1);
        final prevDays = daysInMonth(prevStart.year, prevStart.month);
        final n = math.min(today.day, prevDays);
        return PeriodWindow(
          period: period,
          full: DateSpan(ms, DateTime(today.year, today.month + 1)),
          toDate: DateSpan(ms, tomorrow),
          previous: DateSpan(
            prevStart,
            DateTime(prevStart.year, prevStart.month, n + 1),
          ),
          today: today,
        );
      case RevenuePeriod.year:
        final ys = DateTime(today.year);
        final py = today.year - 1;
        final n = math.min(today.day, daysInMonth(py, today.month));
        return PeriodWindow(
          period: period,
          full: DateSpan(ys, DateTime(today.year + 1)),
          toDate: DateSpan(ys, tomorrow),
          previous: DateSpan(DateTime(py), DateTime(py, today.month, n + 1)),
          today: today,
        );
    }
  }

  /// "23 September", "1 to 23 September", "31 August to 2 September".
  static String rangeText(DateTime first, DateTime last) {
    final dm = DateFormat('d MMMM');
    if (sameDay(first, last)) return dm.format(last);
    if (first.year == last.year && first.month == last.month) {
      return '${first.day} to ${dm.format(last)}';
    }
    return '${dm.format(first)} to ${dm.format(last)}';
  }

  /// The header subtitle for [w].
  static String subtitle(PeriodWindow w) {
    final first = w.toDate.start;
    final last = w.today;
    switch (w.period) {
      case RevenuePeriod.today:
        return DashFormat.dateLine(last);
      case RevenuePeriod.week:
        return 'This week · ${rangeText(first, last)}';
      case RevenuePeriod.month:
        return '${DateFormat('MMMM y').format(last)} · ${rangeText(first, last)}';
      case RevenuePeriod.year:
        return '${last.year} · ${rangeText(first, last)}';
    }
  }

  /// What the Collected caption compares against ("August, same days").
  static String comparisonLabel(PeriodWindow w) {
    switch (w.period) {
      case RevenuePeriod.today:
        return 'yesterday';
      case RevenuePeriod.week:
        return 'last week, same days';
      case RevenuePeriod.month:
        return '${DateFormat('MMMM').format(w.previous.start)}, same days';
      case RevenuePeriod.year:
        return '${w.previous.start.year}, same days';
    }
  }

  // ---------------------------------------------------------------------
  // Sums
  // ---------------------------------------------------------------------

  static double sum(
    Iterable<RevenueEntry> entries,
    DateSpan span,
    TransactionKind kind,
  ) {
    var total = 0.0;
    for (final e in entries) {
      if (e.isDeleted || e.kind != kind) continue;
      if (span.contains(when(e))) total += e.amount;
    }
    return total;
  }

  // ---------------------------------------------------------------------
  // Descriptions
  // ---------------------------------------------------------------------

  static final RegExp _trailingNote = RegExp(r'\s*\(([^()]*)\)\s*$');
  static final RegExp _titleWord = RegExp(r'^[A-Z][a-z]+$');

  /// Splits "Medical Supplies (Gloves, 1 box)" into its category and the
  /// note the Add Transaction form appends.
  static (String what, String? note) splitDescription(String raw) {
    final s = raw.trim();
    final m = _trailingNote.firstMatch(s);
    if (m == null) return (s, null);
    final what = s.substring(0, m.start).trim();
    final note = m.group(1)!.trim();
    if (what.isEmpty) return (s, null);
    return (what, note.isEmpty ? null : note);
  }

  /// Sentence case that leaves acronyms alone: "Clinic Rent" becomes
  /// "Clinic rent" (or "clinic rent" when [lowerFirst]), "HbA1c" stays.
  static String sentence(String s, {bool lowerFirst = false}) {
    final words = s.trim().split(RegExp(r'\s+'));
    final out = <String>[];
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      if (w.isEmpty) continue;
      if (i == 0 && !lowerFirst) {
        out.add(w[0].toUpperCase() + w.substring(1));
      } else if (_titleWord.hasMatch(w)) {
        out.add(w.toLowerCase());
      } else {
        out.add(w);
      }
    }
    return out.join(' ');
  }

  /// The top three expense descriptions by amount: "Rent, salary,
  /// supplies". Trailing " (note)" suffixes are dropped.
  static String expenseCaption(Iterable<RevenueEntry> entries, DateSpan span) {
    final totals = <String, double>{};
    final names = <String, String>{};
    for (final e in entries) {
      if (e.isDeleted || e.kind != TransactionKind.expense) continue;
      if (!span.contains(when(e))) continue;
      final (what, _) = splitDescription(e.description);
      if (what.isEmpty) continue;
      final key = what.toLowerCase();
      totals[key] = (totals[key] ?? 0) + e.amount;
      names.putIfAbsent(key, () => what);
    }
    if (totals.isEmpty) return 'No expenses yet';
    final keys = totals.keys.toList()
      ..sort((a, b) {
        final byAmount = totals[b]!.compareTo(totals[a]!);
        return byAmount != 0 ? byAmount : a.compareTo(b);
      });
    final top = keys.take(3).toList();
    return [
      for (var i = 0; i < top.length; i++)
        sentence(names[top[i]]!, lowerFirst: i > 0),
    ].join(', ');
  }

  // ---------------------------------------------------------------------
  // Chart
  // ---------------------------------------------------------------------

  /// y ticks from 0 in a 1 / 2 / 2.5 / 5 step, two to four intervals.
  static List<double> niceTicks(double max) {
    if (max <= 0) return const [0];
    final raw = max / 2;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final norm = raw / mag;
    final double step;
    if (norm >= 5) {
      step = 5 * mag;
    } else if (norm >= 2.5) {
      step = 2.5 * mag;
    } else if (norm >= 2) {
      step = 2 * mag;
    } else {
      step = mag;
    }
    final ticks = <double>[];
    for (var t = 0.0; t <= max + 1e-9; t += step) {
      ticks.add(t);
    }
    return ticks;
  }

  static Map<DateTime, double> _dailyIncome(Iterable<RevenueEntry> entries) {
    final out = <DateTime, double>{};
    for (final e in entries) {
      if (e.isDeleted || e.kind != TransactionKind.income) continue;
      final d = day(when(e));
      out[d] = (out[d] ?? 0) + e.amount;
    }
    return out;
  }

  static BarKind _kind(DateTime d, DateTime today, double amount) {
    if (sameDay(d, today)) return BarKind.today;
    if (d.isAfter(today)) return BarKind.future;
    return amount > 0 ? BarKind.past : BarKind.emptyPast;
  }

  static ChartData chart(
    Iterable<RevenueEntry> entries,
    PeriodWindow w,
  ) {
    final daily = _dailyIncome(entries);
    final today = w.today;
    final bars = <ChartBar>[];
    String todayLegend = 'Today';
    String? note;

    ChartBar dayBar(DateTime d, String? label) {
      // Days after today are never counted, even if something is
      // recorded ahead of time.
      final amount = d.isAfter(today) ? 0.0 : (daily[d] ?? 0);
      return ChartBar(
        date: d,
        amount: amount,
        kind: _kind(d, today, amount),
        label: label,
        semantic: '${DashFormat.dateLine(d)}: ${DashFormat.rupees(amount)}',
      );
    }

    switch (w.period) {
      case RevenuePeriod.today:
      case RevenuePeriod.week:
        // Today has one day of data; its chart shows the week around it.
        if (w.period == RevenuePeriod.today) note = 'This week';
        final ws = weekStart(today);
        for (var i = 0; i < 7; i++) {
          final d = addDays(ws, i);
          bars.add(dayBar(d, DateFormat('EEE').format(d)));
        }
      case RevenuePeriod.month:
        final n = daysInMonth(today.year, today.month);
        for (var i = 1; i <= n; i++) {
          final d = DateTime(today.year, today.month, i);
          final isToday = i == today.day;
          final regular = i == 1 || i % 7 == 0;
          // A regular label next to today's would collide with it.
          final label =
              isToday || (regular && (i - today.day).abs() != 1) ? '$i' : null;
          bars.add(dayBar(d, label));
        }
      case RevenuePeriod.year:
        todayLegend = 'This month';
        for (var m = 1; m <= 12; m++) {
          final start = DateTime(today.year, m);
          var amount = 0.0;
          if (!start.isAfter(today)) {
            daily.forEach((d, v) {
              if (d.year == today.year && d.month == m && !d.isAfter(today)) {
                amount += v;
              }
            });
          }
          final BarKind kind;
          if (m == today.month) {
            kind = BarKind.today;
          } else if (m > today.month) {
            kind = BarKind.future;
          } else {
            kind = amount > 0 ? BarKind.past : BarKind.emptyPast;
          }
          bars.add(ChartBar(
            date: start,
            amount: amount,
            kind: kind,
            label: DateFormat('MMM').format(start),
            semantic:
                '${DateFormat('MMMM y').format(start)}: ${DashFormat.rupees(amount)}',
          ));
        }
    }

    final max = bars.fold<double>(0, (m, b) => math.max(m, b.amount));
    final ticks = niceTicks(max);
    final todayBar = bars.where((b) => b.isToday);
    return ChartData(
      bars: bars,
      ticks: ticks,
      scaleMax: math.max(max, ticks.last) <= 0 ? 1.0 : math.max(max, ticks.last),
      todayAmount: todayBar.isEmpty ? 0 : todayBar.first.amount,
      todayLegend: todayLegend,
      note: note,
    );
  }

  // ---------------------------------------------------------------------
  // Transactions
  // ---------------------------------------------------------------------

  static String dayLabel(DateTime t, DateTime today) {
    final d = day(t);
    if (sameDay(d, today)) return 'Today';
    if (sameDay(d, addDays(today, -1))) return 'Yesterday';
    return DateFormat('EEE d MMM').format(d);
  }

  static String _typeLabel(RevenueType type) => switch (type) {
        RevenueType.visit => 'Visit',
        RevenueType.online => 'Online consultation',
        RevenueType.miscellaneous => 'Other income',
      };

  static TxnRow row(RevenueEntry e, DateTime today) {
    final t = when(e);
    final (time, meridiem) = DashFormat.timeParts(t);
    final out = e.kind == TransactionKind.expense;
    final payer = (e.payer ?? '').trim();
    final hasPayer = payer.isNotEmpty;
    final (what, note) = splitDescription(e.description);
    final whatText = what.isEmpty ? null : sentence(what);

    final String title;
    final String subtitle;
    if (out) {
      // Money out leads with the item bought, then who was paid.
      title = note ?? (hasPayer ? payer : (whatText ?? 'Expense'));
      subtitle = [
        if (whatText != null && title != whatText) whatText,
        if (hasPayer && title != payer) payer,
      ].join(' · ');
    } else {
      title = hasPayer ? payer : (whatText ?? _typeLabel(e.type));
      final what2 = e.description.trim();
      subtitle = hasPayer
          ? (what2.isEmpty ? _typeLabel(e.type) : what2)
          : _typeLabel(e.type);
    }
    final money = DashFormat.rupees(e.amount);
    return TxnRow(
      entry: e,
      moneyOut: out,
      dayLabel: dayLabel(t, today),
      time: time,
      meridiem: meridiem,
      title: title,
      subtitle: subtitle.isEmpty ? (out ? 'Expense' : 'Income') : subtitle,
      amount: out ? '−$money' : '+$money',
    );
  }

  static bool _passes(RevenueEntry e, TxnFilter f) => switch (f) {
        TxnFilter.all => true,
        TxnFilter.moneyIn => e.kind == TransactionKind.income,
        TxnFilter.moneyOut => e.kind == TransactionKind.expense,
      };

  static List<RevenueEntry> inSpan(
    Iterable<RevenueEntry> entries,
    DateSpan span,
  ) {
    final list = [
      for (final e in entries)
        if (!e.isDeleted && span.contains(when(e))) e,
    ]..sort((a, b) {
        final byTime = when(b).compareTo(when(a));
        return byTime != 0 ? byTime : b.createdAt.compareTo(a.createdAt);
      });
    return list;
  }

  // ---------------------------------------------------------------------
  // Overview
  // ---------------------------------------------------------------------

  static RevenueOverview overview({
    required List<RevenueEntry> entries,
    required RevenuePeriod period,
    required TxnFilter filter,
    required DateTime now,
  }) {
    final w = window(period, now);
    final collected = sum(entries, w.toDate, TransactionKind.income);
    final previous = sum(entries, w.previous, TransactionKind.income);
    final expenses = sum(entries, w.toDate, TransactionKind.expense);
    final todaySpan = DateSpan(w.today, addDays(w.today, 1));
    final inPeriod = inSpan(entries, w.toDate);
    return RevenueOverview(
      window: w,
      subtitle: subtitle(w),
      collected: collected,
      expenses: expenses,
      comparison: Comparison(current: collected, previous: previous),
      comparisonLabel: comparisonLabel(w),
      expenseCaption: expenseCaption(entries, w.toDate),
      chart: chart(entries, w),
      transactions: [
        for (final e in inPeriod)
          if (_passes(e, filter)) row(e, w.today),
      ],
      periodTransactionCount: inPeriod.length,
      todayIn: sum(entries, todaySpan, TransactionKind.income),
      todayOut: sum(entries, todaySpan, TransactionKind.expense),
    );
  }

  // ---------------------------------------------------------------------
  // Pending
  // ---------------------------------------------------------------------

  /// "today", "1 day", "17 days".
  static String age(int days) => days <= 0
      ? 'today'
      : days == 1
          ? '1 day'
          : '$days days';

  /// Unpaid balances grouped per patient (patientId, else payer),
  /// oldest first.
  static List<PendingGroup> pendingGroups(
    List<PendingPayment> pending,
    List<Patient> patients,
    DateTime now,
  ) {
    final byId = {for (final p in patients) p.id: p};
    final groups = <String, List<PendingPayment>>{};
    for (final p in pending) {
      if (p.isPaid || p.amount <= 0) continue;
      final payer = p.payer?.trim() ?? '';
      final key = p.patientId != null && p.patientId!.isNotEmpty
          ? 'patient:${p.patientId}'
          : payer.isNotEmpty
              ? 'payer:${payer.toLowerCase()}'
              : 'row:${p.id}';
      groups.putIfAbsent(key, () => []).add(p);
    }

    final today = day(now);
    final out = <PendingGroup>[];
    groups.forEach((key, rows) {
      rows.sort((a, b) => a.date.compareTo(b.date));
      final first = rows.first;
      final patient = first.patientId == null ? null : byId[first.patientId];
      final payer = rows
          .map((r) => r.payer?.trim() ?? '')
          .firstWhere((s) => s.isNotEmpty, orElse: () => '');
      final name = patient != null
          ? patient.fullName.trim()
          : payer.isNotEmpty
              ? payer
              : 'No name';
      final total = rows.fold<double>(0, (s, r) => s + r.amount);
      final ageDays = math.max(0, daysBetween(first.date, today));
      final on = DateFormat('d MMM').format(first.date);
      final String lead;
      if (rows.length == 1) {
        final (what, _) = splitDescription(first.description);
        lead = '${what.isEmpty ? 'Payment' : sentence(what)} on $on';
      } else {
        lead = '${rows.length} items since $on';
      }
      out.add(PendingGroup(
        key: key,
        name: name.isEmpty ? 'No name' : name,
        patient: patient,
        rows: List.unmodifiable(rows),
        total: total,
        oldest: first.date,
        ageDays: ageDays,
        detail: '$lead · ${age(ageDays)}',
      ));
    });
    out.sort((a, b) {
      final byDate = a.oldest.compareTo(b.oldest);
      return byDate != 0 ? byDate : a.name.compareTo(b.name);
    });
    return out;
  }
}
