import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/data/repo/inventory_repository.dart';
import 'package:doctor_management_app/features/inventory/data/services/bill_scan_tool.dart';
import 'package:doctor_management_app/features/inventory/data/services/inventory_receipt_sync.dart';
import 'package:doctor_management_app/features/inventory/data/services/ocr_service.dart';
import 'package:doctor_management_app/features/inventory/domain/bill_import.dart';
import 'package:doctor_management_app/features/inventory/domain/stock_batches.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_style.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/patient_dialogs.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// What Add from bill did.
class BillReviewOutcome {
  const BillReviewOutcome({
    this.added = 0,
    this.restocked = 0,
    this.addByHand = false,
  });

  final int added;
  final int restocked;

  /// The bill couldn't be read; the doctor wants the blank form instead.
  final bool addByHand;
}

/// Add from bill: reads [image], a supplier's purchase bill, lists every
/// medicine on it for review and adds the ticked ones. Medicines already
/// in the inventory are restocked; the rest become new items. Every line
/// is kept as a purchase (batch, expiry, cost, supplier, bill), so the
/// same bill isn't added twice. Null when closed without adding.
Future<BillReviewOutcome?> showDesktopBillReviewDialog(
  BuildContext context, {
  required XFile image,
  required InventoryRepository repository,
}) {
  return showDialog<BillReviewOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        DesktopBillReviewDialog(image: image, repository: repository),
  );
}

class DesktopBillReviewDialog extends StatefulWidget {
  const DesktopBillReviewDialog({
    super.key,
    required this.image,
    required this.repository,
    this.scan = BillScanTool.scan,
  });

  final XFile image;
  final InventoryRepository repository;

  /// Reads the bill at a path ([BillScanTool.scan]; a fake in tests).
  final Future<ScannedBill> Function(String path) scan;

  @override
  State<DesktopBillReviewDialog> createState() =>
      _DesktopBillReviewDialogState();
}

enum _Phase { reading, ready, failed }

/// Whether bills' GST is counted as part of what stock cost; remembered.
const _includeGstKey = 'inventory.billCostIncludesGst';

/// One bill line being reviewed.
class _Row {
  _Row(this.line, BillItemDraft d, this.cost)
    : name = TextEditingController(text: d.name),
      unit = TextEditingController(text: d.unit),
      perPack = TextEditingController(text: '${d.perPack}'),
      stock = TextEditingController(text: '${d.stock}'),
      price = TextEditingController(),
      batch = TextEditingController(text: d.batch ?? ''),
      expiry = TextEditingController(
        text: d.expiry == null ? '' : formatBillExpiry(d.expiry!),
      ),
      category = OcrService.categoryOf(line.name),
      perPackSure = d.perPackSure {
    _showPrice(d);
  }

  final BillLine line;

  /// What the line cost in all, as counted (GST in or out).
  BillLineCost? cost;
  final String? category;
  final TextEditingController name;
  final TextEditingController unit;

  /// Units in one pack of the bill: tablets in a strip, a box…
  final TextEditingController perPack;
  final TextEditingController stock;
  final TextEditingController price;
  final TextEditingController batch;
  final TextEditingController expiry;

  /// The pack size was a guess when read.
  final bool perPackSure;
  bool selected = true;

  /// Not added to the item it's a letter away from ("Gener" / Gemer):
  /// the doctor said it's a different medicine.
  bool keepSeparate = false;

  /// The bill's exact cost per unit, and the field's text for it.
  double? _unitCost;
  String _priceShown = '';

  void _showPrice(BillItemDraft d) {
    _unitCost = d.unitCost;
    _priceShown = d.unitPrice == null ? '' : _money(d.unitPrice!);
    price.text = _priceShown;
  }

  /// The price to save: the exact cost while the field still shows it
  /// (so the bill's total is kept to the paisa), else what was typed.
  double? get unitPrice {
    final typed = price.text.trim();
    if (typed == _priceShown) return _unitCost;
    return double.tryParse(typed);
  }

