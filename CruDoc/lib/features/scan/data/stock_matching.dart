import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';

/// Finds the stocked medicine a bill line restocks. Names on bills and in
/// stock differ in case, punctuation and form words ("PAN-40 TAB" and
/// "Pan 40"), so both are reduced to their words and numbers first. The
/// numbers (strengths) must agree exactly: Dolo 500 never restocks Dolo
/// 650.
abstract final class StockMatching {
  static const _formWords = {
    'tab', 'tabs', 'tablet', 'tablets', 'cap', 'caps', 'capsule', //
    'capsules', 'syp', 'syr', 'syrup', 'susp', 'suspension', 'inj',
    'injection', 'oint', 'ointment', 'cream', 'gel', 'drop', 'drops',
    'sol', 'solution', 'lotion', 'mg', 'ml', 'gm', 'g', 'mcg',
  };

  static Set<String> _tokens(String name) => name
      .toLowerCase()
      // "40mg" → "40 mg", so the number stands alone.
      .replaceAllMapped(RegExp(r'(\d)([a-z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp(r'[^a-z0-9.]+'), ' ')
      .split(' ')
      .where((t) => t.isNotEmpty && t != '.' && !_formWords.contains(t))
      .toSet();

  static bool _isNumber(String t) => RegExp(r'^\d').hasMatch(t);

  /// 0 (nothing alike) to 1 (the same product).
  static double similarity(String a, String b) {
    final ta = _tokens(a);
    final tb = _tokens(b);
    if (ta.isEmpty || tb.isEmpty) return 0;
    final na = ta.where(_isNumber).toSet();
    final nb = tb.where(_isNumber).toSet();
    if (na.length != nb.length || !na.containsAll(nb)) return 0;
    final wa = ta.difference(na);
    final wb = tb.difference(nb);
    if (wa.isEmpty || wb.isEmpty) return 0;
    final shared = wa.intersection(wb).length;
    return shared / wa.union(wb).length;
  }

  /// The stocked medicine [name] restocks, or null for a new item.
  static MedicineModel? match(String name, List<MedicineModel> stock) {
    MedicineModel? best;
    var bestScore = 0.0;
    for (final m in stock) {
      if (!m.isActive) continue;
      final score = similarity(name, m.name);
      if (score > bestScore) {
        best = m;
        bestScore = score;
      }
    }
    return bestScore >= 0.75 ? best : null;
  }

  /// The closest stocked medicines, for choosing another match by hand:
  /// same strength first, then any sharing a word.
  static List<MedicineModel> closest(
    String name,
    List<MedicineModel> stock, {
    int limit = 6,
  }) {
    final words = _tokens(name).where((t) => !_isNumber(t)).toSet();
    double loose(MedicineModel m) {
      final other = _tokens(m.name).where((t) => !_isNumber(t)).toSet();
      if (words.isEmpty || other.isEmpty) return 0;
      return words.intersection(other).length / words.union(other).length;
    }

    final scored = [
      for (final m in stock)
        if (m.isActive) (m, 2 * similarity(name, m.name) + loose(m)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return [
      for (final (m, score) in scored)
        if (score > 0) m,
    ].take(limit).toList();
  }
}
