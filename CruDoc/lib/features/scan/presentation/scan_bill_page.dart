import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/inventory/data/services/inventory_receipt_sync.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_add_transaction_dialog.dart';
import 'package:doctor_management_app/features/scan/data/scan_capture.dart';
import 'package:doctor_management_app/features/scan/data/scan_reader.dart';
import 'package:doctor_management_app/features/scan/data/stock_matching.dart';
import 'package:doctor_management_app/features/scan/presentation/scan_flow.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

final _money = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 2,
);
final _expiry = DateFormat('MM/yyyy');

/// One bill line on its way into stock: restocking [match], or a new
/// item when there is none.
class _Line {
  _Line(this.item, this.match);

  final BillItem item;
  MedicineModel? match;
  bool include = true;
}

/// A supplier's bill, read by the AI the way a person reads it (whatever
/// the columns are called), turned into stock. Lines that name something
/// already stocked restock it; the rest become new items. Each item keeps
/// the bill page it came from as its receipt.
class ScanBillPage extends ConsumerStatefulWidget {
  const ScanBillPage({super.key, required this.pages, required this.revenue});

  final List<ScannedPage> pages;

  /// The revenue module is on: offer to record the bill as an expense.
  final bool revenue;

  @override
  ConsumerState<ScanBillPage> createState() => _ScanBillPageState();
}

class _ScanBillPageState extends ConsumerState<ScanBillPage> {
  final _reader = ScanReader();

  ScannedBill? _bill;
  String? _error;
  List<_Line> _lines = const [];
  List<MedicineModel> _stock = const [];
  bool _saving = false;
  bool _expense = false;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    setState(() {
      _error = null;
      _bill = null;
    });
    try {
      final results = await Future.wait([
        _reader.readBill(widget.pages),
        ref
            .read(medicinesStreamProvider.future)
            .timeout(
              const Duration(seconds: 6),
              onTimeout: () => const <MedicineModel>[],
            ),
      ]);
      final bill = results[0] as ScannedBill;
      final stock = results[1] as List<MedicineModel>;
      if (!mounted) return;
      setState(() {
        _bill = bill;
        _stock = stock;
        _lines = [
          for (final item in bill.items)
            _Line(item, StockMatching.match(item.name, stock)),
        ];
        _expense = widget.revenue && bill.total != null;
      });
    } on ScanReadException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  String _details(BillItem it) {
    final unit = it.quantity == 1 ? it.unit : '${it.unit}s';
    return [
      '${it.quantity} $unit${it.freeQuantity > 0 ? ' + ${it.freeQuantity} free' : ''}',
      if (it.batchNumber.isNotEmpty) 'Batch ${it.batchNumber}',
      if (it.expiryDate != null) 'Exp ${_expiry.format(it.expiryDate!)}',
      if (it.unitPrice != null) '${_money.format(it.unitPrice)} each',
    ].join(' · ');
  }

  Future<void> _edit(_Line line) async {
    final changed = await showModalBottomSheet<bool>(
      context: mobileRoot(context),
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (_) => _LineEditor(line: line, stock: _stock),
    );
    if (changed == true && mounted) setState(() {});
  }

