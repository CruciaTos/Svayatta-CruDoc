import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';

/// A supplier's purchase bill as tool/paddle_ocr_test/bill_scan.py read
/// it: the lines are as printed, quantities in packs.
class ScannedBill {
  const ScannedBill({
    required this.source,
    this.note,
    this.supplier,
    this.invoiceNumber,
    this.invoiceDate,
    this.subtotal,
    this.taxAmount,
    this.taxPercent,
    this.grandTotal,
    this.amountsIncludeTax,
    this.items = const [],
    this.lines = const [],
  });

  factory ScannedBill.fromJson(Map<String, dynamic> json) => ScannedBill(
    source: json['source'] as String? ?? 'paddle',
    note: _text(json['note']),
    supplier: _text(json['supplier']),
    invoiceNumber: _text(json['invoiceNumber']),
    invoiceDate: _text(json['invoiceDate']),
    subtotal: _number(json['subtotal']),
    taxAmount: _number(json['taxAmount']),
    taxPercent: _number(json['taxPercent']),
    grandTotal: _number(json['grandTotal']),
    amountsIncludeTax: switch (json['amountsIncludeTax']) {
      final bool b => b,
      'true' => true,
      'false' => false,
      _ => null,
    },
    items: [
      for (final item in json['items'] as List? ?? const [])
        if (item is Map) BillLine.fromJson(item.cast<String, dynamic>()),
    ],
    lines: [
      for (final line in json['lines'] as List? ?? const []) ?_text(line),
    ],
  );

  /// 'sarvam' (Sarvam Vision, online) or 'paddle' (PaddleOCR, offline).
  final String source;

  /// Why PaddleOCR read it ("no internet connection to Sarvam").
  final String? note;
  final String? supplier;
  final String? invoiceNumber;
  final String? invoiceDate;

  /// Taxable value after discounts, the GST on it, the GST rate when one
  /// rate covers the bill, and the amount payable.
  final double? subtotal;
  final double? taxAmount;
  final double? taxPercent;
  final double? grandTotal;

  /// Sarvam's reading of whether the rates and amounts printed already
  /// include GST (a chemist's retail cash memo); null when it didn't say.
  final bool? amountsIncludeTax;
  final List<BillLine> items;

  /// The bill's text row by row (PaddleOCR only).
  final List<String> lines;

  bool get readOffline => source != 'sarvam';
}