  /// Units per pack, cost or GST changed: stock and price again. A price
  /// typed over is kept.
  void recount() {
    final n = int.tryParse(perPack.text.trim());
    if (n == null || n < 1) return;
    final typedPrice = price.text.trim() != _priceShown;
    final typed = price.text;
    final d = BillItemDraft.fromLine(line, cost: cost, perPack: n);
    stock.text = '${d.stock}';
    _showPrice(d);
    if (typedPrice) price.text = typed;
  }

  void dispose() {
    for (final c in [name, unit, perPack, stock, price, batch, expiry]) {
      c.dispose();
    }
  }
}

/// To the paisa, so 200 × 1.12 is 224, not 224.00000000000003.
double _paise(double v) => (v * 100).roundToDouble() / 100;

String _money(double v) {
  final p = _paise(v);
  return p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(2);
}

final _rupeeFormat = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 2,
);

/// "₹2,469.60", "₹45".
String _rupees(double v) {
  final p = _paise(v);
  final text = _rupeeFormat.format(p);
  return p == p.roundToDouble() ? text.replaceFirst('.00', '') : text;
}

/// "12%", "12.5%".
String _percent(double v) =>
    '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}%';

class _DesktopBillReviewDialogState extends State<DesktopBillReviewDialog> {
  final _formKey = GlobalKey<FormState>();

  _Phase _phase = _Phase.reading;
  ScannedBill? _bill;
  BillCosting? _costing;
  String? _failure;
  List<MedicineModel> _inventory = const [];
  List<_Row> _rows = [];

  /// Every row made, shown or not: their controllers are disposed only
  /// with the dialog, never while a field might still draw them.
  final _allRows = <_Row>[];

  /// GST counted as part of the cost (off when the clinic claims it back).
  bool _includeGst = true;

  int _seconds = 0;
  Timer? _clock;

