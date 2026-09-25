import 'package:intl/intl.dart';

/// Copy and number formatting for the Inventory screen.
abstract final class InventoryFormat {
  static final NumberFormat _rupees = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  static final NumberFormat _count = NumberFormat.decimalPattern('en_IN');

  /// "₹1,50,000" (Indian grouping, no paise).
  static String rupees(double amount) => _rupees.format(amount.round());

  static String count(int n) => _count.format(n);

  static String plural(int n, String one, [String? many]) =>
      '${count(n)} ${n == 1 ? one : (many ?? '${one}s')}';

  /// The stored unit as it reads after a number: "Strips" → "strips",
  /// and "strip" for one.
  static String unitFor(String unit, int qty) {
    final u = unit.trim().toLowerCase();
    if (u.isEmpty) return '';
    return qty == 1 ? singular(u) : u;
  }

  /// "strips" → "strip", "boxes" → "box", "pcs" → "pc".
  static String singular(String unit) {
    final u = unit.trim();
    final lower = u.toLowerCase();
    if (lower.endsWith('ss') || !lower.endsWith('s') || lower.length < 3) {
      return u;
    }
    for (final end in const ['ches', 'shes', 'xes', 'sses']) {
      if (lower.endsWith(end)) return u.substring(0, u.length - 2);
    }
    return u.substring(0, u.length - 1);
  }

  /// "12 strips".
  static String quantity(int qty, String unit) {
    final u = unitFor(unit, qty);
    return u.isEmpty ? count(qty) : '${count(qty)} $u';
  }

  /// The form is a GAP: the stored unit stands in its place ("Strips").
  static String form(String unit) {
    final u = unit.trim();
    if (u.isEmpty) return '';
    return u[0].toUpperCase() + u.substring(1);
  }

  /// "4 days", "5 weeks", "2 months". Days are rounded down (so the
  /// estimate never promises more stock than there is); weeks and
  /// months are rounded.
  static String span(double days) {
    final d = days.floor();
    if (d < 14) return plural(d < 1 ? 1 : d, 'day');
    if (days < 56) return plural((days / 7).round(), 'week');
    return plural((days / 30).round(), 'month');
  }

  /// List "Lasts" cell and panel: "about 4 days".
  static String lasts(double daysLeft, {required bool outOfStock}) {
    if (outOfStock) return 'Out of stock';
    if (daysLeft < 1) return 'less than a day';
    return 'about ${span(daysLeft)}';
  }

  /// Grid tile: "4 days left".
  static String left(double daysLeft, {required bool outOfStock}) {
    if (outOfStock) return 'Out of stock';
    if (daysLeft < 1) return 'Under a day left';
    return '${span(daysLeft)} left';
  }

  /// "Mar 2027".
  static String monthYear(DateTime d) => DateFormat('MMM y').format(d);

  /// "Oct", or "Oct 2027" outside the current year.
  static String month(DateTime d, DateTime now) =>
      d.year == now.year ? DateFormat('MMM').format(d) : monthYear(d);

  /// "Expires in Oct" (or "Expired").
  static String expiresIn(DateTime expiry, int daysToExpiry, DateTime now) =>
      daysToExpiry < 0 ? 'Expired' : 'Expires in ${month(expiry, now)}';

  /// Under the Next expiry date: "in 5 weeks".
  static String inTime(int days) {
    if (days < 0) return 'expired';
    if (days == 0) return 'today';
    if (days == 1) return 'tomorrow';
    if (days < 14) return 'in $days days';
    if (days < 56) return 'in ${plural((days / 7).round(), 'week')}';
    return 'in ${plural((days / 30).round(), 'month')}';
  }

  /// "Paracetamol, Gloves and Amoxicillin", "A, B, C and 2 more".
  static String names(List<String> names, {int max = 3}) {
    if (names.isEmpty) return '';
    if (names.length == 1) return names.first;
    if (names.length <= max) {
      return '${names.take(names.length - 1).join(', ')} and ${names.last}';
    }
    return '${names.take(max).join(', ')} and ${names.length - max} more';
  }

  /// Right of "Used in the last 2 weeks": "37 strips · about 3 a day".
  static String usageSummary(int total, int days, String unit) {
    if (total <= 0) return 'None used';
    final avg = total / days;
    final rate = avg >= 1
        ? 'about ${avg.round()} a day'
        : 'about ${(total * 7 / days).round().clamp(1, 7)} a week';
    return '${quantity(total, unit)} · $rate';
  }
}