/// What identifies a bill: its supplier and invoice number (or, without a
/// number, its date and total), so the same bill isn't added twice. Null
/// when the bill doesn't say enough to tell.
String? billKeyOf(ScannedBill bill) {
  String squash(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final supplier = squash(bill.supplier ?? '');
  if (supplier.isEmpty) return null;
  final number = squash(bill.invoiceNumber ?? '');
  if (number.isNotEmpty) return '$supplier#$number';
  final date = squash(bill.invoiceDate ?? '');
  final total = bill.grandTotal;
  if (date.isNotEmpty && total != null) {
    return '$supplier@$date=${total.toStringAsFixed(2)}';
  }
  return null;
}

/// One product line of a bill, as printed.
class BillLine {
  const BillLine({
    required this.name,
    this.pack,
    this.batch,
    this.expiry,
    this.quantity,
    this.quantityUnit,
    this.freeQuantity,
    this.mrp,
    this.rate,
    this.discountPercent,
    this.taxPercent,
    this.amount,
  });

  factory BillLine.fromJson(Map<String, dynamic> json) => BillLine(
    name: _text(json['name']) ?? '',
    pack: _text(json['pack']),
    batch: _text(json['batch']),
    expiry: _text(json['expiry']),
    quantity: _number(json['quantity']),
    quantityUnit: _text(json['quantityUnit']),
    freeQuantity: _number(json['freeQuantity']),
    mrp: _number(json['mrp']),
    rate: _number(json['rate']),
    discountPercent: _number(json['discountPercent']),
    taxPercent: _number(json['taxPercent']),
    amount: _number(json['amount']),
  );

  final String name;
  final String? pack;
  final String? batch;
  final String? expiry;

  /// Packs billed, the unit printed with them ("TBS", "STRIP", "BTL"),
  /// and packs given free.
  final double? quantity;
  final String? quantityUnit;
  final double? freeQuantity;

  /// Per pack: the printed MRP and the purchase rate before discount and
  /// tax.
  final double? mrp;
  final double? rate;

  /// The line's discount and, when the table has the column, its GST.
  final double? discountPercent;
  final double? taxPercent;

  /// The amount column as printed: usually the taxable value after
  /// discount, sometimes the total with GST.
  final double? amount;
}

/// What one bill line really cost: rate less discount, with or without
/// GST.
class BillLineCost {
  const BillLineCost({
    required this.total,
    this.discountPercent,
    this.taxPercent,
    this.taxIncluded = false,
    this.taxRemoved = false,
  });

  /// The whole line, as counted in the inventory.
  final double total;
  final double? discountPercent;

  /// The GST rate in percent: added to [total] (GST counted), or taken
  /// out of it ([taxRemoved]). Null when none was found.
  final double? taxPercent;

  /// The amount printed already had GST in it, and it was left in.
  final bool taxIncluded;

  /// The amount printed had GST in it, and it was taken out.
  final bool taxRemoved;
}

/// The cost of every line of [bill], and whether they add up to its
/// total.
class BillCosting {
  const BillCosting({
    required this.lines,
    required this.itemsTotal,
    this.billTotal,
    this.includeTax = true,
    this.taxNotSeparable = false,
  });

  /// Per item of the bill, in order; null when the line has no price.
  final List<BillLineCost?> lines;

  /// What the priced lines come to.
  final double itemsTotal;

  /// The total the lines are checked against: the grand total with GST
  /// counted, the taxable value without. Null when the bill doesn't show
  /// it.
  final double? billTotal;

  /// Whether GST is counted as part of the cost.
  final bool includeTax;

  /// GST was not to be counted, but the prices include it and the bill
  /// doesn't show its rate: they were left as printed.
  final bool taxNotSeparable;

  /// The items add up to the bill's total, give or take ₹1 of rounding.
  /// True when there's no total to check against.
  bool get matchesBill =>
      billTotal == null || (itemsTotal - billTotal!).abs() <= 1;
}

/// The GST slabs; a rate worked out from totals must be one of them.
const _gstSlabs = [0.0, 0.1, 0.25, 1.5, 3.0, 5.0, 12.0, 18.0, 28.0];

double? _asSlab(double rate) {
  for (final slab in _gstSlabs) {
    if ((rate - slab).abs() <= 0.5) return slab;
  }
  return null;
}

/// Works out what each line of [bill] cost.
///
/// A line's value is its printed amount, else quantity × rate less the
/// discount. Whether that value already includes GST: the bill says so,
/// or an amount is clearly more than its discounted price, or the
/// amounts add up to the grand total by themselves (a chemist's cash
/// memo prints prices with GST in them).
///
/// With [includeTax], GST is part of the cost: added to values without
/// it (the line's rate, else the bill's, else worked out from its
/// totals), left in values with it; the lines are checked against the
/// grand total. Without, values without GST stay as they are, values
/// with it have it taken out when its rate is known; the lines are
/// checked against the taxable value. Lines within 3% of the total
/// (round-off, freight) are scaled to it exactly.
BillCosting costBill(ScannedBill bill, {bool includeTax = true}) {
  final bases = <(double, bool)?>[];
  for (final line in bill.items) {
    final qty = line.quantity;
    final rate = line.rate;
    final discount = line.discountPercent ?? 0;
    final discounted = qty != null && rate != null
        ? qty * rate * (1 - discount / 100)
        : null;
    final amount = line.amount;
    if (amount != null && amount > 0) {
      // An amount clearly over the discounted price already has the GST.
      final withTax = discounted != null && amount > discounted * 1.02;
      bases.add((amount, withTax));
    } else if (discounted != null && discounted > 0) {
      bases.add((discounted, false));
    } else {
      bases.add(null);
    }
  }
  final allPriced = bases.every((b) => b != null);
  final printedSum = bases.fold(0.0, (s, b) => s + (b?.$1 ?? 0));
  final grand = bill.grandTotal;

  // Prices with GST in them: they add up to the grand total by
  // themselves. The arithmetic decides when there's a total: Sarvam has
  // called a chemist's GST-inclusive memo "without GST". Its word counts
  // only when there's no total to check.
  final bool inclusive;
  if (grand != null && allPriced && printedSum > 0) {
    inclusive =
        !bases.any((b) => b!.$2) &&
        ((printedSum - grand).abs() <= 1 || _cutShort(grand, printedSum));
  } else {
    inclusive = bill.amountsIncludeTax ?? false;
  }

  // The bill's GST rate: as printed, else from its taxable value and tax.
  double? billRate = bill.taxPercent;
  final subtotal = bill.subtotal;
  if (billRate == null &&
      bill.taxAmount != null &&
      subtotal != null &&
      subtotal > 0) {
    billRate = _asSlab(bill.taxAmount! / subtotal * 100);
  }
  if (billRate == null &&
      subtotal != null &&
      subtotal > 0 &&
      grand != null &&
      grand >= subtotal) {
    billRate = _asSlab((grand / subtotal - 1) * 100);
  }
  // Prices without GST and a grand total: the rate the total implies
  // wins when the one read doesn't add up to it (Sarvam has read "5%"
  // off a bill mixing 5% and 18% items).
  if (!inclusive && grand != null) {
    var withTax = 0.0, without = 0.0, ownRate = 0.0;
    for (final (i, b) in bases.indexed) {
      if (b == null) continue;
      final own = bill.items[i].taxPercent;
      if (b.$2) {
        withTax += b.$1;
      } else if (own != null) {
        ownRate += b.$1 * (1 + own / 100);
      } else {
        without += b.$1;
      }
    }
    final implied = without > 0
        ? ((grand - withTax - ownRate) / without - 1) * 100
        : null;
    if (implied != null && implied >= -0.5 && implied <= 30) {
      final readAddsUp =
          billRate != null &&
          (without * (1 + billRate / 100) + withTax + ownRate - grand).abs() <=
              1;
      if (!readAddsUp) billRate = implied < 0.5 ? 0 : implied;
    }
  }

  var notSeparable = false;
  final lines = <BillLineCost?>[];
  for (final (i, b) in bases.indexed) {
    if (b == null) {
      lines.add(null);
      continue;
    }
    final item = bill.items[i];
    final (value, hasTax) = (b.$1, b.$2 || inclusive);
    final rate = item.taxPercent ?? billRate;
    if (hasTax) {
      if (includeTax || rate == null || rate == 0) {
        if (!includeTax && rate == null) notSeparable = true;
        lines.add(
          BillLineCost(
            total: value,
            discountPercent: item.discountPercent,
            taxPercent: rate,
            taxIncluded: true,
          ),
        );
      } else {
        lines.add(
          BillLineCost(
            total: value / (1 + rate / 100),
            discountPercent: item.discountPercent,
            taxPercent: rate,
            taxRemoved: true,
          ),
        );
      }
    } else {
      lines.add(
        BillLineCost(
          total: includeTax ? value * (1 + (rate ?? 0) / 100) : value,
          discountPercent: item.discountPercent,
          taxPercent: rate,
        ),
      );
    }
  }

  var total = lines.fold(0.0, (s, l) => s + (l?.total ?? 0));
  // What to check against: the grand total with GST, the taxable value
  // without (printed, or the grand total less one GST rate).
  double? target;
  if (includeTax || (inclusive && notSeparable)) {
    target = includeTax ? grand : null;
  } else if (subtotal != null && subtotal <= (grand ?? subtotal)) {
    target = subtotal;
  } else if (grand != null && billRate != null) {
    target = grand / (1 + billRate / 100);
  }
  // A total missing its last digit (torn off, smudged: "4092.7" for
  // ₹4,092.75) that the lines agree with: the lines are right.
  if (target != null && allPriced && _cutShort(target, total)) {
    target = total;
  }
  if (target != null && allPriced && total > 0) {
    final ratio = target / total;
    if (ratio != 1 && (ratio - 1).abs() <= 0.03) {
      for (final (i, l) in lines.indexed) {
        lines[i] = BillLineCost(
          total: l!.total * ratio,
          discountPercent: l.discountPercent,
          taxPercent: l.taxPercent,
          taxIncluded: l.taxIncluded,
          taxRemoved: l.taxRemoved,
        );
      }
      total = target;
    }
  }
  return BillCosting(
    lines: lines,
    itemsTotal: total,
    billTotal: target,
    includeTax: includeTax,
    taxNotSeparable: notSeparable,
  );
}

/// Whether [read] is [total] with its last digit lost: one decimal
/// place, and [total] cut to one place is [read] (4092.7 for 4092.75).
bool _cutShort(double read, double total) {
  final tenths = read * 10;
  if ((tenths - tenths.round()).abs() > 1e-6) return false;
  if ((read - total).abs() < 0.005) return false;
  return (total * 10 + 1e-6).floor() == tenths.round();
}

/// A bill line as an inventory item: counted in [unit]s, priced per unit.
class BillItemDraft {
  const BillItemDraft({
    required this.name,
    required this.unit,
    required this.stock,
    required this.perPack,
    this.perPackSure = true,
    this.unitPrice,
    this.unitCost,
    this.batch,
    this.expiry,
  });

  /// "DOLO 650 TAB", 15'S, 10 + 1 free, costing ₹270.10 in all →
  /// "Dolo 650", 165 Tablets at ₹1.64. Free packs share the cost.
  ///
  /// [perPack] overrides the units per pack read from the bill (the
  /// doctor corrected it). Without [cost] (a bill with no prices read),
  /// the rate per unit.
  factory BillItemDraft.fromLine(
    BillLine line, {
    BillLineCost? cost,
    int? perPack,
  }) {
    final unit = billUnit('${line.name} ${line.quantityUnit ?? ''}', line.pack);
    // "10 TBS" is already counted in tablets.
    final singles = RegExp(
      r'^(?:tbs|tbl|tabs?|tablets?|caps?|capsules?|nos|units?|pcs)$',
      caseSensitive: false,
    ).hasMatch(line.quantityUnit?.trim() ?? '');
    final pack = readPack(line.pack);
    final counted = countsPerPack(unit) && !singles;
    final perPackRead = counted ? pack.count : 1;
    final units = perPack != null && perPack > 0 ? perPack : perPackRead;
    final packs = (line.quantity ?? 0) + (line.freeQuantity ?? 0);
    final stock = (packs * units).round();
    final double? price;
    if (cost != null && stock > 0) {
      price = cost.total / stock;
    } else {
      final rate =
          line.rate ??
          (line.amount != null && (line.quantity ?? 0) > 0
              ? line.amount! / line.quantity!
              : null);
      price = rate == null ? null : rate / units;
    }
    return BillItemDraft(
      name: billItemName(line.name),
      unit: unit,
      stock: stock,
      perPack: units,
      // Counted by the strip or box but the pack doesn't say clearly how
      // many: worth a look.
      perPackSure: perPack != null || !counted || pack.sure,
      unitPrice: price == null || price <= 0
          ? null
          : (price * 100).roundToDouble() / 100,
      unitCost: price == null || price <= 0 ? null : price,
      batch: line.batch?.toUpperCase(),
      expiry: parseBillExpiry(line.expiry),
    );
  }

  final String name;
  final String unit;

  /// Units to add: (billed + free packs) × [perPack].
  final int stock;

  /// Units in one pack: 15 for a strip of 15 tablets, 1 for a tube.
  final int perPack;

  /// False when [perPack] is a guess: the pack is missing, unclear, or
  /// could be a box or a strip ("10x10").
  final bool perPackSure;

  /// What one unit cost, discount and GST included, to the paisa (for
  /// showing and typing over).
  final double? unitPrice;

  /// The same, unrounded: [stock] × [unitCost] is exactly what the line
  /// cost, so the items' value matches the bill's total to the paisa
  /// (₹241 / 165 tablets is ₹1.4606…, not ₹1.46).
  final double? unitCost;
  final String? batch;
  final DateTime? expiry;
}

// ─── Reading a bill line ──────────────────────────────────────────────────

/// The dosage form words bills put after a name, as the form's units.
const _units = [
  (r'\b(?:tabs?|tablets?|tbs|tbl)\b', 'Tablets'),
  (r'\b(?:caps?|capsules?)\b', 'Capsules'),
  (
    r'\b(?:syp|syrup|susp|suspension|liq|liquid|lotion|btl|bottles?)\b',
    'Bottles',
  ),
  (r'\b(?:inj|injection|amp|ampoules?)\b', 'Injections'),
  (r'\b(?:vials?)\b', 'Vials'),
  (r'\b(?:gel|cream|oint|ointment|tubes?)\b', 'Ointment'),
  (r'\b(?:drops?|e/d|eye drops?)\b', 'Drops'),
  (r'\b(?:sachets?|sach)\b', 'Sachets'),
  (r'\b(?:strips?)\b', 'Strips'),
];

/// The inventory unit for a bill line: from its name ("DOLO 650 TAB"),
/// else its pack ("100ML"), else 'Packs'.
String billUnit(String name, String? pack) {
  final text = '$name ${pack ?? ''}';
  for (final (pattern, unit) in _units) {
    if (RegExp(pattern, caseSensitive: false).hasMatch(text)) return unit;
  }
  // Pharmacy shorthand for the pack: "10T", "120T" tablets, "10C" capsules.
  final p = (pack ?? '').trim();
  if (RegExp(r'^\d+\s*t$', caseSensitive: false).hasMatch(p)) return 'Tablets';
  if (RegExp(r'^\d+\s*c$', caseSensitive: false).hasMatch(p)) {
    return 'Capsules';
  }
  if (RegExp(r'\d\s*ml\b', caseSensitive: false).hasMatch(p)) {
    return 'Bottles';
  }
  return 'Packs';
}

/// Units bought by the strip or box but counted one by one.
bool countsPerPack(String unit) =>
    const {'Tablets', 'Capsules', 'Sachets'}.contains(unit);

/// Units in a pack as bills print it: "15'S", "15S", "1x10", "10X10",
/// "10 TAB", "14T", "120T", "10C". 1 when it doesn't say.
///
/// Getting this right matters most when the same medicine comes in
/// different packs (a strip of 14 on one bill, a box of 120 on the next):
/// counted in tablets, both add up; counted in "packs", they can't.
int packCount(String? pack) => readPack(pack).count;

/// The units in a pack, and whether the pack says so plainly. "15'S",
/// "1x10", "14T" are plain. Unsure: no pack, one that can't be read, or
/// "10x10" (a box of 10 strips of 10: the quantity may count boxes or
/// strips).
({int count, bool sure}) readPack(String? pack) {
  final p = (pack ?? '').trim();
  final times = RegExp(
    r'(\d+)\s*[x×*]\s*(\d+)',
    caseSensitive: false,
  ).firstMatch(p);
  if (times != null) {
    final outer = int.parse(times[1]!), inner = int.parse(times[2]!);
    final n = outer * inner;
    if (n < 1 || n > 1000) return (count: 1, sure: false);
    return (count: n, sure: outer == 1);
  }
  final single = int.tryParse(
    RegExp(
          r"^(\d+)\s*(?:'?\s*s\b|t\b|c\b|tabs?\b|tablets?\b|caps?\b"
          r'|capsules?\b|$)',
          caseSensitive: false,
        ).firstMatch(p)?[1] ??
        '',
  );
  if (single == null || single < 1 || single > 1000) {
    return (count: 1, sure: false);
  }
  return (count: single, sure: true);
}

/// "DOLO 650 TAB" → "Dolo 650"; "PANTOCID 40MG TAB" → "Pantocid 40mg".
String billItemName(String printed) {
  final name = printed
      .replaceFirst(
        RegExp(
          r'\s+(?:tabs?|tablets?|caps?|capsules?|syp|syrup|inj|injection)\.?$',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
  return tidyCaps(name.isEmpty ? printed.trim() : name);
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// A bill's expiry ("03/28", "3-2028", "MAR-28", "2028-03") as the last
/// day of that month.
DateTime? parseBillExpiry(String? raw) {
  final t = (raw ?? '').trim().toLowerCase();
  int? month, year;
  if (RegExp(r'^(\d{4})[/\-.](\d{1,2})$').firstMatch(t) case final m?) {
    year = int.parse(m[1]!);
    month = int.parse(m[2]!);
  } else if (RegExp(r'^(\d{1,2})[/\-.\s](\d{2}|\d{4})$').firstMatch(t)
      case final m?) {
    month = int.parse(m[1]!);
    year = int.parse(m[2]!);
  } else if (RegExp(r'^([a-z]{3})[a-z]*[\s/\-.]*(\d{2}|\d{4})$').firstMatch(t)
      case final m?) {
    month = _months[m[1]!];
    year = int.parse(m[2]!);
  } else if (RegExp(
        r'^\d{1,2}[/\-.](\d{1,2})[/\-.](\d{2}|\d{4})$',
      ).firstMatch(t)
      case final m?) {
    month = int.parse(m[1]!);
    year = int.parse(m[2]!);
  }
  if (month == null || year == null || month < 1 || month > 12) return null;
  if (year < 100) year += 2000;
  return DateTime(year, month + 1, 0);
}

/// "MM/YY" for an expiry field.
String formatBillExpiry(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}/${(d.year % 100).toString().padLeft(2, '0')}';

/// "AMOXYCILLIN CAPSULES" → "Amoxycillin Capsules"; "40MG" → "40mg".
/// Mixed case is kept as typed.
String tidyCaps(String s) {
  if (s != s.toUpperCase()) return s;
  return s
      .split(' ')
      .map(
        (w) =>
            w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase(),
      )
      .join(' ')
      .replaceAllMapped(
        RegExp(r'(?<=\d\s?)(Mg|Mcg|Ml|Iu|Gm|G|Kg)\b'),
        (m) => m[1]!.toLowerCase(),
      );
}

// ─── Matching the inventory ───────────────────────────────────────────────

/// A name reduced for comparing: "Pantocid 40 mg Tab" and "PANTOCID 40MG"
/// both give "pantocid40".
String inventoryNameKey(String name) => name
    .toLowerCase()
    .replaceAll(
      RegExp(
        r'\b(?:tabs?|tablets?|caps?|capsules?|syp|syrup|inj|injection)\b\.?',
      ),
      ' ',
    )
    .replaceAllMapped(RegExp(r'(\d)\s*(?:mg|mcg|ml|gm|g|iu)\b'), (m) => m[1]!)
    .replaceAll(RegExp(r'[^a-z0-9]'), '');

/// An inventory item a bill line refers to. Not [exact]: the names are a
/// letter apart (a misread, or a different medicine): the doctor decides.
class InventoryMatch {
  const InventoryMatch(this.item, {required this.exact});

  final MedicineModel item;
  final bool exact;
}

/// The active inventory item [name], counted in [unit], refers to.
///
/// Only items counted in the same unit match: "Crocin 500" tablets and a
/// "Crocin 500" syrup stay apart. The same name matches exactly. Failing
/// that, one letter misread ("Gener 1mg" for Gemer, "Kenia St 25" for
/// Xenia) is a possible match: same strength, same length, the one
/// letter only, and a single such item.
InventoryMatch? matchInventoryItem(
  String name,
  String unit,
  List<MedicineModel> items,
) {
  final key = inventoryNameKey(name);
  if (key.isEmpty) return null;
  final sameUnit = items.where((m) => m.isActive && _sameUnit(m.unit, unit));
  for (final m in sameUnit) {
    if (inventoryNameKey(m.name) == key) return InventoryMatch(m, exact: true);
  }
  final near = [
    for (final m in sameUnit)
      if (_oneLetterOff(key, inventoryNameKey(m.name))) m,
  ];
  return near.length == 1 ? InventoryMatch(near.single, exact: false) : null;
}

/// Whether two lines of one bill are the same medicine: the same name
/// and unit. (Only exact: a misread within a bill is left to the doctor.)
bool sameMedicine(String a, String unitA, String b, String unitB) {
  final x = inventoryNameKey(a);
  return x.isNotEmpty && x == inventoryNameKey(b) && _sameUnit(unitA, unitB);
}

bool _sameUnit(String a, String b) =>
    a.trim().toLowerCase() == b.trim().toLowerCase();

/// Two name keys one letter apart: the same digits (strength) in the
/// same places, the same length, at least 5 letters, and exactly one
/// letter different. "Amlokind 5" and "Amlokind-AT 5" (a combination)
/// differ in length, so they never match.
bool _oneLetterOff(String a, String b) {
  if (a.length != b.length || a == b) return false;
  if (a.replaceAll(RegExp(r'[0-9]'), '').length < 5) return false;
  var differences = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] == b[i]) continue;
    final digit = RegExp(r'[0-9]');
    if (digit.hasMatch(a[i]) || digit.hasMatch(b[i])) return false;
    if (++differences > 1) return false;
  }
  return differences == 1;
}

String? _text(Object? v) {
  final t = v?.toString().trim() ?? '';
  return t.isEmpty || t.toLowerCase() == 'null' ? null : t;
}

double? _number(Object? v) => switch (v) {
  num() => v.toDouble(),
  String() => double.tryParse(v.replaceAll(RegExp(r'[^\d.]'), '')),
  _ => null,
};