  bool _dirty = false;
  bool _saving = false;
  bool _submitted = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _read(first: true);
  }

  @override
  void dispose() {
    _clock?.cancel();
    for (final r in _allRows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<bool> _savedIncludeGst() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_includeGstKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> _read({bool first = false}) async {
    void reset() {
      _phase = _Phase.reading;
      _failure = null;
      _seconds = 0;
    }

    first ? reset() : setState(reset);
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
    final inventory = widget.repository.watchMedicines().first.catchError(
      (Object _) => <MedicineModel>[],
    );
    try {
      final bill = await widget.scan(widget.image.path);
      final items = await inventory;
      final includeGst = await _savedIncludeGst();
      // Already in the inventory? (Can't tell: carry on.)
      final key = billKeyOf(bill);
      var earlier = const <StockTransactionModel>[];
      if (key != null) {
        try {
          earlier = await widget.repository.getPurchases(billKey: key);
        } catch (e) {
          debugPrint('[Add from bill] earlier purchases: $e');
        }
      }
      if (!mounted) return;
      final costing = costBill(bill, includeTax: includeGst);
      setState(() {
        _bill = bill;
        _costing = costing;
        _includeGst = includeGst;
        _inventory = [...items];
        _rows = [
          for (final (i, line) in bill.items.indexed)
            if (line.name.isNotEmpty)
              _Row(
                line,
                BillItemDraft.fromLine(line, cost: costing.lines[i]),
                costing.lines[i],
              ),
        ];
        _allRows.addAll(_rows);
        _phase = _rows.isEmpty ? _Phase.failed : _Phase.ready;
        if (_rows.isEmpty) {
          _failure = 'No medicines found on this bill.';
        }
      });
      _clock?.cancel();
      if (earlier.isNotEmpty && _rows.isNotEmpty) {
        await _warnAlreadyAdded(bill, earlier);
      }
    } on OcrSetupException catch (e) {
      _fail(e.message);
    } catch (e) {
      debugPrint('[Add from bill] $e');
      _fail("Couldn't read this bill.");
    } finally {
      _clock?.cancel();
    }
  }

  /// This bill is in the inventory already: say when, and close unless
  /// the doctor really means to add it again.
  Future<void> _warnAlreadyAdded(
    ScannedBill bill,
    List<StockTransactionModel> earlier,
  ) async {
    final c = context.cru;
    final when = earlier.first.createdAt;
    final lines = earlier.length;
    final again = await showDialog<bool>(
      context: context,
      builder: (ctx) => PatientDialog(
        title: 'This bill is already in your inventory',
        body: Text(
          '${bill.invoiceNumber == null ? 'This bill' : 'Bill ${bill.invoiceNumber}'}'
          '${_supplier() == null ? '' : ' from ${_supplier()}'} was added on '
          '${DateFormat('d MMM y').format(when)} '
          '($lines ${lines == 1 ? 'line' : 'lines'}). Adding it again '
          'would count its stock twice.',
          style: CruType.text.tint(c.label2),
        ),
        cancelLabel: 'Close',
        confirmLabel: 'Add it again',
        onConfirm: () => Navigator.of(ctx).pop(true),
      ),
    );
    if (again != true && mounted) Navigator.of(context).pop();
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.failed;
      _failure = message;
    });
  }

  void _edited([Object? _]) => setState(() {
    _dirty = true;
    _notice = null;
  });

  /// GST in or out of the cost: every line's cost again, remembered.
  void _setIncludeGst(bool include) {
    final bill = _bill;
    if (bill == null || include == _includeGst) return;
    final costing = costBill(bill, includeTax: include);
    setState(() {
      _includeGst = include;
      _costing = costing;
      for (final row in _rows) {
        final i = bill.items.indexOf(row.line);
        row.cost = i < 0 ? null : costing.lines[i];
        row.recount();
      }
    });
    unawaited(
      SharedPreferences.getInstance()
          .then((p) => p.setBool(_includeGstKey, include))
          .catchError((Object _) => false),
    );
  }

  InventoryMatch? _matchOf(_Row r) {
    final m = matchInventoryItem(
      r.name.text.trim(),
      r.unit.text.trim(),
      _inventory,
    );
    if (m == null || (!m.exact && r.keepSeparate)) return null;
    return m;
  }

  /// The name on an earlier ticked line of the same new medicine, which
  /// [r] then adds to instead of making a second item.
  String? _joinsAbove(_Row r) {
    if (_matchOf(r) != null) return null;
    final name = r.name.text.trim(), unit = r.unit.text.trim();
    for (final earlier in _rows.takeWhile((e) => e != r)) {
      if (!earlier.selected || _matchOf(earlier) != null) continue;
      final other = earlier.name.text.trim();
      if (sameMedicine(name, unit, other, earlier.unit.text.trim())) {
        return other;
      }
    }
    return null;
  }

  int get _selectedCount => _rows.where((r) => r.selected).length;

  String? _supplier() {
    final s = _bill?.supplier;
    return s == null ? null : tidyCaps(s);
  }

  // ── Saving ──────────────────────────────────────────────────────────

  Future<void> _submit() async {
    switch (_phase) {
      case _Phase.reading:
        return;
      case _Phase.failed:
        Navigator.of(context).pop(const BillReviewOutcome(addByHand: true));
        return;
      case _Phase.ready:
        break;
    }
    if (_saving) return;
    if (_selectedCount == 0) {
      setState(() => _notice = 'Tick at least one medicine to add.');
      return;
    }
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _notice = null;
    });

    final bill = _bill!;
    final supplier = _supplier();
    final key = billKeyOf(bill);
    final note = [
      if (bill.invoiceNumber != null) 'Bill ${bill.invoiceNumber}',
      ?supplier,
    ].join(' · ');
    var added = 0, restocked = 0;
    final failed = <String>[];
    final saved = <_Row>{};
    for (final row in [..._rows.where((r) => r.selected)]) {
      final name = row.name.text.trim();
      try {
        final (created, item) = await _saveRow(row, supplier, note, key);
        created ? added++ : restocked++;
        saved.add(row);
        // A later line of the same medicine adds to this one.
        _inventory = [..._inventory.where((m) => m.id != item.id), item];
      } catch (e) {
        debugPrint('[Add from bill] $name: $e');
        failed.add(name);
      }
    }
    if (!mounted) return;
    if (failed.isEmpty) {
      // The rows' fields stay alive while the dialog animates away; they
      // are let go in dispose().
      Navigator.of(
        context,
      ).pop(BillReviewOutcome(added: added, restocked: restocked));
      return;
    }
    setState(() {
      // Saved lines leave the list, so trying again doesn't add them twice.
      _rows = [..._rows.where((r) => !saved.contains(r))];
      _saving = false;
      final done = added + restocked;
      _notice =
          "Couldn't save ${failed.join(', ')}."
          '${done > 0 ? ' The other $done were added.' : ''} Try again.';
    });
  }

  /// Adds [row] as a purchase: to the item it matches, else to a new
  /// item. The item then shows the batch to use first, and costs what
  /// its batches in stock cost on average. Whether it was created, and
  /// the item as it now stands.
  Future<(bool, MedicineModel)> _saveRow(
    _Row row,
    String? supplier,
    String note,
    String? billKey,
  ) async {
    final repo = widget.repository;
    final name = row.name.text.trim();
    final unit = row.unit.text.trim();
    final stock = int.tryParse(row.stock.text.trim()) ?? 0;
    final price = row.unitPrice;
    final batch = row.batch.text.trim().toUpperCase();
    final expiry = parseBillExpiry(row.expiry.text);
    final match = _matchOf(row)?.item;

    final now = DateTime.now();
    var item =
        match ??
        MedicineModel(
          id: '',
          name: name,
          category: row.category ?? '',
          unit: unit,
          unitPrice: price,
          supplierName: supplier,
          batchNumber: batch.isEmpty ? null : batch,
          expiryDate: expiry,
          createdAt: now,
          updatedAt: now,
        );
    if (match == null) {
      final id = await repo.createMedicine(item);
      item = MedicineModel.fromJson({
        ...item.toJson(),
        'id': id,
      }).copyWith(unitPrice: price);
      // The bill photo goes to the cloud in the background.
      unawaited(
        InventoryReceiptSync.enqueueReceipt(
          medicineId: id,
          image: widget.image,
        ),
      );
    }

    if (stock > 0) {
      await repo.recordTransaction(
        medicineId: item.id,
        type: StockTransactionType.restock,
        quantity: stock,
        note: note.isEmpty ? 'Added from a bill' : note,
        batchNumber: batch.isEmpty ? null : batch,
        expiryDate: expiry,
        unitCost: price,
        supplierName: supplier,
        billKey: billKey,
      );
      item = item.copyWith(currentStock: item.currentStock + stock);
    }

    // The batches now in stock: the item shows the one to use first, and
    // costs what they cost on average.
    List<StockTransactionModel> purchases;
    try {
      purchases = await repo.getTransactionsForMedicine(item.id);
    } catch (_) {
      purchases = const [];
    }
    final batches = remainingBatches(item, purchases);
    final first = batches.isEmpty ? null : batches.first;
    final cost = averageCost(batches) ?? price;
    final changes = <String, dynamic>{
      'unitPrice': ?cost,
      'supplierName': ?supplier,
      'expiryDate': ?first?.expiry,
      'batchNumber': ?first?.batch,
    };
    if (changes.isNotEmpty) await repo.updateMedicine(item.id, changes);
    return (
      match == null,
      item.copyWith(
        unitPrice: cost,
        supplierName: supplier,
        expiryDate: first?.expiry,
        batchNumber: first?.batch,
      ),
    );
  }

  // ── Layout ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bill = _bill;
    final n = _selectedCount;
    return CruFormDialog(
      width: InventorySize.billReviewDialog,
      title: 'Add from bill',
      subtitle: switch (_phase) {
        _Phase.ready => switch ([
          ?_supplier(),
          if (bill?.invoiceNumber != null) 'Invoice ${bill!.invoiceNumber}',
          ?bill?.invoiceDate,
        ].join(' · ')) {
          '' => null,
          final s => s,
        },
        _ => widget.image.name,
      },
      leading: const CruIconTile(
        icon: CruIcons.fileText,
        tone: CruTileTone.neutral,
      ),
      submitLabel: switch (_phase) {
        _Phase.failed => 'Add by hand',
        _Phase.ready when n > 0 => 'Add $n ${n == 1 ? 'item' : 'items'}',
        _ => 'Add items',
      },
      onSubmit: _submit,
      busy: _saving,
      dirty: _dirty,
      notice:
          _notice ?? (_phase == _Phase.ready ? _readingNotice(bill!) : null),
      footerHint: _phase == _Phase.ready
          ? 'Read by ${bill!.readOffline ? 'PaddleOCR' : 'Sarvam Vision'}'
                ' · Ctrl + Enter to add'
          : null,
      body: switch (_phase) {
        _Phase.reading => _Reading(seconds: _seconds),
        _Phase.failed => _Failed(message: _failure!, onRetry: () => _read()),
        _Phase.ready => Form(
          key: _formKey,
          autovalidateMode: _submitted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: _list(context),
        ),
      },
    );
  }

  /// The lines don't add up to the bill's total, GST couldn't be taken
  /// out, or it was read offline.
  String? _readingNotice(ScannedBill bill) {
    final costing = _costing;
    if (costing != null && costing.taxNotSeparable) {
      return "This bill's prices include GST but don't show its rate, so "
          "they're kept with GST in them.";
    }
    if (costing != null && !costing.matchesBill) {
      return 'These lines come to ${_rupees(costing.itemsTotal)}, but the '
          "bill's ${costing.includeTax ? 'total' : 'taxable value'} is "
          '${_rupees(costing.billTotal!)}. A line may be missing or '
          'misread: check them against the bill.';
    }
    if (bill.readOffline) {
      return 'Read offline with PaddleOCR'
          '${bill.note == null ? '' : ' (${bill.note})'}. '
          'Check each line against the bill.';
    }
    return null;
  }

  Widget _list(BuildContext context) {
    final c = context.cru;
    final inStock = _rows.where((r) => _matchOf(r) != null).length;
    // Stock before each line, counting the ticked lines above it that add
    // to the same item (Axcer 120 → 134, then 134 → 148…).
    final running = <String, int>{};
    final before = <_Row, int>{};
    for (final row in _rows) {
      final m = _matchOf(row)?.item;
      if (m == null) continue;
      final start = running[m.id] ?? m.currentStock;
      before[row] = start;
      if (row.selected) {
        running[m.id] = start + (int.tryParse(row.stock.text.trim()) ?? 0);
      }
    }
    final costing = _costing;
    final what = _includeGst ? "the bill's total" : "the bill's taxable value";
    final total = costing == null || costing.itemsTotal <= 0
        ? null
        : costing.billTotal != null && costing.matchesBill
        ? 'They come to ${_rupees(costing.itemsTotal)}, $what.'
        : 'They come to ${_rupees(costing.itemsTotal)}.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_rows.length} ${_rows.length == 1 ? 'line' : 'lines'} '
                  'on this bill. ${total ?? ''} ${switch (inStock) {
                    0 => 'All are new to your inventory.',
                    _ when inStock == _rows.length => 'All are in your inventory already and get restocked.',
                    1 => '1 is in your inventory already and gets restocked; the others become new items.',
                    _ => '$inStock are in your inventory already and get restocked; the others become new items.',
                  }} Unit prices are after discount${_includeGst ? ', with GST' : ', without GST'}.',
                  style: CruType.caption.tabular.tint(c.label2),
                ),
              ),
              const SizedBox(width: CruSpace.s16),
              CruSegmentedControl<bool>(
                segments: const [
                  CruSegment(true, 'With GST'),
                  CruSegment(false, 'Without GST'),
                ],
                selected: _includeGst,
                onChanged: _saving ? (_) {} : _setIncludeGst,
                semanticLabel: 'Count GST in the cost',
              ),
            ],
          ),
        ),
        for (final (i, row) in _rows.indexed) ...[
          if (i > 0) const CruSeparator(),
          _BillRowView(
            row: row,
            match: matchInventoryItem(
              row.name.text.trim(),
              row.unit.text.trim(),
              _inventory,
            ),
            stockBefore: before[row],
            joins: _joinsAbove(row),
            enabled: !_saving,
            onToggle: (v) {
              row.selected = v;
              _edited();
            },
            onKeepSeparate: (v) {
              row.keepSeparate = v;
              _edited();
            },
            onPerPack: (_) {
              row.recount();
              _edited();
            },
            onChanged: _edited,
          ),
        ],
      ],
    );
  }
}

