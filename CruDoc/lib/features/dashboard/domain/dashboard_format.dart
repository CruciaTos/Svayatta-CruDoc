import 'package:intl/intl.dart';

/// Display formatting for the dashboard. Pure, so it's easy to test.
abstract final class DashFormat {
  static final NumberFormat _rupees =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  /// ₹21,300 (Indian grouping).
  static String rupees(double amount) => _rupees.format(amount.round());

  /// ₹950, ₹3.4k, ₹1.2L, ₹1.1Cr.
  static String rupeesCompact(double amount) {
    String trim(double v) {
      final s = v.toStringAsFixed(1);
      return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
    }

    // Pick the unit after rounding to one decimal, so ₹99,960 reads
    // "₹1L" rather than "₹100k".
    double r1(double v) => double.parse(v.toStringAsFixed(1));
    final a = amount.abs();
    if (a.round() < 1000) return rupees(amount);
    if (r1(a / 1000) < 100) return '₹${trim(amount / 1000)}k';
    if (r1(a / 100000) < 100) return '₹${trim(amount / 100000)}L';
    return '₹${trim(amount / 10000000)}Cr';
  }

  /// ("11:30", "AM").
  static (String, String) timeParts(DateTime t) =>
      (DateFormat('h:mm').format(t), DateFormat('a').format(t));

  /// 11:30 AM.
  static String time(DateTime t) => DateFormat('h:mm a').format(t);

  /// "9:30 AM to 6:10 PM", or "5:00 to 6:10 PM" within one half of the day.
  static String timeRange(DateTime a, DateTime b) {
    final (ha, pa) = timeParts(a);
    if (a.hour < 12 == b.hour < 12) return '$ha to ${time(b)}';
    return '$ha $pa to ${time(b)}';
  }

  /// Wednesday, 23 September.
  static String dateLine(DateTime t) => DateFormat('EEEE, d MMMM').format(t);

  /// 14 Aug.
  static String shortDate(DateTime t) => DateFormat('d MMM').format(t);

  static String weekday(DateTime t) => DateFormat('EEEE').format(t);

  /// Th, Fr, Sa…
  static String dayInitials(DateTime t) =>
      DateFormat('E').format(t).substring(0, 2);

  /// Good morning (< 12:00), Good afternoon (12–17), Good evening (≥ 17).
  static String greeting(DateTime t) {
    if (t.hour < 12) return 'Good morning';
    if (t.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// "Priya, Rahul, Fatima" or "Priya, Rahul, Fatima, Arjun and 7 more".
  static String names(List<String> names, {int max = 5}) {
    if (names.length <= max) return names.join(', ');
    final shown = names.take(max - 1).join(', ');
    return '$shown and ${names.length - (max - 1)} more';
  }

  static String minutes(int m) => '$m min';

  static String plural(int n, String one, [String? many]) =>
      '$n ${n == 1 ? one : (many ?? '${one}s')}';
}