  Future<void> _save() async {
    final bill = _bill;
    if (bill == null || _saving) return;
    final lines = _lines.where((l) => l.include).toList();
    if (lines.isEmpty) {
      mobileSay(context, 'Choose at least one item to add.');
      return;
    }
    setState(() => _saving = true);
    final root = mobileRoot(context);
    final repo = ref.read(inventoryRepositoryProvider);
    final supplier = bill.supplierName;
    final note = [
      'Bill',
      if (bill.invoiceNumber.isNotEmpty) 'No. ${bill.invoiceNumber}',
      if (supplier.isNotEmpty) '· $supplier',
    ].join(' ');
    var added = 0;
    final failed = <String>[];
    for (final line in lines) {
      final it = line.item;
      try {
        final String id;
        final m = line.match;
        if (m != null) {
          id = m.id;
          // Keep the batch that expires first while older stock is left.
          final newBatch =
              m.currentStock <= 0 ||
              m.expiryDate == null ||
              (it.expiryDate != null && it.expiryDate!.isBefore(m.expiryDate!));
          final updates = <String, dynamic>{
            if (newBatch && it.batchNumber.isNotEmpty)
              'batchNumber': it.batchNumber,
            if (newBatch && it.expiryDate != null) 'expiryDate': it.expiryDate,
            if (it.unitPrice != null) 'unitPrice': it.unitPrice,
            if (supplier.isNotEmpty) 'supplierName': supplier,
          };
          if (updates.isNotEmpty) await repo.updateMedicine(id, updates);
          if (it.stockAdded > 0) {
            await repo.recordTransaction(
              medicineId: id,
              type: StockTransactionType.restock,
              quantity: it.stockAdded,
              note: note,
            );
          }
        } else {
          final now = DateTime.now();
          id = await repo.createMedicine(
            MedicineModel(
              id: '',
              name: it.name,
              category: it.category,
              unit: it.unit,
              currentStock: it.stockAdded,
              unitPrice: it.unitPrice,
              supplierName: supplier.isEmpty ? null : supplier,
              batchNumber: it.batchNumber.isEmpty ? null : it.batchNumber,
              expiryDate: it.expiryDate,
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
        // The bill page the line is on stays with the item as its receipt.
        unawaited(
          InventoryReceiptSync.enqueueReceiptBytes(
            medicineId: id,
            bytes: widget.pages[it.page - 1].jpeg,
            replacePath: m?.receiptStoragePath,
          ),
        );
        added++;
      } catch (e) {
        debugPrint('[ScanBill] ${it.name}: $e');
        failed.add(it.name);
      }
    }
    if (!mounted) return;
    if (added == 0) {
      setState(() => _saving = false);
      mobileSay(context, "Couldn't add the items. Try again.");
      return;
    }
    Navigator.of(context).pop();
    if (!root.mounted) return;
    mobileSay(
      root,
      [
        'Added $added ${added == 1 ? 'item' : 'items'} to inventory.',
        if (failed.isNotEmpty) "Couldn't add ${failed.join(', ')}.",
      ].join(' '),
    );
    if (_expense && bill.total != null) {
      // The person confirms the expense in its own form.
      await showDesktopAddTransactionDialog(
        root,
        initialKind: TransactionKind.expense,
        initialAmount: bill.total,
        initialDescription: [
          'Supplier bill',
          if (bill.invoiceNumber.isNotEmpty) bill.invoiceNumber,
        ].join(' '),
        initialPayer: supplier.isEmpty ? null : supplier,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bill = _bill;
    final error = _error;
    final c = context.cru;
    final count = _lines.where((l) => l.include).length;
    return ScanScaffold(
      title: 'Supplier bill',
      subtitle: bill?.supplierName.isNotEmpty == true
          ? bill!.supplierName
          : null,
      bottom: bill == null
          ? null
          : MobilePrimaryButton(
              label: _saving
                  ? 'Adding…'
                  : 'Add $count ${count == 1 ? 'item' : 'items'} to inventory',
              icon: CruIcons.box,
              onPressed: _saving || count == 0 ? null : _save,
            ),
      children: [
        if (error != null)
          ScanProblem(message: error, onRetry: _read)
        else if (bill == null)
          ScanReading(page: widget.pages.first, label: 'Reading the bill…')
        else ...[
          ScanAiNote(
            text:
                'Read by AI from the bill. Check quantities, batches and '
                'expiry dates before adding.',
            unclear: bill.unclear,
          ),
          MobileRowGroup(
            indent: CruSpace.s16,
            children: [
              MobileRow(
                title: bill.supplierName.isEmpty
                    ? 'Supplier not printed'
                    : bill.supplierName,
                subtitle: [
                  if (bill.invoiceNumber.isNotEmpty)
                    'No. ${bill.invoiceNumber}',
                  if (bill.invoiceDate != null)
                    DateFormat('d MMM yyyy').format(bill.invoiceDate!),
                ].join(' · '),
                trailing: bill.total == null
                    ? null
                    : Text(
                        _money.format(bill.total),
                        style: MobileType.row.tabular
                            .copyWith(fontWeight: FontWeight.w600)
                            .tint(c.label),
                      ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),
          MobileRowGroup(
            title: '${_lines.length} ${_lines.length == 1 ? 'item' : 'items'}',
            indent: 62,
            children: [
              for (final line in _lines)
                MobileRow(
                  leading: _Tick(
                    on: line.include,
                    onTap: _saving
                        ? null
                        : () => setState(() => line.include = !line.include),
                  ),
                  title: line.item.name,
                  titleStyle: MobileType.row.tint(
                    line.include ? c.label : c.label3,
                  ),
                  subtitle: _details(line.item),
                  trailing: MobilePill(
                    line.match == null ? 'New' : 'Restock',
                    tone: line.match == null
                        ? MobileTone.indigo
                        : MobileTone.sky,
                  ),
                  onTap: _saving ? null : () => _edit(line),
                ),
            ],
          ),
          if (widget.revenue && bill.total != null) ...[
            const SizedBox(height: CruSpace.s12),
            MobileRowGroup(
              indent: CruSpace.s16,
              children: [
                MobileRow(
                  title: 'Also record as an expense',
                  subtitle: '${_money.format(bill.total)} paid to the supplier',
                  trailing: Switch.adaptive(
                    value: _expense,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _expense = v),
                  ),
                  onTap: _saving
                      ? null
                      : () => setState(() => _expense = !_expense),
                ),
              ],
            ),
          ],
          const SizedBox(height: CruSpace.s16),
          const MobileGroupTitle('Scanned bill', onBackground: true),
          const SizedBox(height: CruSpace.s8),
          ScanPagesStrip(pages: widget.pages),
        ],
      ],
    );
  }
}

/// Whether a line goes into stock: a filled check, or an empty ring.
class _Tick extends StatelessWidget {
  const _Tick({required this.on, required this.onTap});

  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(CruSpace.s4),
        child: AnimatedContainer(
          duration: CruMotion.fast,
          curve: CruMotion.curve,
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? MobileBlue.neon : Colors.transparent,
            border: on ? null : Border.all(color: c.label3, width: 1.5),
          ),
          child: on
              ? const CruIcon(
                  CruIcons.check,
                  size: 15,
                  strokeWidth: 2.4,
                  color: Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}

/// One bill line's details and what it restocks, corrected by hand.
class _LineEditor extends StatefulWidget {
  const _LineEditor({required this.line, required this.stock});

  final _Line line;
  final List<MedicineModel> stock;

  @override
  State<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<_LineEditor> {
  BillItem get _it => widget.line.item;

  late final _name = TextEditingController(text: _it.name);
  late final _qty = TextEditingController(text: '${_it.quantity}');
  late final _free = TextEditingController(
    text: _it.freeQuantity > 0 ? '${_it.freeQuantity}' : '',
  );
  late final _unit = TextEditingController(text: _it.unit);
  late final _category = TextEditingController(text: _it.category);
  late final _batch = TextEditingController(text: _it.batchNumber);
  late final _expiryText = TextEditingController(
    text: _it.expiryDate == null ? '' : _expiry.format(_it.expiryDate!),
  );
  late final _price = TextEditingController(
    text: _it.unitPrice?.toStringAsFixed(2) ?? '',
  );
  late MedicineModel? _match = widget.line.match;
  late final List<MedicineModel> _candidates = {
    ?widget.line.match,
    ...StockMatching.closest(_it.name, widget.stock),
  }.toList();

  @override
  void dispose() {
    for (final c in [
      _name,
      _qty,
      _free,
      _unit,
      _category,
      _batch,
      _expiryText,
      _price,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// "03/2027" or "3/27": the last day of that month.
  static DateTime? _parseExpiry(String text) {
    final m = RegExp(r'^\s*(\d{1,2})\s*[/\-.]\s*(\d{2}|\d{4})\s*$')
        .firstMatch(text);
    if (m == null) return null;
    final month = int.parse(m[1]!);
    var year = int.parse(m[2]!);
    if (year < 100) year += 2000;
    if (month < 1 || month > 12) return null;
    return DateTime(year, month + 1, 0);
  }

  void _done() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    _it
      ..name = name
      ..quantity = int.tryParse(_qty.text.trim()) ?? _it.quantity
      ..freeQuantity = int.tryParse(_free.text.trim()) ?? 0
      ..unit = _unit.text.trim().isEmpty ? _it.unit : _unit.text.trim()
      ..category = _category.text.trim()
      ..batchNumber = _batch.text.trim()
      ..expiryDate = _expiryText.text.trim().isEmpty
          ? null
          : (_parseExpiry(_expiryText.text) ?? _it.expiryDate)
      ..unitPrice = double.tryParse(_price.text.trim());
    widget.line.match = _match;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    Widget pair(Widget a, Widget b) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: CruSpace.s10),
        Expanded(child: b),
      ],
    );
    const gap = SizedBox(height: CruSpace.s10);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(
            CruSpace.s8,
            0,
            CruSpace.s8,
            CruSpace.s8,
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          decoration: ShapeDecoration(color: c.canvas, shape: cruShape(28)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: CruSpace.s8),
              Center(
                child: Container(
                  width: 36,
                  height: 5,
                  decoration: ShapeDecoration(
                    color: c.track,
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  children: [
                    Text('Bill line', style: MobileType.headline.tint(c.label)),
                    const SizedBox(height: CruSpace.s12),
                    ScanTextField(label: 'Name', controller: _name),
                    gap,
                    pair(
                      ScanTextField(
                        label: 'Quantity',
                        controller: _qty,
                        keyboardType: TextInputType.number,
                      ),
                      ScanTextField(
                        label: 'Free',
                        controller: _free,
                        keyboardType: TextInputType.number,
                        hint: '0',
                      ),
                    ),
                    gap,
                    pair(
                      ScanTextField(label: 'Unit', controller: _unit),
                      ScanTextField(label: 'Category', controller: _category),
                    ),
                    gap,
                    pair(
                      ScanTextField(label: 'Batch', controller: _batch),
                      ScanTextField(
                        label: 'Expiry (MM/YYYY)',
                        controller: _expiryText,
                        keyboardType: TextInputType.datetime,
                      ),
                    ),
                    gap,
                    ScanTextField(
                      label: 'Rate per unit (₹, before tax)',
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: CruSpace.s16),
                    Text(
                      'Adds to',
                      style: MobileType.caption.tint(c.label3),
                    ),
                    const SizedBox(height: CruSpace.s6),
                    MobileCard(
                      child: Column(
                        children: [
                          for (final m in _candidates) ...[
                            MobileRow(
                              title: m.name,
                              subtitle:
                                  '${m.currentStock} ${m.unit} in stock',
                              trailing: _match?.id == m.id
                                  ? const CruIcon(
                                      CruIcons.check,
                                      size: 18,
                                      color: MobileBlue.neon,
                                    )
                                  : null,
                              onTap: () => setState(() => _match = m),
                            ),
                            const CruSeparator(indent: CruSpace.s16),
                          ],
                          MobileRow(
                            title: 'A new item',
                            subtitle: 'Not stocked yet',
                            trailing: _match == null
                                ? const CruIcon(
                                    CruIcons.check,
                                    size: 18,
                                    color: MobileBlue.neon,
                                  )
                                : null,
                            onTap: () => setState(() => _match = null),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: MobilePrimaryButton(label: 'Done', onPressed: _done),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