class _BillRowView extends StatelessWidget {
  const _BillRowView({
    required this.row,
    required this.match,
    required this.stockBefore,
    required this.joins,
    required this.enabled,
    required this.onToggle,
    required this.onKeepSeparate,
    required this.onPerPack,
    required this.onChanged,
  });

  final _Row row;

  /// The inventory item this line matches, before "Keep separate".
  final InventoryMatch? match;

  /// The same medicine's name on an earlier line of this bill, which this
  /// line adds to.
  final String? joins;

  /// [match]'s stock once the lines above have been added.
  final int? stockBefore;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final ValueChanged<bool> onKeepSeparate;
  final ValueChanged<String> onPerPack;
  final ValueChanged<String> onChanged;

  String? _required(String? v, String message) =>
      row.selected && (v == null || v.trim().isEmpty) ? message : null;

  String? _count(String? v, {int min = 0}) {
    if (!row.selected) return null;
    final n = int.tryParse(v?.trim() ?? '');
    return n == null || n < min ? 'A whole number.' : null;
  }

  String? _price(String? v) {
    final t = v?.trim() ?? '';
    if (!row.selected || t.isEmpty) return null;
    final d = double.tryParse(t);
    return d == null || d < 0 ? 'Like 12.50.' : null;
  }

  String? _expiry(String? v) {
    final t = v?.trim() ?? '';
    if (!row.selected || t.isEmpty) return null;
    return parseBillExpiry(t) == null ? 'Use MM/YY.' : null;
  }

  /// The bill's line and what it cost: "Paracetamol 500 mg · 10 TBS ×
  /// ₹40 − 10% + 12% GST = ₹403.20 · MRP ₹50".
  String get _printed {
    final l = row.line;
    final cost = row.cost;
    final free = (l.freeQuantity ?? 0) > 0
        ? ' + ${_money(l.freeQuantity!)} free'
        : '';
    final qty = l.quantity == null
        ? null
        : '${_money(l.quantity!)}'
              '${l.quantityUnit == null ? '' : ' ${l.quantityUnit}'}$free';
    final price = [
      if (qty != null && l.rate != null) '$qty × ${_rupees(l.rate!)}' else ?qty,
      if ((cost?.discountPercent ?? 0) > 0)
        '− ${_percent(cost!.discountPercent!)}',
      if (cost?.taxRemoved ?? false)
        '− ${_percent(cost!.taxPercent!)} GST taken out'
      else if (cost?.taxIncluded ?? false)
        'with GST'
      else if ((cost?.taxPercent ?? 0) > 0)
        '+ ${_percent(cost!.taxPercent!)} GST',
      if (cost != null) '= ${_rupees(cost.total)}',
    ].join(' ');
    return [
      l.name,
      ?l.pack,
      if (price.isNotEmpty) price,
      if (l.mrp != null) 'MRP ${_rupees(l.mrp!)}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final found = match;
    final m = found != null && !(row.keepSeparate && !found.exact)
        ? found.item
        : null;
    final add = int.tryParse(row.stock.text.trim()) ?? 0;
    final from = stockBefore ?? m?.currentStock ?? 0;
    final active = enabled && row.selected;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // Level with the fields' boxes, under their labels.
            padding: const EdgeInsets.only(top: CruSpace.s24),
            child: Checkbox(
              value: row.selected,
              onChanged: enabled ? (v) => onToggle(v ?? false) : null,
              activeColor: c.accent,
              checkColor: c.onAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              side: BorderSide(color: c.separator, width: 1.5),
            ),
          ),
          const SizedBox(width: CruSpace.s8),
          Expanded(
            child: AnimatedOpacity(
              opacity: row.selected ? 1 : 0.45,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CruFieldRow(
                    flex: const [4, 2, 2, 2, 2, 2, 2],
                    children: [
                      CruTextField(
                        label: 'Name',
                        controller: row.name,
                        enabled: active,
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => _required(v, 'Add a name.'),
                        onChanged: onChanged,
                      ),
                      CruTextField(
                        label: 'Unit',
                        controller: row.unit,
                        enabled: active,
                        validator: (v) => _required(v, 'Add a unit.'),
                        onChanged: onChanged,
                      ),
                      CruTextField(
                        label: 'Per pack',
                        controller: row.perPack,
                        enabled: active,
                        tabular: true,
                        // A guessed pack size: a box of 10 strips, or
                        // one strip?
                        help: row.perPackSure ? null : 'Check this',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (v) => _count(v, min: 1),
                        onChanged: onPerPack,
                      ),
                      CruTextField(
                        label: m == null && joins == null
                            ? 'In stock'
                            : 'Add to stock',
                        controller: row.stock,
                        enabled: active,
                        tabular: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: _count,
                        onChanged: onChanged,
                      ),
                      CruTextField(
                        label: 'Unit price',
                        optional: true,
                        controller: row.price,
                        enabled: active,
                        prefix: '₹',
                        tabular: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _price,
                        onChanged: onChanged,
                      ),
                      CruTextField(
                        label: 'Batch',
                        optional: true,
                        controller: row.batch,
                        enabled: active,
                        textCapitalization: TextCapitalization.characters,
                        onChanged: onChanged,
                      ),
                      CruTextField(
                        label: 'Expiry',
                        optional: true,
                        controller: row.expiry,
                        enabled: active,
                        hint: 'MM/YY',
                        tabular: true,
                        validator: _expiry,
                        onChanged: onChanged,
                      ),
                    ],
                  ),
                  const SizedBox(height: CruSpace.s8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _printed,
                          style: CruType.caption.tabular.tint(c.label3),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: CruSpace.s12),
                      CruPill(
                        text: switch ((m, joins)) {
                          (_?, _) when found!.exact =>
                            'In stock $from → ${from + add}',
                          // A letter apart: say which item, so a different
                          // medicine can be kept apart.
                          (final m?, _) =>
                            'Same as ${m.name}? $from → ${from + add}',
                          (null, final above?) => 'Adds to $above above',
                          _ => 'New item',
                        },
                        background: c.inset,
                        foreground: c.label2,
                      ),
                      if (found != null && !found.exact) ...[
                        const SizedBox(width: CruSpace.s8),
                        CruCapsuleButton(
                          label: row.keepSeparate
                              ? 'Add to ${found.item.name}'
                              : 'Keep separate',
                          kind: CruCapsuleKind.surface,
                          onPressed: active
                              ? () => onKeepSeparate(!row.keepSeparate)
                              : null,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s32),
      child: Column(
        children: [
          SizedBox.square(
            dimension: CruSpace.s24,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.label3),
          ),
          const SizedBox(height: CruSpace.s16),
          Text(
            'Reading the bill… ${seconds}s',
            style: CruType.row.tabular.tint(c.label),
          ),
          const SizedBox(height: CruSpace.s4),
          Text(
            'Sarvam Vision reads most bills in about 10 seconds. Without '
            'internet, PaddleOCR reads it on this computer, which takes up '
            'to a minute.',
            textAlign: TextAlign.center,
            style: CruType.caption.tint(c.label2),
          ),
        ],
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s24),
      child: Column(
        children: [
          Text(message, style: CruType.row.tint(c.label)),
          const SizedBox(height: CruSpace.s4),
          Text(
            'Try a sharper, straight-on photo of the whole bill, or add the '
            'items by hand.',
            textAlign: TextAlign.center,
            style: CruType.caption.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s16),
          CruCapsuleButton(
            label: 'Try again',
            kind: CruCapsuleKind.surface,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
